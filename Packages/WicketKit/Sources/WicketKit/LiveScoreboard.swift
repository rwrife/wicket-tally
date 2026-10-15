import Foundation

/// Pure, deterministic Live Activity presentation derived from replayed
/// ledger state (issue #20). Unknowns render the literal "unknown" —
/// never a guessed zero, target, or verdict. The widget UI and the
/// ActivityKit manager both consume only this struct, so everything the
/// Lock Screen shows is testable without ActivityKit.
public struct LiveScoreboardPresentation: Sendable, Codable, Equatable {
    public enum Phase: String, Sendable, Codable, Hashable {
        case notStarted
        case inProgress
        case inningsBreak
        /// The ledger closed the match with a derived verdict.
        case completed
        /// The ledger closed the match with no live verdict (abandoned or
        /// an unfinished completed status); the scoreboard states exactly that.
        case noVerdict
    }

    /// Raw fixture identifier so an app relaunch can adopt or stop its own
    /// activity. Contains no player names or personal data.
    public let fixtureID: String
    public let homeName: String
    public let awayName: String
    /// The side at the crease; the winning side once a verdict is derived.
    public let battingName: String
    public let scoreline: String
    public let overs: String
    public let wickets: String
    public let phase: Phase
    /// Chase target derived from the ledger only while a chase is defined.
    public let target: TextValue
    public let requiredRunRate: TextValue
    /// One-line result text, populated only for a *derived* verdict.
    public let resultText: TextValue

    public init(
        fixtureID: String,
        homeName: String,
        awayName: String,
        battingName: String,
        scoreline: String,
        overs: String,
        wickets: String,
        phase: Phase,
        target: TextValue,
        requiredRunRate: TextValue,
        resultText: TextValue
    ) {
        self.fixtureID = fixtureID
        self.homeName = homeName
        self.awayName = awayName
        self.battingName = battingName
        self.scoreline = scoreline
        self.overs = overs
        self.wickets = wickets
        self.phase = phase
        self.target = target
        self.requiredRunRate = requiredRunRate
        self.resultText = resultText
    }

    /// True once the ledger has closed the match in any way, so the
    /// companion must stop rather than linger on a finished or verdict-less
    /// match with a stale "live" badge.
    public var isMatchClosed: Bool {
        phase == .completed || phase == .noVerdict
    }

    /// Wrist-sized second line derived only from ledger state: overs, then
    /// chase figures only when the ledger actually defines them. Unknown chase
    /// figures are omitted rather than turned into a zero target or rate.
    public var watchSecondaryLine: String {
        var line = "\(overs) ov"
        if target != .unknown { line += " · need \(target.rendered)" }
        if requiredRunRate != .unknown { line += " · rrr \(requiredRunRate.rendered)" }
        return line
    }

    /// Static text fallback for devices or settings where Live Activities
    /// are unavailable — the same deterministic scoreboard, as one line.
    public var fallbackText: String {
        var line = "\(homeName) vs \(awayName): \(battingName) \(scoreline) (\(overs) ov)"
        if isMatchClosed, resultText != .unknown {
            line += " — \(resultText.rendered)"
        }
        return line
    }
}

public enum LiveScoreboardPresenter {
    public static func present(
        fixtureID: String,
        state: MatchState,
        homeTeamID: TeamID,
        homeName: String,
        awayName: String
    ) -> LiveScoreboardPresentation {
        func name(_ team: TeamID) -> String {
            team == homeTeamID ? homeName : awayName
        }

        let current = state.innings.last
        let battingName = current.map { name($0.battingTeam) } ?? "Awaiting toss"
        let scoreline = current?.scoreline ?? "unknown"
        let overs = current?.oversString(ballsPerOver: state.rules.ballsPerOver) ?? "unknown"
        let wickets = current.map { "\($0.wickets)" } ?? "unknown"

        let phase: LiveScoreboardPresentation.Phase
        let target: TextValue
        let resultText: TextValue
        var battingOverride: String?
        switch state.status {
        case .notStarted:
            phase = .notStarted
            target = .unknown
            resultText = .unknown
        case .inProgress:
            phase = .inProgress
            target = state.innings.count == 2 && state.innings[0].isComplete
                ? .known("\(state.innings[0].runs + 1)")
                : .unknown
            resultText = .unknown
        case let .inningsBreak(chaseTarget):
            phase = .inningsBreak
            target = .known("\(chaseTarget)")
            resultText = .unknown
        case let .completed(result):
            switch result {
            case let .wonByRuns(team, runs):
                phase = .completed
                battingOverride = name(team)
                resultText = .known("\(name(team)) won by \(runs) runs")
            case let .wonByWickets(team, wicketsRemaining):
                phase = .completed
                battingOverride = name(team)
                resultText = .known("\(name(team)) won by \(wicketsRemaining) wickets")
            case .tie:
                phase = .completed
                resultText = .known("Match tied")
            case let .noResult(reason):
                phase = .noVerdict
                resultText = .known("No result: \(reason)")
            }
            target = .unknown
        }

        // Required run rate is only meaningful during a live chase; an
        // unknown rate stays unknown rather than rendering "unknown" as a
        // known string.
        let requiredRunRate: TextValue
        if state.status == .inProgress, case .known = state.requiredRunRate {
            requiredRunRate = .known(UnknownSafeFormatter.rateString(state.requiredRunRate))
        } else {
            requiredRunRate = .unknown
        }

        return LiveScoreboardPresentation(
            fixtureID: fixtureID,
            homeName: homeName,
            awayName: awayName,
            battingName: battingOverride ?? battingName,
            scoreline: scoreline,
            overs: overs,
            wickets: wickets,
            phase: phase,
            target: target,
            requiredRunRate: requiredRunRate,
            resultText: resultText
        )
    }
}
