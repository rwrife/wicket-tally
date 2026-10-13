import ActivityKit
import Foundation
import WicketKit

/// Local-only scoreboard companion for the active match (issue #20).
///
/// In Swift 6, `Activity<Attributes>` methods (`update`, `end`) are nonisolated
/// asynchronous calls while this manager is `@MainActor`. Querying `activities`
/// inside a detached task prevents sending actor-isolated `Activity` references
/// across boundaries.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private let enabledDefaultsKeyPrefix = "wicket.liveactivity.enabled."
    private var pending: Task<Void, Never>?

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func isEnabled(for fixtureID: String) -> Bool {
        UserDefaults.standard.bool(forKey: enabledDefaultsKeyPrefix + fixtureID)
    }

    func setEnabled(_ enabled: Bool, for fixtureID: String) {
        UserDefaults.standard.set(enabled, forKey: enabledDefaultsKeyPrefix + fixtureID)
    }

    func sync(presentation: LiveScoreboardPresentation) {
        let active = isEnabled(for: presentation.fixtureID)
            && areActivitiesEnabled
            && presentation.phase != .notStarted
            && !presentation.isMatchClosed
        let state = MatchScoreboardActivityAttributes.ContentState(presentation: presentation)
        let fixtureID = presentation.fixtureID
        let isClosed = presentation.isMatchClosed

        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            await Task.detached {
                let running = Activity<MatchScoreboardActivityAttributes>.activities
                    .filter { $0.attributes.fixtureID == fixtureID }

                if !active {
                    for activity in running {
                        await activity.end(
                            isClosed ? ActivityContent(state: state, staleDate: nil) : nil,
                            dismissalPolicy: .immediate
                        )
                    }
                    return
                }

                if let current = running.first {
                    await current.update(ActivityContent(state: state, staleDate: nil))
                    for duplicate in running.dropFirst() {
                        await duplicate.end(nil, dismissalPolicy: .immediate)
                    }
                } else {
                    let attributes = MatchScoreboardActivityAttributes(fixtureID: fixtureID)
                    do {
                        _ = try Activity<MatchScoreboardActivityAttributes>.request(
                            attributes: attributes,
                            content: ActivityContent(state: state, staleDate: nil),
                            pushType: nil
                        )
                    } catch {
                        // Optional companion; keep scoring path working.
                    }
                }
            }.value
        }
    }

    func stop(for fixtureID: String) {
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            await Task.detached {
                for activity in Activity<MatchScoreboardActivityAttributes>.activities
                    where activity.attributes.fixtureID == fixtureID {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }.value
        }
    }
}
