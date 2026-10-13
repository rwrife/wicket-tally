#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Local Live Activity attributes (issue #20), compiled into WicketKit so the
/// app target and the scoreboard widget extension share one definition.
/// Lives inside the pure package: only Foundation + ActivityKit, and the
/// whole file compiles away on platforms without ActivityKit (Linux CI).
///
/// Zero-network by construction: the app requests the activity with
/// `pushType: nil`, and every displayed value is a
/// `LiveScoreboardPresentation` derived from the local append-only ledger.
public struct MatchScoreboardActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let homeName: String
        public let awayName: String
        public let battingName: String
        public let scoreline: String
        public let overs: String
        public let phase: LiveScoreboardPresentation.Phase
        /// Rendered target text; the literal "unknown" when not derivable.
        public let target: String
        public let requiredRunRate: String
        public let resultText: String
        public let isMatchClosed: Bool

        public init(presentation: LiveScoreboardPresentation) {
            homeName = presentation.homeName
            awayName = presentation.awayName
            battingName = presentation.battingName
            scoreline = presentation.scoreline
            overs = presentation.overs
            phase = presentation.phase
            target = presentation.target.rendered
            requiredRunRate = presentation.requiredRunRate.rendered
            resultText = presentation.resultText.rendered
            isMatchClosed = presentation.isMatchClosed
        }
    }

    /// Raw fixture identifier so an app relaunch can adopt or stop its own
    /// activity. No personal data crosses into the widget.
    public let fixtureID: String

    public init(fixtureID: String) {
        self.fixtureID = fixtureID
    }
}
#endif
