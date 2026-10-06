import Foundation
import Testing
import WicketKit

@Suite("Ad-hoc match plan")
struct AdhocMatchPlanTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    @Test("trims names and derives the fixture name and window")
    func derivation() throws {
        let plan = try AdhocMatchPlan(
            homeName: "  Street Kings  ",
            awayName: "Gully XI\n",
            rules: MatchRules(oversPerInnings: 6),
            startingAt: start
        )
        #expect(plan.homeName == "Street Kings")
        #expect(plan.awayName == "Gully XI")
        #expect(plan.fixtureName == "Street Kings vs Gully XI")
        #expect(plan.startsAt == start)
        #expect(plan.endsAt == start.addingTimeInterval(4 * 60 * 60))
        #expect(plan.rules.oversPerInnings == 6)
    }

    @Test("summary states the sides and the copied rules, never a verdict")
    func summary() throws {
        let plan = try AdhocMatchPlan(
            homeName: "Office A",
            awayName: "Office B",
            rules: MatchRules(oversPerInnings: 10),
            startingAt: start
        )
        #expect(plan.summary.contains("Office A vs Office B"))
        #expect(plan.summary.contains("10 overs"))
    }

    @Test("blank side names are rejected per side")
    func blankNames() {
        #expect(throws: AdhocMatchPlanError.homeNameRequired) {
            try AdhocMatchPlan(homeName: "   ", awayName: "B", rules: .t20, startingAt: start)
        }
        #expect(throws: AdhocMatchPlanError.awayNameRequired) {
            try AdhocMatchPlan(homeName: "A", awayName: "\n ", rules: .t20, startingAt: start)
        }
    }

    @Test("overlong side names are rejected per side")
    func longNames() {
        let tooLong = String(repeating: "x", count: AdhocMatchPlan.maxNameLength + 1)
        #expect(throws: AdhocMatchPlanError.homeNameTooLong) {
            try AdhocMatchPlan(homeName: tooLong, awayName: "B", rules: .t20, startingAt: start)
        }
        #expect(throws: AdhocMatchPlanError.awayNameTooLong) {
            try AdhocMatchPlan(homeName: "A", awayName: tooLong, rules: .t20, startingAt: start)
        }
    }

    @Test("exactly-maximum names are accepted")
    func maxNames() throws {
        let edge = String(repeating: "y", count: AdhocMatchPlan.maxNameLength)
        let plan = try AdhocMatchPlan(homeName: edge, awayName: edge, rules: .t20, startingAt: start)
        #expect(plan.homeName.count == AdhocMatchPlan.maxNameLength)
    }

    @Test("error descriptions exist for every case")
    func errorDescriptions() {
        for error in [
            AdhocMatchPlanError.homeNameRequired,
            .awayNameRequired,
            .homeNameTooLong,
            .awayNameTooLong,
        ] {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
