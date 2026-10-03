import Foundation
import Testing
import WicketKit
@testable import WicketStore

@Suite("Ad-hoc quick games (issue #16)")
struct AdhocMatchStoreTests {
    @Test("a quick game is immediately scoreable with frozen rules and no league")
    func startAndScore() throws {
        let store = try WicketStore.inMemory()
        let start = try store.startAdhocMatch(homeName: "Street Kings", awayName: "Gully XI", rules: .t10)

        #expect(start.fixture.leagueID == nil)
        #expect(start.fixture.name == "Street Kings vs Gully XI")
        #expect(start.homeTeam.name == "Street Kings")
        #expect(start.awayTeam.name == "Gully XI")
        #expect(start.homeTeam.leagueID == WicketStore.quickGamesLeagueID)
        #expect(start.awayTeam.leagueID == WicketStore.quickGamesLeagueID)

        // Rules freeze into the header before any event exists, exactly like
        // a scheduled match.
        var session = try store.scoringSession(fixtureID: start.fixture.id)
        #expect(session.rules == .t10)
        #expect(session.ledger.events.isEmpty)

        // The existing scorer path accepts events on the ad-hoc fixture.
        try store.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: start.homeTeam.id, decision: .bat)),
            fixtureID: start.fixture.id,
            rules: session.rules
        )
        session = try store.scoringSession(fixtureID: start.fixture.id)
        #expect(session.ledger.events.count == 1)
    }

    @Test("containers are created once and reused across games")
    func containerReuse() throws {
        let store = try WicketStore.inMemory()
        let first = try store.startAdhocMatch(homeName: "A", awayName: "B", rules: .t20)
        let second = try store.startAdhocMatch(homeName: "C", awayName: "D", rules: .t20)

        #expect(first.homeTeam.id != second.homeTeam.id)
        #expect(first.homeTeam.leagueID == second.homeTeam.leagueID)

        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM leagues WHERE id = 'quick-games'") == 1)
        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM grounds WHERE id = 'quick-games'") == 1)
    }

    @Test("quick-game containers stay hidden from user-facing listings")
    func hiddenContainers() throws {
        let store = try WicketStore.inMemory()
        _ = try store.startAdhocMatch(homeName: "A", awayName: "B", rules: .t20)

        #expect(try store.listLeagues().isEmpty)
        #expect(try store.listLeagues(includeArchived: true).isEmpty)
        #expect(try store.listGrounds().isEmpty)

        // Visible only on the explicit export/backup-name-resolution path.
        #expect(try store.listLeagues(includeArchived: true, includeQuickGames: true).count == 1)
        #expect(try store.listGrounds(includeQuickGames: true).count == 1)

        // User-created records still list normally alongside containers.
        _ = try store.createLeague(name: "Real League", kind: .league)
        _ = try store.createGround(name: "Real Ground")
        #expect(try store.listLeagues().map { $0.name } == ["Real League"])
        #expect(try store.listGrounds().map { $0.name } == ["Real Ground"])
    }

    @Test("validation failures leave the database untouched")
    func validationNoWrites() throws {
        let store = try WicketStore.inMemory()
        #expect(throws: AdhocMatchPlanError.homeNameRequired) {
            try store.startAdhocMatch(homeName: " ", awayName: "B", rules: .t20)
        }
        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM leagues") == 0)
        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM teams") == 0)
        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM fixtures") == 0)
    }

    @Test("deleting the last fixture for an ad-hoc side removes its throwaway team")
    func teamGarbageCollection() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Real League", kind: .league)
        let realTeam = try store.createTeam(leagueID: league.id, name: "Riders", colour: .saffron)
        _ = try store.createGround(name: "Real Ground")
        let game = try store.startAdhocMatch(homeName: "A", awayName: "B", rules: .t20)

        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM teams") == 3)

        try store.deleteFixture(id: game.fixture.id)
        #expect(try tableCount(store, sql: "SELECT COUNT(*) FROM teams") == 1)
        #expect(try store.team(id: realTeam.id) != nil)
    }

    @Test("teams still referenced by another fixture survive the sweep")
    func teamSweepKeepsLiveReferences() throws {
        let store = try WicketStore.inMemory()
        let first = try store.startAdhocMatch(homeName: "A", awayName: "B", rules: .t20)
        let second = try store.startAdhocMatch(homeName: "C", awayName: "D", rules: .t20)

        try store.deleteFixture(id: first.fixture.id)
        let teamsAfter = try store.listTeams(leagueID: WicketStore.quickGamesLeagueID, includeArchived: true)
        #expect(Set(teamsAfter.map(\.id)) == [second.homeTeam.id, second.awayTeam.id])
    }

    @Test("ad-hoc fixtures and teams round-trip through versioned JSON backup")
    func backupRestore() throws {
        let source = try WicketStore.inMemory()
        let game = try source.startAdhocMatch(homeName: "Street Kings", awayName: "Gully XI", rules: .t10)
        try source.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: game.homeTeam.id, decision: .bat)),
            fixtureID: game.fixture.id,
            rules: .t10
        )
        let data = try source.makeBackup()

        let target = try WicketStore.inMemory()
        let preview = try target.previewRestore(from: data)
        #expect(preview.fixtureCount == 1)
        #expect(preview.teamCount == 2)
        try target.restoreBackup(from: data, confirming: preview)

        let optionalRestored = try target.fixture(id: game.fixture.id)
        let restored = try #require(optionalRestored)
        #expect(restored == game.fixture)
        #expect(try target.team(id: game.homeTeam.id)?.name == "Street Kings")
        let session = try target.scoringSession(fixtureID: game.fixture.id)
        #expect(session.ledger.events.count == 1)
        // Containers remain hidden after restore too.
        #expect(try target.listLeagues().isEmpty)
    }

    @Test("scorecard export names ad-hoc sides and standings export omits the container")
    func csvExports() throws {
        let store = try WicketStore.inMemory()
        _ = try store.startAdhocMatch(homeName: "Street Kings", awayName: "Gully XI", rules: .t10)

        let scorecards = try String(decoding: store.makeCSV(.scorecards), as: UTF8.self)
        #expect(scorecards.contains("# match: Street Kings vs Gully XI"))

        let standings = try String(decoding: store.makeCSV(.standings), as: UTF8.self)
        #expect(!standings.contains("Quick games"))
    }

    @Test("ad-hoc fixtures never clash with scheduled grounds or players")
    func conflictIsolation() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Real League", kind: .league)
        let home = try store.createTeam(leagueID: league.id, name: "Riders", colour: .saffron)
        let away = try store.createTeam(leagueID: league.id, name: "Kings", colour: .skyBlue)
        let ground = try store.createGround(name: "Oval")
        let game = try store.startAdhocMatch(homeName: "A", awayName: "B", rules: .t20)

        // A scheduled fixture overlapping the ad-hoc window on a real ground
        // shares neither ground nor players with the impromptu game.
        let candidate = try FixtureRecord.validated(
            id: "scheduled",
            leagueID: league.id,
            name: "Scheduled",
            homeTeamID: home.id,
            awayTeamID: away.id,
            groundID: ground.id,
            participatingPlayerIDs: [],
            startsAt: game.fixture.startsAt,
            endsAt: game.fixture.endsAt,
            reminder: .none,
            createdAt: Date(),
            updatedAt: Date()
        )
        let conflicts = try store.conflicts(for: candidate)
        #expect(conflicts.isEmpty)
    }
}

private func tableCount(_ store: WicketStore, sql: String) throws -> Int {
    try store.db.read { database in
        try Int.fetchOne(database, sql: sql) ?? -1
    }
}
