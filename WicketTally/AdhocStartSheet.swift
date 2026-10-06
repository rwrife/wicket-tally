import SwiftUI

/// Issue #16: start an impromptu game from two names — no league, teams,
/// players, or ground setup. The created fixture opens straight into the
/// existing outdoor scorer, so the quick path and the scheduled path share
/// one scoring surface.
struct AdhocStartSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var homeName = ""
    @State private var awayName = ""
    @State private var overs = 6
    @State private var errorMessage: String?
    /// Set while the sheet is closing on a confirmed start so the error
    /// alert cannot reappear during dismissal.
    @State private var started = false
    @FocusState private var focusedField: Field?
    let onStart: (_ homeName: String, _ awayName: String, _ overs: Int) throws -> Void

    private enum Field {
        case home, away
    }

    private static let oversChoices = [2, 5, 6, 10, 20]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Home side", text: $homeName)
                        .focused($focusedField, equals: .home)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .away }
                        .accessibilityIdentifier("adhoc.homeName")
                    TextField("Away side", text: $awayName)
                        .focused($focusedField, equals: .away)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .accessibilityIdentifier("adhoc.awayName")
                } header: {
                    Text("Who's playing?")
                } footer: {
                    Text("Names are just for this game — no league, team, or player setup needed.")
                }
                .indicaRowBackground()

                Section {
                    Picker("Overs per innings", selection: $overs) {
                        ForEach(Self.oversChoices, id: \.self) { count in
                            Text("\(count) overs").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("adhoc.overs")
                } header: {
                    Text("How long?")
                }
                .indicaRowBackground()

                Section {
                    Button("Start game") { start() }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .buttonStyle(AdhocStartButtonStyle())
                        .accessibilityIdentifier("adhoc.start")
                } footer: {
                    Text("The game opens straight into the scorer with the same glance scoreboard as a scheduled fixture.")
                }
                .indicaRowBackground()
            }
            .indicaScreenBackground()
            .indicaPrimaryText()
            .navigationTitle("Quick game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Quick game", isPresented: Binding(
                get: { errorMessage != nil && !started },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func start() {
        focusedField = nil
        do {
            try onStart(homeName, awayName, overs)
            started = true
            errorMessage = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Same ≥ 60 pt sun-legible treatment as the scorer's primary buttons,
/// with colour from the active Indica theme only.
private struct AdhocStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdhocStartBody(configuration: configuration)
    }

    private struct AdhocStartBody: View {
        @Environment(\.indicaTheme) private var theme
        let configuration: ButtonStyle.Configuration

        var body: some View {
            configuration.label
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(theme.palette.textOnAccent.color)
                .background(
                    theme.palette.accentPrimary.color,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

#Preview("Quick game") {
    AdhocStartSheet { _, _, _ in }
}
