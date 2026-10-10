import SwiftUI
import WicketKit
import WicketStore

struct LineupPicker: View {
    let players: [PlayerRecord]
    @Binding var lineup: TeamLineup
    var limit: Int? = nil

    var body: some View {
        Section {
            Toggle("Use batting order", isOn: $lineup.hasBattingOrder)
            Text("\(lineup.playerIDs.count) selected\(limit.map { " / \($0)" } ?? ""). Attribution may be unknown.")
                .font(.footnote)
            ForEach(Array(lineup.playerIDs.enumerated()), id: \.element) { index, id in
                HStack {
                    Text(label(id, index: index))
                    Spacer()
                    if lineup.hasBattingOrder, index > 0 {
                        Button { lineup.playerIDs.swapAt(index, index - 1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .accessibilityLabel("Move \(label(id, index: index)) earlier")
                    }
                    Button("Remove") { lineup.playerIDs.removeAll { $0 == id } }
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 60)
            }
            ForEach(players.filter { !$0.isArchived && !lineup.playerIDs.contains($0.id) }) { player in
                Button { lineup.playerIDs.append(player.id) } label: {
                    Label(player.name, systemImage: "plus.circle")
                        .frame(minHeight: 60)
                }
                .disabled(limit.map { lineup.playerIDs.count >= $0 } ?? false)
            }
        }
        .indicaRowBackground()
    }

    private func label(_ id: PlayerID, index: Int) -> String {
        let player = players.first { $0.id == id }
        let name = player.map { $0.name + ($0.isArchived ? " (unavailable — archived)" : "") }
            ?? "Deleted/unavailable player (\(id.rawValue))"
        return (lineup.hasBattingOrder ? "\(index + 1). " : "") + name
    }
}

struct LineupTemplatesView: View {
    let teamID: TeamID
    let store: WicketStore?
    @State private var templates: [LineupTemplate] = []
    @State private var players: [PlayerRecord] = []
    @State private var error: String?
    @State private var editing: LineupTemplate?
    @State private var showingEditor = false

    var body: some View {
        List {
            ForEach(templates) { template in
                Button {
                    editing = template
                    showingEditor = true
                } label: {
                    VStack(alignment: .leading) {
                        Text(template.name).font(.headline)
                        Text(template.lineup.hasBattingOrder ? "Batting order" : "Participants").font(.caption)
                        Text(template.lineup.playerIDs.enumerated().map { index, id in
                            let player = players.first { $0.id == id }
                            return (template.lineup.hasBattingOrder ? "\(index + 1). " : "") + (player.map { $0.name + ($0.isArchived ? " (unavailable)" : "") } ?? "Deleted/unavailable player")
                        }.joined(separator: ", "))
                    }
                    .frame(minHeight: 60)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        do { try store?.deleteLineupTemplate(id: template.id); reload() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            .indicaRowBackground()
        }
        .indicaScreenBackground()
        .indicaPrimaryText()
        .navigationTitle("Lineup templates")
        .toolbar {
            Button("New lineup") { editing = nil; showingEditor = true }
        }
        .onAppear { reload() }
        .sheet(isPresented: $showingEditor) {
            LineupTemplateEditor(template: editing, players: players) { name, lineup in
                guard let store else { throw WicketStoreError.recordNotFound }
                try store.saveLineupTemplate(id: editing?.id, teamID: teamID, name: name, lineup: lineup)
                reload()
            }
        }
        .alert("Lineup templates", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func reload() {
        do {
            guard let store else { throw WicketStoreError.recordNotFound }
            templates = try store.listLineupTemplates(teamID: teamID)
            players = try store.listPlayers(teamID: teamID, includeArchived: true)
        } catch { self.error = error.localizedDescription }
    }
}

private struct LineupTemplateEditor: View {
    let players: [PlayerRecord]
    let save: (String, TeamLineup) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var lineup: TeamLineup
    @State private var error: String?

    init(template: LineupTemplate?, players: [PlayerRecord], save: @escaping (String, TeamLineup) throws -> Void) {
        self.players = players
        self.save = save
        _name = State(initialValue: template?.name ?? "")
        _lineup = State(initialValue: template?.lineup ?? TeamLineup())
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Lineup name", text: $name).indicaRowBackground()
                LineupPicker(players: players, lineup: $lineup)
                if let error { Text(error).indicaRowBackground() }
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Team lineup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try save(name, lineup); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
    }
}
