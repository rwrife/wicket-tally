import Foundation
import Testing
@testable import WicketKit

@Suite("User-owned casual rule presets")
struct RulePresetTests {
    private func delivery(
        _ runs: Int = 0,
        extra: ExtraEvent? = nil,
        wicket: WicketEvent? = nil
    ) -> MatchEventKind {
        .ball(BallEvent(striker: "a", nonStriker: "b", bowler: "c", runsOffBat: runs, extra: extra, wicket: wicket))
    }

    private func replay(_ deliveries: [MatchEventKind], rules: MatchRules) -> MatchState {
        let kinds: [MatchEventKind] = [.inningsStarted(number: 1, batting: "A", bowling: "B")] + deliveries
        return MatchLedger(events: kinds.enumerated().map {
            MatchEvent(sequence: $0.offset, kind: $0.element)
        }).replay(rules: rules)
    }

    @Test("standard defaults keep all casual switches opt-in")
    func defaults() throws {
        let preset = RulePreset.standard
        #expect(preset.oversPerInnings == 20)
        #expect(preset.ballsPerOver == 6)
        #expect(preset.playersPerSide == 11)
        #expect(preset.rules.maxWickets == 10)
        #expect(preset.maxRunsPerOver == nil)
        #expect(preset.inningsRunCap == nil)
        #expect(!preset.oneHandCatchAllowed)
        #expect(preset.runPresets == [0, 1, 2, 3, 4, 6])
        #expect(MatchRules.standard == .t20)
        #expect(replay([delivery(12)], rules: preset.rules).scorecard[0].score == "12/0")
    }

    @Test("custom over lengths and innings caps", arguments: [1, 4, 6, 8, 12])
    func overLengths(balls: Int) throws {
        let rules = try RulePreset(name: "Local", oversPerInnings: 2, ballsPerOver: balls).rules
        let before = replay(Array(repeating: delivery(), count: balls * 2 - 1), rules: rules)
        #expect(before.status == .inProgress)
        #expect(before.scorecard[0].overs == "1.\(balls - 1)")
        let after = replay(Array(repeating: delivery(), count: balls * 2 + 1), rules: rules)
        #expect(after.status == .inningsBreak(target: 1))
        #expect(after.innings[0].legalDeliveries == balls * 2)
        #expect(after.scorecard[0].overs == "2.0")
    }

    struct CutCase: Sendable {
        let runs: [Int]
        let extra: ExtraEvent?
        let expectedRuns: Int
        let expectedBalls: Int
        let overs: String
    }

    @Test("run-cut over edges count the full crossing delivery exactly once", arguments: [
        CutCase(runs: [4, 5], extra: nil, expectedRuns: 9, expectedBalls: 2, overs: "0.2"),
        CutCase(runs: [4, 6], extra: nil, expectedRuns: 10, expectedBalls: 2, overs: "1.0"),
        CutCase(runs: [6, 6], extra: nil, expectedRuns: 12, expectedBalls: 2, overs: "1.0"),
        CutCase(runs: [0, 0, 0, 0, 4, 6], extra: nil, expectedRuns: 10, expectedBalls: 6, overs: "1.0"),
        CutCase(runs: [0, 0, 0, 0, 0, 0], extra: nil, expectedRuns: 0, expectedBalls: 6, overs: "1.0"),
        CutCase(runs: [0], extra: ExtraEvent(kind: .wide, runs: 10), expectedRuns: 10, expectedBalls: 0, overs: "1.0"),
        CutCase(runs: [6], extra: ExtraEvent(kind: .noBall, runs: 4), expectedRuns: 10, expectedBalls: 0, overs: "1.0"),
        CutCase(runs: [0], extra: ExtraEvent(kind: .bye, runs: 10), expectedRuns: 10, expectedBalls: 1, overs: "1.0"),
        CutCase(runs: [0], extra: ExtraEvent(kind: .legBye, runs: 10), expectedRuns: 10, expectedBalls: 1, overs: "1.0"),
        CutCase(runs: [25], extra: nil, expectedRuns: 25, expectedBalls: 1, overs: "1.0"),
    ])
    func runCut(testCase: CutCase) throws {
        let rules = try RulePreset(name: "Ten run cut", maxRunsPerOver: 10).rules
        let state = replay(testCase.runs.map { delivery($0, extra: testCase.extra) }, rules: rules)
        #expect(state.innings[0].runs == testCase.expectedRuns)
        #expect(state.innings[0].legalDeliveries == testCase.expectedBalls)
        #expect(state.scorecard[0].overs == testCase.overs)
    }

    @Test("cut overs reset their own run and ball totals and exhaust innings")
    func resetAndComplete() throws {
        let rules = try RulePreset(name: "Short", oversPerInnings: 2, maxRunsPerOver: 10).rules
        let state = replay([delivery(12), .overCompleted, delivery(4)], rules: rules)
        #expect(state.scorecard[0].overs == "1.1")
        #expect(state.innings[0].runsInCurrentOver == 4)
        #expect(state.innings[0].completedOvers == 1)
        let ended = replay([delivery(12), delivery(4), delivery(6), delivery(99)], rules: rules)
        #expect(ended.status == .inningsBreak(target: 23))
        #expect(ended.innings[0].runs == 22)
        #expect(ended.innings[0].legalDeliveries == 3)
        #expect(ended.scorecard[0].overs == "2.0")
    }

    @Test("remaining budget and rates account for cut overs, not just physical balls")
    func remainingBudget() throws {
        let rules = try RulePreset(name: "Short", oversPerInnings: 2, maxRunsPerOver: 10).rules
        let state = replay([
            delivery(20), .inningsEnded(reason: .declared),
            .inningsStarted(number: 2, batting: "B", bowling: "A"),
            delivery(4), delivery(6),
        ], rules: rules)
        #expect(state.ballsRemaining == .known(6))
        #expect(state.oversRemaining == .known(1))
        #expect(state.currentRunRate == .known(10))
        #expect(state.requiredRunRate == .known(11))
        #expect(state.innings[1].legalDeliveries == 2)
    }

    @Test("innings run cap counts full bat runs, extras, and penalties", arguments: [9, 10, 12])
    func inningsCap(runs: Int) throws {
        let rules = try RulePreset(name: "Cap", inningsRunCap: 10).rules
        let inputs = [
            delivery(runs),
            delivery(extra: ExtraEvent(kind: .wide, runs: runs)),
            MatchEventKind.penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: runs, reason: "Recorded")),
        ]
        for input in inputs {
            let state = replay([input], rules: rules)
            #expect(state.innings[0].runs == runs)
            #expect(state.innings[0].isComplete == (runs >= 10))
        }
    }

    @Test("standalone penalties do not consume run-cut overs")
    func standalonePenalties() throws {
        let rules = try RulePreset(name: "Cut", maxRunsPerOver: 10).rules
        let state = replay([
            .penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: 10, reason: "Recorded")),
            .penaltyRuns(PenaltyRunEvent(awardedToBatting: false, runs: 10, reason: "Recorded")),
            delivery(1),
        ], rules: rules)
        #expect(state.innings[0].runs == 11)
        #expect(state.innings[0].runsInCurrentOver == 1)
        #expect(state.scorecard[0].overs == "0.1")
    }

    @Test("score adjustments can reach the innings cap without consuming an over")
    func adjustmentCap() throws {
        let rules = try RulePreset(name: "Cap", maxRunsPerOver: 10, inningsRunCap: 10).rules
        let state = replay([
            delivery(4),
            .correction(CorrectionEvent(
                action: .scoreAdjustment(ScoreAdjustment(runsDelta: 6)),
                reason: "Recorded adjustment", provenance: "Scorer"
            )),
        ], rules: rules)
        #expect(state.status == .inningsBreak(target: 11))
        #expect(state.innings[0].runsInCurrentOver == 4)
        #expect(state.scorecard[0].overs == "0.1")
    }

    @Test("illegal deliveries alone can exhaust the final run-cut over")
    func noLegalBalls() throws {
        let rules = try RulePreset(name: "Short", oversPerInnings: 1, maxRunsPerOver: 5).rules
        let state = replay([
            delivery(extra: ExtraEvent(kind: .wide, runs: 3)),
            delivery(extra: ExtraEvent(kind: .noBall, runs: 3)),
            delivery(6),
        ], rules: rules)
        #expect(state.status == .inningsBreak(target: 7))
        #expect(state.innings[0].legalDeliveries == 0)
        #expect(state.scorecard[0].overs == "1.0")
        #expect(state.currentRunRate == .known(6))
    }

    @Test("small sides finish all-out and retain correct winning wicket margins", arguments: [2, 3, 6, 11])
    func teamSizes(players: Int) throws {
        let rules = try RulePreset(name: "Small side", playersPerSide: players).rules
        let wicket = WicketEvent(kind: .bowled, dismissed: "a")
        let state = replay(Array(repeating: delivery(wicket: wicket), count: players), rules: rules)
        #expect(state.innings[0].wickets == players - 1)
        #expect(state.innings[0].legalDeliveries == players - 1)
        #expect(state.status == .inningsBreak(target: 1))
        let chase = replay([
            .inningsEnded(reason: .declared),
            .inningsStarted(number: 2, batting: "B", bowling: "A"),
            delivery(1),
        ], rules: rules)
        #expect(chase.status == .completed(.wonByWickets(team: "B", wickets: players - 1)))
    }

    @Test("one-hand catch requires the opt-in and retains existing extra rules", arguments: [false, true])
    func oneHandCatch(enabled: Bool) throws {
        let rules = try RulePreset(name: "Catch", oneHandCatchAllowed: enabled).rules
        let catchEvent = WicketEvent(kind: .caught, dismissed: "a", isOneHandCatch: true)
        for extra in [nil, ExtraEvent(kind: .bye, runs: 1), ExtraEvent(kind: .legBye, runs: 1)] {
            #expect(replay([delivery(extra: extra, wicket: catchEvent)], rules: rules).innings[0].wickets == (enabled ? 1 : 0))
        }
        for extra in [ExtraEvent(kind: .wide, runs: 1), ExtraEvent(kind: .noBall, runs: 1)] {
            #expect(replay([delivery(extra: extra, wicket: catchEvent)], rules: rules).innings[0].wickets == 0)
        }
        #expect(replay([delivery(wicket: WicketEvent(kind: .caught, dismissed: "a"))], rules: rules).innings[0].wickets == 1)
    }

    @Test("run button order is user-owned without truncating recorded runs", arguments: [[0], [6, 4, 2, 0], [0, 7, 12]])
    func runButtons(buttons: [Int]) throws {
        let preset = try RulePreset(name: "Buttons", runPresets: buttons)
        #expect(preset.rules.runPresets == buttons)
        #expect(replay([delivery(13)], rules: preset.rules).innings[0].runs == 13)
    }

    @Test("invalid run buttons fail explicitly", arguments: [[], [-1], [13], [0, 0]])
    func invalidButtons(buttons: [Int]) {
        #expect(throws: RulePresetError.invalidRunPresets) {
            try RulePreset(name: "Invalid", runPresets: buttons)
        }
    }

    @Test("invalid bounds fail on construction and decoding", arguments: [
        ("oversPerInnings", 0), ("oversPerInnings", 51),
        ("ballsPerOver", 0), ("ballsPerOver", 13),
        ("playersPerSide", 1), ("playersPerSide", 12),
        ("maxRunsPerOver", 0), ("maxRunsPerOver", 101),
        ("inningsRunCap", 0), ("inningsRunCap", 1001),
    ])
    func invalidBounds(field: String, value: Int) throws {
        #expect(throws: (any Error).self) {
            try RulePreset(
                name: "Invalid",
                oversPerInnings: field == "oversPerInnings" ? value : 20,
                ballsPerOver: field == "ballsPerOver" ? value : 6,
                playersPerSide: field == "playersPerSide" ? value : 11,
                maxRunsPerOver: field == "maxRunsPerOver" ? value : nil,
                inningsRunCap: field == "inningsRunCap" ? value : nil
            )
        }
        let data = try JSONEncoder().encode(RulePreset.standard)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object[field] = value
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(RulePreset.self, from: invalid) }
    }

    @Test("blank or oversized names are rejected", arguments: ["", " \n", String(repeating: "a", count: 81)])
    func invalidNames(name: String) {
        #expect(throws: RulePresetError.invalidName) { try RulePreset(name: name) }
    }

    @Test("preset and match snapshots round-trip all knobs")
    func roundTrip() throws {
        let preset = try RulePreset(name: "Weekend", oversPerInnings: 5, ballsPerOver: 4, playersPerSide: 6,
                                    maxRunsPerOver: 10, inningsRunCap: 50, runPresets: [0, 1, 4, 6], oneHandCatchAllowed: true)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        #expect(try decoder.decode(RulePreset.self, from: encoder.encode(preset)) == preset)
        #expect(try decoder.decode(MatchRules.self, from: encoder.encode(preset.rules)) == preset.rules)
        let state = replay([delivery(12)], rules: preset.rules)
        #expect(try decoder.decode(MatchState.self, from: encoder.encode(state)) == state)
        let wicket = WicketEvent(kind: .caught, dismissed: "a", isOneHandCatch: true)
        #expect(try decoder.decode(WicketEvent.self, from: encoder.encode(wicket)) == wicket)
        #expect(preset.summary.contains("10 runs cut/over"))
        #expect(preset.rules.presetName == "Weekend")
    }

    @Test("legacy rules, wickets, and innings states decode with standard behavior")
    func legacyDecoding() throws {
        let decoder = JSONDecoder()
        let rules = try decoder.decode(MatchRules.self, from: Data(#"{"oversPerInnings":10,"ballsPerOver":6,"maxWickets":10}"#.utf8))
        #expect(rules == .t10)
        #expect(rules.maxRunsPerOver == nil)
        #expect(rules.runPresets == RulePreset.standardRunPresets)
        #expect(!rules.oneHandCatchAllowed)
        let wicket = try decoder.decode(WicketEvent.self, from: Data(#"{"kind":"caught","dismissed":{"rawValue":"a"}}"#.utf8))
        #expect(!wicket.isOneHandCatch)
        let innings = try decoder.decode(InningsState.self, from: Data(#"{"number":1,"battingTeam":{"rawValue":"A"},"bowlingTeam":{"rawValue":"B"},"runs":4,"wickets":0,"legalDeliveries":9,"isComplete":false}"#.utf8))
        #expect(innings.completedOvers == nil)
        #expect(innings.oversString(ballsPerOver: 4) == "2.1")
        #expect(innings.consumedBallBudget(ballsPerOver: 4) == 9)
    }

    @Test("contradictory preset snapshots fail decoding rather than changing the contract")
    func inconsistentSnapshot() throws {
        let preset = try RulePreset(name: "Short", oversPerInnings: 5, playersPerSide: 6)
        let encoded = try JSONEncoder().encode(preset.rules)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["maxWickets"] = 10
        let invalid = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(MatchRules.self, from: invalid) }
    }

    @Test("corrected deliveries recompute run cuts without changing the raw ledger")
    func correctionReplay() throws {
        let rules = try RulePreset(name: "Cut", oversPerInnings: 1, maxRunsPerOver: 10).rules
        let start = MatchEvent(sequence: 0, kind: .inningsStarted(number: 1, batting: "A", bowling: "B"))
        let mistaken = MatchEvent(sequence: 1, kind: delivery(12))
        let following = MatchEvent(sequence: 2, kind: delivery(2))
        for action in [
            CorrectionAction.invalidate(target: mistaken.id),
            CorrectionAction.replace(target: mistaken.id, with: delivery(4)),
        ] {
            let correction = MatchEvent(sequence: 3, kind: .correction(CorrectionEvent(action: action, reason: "Correction", provenance: "Scorer")))
            let ledger = MatchLedger(events: [start, mistaken, following, correction])
            let state = ledger.replay(rules: rules)
            #expect(state.status == .inProgress)
            #expect(state.innings[0].completedOvers == 0)
            #expect(ledger.events.count == 4)
            #expect(state == ledger.replay(rules: rules))
        }
    }

    @Test("chase wins on the same event as a run cutoff or innings cap", arguments: [false, true])
    func chaseAtCutoff(illegal: Bool) throws {
        let rules = try RulePreset(name: "Cut", oversPerInnings: 1, maxRunsPerOver: 10, inningsRunCap: 10).rules
        let state = replay([
            delivery(9), .inningsEnded(reason: .declared),
            .inningsStarted(number: 2, batting: "B", bowling: "A"),
            delivery(illegal ? 9 : 10, extra: illegal ? ExtraEvent(kind: .noBall, runs: 1) : nil),
        ], rules: rules)
        #expect(state.status == .completed(.wonByWickets(team: "B", wickets: 10)))
        #expect(state.innings[1].runs == 10)
    }
}
