import Foundation

public struct GroundID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { rawValue = value }
}

public struct FixtureID: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: StringLiteralType) { rawValue = value }
}

public struct GroundRecord: Sendable, Codable, Equatable, Identifiable {
    public let id: GroundID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: GroundID, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A reminder is an opt-in, local notification offset from the recorded start
/// instant. Subtracting a duration from the instant keeps it correct through
/// daylight-saving gaps and repeated wall-clock hours.
public enum FixtureReminder: Int, Sendable, Codable, CaseIterable {
    case none = 0
    case fifteenMinutesBefore = 15
    case oneHourBefore = 60
    case oneDayBefore = 1_440

    public var displayName: String {
        switch self {
        case .none: return "No reminder"
        case .fifteenMinutesBefore: return "15 minutes before"
        case .oneHourBefore: return "1 hour before"
        case .oneDayBefore: return "1 day before"
        }
    }

    public func reminderDate(for start: Date, calendar: Calendar = .current) -> Date? {
        guard self != .none else { return nil }
        _ = calendar
        return start.addingTimeInterval(-Double(rawValue * 60))
    }
}

public enum FixtureValidationError: Error, Equatable, Sendable {
    case invalidTimeSlot
    case sameTeam
}

/// Hashable so a fixture can be a `NavigationStack` value destination: an
/// impromptu game (issue #16) pushes the scorer programmatically right
/// after the quick-game sheet dismisses.
public struct FixtureRecord: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: FixtureID
    public let leagueID: LeagueID?
    public let name: String
    public let homeTeamID: TeamID
    public let awayTeamID: TeamID
    public let groundID: GroundID
    public let participatingPlayerIDs: Set<PlayerID>
    public let startsAt: Date
    public let endsAt: Date
    public let reminder: FixtureReminder
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: FixtureID,
        leagueID: LeagueID?,
        name: String,
        homeTeamID: TeamID,
        awayTeamID: TeamID,
        groundID: GroundID,
        participatingPlayerIDs: Set<PlayerID>,
        startsAt: Date,
        endsAt: Date,
        reminder: FixtureReminder,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.leagueID = leagueID
        self.name = name
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.groundID = groundID
        self.participatingPlayerIDs = participatingPlayerIDs
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.reminder = reminder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static func validated(
        id: FixtureID,
        leagueID: LeagueID?,
        name: String,
        homeTeamID: TeamID,
        awayTeamID: TeamID,
        groundID: GroundID,
        participatingPlayerIDs: Set<PlayerID>,
        startsAt: Date,
        endsAt: Date,
        reminder: FixtureReminder,
        createdAt: Date,
        updatedAt: Date
    ) throws -> FixtureRecord {
        guard startsAt < endsAt else { throw FixtureValidationError.invalidTimeSlot }
        guard homeTeamID != awayTeamID else { throw FixtureValidationError.sameTeam }
        return FixtureRecord(
            id: id,
            leagueID: leagueID,
            name: name,
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
            groundID: groundID,
            participatingPlayerIDs: participatingPlayerIDs,
            startsAt: startsAt,
            endsAt: endsAt,
            reminder: reminder,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum FixtureConflictReason: Hashable, Sendable, Codable {
    case ground(GroundID)
    case team(TeamID)
    case player(PlayerID)
}

public struct FixtureConflict: Sendable, Codable, Equatable {
    public let clashingFixtureID: FixtureID
    public let clashingFixtureName: String
    public let reasons: [FixtureConflictReason]

    public init(clashingFixtureID: FixtureID, clashingFixtureName: String, reasons: [FixtureConflictReason]) {
        self.clashingFixtureID = clashingFixtureID
        self.clashingFixtureName = clashingFixtureName
        self.reasons = reasons
    }

    public var explanation: String {
        let groundCount = reasons.filter { if case .ground = $0 { return true }; return false }.count
        let teamCount = reasons.filter { if case .team = $0 { return true }; return false }.count
        let playerCount = reasons.count - groundCount - teamCount
        var details: [String] = []
        if groundCount > 0 { details.append("same ground") }
        if teamCount > 0 { details.append(teamCount == 1 ? "1 double-booked team" : "\(teamCount) double-booked teams") }
        if playerCount > 0 {
            details.append(playerCount == 1 ? "1 double-booked player" : "\(playerCount) double-booked players")
        }
        return "Clashes with \(clashingFixtureName): \(details.joined(separator: " and "))."
    }
}

public enum FixtureConflictDetector {
    public static func conflicts(for candidate: FixtureRecord, among fixtures: [FixtureRecord]) -> [FixtureConflict] {
        fixtures
            .filter { existing in
                existing.id != candidate.id
                    && candidate.startsAt < existing.endsAt
                    && existing.startsAt < candidate.endsAt
            }
            .compactMap { existing in
                var reasons: [FixtureConflictReason] = []
                if existing.groundID == candidate.groundID {
                    reasons.append(.ground(candidate.groundID))
                }
                let sharedTeams = Set([candidate.homeTeamID, candidate.awayTeamID])
                    .intersection([existing.homeTeamID, existing.awayTeamID])
                reasons.append(contentsOf: sharedTeams.sorted { $0.rawValue < $1.rawValue }.map(FixtureConflictReason.team))
                reasons.append(contentsOf: candidate.participatingPlayerIDs
                    .intersection(existing.participatingPlayerIDs)
                    .sorted { $0.rawValue < $1.rawValue }
                    .map(FixtureConflictReason.player))
                guard !reasons.isEmpty else { return nil }
                return FixtureConflict(
                    clashingFixtureID: existing.id,
                    clashingFixtureName: existing.name,
                    reasons: reasons
                )
            }
            .sorted {
                if $0.clashingFixtureName == $1.clashingFixtureName {
                    return $0.clashingFixtureID.rawValue < $1.clashingFixtureID.rawValue
                }
                return $0.clashingFixtureName.localizedCaseInsensitiveCompare($1.clashingFixtureName) == .orderedAscending
            }
    }
}
