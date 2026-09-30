import Foundation

/// A user-owned scoring contract. Copy a league's preset into a match before
/// scoring; later league edits must not change that match's recorded contract.
public struct RulePreset: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let oversPerInnings: Int
    public let ballsPerOver: Int
    public let playersPerSide: Int
    /// Bat runs plus extras close an over at or above this total. The full
    /// crossing delivery counts; excess runs do not carry into the next over.
    public let maxRunsPerOver: Int?
    /// Ends an innings after the full scoring event reaches this total.
    public let inningsRunCap: Int?
    /// Quick-entry choices, not a restriction on recorded delivery totals.
    public let runPresets: [Int]
    public let oneHandCatchAllowed: Bool

    public static let overRange = 1...50
    public static let ballsPerOverRange = 1...12
    public static let playersPerSideRange = 2...11
    public static let overRunCutRange = 1...100
    public static let inningsRunCapRange = 1...1_000
    public static let runPresetRange = 0...12
    public static let standardRunPresets = [0, 1, 2, 3, 4, 6]

    public init(
        id: UUID = UUID(),
        name: String,
        oversPerInnings: Int = 20,
        ballsPerOver: Int = 6,
        playersPerSide: Int = 11,
        maxRunsPerOver: Int? = nil,
        inningsRunCap: Int? = nil,
        runPresets: [Int] = RulePreset.standardRunPresets,
        oneHandCatchAllowed: Bool = false
    ) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else {
            throw RulePresetError.invalidName
        }
        guard Self.overRange.contains(oversPerInnings) else { throw RulePresetError.invalidOvers }
        guard Self.ballsPerOverRange.contains(ballsPerOver) else { throw RulePresetError.invalidBallsPerOver }
        guard Self.playersPerSideRange.contains(playersPerSide) else { throw RulePresetError.invalidTeamSize }
        if let maxRunsPerOver, !Self.overRunCutRange.contains(maxRunsPerOver) {
            throw RulePresetError.invalidOverRunCut
        }
        if let inningsRunCap, !Self.inningsRunCapRange.contains(inningsRunCap) {
            throw RulePresetError.invalidInningsRunCap
        }
        guard !runPresets.isEmpty,
              runPresets.count <= Self.runPresetRange.count,
              Set(runPresets).count == runPresets.count,
              runPresets.allSatisfy(Self.runPresetRange.contains) else {
            throw RulePresetError.invalidRunPresets
        }
        self.id = id
        self.name = name
        self.oversPerInnings = oversPerInnings
        self.ballsPerOver = ballsPerOver
        self.playersPerSide = playersPerSide
        self.maxRunsPerOver = maxRunsPerOver
        self.inningsRunCap = inningsRunCap
        self.runPresets = runPresets
        self.oneHandCatchAllowed = oneHandCatchAllowed
    }

    public static let standard = RulePreset(
        standardID: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    )

    private init(standardID: UUID) {
        id = standardID
        name = "Standard limited overs"
        oversPerInnings = 20
        ballsPerOver = 6
        playersPerSide = 11
        maxRunsPerOver = nil
        inningsRunCap = nil
        runPresets = Self.standardRunPresets
        oneHandCatchAllowed = false
    }

    public var rules: MatchRules { MatchRules(preset: self) }

    /// Factual header copy; describes the agreed settings, not umpiring advice.
    public var summary: String { rules.summary }

    private enum CodingKeys: String, CodingKey {
        case id, name, oversPerInnings, ballsPerOver, playersPerSide
        case maxRunsPerOver, inningsRunCap, runPresets, oneHandCatchAllowed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            oversPerInnings: container.decode(Int.self, forKey: .oversPerInnings),
            ballsPerOver: container.decode(Int.self, forKey: .ballsPerOver),
            playersPerSide: container.decode(Int.self, forKey: .playersPerSide),
            maxRunsPerOver: container.decodeIfPresent(Int.self, forKey: .maxRunsPerOver),
            inningsRunCap: container.decodeIfPresent(Int.self, forKey: .inningsRunCap),
            runPresets: container.decode([Int].self, forKey: .runPresets),
            oneHandCatchAllowed: container.decode(Bool.self, forKey: .oneHandCatchAllowed)
        )
    }
}

public enum RulePresetError: Error, Sendable, Equatable, LocalizedError {
    case invalidName
    case invalidOvers
    case invalidBallsPerOver
    case invalidTeamSize
    case invalidOverRunCut
    case invalidInningsRunCap
    case invalidRunPresets

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a preset name of 1 to 80 characters."
        case .invalidOvers: return "Choose 1 to 50 overs per innings."
        case .invalidBallsPerOver: return "Choose 1 to 12 balls per over."
        case .invalidTeamSize: return "Choose 2 to 11 players per side."
        case .invalidOverRunCut: return "Choose an over run cutoff of 1 to 100, or leave it off."
        case .invalidInningsRunCap: return "Choose an innings run cap of 1 to 1000, or leave it off."
        case .invalidRunPresets: return "Choose distinct run buttons from 0 to 12, with at least one button."
        }
    }
}

public extension MatchRules {
    var presetID: UUID? { preset?.id }
    var presetName: String { preset?.name ?? "Standard limited overs" }
    var playersPerSide: Int { preset?.playersPerSide ?? (maxWickets == Int.max ? Int.max : maxWickets + 1) }
    var maxRunsPerOver: Int? { preset?.maxRunsPerOver }
    var inningsRunCap: Int? { preset?.inningsRunCap }
    var runPresets: [Int] { preset?.runPresets ?? RulePreset.standardRunPresets }
    var oneHandCatchAllowed: Bool { preset?.oneHandCatchAllowed ?? false }

    var summary: String {
        var parts = [
            "\(oversPerInnings) overs",
            "\(ballsPerOver) balls/over",
            "\(playersPerSide) a side",
        ]
        if let maxRunsPerOver { parts.append("\(maxRunsPerOver) runs cut/over") }
        if let inningsRunCap { parts.append("\(inningsRunCap) run innings cap") }
        parts.append("Run buttons: " + runPresets.map(String.init).joined(separator: ", "))
        parts.append(oneHandCatchAllowed ? "One-hand catch on" : "One-hand catch off")
        return parts.joined(separator: " | ")
    }
}
