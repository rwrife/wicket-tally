import Foundation

/// Ordered participants; the same order is a batting order only when enabled.
/// IDs deliberately survive player deletion. Attribution remains in the ledger.
public struct TeamLineup: Codable, Equatable, Sendable {
    public var playerIDs: [PlayerID]
    public var hasBattingOrder: Bool

    public init(playerIDs: [PlayerID] = [], hasBattingOrder: Bool = false) {
        self.playerIDs = playerIDs
        self.hasBattingOrder = hasBattingOrder
    }
}

public struct LineupTemplate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let teamID: TeamID
    public let name: String
    public let lineup: TeamLineup

    public init(id: String, teamID: TeamID, name: String, lineup: TeamLineup) {
        self.id = id
        self.teamID = teamID
        self.name = name
        self.lineup = lineup
    }
}

public enum LineupError: Error, Equatable, Sendable, LocalizedError {
    case duplicatePlayer
    case unavailablePlayer(PlayerID)
    case teamSizeExceeded(Int)
    case invalidTeam

    public var errorDescription: String? {
        switch self {
        case .duplicatePlayer: return "Select each player only once."
        case .unavailablePlayer: return "Remove or replace unavailable/deleted players before saving."
        case .teamSizeExceeded(let limit): return "Select at most \(limit) players per side. Unknown attribution is still allowed."
        case .invalidTeam: return "Choose a team playing in this fixture."
        }
    }
}
