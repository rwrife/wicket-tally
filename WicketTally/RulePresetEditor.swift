import SwiftUI
import WicketKit

struct RulePresetHeader: View {
    let rules: MatchRules

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rules.presetName)
                .font(.headline)
            Text(rules.summary)
                .font(.subheadline)
                .indicaSecondaryText()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The caller owns persistence and decides when a preset can be changed.
/// Throwing from onSave keeps the editor open and displays the storage error.
struct RulePresetEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let presetID: UUID
    private let onSave: (RulePreset) throws -> Void
    @State private var name: String
    @State private var overs: Int
    @State private var balls: Int
    @State private var players: Int
    @State private var runCutEnabled: Bool
    @State private var runCut: Int
    @State private var inningsCapEnabled: Bool
    @State private var inningsCap: Int
    @State private var runPresets: [Int]
    @State private var oneHandCatch: Bool
    @State private var errorMessage: String?

    init(initial: RulePreset, onSave: @escaping (RulePreset) -> Void) {
        self.init(preset: initial, onSave: onSave)
    }

    init(preset: RulePreset = .standard, onSave: @escaping (RulePreset) throws -> Void) {
        presetID = preset.id == RulePreset.standard.id ? UUID() : preset.id
        self.onSave = onSave
        _name = State(initialValue: preset.name)
        _overs = State(initialValue: preset.oversPerInnings)
        _balls = State(initialValue: preset.ballsPerOver)
        _players = State(initialValue: preset.playersPerSide)
        _runCutEnabled = State(initialValue: preset.maxRunsPerOver != nil)
        _runCut = State(initialValue: preset.maxRunsPerOver ?? 10)
        _inningsCapEnabled = State(initialValue: preset.inningsRunCap != nil)
        _inningsCap = State(initialValue: preset.inningsRunCap ?? 50)
        _runPresets = State(initialValue: preset.runPresets)
        _oneHandCatch = State(initialValue: preset.oneHandCatchAllowed)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scoring contract") {
                    TextField("Preset name", text: $name)
                    Stepper("\(overs) overs per innings", value: $overs, in: RulePreset.overRange)
                    Stepper("\(balls) balls per over", value: $balls, in: RulePreset.ballsPerOverRange)
                    Stepper("\(players) players per side", value: $players, in: RulePreset.playersPerSideRange)
                }
                .indicaRowBackground()
                Section {
                    Toggle("Run cutoff per over", isOn: $runCutEnabled)
                    if runCutEnabled {
                        Stepper("\(runCut) runs cut", value: $runCut, in: RulePreset.overRunCutRange)
                    }
                    Toggle("Innings run cap", isOn: $inningsCapEnabled)
                    if inningsCapEnabled {
                        Stepper("\(inningsCap) run innings cap", value: $inningsCap, in: RulePreset.inningsRunCapRange)
                    }
                    Toggle("One-hand catch", isOn: $oneHandCatch)
                } footer: {
                    Text("A run-cut over ends on the ball limit or bat runs plus extras, whichever comes first. The full scoring event is recorded, including runs beyond a cutoff or cap. Standalone penalties do not cut an over.")
                }
                .indicaRowBackground()
                Section {
                    ForEach(Array(RulePreset.runPresetRange), id: \.self) { runs in
                        Toggle("\(runs) runs", isOn: Binding(
                            get: { runPresets.contains(runs) },
                            set: { selected in
                                if selected {
                                    runPresets.append(runs)
                                    runPresets.sort()
                                } else {
                                    runPresets.removeAll { $0 == runs }
                                }
                            }
                        ))
                    }
                } header: {
                    Text("Quick-entry run buttons")
                } footer: {
                    Text("Choose at least one button. Other recorded run totals are not capped by these choices.")
                }
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Rule preset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .alert("Could not save preset", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        do {
            let preset = try RulePreset(
                id: presetID,
                name: name,
                oversPerInnings: overs,
                ballsPerOver: balls,
                playersPerSide: players,
                maxRunsPerOver: runCutEnabled ? runCut : nil,
                inningsRunCap: inningsCapEnabled ? inningsCap : nil,
                runPresets: runPresets,
                oneHandCatchAllowed: oneHandCatch
            )
            try onSave(preset)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
