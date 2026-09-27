import Foundation
import Testing
@testable import WicketKit

@Suite("Fixture scheduling")
struct FixtureSchedulingTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("conflict matrix identifies shared player and ground without silently blocking")
    func conflictMatrix() {
        let existing = fixture(
            id: "existing",
            name: "Park semifinal",
            groundID: "azad-maidan",
            players: ["p1", "p2"],
            start: date("2026-10-04T09:00:00Z"),
            end: date("2026-10-04T11:00:00Z")
        )
        let cases: [(String, GroundID, Set<PlayerID>, Date, Date, Set<FixtureConflictReason>)] = [
            ("player only", "other-ground", ["p2"], date("2026-10-04T10:00:00Z"), date("2026-10-04T12:00:00Z"), [.player("p2")]),
            ("ground only", "azad-maidan", ["p3"], date("2026-10-04T10:00:00Z"), date("2026-10-04T12:00:00Z"), [.ground("azad-maidan")]),
            ("player and ground", "azad-maidan", ["p1"], date("2026-10-04T10:00:00Z"), date("2026-10-04T12:00:00Z"), [.ground("azad-maidan"), .player("p1")]),
            ("different resources", "other-ground", ["p3"], date("2026-10-04T10:00:00Z"), date("2026-10-04T12:00:00Z"), []),
            ("touching slot boundary", "azad-maidan", ["p1"], date("2026-10-04T11:00:00Z"), date("2026-10-04T12:00:00Z"), []),
        ]

        for (label, groundID, players, start, end, expected) in cases {
            let candidate = fixture(
                id: FixtureID("candidate-\(label)"),
                name: "Candidate",
                groundID: groundID,
                players: players,
                start: start,
                end: end
            )
            let conflicts = FixtureConflictDetector.conflicts(for: candidate, among: [existing])
            #expect(Set(conflicts.flatMap { $0.reasons }) == expected, Comment(rawValue: label))
            if expected.isEmpty {
                #expect(conflicts.isEmpty, Comment(rawValue: label))
            } else {
                #expect(conflicts.map { $0.clashingFixtureName } == ["Park semifinal"], Comment(rawValue: label))
                #expect(conflicts[0].explanation.contains("Park semifinal"), Comment(rawValue: label))
            }
        }
    }

    @Test("conflicts are deterministic and ignore the fixture being edited")
    func deterministicConflictOrdering() {
        let candidate = fixture(id: "editing", name: "Edited match", groundID: "g1", players: ["p1"], start: date("2026-10-04T10:00:00Z"), end: date("2026-10-04T11:00:00Z"))
        let laterID = fixture(id: "z", name: "Zulu match", groundID: "g1", players: [], start: date("2026-10-04T10:00:00Z"), end: date("2026-10-04T12:00:00Z"))
        let earlierID = fixture(id: "a", name: "Alpha match", groundID: "g1", players: [], start: date("2026-10-04T10:00:00Z"), end: date("2026-10-04T12:00:00Z"))

        let conflicts = FixtureConflictDetector.conflicts(for: candidate, among: [laterID, candidate, earlierID])
        #expect(conflicts.map { $0.clashingFixtureName } == ["Alpha match", "Zulu match"])
    }

    @Test("notification dates remain exact across daylight-saving transitions")
    func daylightSavingSafeReminderDates() throws {
        var newYork = calendar
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        let springStart = date("2026-03-08T03:30:00-04:00")
        let springReminder = try #require(FixtureReminder.oneHourBefore.reminderDate(for: springStart, calendar: newYork))
        #expect(springStart.timeIntervalSince(springReminder) == 3_600)

        let autumnStart = date("2026-11-01T01:30:00-05:00")
        let autumnReminder = try #require(FixtureReminder.oneHourBefore.reminderDate(for: autumnStart, calendar: newYork))
        #expect(autumnStart.timeIntervalSince(autumnReminder) == 3_600)
        #expect(FixtureReminder.none.reminderDate(for: springStart, calendar: newYork) == nil)
    }

    @Test("fixture validates chronological slots")
    func slotValidation() {
        #expect(throws: FixtureValidationError.invalidTimeSlot) {
            try FixtureRecord.validated(
                id: "bad",
                leagueID: nil,
                name: "Bad slot",
                homeTeamID: "home",
                awayTeamID: "away",
                groundID: "g1",
                participatingPlayerIDs: [],
                startsAt: date("2026-10-04T11:00:00Z"),
                endsAt: date("2026-10-04T10:00:00Z"),
                reminder: .none,
                createdAt: date("2026-01-01T00:00:00Z"),
                updatedAt: date("2026-01-01T00:00:00Z")
            )
        }
    }

    @Test("fixture rejects a team playing itself")
    func sameTeamValidation() {
        #expect(throws: FixtureValidationError.sameTeam) {
            try FixtureRecord.validated(
                id: "derby",
                leagueID: nil,
                name: "Self derby",
                homeTeamID: "same",
                awayTeamID: "same",
                groundID: "g1",
                participatingPlayerIDs: [],
                startsAt: date("2026-10-04T09:00:00Z"),
                endsAt: date("2026-10-04T11:00:00Z"),
                reminder: .none,
                createdAt: date("2026-01-01T00:00:00Z"),
                updatedAt: date("2026-01-01T00:00:00Z")
            )
        }
    }

    @Test("fixture validation accepts a well-formed standalone fixture")
    func validatedAccepts() throws {
        let record = try FixtureRecord.validated(
            id: "ok",
            leagueID: nil,
            name: "Weekend friendly",
            homeTeamID: "home",
            awayTeamID: "away",
            groundID: "g1",
            participatingPlayerIDs: ["p1"],
            startsAt: date("2026-10-04T09:00:00Z"),
            endsAt: date("2026-10-04T11:00:00Z"),
            reminder: .fifteenMinutesBefore,
            createdAt: date("2026-01-01T00:00:00Z"),
            updatedAt: date("2026-01-01T00:00:00Z")
        )
        #expect(record.name == "Weekend friendly")
        #expect(record.leagueID == nil)
        #expect(record.reminder == .fifteenMinutesBefore)
    }

    @Test("reminder offsets and display names cover every option")
    func reminderOptions() throws {
        let start = date("2026-10-04T09:00:00Z")
        #expect(FixtureReminder.allCases.count == 4)
        #expect(FixtureReminder.none.displayName == "No reminder")
        #expect(FixtureReminder.fifteenMinutesBefore.displayName == "15 minutes before")
        #expect(FixtureReminder.oneHourBefore.displayName == "1 hour before")
        #expect(FixtureReminder.oneDayBefore.displayName == "1 day before")

        let fifteen = try #require(FixtureReminder.fifteenMinutesBefore.reminderDate(for: start, calendar: calendar))
        #expect(start.timeIntervalSince(fifteen) == 900)
        let day = try #require(FixtureReminder.oneDayBefore.reminderDate(for: start, calendar: calendar))
        #expect(start.timeIntervalSince(day) == 86_400)
    }

    @Test("conflict explanations phrase ground and player counts")
    func conflictExplanations() {
        let groundOnly = FixtureConflict(
            clashingFixtureID: "f1",
            clashingFixtureName: "Ground clash",
            reasons: [.ground("g1")]
        )
        #expect(groundOnly.explanation == "Clashes with Ground clash: same ground.")

        let playerOnly = FixtureConflict(
            clashingFixtureID: "f2",
            clashingFixtureName: "Player clash",
            reasons: [.player("p1")]
        )
        #expect(playerOnly.explanation == "Clashes with Player clash: 1 double-booked player.")

        let both = FixtureConflict(
            clashingFixtureID: "f3",
            clashingFixtureName: "Full clash",
            reasons: [.ground("g1"), .player("p1"), .player("p2")]
        )
        #expect(both.explanation == "Clashes with Full clash: same ground and 2 double-booked players.")
    }

    private func fixture(
        id: FixtureID,
        name: String,
        groundID: GroundID,
        players: Set<PlayerID>,
        start: Date,
        end: Date
    ) -> FixtureRecord {
        FixtureRecord(
            id: id,
            leagueID: nil,
            name: name,
            homeTeamID: "home",
            awayTeamID: "away",
            groundID: groundID,
            participatingPlayerIDs: players,
            startsAt: start,
            endsAt: end,
            reminder: .none,
            createdAt: date("2026-01-01T00:00:00Z"),
            updatedAt: date("2026-01-01T00:00:00Z")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private extension FixtureConflictReason {
    static func ground(_ value: String) -> FixtureConflictReason { .ground(GroundID(value)) }
    static func player(_ value: String) -> FixtureConflictReason { .player(PlayerID(value)) }
}
