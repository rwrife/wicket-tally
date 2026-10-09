import Foundation

/// Per-match figures are derived from effective ledger events, never saved totals.
public struct SeasonMatchInsight: Equatable, Sendable {
    public let fixtureID: FixtureID
    public let isComplete: Bool
    public let runs: NumericValue
    public let wickets: NumericValue
    public let cumulativeRuns: NumericValue
    public let cumulativeWickets: NumericValue
}

public struct PlayerSeasonInsight: Equatable, Sendable {
    public let playerID: PlayerID
    public let matches: [SeasonMatchInsight]
    public let bestRuns: NumericValue
    public let bestWickets: NumericValue
    public let bestRunsFixtures: [FixtureID]
    public let bestWicketsFixtures: [FixtureID]

    public func plainText(name: String, fixtureNames: [FixtureID: String] = [:]) -> String {
        var lines = ["\(name) — season insights"]
        if matches.isEmpty { lines.append("No recorded matches. Totals and personal bests unknown.") }
        for match in matches {
            let title = fixtureNames[match.fixtureID] ?? match.fixtureID.rawValue
            lines.append("\(title): runs \(UnknownSafeFormatter.ballsString(match.runs)), wickets \(UnknownSafeFormatter.ballsString(match.wickets)); cumulative runs \(UnknownSafeFormatter.ballsString(match.cumulativeRuns)), wickets \(UnknownSafeFormatter.ballsString(match.cumulativeWickets))\(match.isComplete ? "" : " (incomplete)")")
        }
        lines.append("Best runs: \(UnknownSafeFormatter.ballsString(bestRuns))\(bestRunsFixtures.isEmpty ? "" : " (" + bestRunsFixtures.map { fixtureNames[$0] ?? $0.rawValue }.joined(separator: ", ") + ")")")
        lines.append("Best wickets: \(UnknownSafeFormatter.ballsString(bestWickets))\(bestWicketsFixtures.isEmpty ? "" : " (" + bestWicketsFixtures.map { fixtureNames[$0] ?? $0.rawValue }.joined(separator: ", ") + ")")")
        return lines.joined(separator: "\n")
    }
}

public enum SeasonInsights {
    /// Pass fixtures from one league. An incomplete or unattributed game poisons
    /// cumulative totals and bests rather than silently counting a zero.
    public static func derive(fixtures: [StatsFixture], playerIDs: [PlayerID]) throws -> [PlayerSeasonInsight] {
        let cards = try StatsDerivation.scorecards(fixtures: fixtures)
        let roster = Set(playerIDs).union(fixtures.flatMap(\.playerIDs)).union(cards.values.flatMap { card in
            card.innings.flatMap { $0.batting.compactMap(\.playerID) + $0.bowling.compactMap(\.playerID) }
        })
        let ordered = fixtures.sorted {
            if $0.startsAt != $1.startsAt {
                return ($0.startsAt ?? .distantPast) < ($1.startsAt ?? .distantPast)
            }
            return $0.id.rawValue < $1.id.rawValue
        }
        return roster.sorted { $0.rawValue < $1.rawValue }.map { player in
            var totalRuns = 0
            var totalWickets = 0
            var runsValid = true
            var wicketsValid = true
            var hasRuns = false
            var hasWickets = false
            var unknownRuns = false
            var unknownWickets = false
            var matchRows: [SeasonMatchInsight] = []
            var bestRuns = -1
            var bestWickets = -1
            var bestRunsFixtures: [FixtureID] = []
            var bestWicketsFixtures: [FixtureID] = []
            for fixture in ordered {
                let id = fixture.id
                guard let card = cards[id] else { continue }
                let batting = card.innings.flatMap(\.batting).filter { $0.playerID == player }
                let bowling = card.innings.flatMap(\.bowling).filter { $0.playerID == player }
                let participant = fixture.playerIDs.contains(player) || !batting.isEmpty || !bowling.isEmpty
                guard participant else { continue }
                let runs = batting.reduce(0) { $0 + $1.runs }
                let wickets = bowling.reduce(0) { $0 + $1.wickets }
                let complete = card.result != nil
                let adjusted = card.innings.contains { !$0.adjustments.isEmpty }
                let runsKnown = complete && !adjusted && !batting.isEmpty && !card.innings.contains { $0.hasUnknownBatting }
                let wicketsKnown = complete && !adjusted && !bowling.isEmpty && !card.innings.contains { $0.hasUnknownBowling }
                if !runsKnown { runsValid = false; unknownRuns = true }
                if !wicketsKnown { wicketsValid = false; unknownWickets = true }
                if runsKnown {
                    hasRuns = true
                    totalRuns += runs
                    if runs > bestRuns { bestRuns = runs; bestRunsFixtures = [id] }
                    else if runs == bestRuns { bestRunsFixtures.append(id) }
                }
                if wicketsKnown {
                    hasWickets = true
                    totalWickets += wickets
                    if wickets > bestWickets { bestWickets = wickets; bestWicketsFixtures = [id] }
                    else if wickets == bestWickets { bestWicketsFixtures.append(id) }
                }
                matchRows.append(SeasonMatchInsight(
                    fixtureID: id, isComplete: complete,
                    runs: runsKnown ? .known(Double(runs)) : .unknown,
                    wickets: wicketsKnown ? .known(Double(wickets)) : .unknown,
                    cumulativeRuns: runsValid && hasRuns ? .known(Double(totalRuns)) : .unknown,
                    cumulativeWickets: wicketsValid && hasWickets ? .known(Double(totalWickets)) : .unknown
                ))
            }
            // A gap can hide an earlier or later personal best; no definitive
            // leader can be asserted for the full season.
            return PlayerSeasonInsight(
                playerID: player, matches: matchRows,
                bestRuns: !unknownRuns && bestRuns >= 0 ? .known(Double(bestRuns)) : .unknown,
                bestWickets: !unknownWickets && bestWickets >= 0 ? .known(Double(bestWickets)) : .unknown,
                bestRunsFixtures: unknownRuns ? [] : bestRunsFixtures,
                bestWicketsFixtures: unknownWickets ? [] : bestWicketsFixtures
            )
        }
    }
}
