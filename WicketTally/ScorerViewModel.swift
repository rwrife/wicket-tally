import Foundation
import Observation
import UIKit
import WicketKit
import WicketStore

@MainActor
@Observable
final class ScorerViewModel {
    let fixture: FixtureRecord

    private let store: WicketStore?
    private(set) var session: PersistedScoringSession
    private(set) var homePlayers: [PlayerRecord] = []
    private(set) var awayPlayers: [PlayerRecord] = []
    var errorMessage: String?

    private static let undoReason = "scorer undo"
    private static let redoReason = "scorer redo"
    private static let correctionProvenance = "wicket-tally-scorer"
    private static let neutralReason = "wicket-tally undo no-op"

    init(fixture: FixtureRecord, store: WicketStore?) {
        self.fixture = fixture
        self.store = store
        session = PersistedScoringSession(rules: .t20, ledger: MatchLedger(events: []))
        reload()
    }

    var state: MatchState {
        session.ledger.replay(rules: session.rules)
    }

    var toss: (winner: TeamID, decision: TossDecision)? {
        for event in effectiveActionEvents.reversed() {
            if case let .toss(winner, decision) = event.kind {
                return (winner, decision)
            }
        }
        return nil
    }

    var activeInnings: InningsState? {
        guard case .inProgress = state.status else { return nil }
        return state.innings.last
    }

    var isInningsBreak: Bool {
        if case .inningsBreak = state.status { return true }
        return false
    }

    var battingPlayers: [PlayerRecord] {
        activeInnings?.battingTeam == fixture.awayTeamID ? awayPlayers : homePlayers
    }

    var bowlingPlayers: [PlayerRecord] {
        activeInnings?.bowlingTeam == fixture.homeTeamID ? homePlayers : awayPlayers
    }

    /// True when the replay engine has closed an over that the ledger has not
    /// yet acknowledged with an `.overCompleted` marker. Derived by comparing
    /// replay's `completedOvers` against the markers already recorded, rather
    /// than re-deriving boundaries from legal-ball counts: the engine also cuts
    /// overs on a run limit, which can land on a wide or no-ball, and this
    /// comparison stays correct after undo/redo corrections.
    var needsOverCompletion: Bool {
        guard let innings = activeInnings else { return false }
        let acknowledged = currentInningsEvents.reduce(into: 0) { total, event in
            if case .overCompleted = event.kind { total += 1 }
        }
        return (innings.completedOvers ?? 0) > acknowledged
    }

    var canUndo: Bool {
        effectiveActionEvents.last != nil
    }

    var canRedo: Bool {
        redoTarget != nil
    }

    var lastOverDots: [String] {
        var dots: [String] = []
        for event in currentInningsEvents {
            switch event.kind {
            case let .ball(ball):
                dots.append(Self.dot(for: ball))
            case .overCompleted:
                dots.removeAll()
            default:
                continue
            }
        }
        return Array(dots.suffix(6))
    }

    /// Throws so a rules editor can keep its form open and show the failure.
    func chooseRules(_ rules: MatchRules) throws {
        guard let store else { throw WicketStoreError.recordNotFound }
        do {
            try store.setMatchRules(rules, fixtureID: fixture.id)
            session = try store.scoringSession(fixtureID: fixture.id)
        } catch {
            report(error)
            throw error
        }
    }

    func recordToss(winner: TeamID, decision: TossDecision) {
        append(.toss(winner: winner, decision: decision))
    }

    func startNextInnings() {
        guard let toss else {
            errorMessage = "Record the toss before starting the innings."
            return
        }
        let inningsNumber = state.innings.count + 1
        guard inningsNumber <= 2 else { return }

        let firstBatting: TeamID
        if toss.decision == .bat {
            firstBatting = toss.winner
        } else {
            firstBatting = toss.winner == fixture.homeTeamID ? fixture.awayTeamID : fixture.homeTeamID
        }
        let firstBowling = firstBatting == fixture.homeTeamID ? fixture.awayTeamID : fixture.homeTeamID
        append(
            .inningsStarted(
                number: inningsNumber,
                batting: inningsNumber == 1 ? firstBatting : firstBowling,
                bowling: inningsNumber == 1 ? firstBowling : firstBatting
            )
        )
    }

    func record(_ ball: BallEvent) {
        guard activeInnings != nil, !needsOverCompletion else { return }
        append(.ball(ball))
    }

    func completeOver() {
        guard needsOverCompletion else { return }
        append(.overCompleted)
    }

    func endInnings() {
        guard activeInnings != nil else { return }
        append(.inningsEnded(reason: .declared))
    }

    func undo() {
        guard let target = effectiveActionEvents.last else { return }
        appendCorrection(
            target: target.id,
            replacement: Self.neutralKind,
            reason: Self.undoReason
        )
    }

    func redo() {
        guard let target = redoTarget else { return }
        appendCorrection(
            target: target.event.id,
            replacement: target.event.kind,
            reason: Self.redoReason
        )
    }

    func clearError() {
        errorMessage = nil
    }

    private var events: [MatchEvent] {
        session.ledger.events
    }

    private var replacements: [EventID: (kind: MatchEventKind, sequence: Int)] {
        var values: [EventID: (MatchEventKind, Int)] = [:]
        for event in events {
            guard case let .correction(correction) = event.kind,
                  case let .replace(target, replacement) = correction.action
            else { continue }
            values[target] = (replacement, event.sequence)
        }
        return values
    }

    private var effectiveActionEvents: [MatchEvent] {
        let replacements = replacements
        return events.compactMap { event in
            guard !Self.isCorrection(event.kind) else { return nil }
            let kind = replacements[event.id]?.kind ?? event.kind
            guard !Self.isNeutral(kind) else { return nil }
            return MatchEvent(id: event.id, sequence: event.sequence, kind: kind)
        }
    }

    private var currentInningsEvents: [MatchEvent] {
        guard let startIndex = effectiveActionEvents.lastIndex(where: {
            if case .inningsStarted = $0.kind { return true }
            return false
        }) else { return [] }
        return Array(effectiveActionEvents[startIndex...])
    }

    private var redoTarget: (event: MatchEvent, correctionSequence: Int)? {
        let replacements = replacements
        return events.compactMap { event -> (MatchEvent, Int)? in
            guard !Self.isCorrection(event.kind),
                  let replacement = replacements[event.id],
                  Self.isNeutral(replacement.kind)
            else { return nil }
            return (event, replacement.sequence)
        }
        .max { $0.1 < $1.1 }
    }

    private func append(_ kind: MatchEventKind) {
        persist(MatchEvent(sequence: nextSequence, kind: kind))
    }

    private func appendCorrection(target: EventID, replacement: MatchEventKind, reason: String) {
        append(
            .correction(
                CorrectionEvent(
                    action: .replace(target: target, with: replacement),
                    reason: reason,
                    provenance: Self.correctionProvenance
                )
            )
        )
    }

    private func persist(_ event: MatchEvent) {
        do {
            guard let store else { throw WicketStoreError.recordNotFound }
            try store.appendScoringEvent(event, fixtureID: fixture.id, rules: session.rules)
            session = try store.scoringSession(fixtureID: fixture.id)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            report(error)
        }
    }

    private func reload() {
        do {
            guard let store else { throw WicketStoreError.recordNotFound }
            session = try store.scoringSession(fixtureID: fixture.id)
            homePlayers = try store.listPlayers(teamID: fixture.homeTeamID, includeArchived: true)
            awayPlayers = try store.listPlayers(teamID: fixture.awayTeamID, includeArchived: true)
        } catch {
            report(error)
        }
    }

    private var nextSequence: Int {
        (events.last?.sequence ?? 0) + 1
    }

    private func report(_ error: Error) {
        switch error {
        case WicketStoreError.scoringConflict:
            errorMessage = "The score changed elsewhere. Reopen the fixture before scoring again."
        case WicketStoreError.recordNotFound:
            errorMessage = "This fixture is no longer available for scoring."
        default:
            errorMessage = "The scoring event could not be saved."
        }
    }

    private static var neutralKind: MatchEventKind {
        .penaltyRuns(PenaltyRunEvent(awardedToBatting: false, runs: 0, reason: neutralReason))
    }

    private static func isNeutral(_ kind: MatchEventKind) -> Bool {
        guard case let .penaltyRuns(event) = kind else { return false }
        return !event.awardedToBatting && event.runs == 0 && event.reason == neutralReason
    }

    private static func isCorrection(_ kind: MatchEventKind) -> Bool {
        if case .correction = kind { return true }
        return false
    }

    private static func dot(for ball: BallEvent) -> String {
        if ball.countsAsWicket { return "W" }
        if let extra = ball.extra {
            switch extra.kind {
            case .wide: return "\(extra.runs)Wd"
            case .noBall: return ball.runsOffBat > 0 ? "\(ball.totalRuns)Nb" : "Nb"
            case .bye: return "\(extra.runs)B"
            case .legBye: return "\(extra.runs)Lb"
            }
        }
        return ball.runsOffBat == 0 ? "•" : "\(ball.runsOffBat)"
    }
}
