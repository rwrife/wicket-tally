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
    case scoringConflict
    /// A stored configuration blob could not be decoded. Never swallowed: a
    /// corrupt league preset surfaces instead of silently reverting to defaults.
    case malformedConfiguration
}

public struct PersistedScoringSession: Sendable, Equatable {
    public let rules: MatchRules
    public let ledger: MatchLedger

    public init(rules: MatchRules, ledger: MatchLedger) {
        self.rules = rules
        self.ledger = ledger
    }
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
        migrator.registerMigration("v3") { db in
            try db.create(table: "match_rules") { table in
                table.column("fixture_id", .text).notNull().primaryKey()
                    .references("fixtures", onDelete: .cascade)
                table.column("overs_per_innings", .integer).notNull()
                table.column("balls_per_over", .integer).notNull()
                table.column("max_wickets", .integer).notNull()
            }

            try db.create(table: "match_events") { table in
                table.column("id", .text).notNull().primaryKey()
                table.column("fixture_id", .text).notNull()
                    .references("fixtures", onDelete: .cascade)
                table.column("sequence", .integer).notNull()
                table.column("payload", .blob).notNull()
                table.uniqueKey(["fixture_id", "sequence"])
            }
            try db.create(index: "match_events_on_fixture", on: "match_events", columns: ["fixture_id", "sequence"])
        }
        migrator.registerMigration("v4") { db in
            try db.alter(table: "match_rules") { table in
                table.add(column: "rules_payload", .blob)
            }
        }
        migrator.registerMigration("v5") { db in
            try db.alter(table: "leagues") { table in
                table.add(column: "rule_preset_json", .text)
            }
        }
        migrator.registerMigration("v6") { db in
            // Append-only audit: every override a user records is kept, and the
            // standings projection reads only the latest row per team.
            try db.create(table: "standings_points_overrides") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("league_id", .text).notNull()
                    .references("leagues", onDelete: .cascade)
                table.column("team_id", .text).notNull()
                    .references("teams", onDelete: .cascade)
                table.column("points", .integer).notNull()
                table.column("reason", .text).notNull()
                table.column("provenance", .text).notNull()
                table.column("recorded_at_ms", .integer).notNull()
            }
            try db.create(
                index: "standings_points_overrides_on_league",
                on: "standings_points_overrides",
                columns: ["league_id", "team_id", "id"]
            )
        }
        return migrator
    }

    public static func removeV1Schema(_ db: Database) throws {
        if try db.tableExists("standings_points_overrides") {
            try removeV6Schema(db)
        }
        try db.drop(table: "players")
        try db.drop(table: "teams")
        try db.drop(table: "leagues")
    }

    public static func removeV2Schema(_ db: Database) throws {
        if try db.tableExists("match_events") {
            try removeV3Schema(db)
        }
        try db.drop(table: "fixture_players")
        try db.drop(table: "fixtures")
        try db.drop(table: "grounds")
    }

    public static func removeV3Schema(_ db: Database) throws {
        try db.drop(table: "match_events")
        try db.drop(table: "match_rules")
    }

    public static func removeV6Schema(_ db: Database) throws {
        try db.drop(table: "standings_points_overrides")
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

    /// Lists user-owned leagues and tournaments. The system-owned
    /// quick-games container (issue #16) is hidden by default: it exists
    /// only to hold throwaway teams for impromptu matches and must never
    /// surface in setup, standings pickers, or stats. Pass
    /// `includeQuickGames: true` for export/backup-name-resolution paths.
    public func listLeagues(includeArchived: Bool = false, includeQuickGames: Bool = false) throws -> [LeagueRecord] {
        try db.read { database in
            var conditions: [String] = []
            if !includeArchived { conditions.append("is_archived = 0") }
            if !includeQuickGames { conditions.append("id <> ?") }
            let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let order = "ORDER BY name COLLATE NOCASE, id"
            if includeQuickGames {
                let rows = try Row.fetchAll(database, sql: "SELECT * FROM leagues \(filter) \(order)")
                return try rows.map(decodeLeague)
            }
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM leagues \(filter) \(order)",
                arguments: [Self.quickGamesLeagueID.rawValue]
            )
            return try rows.map(decodeLeague)
        }
    }

    public func league(id: LeagueID) throws -> LeagueRecord? {
        try db.read { database in try league(id: id, in: database) }
    }

    /// The league's configured casual rule preset, or `.standard` when the
    /// league has never been configured. Malformed stored JSON throws rather
    /// than quietly degrading to defaults.
    public func rulePreset(for leagueID: LeagueID) throws -> RulePreset {
        try db.read { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            let json = try String.fetchOne(
                database,
                sql: "SELECT rule_preset_json FROM leagues WHERE id = ?",
                arguments: [leagueID.rawValue]
            )
            // Only SQL NULL means "unconfigured". An empty string cannot be a
            // valid encoded preset, so it is corruption and must surface.
            guard let json else { return .standard }
            guard !json.isEmpty,
                  let data = json.data(using: .utf8),
                  let preset = try? JSONDecoder().decode(RulePreset.self, from: data)
            else { throw WicketStoreError.malformedConfiguration }
            return preset
        }
    }

    /// Stores the league's preset for *future* match creation only. Existing
    /// matches keep the rules snapshot copied into their own header.
    public func setRulePreset(_ preset: RulePreset, for leagueID: LeagueID) throws {
        let payload = try JSONEncoder().encode(preset)
        guard let json = String(data: payload, encoding: .utf8) else {
            throw WicketStoreError.malformedConfiguration
        }
        try db.write { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            try database.execute(
                sql: "UPDATE leagues SET rule_preset_json = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [json, Date().truncatedToMilliseconds.millisecondsSince1970, leagueID.rawValue]
            )
        }
    }

    /// The effective manual points overrides for a league: the most recently
    /// recorded row per team. Earlier rows stay in the table as audit history,
    /// so the standings projection never sees duplicates for one team.
    public func listPointsOverrides(leagueID: LeagueID) throws -> [StandingsPointsOverride] {
        try db.read { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT o.* FROM standings_points_overrides o
                JOIN (
                    SELECT team_id, MAX(id) AS latest
                    FROM standings_points_overrides
                    WHERE league_id = ?
                    GROUP BY team_id
                ) newest ON o.team_id = newest.team_id AND o.id = newest.latest
                ORDER BY o.team_id
                """,
                arguments: [leagueID.rawValue]
            )
            return try rows.map(decodePointsOverride)
        }
    }

    /// The full append-only audit trail, oldest first, for showing who changed
    /// a team's points and why.
    public func pointsOverrideHistory(leagueID: LeagueID) throws -> [StandingsPointsOverride] {
        try db.read { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT * FROM standings_points_overrides
                WHERE league_id = ? ORDER BY id
                """,
                arguments: [leagueID.rawValue]
            )
            return try rows.map(decodePointsOverride)
        }
    }

    /// Appends a new override row. Never updates or deletes an earlier row, so
    /// the correction history of a user-owned points decision is preserved.
    public func setPointsOverride(
        leagueID: LeagueID,
        override: StandingsPointsOverride
    ) throws {
        // Revalidate: a decoded value can carry blanks the initializer rejects.
        _ = try StandingsPointsOverride(
            teamID: override.teamID,
            points: override.points,
            reason: override.reason,
            provenance: override.provenance,
            recordedAt: override.recordedAt
        )
        try db.write { database in
            guard try league(id: leagueID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            guard let team = try team(id: override.teamID, in: database),
                  team.leagueID == leagueID
            else { throw WicketStoreError.parentNotFound }
            try database.execute(
                sql: """
                INSERT INTO standings_points_overrides
                    (league_id, team_id, points, reason, provenance, recorded_at_ms)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    leagueID.rawValue,
                    override.teamID.rawValue,
                    override.points,
                    override.reason,
                    override.provenance,
                    override.recordedAt.truncatedToMilliseconds.millisecondsSince1970,
                ]
            )
        }
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

    /// Grounds a user can pick for scheduled fixtures. The hidden
    /// quick-games ground (issue #16) is system-owned and never selectable.
    public func listGrounds(includeQuickGames: Bool = false) throws -> [GroundRecord] {
        try db.read { database in
            let order = "ORDER BY name COLLATE NOCASE, id"
            if includeQuickGames {
                let rows = try Row.fetchAll(database, sql: "SELECT * FROM grounds \(order)")
                return try rows.map(decodeGround)
            }
            let rows = try Row.fetchAll(
                database,
                sql: "SELECT * FROM grounds WHERE id <> ? \(order)",
                arguments: [Self.quickGamesGroundID.rawValue]
            )
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
            // Garbage-collect throwaway ad-hoc teams (issue #16): the hidden
            // quick-games league holds one team pair per impromptu game, and
            // nothing else can legitimately reference those rows. Once the
            // last fixture using a pair is gone, the pair goes with it.
            try database.execute(
                sql: """
                DELETE FROM teams
                WHERE league_id = ?
                  AND id NOT IN (
                      SELECT home_team_id FROM fixtures
                      UNION
                      SELECT away_team_id FROM fixtures
                  )
                """,
                arguments: [Self.quickGamesLeagueID.rawValue]
            )
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

    // MARK: - Match scoring ledger

    /// Loads the complete append-only ledger for a fixture. Rules default to
    /// T20 until explicitly selected or the first event is appended.
    public func scoringSession(fixtureID: FixtureID) throws -> PersistedScoringSession {
        try db.read { database in
            guard try fixture(id: fixtureID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }

            let rules: MatchRules
            if let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM match_rules WHERE fixture_id = ?",
                arguments: [fixtureID.rawValue]
            ) {
                let payload: Data? = row["rules_payload"]
                if let payload {
                    rules = try JSONDecoder().decode(MatchRules.self, from: payload)
                } else {
                    rules = MatchRules(
                        oversPerInnings: row["overs_per_innings"],
                        ballsPerOver: row["balls_per_over"],
                        maxWickets: row["max_wickets"]
                    )
                }
            } else {
                rules = try unconfiguredRules(fixtureID: fixtureID, in: database)
            }

            let rows = try Row.fetchAll(
                database,
                sql: "SELECT payload FROM match_events WHERE fixture_id = ? ORDER BY sequence ASC",
                arguments: [fixtureID.rawValue]
            )
            let decoder = JSONDecoder()
            let events = try rows.map { row in
                try decoder.decode(MatchEvent.self, from: row["payload"] as Data)
            }
            return PersistedScoringSession(rules: rules, ledger: MatchLedger(events: events))
        }
    }

    /// Match rules become immutable once scoring begins so replay cannot
    /// reinterpret an already persisted partial innings.
    public func setMatchRules(_ rules: MatchRules, fixtureID: FixtureID) throws {
        try db.write { database in
            guard try fixture(id: fixtureID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }
            let eventCount = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM match_events WHERE fixture_id = ?",
                arguments: [fixtureID.rawValue]
            ) ?? 0
            guard eventCount == 0 else {
                throw WicketStoreError.scoringConflict
            }
            try database.execute(
                sql: """
                INSERT OR REPLACE INTO match_rules
                    (fixture_id, overs_per_innings, balls_per_over, max_wickets, rules_payload)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    fixtureID.rawValue,
                    rules.oversPerInnings,
                    rules.ballsPerOver,
                    rules.maxWickets,
                    try JSONEncoder().encode(rules),
                ]
            )
        }
    }

    /// Appends exactly one event at the next sequence. The sequence guard
    /// prevents two stale scorer views from silently forking the local ledger.
    public func appendScoringEvent(
        _ event: MatchEvent,
        fixtureID: FixtureID,
        rules: MatchRules
    ) throws {
        try db.write { database in
            guard try fixture(id: fixtureID, in: database) != nil else {
                throw WicketStoreError.recordNotFound
            }

            if let row = try Row.fetchOne(
                database,
                sql: "SELECT * FROM match_rules WHERE fixture_id = ?",
                arguments: [fixtureID.rawValue]
            ) {
                let payload: Data? = row["rules_payload"]
                let persistedRules: MatchRules
                if let payload {
                    persistedRules = try JSONDecoder().decode(MatchRules.self, from: payload)
                } else {
                    persistedRules = MatchRules(
                        oversPerInnings: row["overs_per_innings"],
                        ballsPerOver: row["balls_per_over"],
                        maxWickets: row["max_wickets"]
                    )
                }
                guard persistedRules == rules else {
                    throw WicketStoreError.scoringConflict
                }
            } else {
                try database.execute(
                    sql: """
                    INSERT INTO match_rules
                        (fixture_id, overs_per_innings, balls_per_over, max_wickets, rules_payload)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        fixtureID.rawValue,
                        rules.oversPerInnings,
                        rules.ballsPerOver,
                        rules.maxWickets,
                        try JSONEncoder().encode(rules),
                    ]
                )
            }

            let lastSequence = try Int.fetchOne(
                database,
                sql: "SELECT MAX(sequence) FROM match_events WHERE fixture_id = ?",
                arguments: [fixtureID.rawValue]
            ) ?? 0
            guard event.sequence == lastSequence + 1 else {
                throw WicketStoreError.scoringConflict
            }

            try database.execute(
                sql: """
                INSERT INTO match_events (id, fixture_id, sequence, payload)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [
                    event.id.rawValue.uuidString.lowercased(),
                    fixtureID.rawValue,
                    event.sequence,
                    try JSONEncoder().encode(event),
                ]
            )
        }
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

    /// Rules for a match whose header has not been written yet: a copy of the
    /// owning league's preset. The copy is frozen into `match_rules` as soon as
    /// rules are set or the first ball is appended, so later league edits only
    /// affect future matches and replay never reads mutable league config.
    private func unconfiguredRules(fixtureID: FixtureID, in database: Database) throws -> MatchRules {
        let leagueIDString = try String.fetchOne(
            database,
            sql: "SELECT league_id FROM fixtures WHERE id = ?",
            arguments: [fixtureID.rawValue]
        )
        guard let leagueIDString else { return .t20 }
        let json = try String.fetchOne(
            database,
            sql: "SELECT rule_preset_json FROM leagues WHERE id = ?",
            arguments: [leagueIDString]
        )
        guard let json else { return .t20 }
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let preset = try? JSONDecoder().decode(RulePreset.self, from: data)
        else { throw WicketStoreError.malformedConfiguration }
        return preset.rules
    }

    private func decodePointsOverride(_ row: Row) throws -> StandingsPointsOverride {
        let milliseconds: Int64 = row["recorded_at_ms"]
        return try StandingsPointsOverride(
            teamID: TeamID(row["team_id"]),
            points: row["points"],
            reason: row["reason"],
            provenance: row["provenance"],
            recordedAt: Date(millisecondsSince1970: milliseconds)
        )
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
        let fixtureCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM fixtures WHERE league_id = ?",
            arguments: [id.rawValue]
        ) ?? 0
        // Scoring events and the points audit cascade away with the league, so
        // the confirmation must show them or a user could destroy a scored
        // season believing only teams were at stake.
        let scoringEventCount = try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*) FROM match_events
            JOIN fixtures ON fixtures.id = match_events.fixture_id
            WHERE fixtures.league_id = ?
            """,
            arguments: [id.rawValue]
        ) ?? 0
        let pointsOverrideCount = try Int.fetchOne(
            database,
            sql: "SELECT COUNT(*) FROM standings_points_overrides WHERE league_id = ?",
            arguments: [id.rawValue]
        ) ?? 0
        return LeagueDeletionPreview(
            leagueID: id,
            leagueName: league.name,
            teamCount: teamCount,
            playerCount: playerCount,
            fixtureCount: fixtureCount,
            scoringEventCount: scoringEventCount,
            pointsOverrideCount: pointsOverrideCount
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
