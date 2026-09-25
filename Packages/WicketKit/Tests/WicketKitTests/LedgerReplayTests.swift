import Testing
@testable import WicketKit

private let teamA: TeamID = "A"
private let teamB: TeamID = "B"
private let batter1: PlayerID = "b1"
private let batter2: PlayerID = "b2"
private let bowler: PlayerID = "p1"

private func start(_ sequence: Int, innings: Int, batting: TeamID, bowling: TeamID) -> MatchEvent {
    MatchEvent(sequence: sequence, kind: .inningsStarted(number: innings, batting: batting, bowling: bowling))
}

private func ball(
    _ sequence: Int,
    batRuns: Int = 0,
    extra: ExtraEvent? = nil,
    wicket: WicketEvent? = nil
) -> MatchEvent {
    MatchEvent(
        sequence: sequence,
        kind: .ball(
            BallEvent(
                striker: batter1,
                nonStriker: batter2,
                bowler: bowler,
                runsOffBat: batRuns,
                extra: extra,
                wicket: wicket
            )
        )
    )
}

@Suite("Append-only ledger replay")
struct LedgerReplayTests {
    @Test("empty ledger is unknown-safe and not started")
    func emptyLedger() {
        let state = MatchLedger(events: []).replay(rules: .t20)

        #expect(state.status == .notStarted)
        #expect(state.innings.isEmpty)
        #expect(state.currentRunRate == .unknown)
        #expect(state.requiredRunRate == .unknown)
        #expect(state.ballsRemaining == .unknown)
        #expect(state.oversRemaining == .unknown)
        #expect(state.scorecard.isEmpty)
    }

    @Test("standard format presets are deterministic")
    func formatPresets() {
        #expect(MatchRules.t10.maxLegalDeliveriesPerInnings == 60)
        #expect(MatchRules.t20.maxLegalDeliveriesPerInnings == 120)
        #expect(MatchRules.odi.maxLegalDeliveriesPerInnings == 300)
        #expect(MatchRules(oversPerInnings: 0, ballsPerOver: 0, maxWickets: 0) == MatchRules(oversPerInnings: 1, ballsPerOver: 1, maxWickets: 1))
    }

    @Test("events are ordered by sequence before replay")
    func sequenceOrdering() {
        let events = [ball(3, batRuns: 4), start(1, innings: 1, batting: teamA, bowling: teamB), ball(2, batRuns: 1)]
        let ledger = MatchLedger(events: events)
        let state = ledger.replay(rules: MatchRules(oversPerInnings: 2))

        #expect(ledger.events.map(\.sequence) == [1, 2, 3])
        #expect(state.innings[0].runs == 5)
        #expect(state.innings[0].legalDeliveries == 2)
    }

    @Test("full recompute from the same ledger is idempotent")
    func replayIdempotent() {
        let events = [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, batRuns: 4),
            ball(3, extra: ExtraEvent(kind: .wide, runs: 2)),
            ball(4, batRuns: 1),
        ]
        let ledger = MatchLedger(events: events)

        #expect(ledger.replay(rules: .t10) == ledger.replay(rules: .t10))
        #expect(ledger.events == events)
    }

    @Test("a logged invalidation correction keeps raw history and removes score effect")
    func invalidationCorrection() {
        let mistaken = ball(2, batRuns: 6)
        let correction = MatchEvent(
            sequence: 3,
            kind: .correction(
                CorrectionEvent(
                    action: .invalidate(target: mistaken.id),
                    reason: "boundary entered twice",
                    provenance: "scorer-review"
                )
            )
        )
        let ledger = MatchLedger(events: [start(1, innings: 1, batting: teamA, bowling: teamB), mistaken, correction])
        let state = ledger.replay(rules: .t10)

        #expect(ledger.events.count == 3)
        #expect(state.innings[0].runs == 0)
        #expect(state.innings[0].legalDeliveries == 0)
    }

    @Test("a replacement correction changes one prior delivery with provenance")
    func replacementCorrection() {
        let mistaken = ball(2, batRuns: 6)
        let correctedBall = MatchEventKind.ball(
            BallEvent(striker: batter1, nonStriker: batter2, bowler: bowler, runsOffBat: 4)
        )
        let correction = MatchEvent(
            sequence: 3,
            kind: .correction(
                CorrectionEvent(
                    action: .replace(target: mistaken.id, with: correctedBall),
                    reason: "umpire signalled four",
                    provenance: "umpire-confirmed"
                )
            )
        )
        let state = MatchLedger(events: [start(1, innings: 1, batting: teamA, bowling: teamB), mistaken, correction]).replay(rules: .t10)

        #expect(state.innings[0].runs == 4)
        #expect(state.innings[0].legalDeliveries == 1)
    }

    @Test("a direct score adjustment is appended and clamped at zero")
    func scoreAdjustment() {
        let correction = MatchEvent(
            sequence: 3,
            kind: .correction(
                CorrectionEvent(
                    action: .scoreAdjustment(ScoreAdjustment(runsDelta: -10, wicketsDelta: 1)),
                    reason: "remove invalid penalty",
                    provenance: "match-official"
                )
            )
        )
        let state = MatchLedger(events: [start(1, innings: 1, batting: teamA, bowling: teamB), ball(2, batRuns: 4), correction]).replay(rules: .t10)

        #expect(state.innings[0].runs == 0)
        #expect(state.innings[0].wickets == 1)
    }

    @Test("replacement targeting a correction does not erase correction semantics")
    func correctionCannotBeReplacedWithBall() {
        let adjustment = MatchEvent(
            sequence: 2,
            kind: .correction(
                CorrectionEvent(
                    action: .scoreAdjustment(ScoreAdjustment(runsDelta: 2)),
                    reason: "manual add",
                    provenance: "official"
                )
            )
        )
        let replacement = MatchEvent(
            sequence: 3,
            kind: .correction(
                CorrectionEvent(
                    action: .replace(target: adjustment.id, with: .ball(BallEvent(striker: nil, nonStriker: nil, bowler: nil, runsOffBat: 6))),
                    reason: "invalid attempt",
                    provenance: "audit"
                )
            )
        )
        let state = MatchLedger(events: [start(1, innings: 1, batting: teamA, bowling: teamB), adjustment, replacement]).replay(rules: .t10)

        #expect(state.innings[0].runs == 2)
        #expect(state.innings[0].legalDeliveries == 0)
    }
}

@Suite("Extras, penalties, and over boundaries")
struct ScoringRulesTests {
    struct ExtraCase: Sendable {
        let name: String
        let event: ExtraEvent
        let batRuns: Int
        let expectedRuns: Int
        let expectedLegalBalls: Int
    }

    @Test(
        "extras are scored against table-driven fixtures",
        arguments: [
            ExtraCase(name: "wide", event: ExtraEvent(kind: .wide, runs: 1), batRuns: 0, expectedRuns: 1, expectedLegalBalls: 0),
            ExtraCase(name: "multi-wide", event: ExtraEvent(kind: .wide, runs: 3), batRuns: 0, expectedRuns: 3, expectedLegalBalls: 0),
            ExtraCase(name: "no-ball boundary", event: ExtraEvent(kind: .noBall, runs: 1), batRuns: 4, expectedRuns: 5, expectedLegalBalls: 0),
            ExtraCase(name: "bye", event: ExtraEvent(kind: .bye, runs: 2), batRuns: 0, expectedRuns: 2, expectedLegalBalls: 1),
            ExtraCase(name: "leg-bye", event: ExtraEvent(kind: .legBye, runs: 1), batRuns: 0, expectedRuns: 1, expectedLegalBalls: 1),
        ]
    )
    func extraTable(testCase: ExtraCase) {
        let state = MatchLedger(events: [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, batRuns: testCase.batRuns, extra: testCase.event),
        ]).replay(rules: MatchRules(oversPerInnings: 2))

        #expect(state.innings[0].runs == testCase.expectedRuns, Comment(rawValue: testCase.name))
        #expect(state.innings[0].legalDeliveries == testCase.expectedLegalBalls, Comment(rawValue: testCase.name))
    }

    @Test("negative bat or extra inputs clamp to zero")
    func negativeInputClamps() {
        let delivery = BallEvent(striker: nil, nonStriker: nil, bowler: nil, runsOffBat: -4, extra: ExtraEvent(kind: .wide, runs: -1))
        #expect(delivery.runsOffBat == 0)
        #expect(delivery.extraRuns == 0)
        #expect(delivery.totalRuns == 0)
    }

    @Test("over completes only after six legal deliveries despite wides and no-balls")
    func overBoundary() {
        var events = [start(1, innings: 1, batting: teamA, bowling: teamB)]
        events.append(ball(2, extra: ExtraEvent(kind: .wide, runs: 1)))
        events.append(ball(3, extra: ExtraEvent(kind: .noBall, runs: 1)))
        for index in 0..<6 {
            events.append(ball(4 + index, batRuns: index == 5 ? 4 : 0))
        }

        let state = MatchLedger(events: events).replay(rules: MatchRules(oversPerInnings: 1))
        #expect(state.innings[0].legalDeliveries == 6)
        #expect(state.innings[0].runs == 6)
        #expect(state.scorecard[0].overs == "1.0")
        #expect(state.status == .inningsBreak(target: 7))
    }

    @Test("batting and non-batting penalty runs are accounted separately")
    func penalties() {
        let events: [MatchEvent] = [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            MatchEvent(sequence: 2, kind: .penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: 5, reason: "fielding penalty"))),
            MatchEvent(sequence: 3, kind: .penaltyRuns(PenaltyRunEvent(awardedToBatting: false, runs: 5, reason: "batting penalty"))),
        ]
        let state = MatchLedger(events: events).replay(rules: .t10)

        #expect(state.innings[0].runs == 5)
        #expect(state.innings[0].legalDeliveries == 0)
    }

    @Test("wickets clamp at the configured maximum")
    func maxWickets() {
        let wicket = WicketEvent(kind: .bowled, dismissed: batter1)
        let events = [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, wicket: wicket),
            ball(3, wicket: wicket),
        ]
        let state = MatchLedger(events: events).replay(rules: MatchRules(oversPerInnings: 5, maxWickets: 1))

        #expect(state.innings[0].wickets == 1)
        #expect(state.innings[0].legalDeliveries == 1)
        #expect(state.status == .inningsBreak(target: 1))
    }
}

@Suite("Results and run-rate derivations")
struct ResultDerivationTests {
    @Test("run-rate is unknown before a legal ball")
    func unknownRateAtStart() {
        let state = MatchLedger(events: [start(1, innings: 1, batting: teamA, bowling: teamB)]).replay(rules: .t20)
        #expect(state.currentRunRate == .unknown)
        #expect(UnknownSafeFormatter.rateString(state.currentRunRate) == "unknown")
    }

    @Test("current run rate derives from legal deliveries")
    func currentRunRate() {
        let state = MatchLedger(events: [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, batRuns: 4), ball(3, batRuns: 2), ball(4),
        ]).replay(rules: .t20)

        #expect(state.currentRunRate == .known(12))
        #expect(UnknownSafeFormatter.rateString(state.currentRunRate) == "12.00")
    }

    @Test("required run rate and balls remaining derive only in a live chase")
    func requiredRunRate() {
        let rules = MatchRules(oversPerInnings: 2)
        var events = [start(1, innings: 1, batting: teamA, bowling: teamB)]
        for index in 0..<12 { events.append(ball(2 + index, batRuns: index == 0 ? 11 : 0)) }
        events.append(start(14, innings: 2, batting: teamB, bowling: teamA))
        events.append(ball(15, batRuns: 2))
        events.append(ball(16, batRuns: 1))

        let state = MatchLedger(events: events).replay(rules: rules)
        let rrr = state.requiredRunRate
        if case let .known(value) = rrr {
            #expect(abs(value - 5.4) < 0.0001)
        } else {
            Issue.record("expected known RRR, got \(rrr)")
        }
        #expect(state.ballsRemaining == .known(10))
        #expect(state.oversRemaining == .known(Double(10) / 6.0))
        #expect(state.status == .inProgress)
    }

    @Test("chase ending on a boundary is an immediate wickets win")
    func boundaryWin() {
        let rules = MatchRules(oversPerInnings: 1, maxWickets: 2)
        let events = firstInnings(runs: 5, rules: rules) + [
            start(8, innings: 2, batting: teamB, bowling: teamA),
            ball(9, batRuns: 6),
        ]
        let state = MatchLedger(events: events).replay(rules: rules)

        #expect(state.innings[1].runs == 6)
        #expect(state.innings[1].legalDeliveries == 1)
        #expect(state.status == .completed(.wonByWickets(team: teamB, wickets: 2)))
        #expect(state.requiredRunRate == .unknown)
        #expect(state.ballsRemaining == .unknown)
    }

    @Test("chase ending on a no-ball is immediate and consumes no legal delivery")
    func noBallWin() {
        let rules = MatchRules(oversPerInnings: 1, maxWickets: 2)
        let events = firstInnings(runs: 1, rules: rules) + [
            start(8, innings: 2, batting: teamB, bowling: teamA),
            ball(9, batRuns: 1, extra: ExtraEvent(kind: .noBall, runs: 1)),
        ]
        let state = MatchLedger(events: events).replay(rules: rules)

        #expect(state.innings[1].runs == 2)
        #expect(state.innings[1].legalDeliveries == 0)
        #expect(state.status == .completed(.wonByWickets(team: teamB, wickets: 2)))
    }

    @Test("defending team wins by runs")
    func winByRuns() {
        let rules = MatchRules(oversPerInnings: 1, maxWickets: 2)
        var events = firstInnings(runs: 8, rules: rules)
        events.append(start(8, innings: 2, batting: teamB, bowling: teamA))
        for index in 0..<6 { events.append(ball(9 + index, batRuns: index == 0 ? 3 : 0)) }
        let state = MatchLedger(events: events).replay(rules: rules)

        #expect(state.status == .completed(.wonByRuns(team: teamA, runs: 5)))
    }

    @Test("equal scores at innings completion derive tie")
    func tie() {
        let rules = MatchRules(oversPerInnings: 1, maxWickets: 2)
        var events = firstInnings(runs: 4, rules: rules)
        events.append(start(8, innings: 2, batting: teamB, bowling: teamA))
        for index in 0..<6 { events.append(ball(9 + index, batRuns: index == 0 ? 4 : 0)) }
        let state = MatchLedger(events: events).replay(rules: rules)

        #expect(state.status == .completed(.tie))
    }

    @Test("abandoned match derives no result, never a guessed verdict")
    func noResult() {
        let events = [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, batRuns: 4),
            MatchEvent(sequence: 3, kind: .matchAbandoned(reason: "unsafe ground")),
        ]
        let state = MatchLedger(events: events).replay(rules: .t20)
        #expect(state.status == .completed(.noResult(reason: "unsafe ground")))
    }

    @Test("manual innings end creates innings break target")
    func manualInningsEnd() {
        let events = [
            start(1, innings: 1, batting: teamA, bowling: teamB),
            ball(2, batRuns: 4),
            MatchEvent(sequence: 3, kind: .overCompleted),
            MatchEvent(sequence: 4, kind: .inningsEnded(reason: .declared)),
        ]
        let state = MatchLedger(events: events).replay(rules: .t20)
        #expect(state.status == .inningsBreak(target: 5))
        #expect(state.scorecard == [ScorecardLine(innings: 1, team: teamA, score: "4/0", overs: "0.1")])
    }

    @Test("wickets on no-balls and wides respect cricket dismissal rules")
    func wicketRulesOnExtras() {
        let caught = WicketEvent(kind: .caught, dismissed: batter1)
        let runOut = WicketEvent(kind: .runOut, dismissed: batter1)
        let stumped = WicketEvent(kind: .stumped, dismissed: batter1)

        // Caught off a no-ball does not count as a wicket
        let noBallCaught = BallEvent(striker: batter1, nonStriker: batter2, bowler: bowler, runsOffBat: 0, extra: ExtraEvent(kind: .noBall, runs: 1), wicket: caught)
        #expect(!noBallCaught.countsAsWicket)

        // Run out off a no-ball DOES count as a wicket
        let noBallRunOut = BallEvent(striker: batter1, nonStriker: batter2, bowler: bowler, runsOffBat: 0, extra: ExtraEvent(kind: .noBall, runs: 1), wicket: runOut)
        #expect(noBallRunOut.countsAsWicket)

        // Bowled/caught off a wide does not count as a wicket
        let wideCaught = BallEvent(striker: batter1, nonStriker: batter2, bowler: bowler, runsOffBat: 0, extra: ExtraEvent(kind: .wide, runs: 1), wicket: caught)
        #expect(!wideCaught.countsAsWicket)

        // Stumped off a wide DOES count as a wicket
        let wideStumped = BallEvent(striker: batter1, nonStriker: batter2, bowler: bowler, runsOffBat: 0, extra: ExtraEvent(kind: .wide, runs: 1), wicket: stumped)
        #expect(wideStumped.countsAsWicket)
    }

    @Test("penalty runs in chasing innings can complete the chase immediately")
    func penaltyChaseWin() {
        let rules = MatchRules(oversPerInnings: 1)
        let events = firstInnings(runs: 4, rules: rules) + [
            start(8, innings: 2, batting: teamB, bowling: teamA),
            MatchEvent(sequence: 9, kind: .penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: 5, reason: "ball hit helmet"))),
        ]
        let state = MatchLedger(events: events).replay(rules: rules)
        #expect(state.status == .completed(.wonByWickets(team: teamB, wickets: 10)))
    }

    private func firstInnings(runs: Int, rules: MatchRules) -> [MatchEvent] {
        var events = [start(1, innings: 1, batting: teamA, bowling: teamB)]
        for index in 0..<rules.maxLegalDeliveriesPerInnings {
            events.append(ball(2 + index, batRuns: index == 0 ? runs : 0))
        }
        return events
    }
}

@Suite("Unknown-safe rendering")
struct UnknownRenderingTests {
    @Test("unknown text always renders the literal unknown")
    func textUnknown() {
        #expect(UnknownSafeFormatter.text(.unknown) == "unknown")
        #expect(UnknownSafeFormatter.text(.known("known")) == "known")
    }

    @Test("unknown and non-finite numbers never render guessed zero")
    func numberUnknown() {
        #expect(UnknownSafeFormatter.rateString(.unknown) == "unknown")
        #expect(UnknownSafeFormatter.rateString(.known(.infinity)) == "unknown")
        #expect(UnknownSafeFormatter.rateString(.known(.nan)) == "unknown")
        #expect(UnknownSafeFormatter.ballsString(.unknown) == "unknown")
        #expect(UnknownSafeFormatter.ballsString(.known(.infinity)) == "unknown")
        #expect(UnknownSafeFormatter.ballsString(.known(7)) == "7")
    }

    @Test("overs formatting is cricket notation and invalid base is unknown")
    func oversFormatting() {
        #expect(0.cricketOversString(ballsPerOver: 6) == "0.0")
        #expect(8.cricketOversString(ballsPerOver: 6) == "1.2")
        #expect(8.cricketOversString(ballsPerOver: 0) == "unknown")
    }

    @Test("known-state helper reports knowledge explicitly")
    func knownValue() {
        #expect(NumericValue.known(0).isKnown)
        #expect(!NumericValue.unknown.isKnown)
    }
}

@Suite("Seeded replay properties")
struct ReplayPropertyTests {
    @Test("seeded random ledgers always recompute stably", arguments: [1, 7, 42, 1_337, 86_753])
    func seededReplay(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        var events = [start(1, innings: 1, batting: teamA, bowling: teamB)]

        for sequence in 2...81 {
            let choice = generator.next() % 10
            switch choice {
            case 0:
                events.append(ball(sequence, extra: ExtraEvent(kind: .wide, runs: Int(generator.next() % 3) + 1)))
            case 1:
                events.append(ball(sequence, extra: ExtraEvent(kind: .noBall, runs: 1)))
            case 2:
                events.append(ball(sequence, extra: ExtraEvent(kind: .bye, runs: Int(generator.next() % 4))))
            case 3:
                events.append(ball(sequence, extra: ExtraEvent(kind: .legBye, runs: Int(generator.next() % 3))))
            case 4:
                events.append(ball(sequence, wicket: WicketEvent(kind: .runOut, dismissed: batter1)))
            default:
                let options = [0, 0, 1, 1, 2, 3, 4, 6]
                events.append(ball(sequence, batRuns: options[Int(generator.next() % UInt64(options.count))]))
            }
        }

        let ledger = MatchLedger(events: events)
        let first = ledger.replay(rules: .t20)
        let second = ledger.replay(rules: .t20)

        #expect(first == second)
        #expect(ledger.events.count == events.count)
        #expect(first.innings.first?.runs ?? -1 >= 0)
        #expect(first.innings.first?.legalDeliveries ?? -1 <= MatchRules.t20.maxLegalDeliveriesPerInnings)
    }
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
