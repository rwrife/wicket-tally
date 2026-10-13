import ActivityKit
import Foundation
import WicketKit

/// Local-only scoreboard. Queue operations so a rapid score/stop/restart cannot
/// resurrect an older ActivityKit state after a newer ledger commit.
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
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            let running = Activity<MatchScoreboardActivityAttributes>.activities
                .filter { $0.attributes.fixtureID == presentation.fixtureID }
            let state = MatchScoreboardActivityAttributes.ContentState(presentation: presentation)
            let active = isEnabled(for: presentation.fixtureID)
                && areActivitiesEnabled
                && presentation.phase != .notStarted
                && !presentation.isMatchClosed

            if !active {
                for activity in running {
                    await activity.end(
                        presentation.isMatchClosed ? ActivityContent(state: state, staleDate: nil) : nil,
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
                let attributes = MatchScoreboardActivityAttributes(fixtureID: presentation.fixtureID)
                do {
                    _ = try Activity<MatchScoreboardActivityAttributes>.request(
                        attributes: attributes,
                        content: ActivityContent(state: state, staleDate: nil),
                        pushType: nil
                    )
                } catch {
                    // Live Activity is optional; scoring must remain usable.
                    // If iOS rejects a request, the in-app board stays visible.
                }
            }
        }
    }

    func stop(for fixtureID: String) {
        let previous = pending
        pending = Task { @MainActor in
            await previous?.value
            for activity in Activity<MatchScoreboardActivityAttributes>.activities
                where activity.attributes.fixtureID == fixtureID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
