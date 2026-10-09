import Foundation
import Testing
@testable import WicketKit

@Suite("Issue 18 season insights")
struct SeasonInsightsTests {
    private let rules = MatchRules(oversPerInnings: 1, ballsPerOver: 1, maxWickets: 2)

    private func game(_ id: String, runs: Int, bowler: PlayerID? = "p", complete: Bool = true, unknownStriker: Bool = false) -> StatsFixture {
        var kinds: [MatchEventKind] = [
            .inningsStarted(number: 1, batting: "A", bowling: "B"),
            .ball(BallEvent(striker: unknownStriker ? nil : "p", nonStriker: nil, bowler: "q", runsOffBat: runs)),
        ]
        if complete {
            kinds += [
                .inningsStarted(number: 2, batting: "B", bowling: "A"),
                .ball(BallEvent(striker: "q", nonStriker: nil, bowler: bowler, runsOffBat: 0)),
            ]
        }
        return StatsFixture(id: FixtureID(id), homeTeamID: "A", awayTeamID: "B", rules: rules,
            ledger: MatchLedger(events: kinds.enumerated().map { MatchEvent(sequence: $0.offset + 1, kind: $0.element) }),
            playerIDs: ["p", "q"])
    }

    @Test("ties in recorded best point to both underlying scorecards")
    func ties() throws {
        let season = try SeasonInsights.derive(fixtures: [game("two", runs: 4), game("one", runs: 4)], playerIDs: ["p"])
        let player = try #require(season.first { $0.playerID == "p" })
        #expect(player.matches.map(\.fixtureID) == ["one", "two"])
        #expect(player.matches.map(\.cumulativeRuns) == [.known(4), .known(8)])
        #expect(player.matches.map(\.cumulativeWickets) == [.known(0), .known(0)])
        #expect(player.bestRuns == .known(4))
        #expect(player.bestRunsFixtures == ["one", "two"])
        #expect(player.bestWickets == .known(0))
        #expect(player.plainText(name: "Pat").contains("Pat"))
        #expect(player.plainText(name: "Pat").contains("one"))
    }

    @Test("append-only correction changes best and cumulative runs")
    func correction() throws {
        let base = game("first", runs: 4)
        let ball = base.ledger.events[1]
        let replacement = MatchEvent(sequence: 5, kind: .correction(CorrectionEvent(
            action: .replace(target: ball.id, with: .ball(BallEvent(striker: "p", nonStriker: nil, bowler: "q", runsOffBat: 2))),
            reason: "Scorebook review", provenance: "scorer")))
        let fixed = StatsFixture(id: base.id, homeTeamID: base.homeTeamID, awayTeamID: base.awayTeamID,
            rules: rules, ledger: MatchLedger(events: base.ledger.events + [replacement]), playerIDs: base.playerIDs)
        let player = try #require(SeasonInsights.derive(fixtures: [fixed, game("second", runs: 3)], playerIDs: ["p"]).first)
        #expect(player.matches.map(\.runs) == [.known(2), .known(3)])
        #expect(player.matches.map(\.cumulativeRuns) == [.known(2), .known(5)])
        #expect(player.bestRunsFixtures == ["second"])
    }

    @Test("incomplete or unidentified matches cannot become a zero appearance or a personal best")
    func gaps() throws {
        let player = try #require(SeasonInsights.derive(fixtures: [
            game("good", runs: 4), game("partial", runs: 8, complete: false),
            game("unknown", runs: 2, unknownStriker: true),
        ], playerIDs: ["p"]).first)
        #expect(player.matches[1].isComplete == false)
        #expect(player.matches[1].runs == .unknown)
        #expect(player.matches[1].cumulativeRuns == .unknown)
        #expect(player.matches[2].runs == .unknown)
        #expect(player.matches[2].cumulativeRuns == .unknown)
        #expect(player.bestRuns == .unknown)
        #expect(player.bestRunsFixtures.isEmpty)
        #expect(player.plainText(name: "Pat").contains("unknown"))
    }

    @Test("chronology uses recorded fixture start rather than identifier order")
    func chronology() throws {
        let early = game("z", runs: 1)
        let late = game("a", runs: 3)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let fixtures = [(early, start), (late, start.addingTimeInterval(3_600))].map { game, date in
            StatsFixture(id: game.id, homeTeamID: game.homeTeamID, awayTeamID: game.awayTeamID,
                rules: game.rules, ledger: game.ledger, playerIDs: game.playerIDs, startsAt: date)
        }
        let player = try #require(SeasonInsights.derive(fixtures: fixtures, playerIDs: ["p"]).first)
        #expect(player.matches.map { $0.fixtureID } == ["z", "a"])
        #expect(player.matches.map { $0.cumulativeRuns } == [.known(1), .known(4)])
    }

    @Test("absent attribution is not a guessed zero", arguments: [0, 1, 2])
    func absentAttribution(_ mode: Int) throws {
        let base = game("game", runs: 4, bowler: mode == 0 ? nil : "q")
        let kinds = mode == 2 ? base.ledger.events + [MatchEvent(sequence: 5, kind: .matchAbandoned(reason: "Rain"))] : base.ledger.events
        let fixture = StatsFixture(id: base.id, homeTeamID: "A", awayTeamID: "B", rules: rules,
            ledger: MatchLedger(events: kinds), playerIDs: ["p", "q", "unused"])
        let players = try SeasonInsights.derive(fixtures: [fixture], playerIDs: ["unused"])
        let unused = try #require(players.first { $0.playerID == "unused" })
        #expect(unused.matches.first?.runs == .unknown)
        #expect(unused.matches.first?.wickets == .unknown)
        #expect(unused.bestRuns == .unknown)
        #expect(unused.bestWickets == .unknown)
    }

    @Test("distinct local identities are never combined even with identical names")
    func identities() throws {
        let players = try SeasonInsights.derive(fixtures: [game("one", runs: 4)], playerIDs: ["same-name"])
        let unused = try #require(players.first { $0.playerID == "same-name" })
        #expect(unused.matches.isEmpty)
        #expect(unused.plainText(name: "Pat").contains("unknown"))
        #expect(players.count == 3)
    }

    @Test("a player with zero recorded matches has unknown totals and no best")
    func zeroMatches() throws {
        let player = try #require(SeasonInsights.derive(fixtures: [], playerIDs: ["unused"]).first)
        #expect(player.matches.isEmpty)
        #expect(player.bestRuns == .unknown)
        #expect(player.bestWickets == .unknown)
        #expect(player.plainText(name: "Pat").contains("No recorded matches"))
    }
}
