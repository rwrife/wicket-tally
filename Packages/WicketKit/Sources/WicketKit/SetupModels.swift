import Foundation

/// League/tournament, team, and player identity and domain models for the
/// setup CRUD flow (issue #3). These types are pure Swift — persistence and
/// GRDB mapping live in `WicketStore`; UI theming (Indica tokens) lives in
/// the design-system pass (issue #9) and consumes `TeamKitColour` only.
public struct LeagueID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

/// A league runs across a season (points table); a tournament is a single
/// knockout/round-robin event. Both share the same setup and scheduling
/// machinery — the distinction only affects standings semantics (issue #7).
public enum LeagueKind: String, Sendable, Codable, CaseIterable {
    case league
    case tournament

    public var displayName: String {
        switch self {
        case .league: return "League"
        case .tournament: return "Tournament"
        }
    }
}

/// Batting/bowling role tag shown on player setup rows and used later by
/// scorer defaults (issue #5) and player stat cards (issue #7).
public enum PlayerRole: String, Sendable, Codable, CaseIterable {
    case batter
    case bowler
    case allRounder
    case wicketKeeper

    public var displayName: String {
        switch self {
        case .batter: return "Batter"
        case .bowler: return "Bowler"
        case .allRounder: return "All-rounder"
        case .wicketKeeper: return "Wicket-keeper"
        }
    }
}

/// The Indica saturated team-colour kit system (issue #9 defines the full
/// design-token palette; this is the closed set of jersey colours a team can
/// be assigned during setup). Every case ships a hex value so `WicketStore`
/// and preview/UI code never hardcode colors — the design-system pass
/// consumes these tokens, it does not reinvent them.
public enum TeamKitColour: String, Sendable, Codable, CaseIterable {
    case cricketRed
    case saffron
    case wicketGreen
    case royalPurple
    case skyBlue
    case marigold
    case sunsetOrange
    case peacockTeal

    public var displayName: String {
        switch self {
        case .cricketRed: return "Cricket Red"
        case .saffron: return "Saffron"
        case .wicketGreen: return "Wicket Green"
        case .royalPurple: return "Royal Purple"
        case .skyBlue: return "Sky Blue"
        case .marigold: return "Marigold"
        case .sunsetOrange: return "Sunset Orange"
        case .peacockTeal: return "Peacock Teal"
        }
    }

    /// sRGB hex (no alpha), e.g. "C92A2A". Saturated, high-contrast values
    /// chosen to read clearly as jersey-style chips outdoors.
    public var hexRGB: String {
        switch self {
        case .cricketRed: return "C92A2A"
        case .saffron: return "F76707"
        case .wicketGreen: return "2B8A3E"
        case .royalPurple: return "6741D9"
        case .skyBlue: return "1971C2"
        case .marigold: return "F08C00"
        case .sunsetOrange: return "E8590C"
        case .peacockTeal: return "0B7285"
        }
    }

    /// All these kit colours are dark/saturated enough that white text/icons
    /// read correctly on top of them (contrast audited alongside issue #9).
    public var prefersLightForeground: Bool { true }
}

public struct LeagueRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: LeagueID
    public let name: String
    public let kind: LeagueKind
    public let isArchived: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: LeagueID,
        name: String,
        kind: LeagueKind,
        isArchived: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TeamRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: TeamID
    public let leagueID: LeagueID
    public let name: String
    public let colour: TeamKitColour
    public let isArchived: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: TeamID,
        leagueID: LeagueID,
        name: String,
        colour: TeamKitColour,
        isArchived: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.leagueID = leagueID
        self.name = name
        self.colour = colour
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PlayerRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: PlayerID
    public let teamID: TeamID
    public let name: String
    public let role: PlayerRole
    public let isArchived: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: PlayerID,
        teamID: TeamID,
        name: String,
        role: PlayerRole,
        isArchived: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.teamID = teamID
        self.name = name
        self.role = role
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Explicit, human-readable cascade preview shown before any destructive
/// deletion — the product contract forbids silent destruction of children.
public struct LeagueDeletionPreview: Sendable, Codable, Equatable {
    public let leagueID: LeagueID
    public let leagueName: String
    public let teamCount: Int
    public let playerCount: Int

    public init(leagueID: LeagueID, leagueName: String, teamCount: Int, playerCount: Int) {
        self.leagueID = leagueID
        self.leagueName = leagueName
        self.teamCount = teamCount
        self.playerCount = playerCount
    }

    /// Always 1 for a league preview; kept for a uniform "N leagues" phrasing
    /// helper shared with the other preview summaries.
    public var leagueCount: Int { 1 }

    public var summary: String {
        var parts: [String] = []
        if teamCount > 0 {
            parts.append(teamCount == 1 ? "1 team" : "\(teamCount) teams")
        }
        if playerCount > 0 {
            parts.append(playerCount == 1 ? "1 player" : "\(playerCount) players")
        }
        guard !parts.isEmpty else { return "Delete \(leagueName)" }
        if parts.count == 1 {
            return "Delete \(leagueName), \(parts[0])"
        }
        let prefix = parts.dropLast().joined(separator: ", ")
        let tail = parts.last ?? ""
        return "Delete \(leagueName), \(prefix), and \(tail)"
    }
}

public struct TeamDeletionPreview: Sendable, Codable, Equatable {
    public let teamID: TeamID
    public let teamName: String
    public let playerCount: Int

    public init(teamID: TeamID, teamName: String, playerCount: Int) {
        self.teamID = teamID
        self.teamName = teamName
        self.playerCount = playerCount
    }

    public var summary: String {
        guard playerCount > 0 else { return "Delete \(teamName)" }
        let noun = playerCount == 1 ? "player" : "players"
        return "Delete \(teamName) and \(playerCount) \(noun)"
    }
}

public struct PlayerDeletionPreview: Sendable, Codable, Equatable {
    public let playerID: PlayerID
    public let playerName: String

    public init(playerID: PlayerID, playerName: String) {
        self.playerID = playerID
        self.playerName = playerName
    }

    public var summary: String { "Delete \(playerName)" }
}
