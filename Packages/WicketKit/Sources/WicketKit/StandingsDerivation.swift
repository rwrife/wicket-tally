import Foundation

public struct StandingsPointsPolicy: Equatable, Sendable {
    public let win: Int
    public let tie: Int
    public let loss: Int

    public init(win: Int = 2, tie: Int = 1, loss: Int = 0) {
        self.win = win
        self.tie = tie
        self.loss = loss
    }
}

/// An override replaces a team's entire league points total, not its match result.
/// Persist this audit record separately; the projection never writes to the ledger.
public struct StandingsPointsOverride: Equatable, Sendable, Codable {
    public let teamID: TeamID
    public let points: Int
    public let reason: String
    public let provenance: String
    public let recordedAt: Date

    public init(teamID: TeamID, points: Int, reason: String, provenance: String, recordedAt: Date) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !provenance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              recordedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw StatsDerivationError.invalidPointsOverride
        }
        self.teamID = teamID
        self.points = points
        self.reason = reason
        self.provenance = provenance
        self.recordedAt = recordedAt
    }
}

public struct StandingsRow: Equatable, Sendable {
    public let teamID: TeamID
    public let played: NumericValue
    public let won: NumericValue
    public let lost: NumericValue
    public let tied: NumericValue
    public let derivedPoints: NumericValue
    public let pointsOverride: StandingsPointsOverride?
    public let unresolvedFixtures: [FixtureID]
    public let netRunRate: NumericValue
    public let nrrUnavailableReason: String?
    public var points: NumericValue {
        pointsOverride.map { .known(Double($0.points)) } ?? derivedPoints
    }
    public var pointsLabel: String {
        pointsOverride == nil ? "Derived points" : "Manual points override"
    }
}

public enum StandingsDerivation {
    /// Include all constituent fixtures, including missing/empty ledgers. Omitting
    /// one falsely makes a partial season look complete. Unknown rows sort last;
    /// equal points use stable team IDs, not an unofficial NRR tie-break.
    public static func derive(
        fixtures: [StatsFixture],
        teamIDs: [TeamID] = [],
        pointsPolicy: StandingsPointsPolicy = .init(),
        manualPoints: [StandingsPointsOverride] = []
    ) throws -> [StandingsRow] {
        let cards = try StatsDerivation.scorecards(fixtures: fixtures)
        return try rows(fixtures: fixtures, cards: cards, teamIDs: teamIDs, policy: pointsPolicy, overrides: manualPoints)
    }

    static func rows(
        fixtures: [StatsFixture], cards: [FixtureID: MatchScorecard], teamIDs: [TeamID],
        policy: StandingsPointsPolicy, overrides: [StandingsPointsOverride]
    ) throws -> [StandingsRow] {
        let teams = Set(teamIDs + fixtures.flatMap { [$0.homeTeamID, $0.awayTeamID] })
        var manual: [TeamID: StandingsPointsOverride] = [:]
        for override in overrides {
            // Revalidate decoded values as well as values made by the initializer.
            _ = try StandingsPointsOverride(
                teamID: override.teamID, points: override.points, reason: override.reason,
                provenance: override.provenance, recordedAt: override.recordedAt
            )
            guard teams.contains(override.teamID) else { throw StatsDerivationError.unknownOverrideTeam(override.teamID) }
            guard manual[override.teamID] == nil else { throw StatsDerivationError.duplicatePointsOverride(override.teamID) }
            manual[override.teamID] = override
        }
        return teams.map { team in
            let games = fixtures.filter { $0.homeTeamID == team || $0.awayTeamID == team }
                .sorted { $0.id.rawValue < $1.id.rawValue }
            var wins = 0
            var losses = 0
            var ties = 0
            var unresolved: [FixtureID] = []
            var nrrReasons: [String] = []
            var runsFor = 0
            var runsAgainst = 0
            var oversFor = 0.0
            var oversAgainst = 0.0
            for game in games {
                guard let card = cards[game.id] else { continue }
                switch card.result {
                case let .wonByRuns(winner, _), let .wonByWickets(winner, _):
                    if winner == team { wins += 1 } else { losses += 1 }
                case .tie: ties += 1
                case .noResult, nil: unresolved.append(game.id)
                }
                if let reason = card.nrrUnavailableReason {
                    nrrReasons.append("\(game.id.rawValue): \(reason)")
                    continue
                }
                for innings in card.innings {
                    let state = innings.state
                    let balls = state.wickets == game.rules.maxWickets
                        ? game.rules.maxLegalDeliveriesPerInnings : state.legalDeliveries
                    let overs = Double(balls) / Double(game.rules.ballsPerOver)
                    if state.battingTeam == team {
                        runsFor += state.runs
                        oversFor += overs
                    } else {
                        runsAgainst += state.runs
                        oversAgainst += overs
                    }
                }
            }
            if games.isEmpty { nrrReasons.append("No constituent fixtures.") }
            if nrrReasons.isEmpty && (oversFor <= 0 || oversAgainst <= 0) {
                nrrReasons.append("Insufficient legal deliveries.")
            }
            func count(_ value: Int) -> NumericValue {
                unresolved.isEmpty ? .known(Double(value)) : .unknown
            }
            return StandingsRow(
                teamID: team, played: count(games.count), won: count(wins), lost: count(losses), tied: count(ties),
                derivedPoints: unresolved.isEmpty
                    ? .known(Double(wins) * Double(policy.win) + Double(losses) * Double(policy.loss) + Double(ties) * Double(policy.tie))
                    : .unknown,
                pointsOverride: manual[team], unresolvedFixtures: unresolved,
                netRunRate: nrrReasons.isEmpty ? .known(Double(runsFor) / oversFor - Double(runsAgainst) / oversAgainst) : .unknown,
                nrrUnavailableReason: nrrReasons.isEmpty ? nil : nrrReasons.joined(separator: " ")
            )
        }.sorted { left, right in
            switch (left.points, right.points) {
            case let (.known(a), .known(b)) where a != b: return a > b
            case (.known, .unknown): return true
            case (.unknown, .known): return false
            default: return left.teamID.rawValue < right.teamID.rawValue
            }
        }
    }
}
