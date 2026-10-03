import Foundation
import GRDB
import WicketKit

/// One-shot result of starting an ad-hoc game.
public struct AdhocMatchStart: Sendable, Equatable, Hashable {
    public let fixture: FixtureRecord
    public let homeTeam: TeamRecord
    public let awayTeam: TeamRecord

    public init(fixture: FixtureRecord, homeTeam: TeamRecord, awayTeam: TeamRecord) {
        self.fixture = fixture
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fixture.id)
        hasher.combine(homeTeam.id)
        hasher.combine(awayTeam.id)
    }
}

extension WicketStore {
    /// System-owned containers for impromptu games (issue #16). They are
    /// created lazily on the first quick match and excluded from every
    /// user-facing league listing, so a scorer never has to set up a formal
    /// league, teams, or a ground just to keep score. Computed vars keep
    /// them constant-expression safe (no stored properties in extensions).
    public static var quickGamesLeagueID: LeagueID { LeagueID("quick-games") }
    public static var quickGamesGroundID: GroundID { GroundID("quick-games") }
    public static var quickGamesLeagueName: String { "Quick games" }
    public static var quickGamesGroundName: String { "Any ground" }

    /// Materializes an `AdhocMatchPlan` into local records and returns a
    /// fixture that is immediately scoreable by the existing scorer. The
    /// fixture carries no league (a standalone match), so it never pollutes
    /// league standings; its throwaway teams live only inside the hidden
    /// quick-games league. Rules are frozen into the fixture header before
    /// any event exists, exactly like a scheduled match.
    public func startAdhocMatch(
        homeName: String,
        awayName: String,
        rules: MatchRules,
        startingAt start: Date = Date()
    ) throws -> AdhocMatchStart {
        let plan = try AdhocMatchPlan(homeName: homeName, awayName: awayName, rules: rules, startingAt: start)

        try db.write { database in
            let leagueExists = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM leagues WHERE id = ?",
                arguments: [Self.quickGamesLeagueID.rawValue]
            ) ?? 0
            if leagueExists == 0 {
                let now = Date().truncatedToMilliseconds.millisecondsSince1970
                try database.execute(
                    sql: """
                    INSERT INTO leagues (id, name, kind, is_archived, created_at_ms, updated_at_ms)
                    VALUES (?, ?, 'tournament', 0, ?, ?)
                    """,
                    arguments: [Self.quickGamesLeagueID.rawValue, Self.quickGamesLeagueName, now, now]
                )
            }
            let groundExists = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM grounds WHERE id = ?",
                arguments: [Self.quickGamesGroundID.rawValue]
            ) ?? 0
            if groundExists == 0 {
                let now = Date().truncatedToMilliseconds.millisecondsSince1970
                try database.execute(
                    sql: "INSERT INTO grounds (id, name, created_at_ms, updated_at_ms) VALUES (?, ?, ?, ?)",
                    arguments: [Self.quickGamesGroundID.rawValue, Self.quickGamesGroundName, now, now]
                )
            }
        }

        let home = try createTeam(leagueID: Self.quickGamesLeagueID, name: plan.homeName, colour: .marigold)
        let away = try createTeam(leagueID: Self.quickGamesLeagueID, name: plan.awayName, colour: .peacockTeal)

        let fixtureID = FixtureID(UUID().uuidString.lowercased())
        let now = Date().truncatedToMilliseconds
        try db.write { database in
            try database.execute(
                sql: """
                INSERT INTO fixtures
                    (id, league_id, name, home_team_id, away_team_id, ground_id,
                     starts_at_ms, ends_at_ms, reminder_minutes, created_at_ms, updated_at_ms)
                VALUES (?, NULL, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                """,
                arguments: [
                    fixtureID.rawValue,
                    plan.fixtureName,
                    home.id.rawValue,
                    away.id.rawValue,
                    Self.quickGamesGroundID.rawValue,
                    plan.startsAt.truncatedToMilliseconds.millisecondsSince1970,
                    plan.endsAt.truncatedToMilliseconds.millisecondsSince1970,
                    now.millisecondsSince1970,
                    now.millisecondsSince1970,
                ]
            )
        }
        try setMatchRules(plan.rules, fixtureID: fixtureID)

        guard let fixture = try fixture(id: fixtureID) else {
            throw WicketStoreError.recordNotFound
        }
        return AdhocMatchStart(fixture: fixture, homeTeam: home, awayTeam: away)
    }
}
