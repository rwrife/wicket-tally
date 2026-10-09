import SwiftUI
import WicketKit

struct PlayerSeasonView: View {
    @Environment(\.indicaTheme) private var theme
    let insight: PlayerSeasonInsight
    let stats: LeagueStats
    let teamNames: [TeamID: String]
    let playerNames: [PlayerID: String]
    let fixtureNames: [FixtureID: String]

    private var name: String { playerNames[insight.playerID] ?? insight.playerID.rawValue }

    var body: some View {
        List {
            Section("Personal bests in this league") {
                Text("Best match runs: \(count(insight.bestRuns))")
                Text("Best match wickets: \(count(insight.bestWickets))")
                Text("Unknown means missing, incomplete, or unattributed records; not zero.")
                    .font(.caption).indicaSecondaryText()
                ShareLink(item: insight.plainText(name: name, fixtureNames: fixtureNames)) {
                    Label("Share season summary", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("season.share")
            }
            .indicaRowBackground()
            Section("Match-by-match performance") {
                if insight.matches.isEmpty { Text("No recorded matches") }
                ForEach(insight.matches, id: \.fixtureID) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(fixtureNames[match.fixtureID] ?? match.fixtureID.rawValue).font(.headline)
                        if !match.isComplete { Text("Incomplete or unresolved — not a completed appearance").indicaSecondaryText() }
                        Text("Runs \(count(match.runs)) • Wickets \(count(match.wickets))").monospacedDigit()
                        Text("Cumulative runs \(count(match.cumulativeRuns)) • wickets \(count(match.cumulativeWickets))")
                        if insight.bestRunsFixtures.contains(match.fixtureID) { Text("Personal best: match runs (ties included)") }
                        if insight.bestWicketsFixtures.contains(match.fixtureID) { Text("Personal best: match wickets (ties included)") }
                        if let card = stats.scorecards[match.fixtureID] {
                            let text = card.plainText(title: fixtureNames[match.fixtureID] ?? match.fixtureID.rawValue,
                                teamNames: teamNames, playerNames: playerNames)
                            NavigationLink("Open match scorecard") {
                                ScrollView {
                                    Text(text).font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
                                }
                                .background(theme.palette.background.color.ignoresSafeArea())
                                .foregroundStyle(theme.palette.textPrimary.color)
                                .navigationTitle("Scorecard")
                            }
                        }
                    }
                }
            }
            .indicaRowBackground()
        }
        .indicaScreenBackground()
        .indicaPrimaryText()
        .navigationTitle(name)
    }

    private func count(_ value: NumericValue) -> String { UnknownSafeFormatter.ballsString(value) }
}
