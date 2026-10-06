import SwiftUI
import WicketKit

struct FixturesView: View {
    @Environment(\.indicaTheme) private var theme
    @State private var statsLeague: LeagueRecord?
    /// Held in parent state so saving an override recomputes in place instead
    /// of rebuilding (and dismissing) the sheet.
    @State private var leagueStats: LeagueStats?
    @State private var model: FixturesViewModel
    @State private var draft: FixtureEditorState?
    @State private var selectedConflict: [FixtureConflict] = []
    @State private var showingAdhocSheet = false
    @State private var showingScheduleDraft = false
    /// Set by a confirmed quick-game start; drives the navigation to the
    /// scorer once the sheet has dismissed (a sheet cannot present a push
    /// while it is on screen).
    @State private var pendingAdhocFixture: FixtureRecord?
    /// Value-based path so a confirmed quick game can push the scorer from
    /// outside the sheet that started it.
    @State private var path: [FixtureRecord] = []

    init(model: FixturesViewModel = .live()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        showingAdhocSheet = true
                    } label: {
                        Label("Quick game", systemImage: "play.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .accessibilityIdentifier("fixtures.quickGame")
                } footer: {
                    Text("Score an impromptu game from two names — no league, teams, or ground setup.")
                }
                .indicaRowBackground()

                Section {
                    Button {
                        showingScheduleDraft = true
                    } label: {
                        Label("Draft tournament schedule", systemImage: "calendar.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .disabled(model.leagues.isEmpty || model.grounds.isEmpty)
                    .accessibilityIdentifier("fixtures.draftSchedule")
                } footer: {
                    Text("Generate and review offline. Nothing is saved until you confirm.")
                }
                .indicaRowBackground()

                if model.fixtures.isEmpty {
                    Section {
                        Text("No fixtures yet")
                            .foregroundStyle(theme.palette.textSecondary.color)
                    }
                    .indicaRowBackground()
                } else {
                    Section("Upcoming fixtures") {
                        ForEach(model.fixtures) { fixture in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    TeamChip(team: model.team(fixture.homeTeamID))
                                    Text("vs")
                                        .font(.caption.bold())
                                        .foregroundStyle(theme.palette.textSecondary.color)
                                    TeamChip(team: model.team(fixture.awayTeamID))
                                }
                                Text(fixture.name)
                                    .font(.headline)
                                Label(fixture.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                    .font(.subheadline)
                                Label(model.ground(fixture.groundID)?.name ?? "Unknown ground", systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                NavigationLink {
                                    ScorerView(
                                        fixture: fixture,
                                        homeName: model.team(fixture.homeTeamID)?.name ?? "Home",
                                        awayName: model.team(fixture.awayTeamID)?.name ?? "Away",
                                        store: model.scoringStore
                                    )
                                } label: {
                                    Label("Score match", systemImage: "cricket.ball.fill")
                                        .font(.headline)
                                        .frame(minHeight: 60)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("fixture.score.\(fixture.id.rawValue)")

                                Button("Edit fixture") {
                                    draft = .edit(fixture, FixtureDraft(
                                        leagueID: fixture.leagueID,
                                        name: fixture.name,
                                        homeTeamID: fixture.homeTeamID,
                                        awayTeamID: fixture.awayTeamID,
                                        groundID: fixture.groundID,
                                        startsAt: fixture.startsAt,
                                        endsAt: fixture.endsAt,
                                        reminder: fixture.reminder
                                    ))
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("fixture.edit.\(fixture.id.rawValue)")
                            }
                            .padding(.vertical, 8)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await model.delete(fixture)
                                        } catch {
                                            model.report(error)
                                        }
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .indicaRowBackground()
                            }
                        }
                        .indicaScreenBackground()
                    }
                }
            }
            .navigationTitle("Fixtures")
            .navigationDestination(for: FixtureRecord.self) { fixture in
                ScorerView(
                    fixture: fixture,
                    homeName: model.team(fixture.homeTeamID)?.name ?? "Home",
                    awayName: model.team(fixture.awayTeamID)?.name ?? "Away",
                    store: model.scoringStore
                )
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let bootstrap = bootstrapDraft() {
                            draft = .create(bootstrap)
                        }
                    } label: {
                        Label("Add fixture", systemImage: "plus.circle.fill")
                    }
                    .disabled(bootstrapDraft() == nil)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(model.leagues) { league in
                            Button(league.name) {
                                // No silent fallback: a derivation or store
                                // failure is surfaced instead of opening a
                                // sheet with missing or stale numbers.
                                do {
                                    leagueStats = try model.leagueStats(for: league.id)
                                    statsLeague = league
                                } catch {
                                    leagueStats = nil
                                    model.reportStatsFailure(error, league: league.name)
                                }
                            }
                        }
                    } label: {
                        Label("Standings", systemImage: "list.number")
                    }
                    .disabled(model.leagues.isEmpty)
                    .accessibilityIdentifier("fixtures.standings")
                }
            }
            // Identity is the league, never the derived stats value, so a
            // recomputation updates the sheet instead of dismissing it.
            .sheet(item: $statsLeague, onDismiss: { leagueStats = nil }) { league in
                leagueStatsSheet(for: league)
            }
            .sheet(isPresented: $showingScheduleDraft) {
                ScheduleDraftSheet(model: model)
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $showingAdhocSheet, onDismiss: {
                // Push the scorer only now that the sheet is gone; a push
                // while a sheet is up gets swallowed by the presentation.
                if let fixture = pendingAdhocFixture {
                    pendingAdhocFixture = nil
                    path.append(fixture)
                }
            }) {
                AdhocStartSheet { homeName, awayName, overs in
                    do {
                        let start = try model.startQuickGame(homeName: homeName, awayName: awayName, overs: overs)
                        pendingAdhocFixture = start.fixture
                    } catch {
                        // The sheet keeps its form open and shows the
                        // failure itself; no parent-level alert stacked
                        // behind it.
                        throw error
                    }
                }
                .presentationDetents([.large])
            }
            .alert(
                "Fixtures",
                isPresented: Binding(
                    get: { model.errorMessage != nil && statsLeague == nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .overlay(alignment: .bottom) {
                if bootstrapDraft() == nil {
                    Text("Or tap Quick game above to score right now — no league, teams, or ground needed.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(theme.palette.surfaceElevated.color, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .sheet(item: $draft) { state in
            FixtureEditorSheet(
                state: state,
                leagues: model.leagues,
                teams: model.teams,
                grounds: model.grounds,
                onCreateGround: { name in
                    do {
                        let ground = try model.createGround(name: name)
                        return ground.id
                    } catch {
                        model.report(error)
                        return nil
                    }
                },
                onSave: { state, edited in
                    Task {
                        do {
                            selectedConflict = try await model.save(edited, editing: state.fixture)
                            draft = nil
                        } catch {
                            model.report(error)
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
        .alert(
            "Conflict warning",
            isPresented: Binding(
                get: { !selectedConflict.isEmpty },
                set: { if !$0 { selectedConflict = [] } }
            )
        ) {
            Button("OK", role: .cancel) { selectedConflict = [] }
        } message: {
            Text(selectedConflict.map(\.explanation).joined(separator: "\n"))
        }
    }

    @ViewBuilder
    private func leagueStatsSheet(for league: LeagueRecord) -> some View {
        if let stats = leagueStats {
            StatsView(
                stats: stats,
                teamNames: Dictionary(
                    uniqueKeysWithValues: model.teams.map { ($0.id, $0.name) }
                ),
                playerNames: Dictionary(
                    uniqueKeysWithValues: model.players.map { ($0.id, $0.name) }
                ),
                fixtureNames: Dictionary(
                    uniqueKeysWithValues: model.fixtures.map { ($0.id, $0.name) }
                ),
                savePointsOverride: { override in
                    try model.savePointsOverride(override, leagueID: league.id)
                    // Recompute synchronously: a throw here keeps the editor
                    // open and reports the real cause, while success refreshes
                    // the visible standings in place.
                    do {
                        leagueStats = try model.leagueStats(for: league.id)
                    } catch {
                        model.reportStatsFailure(error, league: league.name)
                        throw error
                    }
                }
            )
        } else {
            VStack(spacing: 12) {
                Label("Standings unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(theme.palette.warning.color)
                Text(model.errorMessage ?? "The standings could not be derived for \(league.name).")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.palette.textSecondary.color)
            }
            .padding(24)
            .accessibilityIdentifier("fixtures.standingsError")
        }
    }

    private func bootstrapDraft() -> FixtureDraft? {
        guard let firstLeague = model.leagues.first else { return nil }
        let leagueTeams = model.teams.filter { $0.leagueID == firstLeague.id }
        guard leagueTeams.count >= 2 else { return nil }
        let start = Date().addingTimeInterval(7_200)
        return FixtureDraft(
            leagueID: firstLeague.id,
            name: "\(leagueTeams[0].name) vs \(leagueTeams[1].name)",
            homeTeamID: leagueTeams[0].id,
            awayTeamID: leagueTeams[1].id,
            groundID: model.grounds.first?.id ?? GroundID(""),
            startsAt: start,
            endsAt: start.addingTimeInterval(7_200),
            reminder: .oneHourBefore
        )
    }
}

private struct TeamChip: View {
    @Environment(\.indicaTheme) private var theme
    let team: TeamRecord?

    var body: some View {
        // Kit colours come from the theme's contrast-audited chip styles, so
        // the foreground is legible on every skin including sunlight.
        let style = theme.chipStyle(for: IndicaKitColour(team?.colour ?? .cricketRed))
        Text(team?.name ?? "Unknown")
            .font(.headline)
            .foregroundStyle(style.foreground.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 140, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(style.fill.color)
                    .strokeBorder(style.stroke.color, lineWidth: 2)
            )
    }
}

private enum FixtureEditorState: Identifiable {
    case create(FixtureDraft)
    case edit(FixtureRecord, FixtureDraft)

    var id: String {
        switch self {
        case let .create(draft): return "create-\(draft.homeTeamID.rawValue)-\(draft.awayTeamID.rawValue)"
        case let .edit(fixture, _): return "edit-\(fixture.id.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .create: return "New fixture"
        case .edit: return "Edit fixture"
        }
    }

    var fixture: FixtureRecord? {
        switch self {
        case .create: return nil
        case let .edit(fixture, _): return fixture
        }
    }

    var draft: FixtureDraft {
        switch self {
        case let .create(draft): return draft
        case let .edit(_, draft): return draft
        }
    }
}

private struct FixtureEditorSheet: View {
    let state: FixtureEditorState
    let leagues: [LeagueRecord]
    let teams: [TeamRecord]
    let grounds: [GroundRecord]
    let onCreateGround: (String) -> GroundID?
    let onSave: (FixtureEditorState, FixtureDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixtureDraft
    @State private var newGroundName = ""

    init(
        state: FixtureEditorState,
        leagues: [LeagueRecord],
        teams: [TeamRecord],
        grounds: [GroundRecord],
        onCreateGround: @escaping (String) -> GroundID?,
        onSave: @escaping (FixtureEditorState, FixtureDraft) -> Void
    ) {
        self.state = state
        self.leagues = leagues
        self.teams = teams
        self.grounds = grounds
        self.onCreateGround = onCreateGround
        self.onSave = onSave
        _draft = State(initialValue: state.draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Fixture name", text: $draft.name)
                    .indicaRowBackground()

                Picker("League", selection: Binding(
                    get: { draft.leagueID ?? leagues.first?.id ?? "" },
                    set: { draft.leagueID = $0 }
                )) {
                    ForEach(leagues) { league in
                        Text(league.name).tag(league.id)
                    }
                }
                .indicaRowBackground()

                Picker("Home team", selection: $draft.homeTeamID) {
                    ForEach(eligibleTeams) { team in
                        Text(team.name).tag(team.id)
                    }
                }
                .indicaRowBackground()

                Picker("Away team", selection: $draft.awayTeamID) {
                    ForEach(eligibleTeams.filter { $0.id != draft.homeTeamID }) { team in
                        Text(team.name).tag(team.id)
                    }
                }
                .indicaRowBackground()

                Picker("Ground", selection: $draft.groundID) {
                    ForEach(grounds) { ground in
                        Text(ground.name).tag(ground.id)
                    }
                }
                .indicaRowBackground()
                .onAppear {
                    if draft.groundID.rawValue.isEmpty, let first = grounds.first {
                        draft.groundID = first.id
                    }
                }

                HStack {
                    TextField("New ground", text: $newGroundName)
                    Button("Add") {
                        if let id = onCreateGround(newGroundName) {
                            draft.groundID = id
                            newGroundName = ""
                        }
                    }
                }
                .indicaRowBackground()

                DatePicker("Starts", selection: $draft.startsAt)
                    .indicaRowBackground()
                DatePicker("Ends", selection: $draft.endsAt)
                    .indicaRowBackground()

                Picker("Reminder", selection: $draft.reminder) {
                    ForEach(FixtureReminder.allCases, id: \.self) { reminder in
                        Text(reminder.displayName).tag(reminder)
                    }
                }
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle(state.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(state, draft)
                        dismiss()
                    }
                }
            }
        }
    }

    private var eligibleTeams: [TeamRecord] {
        let leagueID = draft.leagueID
        return teams.filter { team in
            if let leagueID { return team.leagueID == leagueID }
            return true
        }
    }
}

#Preview("Fixtures") {
    FixturesView(model: .preview())
}
