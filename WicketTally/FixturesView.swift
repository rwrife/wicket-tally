import SwiftUI
import WicketKit

struct FixturesView: View {
    @State private var model: FixturesViewModel
    @State private var draft: FixtureEditorState?
    @State private var selectedConflict: [FixtureConflict] = []

    init(model: FixturesViewModel = .live()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                if model.fixtures.isEmpty {
                    Section {
                        Text("No fixtures yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Upcoming fixtures") {
                        ForEach(model.fixtures) { fixture in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    TeamChip(team: model.team(fixture.homeTeamID))
                                    Text("vs")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TeamChip(team: model.team(fixture.awayTeamID))
                                }
                                Text(fixture.name)
                                    .font(.headline)
                                Label(fixture.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                                    .font(.subheadline)
                                Label(model.ground(fixture.groundID)?.name ?? "Unknown ground", systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .onTapGesture {
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
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fixtures")
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
            }
            .overlay(alignment: .bottom) {
                if bootstrapDraft() == nil {
                    Text("Create at least one league with two teams in Setup first.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.thinMaterial, in: Capsule())
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
    let team: TeamRecord?

    var body: some View {
        Text(team?.name ?? "Unknown")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: 140, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hexRGB: team?.colour.hexRGB ?? "6B7280"))
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

                Picker("League", selection: Binding(
                    get: { draft.leagueID ?? leagues.first?.id ?? "" },
                    set: { draft.leagueID = $0 }
                )) {
                    ForEach(leagues) { league in
                        Text(league.name).tag(league.id)
                    }
                }

                Picker("Home team", selection: $draft.homeTeamID) {
                    ForEach(eligibleTeams) { team in
                        Text(team.name).tag(team.id)
                    }
                }

                Picker("Away team", selection: $draft.awayTeamID) {
                    ForEach(eligibleTeams.filter { $0.id != draft.homeTeamID }) { team in
                        Text(team.name).tag(team.id)
                    }
                }

                Picker("Ground", selection: $draft.groundID) {
                    ForEach(grounds) { ground in
                        Text(ground.name).tag(ground.id)
                    }
                }
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

                DatePicker("Starts", selection: $draft.startsAt)
                DatePicker("Ends", selection: $draft.endsAt)

                Picker("Reminder", selection: $draft.reminder) {
                    ForEach(FixtureReminder.allCases, id: \.self) { reminder in
                        Text(reminder.displayName).tag(reminder)
                    }
                }
            }
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

private extension Color {
    init(hexRGB: String) {
        let clean = hexRGB.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 6, let raw = Int(clean, radix: 16) else {
            self = .gray
            return
        }
        let red = Double((raw >> 16) & 0xFF) / 255.0
        let green = Double((raw >> 8) & 0xFF) / 255.0
        let blue = Double(raw & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

#Preview("Fixtures") {
    FixturesView(model: .preview())
}
