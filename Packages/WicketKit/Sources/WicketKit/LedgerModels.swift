import Foundation

public struct TeamID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct PlayerID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

public struct EventID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum TossDecision: String, Sendable, Codable {
    case bat
    case bowl
}

public enum WicketKind: String, Sendable, Codable {
    case bowled
    case caught
    case lbw
    case runOut
    case stumped
    case hitWicket
    case retired
    case obstructingField
    case timedOut
    case hitBallTwice
}

public struct WicketEvent: Sendable, Codable, Equatable {
    public let kind: WicketKind
    public let dismissed: PlayerID
    public let fielder: PlayerID?

    public init(kind: WicketKind, dismissed: PlayerID, fielder: PlayerID? = nil) {
        self.kind = kind
        self.dismissed = dismissed
        self.fielder = fielder
    }
}

public enum ExtraType: String, Sendable, Codable {
    /// One (or more) wides. Not a legal delivery.
    case wide
    /// One (or more) no-ball runs. Not a legal delivery.
    case noBall
    /// Bye runs. Legal delivery.
    case bye
    /// Leg-bye runs. Legal delivery.
    case legBye
}

public struct ExtraEvent: Sendable, Codable, Equatable {
    public let kind: ExtraType
    /// Total runs awarded for this extra event.
    /// Example: no-ball + 2 run scramble => runs = 3.
    public let runs: Int

    public init(kind: ExtraType, runs: Int) {
        self.kind = kind
        self.runs = max(0, runs)
    }

    public var isLegalDelivery: Bool {
        switch kind {
        case .wide, .noBall:
            return false
        case .bye, .legBye:
            return true
        }
    }
}

public struct BallEvent: Sendable, Codable, Equatable {
    public let striker: PlayerID?
    public let nonStriker: PlayerID?
    public let bowler: PlayerID?
    public let runsOffBat: Int
    public let extra: ExtraEvent?
    public let wicket: WicketEvent?

    public init(
        striker: PlayerID?,
        nonStriker: PlayerID?,
        bowler: PlayerID?,
        runsOffBat: Int,
        extra: ExtraEvent? = nil,
        wicket: WicketEvent? = nil
    ) {
        self.striker = striker
        self.nonStriker = nonStriker
        self.bowler = bowler
        self.runsOffBat = max(0, runsOffBat)
        self.extra = extra
        self.wicket = wicket
    }

    public var extraRuns: Int { extra?.runs ?? 0 }
    public var totalRuns: Int { runsOffBat + extraRuns }

    public var isLegalDelivery: Bool {
        if let extra {
            return extra.isLegalDelivery
        }
        return true
    }

    public var countsAsWicket: Bool {
        guard let wicket else { return false }
        guard let extra else { return true }

        switch extra.kind {
        case .noBall:
            switch wicket.kind {
            case .runOut, .obstructingField, .hitBallTwice:
                return true
            default:
                return false
            }
        case .wide:
            switch wicket.kind {
            case .runOut, .stumped, .obstructingField, .hitBallTwice:
                return true
            default:
                return false
            }
        case .bye, .legBye:
            return true
        }
    }
}

public enum InningsEndReason: String, Sendable, Codable {
    case allOut
    case oversComplete
    case chaseCompleted
    case declared
    case abandoned
}

public struct ScoreAdjustment: Sendable, Codable, Equatable {
    public let runsDelta: Int
    public let wicketsDelta: Int

    public init(runsDelta: Int = 0, wicketsDelta: Int = 0) {
        self.runsDelta = runsDelta
        self.wicketsDelta = wicketsDelta
    }
}

public indirect enum CorrectionAction: Sendable, Codable, Equatable {
    /// Ignore the targeted event in replay.
    case invalidate(target: EventID)
    /// Replace an old event with a new payload.
    case replace(target: EventID, with: MatchEventKind)
    /// Direct score adjustment with explicit provenance.
    case scoreAdjustment(ScoreAdjustment)
}

public struct CorrectionEvent: Sendable, Codable, Equatable {
    public let action: CorrectionAction
    public let reason: String
    public let provenance: String

    public init(action: CorrectionAction, reason: String, provenance: String) {
        self.action = action
        self.reason = reason
        self.provenance = provenance
    }
}

public struct PenaltyRunEvent: Sendable, Codable, Equatable {
    public let awardedToBatting: Bool
    public let runs: Int
    public let reason: String

    public init(awardedToBatting: Bool, runs: Int, reason: String) {
        self.awardedToBatting = awardedToBatting
        self.runs = max(0, runs)
        self.reason = reason
    }
}

public indirect enum MatchEventKind: Sendable, Codable, Equatable {
    case toss(winner: TeamID, decision: TossDecision)
    case inningsStarted(number: Int, batting: TeamID, bowling: TeamID)
    case ball(BallEvent)
    case overCompleted
    case penaltyRuns(PenaltyRunEvent)
    case inningsEnded(reason: InningsEndReason)
    case matchAbandoned(reason: String)
    case correction(CorrectionEvent)
}

public struct MatchEvent: Sendable, Codable, Equatable {
    public let id: EventID
    public let sequence: Int
    public let kind: MatchEventKind

    public init(id: EventID = EventID(), sequence: Int, kind: MatchEventKind) {
        self.id = id
        self.sequence = sequence
        self.kind = kind
    }
}

public struct MatchRules: Sendable, Codable, Equatable {
    public let oversPerInnings: Int
    public let ballsPerOver: Int
    public let maxWickets: Int

    public init(oversPerInnings: Int, ballsPerOver: Int = 6, maxWickets: Int = 10) {
        self.oversPerInnings = max(1, oversPerInnings)
        self.ballsPerOver = max(1, ballsPerOver)
        self.maxWickets = max(1, maxWickets)
    }

    public static let t10 = MatchRules(oversPerInnings: 10, ballsPerOver: 6, maxWickets: 10)
    public static let t20 = MatchRules(oversPerInnings: 20, ballsPerOver: 6, maxWickets: 10)
    public static let odi = MatchRules(oversPerInnings: 50, ballsPerOver: 6, maxWickets: 10)

    public var maxLegalDeliveriesPerInnings: Int {
        oversPerInnings * ballsPerOver
    }
}

public enum NumericValue: Sendable, Codable, Equatable {
    case known(Double)
    case unknown

    public var isKnown: Bool {
        if case .known = self { return true }
        return false
    }
}

public enum TextValue: Sendable, Codable, Equatable {
    case known(String)
    case unknown

    public var rendered: String {
        switch self {
        case let .known(value): return value
        case .unknown: return "unknown"
        }
    }
}

public enum MatchResult: Sendable, Codable, Equatable {
    case wonByRuns(team: TeamID, runs: Int)
    case wonByWickets(team: TeamID, wickets: Int)
    case tie
    case noResult(reason: String)
}

public enum MatchStatus: Sendable, Codable, Equatable {
    case notStarted
    case inProgress
    case inningsBreak(target: Int)
    case completed(MatchResult)
}

public struct InningsState: Sendable, Codable, Equatable {
    public let number: Int
    public let battingTeam: TeamID
    public let bowlingTeam: TeamID
    public let runs: Int
    public let wickets: Int
    public let legalDeliveries: Int
    public let isComplete: Bool

    public init(
        number: Int,
        battingTeam: TeamID,
        bowlingTeam: TeamID,
        runs: Int,
        wickets: Int,
        legalDeliveries: Int,
        isComplete: Bool = false
    ) {
        self.number = number
        self.battingTeam = battingTeam
        self.bowlingTeam = bowlingTeam
        self.runs = max(0, runs)
        self.wickets = max(0, wickets)
        self.legalDeliveries = max(0, legalDeliveries)
        self.isComplete = isComplete
    }

    public var scoreline: String {
        "\(runs)/\(wickets)"
    }
}

public struct ScorecardLine: Sendable, Codable, Equatable {
    public let innings: Int
    public let team: TeamID
    public let score: String
    public let overs: String
}

public struct MatchState: Sendable, Codable, Equatable {
    public let rules: MatchRules
    public let innings: [InningsState]
    public let status: MatchStatus
    public let currentRunRate: NumericValue
    public let requiredRunRate: NumericValue
    public let oversRemaining: NumericValue
    public let ballsRemaining: NumericValue
    public let scorecard: [ScorecardLine]

    public init(
        rules: MatchRules,
        innings: [InningsState],
        status: MatchStatus,
        currentRunRate: NumericValue,
        requiredRunRate: NumericValue,
        oversRemaining: NumericValue,
        ballsRemaining: NumericValue,
        scorecard: [ScorecardLine]
    ) {
        self.rules = rules
        self.innings = innings
        self.status = status
        self.currentRunRate = currentRunRate
        self.requiredRunRate = requiredRunRate
        self.oversRemaining = oversRemaining
        self.ballsRemaining = ballsRemaining
        self.scorecard = scorecard
    }
}

public struct MatchLedger: Sendable, Codable, Equatable {
    public let events: [MatchEvent]

    public init(events: [MatchEvent]) {
        self.events = events.sorted { $0.sequence < $1.sequence }
    }

    public func replay(rules: MatchRules) -> MatchState {
        MatchReplayEngine(rules: rules).replay(events: events)
    }
}

public extension Int {
    /// Cricket overs text from legal deliveries, e.g. 18.2
    func cricketOversString(ballsPerOver: Int) -> String {
        guard ballsPerOver > 0 else { return "unknown" }
        let overs = self / ballsPerOver
        let balls = self % ballsPerOver
        return "\(overs).\(balls)"
    }
}
