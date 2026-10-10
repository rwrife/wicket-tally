import Foundation
import GRDB
import Testing
import WicketKit
@testable import WicketStore

@Suite("Local lineup templates and match-day snapshots")
struct LineupTests {
    func setup(_ store: WicketStore) throws -> (TeamRecord, TeamRecord, PlayerRecord, PlayerRecord, FixtureRecord) {
        let league = try store.createLeague(name: "Season", kind: .league)
        let home = try store.createTeam(leagueID: league.id, name: "Home", colour: .saffron)
        let away = try store.createTeam(leagueID: league.id, name: "Away", colour: .wicketGreen)
        let first = try store.createPlayer(teamID: home.id, name: "First", role: .batter)
        let second = try store.createPlayer(teamID: home.id, name: "Second", role: .bowler)
        let ground = try store.createGround(name: "Park")
        let fixture = try store.createFixture(leagueID: league.id, name: "Match", homeTeamID: home.id, awayTeamID: away.id, groundID: ground.id, participatingPlayerIDs: [first.id, second.id], startsAt: Date(), endsAt: Date().addingTimeInterval(3600), reminder: .none)
        return (home, away, first, second, fixture)
    }

    @Test func templateCRUDAndIndependentReuse() throws {
        let store = try WicketStore.inMemory()
        let (home, _, first, second, fixture) = try setup(store)
        let lineup = TeamLineup(playerIDs: [second.id, first.id], hasBattingOrder: true)
        let template = try store.saveLineupTemplate(teamID: home.id, name: "Weekend", lineup: lineup)
        try store.setFixtureLineup(template.lineup, fixtureID: fixture.id, teamID: home.id)
        try store.setFixtureLineup(TeamLineup(playerIDs: [first.id]), fixtureID: fixture.id, teamID: home.id)
        #expect(try store.listLineupTemplates(teamID: home.id) == [template])
        let renamed = try store.saveLineupTemplate(id: template.id, teamID: home.id, name: "Sunday", lineup: lineup)
        #expect(renamed.name == "Sunday")
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs == [first.id])
        try store.deleteLineupTemplate(id: template.id)
        #expect(try store.listLineupTemplates(teamID: home.id).isEmpty)
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs == [first.id])
    }

    @Test func validationAndUnknownSelection() throws {
        let store = try WicketStore.inMemory()
        let (home, away, first, second, fixture) = try setup(store)
        let third = try store.createPlayer(teamID: home.id, name: "Third", role: .batter)
        try store.setMatchRules(try RulePreset(name: "Pairs", playersPerSide: 2).rules, fixtureID: fixture.id)
        #expect(throws: LineupError.teamSizeExceeded(2)) {
            try store.setFixtureLineup(TeamLineup(playerIDs: [first.id, second.id, third.id]), fixtureID: fixture.id, teamID: home.id)
        }
        #expect(throws: LineupError.duplicatePlayer) {
            try store.saveLineupTemplate(teamID: home.id, name: "Duplicates", lineup: TeamLineup(playerIDs: [first.id, first.id]))
        }
        #expect(throws: LineupError.unavailablePlayer(first.id)) {
            try store.setFixtureLineup(TeamLineup(playerIDs: [first.id]), fixtureID: fixture.id, teamID: away.id)
        }
        #expect(throws: WicketStoreError.invalidName) {
            try store.saveLineupTemplate(teamID: home.id, name: " \n ", lineup: TeamLineup())
        }
        try store.setFixtureLineup(TeamLineup(), fixtureID: fixture.id, teamID: home.id)
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs.isEmpty)
    }

    @Test func deletedAndArchivedPlayersStayExplicit() throws {
        let store = try WicketStore.inMemory()
        let (home, _, first, second, fixture) = try setup(store)
        let lineup = TeamLineup(playerIDs: [first.id, second.id], hasBattingOrder: true)
        let template = try store.saveLineupTemplate(teamID: home.id, name: "Regulars", lineup: lineup)
        try store.setFixtureLineup(lineup, fixtureID: fixture.id, teamID: home.id)
        try store.setPlayerArchived(id: second.id, archived: true)
        try store.deletePlayer(id: first.id, confirming: store.previewPlayerDeletion(id: first.id))
        #expect(try store.listLineupTemplates(teamID: home.id) == [template])
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id) == lineup)
        let backup = try store.makeBackup()
        let target = try WicketStore.inMemory()
        try target.restoreBackup(from: backup, confirming: target.previewRestore(from: backup))
        #expect(try target.fixtureLineup(fixtureID: fixture.id, teamID: home.id) == lineup)
        #expect(try target.listLineupTemplates(teamID: home.id) == [template])
        #expect(throws: LineupError.unavailablePlayer(first.id)) {
            try store.setFixtureLineup(lineup, fixtureID: fixture.id, teamID: home.id)
        }
        #expect(throws: LineupError.unavailablePlayer(second.id)) {
            try store.setFixtureLineup(TeamLineup(playerIDs: [second.id]), fixtureID: fixture.id, teamID: home.id)
        }
    }

    @Test func correctionSafeLedgerAndBackup() throws {
        let store = try WicketStore.inMemory()
        let (home, away, first, second, fixture) = try setup(store)
        let lineup = TeamLineup(playerIDs: [second.id, first.id], hasBattingOrder: true)
        let template = try store.saveLineupTemplate(teamID: home.id, name: "Order", lineup: lineup)
        try store.setFixtureLineup(lineup, fixtureID: fixture.id, teamID: home.id)
        let rules = MatchRules.t20
        let ball = MatchEvent(sequence: 2, kind: .ball(BallEvent(striker: first.id, nonStriker: second.id, bowler: nil, runsOffBat: 4)))
        let events = [MatchEvent(sequence: 1, kind: .inningsStarted(number: 1, batting: home.id, bowling: away.id)), ball,
                      MatchEvent(sequence: 3, kind: .correction(CorrectionEvent(action: .replace(target: ball.id, with: .ball(BallEvent(striker: first.id, nonStriker: nil, bowler: nil, runsOffBat: 6))), reason: "Boundary", provenance: "Scorer")))]
        for event in events { try store.appendScoringEvent(event, fixtureID: fixture.id, rules: rules) }
        let before = try store.scoringSession(fixtureID: fixture.id)
        let cardBefore = try StatsDerivation.derive(fixtures: [StatsFixture(id: fixture.id, homeTeamID: home.id, awayTeamID: away.id, rules: rules, ledger: before.ledger, playerIDs: fixture.participatingPlayerIDs)], teamIDs: [home.id, away.id])
        try store.setFixtureLineup(TeamLineup(), fixtureID: fixture.id, teamID: home.id)
        let after = try store.scoringSession(fixtureID: fixture.id)
        #expect(after == before)
        let edited = try #require(try store.fixture(id: fixture.id))
        let cardAfter = try StatsDerivation.derive(fixtures: [StatsFixture(id: fixture.id, homeTeamID: home.id, awayTeamID: away.id, rules: rules, ledger: after.ledger, playerIDs: edited.participatingPlayerIDs)], teamIDs: [home.id, away.id])
        #expect(cardAfter.scorecards == cardBefore.scorecards)
        #expect(cardAfter.players.first { $0.playerID == first.id } == cardBefore.players.first { $0.playerID == first.id })
        #expect(cardAfter.scorecards[fixture.id]?.innings.first?.batting.first { $0.playerID == first.id }?.runs == 6)
        #expect(after.ledger.replay(rules: rules) == before.ledger.replay(rules: rules))
        let backup = try store.makeBackup()
        let target = try WicketStore.inMemory()
        let preview = try target.previewRestore(from: backup)
        #expect(preview.lineupTemplateCount == 1)
        #expect(preview.fixtureLineupCount == 2)
        try target.restoreBackup(from: backup, confirming: preview)
        #expect(try target.listLineupTemplates(teamID: home.id) == [template])
        #expect(try target.fixtureLineup(fixtureID: fixture.id, teamID: home.id) == TeamLineup())
        #expect(try target.scoringSession(fixtureID: fixture.id) == before)
        let deletion = try target.previewLeagueDeletion(id: home.leagueID)
        #expect(deletion.lineupTemplateCount == 1)
        #expect(deletion.fixtureLineupCount == 2)
        #expect(deletion.summary.contains("1 lineup template"))
        try target.deleteLeague(id: home.leagueID, confirming: deletion)
        #expect(try target.listLineupTemplates(teamID: home.id).isEmpty)
    }

    @Test func atomicFixtureSetupAndTemplateReuse() throws {
        let store = try WicketStore.inMemory()
        let (home, away, first, second, fixture) = try setup(store)
        let lineup = TeamLineup(playerIDs: [second.id, first.id], hasBattingOrder: true)
        let template = try store.saveLineupTemplate(teamID: home.id, name: "Reusable", lineup: lineup)
        let secondFixture = try store.createFixture(leagueID: fixture.leagueID, name: "Second", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: [], startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none, lineups: [home.id: template.lineup, away.id: TeamLineup()])
        #expect(secondFixture.participatingPlayerIDs == Set(lineup.playerIDs))
        #expect(try store.fixtureLineup(fixtureID: secondFixture.id, teamID: home.id) == lineup)
        try store.setFixtureLineup(TeamLineup(), fixtureID: fixture.id, teamID: home.id)
        #expect(try store.fixtureLineup(fixtureID: secondFixture.id, teamID: home.id) == lineup)
        let before = try store.fixture(id: secondFixture.id)
        #expect(throws: LineupError.unavailablePlayer("missing")) {
            try store.updateFixture(id: secondFixture.id, leagueID: fixture.leagueID, name: "Must roll back", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: [], startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none, lineups: [home.id: TeamLineup(playerIDs: ["missing"]), away.id: TeamLineup()])
        }
        #expect(try store.fixture(id: secondFixture.id) == before)
        #expect(try store.fixtureLineup(fixtureID: secondFixture.id, teamID: home.id) == lineup)
        #expect(try store.listLineupTemplates(teamID: home.id) == [template])
        let preview = try store.previewLeagueDeletion(id: home.leagueID)
        _ = try store.saveLineupTemplate(teamID: home.id, name: "Another", lineup: TeamLineup())
        #expect(throws: WicketStoreError.confirmationStale) { try store.deleteLeague(id: home.leagueID, confirming: preview) }
    }

    @Test func matchSizeSnapshotAndLegacyAPI() throws {
        let store = try WicketStore.inMemory()
        let (home, away, first, second, fixture) = try setup(store)
        let third = try store.createPlayer(teamID: home.id, name: "Third", role: .batter)
        try store.setMatchRules(try RulePreset(name: "Two", playersPerSide: 2).rules, fixtureID: fixture.id)
        try store.setRulePreset(try RulePreset(name: "Three", playersPerSide: 3), for: home.leagueID)
        #expect(throws: LineupError.teamSizeExceeded(2)) {
            try store.setFixtureLineup(TeamLineup(playerIDs: [first.id, second.id, third.id]), fixtureID: fixture.id, teamID: home.id)
        }
        try store.updateFixture(id: fixture.id, leagueID: fixture.leagueID, name: fixture.name, homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: [second.id], startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none)
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs == [second.id])
        #expect(throws: LineupError.invalidTeam) {
            try store.fixtureLineup(fixtureID: fixture.id, teamID: "foreign")
        }
        #expect(throws: WicketStoreError.recordNotFound) {
            try store.fixtureLineup(fixtureID: "missing", teamID: home.id)
        }
    }

    @Test func participantWritesValidateAndRollBack() throws {
        let store = try WicketStore.inMemory()
        let (home, away, first, second, fixture) = try setup(store)
        try store.setRulePreset(try RulePreset(name: "Pairs", playersPerSide: 2), for: home.leagueID)
        let thirdTeam = try store.createTeam(leagueID: home.leagueID, name: "Other", colour: .saffron)
        let foreign = try store.createPlayer(teamID: thirdTeam.id, name: "Foreign", role: .batter)
        let archived = try store.createPlayer(teamID: away.id, name: "Archived", role: .batter)
        try store.setPlayerArchived(id: archived.id, archived: true)
        let visitor = try store.createPlayer(teamID: away.id, name: "Visitor", role: .batter)
        let third = try store.createPlayer(teamID: home.id, name: "Third", role: .batter)
        func create(_ ids: Set<PlayerID>) throws -> FixtureRecord {
            try store.createFixture(leagueID: fixture.leagueID, name: "New", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: ids, startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none)
        }
        func update(_ ids: Set<PlayerID>) throws {
            try store.updateFixture(id: fixture.id, leagueID: fixture.leagueID, name: "Changed", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: ids, startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none)
        }
        #expect(throws: LineupError.teamSizeExceeded(2)) { try create([first.id, second.id, third.id]) }
        #expect(throws: LineupError.teamSizeExceeded(2)) { try update([first.id, second.id, third.id]) }
        for id in [foreign.id, archived.id, PlayerID("missing")] {
            #expect(throws: LineupError.unavailablePlayer(id)) { try create([id]) }
            #expect(throws: LineupError.unavailablePlayer(id)) { try update([id]) }
        }
        #expect(try store.listFixtures().count == 1)
        #expect(try store.fixture(id: fixture.id) == fixture)
        #expect(Set(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs) == [first.id, second.id])
        // A failed rules change must preserve the previous explicit snapshot.
        try store.setMatchRules(try RulePreset(name: "Three", playersPerSide: 3).rules, fixtureID: fixture.id)
        try update([first.id, second.id, third.id])
        #expect(throws: LineupError.teamSizeExceeded(2)) {
            try store.setMatchRules(try RulePreset(name: "Pairs", playersPerSide: 2).rules, fixtureID: fixture.id)
        }
        #expect(try store.scoringSession(fixtureID: fixture.id).rules.playersPerSide == 3)
        let fourth = try store.createPlayer(teamID: home.id, name: "Fourth", role: .batter)
        #expect(throws: LineupError.teamSizeExceeded(3)) { try update([first.id, second.id, third.id, fourth.id]) }
        let oversized = TeamLineup(playerIDs: [first.id, second.id, third.id, fourth.id])
        #expect(throws: LineupError.teamSizeExceeded(2)) {
            try store.createFixture(leagueID: fixture.leagueID, name: "Explicit", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: [], startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none, lineups: [home.id: oversized, away.id: TeamLineup()])
        }
        #expect(throws: LineupError.teamSizeExceeded(3)) {
            try store.updateFixture(id: fixture.id, leagueID: fixture.leagueID, name: "Explicit", homeTeamID: home.id, awayTeamID: away.id, groundID: fixture.groundID, participatingPlayerIDs: [], startsAt: fixture.startsAt, endsAt: fixture.endsAt, reminder: .none, lineups: [home.id: oversized, away.id: TeamLineup()])
        }
        let valid = try create([first.id, visitor.id])
        #expect(try store.fixtureLineup(fixtureID: valid.id, teamID: away.id).playerIDs == [visitor.id])
        try update([second.id, visitor.id])
        #expect(try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs == [second.id])
    }

    @Test func persistedLineupReadErrorsAreExplicit() throws {
        let store = try WicketStore.inMemory()
        let (home, _, _, _, fixture) = try setup(store)
        try store.db.write { database in
            try database.execute(sql: "UPDATE fixture_lineups SET payload = ? WHERE fixture_id = ? AND team_id = ?", arguments: [Data("invalid JSON".utf8), fixture.id.rawValue, home.id.rawValue])
        }
        #expect(throws: DecodingError.self) {
            try store.fixtureLineup(fixtureID: fixture.id, teamID: home.id)
        }
    }

    @Test func migrationAndRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try DatabaseQueue(path: url.path)
        try WicketStore.migrator.migrate(database, upTo: "v6")
        let old = WicketStore(db: database)
        let (home, _, first, second, fixture) = try setup(old)
        // Historical selections can exceed the current preset and contain archived players.
        let third = try old.createPlayer(teamID: home.id, name: "Third", role: .batter)
        try database.write { db in
            try db.execute(sql: "INSERT INTO fixture_players VALUES (?, ?)", arguments: [fixture.id.rawValue, third.id.rawValue])
        }
        try old.setRulePreset(try RulePreset(name: "Pairs", playersPerSide: 2), for: home.leagueID)
        try old.setPlayerArchived(id: second.id, archived: true)
        let legacyBackup = try old.makeBackup()
        try WicketStore.migrator.migrate(database)
        let expected = Set([first.id, second.id, third.id])
        #expect(Set(try old.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs) == expected)
        try old.setRulePreset(try RulePreset(name: "Pairs", playersPerSide: 2), for: home.leagueID)
        try old.setPlayerArchived(id: second.id, archived: false)
        let lineup = TeamLineup(playerIDs: [second.id, first.id], hasBattingOrder: true)
        try old.setFixtureLineup(lineup, fixtureID: fixture.id, teamID: home.id)
        let template = try old.saveLineupTemplate(teamID: home.id, name: "Persisted", lineup: lineup)
        let reopened = try WicketStore.open(at: url)
        #expect(try reopened.fixtureLineup(fixtureID: fixture.id, teamID: home.id) == lineup)
        #expect(try reopened.listLineupTemplates(teamID: home.id) == [template])
        let target = try WicketStore.inMemory()
        try target.restoreBackup(from: legacyBackup, confirming: target.previewRestore(from: legacyBackup))
        #expect(Set(try target.fixtureLineup(fixtureID: fixture.id, teamID: home.id).playerIDs) == expected)
    }
}
