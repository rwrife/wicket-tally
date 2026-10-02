import SwiftUI
import WicketKit
import WicketStore

/// Wicket Tally app entry point.
///
/// iPhone-only by user directive 2026-09-15 (`TARGETED_DEVICE_FAMILY = 1`
/// in every build configuration; CI enforces it pre- and post-build).
/// Zero-network by construction: no network APIs anywhere in app or
/// package sources — CI enforces an empty-allowlist scan.
@main
struct WicketTallyApp: App {
    @State private var dataGeneration = 0
    @State private var showDataRefresh = false

    init() {
        // UI-test seam (issue #9): `--indica-theme <id>` seeds the persisted
        // skin selection before the first view reads it, so the Sunlight
        // theme layout tests run deterministically on the CI simulator.
        // Unknown ids are ignored; real users' stored choice is untouched.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--indica-theme"),
           index + 1 < arguments.count,
           IndicaThemeSelection(rawValue: arguments[index + 1]) != nil {
            UserDefaults.standard.set(arguments[index + 1], forKey: "indica.theme.selection")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppHome(onDataChanged: {
                dataGeneration += 1
                showDataRefresh = true
            })
                .id(dataGeneration)
                .alert("Local data updated", isPresented: $showDataRefresh) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Your views now show the restored or cleared records.")
                }
        }
    }
}

private struct AppHome: View {
    @State private var model = SetupViewModel.live()
    let onDataChanged: () -> Void

    var body: some View {
        ContentView(model: model) {
            if let store = model.dataStore {
                StatsDashboardView(store: store)
                    .tabItem { Label("Stats", systemImage: "chart.bar") }

                NavigationStack {
                    BackupSettingsView(store: store, onDataChanged: onDataChanged)
                }
                .tabItem { Label("Data", systemImage: "externaldrive") }
            }
        }
    }
}
