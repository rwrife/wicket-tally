import Foundation

public enum ScorecardDerivation {
    /// Replays effective events and uses MatchLedger for canonical team totals.
    /// Supports two-innings limited-overs cricket; ambiguous streams are labelled
    /// unresolved rather than manufacturing results. No state is persisted here.
    public static func derive(ledger: MatchLedger, rules: MatchRules) throws -> MatchScorecard {
        let events = try StatsEffectiveEvents.resolve(ledger)
        let replay = MatchLedger(events: events).replay(rules: rules)
        var builders: [ScorecardInningsBuilder] = []
        var active: Int?
        var warnings: [String] = []
        var adjustments: [CorrectionEvent] = []
        var abandonment: String?
        func warn(_ reason: String) {
            if !warnings.contains(reason) { warnings.append(reason) }
        }
        for event in events {
            switch event.kind {
            case let .inningsStarted(number, batting, bowling):
                if active != nil { warn("An innings was started before the previous innings ended.") }
                if number != builders.count + 1 || number > 2 || batting == bowling {
                    warn("Unsupported innings order or teams.")
                }
                if let first = builders.first,
                   (first.battingTeam != bowling || first.bowlingTeam != batting) {
                    warn("Innings teams do not alternate.")
                }
                builders.append(ScorecardInningsBuilder(number: number, battingTeam: batting, bowlingTeam: bowling, rules: rules))
                active = builders.count - 1
            case let .ball(ball):
                guard let index = active else {
                    // Correcting an earlier delivery can move the winning ball
                    // earlier. Replay deliberately ignores the remaining balls.
                    if builders.isEmpty { warn("Delivery before an innings was not attributed.") }
                    continue
                }
                builders[index].record(ball)
                if builders[index].wickets >= rules.maxWickets {
                    builders[index].endReason = .allOut
                    active = nil
                } else if builders[index].completedOvers >= rules.oversPerInnings {
                    builders[index].endReason = .oversComplete
                    active = nil
                }
                if let cap = rules.inningsRunCap, builders[index].runs >= cap { active = nil }
                if index == 1, builders[index].runs > builders[0].runs {
                    builders[index].endReason = .chaseCompleted
                    active = nil
                }
            case let .penaltyRuns(penalty):
                guard let index = active else {
                    if builders.isEmpty { warn("Penalty before an innings was not attributed.") }
                    continue
                }
                if penalty.awardedToBatting {
                    builders[index].extras.penalties += penalty.runs
                    builders[index].runs += penalty.runs
                } else {
                    warn("Penalty awarded to the fielding side cannot be allocated by the ledger.")
                }
                if let cap = rules.inningsRunCap, builders[index].runs >= cap { active = nil }
                if index == 1, builders[index].runs > builders[0].runs {
                    builders[index].endReason = .chaseCompleted
                    active = nil
                }
            case let .inningsEnded(reason):
                if reason == .abandoned { abandonment = "Innings abandoned" }
                if let index = active {
                    builders[index].endReason = reason
                    active = nil
                } else if let last = builders.indices.last {
                    // An explicit end commonly follows an automatic over/chase end.
                    if reason == .abandoned || reason == .declared {
                        builders[last].endReason = reason
                    }
                } else {
                    warn("Innings end without an innings.")
                }
            case let .matchAbandoned(reason):
                abandonment = reason
            case let .correction(correction):
                if case .scoreAdjustment = correction.action { adjustments.append(correction) }
            case .overCompleted, .toss:
                break
            }
        }
        if builders.isEmpty && !adjustments.isEmpty {
            warn("Score adjustment has no innings to adjust.")
        }
        for builder in builders {
            if builder.batting.contains(where: { $0.dismissal?.kind == .retired }) {
                warn("Retirement does not specify retired hurt versus retired out.")
            }
        }
        // Replay applies unscoped score adjustments to the final innings.
        // Keep their audit trail separate from player figures and extras.
        let innings = builders.enumerated().compactMap { index, builder -> ScorecardInnings? in
            guard let state = replay.innings.first(where: {
                $0.number == builder.number && $0.battingTeam == builder.battingTeam
            }) else { return nil }
            return builder.finish(state: state, adjustments: index == builders.count - 1 ? adjustments : [])
        }
        var result: MatchResult?
        var unavailable: String?
        if let abandonment {
            unavailable = "Abandoned: \(abandonment)"
        } else if !warnings.isEmpty {
            unavailable = warnings.joined(separator: " ")
        } else if innings.count != 2 || !innings.allSatisfy(\.state.isComplete) {
            unavailable = "Match is incomplete or not started."
        } else if case let .completed(value) = replay.status {
            if case let .noResult(reason) = value {
                unavailable = reason
            } else {
                result = value
            }
        } else {
            unavailable = "Match result is unresolved."
        }
        let nrrReason: String?
        if let unavailable {
            nrrReason = unavailable
        } else if rules.maxRunsPerOver != nil || rules.inningsRunCap != nil {
            nrrReason = "Run-cut overs or innings caps do not have a defined NRR policy."
        } else if !adjustments.isEmpty {
            nrrReason = "Unattributed score adjustments prevent verified NRR inputs."
        } else if innings.contains(where: { $0.state.legalDeliveries == 0 }) {
            nrrReason = "An innings has no legal deliveries."
        } else if innings.contains(where: { innings in
            switch innings.endReason {
            case .allOut: return innings.state.wickets != rules.maxWickets
            case .oversComplete: return innings.state.legalDeliveries != rules.maxLegalDeliveriesPerInnings
            case .chaseCompleted: return innings.state.number != 2 || innings.state.runs <= (replay.innings.first?.runs ?? 0)
            default: return true
            }
        }) {
            nrrReason = "An innings lacks a verified full-quota, all-out, or successful-chase ending."
        } else {
            nrrReason = nil
        }
        return MatchScorecard(
            rules: rules, innings: innings, status: replay.status, warnings: warnings,
            result: result, resultUnavailableReason: unavailable, nrrUnavailableReason: nrrReason
        )
    }
}

private struct ScorecardInningsBuilder {
    let number: Int
    let battingTeam: TeamID
    let bowlingTeam: TeamID
    let rules: MatchRules
    var runs = 0
    var wickets = 0
    var legalDeliveries = 0
    var completedOvers = 0
    var ballsInCurrentOver = 0
    var runsInCurrentOver = 0
    var endReason: InningsEndReason?
    var batting: [ScorecardBattingLine] = []
    var bowling: [ScorecardBowlingLine] = []
    var extras = ScorecardExtras()
    var falls: [ScorecardFallOfWicket] = []
    var overBowlers = Set<PlayerID>()
    var overHasUnknownBowler = false
    var overConceded = 0
    var unknownBatting = false
    var unknownBowling = false

    mutating func batter(_ id: PlayerID?) -> Int {
        if let index = batting.firstIndex(where: { $0.playerID == id }) { return index }
        batting.append(ScorecardBattingLine(playerID: id))
        return batting.count - 1
    }

    mutating func record(_ ball: BallEvent) {
        let striker = batter(ball.striker)
        if let nonStriker = ball.nonStriker { _ = batter(nonStriker) }
        if ball.striker == nil { unknownBatting = true }
        if ball.bowler == nil { unknownBowling = true }
        batting[striker].runs += ball.runsOffBat
        // No-balls count as balls faced; wides do not.
        if ball.extra?.kind != .wide { batting[striker].balls += 1 }
        if ball.runsOffBat == 4 { batting[striker].fours += 1 }
        if ball.runsOffBat == 6 { batting[striker].sixes += 1 }
        let bowler: Int
        if let index = bowling.firstIndex(where: { $0.playerID == ball.bowler }) {
            bowler = index
        } else {
            bowling.append(ScorecardBowlingLine(playerID: ball.bowler, ballsPerOver: rules.ballsPerOver))
            bowler = bowling.count - 1
        }
        var conceded = ball.runsOffBat
        if let extra = ball.extra {
            switch extra.kind {
            case .wide: extras.wides += extra.runs; conceded += extra.runs
            case .noBall: extras.noBalls += extra.runs; conceded += extra.runs
            case .bye: extras.byes += extra.runs
            case .legBye: extras.legByes += extra.runs
            }
        }
        runs += ball.totalRuns
        runsInCurrentOver += ball.totalRuns
        bowling[bowler].runs += conceded
        overConceded += conceded
        if let id = ball.bowler { overBowlers.insert(id) } else { overHasUnknownBowler = true }
        if ball.isLegalDelivery {
            legalDeliveries += 1
            ballsInCurrentOver += 1
            bowling[bowler].legalDeliveries += 1
        }
        let fullOver = ballsInCurrentOver == rules.ballsPerOver
        let cutOver = rules.maxRunsPerOver.map { runsInCurrentOver >= $0 } ?? false
        if fullOver || cutOver {
            if fullOver && overBowlers.count == 1 && !overHasUnknownBowler && overConceded == 0 {
                bowling[bowler].maidens += 1
            }
            completedOvers += 1
            ballsInCurrentOver = 0
            runsInCurrentOver = 0
            overBowlers.removeAll()
            overHasUnknownBowler = false
            overConceded = 0
        }
        if ball.countsAsWicket(rules: rules), let wicket = ball.wicket {
            wickets += 1
            let dismissed = batter(wicket.dismissed)
            batting[dismissed].dismissal = wicket
            switch wicket.kind {
            case .bowled, .caught, .lbw, .stumped, .hitWicket:
                bowling[bowler].wickets += 1
                batting[dismissed].dismissalBowler = ball.bowler
            case .runOut, .retired, .obstructingField, .timedOut, .hitBallTwice:
                break
            }
            falls.append(ScorecardFallOfWicket(
                wicket: wickets, runs: runs, legalDeliveries: legalDeliveries,
                dismissed: wicket.dismissed, kind: wicket.kind,
                overs: "\(completedOvers).\(ballsInCurrentOver)"
            ))
        }
    }

    func finish(state: InningsState, adjustments: [CorrectionEvent]) -> ScorecardInnings {
        ScorecardInnings(
            state: state, batting: batting, bowling: bowling, extras: extras,
            fallOfWickets: falls, adjustments: adjustments, endReason: endReason,
            hasUnknownBatting: unknownBatting, hasUnknownBowling: unknownBowling
        )
    }
}
