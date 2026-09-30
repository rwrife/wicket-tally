import Foundation

public enum StatsDerivationError: Error, Equatable, Sendable, LocalizedError {
    case duplicateEventID
    case duplicateSequence(Int)
    case invalidCorrectionTarget(EventID)
    case unsupportedCorrection(EventID)
    case missingProvenance(EventID)
    case duplicateFixture(FixtureID)
    case invalidTeams(FixtureID)
    case invalidPointsOverride
    case duplicatePointsOverride(TeamID)
    case unknownOverrideTeam(TeamID)

    public var errorDescription: String? {
        switch self {
        case .duplicateEventID: return "The ledger contains duplicate event IDs."
        case let .duplicateSequence(sequence): return "The ledger repeats sequence \(sequence)."
        case .invalidCorrectionTarget: return "A correction must target an earlier event in the same ledger."
        case .unsupportedCorrection: return "Corrections of corrections are not supported by the stats projection."
        case .missingProvenance: return "A correction needs a reason and provenance."
        case let .duplicateFixture(id): return "Fixture \(id.rawValue) was supplied more than once."
        case let .invalidTeams(id): return "Fixture \(id.rawValue) has inconsistent teams."
        case .invalidPointsOverride: return "Manual points require a reason, provenance, and valid date."
        case .duplicatePointsOverride: return "Supply only the current points override for each team."
        case .unknownOverrideTeam: return "The points override refers to a team outside this league."
        }
    }
}

/// Validates an append-only stream before applying the same first-order correction
/// policy as MatchLedger: invalidation wins; the last replacement wins otherwise.
/// Corrections of corrections are rejected rather than given divergent semantics.
enum StatsEffectiveEvents {
    static func resolve(_ ledger: MatchLedger) throws -> [MatchEvent] {
        let sorted = ledger.events.sorted { $0.sequence < $1.sequence }
        var seen: [EventID: MatchEvent] = [:]
        var sequences = Set<Int>()
        var invalidated = Set<EventID>()
        var replacements: [EventID: MatchEventKind] = [:]
        for event in sorted {
            guard seen[event.id] == nil else { throw StatsDerivationError.duplicateEventID }
            guard sequences.insert(event.sequence).inserted else {
                throw StatsDerivationError.duplicateSequence(event.sequence)
            }
            if case let .correction(correction) = event.kind {
                guard !correction.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !correction.provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StatsDerivationError.missingProvenance(event.id)
                }
                switch correction.action {
                case let .invalidate(target):
                    try validate(target, in: seen)
                    invalidated.insert(target)
                case let .replace(target, with: kind):
                    try validate(target, in: seen)
                    if case .correction = kind {
                        throw StatsDerivationError.unsupportedCorrection(event.id)
                    }
                    replacements[target] = kind
                case .scoreAdjustment:
                    break
                }
            }
            seen[event.id] = event
        }
        return sorted.compactMap { event in
            guard !invalidated.contains(event.id) else { return nil }
            return MatchEvent(id: event.id, sequence: event.sequence, kind: replacements[event.id] ?? event.kind)
        }
    }

    private static func validate(_ target: EventID, in seen: [EventID: MatchEvent]) throws {
        guard let original = seen[target] else {
            throw StatsDerivationError.invalidCorrectionTarget(target)
        }
        if case .correction = original.kind {
            throw StatsDerivationError.unsupportedCorrection(target)
        }
    }
}

public struct ScorecardBattingLine: Equatable, Sendable {
    /// nil is the explicitly unattributed batter, never an invented player.
    public let playerID: PlayerID?
    public internal(set) var runs = 0
    public internal(set) var balls = 0
    /// Ledger records runs, not boundary signals: counts four/six-run shots.
    public internal(set) var fours = 0
    public internal(set) var sixes = 0
    public internal(set) var dismissal: WicketEvent?
    public internal(set) var dismissalBowler: PlayerID?
    public var strikeRate: NumericValue {
        balls > 0 ? .known(Double(runs) * 100 / Double(balls)) : .unknown
    }
}

public struct ScorecardBowlingLine: Equatable, Sendable {
    public let playerID: PlayerID?
    public internal(set) var legalDeliveries = 0
    public internal(set) var maidens = 0
    public internal(set) var runs = 0
    public internal(set) var wickets = 0
    public let ballsPerOver: Int
    public var overs: String { legalDeliveries.cricketOversString(ballsPerOver: ballsPerOver) }
    public var economy: NumericValue {
        legalDeliveries > 0 ? .known(Double(runs) * Double(ballsPerOver) / Double(legalDeliveries)) : .unknown
    }
}

public struct ScorecardExtras: Equatable, Sendable {
    public internal(set) var wides = 0
    public internal(set) var noBalls = 0
    public internal(set) var byes = 0
    public internal(set) var legByes = 0
    public internal(set) var penalties = 0
    public var total: Int { wides + noBalls + byes + legByes + penalties }
}

public struct ScorecardFallOfWicket: Equatable, Sendable {
    public let wicket: Int
    public let runs: Int
    public let legalDeliveries: Int
    public let dismissed: PlayerID
    public let kind: WicketKind
    /// Scheduled-over position, including run-cut overs under house rules.
    public let overs: String
}

public struct ScorecardInnings: Equatable, Sendable {
    public let state: InningsState
    public let batting: [ScorecardBattingLine]
    public let bowling: [ScorecardBowlingLine]
    public let extras: ScorecardExtras
    public let fallOfWickets: [ScorecardFallOfWicket]
    /// Direct adjustments cannot safely be assigned to a batter, bowler, or wicket.
    public let adjustments: [CorrectionEvent]
    public let endReason: InningsEndReason?
    public let hasUnknownBatting: Bool
    public let hasUnknownBowling: Bool
}

public struct MatchScorecard: Equatable, Sendable {
    public let rules: MatchRules
    public let innings: [ScorecardInnings]
    /// Canonical ledger status. Use `result` for standings: it additionally
    /// guards incomplete innings, abandonment, and unsupported attribution.
    public let status: MatchStatus
    public let warnings: [String]
    /// nil means the result must not contribute a win/loss/tie or derived points.
    public let result: MatchResult?
    public let resultUnavailableReason: String?
    public let nrrUnavailableReason: String?

    /// Recorded figures remain visible for unfinished games, explicitly labelled
    /// partial. League aggregates use unknown instead of treating them as final.
    public func plainText(
        title: String = "Match scorecard",
        teamNames: [TeamID: String] = [:],
        playerNames: [PlayerID: String] = [:]
    ) -> String {
        func player(_ id: PlayerID?) -> String {
            guard let id else { return "Unknown player" }
            return playerNames[id] ?? id.rawValue
        }
        func team(_ id: TeamID) -> String { teamNames[id] ?? id.rawValue }
        var lines = [title]
        if let result {
            switch result {
            case let .wonByRuns(id, runs): lines.append("\(team(id)) won by \(runs) runs")
            case let .wonByWickets(id, wickets): lines.append("\(team(id)) won by \(wickets) wickets")
            case .tie: lines.append("Tie")
            case let .noResult(reason): lines.append("No result: \(reason)")
            }
        } else {
            lines.append("Result: unknown - \(resultUnavailableReason ?? "incomplete match")")
        }
        lines.append("Rules: \(rules.summary)")
        for innings in innings {
            let state = innings.state
            lines += [
                "",
                "Innings \(state.number): \(team(state.battingTeam)) \(state.scoreline) (\(state.oversString(ballsPerOver: rules.ballsPerOver)) overs)",
                result == nil ? "Recorded figures (partial/unresolved)" : "Recorded figures",
                "Batting: runs balls 4s 6s SR dismissal",
            ]
            for row in innings.batting {
                let dismissal: String
                if let wicket = row.dismissal {
                    var detail = wicket.kind.rawValue
                    if wicket.isOneHandCatch { detail += " (one hand)" }
                    if [.caught, .stumped, .runOut].contains(wicket.kind) {
                        detail += " fielder \(player(wicket.fielder))"
                    }
                    if [.bowled, .caught, .lbw, .stumped, .hitWicket].contains(wicket.kind) {
                        detail += " b \(player(row.dismissalBowler))"
                    }
                    dismissal = detail
                } else {
                    dismissal = state.isComplete && result != nil ? "not out" : "not dismissed (partial)"
                }
                lines.append("\(player(row.playerID)): \(row.runs) \(row.balls) \(row.fours) \(row.sixes) \(UnknownSafeFormatter.rateString(row.strikeRate)) \(dismissal)")
            }
            let extras = innings.extras
            lines.append("Extras: \(extras.total) (wd \(extras.wides), nb \(extras.noBalls), b \(extras.byes), lb \(extras.legByes), penalty \(extras.penalties))")
            for adjustment in innings.adjustments {
                if case let .scoreAdjustment(delta) = adjustment.action {
                    lines.append("Unattributed adjustment: runs \(delta.runsDelta), wickets \(delta.wicketsDelta); \(adjustment.reason) [\(adjustment.provenance)]")
                }
            }
            lines.append("Bowling: overs maidens runs wickets economy")
            for row in innings.bowling {
                lines.append("\(player(row.playerID)): \(row.overs) \(row.maidens) \(row.runs) \(row.wickets) \(UnknownSafeFormatter.rateString(row.economy))")
            }
            lines.append("Fall of wickets: " + (innings.fallOfWickets.isEmpty ? "none recorded" : innings.fallOfWickets.map {
                "\($0.wicket)-\($0.runs) \(player($0.dismissed)) (\($0.overs))"
            }.joined(separator: ", ")))
        }
        if let reason = nrrUnavailableReason { lines.append("NRR hidden: \(reason)") }
        lines.append(contentsOf: warnings.map { "Warning: \($0)" })
        return lines.joined(separator: "\n")
    }
}
