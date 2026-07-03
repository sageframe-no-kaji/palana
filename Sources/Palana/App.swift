// Palana: the SwiftUI app — a thin surface with no business logic.
//
// Placeholder shell. The Surface (dual panes, plan panel, field view,
// keyboard grammar) arrives with its hos; everything it renders comes
// from PalanaCore.

import PalanaCore
import SwiftUI

@main
struct PalanaApp: App {
    var body: some Scene {
        WindowGroup("pālana") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("pālana")
                .font(.largeTitle)
            Text("v\(PalanaCore.version)")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 320)
    }
}
