import Foundation
import GRDB
import WicketKit

public enum WicketStoreError: Error, Equatable, Sendable {
    case invalidName
    case parentNotFound
    case recordNotFound
    case confirmationStale
}

/// Dates are persisted as integer epoch-milliseconds so that a record written
/// and read back compares exactly (no sub-millisecond drift between the value
/// returned on create and the value a later fetch returns).
extension Date {
    var millisecondsSince1970: Int64 { Int64((timeIntervalSince1970 * 1000).rounded(.down)) }

    init(millisecondsSince1970 milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    var truncatedToMilliseconds: Date { Date(millisecondsSince1970: millisecondsSince1970) }
}

/// Local-only GRDB/SQLite persistence for Wicket Tally.
///
/// Schema v1 stores leagues/tournaments, teams, and players. Deletion uses
/// SQLite cascades only after the caller supplies an exact, freshly computed
/// cascade preview, so child records are never destroyed silently.
public struct WicketStore: Sendable {
    public let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

    /// The first production schema. Migration identifiers are immutable once
    /// released because checked-in fixture databases depend on them.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "leagues") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("name", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("is_archived", .boolean).notNull().defaults(to: false)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.check(sql: "length(trim(name)) > 0")
                table.check(sql: "kind IN ('league', 'tournament')")
            }

            try db.create(table: "teams") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("league_id", .text).notNull()
                    .references("leagues", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("colour", .text).notNull()
                table.column("is_archived", .boolean).notNull().defaults(to: false)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.check(sql: "length(trim(name)) > 0")
                let colours = TeamKitColour.allCases
                    .map { "'\($0.rawValue)'" }
                    .joined(separator: ", ")
                table.check(sql: "colour IN (\(colours))")
            }
            try db.create(index: "teams_on_league_id", on: "teams", columns: ["league_id"])

            try db.create(table: "players") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("team_id", .text).notNull()
                    .references("teams", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("role", .text).notNull()
                table.column("is_archived", .boolean).notNull().defaults(to: false)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.check(sql: "length(trim(name)) > 0")
                let roles = PlayerRole.allCases
                    .map { "'\($0.rawValue)'" }
                    .joined(separator: ", ")
                table.check(sql: "role IN (\(roles))")
            }
            try db.create(index: "players_on_team_id", on: "players", columns: ["team_id"])
        }
        return migrator
    }

    /// Reverse schema-v1 in foreign-key order. Production startup migrates
    /// forward only; this function exists to prove reversible schema design in
    /// migration tests and fixture maintenance tooling.
    public static func removeV1Schema(_ db: Database) throws {
        try db.drop(table: "players")
        try db.drop(table: "teams")
        try db.drop(table: "leagues")
    }

    /// Opens (creating if needed) and migrates the on-disk store at `url`.
    public static func open(at url: URL) throws -> WicketStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let database = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(database)
        return WicketStore(db: database)
    }

    /// A migrated in-memory store for previews and unit tests.
    public static func inMemory() throws -> WicketStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let database = try DatabaseQueue(configuration: config)
        try migrator.migrate(database)
        return WicketStore(db: database)
    }

    // MARK: - Leagues / tournaments

    @discardableResult
    public func createLeague(name: String, kind: LeagueKind) throws -> LeagueRecord {
        let name = try normalized(name)
        let now = Date().truncatedToMilliseconds
        let record = LeagueRecord(
            id: LeagueID(UUID().uuidString.lowercased()),
            name: name,
            kind: kind,
            createdAt: now,
            updatedAt: now
        )
        try db.write { database in
            try database.execute(
                sql: """
                INSERT INTO leagues (id, name, kind, is_archived, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.rawValue,
                    record.name,
                    record.kind.rawValue,
                    record.isArchived,
                    record.createdAt.millisecondsSince1970,
                    record.updatedAt.millisecondsSince1970,
                ]
            )
        }
        return record
    }

    @discardableResult
    public func updateLeague(id: LeagueID, name: String, kind: LeagueKind) throws -> LeagueRecord {
        let name = try normalized(name)
        return try db.write { database in
            guard try league(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE leagues SET name = ?, kind = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [name, kind.rawValue, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredLeague(id: id, in: database)
        }
    }

    @discardableResult
    public func setLeagueArchived(id: LeagueID, archived: Bool) throws -> LeagueRecord {
        try db.write { database in
            guard try league(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE leagues SET is_archived = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [archived, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredLeague(id: id, in: database)
        }
    }

    public func listLeagues(includeArchived: Bool = false) throws -> [LeagueRecord] {
        try db.read { database in
            let filter = includeArchived ? "" : "WHERE is_archived = 0"
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM leagues \(filter) ORDER BY name COLLATE NOCASE, id"
            )
            return try rows.map(decodeLeague)
        }
    }

    public func league(id: LeagueID) throws -> LeagueRecord? {
        try db.read { database in try league(id: id, in: database) }
    }

    public func previewLeagueDeletion(id: LeagueID) throws -> LeagueDeletionPreview {
        try db.read { database in try leagueDeletionPreview(id: id, in: database) }
    }

    public func deleteLeague(id: LeagueID, confirming preview: LeagueDeletionPreview) throws {
        try db.write { database in
            let current = try leagueDeletionPreview(id: id, in: database)
            guard current == preview else { throw WicketStoreError.confirmationStale }
            try database.execute(sql: "DELETE FROM leagues WHERE id = ?", arguments: [id.rawValue])
        }
    }

    // MARK: - Teams

    @discardableResult
    public func createTeam(leagueID: LeagueID, name: String, colour: TeamKitColour) throws -> TeamRecord {
        let name = try normalized(name)
        let now = Date().truncatedToMilliseconds
        let record = TeamRecord(
            id: TeamID(UUID().uuidString.lowercased()),
            leagueID: leagueID,
            name: name,
            colour: colour,
            createdAt: now,
            updatedAt: now
        )
        try db.write { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.parentNotFound
            }
            try database.execute(
                sql: """
                INSERT INTO teams (id, league_id, name, colour, is_archived, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.rawValue,
                    record.leagueID.rawValue,
                    record.name,
                    record.colour.rawValue,
                    record.isArchived,
                    record.createdAt.millisecondsSince1970,
                    record.updatedAt.millisecondsSince1970,
                ]
            )
        }
        return record
    }

    @discardableResult
    public func updateTeam(id: TeamID, name: String, colour: TeamKitColour) throws -> TeamRecord {
        let name = try normalized(name)
        return try db.write { database in
            guard try team(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE teams SET name = ?, colour = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [name, colour.rawValue, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredTeam(id: id, in: database)
        }
    }

    @discardableResult
    public func setTeamArchived(id: TeamID, archived: Bool) throws -> TeamRecord {
        try db.write { database in
            guard try team(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE teams SET is_archived = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [archived, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredTeam(id: id, in: database)
        }
    }

    public func listTeams(leagueID: LeagueID, includeArchived: Bool = false) throws -> [TeamRecord] {
        try db.read { database in
            let archivedClause = includeArchived ? "" : "AND is_archived = 0"
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM teams
                WHERE league_id = ? \(archivedClause)
                ORDER BY name COLLATE NOCASE, id
                """,
                arguments: [leagueID.rawValue]
            )
            return try rows.map(decodeTeam)
        }
    }

    public func team(id: TeamID) throws -> TeamRecord? {
        try db.read { database in try team(id: id, in: database) }
    }

    public func previewTeamDeletion(id: TeamID) throws -> TeamDeletionPreview {
        try db.read { database in try teamDeletionPreview(id: id, in: database) }
    }

    public func deleteTeam(id: TeamID, confirming preview: TeamDeletionPreview) throws {
        try db.write { database in
            let current = try teamDeletionPreview(id: id, in: database)
            guard current == preview else { throw WicketStoreError.confirmationStale }
            try database.execute(sql: "DELETE FROM teams WHERE id = ?", arguments: [id.rawValue])
        }
    }

    // MARK: - Players

    @discardableResult
    public func createPlayer(teamID: TeamID, name: String, role: PlayerRole) throws -> PlayerRecord {
        let name = try normalized(name)
        let now = Date().truncatedToMilliseconds
        let record = PlayerRecord(
            id: PlayerID(UUID().uuidString.lowercased()),
            teamID: teamID,
            name: name,
            role: role,
            createdAt: now,
            updatedAt: now
        )
        try db.write { database in
            guard try team(id: teamID, in: database) != nil else {
                throw WicketStoreError.parentNotFound
            }
            try database.execute(
                sql: """
                INSERT INTO players (id, team_id, name, role, is_archived, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.rawValue,
                    record.teamID.rawValue,
                    record.name,
                    record.role.rawValue,
                    record.isArchived,
                    record.createdAt.millisecondsSince1970,
                    record.updatedAt.millisecondsSince1970,
                ]
            )
        }
        return record
    }

    @discardableResult
    public func updatePlayer(id: PlayerID, name: String, role: PlayerRole) throws -> PlayerRecord {
        let name = try normalized(name)
        return try db.write { database in
            guard try player(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE players SET name = ?, role = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [name, role.rawValue, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredPlayer(id: id, in: database)
        }
    }

    @discardableResult
    public func setPlayerArchived(id: PlayerID, archived: Bool) throws -> PlayerRecord {
        try db.write { database in
            guard try player(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE players SET is_archived = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [archived, Date().millisecondsSince1970, id.rawValue]
            )
            return try requiredPlayer(id: id, in: database)
        }
    }

    public func listPlayers(teamID: TeamID, includeArchived: Bool = false) throws -> [PlayerRecord] {
        try db.read { database in
            let archivedClause = includeArchived ? "" : "AND is_archived = 0"
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM players
                WHERE team_id = ? \(archivedClause)
                ORDER BY name COLLATE NOCASE, id
                """,
                arguments: [teamID.rawValue]
            )
            return try rows.map(decodePlayer)
        }
    }

    public func player(id: PlayerID) throws -> PlayerRecord? {
        try db.read { database in try player(id: id, in: database) }
    }

    public func previewPlayerDeletion(id: PlayerID) throws -> PlayerDeletionPreview {
        try db.read { database in
            guard let player = try player(id: id, in: database) else {
                throw WicketStoreError.recordNotFound
            }
            return PlayerDeletionPreview(playerID: player.id, playerName: player.name)
        }
    }

    public func deletePlayer(id: PlayerID, confirming preview: PlayerDeletionPreview) throws {
        try db.write { database in
            guard let player = try player(id: id, in: database) else {
                throw WicketStoreError.recordNotFound
            }
            let current = PlayerDeletionPreview(playerID: player.id, playerName: player.name)
            guard current == preview else { throw WicketStoreError.confirmationStale }
            try database.execute(sql: "DELETE FROM players WHERE id = ?", arguments: [id.rawValue])
        }
    }

    // MARK: - Private mapping and validation

    private func normalized(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WicketStoreError.invalidName }
        return value
    }

    private func league(id: LeagueID, in database: Database) throws -> LeagueRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM leagues WHERE id = ?",
            arguments: [id.rawValue]
        ) else { return nil }
        return try decodeLeague(row)
    }

    private func requiredLeague(id: LeagueID, in database: Database) throws -> LeagueRecord {
        guard let record = try league(id: id, in: database) else {
            throw WicketStoreError.recordNotFound
        }
        return record
    }

    private func team(id: TeamID, in database: Database) throws -> TeamRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM teams WHERE id = ?",
            arguments: [id.rawValue]
        ) else { return nil }
        return try decodeTeam(row)
    }

    private func requiredTeam(id: TeamID, in database: Database) throws -> TeamRecord {
        guard let record = try team(id: id, in: database) else {
            throw WicketStoreError.recordNotFound
        }
        return record
    }

    private func player(id: PlayerID, in database: Database) throws -> PlayerRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM players WHERE id = ?",
            arguments: [id.rawValue]
        ) else { return nil }
        return try decodePlayer(row)
    }

    private func requiredPlayer(id: PlayerID, in database: Database) throws -> PlayerRecord {
        guard let record = try player(id: id, in: database) else {
            throw WicketStoreError.recordNotFound
        }
        return record
    }

    private func decodeLeague(_ row: Row) throws -> LeagueRecord {
        guard let kind = LeagueKind(rawValue: row["kind"]) else {
            throw WicketStoreError.recordNotFound
        }
        return LeagueRecord(
            id: LeagueID(row["id"]),
            name: row["name"],
            kind: kind,
            isArchived: row["is_archived"],
            createdAt: Date(millisecondsSince1970: row["created_at_ms"]),
            updatedAt: Date(millisecondsSince1970: row["updated_at_ms"])
        )
    }

    private func decodeTeam(_ row: Row) throws -> TeamRecord {
        guard let colour = TeamKitColour(rawValue: row["colour"]) else {
            throw WicketStoreError.recordNotFound
        }
        return TeamRecord(
            id: TeamID(row["id"]),
            leagueID: LeagueID(row["league_id"]),
            name: row["name"],
            colour: colour,
            isArchived: row["is_archived"],
            createdAt: Date(millisecondsSince1970: row["created_at_ms"]),
            updatedAt: Date(millisecondsSince1970: row["updated_at_ms"])
        )
    }

    private func decodePlayer(_ row: Row) throws -> PlayerRecord {
        guard let role = PlayerRole(rawValue: row["role"]) else {
            throw WicketStoreError.recordNotFound
        }
        return PlayerRecord(
            id: PlayerID(row["id"]),
            teamID: TeamID(row["team_id"]),
            name: row["name"],
            role: role,
            isArchived: row["is_archived"],
            createdAt: Date(millisecondsSince1970: row["created_at_ms"]),
            updatedAt: Date(millisecondsSince1970: row["updated_at_ms"])
        )
    }

    private func leagueDeletionPreview(id: LeagueID, in database: Database) throws -> LeagueDeletionPreview {
        guard let league = try league(id: id, in: database) else {
            throw WicketStoreError.recordNotFound
        }
        let teamCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM teams WHERE league_id = ?",
            arguments: [id.rawValue]
        ) ?? 0
        let playerCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM players
            JOIN teams ON teams.id = players.team_id
            WHERE teams.league_id = ?
            """,
            arguments: [id.rawValue]
        ) ?? 0
        return LeagueDeletionPreview(
            leagueID: id,
            leagueName: league.name,
            teamCount: teamCount,
            playerCount: playerCount
        )
    }

    private func teamDeletionPreview(id: TeamID, in database: Database) throws -> TeamDeletionPreview {
        guard let team = try team(id: id, in: database) else {
            throw WicketStoreError.recordNotFound
        }
        let playerCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM players WHERE team_id = ?",
            arguments: [id.rawValue]
        ) ?? 0
        return TeamDeletionPreview(teamID: id, teamName: team.name, playerCount: playerCount)
    }
}
