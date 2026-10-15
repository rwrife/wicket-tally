import ActivityKit
import IndicaTheme
import SwiftUI
import WicketKit
import WidgetKit

/// Standalone widget extension (issue #20). No app group, push token,
/// network client, account, or persistent cross-process score cache —
/// ActivityKit content state arrives only from local app scoring events.
/// Colours come only from the Indica scoreboard tokens (the trophy-glow
/// scoreboard surface), never from hardcoded colour literals.
struct MatchScoreboardWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchScoreboardActivityAttributes.self) { context in
            LockScreenScoreboard(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.battingName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.scoreline)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Overs \(context.state.overs)")
                        Spacer(minLength: 4)
                        if context.state.requiredRunRate != "unknown" {
                            Text("RRR \(context.state.requiredRunRate)")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } compactLeading: {
                Text(context.state.battingName.prefix(3))
            } compactTrailing: {
                Text(context.state.scoreline)
                    .monospacedDigit()
            } minimal: {
                Text(context.state.scoreline)
                    .monospacedDigit()
            }
        }
        // watchOS 11 mirrors iPhone Live Activities into Smart Stack without
        // a watch app; opt into a wrist-sized layout rather than scaling Lock Screen UI.
        .supplementalActivityFamilies([.small])
    }
}

/// The scorer's trophy-glow scoreboard compressed for the Lock Screen.
/// The sunlight-derived tokens keep the dark ground and warm high-contrast
/// text that read at arm's length; every figure stays text at every Dynamic
/// Type size via minimumScaleFactor.
struct LockScreenScoreboard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.activityFamily) private var activityFamily
    let state: MatchScoreboardActivityAttributes.ContentState

    private var theme: any IndicaTheme {
        colorScheme == .dark ? IndicaDarkTheme() : IndicaSunlightTheme()
    }

    var body: some View {
        // Apple Watch Smart Stack renders the `.small` family in a wrist tile;
        // the Lock Screen layout's four stacked rows overflow it and truncate
        // the scoreline, so the wrist gets its own two-line composition.
        if activityFamily == .small {
            WatchScoreboard(state: state, palette: theme.palette)
        } else {
            LockScreenLayout(state: state, palette: theme.palette)
        }
    }
}

/// Wrist tile: batting side plus score, then overs and the one chase figure
/// that matters. Everything is text so Dynamic Type scales it, and only the
/// highest-value facts survive the smaller canvas.
private struct WatchScoreboard: View {
    let state: MatchScoreboardActivityAttributes.ContentState
    let palette: IndicaPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.battingName)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(state.scoreline)
                .font(.system(.title3, design: .rounded, weight: .black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if state.isMatchClosed, state.resultText != "unknown" {
                Text(state.resultText)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
            } else {
                Text(state.watchSecondaryLine)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(palette.scoreboardForeground.color)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.scoreboardBackground.color)
        .accessibilityElement(children: .combine)
    }
}

/// The scorer's trophy-glow scoreboard compressed for the Lock Screen.
/// The sunlight-derived tokens keep the dark ground and warm high-contrast
/// text that read at arm's length; every figure stays text at every Dynamic
/// Type size via minimumScaleFactor.
private struct LockScreenLayout: View {
    let state: MatchScoreboardActivityAttributes.ContentState
    let palette: IndicaPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.homeName) · \(state.awayName)")
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .firstTextBaseline) {
                Text(state.battingName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Text(state.scoreline)
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack {
                Text("Overs \(state.overs)")
                if state.target != "unknown" {
                    Spacer(minLength: 4)
                    Text("Target \(state.target)")
                }
                if state.requiredRunRate != "unknown" {
                    Spacer(minLength: 4)
                    Text("RRR \(state.requiredRunRate)")
                }
            }
            .font(.subheadline.weight(.semibold))
            if state.isMatchClosed && state.resultText != "unknown" {
                Text(state.resultText)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(palette.scoreboardForeground.color)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.scoreboardBackground.color)
        .accessibilityElement(children: .combine)
    }
}

@main
struct MatchScoreboardWidgetBundle: WidgetBundle {
    var body: some Widget {
        MatchScoreboardWidget()
    }
}
