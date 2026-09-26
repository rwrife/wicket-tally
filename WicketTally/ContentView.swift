import SwiftUI
import WicketKit
import WicketStore

struct ContentView: View {
    @State private var model: SetupViewModel

    init(model: SetupViewModel = .live()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            LeaguesView(model: model)
                .navigationDestination(for: LeagueID.self) { leagueID in
                    LeagueTeamsView(model: model, leagueID: leagueID)
                }
                .navigationDestination(for: TeamID.self) { teamID in
                    TeamPlayersView(model: model, teamID: teamID)
                }
                .navigationTitle("Setup")
        }
        .dynamicTypeSize(.xSmall ... .accessibility5)
        .alert(
            "Local data message",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

private struct LeaguesView: View {
    @Bindable var model: SetupViewModel
    @State private var showArchived = false

    @State private var draft: LeagueDraft?
    @State private var deletionPreview: LeagueDeletionPreview?

    var body: some View {
        List {
            Section {
                Toggle("Show archived leagues", isOn: $showArchived)
                    .accessibilityLabel("Show archived leagues")
                    .accessibilityHint("Includes archived leagues and tournaments in the list")
            }

            Section("Leagues and tournaments") {
                ForEach(model.activeLeagues(showArchived: showArchived)) { league in
                    NavigationLink(value: league.id) {
                        LeagueRow(league: league)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            run { try model.setArchived(league, archived: !league.isArchived) }
                        } label: {
                            Label(league.isArchived ? "Unarchive" : "Archive", systemImage: league.isArchived ? "tray.and.arrow.up" : "archivebox")
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            run { deletionPreview = try model.previewDeletion(of: league) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Edit") { draft = .edit(league) }
                        Button(league.isArchived ? "Unarchive" : "Archive") {
                            run { try model.setArchived(league, archived: !league.isArchived) }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            run { deletionPreview = try model.previewDeletion(of: league) }
                        }
                    }
                    .accessibilityHint("Opens teams in this league")
                }

                if model.activeLeagues(showArchived: showArchived).isEmpty {
                    Text("No leagues yet")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No leagues yet")
                        .accessibilityHint("Use Add league to create your first league or tournament")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = .create
                } label: {
                    Label("Add league", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("Add league")
                .accessibilityHint("Opens a form to create a league or tournament")
            }
        }
        .sheet(item: $draft) { draft in
            LeagueEditorSheet(
                draft: draft,
                onSave: { name, kind in
                    run {
                        switch draft {
                        case .create:
                            try model.createLeague(name: name, kind: kind)
                        case let .edit(league):
                            try model.updateLeague(league, name: name, kind: kind)
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Delete league?",
            isPresented: Binding(
                get: { deletionPreview != nil },
                set: { if !$0 { deletionPreview = nil } }
            ),
            presenting: deletionPreview
        ) { preview in
            Button("Delete \(preview.leagueName)", role: .destructive) {
                run {
                    guard let league = model.leagues.first(where: { $0.id == preview.leagueID }) else {
                        throw WicketStoreError.recordNotFound
                    }
                    try model.deleteLeague(league, confirming: preview)
                    deletionPreview = nil
                }
            }
            Button("Cancel", role: .cancel) { deletionPreview = nil }
        } message: { preview in
            Text("\(preview.summary). Review this cascade before confirming.")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.report(error)
        }
    }
}

private struct LeagueTeamsView: View {
    @Bindable var model: SetupViewModel
    let leagueID: LeagueID

    @State private var showArchived = false
    @State private var draft: TeamDraft?
    @State private var deletionPreview: TeamDeletionPreview?

    private var league: LeagueRecord? {
        model.leagues.first { $0.id == leagueID }
    }

    var body: some View {
        List {
            Section {
                Toggle("Show archived teams", isOn: $showArchived)
                    .accessibilityLabel("Show archived teams")
                    .accessibilityHint("Includes archived teams in this league")
            }

            Section {
                if let league {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(league.name)
                            .font(.headline)
                        Text(league.kind.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("League \(league.name)")
                    .accessibilityValue(league.kind.displayName)
                }
            }

            Section("Teams") {
                ForEach(model.teams(for: leagueID, showArchived: showArchived)) { team in
                    NavigationLink(value: team.id) {
                        TeamRow(team: team)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            run { try model.setArchived(team, archived: !team.isArchived) }
                        } label: {
                            Label(team.isArchived ? "Unarchive" : "Archive", systemImage: team.isArchived ? "tray.and.arrow.up" : "archivebox")
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            run { deletionPreview = try model.previewDeletion(of: team) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button("Edit") { draft = .edit(team) }
                        Button(team.isArchived ? "Unarchive" : "Archive") {
                            run { try model.setArchived(team, archived: !team.isArchived) }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            run { deletionPreview = try model.previewDeletion(of: team) }
                        }
                    }
                    .accessibilityHint("Opens players on this team")
                }

                if model.teams(for: leagueID, showArchived: showArchived).isEmpty {
                    Text("No teams yet")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No teams yet")
                }
            }
        }
        .navigationTitle("Teams")
        .task { run { try model.reloadTeams(for: leagueID) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = .create(leagueID)
                } label: {
                    Label("Add team", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("Add team")
                .accessibilityHint("Opens a form to create a team with an Indica jersey colour")
            }
        }
        .sheet(item: $draft) { draft in
            TeamEditorSheet(
                draft: draft,
                onSave: { name, colour in
                    run {
                        switch draft {
                        case let .create(parentLeagueID):
                            try model.createTeam(leagueID: parentLeagueID, name: name, colour: colour)
                        case let .edit(team):
                            try model.updateTeam(team, name: name, colour: colour)
                        }
                    }
                }
            )
            .presentationDetents([.large])
        }
        .alert(
            "Delete team?",
            isPresented: Binding(
                get: { deletionPreview != nil },
                set: { if !$0 { deletionPreview = nil } }
            ),
            presenting: deletionPreview
        ) { preview in
            Button("Delete \(preview.teamName)", role: .destructive) {
                run {
                    guard let team = model.teams(for: leagueID, showArchived: true)
                        .first(where: { $0.id == preview.teamID }) else {
                        throw WicketStoreError.recordNotFound
                    }
                    try model.deleteTeam(team, confirming: preview)
                    deletionPreview = nil
                }
            }
            Button("Cancel", role: .cancel) { deletionPreview = nil }
        } message: { preview in
            Text("\(preview.summary). Review this cascade before confirming.")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.report(error)
        }
    }
}

private struct TeamPlayersView: View {
    @Bindable var model: SetupViewModel
    let teamID: TeamID

    @State private var showArchived = false
    @State private var draft: PlayerDraft?
    @State private var deletionPreview: PlayerDeletionPreview?

    private var team: TeamRecord? {
        for teams in model.teamsByLeague.values {
            if let match = teams.first(where: { $0.id == teamID }) {
                return match
            }
        }
        return nil
    }

    var body: some View {
        List {
            Section {
                Toggle("Show archived players", isOn: $showArchived)
                    .accessibilityLabel("Show archived players")
                    .accessibilityHint("Includes archived players on this team")
            }

            Section {
                if let team {
                    HStack(spacing: 12) {
                        TeamKitChip(colour: team.colour)
                        Text(team.name)
                            .font(.headline)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Team \(team.name)")
                    .accessibilityValue(team.colour.displayName)
                }
            }

            Section("Players") {
                ForEach(model.players(for: teamID, showArchived: showArchived)) { player in
                    PlayerRow(player: player)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                run { try model.setArchived(player, archived: !player.isArchived) }
                            } label: {
                                Label(player.isArchived ? "Unarchive" : "Archive", systemImage: player.isArchived ? "tray.and.arrow.up" : "archivebox")
                            }
                            .tint(.indigo)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                run { deletionPreview = try model.previewDeletion(of: player) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button("Edit") { draft = .edit(player) }
                            Button(player.isArchived ? "Unarchive" : "Archive") {
                                run { try model.setArchived(player, archived: !player.isArchived) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                run { deletionPreview = try model.previewDeletion(of: player) }
                            }
                        }
                }

                if model.players(for: teamID, showArchived: showArchived).isEmpty {
                    Text("No players yet")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("No players yet")
                }
            }
        }
        .navigationTitle("Players")
        .task { run { try model.reloadPlayers(for: teamID) } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draft = .create(teamID)
                } label: {
                    Label("Add player", systemImage: "plus.circle.fill")
                }
                .accessibilityLabel("Add player")
                .accessibilityHint("Opens a form to create a player with batting or bowling role")
            }
        }
        .sheet(item: $draft) { draft in
            PlayerEditorSheet(
                draft: draft,
                onSave: { name, role in
                    run {
                        switch draft {
                        case let .create(parentTeamID):
                            try model.createPlayer(teamID: parentTeamID, name: name, role: role)
                        case let .edit(player):
                            try model.updatePlayer(player, name: name, role: role)
                        }
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(
            "Delete player?",
            isPresented: Binding(
                get: { deletionPreview != nil },
                set: { if !$0 { deletionPreview = nil } }
            ),
            presenting: deletionPreview
        ) { preview in
            Button("Delete \(preview.playerName)", role: .destructive) {
                run {
                    guard let player = model.players(for: teamID, showArchived: true)
                        .first(where: { $0.id == preview.playerID }) else {
                        throw WicketStoreError.recordNotFound
                    }
                    try model.deletePlayer(player, confirming: preview)
                    deletionPreview = nil
                }
            }
            Button("Cancel", role: .cancel) { deletionPreview = nil }
        } message: { preview in
            Text("\(preview.summary). This cannot be undone.")
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            model.report(error)
        }
    }
}

private struct LeagueRow: View {
    let league: LeagueRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(league.name)
                    .font(.headline)
                Text(league.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if league.isArchived {
                Text("Archived")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.secondary.opacity(0.2)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(league.kind.displayName): \(league.name)")
        .accessibilityValue(league.isArchived ? "Archived" : "Active")
    }
}

private struct TeamRow: View {
    let team: TeamRecord

    var body: some View {
        HStack(spacing: 10) {
            TeamKitChip(colour: team.colour)
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.headline)
                Text(team.colour.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if team.isArchived {
                Text("Archived")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.secondary.opacity(0.2)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Team \(team.name)")
        .accessibilityValue("\(team.colour.displayName), \(team.isArchived ? "Archived" : "Active")")
    }
}

private struct PlayerRow: View {
    let player: PlayerRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name)
                    .font(.headline)
                Text(player.role.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if player.isArchived {
                Text("Archived")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.secondary.opacity(0.2)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Player \(player.name)")
        .accessibilityValue("\(player.role.displayName), \(player.isArchived ? "Archived" : "Active")")
    }
}

private struct TeamKitChip: View {
    let colour: TeamKitColour

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tshirt.fill")
                .font(.caption.bold())
            Text(colour.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(colour.prefersLightForeground ? Color.white : Color.black)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hexRGB: colour.hexRGB))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jersey colour \(colour.displayName)")
    }
}

private struct LeagueEditorSheet: View {
    let draft: LeagueDraft
    let onSave: (String, LeagueKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: LeagueKind

    init(draft: LeagueDraft, onSave: @escaping (String, LeagueKind) -> Void) {
        self.draft = draft
        self.onSave = onSave
        switch draft {
        case .create:
            _name = State(initialValue: "")
            _kind = State(initialValue: .league)
        case let .edit(league):
            _name = State(initialValue: league.name)
            _kind = State(initialValue: league.kind)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("League name")
                    .accessibilityHint("Enter a local league or tournament name")

                Picker("Type", selection: $kind) {
                    ForEach(LeagueKind.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .accessibilityLabel("League type")
                .accessibilityHint("Choose league or tournament")
            }
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, kind)
                        dismiss()
                    }
                    .accessibilityHint("Saves this league to local storage")
                }
            }
        }
    }
}

private struct TeamEditorSheet: View {
    let draft: TeamDraft
    let onSave: (String, TeamKitColour) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colour: TeamKitColour

    init(draft: TeamDraft, onSave: @escaping (String, TeamKitColour) -> Void) {
        self.draft = draft
        self.onSave = onSave
        switch draft {
        case .create:
            _name = State(initialValue: "")
            _colour = State(initialValue: .cricketRed)
        case let .edit(team):
            _name = State(initialValue: team.name)
            _colour = State(initialValue: team.colour)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Team name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Team name")
                    .accessibilityHint("Enter a local team name")

                Section("Indica jersey colour") {
                    ForEach(TeamKitColour.allCases, id: \.self) { option in
                        Button {
                            colour = option
                        } label: {
                            HStack {
                                TeamKitChip(colour: option)
                                Spacer()
                                if option == colour {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(option.displayName) jersey colour")
                        .accessibilityValue(option == colour ? "Selected" : "Not selected")
                    }
                }
            }
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, colour)
                        dismiss()
                    }
                    .accessibilityHint("Saves this team with the selected jersey colour")
                }
            }
        }
    }
}

private struct PlayerEditorSheet: View {
    let draft: PlayerDraft
    let onSave: (String, PlayerRole) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: PlayerRole

    init(draft: PlayerDraft, onSave: @escaping (String, PlayerRole) -> Void) {
        self.draft = draft
        self.onSave = onSave
        switch draft {
        case .create:
            _name = State(initialValue: "")
            _role = State(initialValue: .batter)
        case let .edit(player):
            _name = State(initialValue: player.name)
            _role = State(initialValue: player.role)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Player name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Player name")
                    .accessibilityHint("Enter the player name")

                Picker("Role", selection: $role) {
                    ForEach(PlayerRole.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .accessibilityLabel("Player role")
                .accessibilityHint("Choose batting or bowling role tag")
            }
            .navigationTitle(draft.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, role)
                        dismiss()
                    }
                    .accessibilityHint("Saves this player locally")
                }
            }
        }
    }
}

private enum LeagueDraft: Identifiable {
    case create
    case edit(LeagueRecord)

    var id: String {
        switch self {
        case .create: return "create"
        case let .edit(league): return "edit-\(league.id.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .create: return "New league"
        case .edit: return "Edit league"
        }
    }
}

private enum TeamDraft: Identifiable {
    case create(LeagueID)
    case edit(TeamRecord)

    var id: String {
        switch self {
        case let .create(leagueID): return "create-\(leagueID.rawValue)"
        case let .edit(team): return "edit-\(team.id.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .create: return "New team"
        case .edit: return "Edit team"
        }
    }
}

private enum PlayerDraft: Identifiable {
    case create(TeamID)
    case edit(PlayerRecord)

    var id: String {
        switch self {
        case let .create(teamID): return "create-\(teamID.rawValue)"
        case let .edit(player): return "edit-\(player.id.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .create: return "New player"
        case .edit: return "Edit player"
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

#Preview("Setup CRUD") {
    ContentView(model: .preview())
}

#Preview("AX5 dynamic type") {
    ContentView(model: .preview())
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
