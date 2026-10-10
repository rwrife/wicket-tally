import Foundation
import GRDB
import WicketKit

extension WicketStore {
    public func listLineupTemplates(teamID: TeamID) throws -> [LineupTemplate] {
        try db.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM lineup_templates WHERE team_id = ? ORDER BY name COLLATE NOCASE, id", arguments: [teamID.rawValue]).map { row in
                LineupTemplate(id: row["id"], teamID: teamID, name: row["name"], lineup: try JSONDecoder().decode(TeamLineup.self, from: row["payload"] as Data))
            }
        }
    }

    @discardableResult
    public func saveLineupTemplate(id: String? = nil, teamID: TeamID, name: String, lineup: TeamLineup) throws -> LineupTemplate {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw WicketStoreError.invalidName }
        let record = LineupTemplate(id: id ?? UUID().uuidString.lowercased(), teamID: teamID, name: name, lineup: lineup)
        try db.write { database in
            guard try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM teams WHERE id = ?", arguments: [teamID.rawValue]) == 1 else { throw WicketStoreError.parentNotFound }
            if let id {
                guard try String.fetchOne(database, sql: "SELECT team_id FROM lineup_templates WHERE id = ?", arguments: [id]) == teamID.rawValue else { throw WicketStoreError.recordNotFound }
            }
            try Self.validateLineup(lineup, teamID: teamID, limit: nil, in: database)
            try database.execute(sql: "INSERT INTO lineup_templates (id, team_id, name, payload) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, payload = excluded.payload", arguments: [record.id, teamID.rawValue, name, try JSONEncoder().encode(lineup)])
        }
        return record
    }

    public func deleteLineupTemplate(id: String) throws {
        try db.write { try $0.execute(sql: "DELETE FROM lineup_templates WHERE id = ?", arguments: [id]) }
    }

    public func fixtureLineup(fixtureID: FixtureID, teamID: TeamID) throws -> TeamLineup {
        try db.read { database in
            guard let fixture = try Row.fetchOne(database, sql: "SELECT home_team_id, away_team_id FROM fixtures WHERE id = ?", arguments: [fixtureID.rawValue]) else { throw WicketStoreError.recordNotFound }
            let home: String = fixture["home_team_id"]
            let away: String = fixture["away_team_id"]
            guard [home, away].contains(teamID.rawValue) else { throw LineupError.invalidTeam }
            if let payload = try Data.fetchOne(database, sql: "SELECT payload FROM fixture_lineups WHERE fixture_id = ? AND team_id = ?", arguments: [fixtureID.rawValue, teamID.rawValue]) {
                return try JSONDecoder().decode(TeamLineup.self, from: payload)
            }
            // Legacy fixtures remain usable without requiring a template.
            let ids = try String.fetchAll(database, sql: "SELECT p.id FROM fixture_players fp JOIN players p ON p.id = fp.player_id WHERE fp.fixture_id = ? AND p.team_id = ? ORDER BY p.id", arguments: [fixtureID.rawValue, teamID.rawValue])
            return TeamLineup(playerIDs: ids.map { PlayerID($0) })
        }
    }

    /// Replaces only match-day selection, never any recorded event or template.
    public func setFixtureLineup(_ lineup: TeamLineup, fixtureID: FixtureID, teamID: TeamID) throws {
        try db.write { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT home_team_id, away_team_id FROM fixtures WHERE id = ?", arguments: [fixtureID.rawValue]) else { throw WicketStoreError.recordNotFound }
            let home = TeamID(row["home_team_id"])
            let away = TeamID(row["away_team_id"])
            guard [home, away].contains(teamID) else { throw LineupError.invalidTeam }
            let rules = try effectiveLineupRules(fixtureID: fixtureID, in: database)
            try Self.validateLineup(lineup, teamID: teamID, limit: rules.playersPerSide, in: database)
            try database.execute(sql: "INSERT INTO fixture_lineups (fixture_id, team_id, payload) VALUES (?, ?, ?) ON CONFLICT(fixture_id, team_id) DO UPDATE SET payload = excluded.payload", arguments: [fixtureID.rawValue, teamID.rawValue, try JSONEncoder().encode(lineup)])
            try database.execute(sql: "DELETE FROM fixture_players WHERE fixture_id = ? AND player_id IN (SELECT id FROM players WHERE team_id = ?)", arguments: [fixtureID.rawValue, teamID.rawValue])
            for id in lineup.playerIDs {
                try database.execute(sql: "INSERT OR IGNORE INTO fixture_players (fixture_id, player_id) VALUES (?, ?)", arguments: [fixtureID.rawValue, id.rawValue])
            }
        }
    }

    func saveFixtureLineups(_ lineups: [TeamID: TeamLineup], fixtureID: FixtureID, home: TeamID, away: TeamID, in database: Database) throws {
        guard Set(lineups.keys) == Set([home, away]) else { throw LineupError.invalidTeam }
        let rules = try effectiveLineupRules(fixtureID: fixtureID, in: database)
        try database.execute(sql: "DELETE FROM fixture_lineups WHERE fixture_id = ?", arguments: [fixtureID.rawValue])
        for (team, lineup) in lineups {
            try Self.validateLineup(lineup, teamID: team, limit: rules.playersPerSide, in: database)
            try database.execute(sql: "INSERT INTO fixture_lineups VALUES (?, ?, ?)", arguments: [fixtureID.rawValue, team.rawValue, try JSONEncoder().encode(lineup)])
        }
    }

    private func effectiveLineupRules(fixtureID: FixtureID, in database: Database) throws -> MatchRules {
        let rules: MatchRules
        if let row = try Row.fetchOne(database, sql: "SELECT * FROM match_rules WHERE fixture_id = ?", arguments: [fixtureID.rawValue]) {
            if let payload: Data = row["rules_payload"] { rules = try JSONDecoder().decode(MatchRules.self, from: payload) }
            else { rules = MatchRules(oversPerInnings: row["overs_per_innings"], ballsPerOver: row["balls_per_over"], maxWickets: row["max_wickets"]) }
        } else { rules = try unconfiguredRules(fixtureID: fixtureID, in: database) }
        return rules
    }

    /// Used for pre-lineup databases and old backups. No historical selection
    /// is discarded just because it exceeds today's configured size.
    static func backfillFixtureLineups(in database: Database) throws {
        guard try database.tableExists("fixture_lineups") else { return }
        for row in try Row.fetchAll(database, sql: "SELECT id, home_team_id, away_team_id FROM fixtures") {
            let fixture: String = row["id"]
            for column in ["home_team_id", "away_team_id"] {
                let team: String = row[column]
                let exists = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM fixture_lineups WHERE fixture_id = ? AND team_id = ?", arguments: [fixture, team]) ?? 0
                guard exists == 0 else { continue }
                let ids = try String.fetchAll(database, sql: "SELECT p.id FROM fixture_players fp JOIN players p ON p.id = fp.player_id WHERE fp.fixture_id = ? AND p.team_id = ? ORDER BY p.id", arguments: [fixture, team])
                try database.execute(sql: "INSERT INTO fixture_lineups VALUES (?, ?, ?)", arguments: [fixture, team, try JSONEncoder().encode(TeamLineup(playerIDs: ids.map { PlayerID($0) }))])
            }
        }
    }

    static func validateLineup(_ lineup: TeamLineup, teamID: TeamID, limit: Int?, in database: Database) throws {
        guard Set(lineup.playerIDs).count == lineup.playerIDs.count else { throw LineupError.duplicatePlayer }
        if let limit, lineup.playerIDs.count > limit { throw LineupError.teamSizeExceeded(limit) }
        for id in lineup.playerIDs {
            guard try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM players WHERE id = ? AND team_id = ? AND is_archived = 0", arguments: [id.rawValue, teamID.rawValue]) == 1 else { throw LineupError.unavailablePlayer(id) }
        }
    }
}
