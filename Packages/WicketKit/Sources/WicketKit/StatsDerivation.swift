import Foundation

/// Adapter for the app's fixture-to-ledger association. Supply an empty ledger
/// when unavailable, never drop that fixture from the league projection.
public struct StatsFixture: Equatable, Sendable {
    public let id: FixtureID
    public let homeTeamID: TeamID
    public let awayTeamID: TeamID
    public let rules: MatchRules
    public let ledger: MatchLedger
    public let playerIDs: Set<PlayerID>
    public let startsAt: Date?

    public init(
        id: FixtureID, homeTeamID: TeamID, awayTeamID: TeamID,
        rules: MatchRules, ledger: MatchLedger, playerIDs: Set<PlayerID> = [], startsAt: Date? = nil
    ) {
        self.id = id
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.rules = rules
        self.ledger = ledger
        self.playerIDs = playerIDs
        self.startsAt = startsAt
    }
}

public struct PlayerStats: Equatable, Sendable {
    public let playerID: PlayerID
    public let battingInnings: NumericValue
    public let runs: NumericValue
    public let highestScore: NumericValue
    public let dismissals: NumericValue
    public let ballsFaced: NumericValue
    public let average: NumericValue
    public let strikeRate: NumericValue
    public let bowlingOvers: TextValue
    public let bowlingLegalDeliveries: NumericValue
    public let maidens: NumericValue
    public let runsConceded: NumericValue
    public let wickets: NumericValue
    public let economy: NumericValue
    public let battingUnavailableReason: String?
    public let bowlingUnavailableReason: String?
}

public struct LeagueStats: Equatable, Sendable {
    public let standings: [StandingsRow]
    public let players: [PlayerStats]
    public let scorecards: [FixtureID: MatchScorecard]
}

public enum StatsDerivation {
    /// Pure, correction-aware recomputation. Filter the inputs to one league.
    /// Player totals are conservatively unknown if any constituent match is
    /// unresolved or has attribution gaps: the ledger has no authoritative XI.
    /// Recorded partial figures remain available in each scorecard.
    public static func derive(
        fixtures: [StatsFixture],
        teamIDs: [TeamID] = [],
        playerIDs: [PlayerID] = [],
        pointsPolicy: StandingsPointsPolicy = .init(),
        manualPoints: [StandingsPointsOverride] = []
    ) throws -> LeagueStats {
        let cards = try scorecards(fixtures: fixtures)
        return LeagueStats(
            standings: try StandingsDerivation.rows(
                fixtures: fixtures, cards: cards, teamIDs: teamIDs, policy: pointsPolicy, overrides: manualPoints
            ),
            players: playerStats(
                cards: cards, roster: Set(playerIDs).union(fixtures.flatMap { $0.playerIDs })
            ),
            scorecards: cards
        )
    }

    static func scorecards(fixtures: [StatsFixture]) throws -> [FixtureID: MatchScorecard] {
        var cards: [FixtureID: MatchScorecard] = [:]
        for fixture in fixtures.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard cards[fixture.id] == nil else { throw StatsDerivationError.duplicateFixture(fixture.id) }
            guard fixture.homeTeamID != fixture.awayTeamID else { throw StatsDerivationError.invalidTeams(fixture.id) }
            let card = try ScorecardDerivation.derive(ledger: fixture.ledger, rules: fixture.rules)
            let teams: Set<TeamID> = [fixture.homeTeamID, fixture.awayTeamID]
            guard card.innings.allSatisfy({
                teams.contains($0.state.battingTeam) && teams.contains($0.state.bowlingTeam)
            }) else { throw StatsDerivationError.invalidTeams(fixture.id) }
            cards[fixture.id] = card
        }
        return cards
    }

    private static func playerStats(cards: [FixtureID: MatchScorecard], roster: Set<PlayerID>) -> [PlayerStats] {
        let ordered = cards.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { cards[$0] }
        let innings = ordered.flatMap(\.innings)
        let players = roster.union(innings.flatMap { innings in
            innings.batting.compactMap(\.playerID) + innings.bowling.compactMap(\.playerID)
        })
        let incomplete = ordered.contains { $0.result == nil }
        let adjusted = innings.contains { !$0.adjustments.isEmpty }
        let battingGap = innings.contains(where: \.hasUnknownBatting)
        let bowlingGap = innings.contains(where: \.hasUnknownBowling)
        return players.sorted { $0.rawValue < $1.rawValue }.map { player in
            let bat = innings.flatMap(\.batting).filter { $0.playerID == player }
            let bowl = innings.flatMap(\.bowling).filter { $0.playerID == player }
            let battingReason: String?
            let bowlingReason: String?
            if incomplete {
                battingReason = "Constituent fixtures are incomplete, abandoned, or unresolved."
                bowlingReason = battingReason
            } else if adjusted {
                battingReason = "Unattributed score adjustments prevent verified player totals."
                bowlingReason = battingReason
            } else {
                battingReason = battingGap ? "Some batting deliveries have no identified striker." : (bat.isEmpty ? "No recorded batting innings." : nil)
                bowlingReason = bowlingGap ? "Some deliveries have no identified bowler." : (bowl.isEmpty ? "No recorded bowling innings." : nil)
            }
            let runs = bat.reduce(0) { $0 + $1.runs }
            let balls = bat.reduce(0) { $0 + $1.balls }
            let outs = bat.filter { $0.dismissal != nil }.count
            let legal = bowl.reduce(0) { $0 + $1.legalDeliveries }
            let conceded = bowl.reduce(0) { $0 + $1.runs }
            let overs = bowl.reduce(0.0) { $0 + Double($1.legalDeliveries) / Double($1.ballsPerOver) }
            let overSizes = Set(bowl.map(\.ballsPerOver))
            func battingValue(_ n: Int) -> NumericValue { battingReason == nil ? .known(Double(n)) : .unknown }
            func bowlingValue(_ n: Int) -> NumericValue { bowlingReason == nil ? .known(Double(n)) : .unknown }
            return PlayerStats(
                playerID: player,
                battingInnings: battingValue(bat.count), runs: battingValue(runs),
                highestScore: battingValue(bat.map(\.runs).max() ?? 0),
                dismissals: battingValue(outs), ballsFaced: battingValue(balls),
                average: battingReason == nil && outs > 0 ? .known(Double(runs) / Double(outs)) : .unknown,
                strikeRate: battingReason == nil && balls > 0 ? .known(Double(runs) * 100 / Double(balls)) : .unknown,
                bowlingOvers: bowlingReason == nil && overSizes.count == 1
                    ? .known(legal.cricketOversString(ballsPerOver: bowl[0].ballsPerOver)) : .unknown,
                bowlingLegalDeliveries: bowlingValue(legal),
                maidens: bowlingValue(bowl.reduce(0) { $0 + $1.maidens }),
                runsConceded: bowlingValue(conceded), wickets: bowlingValue(bowl.reduce(0) { $0 + $1.wickets }),
                economy: bowlingReason == nil && overs > 0 ? .known(Double(conceded) / overs) : .unknown,
                battingUnavailableReason: battingReason,
                bowlingUnavailableReason: bowlingReason ?? (overSizes.count > 1 ? "Overs notation unavailable across different balls-per-over rules." : nil)
            )
        }
    }
}
