import Foundation

struct MatchReplayEngine {
    private let rules: MatchRules

    init(rules: MatchRules) {
        self.rules = rules
    }

    func replay(events: [MatchEvent]) -> MatchState {
        let sorted = events.sorted { $0.sequence < $1.sequence }

        var invalidated = Set<EventID>()
        var replacement = [EventID: MatchEventKind]()
        var adjustmentEvents: [ScoreAdjustment] = []

        for event in sorted {
            guard case let .correction(correction) = event.kind else { continue }
            switch correction.action {
            case let .invalidate(target):
                invalidated.insert(target)
            case let .replace(target, with: newKind):
                replacement[target] = newKind
            case let .scoreAdjustment(adjustment):
                adjustmentEvents.append(adjustment)
            }
        }

        var completedInnings: [InningsAccumulator] = []
        var current: InningsAccumulator?
        var abandonedReason: String?

        for event in sorted {
            if invalidated.contains(event.id) {
                continue
            }

            let effectiveKind: MatchEventKind
            if replacement[event.id] != nil, case .correction = event.kind {
                // Do not replace correction events with non-corrections.
                effectiveKind = event.kind
            } else if let rep = replacement[event.id] {
                effectiveKind = rep
            } else {
                effectiveKind = event.kind
            }

            switch effectiveKind {
            case .toss:
                continue

            case let .inningsStarted(number, batting, bowling):
                if let current {
                    completedInnings.append(current)
                }
                current = InningsAccumulator(number: number, batting: batting, bowling: bowling)

            case let .ball(ball):
                guard var innings = current else { continue }

                innings.runs += ball.totalRuns
                innings.runsInCurrentOver += ball.totalRuns
                if ball.isLegalDelivery {
                    innings.legalDeliveries += 1
                    innings.ballsInCurrentOver += 1
                }

                if ball.countsAsWicket(rules: rules) {
                    innings.wickets += 1
                }

                let runCutReached = rules.maxRunsPerOver.map { innings.runsInCurrentOver >= $0 } ?? false
                if innings.ballsInCurrentOver >= rules.ballsPerOver || runCutReached {
                    innings.completedOvers += 1
                    innings.ballsInCurrentOver = 0
                    innings.runsInCurrentOver = 0
                }
                if innings.completedOvers >= rules.oversPerInnings {
                    innings.ended = true
                }
                if innings.wickets >= rules.maxWickets {
                    innings.ended = true
                }
                if let cap = rules.inningsRunCap, innings.runs >= cap {
                    innings.ended = true
                }

                var isComplete = innings.ended

                // Chase completed: the moment the chasing side passes the
                // target the innings ends immediately, even mid-over and even
                // when the winning runs arrive on a wide/no-ball boundary.
                if innings.number >= 2, let chased = completedInnings.first {
                    if innings.runs >= chased.runs + 1 {
                        isComplete = true
                    }
                }

                innings.ended = isComplete
                current = innings
                if isComplete {
                    completedInnings.append(innings)
                    current = nil
                }

            case .overCompleted:
                continue

            case let .penaltyRuns(penalty):
                guard var innings = current else { continue }
                if penalty.awardedToBatting {
                    innings.runs += penalty.runs
                }
                // Standalone penalties count toward the innings cap, but are
                // not delivery runs and therefore do not consume an over.
                if let cap = rules.inningsRunCap, innings.runs >= cap {
                    innings.ended = true
                }
                if innings.number >= 2, let chased = completedInnings.first,
                   innings.runs >= chased.runs + 1 {
                    innings.ended = true
                }
                if innings.ended {
                    completedInnings.append(innings)
                    current = nil
                } else {
                    current = innings
                }

            case .inningsEnded:
                if let innings = current {
                    var ended = innings
                    ended.ended = true
                    completedInnings.append(ended)
                    current = nil
                }

            case let .matchAbandoned(reason):
                abandonedReason = reason

            case .correction:
                continue
            }
        }

        if let current {
            completedInnings.append(current)
        }

        // Apply direct score adjustments append-only at end of replay pass.
        if !adjustmentEvents.isEmpty, var last = completedInnings.popLast() {
            for adj in adjustmentEvents {
                last.runs = max(0, last.runs + adj.runsDelta)
                last.wickets = max(0, last.wickets + adj.wicketsDelta)
            }
            if let cap = rules.inningsRunCap, last.runs >= cap {
                last.ended = true
            }
            completedInnings.append(last)
        }

        let innings = completedInnings.map { acc in
            InningsState(
                number: acc.number,
                battingTeam: acc.batting,
                bowlingTeam: acc.bowling,
                runs: acc.runs,
                wickets: min(acc.wickets, rules.maxWickets),
                legalDeliveries: min(acc.legalDeliveries, rules.maxLegalDeliveriesPerInnings),
                isComplete: acc.ended,
                completedOvers: acc.completedOvers,
                ballsInCurrentOver: acc.ballsInCurrentOver,
                runsInCurrentOver: acc.runsInCurrentOver
            )
        }.sorted { $0.number < $1.number }

        let scorecard = innings.map {
            ScorecardLine(
                innings: $0.number,
                team: $0.battingTeam,
                score: $0.scoreline,
                overs: $0.oversString(ballsPerOver: rules.ballsPerOver)
            )
        }

        let status = deriveStatus(innings: innings, abandonedReason: abandonedReason)
        let currentRunRate = deriveCurrentRunRate(innings: innings)
        let requiredRunRate = deriveRequiredRunRate(innings: innings, status: status)
        let ballsRemaining = deriveBallsRemaining(innings: innings, status: status)
        let oversRemaining = deriveOversRemaining(from: ballsRemaining)

        return MatchState(
            rules: rules,
            innings: innings,
            status: status,
            currentRunRate: currentRunRate,
            requiredRunRate: requiredRunRate,
            oversRemaining: oversRemaining,
            ballsRemaining: ballsRemaining,
            scorecard: scorecard
        )
    }

    private func deriveStatus(innings: [InningsState], abandonedReason: String?) -> MatchStatus {
        if let abandonedReason {
            return .completed(.noResult(reason: abandonedReason))
        }

        guard let first = innings.first else {
            return .notStarted
        }

        if innings.count == 1 {
            return first.isComplete ? .inningsBreak(target: first.runs + 1) : .inProgress
        }

        let second = innings[1]
        let target = first.runs + 1

        if second.runs >= target {
            let wicketsInHand = max(0, rules.maxWickets - second.wickets)
            return .completed(.wonByWickets(team: second.battingTeam, wickets: wicketsInHand))
        }

        if second.isComplete {
            if second.runs == first.runs {
                return .completed(.tie)
            }
            if second.runs < first.runs {
                let margin = first.runs - second.runs
                return .completed(.wonByRuns(team: first.battingTeam, runs: margin))
            }
        }

        return .inProgress
    }

    private func deriveCurrentRunRate(innings: [InningsState]) -> NumericValue {
        guard let active = innings.last else {
            return .unknown
        }
        let usedBalls = active.consumedBallBudget(ballsPerOver: rules.ballsPerOver)
        guard usedBalls > 0 else {
            return .unknown
        }
        let overs = Double(usedBalls) / Double(rules.ballsPerOver)
        guard overs > 0 else { return .unknown }
        return .known(Double(active.runs) / overs)
    }

    private func deriveRequiredRunRate(innings: [InningsState], status: MatchStatus) -> NumericValue {
        guard innings.count >= 2 else { return .unknown }
        guard case .inProgress = status else { return .unknown }

        let first = innings[0]
        let second = innings[1]
        let target = first.runs + 1
        let runsNeeded = target - second.runs
        guard runsNeeded > 0 else { return .known(0) }

        let remainingBalls = rules.maxLegalDeliveriesPerInnings - second.consumedBallBudget(ballsPerOver: rules.ballsPerOver)
        guard remainingBalls > 0 else { return .unknown }

        let remainingOvers = Double(remainingBalls) / Double(rules.ballsPerOver)
        guard remainingOvers > 0 else { return .unknown }
        return .known(Double(runsNeeded) / remainingOvers)
    }

    private func deriveBallsRemaining(innings: [InningsState], status: MatchStatus) -> NumericValue {
        guard innings.count >= 2 else { return .unknown }
        guard case .inProgress = status else { return .unknown }

        let second = innings[1]
        let remaining = rules.maxLegalDeliveriesPerInnings - second.consumedBallBudget(ballsPerOver: rules.ballsPerOver)
        return remaining >= 0 ? .known(Double(remaining)) : .unknown
    }

    private func deriveOversRemaining(from ballsRemaining: NumericValue) -> NumericValue {
        switch ballsRemaining {
        case let .known(balls):
            guard rules.ballsPerOver > 0 else { return .unknown }
            return .known(balls / Double(rules.ballsPerOver))
        case .unknown:
            return .unknown
        }
    }
}

private struct InningsAccumulator {
    let number: Int
    let batting: TeamID
    let bowling: TeamID
    var runs: Int = 0
    var wickets: Int = 0
    var legalDeliveries: Int = 0
    var completedOvers: Int = 0
    var ballsInCurrentOver: Int = 0
    var runsInCurrentOver: Int = 0
    var ended: Bool = false
}
