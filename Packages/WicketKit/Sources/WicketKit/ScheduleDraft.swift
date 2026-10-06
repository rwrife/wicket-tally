import Foundation

public enum ScheduleFormat: String, CaseIterable, Sendable {
    case roundRobin = "Round robin"
    case knockout = "Single elimination"
}

public enum ScheduleError: Error, Equatable, Sendable {
    case notEnoughTeams
    case duplicateTeam
}

/// A nil side is a bye (round robin) or a winner not known yet (knockout).
/// Only pairings with two known sides are eligible for fixture creation.
public struct SchedulePairing: Equatable, Sendable {
    public let home: TeamID?
    public let away: TeamID?
    public var isPlayable: Bool { home != nil && away != nil }

    public init(home: TeamID?, away: TeamID?) {
        self.home = home
        self.away = away
    }
}

public struct ScheduleRound: Equatable, Sendable {
    public let number: Int
    public let pairings: [SchedulePairing]
}

public struct SchedulePlan: Equatable, Sendable {
    public let format: ScheduleFormat
    public let rounds: [ScheduleRound]
    public var knownMatchCount: Int { rounds.flatMap(\.pairings).filter(\.isPlayable).count }
    public var projectedMatchCount: Int {
        format == .knockout
            ? rounds.reduce(0) { $0 + $1.pairings.count } - (rounds.first?.pairings.filter { $0.home == nil || $0.away == nil }.count ?? 0)
            : knownMatchCount
    }
}

public enum ScheduleGenerator {
    /// Sort stable IDs before seeding so ordering never depends on picker order.
    public static func generate(teams: [TeamID], format: ScheduleFormat) throws -> SchedulePlan {
        let ordered = teams.sorted { $0.rawValue < $1.rawValue }
        guard ordered.count >= 2 else { throw ScheduleError.notEnoughTeams }
        guard Set(ordered).count == ordered.count else { throw ScheduleError.duplicateTeam }
        switch format {
        case .roundRobin:
            var ring: [TeamID?] = ordered.map(Optional.some)
            if ring.count % 2 != 0 { ring.append(nil) }
            var rounds: [ScheduleRound] = []
            for number in 1..<ring.count {
                let pairs = (0..<(ring.count / 2)).map { index in
                    SchedulePairing(home: ring[index], away: ring[ring.count - 1 - index])
                }
                rounds.append(ScheduleRound(number: number, pairings: pairs))
                // Circle rotation: keep the first seed fixed.
                let last = ring.removeLast()
                ring.insert(last, at: 1)
            }
            return SchedulePlan(format: format, rounds: rounds)
        case .knockout:
            let size = 1 << (Int.bitWidth - (ordered.count - 1).leadingZeroBitCount)
            // Top seeds receive the byes, while the remaining teams play an
            // opening round. No fixture is invented for an unknown winner.
            let byes = size - ordered.count
            var first: [SchedulePairing] = ordered.prefix(byes).map {
                SchedulePairing(home: $0, away: nil)
            }
            let remaining = Array(ordered.dropFirst(byes))
            for index in stride(from: 0, to: remaining.count, by: 2) {
                first.append(SchedulePairing(home: remaining[index], away: remaining[index + 1]))
            }
            var rounds = [ScheduleRound(number: 1, pairings: first)]
            var prior = first
            while prior.count > 1 {
                let next = stride(from: 0, to: prior.count, by: 2).map { index in
                    func advance(_ pair: SchedulePairing) -> TeamID? {
                        if rounds.count != 1 { return nil }
                        if pair.home == nil { return pair.away }
                        if pair.away == nil { return pair.home }
                        return nil // contested: winner is unknown
                    }
                    return SchedulePairing(home: advance(prior[index]), away: advance(prior[index + 1]))
                }
                rounds.append(ScheduleRound(number: rounds.count + 1, pairings: next))
                prior = next
            }
            return SchedulePlan(format: format, rounds: rounds)
        }
    }
}
