import Foundation
import Testing
import WicketKit
@testable import WicketStore

@Suite("League deletion cascade preview")
struct LeagueCascadePreviewTests {
    @Test("shows fixtures, scoring events and points audit before deleting them")
    func previewIncludesAllChildren() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Park season", kind: .league)
        let home = try store.createTeam(leagueID: league.id, name: "Home", colour: .cricketRed)
        let away = try store.createTeam(leagueID: league.id, name: "Away", colour: .saffron)
        let ground = try store.createGround(name: "Park")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try store.createFixture(
            leagueID: league.id, name: "Opening match",
            homeTeamID: home.id, awayTeamID: away.id, groundID: ground.id,
            participatingPlayerIDs: [], startsAt: start,
            endsAt: start.addingTimeInterval(7_200), reminder: .none
        )
        let rules = MatchRules.t20
        try store.appendScoringEvent(
            MatchEvent(sequence: 1, kind: .toss(winner: home.id, decision: .bat)),
            fixtureID: fixture.id, rules: rules
        )
        let override = try StandingsPointsOverride(
            teamID: home.id, points: 2, reason: "Correction",
            provenance: "Scorer", recordedAt: start
        )
        try store.setPointsOverride(leagueID: league.id, override: override)

        let preview = try store.previewLeagueDeletion(id: league.id)
        #expect(preview.teamCount == 2)
        #expect(preview.fixtureCount == 1)
        #expect(preview.scoringEventCount == 1)
        #expect(preview.pointsOverrideCount == 1)
        #expect(preview.summary.contains("1 fixture"))
        #expect(preview.summary.contains("1 scoring event"))
        #expect(preview.summary.contains("1 points override"))

        try store.appendScoringEvent(
            MatchEvent(sequence: 2, kind: .inningsStarted(number: 1, batting: home.id, bowling: away.id)),
            fixtureID: fixture.id, rules: rules
        )
        #expect(throws: WicketStoreError.confirmationStale) {
            try store.deleteLeague(id: league.id, confirming: preview)
        }
        let current = try store.previewLeagueDeletion(id: league.id)
        #expect(current.scoringEventCount == 2)
        try store.deleteLeague(id: league.id, confirming: current)
        #expect(try store.league(id: league.id) == nil)
        #expect(try store.listFixtures().allSatisfy { $0.id != fixture.id })
    }
}
