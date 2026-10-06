import Foundation
import Testing
import WicketKit
@testable import WicketStore

@Suite("Atomic schedule drafts")
struct ScheduleStoreTests {
    @Test func cancelCommitAndConflicts() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Local cup", kind: .tournament)
        let a = try store.createTeam(leagueID: league.id, name: "A", colour: .saffron)
        let b = try store.createTeam(leagueID: league.id, name: "B", colour: .wicketGreen)
        let c = try store.createTeam(leagueID: league.id, name: "C", colour: .cricketRed)
        let ground = try store.createGround(name: "Park")
        let first = record(league: league.id, home: a.id, away: b.id, ground: ground.id, offset: 0)
        let second = record(league: league.id, home: b.id, away: c.id, ground: ground.id, offset: 1_000)
        let proposal = [first, second]
        let warnings = try store.previewSchedule(proposal)
        #expect(warnings[0].isEmpty)
        #expect(warnings[1].count == 1) // same ground, overlapping slots
        #expect(try store.listFixtures().isEmpty) // cancel is write-free
        try store.commitSchedule(proposal, confirmedConflicts: warnings)
        #expect(try store.listFixtures().count == 2)
        #expect(throws: WicketStoreError.scheduleAlreadyExists) {
            try store.commitSchedule([record(league: league.id, home: b.id, away: a.id, ground: ground.id, offset: 9_000)], confirmedConflicts: [[]])
        }
        #expect(try store.listFixtures().count == 2)
    }

    @Test func rollbackAndStaleReview() throws {
        let store = try WicketStore.inMemory()
        let league = try store.createLeague(name: "Cup", kind: .tournament)
        let a = try store.createTeam(leagueID: league.id, name: "A", colour: .saffron)
        let b = try store.createTeam(leagueID: league.id, name: "B", colour: .wicketGreen)
        let ground = try store.createGround(name: "Park")
        let first = record(league: league.id, home: a.id, away: b.id, ground: ground.id, offset: 0)
        let missing = record(league: league.id, home: a.id, away: "missing", ground: ground.id, offset: 86_400)
        let preview = try store.previewSchedule([first, missing])
        #expect(throws: WicketStoreError.parentNotFound) {
            try store.commitSchedule([first, missing], confirmedConflicts: preview)
        }
        #expect(try store.listFixtures().isEmpty) // SQL transaction rolled back
        _ = try store.createFixture(leagueID: league.id, name: "Already here", homeTeamID: a.id,
            awayTeamID: b.id, groundID: ground.id, participatingPlayerIDs: [],
            startsAt: first.startsAt, endsAt: first.endsAt, reminder: .none)
        #expect(throws: WicketStoreError.confirmationStale) {
            try store.commitSchedule([first], confirmedConflicts: [[]])
        }
        #expect(try store.listFixtures().count == 1)
    }

    private func record(league: LeagueID, home: TeamID, away: TeamID, ground: GroundID, offset: TimeInterval) -> FixtureRecord {
        let start = Date(timeIntervalSince1970: 1_800_000_000 + offset)
        return FixtureRecord(id: FixtureID(UUID().uuidString), leagueID: league, name: "Draft",
            homeTeamID: home, awayTeamID: away, groundID: ground,
            participatingPlayerIDs: [], startsAt: start,
            endsAt: start.addingTimeInterval(7_200), reminder: .none,
            createdAt: start, updatedAt: start)
    }
}
