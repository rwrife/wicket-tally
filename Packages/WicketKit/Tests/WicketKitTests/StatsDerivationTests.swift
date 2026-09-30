import Foundation
import Testing
@testable import WicketKit

private enum StatsTestData {
    static let rules = MatchRules(oversPerInnings: 1, ballsPerOver: 2, maxWickets: 2)

    static func ball(
        runs: Int = 0, striker: PlayerID? = "a1", nonStriker: PlayerID? = "a2",
        bowler: PlayerID? = "b1", extra: ExtraEvent? = nil, wicket: WicketEvent? = nil
    ) -> MatchEventKind {
        .ball(BallEvent(
            striker: striker, nonStriker: nonStriker, bowler: bowler,
            runsOffBat: runs, extra: extra, wicket: wicket
        ))
    }

    static func events(_ kinds: [MatchEventKind]) -> [MatchEvent] {
        kinds.enumerated().map { MatchEvent(sequence: $0.offset + 1, kind: $0.element) }
    }

    static func fixture(
        id: FixtureID = "game", first: Int = 4, second: Int = 2,
        extraEvents: [MatchEvent] = []
    ) -> StatsFixture {
        StatsFixture(
            id: id, homeTeamID: "A", awayTeamID: "B", rules: rules,
            ledger: MatchLedger(events: events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                ball(runs: first), ball(),
                .inningsStarted(number: 2, batting: "B", bowling: "A"),
                ball(runs: second, striker: "b1", nonStriker: "b2", bowler: "a1"),
            ] + (second > first ? [] : [ball(striker: "b1", nonStriker: "b2", bowler: "a1")])) + extraEvents)
        )
    }

    static func replacingLedger(_ fixture: StatsFixture, events: [MatchEvent]) -> StatsFixture {
        StatsFixture(
            id: fixture.id, homeTeamID: fixture.homeTeamID, awayTeamID: fixture.awayTeamID,
            rules: fixture.rules, ledger: MatchLedger(events: events), playerIDs: fixture.playerIDs
        )
    }

    static func correction(_ sequence: Int, _ action: CorrectionAction) -> MatchEvent {
        MatchEvent(sequence: sequence, kind: .correction(CorrectionEvent(
            action: action, reason: "Umpire review", provenance: "scorer-1"
        )))
    }
}

@Suite("Issue 7 standings derived from effective ledgers")
struct StatsStandingsTests {
    @Test("wins losses ties and rates", arguments: [
        (4, 2, 2.0, 1.0, 0.0, 0.0, 2.0),
        (4, 4, 1.0, 0.0, 0.0, 1.0, 0.0),
        (4, 6, 0.0, 0.0, 1.0, 0.0, -8.0),
    ])
    func resultTable(first: Int, second: Int, points: Double, won: Double, lost: Double, tied: Double, nrr: Double) throws {
        let fixture = StatsTestData.fixture(first: first, second: second)
        let rows = try StandingsDerivation.derive(fixtures: [fixture])
        let a = try #require(rows.first { $0.teamID == "A" })
        #expect(a.played == .known(1))
        #expect(a.points == .known(points))
        #expect(a.won == .known(won))
        #expect(a.lost == .known(lost))
        #expect(a.tied == .known(tied))
        #expect(a.netRunRate == .known(nrr))
        #expect(a.nrrUnavailableReason == nil)
    }

    @Suite("Issue 7 scorecards and player statistics")
    struct StatsScorecardTests {
        @Test("extras attribution and balls faced", arguments: [
            (ExtraType.wide, 3, 0, 3, 0, 0),
            (.noBall, 1, 4, 5, 0, 1),
            (.bye, 2, 0, 0, 1, 1),
            (.legBye, 2, 0, 0, 1, 1),
        ])
        func extras(kind: ExtraType, extras: Int, bat: Int, conceded: Int, legal: Int, faced: Int) throws {
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(runs: bat, extra: ExtraEvent(kind: kind, runs: extras)),
            ])), rules: .t10)
            let innings = try #require(card.innings.first)
            #expect(innings.state.runs == bat + extras)
            #expect(innings.extras.total == extras)
            #expect(innings.batting.first?.balls == faced)
            #expect(innings.batting.first?.runs == bat)
            #expect(innings.bowling.first?.legalDeliveries == legal)
            #expect(innings.bowling.first?.runs == conceded)
            #expect(innings.state.runs == innings.batting.reduce(0) { $0 + $1.runs } + innings.extras.total)
        }

        @Test("bowler wicket credit matches dismissal type", arguments: [
            (WicketKind.bowled, 1), (.caught, 1), (.lbw, 1), (.stumped, 1),
            (.hitWicket, 1), (.runOut, 0), (.obstructingField, 0), (.timedOut, 0), (.hitBallTwice, 0),
        ])
        func wickets(kind: WicketKind, credit: Int) throws {
            let wicket = WicketEvent(kind: kind, dismissed: "a2", fielder: "b2")
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(runs: 1, wicket: wicket),
            ])), rules: .t10)
            let innings = try #require(card.innings.first)
            #expect(innings.bowling.first?.wickets == credit)
            #expect(innings.batting.first { $0.playerID == "a1" }?.dismissal == nil)
            #expect(innings.batting.first { $0.playerID == "a2" }?.dismissal == wicket)
            #expect(innings.batting.first { $0.playerID == "a2" }?.dismissalBowler == (credit == 1 ? "b1" : nil))
            #expect(innings.fallOfWickets.first?.wicket == 1)
            #expect(innings.fallOfWickets.first?.runs == 1)
            #expect(innings.fallOfWickets.first?.legalDeliveries == 1)
            #expect(innings.fallOfWickets.first?.dismissed == "a2")
        }

        @Test("illegal-ball wickets obey effective ledger legality", arguments: [
            (ExtraType.noBall, WicketKind.caught, 0, 0),
            (.noBall, .runOut, 1, 0),
            (.wide, .stumped, 1, 1),
            (.wide, .bowled, 0, 0),
        ])
        func illegalWickets(extra: ExtraType, kind: WicketKind, wickets: Int, credit: Int) throws {
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(extra: ExtraEvent(kind: extra, runs: 1), wicket: WicketEvent(kind: kind, dismissed: "a1")),
            ])), rules: .t10)
            #expect(card.innings[0].state.wickets == wickets)
            #expect(card.innings[0].fallOfWickets.count == wickets)
            #expect(card.innings[0].bowling[0].wickets == credit)
            #expect(card.innings[0].state.legalDeliveries == 0)
        }

        @Test("maidens require complete single-bowler overs; byes do not count against bowler", arguments: [0, 1, 2, 3])
        func maidens(_ mode: Int) throws {
            var kinds: [MatchEventKind] = [.inningsStarted(number: 1, batting: "A", bowling: "B")]
            if mode == 1 { kinds.append(StatsTestData.ball(extra: ExtraEvent(kind: .wide, runs: 1))) }
            for index in 0..<(mode == 3 ? 5 : 6) {
                kinds.append(StatsTestData.ball(
                    bowler: mode == 2 && index == 5 ? "b2" : "b1",
                    extra: index == 0 ? ExtraEvent(kind: .bye, runs: 2) : nil
                ))
            }
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: StatsTestData.events(kinds)), rules: .t10)
            #expect(card.innings[0].bowling.reduce(0) { $0 + $1.maidens } == (mode == 0 ? 1 : 0))
            #expect(card.innings[0].bowling[0].overs == (mode == 2 || mode == 3 ? "0.5" : "1.0"))
        }

        @Test("average divides by dismissals; strike rate by balls; HS by innings")
        func playerTotals() throws {
            let base = StatsTestData.fixture()
            let dismissal = StatsTestData.correction(20, .replace(
                target: base.ledger.events[2].id,
                with: StatsTestData.ball(wicket: WicketEvent(kind: .caught, dismissed: "a1"))
            ))
            let game = StatsTestData.replacingLedger(base, events: base.ledger.events + [dismissal])
            let stats = try StatsDerivation.derive(fixtures: [game, StatsTestData.fixture(id: "other", first: 6, second: 1)], playerIDs: ["unused"])
            let batter = try #require(stats.players.first { $0.playerID == "a1" })
            #expect(batter.battingInnings == .known(2))
            #expect(batter.runs == .known(10))
            #expect(batter.highestScore == .known(6))
            #expect(batter.dismissals == .known(1))
            #expect(batter.average == .known(10))
            #expect(batter.ballsFaced == .known(4))
            #expect(batter.strikeRate == .known(250))
            #expect(batter.bowlingOvers == .known("2.0"))
            #expect(batter.runsConceded == .known(3))
            #expect(batter.economy == .known(1.5))
            let bowler = try #require(stats.players.first { $0.playerID == "b1" })
            #expect(bowler.wickets == .known(1))
            #expect(bowler.average == .unknown)
            let unused = try #require(stats.players.first { $0.playerID == "unused" })
            #expect(unused.runs == .unknown)
            #expect(unused.highestScore == .unknown)
            #expect(unused.bowlingOvers == .unknown)
        }

        @Test("missing identities retain unattributed rows and hide unsafe aggregates")
        func missingPlayers() throws {
            let base = StatsTestData.fixture()
            let change = StatsTestData.correction(20, .replace(
                target: base.ledger.events[1].id,
                with: StatsTestData.ball(runs: 4, striker: nil, bowler: nil)
            ))
            let stats = try StatsDerivation.derive(fixtures: [StatsTestData.replacingLedger(base, events: base.ledger.events + [change])])
            let card = try #require(stats.scorecards["game"])
            #expect(card.innings[0].batting.first?.playerID == nil)
            #expect(card.innings[0].batting.first?.runs == 4)
            #expect(card.innings[0].bowling.first?.playerID == nil)
            #expect(card.plainText().contains("Unknown player"))
            #expect(stats.players.allSatisfy { $0.runs == .unknown && $0.economy == .unknown })
            #expect(stats.standings.first?.points == .known(2))
            #expect(stats.standings.first?.netRunRate == .known(2))
        }

        @Test("all extras, penalties, fall of wickets and audit text are shareable")
        func scorecardText() throws {
            var events = StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(runs: 4),
                StatsTestData.ball(extra: ExtraEvent(kind: .wide, runs: 2)),
                StatsTestData.ball(extra: ExtraEvent(kind: .noBall, runs: 1)),
                StatsTestData.ball(extra: ExtraEvent(kind: .bye, runs: 2)),
                StatsTestData.ball(extra: ExtraEvent(kind: .legBye, runs: 1)),
                .penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: 5, reason: "Helmet")),
                StatsTestData.ball(wicket: WicketEvent(kind: .bowled, dismissed: "a1")),
            ])
            events.append(StatsTestData.correction(20, .scoreAdjustment(ScoreAdjustment(runsDelta: 2, wicketsDelta: 1))))
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: events), rules: .t10)
            let innings = card.innings[0]
            #expect(innings.state.runs == 17)
            #expect(innings.extras.total == 11)
            #expect(innings.state.wickets == 2)
            #expect(innings.fallOfWickets.count == 1)
            #expect(innings.fallOfWickets[0].runs == 15)
            #expect(innings.bowling[0].runs == 7)
            let text = card.plainText(title: "Cup", teamNames: ["A": "Alphas"], playerNames: ["a1": "Alice"])
            #expect(text.hasPrefix("Cup\nResult: unknown"))
            #expect(text.contains("Alphas 17/2 (0.4 overs)"))
            #expect(text.contains("Alice: 4 5 1 0 80.00 bowled"))
            #expect(text.contains("bowled b b1"))
            #expect(text.contains("Extras: 11 (wd 2, nb 1, b 2, lb 1, penalty 5)"))
            #expect(text.contains("Fall of wickets: 1-15 Alice (0.4)"))
            #expect(text.contains("Unattributed adjustment: runs 2, wickets 1; Umpire review [scorer-1]"))
            #expect(text.contains("Bowling: overs maidens runs wickets economy"))
            #expect(text == card.plainText(title: "Cup", teamNames: ["A": "Alphas"], playerNames: ["a1": "Alice"]))
        }
    }

    @Suite("Issue 7 NRR safety and correction validation")
    struct StatsSafetyTests {
        @Test("NRR aggregates runs and overs, never an average of match NRR values")
        func aggregateNRR() throws {
            let stats = try StatsDerivation.derive(fixtures: [
                StatsTestData.fixture(id: "one", first: 4, second: 2),
                StatsTestData.fixture(id: "two", first: 4, second: 6),
            ])
            let a = try #require(stats.standings.first { $0.teamID == "A" })
            let actual = try #require(known(a.netRunRate))
            #expect(abs(actual - (8.0 / 2.0 - 8.0 / 1.5)) < 0.000001)
            #expect(actual != -3) // Arithmetic average of the two match NRRs.
        }

        private func known(_ value: NumericValue) -> Double? {
            if case let .known(number) = value { return number }
            return nil
        }

        @Test("mixed balls-per-over formats aggregate economy without misleading overs text")
        func mixedOverSizes() throws {
            let base = StatsTestData.fixture()
            let other = StatsFixture(
                id: "six-ball", homeTeamID: "A", awayTeamID: "B",
                rules: MatchRules(oversPerInnings: 1, ballsPerOver: 6),
                ledger: MatchLedger(events: StatsTestData.events([
                    .inningsStarted(number: 1, batting: "A", bowling: "B"),
                ] + (0..<6).map { StatsTestData.ball(runs: $0 == 0 ? 6 : 0) } + [
                    .inningsStarted(number: 2, batting: "B", bowling: "A"),
                ] + (0..<6).map { StatsTestData.ball(runs: $0 == 0 ? 3 : 0, striker: "b1", nonStriker: "b2", bowler: "a1") }))
            )
            let stats = try StatsDerivation.derive(fixtures: [base, other])
            let bowler = try #require(stats.players.first { $0.playerID == "a1" })
            #expect(bowler.bowlingLegalDeliveries == .known(8))
            #expect(bowler.bowlingOvers == .unknown)
            #expect(bowler.economy == .known(2.5))
            #expect(bowler.bowlingUnavailableReason?.contains("different balls-per-over") == true)
        }

        @Test("run-cut overs align cards with canonical replay and cannot create maidens")
        func runCutOvers() throws {
            let preset = try RulePreset(name: "Cut", oversPerInnings: 2, ballsPerOver: 6, maxRunsPerOver: 2)
            let ledger = MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(extra: ExtraEvent(kind: .bye, runs: 2)),
                StatsTestData.ball(runs: 2, wicket: WicketEvent(kind: .runOut, dismissed: "a2")),
                StatsTestData.ball(runs: 99), // Ignored after two cut overs.
                .inningsStarted(number: 2, batting: "B", bowling: "A"),
                StatsTestData.ball(runs: 6, striker: "b1", bowler: "a1"),
            ]))
            let card = try ScorecardDerivation.derive(ledger: ledger, rules: preset.rules)
            #expect(card.innings.map(\.state) == ledger.replay(rules: preset.rules).innings)
            #expect(card.innings[0].batting[0].runs == 2)
            #expect(card.innings[0].bowling[0].maidens == 0)
            #expect(card.innings[0].bowling[0].overs == "0.2")
            #expect(card.innings[0].fallOfWickets[0].overs == "2.0")
            #expect(card.result == .wonByWickets(team: "B", wickets: 10))
            #expect(card.warnings.isEmpty)
            #expect(card.nrrUnavailableReason?.contains("Run-cut overs") == true)
            #expect(card.plainText().contains("A 4/1 (2.0 overs)"))
        }

        @Test("innings run caps close player attribution on deliveries and penalties", arguments: [false, true])
        func inningsCaps(penalty: Bool) throws {
            let preset = try RulePreset(name: "Cap", inningsRunCap: 5)
            let ledger = MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                penalty ? .penaltyRuns(PenaltyRunEvent(awardedToBatting: true, runs: 5, reason: "Helmet")) : StatsTestData.ball(runs: 5),
                StatsTestData.ball(runs: 99),
                .inningsStarted(number: 2, batting: "B", bowling: "A"),
                StatsTestData.ball(runs: 6, striker: "b1", bowler: "a1"),
            ]))
            let card = try ScorecardDerivation.derive(ledger: ledger, rules: preset.rules)
            #expect(card.innings.map(\.state) == ledger.replay(rules: preset.rules).innings)
            #expect(card.innings[0].batting.reduce(0) { $0 + $1.runs } == (penalty ? 0 : 5))
            #expect(card.innings[0].extras.penalties == (penalty ? 5 : 0))
            #expect(card.result == .wonByWickets(team: "B", wickets: 10))
            #expect(card.nrrUnavailableReason?.contains("innings caps") == true)
        }

        @Test("one-hand catch attribution respects the match's snapshotted rules", arguments: [false, true])
        func oneHandCatch(allowed: Bool) throws {
            let preset = try RulePreset(name: "Catch", oneHandCatchAllowed: allowed)
            let ledger = MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(wicket: WicketEvent(kind: .caught, dismissed: "a1", isOneHandCatch: true)),
            ]))
            let card = try ScorecardDerivation.derive(ledger: ledger, rules: preset.rules)
            #expect(card.innings[0].state.wickets == (allowed ? 1 : 0))
            #expect(card.innings[0].bowling[0].wickets == (allowed ? 1 : 0))
            #expect(card.innings[0].fallOfWickets.count == (allowed ? 1 : 0))
            #expect((card.innings[0].batting[0].dismissal != nil) == allowed)
        }

        @Test("retirement ambiguity is explicit instead of assuming retired-out averages")
        func retirement() throws {
            let base = StatsTestData.fixture()
            let correction = StatsTestData.correction(20, .replace(
                target: base.ledger.events[2].id,
                with: StatsTestData.ball(wicket: WicketEvent(kind: .retired, dismissed: "a1"))
            ))
            let stats = try StatsDerivation.derive(fixtures: [StatsTestData.replacingLedger(base, events: base.ledger.events + [correction])])
            #expect(stats.players.first?.average == .unknown)
            #expect(stats.standings.first?.points == .unknown)
            #expect(stats.scorecards["game"]?.warnings.contains("Retirement does not specify retired hurt versus retired out.") == true)
        }

        @Test("one unqualified constituent fixture hides the entire team's NRR")
        func nrrConstituents() throws {
            let rain = StatsTestData.fixture(id: "rain", extraEvents: [MatchEvent(sequence: 20, kind: .matchAbandoned(reason: "Rain"))])
            let stats = try StatsDerivation.derive(fixtures: [StatsTestData.fixture(), rain])
            #expect(stats.standings.allSatisfy { $0.netRunRate == .unknown })
            #expect(stats.standings.allSatisfy { $0.nrrUnavailableReason?.contains("rain: Abandoned: Rain") == true })
        }

        @Test("all-out innings use the full quota rather than balls actually faced")
        func allOutNRR() throws {
            let rules = MatchRules(oversPerInnings: 2, ballsPerOver: 2, maxWickets: 1)
            let ledger = MatchLedger(events: StatsTestData.events([
                .inningsStarted(number: 1, batting: "A", bowling: "B"),
                StatsTestData.ball(runs: 4, wicket: WicketEvent(kind: .runOut, dismissed: "a1")),
                .inningsStarted(number: 2, batting: "B", bowling: "A"),
                StatsTestData.ball(runs: 2, striker: "b1", bowler: "a1", wicket: WicketEvent(kind: .runOut, dismissed: "b1")),
            ]))
            let fixture = StatsFixture(id: "all-out", homeTeamID: "A", awayTeamID: "B", rules: rules, ledger: ledger)
            let stats = try StatsDerivation.derive(fixtures: [fixture])
            #expect(stats.standings.first?.netRunRate == .known(1))
            #expect(stats.scorecards["all-out"]?.innings[0].state.legalDeliveries == 1)
        }

        @Test("zero-ball chase, declarations and unverified short innings hide NRR", arguments: [0, 1, 2])
        func unverifiedNRR(_ mode: Int) throws {
            let kinds: [MatchEventKind]
            if mode == 0 {
                kinds = [
                    .inningsStarted(number: 1, batting: "A", bowling: "B"),
                    StatsTestData.ball(), StatsTestData.ball(),
                    .inningsStarted(number: 2, batting: "B", bowling: "A"),
                    StatsTestData.ball(striker: "b1", bowler: "a1", extra: ExtraEvent(kind: .wide, runs: 1)),
                ]
            } else {
                kinds = [
                    .inningsStarted(number: 1, batting: "A", bowling: "B"),
                    StatsTestData.ball(runs: 4),
                    .inningsEnded(reason: mode == 1 ? .declared : .oversComplete),
                    .inningsStarted(number: 2, batting: "B", bowling: "A"),
                    StatsTestData.ball(runs: 6, striker: "b1", bowler: "a1"),
                ]
            }
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: StatsTestData.events(kinds)), rules: StatsTestData.rules)
            #expect(card.result != nil)
            #expect(card.nrrUnavailableReason != nil)
            if mode == 0 { #expect(card.innings[1].bowling[0].economy == .unknown) }
        }

        @Test("abandoned innings cannot masquerade as a completed result")
        func abandonedInnings() throws {
            let base = StatsTestData.fixture()
            var events = Array(base.ledger.events.prefix(5))
            events.append(MatchEvent(sequence: 6, kind: .inningsEnded(reason: .abandoned)))
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: events), rules: base.rules)
            #expect(card.result == nil)
            #expect(card.resultUnavailableReason == "Abandoned: Innings abandoned")
        }

        @Test("score adjustments retain provenance, recompute points, and hide NRR/player totals")
        func adjustedMatch() throws {
            let base = StatsTestData.fixture()
            let adjustment = StatsTestData.correction(20, .scoreAdjustment(ScoreAdjustment(runsDelta: 4)))
            let stats = try StatsDerivation.derive(fixtures: [StatsTestData.replacingLedger(base, events: base.ledger.events + [adjustment])])
            #expect(stats.standings.first?.teamID == "B")
            #expect(stats.standings.first?.points == .known(2))
            #expect(stats.standings.first?.netRunRate == .unknown)
            #expect(stats.players.allSatisfy { $0.runs == .unknown && $0.wickets == .unknown })
            #expect(stats.scorecards["game"]?.innings[1].adjustments.count == 1)
            #expect(stats.scorecards["game"]?.innings[1].state.runs == 6)
            #expect(stats.scorecards["game"]?.innings[1].batting.first?.runs == 2)
        }

        @Test("invalidation wins over replacement and last replacement wins deterministically")
        func correctionPrecedence() throws {
            let base = StatsTestData.fixture()
            let target = base.ledger.events[1].id
            let changes = [
                StatsTestData.correction(20, .replace(target: target, with: StatsTestData.ball(runs: 5))),
                StatsTestData.correction(21, .replace(target: target, with: StatsTestData.ball(runs: 6))),
            ]
            let replaced = try ScorecardDerivation.derive(ledger: MatchLedger(events: (base.ledger.events + changes).reversed()), rules: base.rules)
            #expect(replaced.innings[0].batting[0].runs == 6)
            let invalidated = try ScorecardDerivation.derive(ledger: MatchLedger(events: base.ledger.events + changes + [
                StatsTestData.correction(22, .invalidate(target: target)),
            ]), rules: base.rules)
            #expect(invalidated.innings[0].batting[0].runs == 0)
            #expect(invalidated.innings[0].batting[0].balls == 1)
            #expect(invalidated.result == nil) // Removing a legal ball leaves the first innings unfinished.
        }

        @Test("invalidating abandonment restores derived results")
        func removeAbandonment() throws {
            let rain = MatchEvent(sequence: 20, kind: .matchAbandoned(reason: "Mistaken"))
            let fixture = StatsTestData.fixture(extraEvents: [rain, StatsTestData.correction(21, .invalidate(target: rain.id))])
            let stats = try StatsDerivation.derive(fixtures: [fixture])
            #expect(stats.standings.first?.points == .known(2))
            #expect(stats.standings.first?.netRunRate == .known(2))
        }

        @Test("ambiguous sequences, IDs, targets, and nested corrections throw")
        func invalidCorrections() throws {
            let event = MatchEvent(sequence: 1, kind: .inningsStarted(number: 1, batting: "A", bowling: "B"))
            #expect(throws: StatsDerivationError.duplicateEventID) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, event]), rules: .t10)
            }
            #expect(throws: StatsDerivationError.duplicateSequence(1)) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, MatchEvent(sequence: 1, kind: .overCompleted)]), rules: .t10)
            }
            let missing = EventID()
            #expect(throws: StatsDerivationError.invalidCorrectionTarget(missing)) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, StatsTestData.correction(2, .invalidate(target: missing))]), rules: .t10)
            }
            let first = StatsTestData.correction(2, .invalidate(target: event.id))
            #expect(throws: StatsDerivationError.unsupportedCorrection(first.id)) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, first, StatsTestData.correction(3, .invalidate(target: first.id))]), rules: .t10)
            }
            let nested = StatsTestData.correction(2, .replace(target: event.id, with: first.kind))
            #expect(throws: StatsDerivationError.unsupportedCorrection(nested.id)) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, nested]), rules: .t10)
            }
            let blank = MatchEvent(sequence: 2, kind: .correction(CorrectionEvent(
                action: .invalidate(target: event.id), reason: "", provenance: ""
            )))
            #expect(throws: StatsDerivationError.missingProvenance(blank.id)) {
                try ScorecardDerivation.derive(ledger: MatchLedger(events: [event, blank]), rules: .t10)
            }
        }

        @Test("fielding-side penalties stay explicit and unknown, not silently lost")
        func unsupportedPenalty() throws {
            let base = StatsTestData.fixture()
            let penalty = StatsTestData.correction(20, .replace(
                target: base.ledger.events[1].id,
                with: .penaltyRuns(PenaltyRunEvent(awardedToBatting: false, runs: 5, reason: "Penalty"))
            ))
            let card = try ScorecardDerivation.derive(ledger: MatchLedger(events: base.ledger.events + [penalty]), rules: base.rules)
            #expect(card.result == nil)
            #expect(card.warnings.contains("Penalty awarded to the fielding side cannot be allocated by the ledger."))
            #expect(card.nrrUnavailableReason != nil)
        }
    }

    @Test("replacement recomputes scorecard, result, points, players and NRR")
    func correctionReplay() throws {
        let original = StatsTestData.fixture()
        let change = StatsTestData.correction(20, .replace(
            target: original.ledger.events[1].id, with: StatsTestData.ball(runs: 1)
        ))
        let corrected = StatsTestData.replacingLedger(original, events: original.ledger.events + [change])
        let before = try StatsDerivation.derive(fixtures: [original])
        let after = try StatsDerivation.derive(fixtures: [corrected])
        #expect(before.standings.first?.teamID == "A")
        #expect(after.standings.first?.teamID == "B")
        #expect(after.players.first { $0.playerID == "a1" }?.runs == .known(1))
        // A correction moves the winning ball earlier; subsequent deliveries
        // must disappear from both team and player figures.
        #expect(after.scorecards["game"]?.innings[1].batting.first?.balls == 1)
        #expect(after.scorecards["game"]?.warnings.isEmpty == true)
        let clean = StatsTestData.replacingLedger(corrected, events: corrected.ledger.events + [
            StatsTestData.correction(21, .invalidate(target: original.ledger.events[5].id)),
        ])
        let final = try StatsDerivation.derive(fixtures: [clean])
        #expect(final.standings.first?.teamID == "B")
        #expect(final.players.first { $0.playerID == "a1" }?.runs == .known(1))
        #expect(final.standings.first?.netRunRate == .known(3))
        #expect(final == (try StatsDerivation.derive(fixtures: [clean])))
        #expect(original.ledger.events.count == 6)
    }

    @Test("abandoned, unfinished and empty fixtures are unknown, never fabricated losses", arguments: [0, 1, 2])
    func unresolved(_ mode: Int) throws {
        let fixture: StatsFixture
        switch mode {
        case 0:
            fixture = StatsTestData.fixture(extraEvents: [MatchEvent(sequence: 20, kind: .matchAbandoned(reason: "Rain"))])
        case 1:
            let original = StatsTestData.fixture()
            fixture = StatsTestData.replacingLedger(original, events: Array(original.ledger.events.prefix(2)))
        default:
            fixture = StatsTestData.replacingLedger(StatsTestData.fixture(), events: [])
        }
        let stats = try StatsDerivation.derive(fixtures: [fixture], playerIDs: ["a1"])
        let row = try #require(stats.standings.first)
        #expect(row.played == .unknown)
        #expect(row.won == .unknown)
        #expect(row.lost == .unknown)
        #expect(row.tied == .unknown)
        #expect(row.points == .unknown)
        #expect(row.netRunRate == .unknown)
        #expect(row.nrrUnavailableReason != nil)
        #expect(stats.players.first?.runs == .unknown)
        #expect(stats.players.first?.economy == .unknown)
        #expect(stats.scorecards["game"]?.plainText().contains("Result: unknown") == true)
    }

    @Test("manual points retain derived total and explicit audit record")
    func manualPoints() throws {
        let date = Date(timeIntervalSince1970: 123)
        let manual = try StandingsPointsOverride(teamID: "B", points: 8, reason: "Committee ruling", provenance: "Chair", recordedAt: date)
        let stats = try StatsDerivation.derive(fixtures: [StatsTestData.fixture()], manualPoints: [manual])
        let row = try #require(stats.standings.first)
        #expect(row.teamID == "B")
        #expect(row.points == .known(8))
        #expect(row.derivedPoints == .known(0))
        #expect(row.pointsOverride == manual)
        #expect(row.pointsLabel == "Manual points override")
        #expect(row.netRunRate == .known(-2))
        let abandoned = StatsTestData.fixture(extraEvents: [MatchEvent(sequence: 20, kind: .matchAbandoned(reason: "Rain"))])
        let unresolved = try StandingsDerivation.derive(fixtures: [abandoned], manualPoints: [manual])
        #expect(unresolved.first?.points == .known(8))
        #expect(unresolved.first?.derivedPoints == .unknown)
        #expect(unresolved.first?.netRunRate == .unknown)
    }

    @Test("override validation and duplicate inputs fail explicitly")
    func validation() throws {
        #expect(throws: StatsDerivationError.invalidPointsOverride) {
            try StandingsPointsOverride(teamID: "A", points: 3, reason: " ", provenance: "Official", recordedAt: Date())
        }
        let manual = try StandingsPointsOverride(teamID: "A", points: -2, reason: "Deduction", provenance: "Chair", recordedAt: Date())
        #expect(throws: StatsDerivationError.duplicatePointsOverride("A")) {
            try StandingsDerivation.derive(fixtures: [StatsTestData.fixture()], manualPoints: [manual, manual])
        }
        #expect(throws: StatsDerivationError.unknownOverrideTeam("A")) {
            try StandingsDerivation.derive(fixtures: [], manualPoints: [manual])
        }
        #expect(throws: StatsDerivationError.duplicateFixture("game")) {
            try StatsDerivation.derive(fixtures: [StatsTestData.fixture(), StatsTestData.fixture()])
        }
    }

    @Test("league totals, configurable points and deterministic fixture ordering")
    func multipleFixtures() throws {
        let fixtures = [StatsTestData.fixture(id: "2", first: 1, second: 2), StatsTestData.fixture(id: "1")]
        let forward = try StatsDerivation.derive(fixtures: fixtures, teamIDs: ["C"], pointsPolicy: .init(win: 3))
        let reverse = try StatsDerivation.derive(fixtures: fixtures.reversed(), teamIDs: ["C"], pointsPolicy: .init(win: 3))
        #expect(forward == reverse)
        #expect(forward.standings.map(\.teamID) == ["A", "B", "C"])
        #expect(forward.standings[0].played == .known(2))
        #expect(forward.standings[0].points == .known(3))
        #expect(forward.standings[2].points == .known(0))
        #expect(forward.standings[2].netRunRate == .unknown)
        #expect(forward.players.first { $0.playerID == "a1" }?.runs == .known(5))
        #expect(forward.players.first { $0.playerID == "a1" }?.highestScore == .known(4))
        #expect(forward.players.first { $0.playerID == "a1" }?.strikeRate == .known(125))
    }
}
