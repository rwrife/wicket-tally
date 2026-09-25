import SwiftUI
import WicketKit

/// Skeleton root view. The outdoor ball-by-ball scorer (issue #5) replaces
/// this screen; the glanceable scoreboard and sun-legible controls land with
/// the design-system pass (issue #9).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Wicket Tally")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
            Text(WicketKit.milestone)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
}
