import SwiftUI
import WicketKit

/// Standalone destination. The caller owns league filtering, ledger loading,
/// recomputation after edits, and persistence of manual-points audit records.
struct StatsView: View {
    @Environment(\.indicaTheme) private var theme
    let stats: LeagueStats
    var teamNames: [TeamID: String] = [:]
    var playerNames: [PlayerID: String] = [:]
    var fixtureNames: [FixtureID: String] = [:]
    var savePointsOverride: ((StandingsPointsOverride) throws -> Void)?
    @State private var editingTeam: StatsEditingTeam?

    init(
        stats: LeagueStats,
        teamNames: [TeamID: String] = [:],
        playerNames: [PlayerID: String] = [:],
        fixtureNames: [FixtureID: String] = [:],
        savePointsOverride: ((StandingsPointsOverride) throws -> Void)? = nil
    ) {
        self.stats = stats
        self.teamNames = teamNames
        self.playerNames = playerNames
        self.fixtureNames = fixtureNames
        self.savePointsOverride = savePointsOverride
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Standings") {
                    ForEach(stats.standings, id: \.teamID) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(teamNames[row.teamID] ?? row.teamID.rawValue).font(.headline)
                            Text("P \(count(row.played))  W \(count(row.won))  L \(count(row.lost))  T \(count(row.tied))")
                                .monospacedDigit()
                            if let manual = row.pointsOverride {
                                Label("Manual points override: \(manual.points)", systemImage: "pencil.circle.fill")
                                    .foregroundStyle(theme.palette.warning.color)
                                Text("\(manual.reason) - \(manual.provenance) - \(manual.recordedAt.formatted())")
                                    .font(.caption)
                                Text("Derived points: \(count(row.derivedPoints))").font(.caption)
                            } else {
                                Text("Derived points: \(count(row.points))")
                            }
                            if !row.unresolvedFixtures.isEmpty {
                                Text("Unknown totals: \(row.unresolvedFixtures.count) unresolved fixture(s).")
                                    .font(.caption).indicaSecondaryText()
                            }
                            if let reason = row.nrrUnavailableReason {
                                Text("NRR hidden: \(reason)").font(.caption).indicaSecondaryText()
                            } else {
                                Text("NRR \(UnknownSafeFormatter.rateString(row.netRunRate))")
                            }
                            if savePointsOverride != nil {
                                Button("Enter manual points") { editingTeam = StatsEditingTeam(id: row.teamID) }
                            }
                        }
                    }
                }
                .indicaRowBackground()
                Section("Player statistics") {
                    ForEach(stats.players, id: \.playerID) { player in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playerNames[player.playerID] ?? player.playerID.rawValue).font(.headline)
                            Text("Runs \(count(player.runs))  HS \(count(player.highestScore))  Avg \(rate(player.average))  SR \(rate(player.strikeRate))")
                            Text("Overs \(player.bowlingOvers.rendered)  M \(count(player.maidens))  R \(count(player.runsConceded))  W \(count(player.wickets))  Econ \(rate(player.economy))")
                            if let reason = player.battingUnavailableReason {
                                Text("Batting: \(reason)").font(.caption).indicaSecondaryText()
                            }
                            if let reason = player.bowlingUnavailableReason {
                                Text("Bowling: \(reason)").font(.caption).indicaSecondaryText()
                            }
                        }
                    }
                }
                .indicaRowBackground()
                Section("Match scorecards") {
                    ForEach(stats.scorecards.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { id in
                        if let card = stats.scorecards[id] {
                            let title = fixtureNames[id] ?? id.rawValue
                            let text = card.plainText(title: title, teamNames: teamNames, playerNames: playerNames)
                            NavigationLink(title) {
                                ScrollView {
                                    Text(text)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .padding()
                                }
                                .background(theme.palette.background.color.ignoresSafeArea())
                                .foregroundStyle(theme.palette.textPrimary.color)
                                .navigationTitle(title)
                                .toolbar {
                                    ShareLink(item: text, subject: Text(title)) {
                                        Label("Share scorecard", systemImage: "square.and.arrow.up")
                                    }
                                }
                            }
                        }
                    }
                }
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Stats")
            .overlay {
                if stats.standings.isEmpty && stats.players.isEmpty && stats.scorecards.isEmpty {
                    ContentUnavailableView("No league data", systemImage: "chart.bar")
                }
            }
            .sheet(item: $editingTeam) { team in
                if let savePointsOverride {
                    StatsPointsEditor(
                        team: team.id, name: teamNames[team.id] ?? team.id.rawValue,
                        save: savePointsOverride
                    )
                }
            }
        }
    }

    private func count(_ value: NumericValue) -> String { UnknownSafeFormatter.rateString(value, fractionDigits: 0) }
    private func rate(_ value: NumericValue) -> String { UnknownSafeFormatter.rateString(value) }
}

private struct StatsEditingTeam: Identifiable {
    let id: TeamID
}

private struct StatsPointsEditor: View {
    let team: TeamID
    let name: String
    let save: (StandingsPointsOverride) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var points = ""
    @State private var reason = ""
    @State private var provenance = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Replaces \(name)'s entire league points total. Match results and NRR are unchanged.")
                    TextField("Total points (integer)", text: $points)
                    TextField("Reason", text: $reason)
                    TextField("Provenance / entered by", text: $provenance)
                }
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Manual points override")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let total = Int(points.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                            error = "Points must be an integer."
                            return
                        }
                        do {
                            let override = try StandingsPointsOverride(
                                teamID: team, points: total, reason: reason,
                                provenance: provenance, recordedAt: Date()
                            )
                            try save(override)
                            dismiss()
                        } catch StatsDerivationError.invalidPointsOverride {
                            error = "A reason and provenance are required."
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Could not save points", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}
