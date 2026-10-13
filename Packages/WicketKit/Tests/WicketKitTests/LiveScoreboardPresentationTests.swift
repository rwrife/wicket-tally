import Foundation
import Testing
@testable import WicketKit

/// Issue #20: every Lock Screen value is a deterministic derivation of the
/// effective ledger. These tests pin unknown-safety, correction handling,
/// innings transitions, and verdict rendering without ActivityKit.
private let home: TeamID = "home"
private let away: TeamID = "away"
private let striker: PlayerID = "b1"
private let nonStriker: PlayerID = "b2"
private let bowler: PlayerID = "p1"

private func begin(_ sequence: Int, innings: Int, batting: TeamID, bowling: TeamID) -> MatchEvent {
    MatchEvent(sequence: sequence, kind: .inningsStarted(number: innings, batting: batting, bowling: bowling))
}

private func bowl(
    _ sequence: Int,
    batRuns: Int = 0,
    extra: ExtraEvent? = nil,
    wicket: WicketEvent? = nil
) -> MatchEvent {
    MatchEvent(
        sequence: sequence,
        kind: .ball(BallEvent(
            striker: striker, nonStriker: nonStriker, bowler: bowler,
            runsOffBat: batRuns, extra: extra, wicket: wicket
        ))
    )
}

private func present(_ events: [MatchEvent], rules: MatchRules = .t10) -> LiveScoreboardPresentation {
    LiveScoreboardPresenter.present(
        fixtureID: "fx-1",
        state: MatchLedger(events: events).replay(rules: rules),
        homeTeamID: home,
        homeName: "Home XI",
        awayName: "Away XI"
    )
}

@Suite("Issue 20 Live Activity presentation")
struct LiveScoreboardPresentationTests {
    @Test("empty ledger shows unknown values, never a guessed zero or verdict")
    func emptyLedger() {
        let board = present([])
        #expect(board.phase == .notStarted)
        #expect(board.scoreline == "unknown")
        #expect(board.overs == "unknown")
        #expect(board.wickets == "unknown")
        #expect(board.target == .unknown)
        #expect(board.requiredRunRate == .unknown)
        #expect(board.resultText == .unknown)
        #expect(!board.isMatchClosed)
    }

    @Test("a committed ball updates score, overs, and batting side")
    func inProgress() {
        let board = present([
            begin(1, innings: 1, batting: away, bowling: home),
            bowl(2, batRuns: 4),
            bowl(3, extra: ExtraEvent(kind: .wide, runs: 1)),
        ])
        #expect(board.phase == .inProgress)
        #expect(board.battingName == "Away XI")
        #expect(board.scoreline == "5/0")
        #expect(board.overs == "0.1")
        #expect(board.target == .unknown)
        // First-innings chase rate is not derivable.
        #expect(board.requiredRunRate == .unknown)
        #expect(!board.isMatchClosed)
    }

    @Test("a manual innings end records the chase target, not a verdict")
    func inningsBreak() {
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            bowl(2, batRuns: 4),
            MatchEvent(sequence: 3, kind: .inningsEnded(reason: .declared)),
        ])
        #expect(board.phase == .inningsBreak)
        #expect(board.target == .known("5"))
        #expect(board.resultText == .unknown)
        #expect(board.requiredRunRate == .unknown)
        #expect(!board.isMatchClosed)
    }

    @Test("a live chase derives required run rate from the ledger")
    func liveChaseRate() {
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            bowl(2, batRuns: 4),
            MatchEvent(sequence: 3, kind: .inningsEnded(reason: .declared)),
            begin(4, innings: 2, batting: away, bowling: home),
            bowl(5, batRuns: 1),
        ], rules: MatchRules(oversPerInnings: 2, ballsPerOver: 1, maxWickets: 5))
        #expect(board.phase == .inProgress)
        #expect(board.requiredRunRate != .unknown)
        #expect(board.target == .known("5"))
    }

    @Test("a replacement correction recomputes the displayed score")
    func correctionRecompute() {
        let mistaken = bowl(2, batRuns: 6)
        let correction = MatchEvent(
            sequence: 3,
            kind: .correction(CorrectionEvent(
                action: .replace(
                    target: mistaken.id,
                    with: .ball(BallEvent(
                        striker: striker, nonStriker: nonStriker, bowler: bowler, runsOffBat: 4
                    ))
                ),
                reason: "umpire signalled four",
                provenance: "scorer-review"
            ))
        )
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            mistaken,
            correction,
        ])
        #expect(board.scoreline == "4/0")
    }

    @Test("a derived verdict names the winner and closes the match")
    func derivedVerdict() {
        // One-ball-per-innings micro match: Home posts 4, Away is bowled
        // out on its single ball for 0.
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            bowl(2, batRuns: 4),
            MatchEvent(sequence: 3, kind: .inningsEnded(reason: .oversComplete)),
            begin(4, innings: 2, batting: away, bowling: home),
            bowl(5, wicket: WicketEvent(kind: .bowled, dismissed: striker)),
        ], rules: MatchRules(oversPerInnings: 1, ballsPerOver: 1, maxWickets: 2))
        #expect(board.phase == .completed)
        #expect(board.isMatchClosed)
        #expect(board.resultText.rendered == "Home XI won by 4 runs")
        #expect(board.fallbackText.contains("Home XI won by 4 runs"))
        #expect(board.requiredRunRate == .unknown)
    }

    @Test("abandonment renders no verdict, never a fabricated result")
    func abandoned() {
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            bowl(2, batRuns: 1),
            MatchEvent(sequence: 3, kind: .matchAbandoned(reason: "unsafe ground")),
        ])
        #expect(board.phase == .noVerdict)
        #expect(board.isMatchClosed)
        #expect(board.resultText.rendered == "No result: unsafe ground")
        #expect(board.fallbackText.contains("No result"))
    }

    @Test("invalid balls alone keep overs in cricket notation")
    func illegalBalls() {
        let board = present([
            begin(1, innings: 1, batting: home, bowling: away),
            bowl(2, extra: ExtraEvent(kind: .wide, runs: 2)),
            bowl(3, extra: ExtraEvent(kind: .noBall, runs: 1), wicket: WicketEvent(kind: .runOut, dismissed: striker)),
        ])
        #expect(board.scoreline == "3/1")
        #expect(board.overs == "0.0")
    }
}
