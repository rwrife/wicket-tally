import Foundation

/// Plan for an ad-hoc, impromptu game (issue #16): two names, one rules
/// choice, no league/team/ground setup. The plan is the pure derivation
/// layer; `WicketStore.startAdhocMatch` materializes it into local records.
///
/// The names here are user-entered facts about who showed up to play —
/// never a formal team registry.
public struct AdhocMatchPlan: Sendable, Codable, Equatable {
    public static let maxNameLength = 40
    public static let matchWindow: TimeInterval = 4 * 60 * 60

    public let homeName: String
    public let awayName: String
    public let fixtureName: String
    public let rules: MatchRules
    public let startsAt: Date
    public let endsAt: Date

    public init(homeName: String, awayName: String, rules: MatchRules, startingAt start: Date) throws {
        let home = homeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let away = awayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty else { throw AdhocMatchPlanError.homeNameRequired }
        guard !away.isEmpty else { throw AdhocMatchPlanError.awayNameRequired }
        guard home.count <= Self.maxNameLength else { throw AdhocMatchPlanError.homeNameTooLong }
        guard away.count <= Self.maxNameLength else { throw AdhocMatchPlanError.awayNameTooLong }
        self.homeName = home
        self.awayName = away
        self.fixtureName = "\(home) vs \(away)"
        self.rules = rules
        self.startsAt = start
        self.endsAt = start.addingTimeInterval(Self.matchWindow)
    }

    /// Factual one-line description of the plan; no rule verdicts.
    public var summary: String {
        "Ad-hoc game: \(fixtureName) | \(rules.summary)"
    }
}

public enum AdhocMatchPlanError: Error, Equatable, Sendable, LocalizedError {
    case homeNameRequired
    case awayNameRequired
    case homeNameTooLong
    case awayNameTooLong

    public var errorDescription: String? {
        switch self {
        case .homeNameRequired: return "Enter a name for the home side."
        case .awayNameRequired: return "Enter a name for the away side."
        case .homeNameTooLong: return "Side names are limited to \(AdhocMatchPlan.maxNameLength) characters."
        case .awayNameTooLong: return "Side names are limited to \(AdhocMatchPlan.maxNameLength) characters."
        }
    }
}
