import Foundation
import GRDB
import WicketKit

public enum WicketStoreError: Error, Equatable, Sendable {
    case invalidName
    case invalidTimeSlot
    case invalidTeams
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
public struct WicketStore: Sendable {
    public let db: any DatabaseWriter

    public init(db: any DatabaseWriter) {
        self.db = db
    }

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

        migrator.registerMigration("v2") { db in
            try db.create(table: "grounds") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("name", .text).notNull()
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.check(sql: "length(trim(name)) > 0")
            }

            try db.create(table: "fixtures") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("league_id", .text)
                    .references("leagues", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("home_team_id", .text).notNull()
                    .references("teams", onDelete: .cascade)
                table.column("away_team_id", .text).notNull()
                    .references("teams", onDelete: .cascade)
                table.column("ground_id", .text).notNull()
                    .references("grounds", onDelete: .cascade)
                table.column("starts_at_ms", .integer).notNull()
                table.column("ends_at_ms", .integer).notNull()
                table.column("reminder_minutes", .integer).notNull().defaults(to: 0)
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.check(sql: "length(trim(name)) > 0")
                table.check(sql: "starts_at_ms < ends_at_ms")
                table.check(sql: "home_team_id != away_team_id")
            }
            try db.create(index: "fixtures_on_league_id", on: "fixtures", columns: ["league_id"])
            try db.create(index: "fixtures_on_ground_id", on: "fixtures", columns: ["ground_id"])
            try db.create(index: "fixtures_on_schedule", on: "fixtures", columns: ["starts_at_ms", "ends_at_ms"])

            try db.create(table: "fixture_players") { table in
                table.column("fixture_id", .text).notNull()
                    .references("fixtures", onDelete: .cascade)
                table.column("player_id", .text).notNull()
                    .references("players", onDelete: .cascade)
                table.primaryKey(["fixture_id", "player_id"])
            }
            try db.create(index: "fixture_players_on_player_id", on: "fixture_players", columns: ["player_id"])
        }
        return migrator
    }

    public static func removeV1Schema(_ db: Database) throws {
        try db.drop(table: "players")
        try db.drop(table: "teams")
        try db.drop(table: "leagues")
    }

    public static func removeV2Schema(_ db: Database) throws {
        try db.drop(table: "fixture_players")
        try db.drop(table: "fixtures")
        try db.drop(table: "grounds")
    }

    public static func open(at url: URL) throws -> WicketStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let database = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(database)
        return WicketStore(db: database)
    }

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

    // MARK: - Grounds

    @discardableResult
    public func createGround(name: String) throws -> GroundRecord {
        let name = try normalized(name)
        let now = Date().truncatedToMilliseconds
        let record = GroundRecord(
            id: GroundID(UUID().uuidString.lowercased()),
            name: name,
            createdAt: now,
            updatedAt: now
        )
        try db.write { database in
            try database.execute(
                sql: """
                INSERT INTO grounds (id, name, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    record.id.rawValue,
                    record.name,
                    record.createdAt.millisecondsSince1970,
                    record.updatedAt.millisecondsSince1970,
                ]
            )
        }
        return record
    }

    @discardableResult
    public func updateGround(id: GroundID, name: String) throws -> GroundRecord {
        let name = try normalized(name)
        return try db.write { database in
            guard try ground(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE grounds SET name = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [name, Date().millisecondsSince1970, id.rawValue]
            )
            guard let updated = try ground(id: id, in: database) else {
                throw WicketStoreError.recordNotFound
            }
            return updated
        }
    }

    public func listGrounds() throws -> [GroundRecord] {
        try db.read { database in
            let rows = try Row.fetchAll(database, sql: "SELECT * FROM grounds ORDER BY name COLLATE NOCASE, id")
            return try rows.map(decodeGround)
        }
    }

    public func ground(id: GroundID) throws -> GroundRecord? {
        try db.read { database in try ground(id: id, in: database) }
    }

    // MARK: - Fixtures

    @discardableResult
    public func createFixture(
        leagueID: LeagueID?,
        name: String,
        homeTeamID: TeamID,
        awayTeamID: TeamID,
        groundID: GroundID,
        participatingPlayerIDs: Set<PlayerID>,
        startsAt: Date,
        endsAt: Date,
        reminder: FixtureReminder
    ) throws -> FixtureRecord {
        let name = try normalized(name)
        guard startsAt < endsAt else { throw WicketStoreError.invalidTimeSlot }
        guard homeTeamID != awayTeamID else { throw WicketStoreError.invalidTeams }
        let now = Date().truncatedToMilliseconds

        let record = FixtureRecord(
            id: FixtureID(UUID().uuidString.lowercased()),
            leagueID: leagueID,
            name: name,
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
            groundID: groundID,
            participatingPlayerIDs: participatingPlayerIDs,
            startsAt: startsAt.truncatedToMilliseconds,
            endsAt: endsAt.truncatedToMilliseconds,
            reminder: reminder,
            createdAt: now,
            updatedAt: now
        )

        try db.write { database in
            if let leagueID {
                guard try league(id: leagueID, in: database) != nil else {
                    throw WicketStoreError.parentNotFound
                }
            }
            guard try team(id: homeTeamID, in: database) != nil,
                  try team(id: awayTeamID, in: database) != nil,
                  try ground(id: groundID, in: database) != nil else {
                throw WicketStoreError.parentNotFound
            }

            try database.execute(
                sql: """
                INSERT INTO fixtures (id, league_id, name, home_team_id, away_team_id, ground_id, starts_at_ms, ends_at_ms, reminder_minutes, created_at_ms, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.rawValue,
                    record.leagueID?.rawValue,
                    record.name,
                    record.homeTeamID.rawValue,
                    record.awayTeamID.rawValue,
                    record.groundID.rawValue,
                    record.startsAt.millisecondsSince1970,
                    record.endsAt.millisecondsSince1970,
                    record.reminder.rawValue,
                    record.createdAt.millisecondsSince1970,
                    record.updatedAt.millisecondsSince1970,
                ]
            )

            for playerID in participatingPlayerIDs {
                try database.execute(
                    sql: "INSERT INTO fixture_players (fixture_id, player_id) VALUES (?, ?)",
                    arguments: [record.id.rawValue, playerID.rawValue]
                )
            }
        }
        return record
    }

    @discardableResult
    public func updateFixture(
        id: FixtureID,
        leagueID: LeagueID?,
        name: String,
        homeTeamID: TeamID,
        awayTeamID: TeamID,
        groundID: GroundID,
        participatingPlayerIDs: Set<PlayerID>,
        startsAt: Date,
        endsAt: Date,
        reminder: FixtureReminder
    ) throws -> FixtureRecord {
        let name = try normalized(name)
        guard startsAt < endsAt else { throw WicketStoreError.invalidTimeSlot }
        guard homeTeamID != awayTeamID else { throw WicketStoreError.invalidTeams }

        return try db.write { database in
            guard try fixture(id: id, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            if let leagueID {
                guard try league(id: leagueID, in: database) != nil else {
                    throw WicketStoreError.parentNotFound
                }
            }
            guard try team(id: homeTeamID, in: database) != nil,
                  try team(id: awayTeamID, in: database) != nil,
                  try ground(id: groundID, in: database) != nil else {
                throw WicketStoreError.parentNotFound
            }

            try database.execute(
                sql: """
                UPDATE fixtures
                SET league_id = ?, name = ?, home_team_id = ?, away_team_id = ?, ground_id = ?, starts_at_ms = ?, ends_at_ms = ?, reminder_minutes = ?, updated_at_ms = ?
                WHERE id = ?
                """,
                arguments: [
                    leagueID?.rawValue,
                    name,
                    homeTeamID.rawValue,
                    awayTeamID.rawValue,
                    groundID.rawValue,
                    startsAt.millisecondsSince1970,
                    endsAt.millisecondsSince1970,
                    reminder.rawValue,
                    Date().millisecondsSince1970,
                    id.rawValue,
                ]
            )

            try database.execute(sql: "DELETE FROM fixture_players WHERE fixture_id = ?", arguments: [id.rawValue])
            for playerID in participatingPlayerIDs {
                try database.execute(
                    sql: "INSERT INTO fixture_players (fixture_id, player_id) VALUES (?, ?)",
                    arguments: [id.rawValue, playerID.rawValue]
                )
            }
            return try requiredFixture(id: id, in: database)
        }
    }

    public func deleteFixture(id: FixtureID) throws {
        try db.write { database in
            try database.execute(sql: "DELETE FROM fixtures WHERE id = ?", arguments: [id.rawValue])
        }
    }

    public func listFixtures() throws -> [FixtureRecord] {
        try db.read { database in
            let rows = try Row.fetchAll(database, sql: "SELECT * FROM fixtures ORDER BY starts_at_ms ASC, id ASC")
            return try rows.map { try decodeFixture($0, in: database) }
        }
    }

    public func listUpcomingFixtures(after threshold: Date = Date()) throws -> [FixtureRecord] {
        try db.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM fixtures WHERE starts_at_ms >= ? ORDER BY starts_at_ms ASC, id ASC",
                arguments: [threshold.millisecondsSince1970]
            )
            return try rows.map { try decodeFixture($0, in: database) }
        }
    }

    public func fixture(id: FixtureID) throws -> FixtureRecord? {
        try db.read { database in try fixture(id: id, in: database) }
    }

    public func conflicts(for candidate: FixtureRecord) throws -> [FixtureConflict] {
        let all = try listFixtures()
        return FixtureConflictDetector.conflicts(for: candidate, among: all)
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

    private func ground(id: GroundID, in database: Database) throws -> GroundRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM grounds WHERE id = ?",
            arguments: [id.rawValue]
        ) else { return nil }
        return try decodeGround(row)
    }

    private func fixture(id: FixtureID, in database: Database) throws -> FixtureRecord? {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM fixtures WHERE id = ?",
            arguments: [id.rawValue]
        ) else { return nil }
        return try decodeFixture(row, in: database)
    }

    private func requiredFixture(id: FixtureID, in database: Database) throws -> FixtureRecord {
        guard let record = try fixture(id: id, in: database) else {
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

    private func decodeGround(_ row: Row) throws -> GroundRecord {
        GroundRecord(
            id: GroundID(row["id"]),
            name: row["name"],
            createdAt: Date(millisecondsSince1970: row["created_at_ms"]),
            updatedAt: Date(millisecondsSince1970: row["updated_at_ms"])
        )
    }

    private func decodeFixture(_ row: Row, in database: Database) throws -> FixtureRecord {
        let fixtureID = FixtureID(row["id"])
        let leagueIDString: String? = row["league_id"]
        let playerRows = try Row.fetchAll(
            database,
            sql: "SELECT player_id FROM fixture_players WHERE fixture_id = ?",
            arguments: [fixtureID.rawValue]
        )
        let playerIDs = Set(playerRows.map { PlayerID($0["player_id"]) })
        let reminderMinutes: Int = row["reminder_minutes"]
        let reminder = FixtureReminder(rawValue: reminderMinutes) ?? .none

        return FixtureRecord(
            id: fixtureID,
            leagueID: leagueIDString.map { LeagueID($0) },
            name: row["name"],
            homeTeamID: TeamID(row["home_team_id"]),
            awayTeamID: TeamID(row["away_team_id"]),
            groundID: GroundID(row["ground_id"]),
            participatingPlayerIDs: playerIDs,
            startsAt: Date(millisecondsSince1970: row["starts_at_ms"]),
            endsAt: Date(millisecondsSince1970: row["ends_at_ms"]),
            reminder: reminder,
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
