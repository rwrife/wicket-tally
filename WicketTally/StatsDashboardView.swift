import SwiftUI
import WicketKit
import WicketStore

struct StatsDashboardView: View {
    @Environment(\.indicaTheme) private var theme
    let store: WicketStore
    @State private var leagues: [LeagueRecord] = []
    @State private var selectedLeague: LeagueID?
    @State private var stats: LeagueStats?
    @State private var teamNames: [TeamID: String] = [:]
    @State private var playerNames: [PlayerID: String] = [:]
    @State private var fixtureNames: [FixtureID: String] = [:]
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if leagues.isEmpty {
                ContentUnavailableView("No leagues yet", systemImage: "chart.bar")
            } else {
                Picker("League", selection: $selectedLeague) {
                    ForEach(leagues) { league in
                        Text(league.name).tag(Optional(league.id))
                    }
                }
                .padding(.horizontal)
                if let stats {
                    StatsView(
                        stats: stats,
                        teamNames: teamNames,
                        playerNames: playerNames,
                        fixtureNames: fixtureNames,
                        savePointsOverride: { override in
                            guard let selectedLeague else { throw WicketStoreError.recordNotFound }
                            try store.setPointsOverride(leagueID: selectedLeague, override: override)
                            try reload()
                        }
                    )
                }
            }
        }
        .background(theme.palette.background.color.ignoresSafeArea())
        .foregroundStyle(theme.palette.textPrimary.color)
        .onAppear(perform: refresh)
        .onChange(of: selectedLeague) { _, _ in refresh() }
        .alert("Could not load league stats", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() {
        do {
            try reload()
        } catch {
            stats = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reload() throws {
        leagues = try store.listLeagues(includeArchived: true)
        if selectedLeague == nil || !leagues.contains(where: { $0.id == selectedLeague }) {
            selectedLeague = leagues.first?.id
        }
        guard let selectedLeague else {
            stats = nil
            return
        }
        let teams = try store.listTeams(leagueID: selectedLeague, includeArchived: true)
        let players = try teams.flatMap { try store.listPlayers(teamID: $0.id, includeArchived: true) }
        let fixtures = try store.listFixtures().filter { $0.leagueID == selectedLeague }
        let inputs = try fixtures.map { fixture in
            let session = try store.scoringSession(fixtureID: fixture.id)
            return StatsFixture(
                id: fixture.id,
                homeTeamID: fixture.homeTeamID,
                awayTeamID: fixture.awayTeamID,
                rules: session.rules,
                ledger: session.ledger,
                playerIDs: fixture.participatingPlayerIDs
            )
        }
        teamNames = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0.name) })
        playerNames = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.name) })
        fixtureNames = Dictionary(uniqueKeysWithValues: fixtures.map { ($0.id, $0.name) })
        stats = try StatsDerivation.derive(
            fixtures: inputs,
            teamIDs: teams.map(\.id),
            playerIDs: players.map(\.id),
            manualPoints: try store.listPointsOverrides(leagueID: selectedLeague)
        )
    }
}
