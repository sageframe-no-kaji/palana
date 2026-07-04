// Palana: the SwiftUI app — a thin surface with no business logic.
// Everything it renders comes from PalanaCore; everything it does is
// forwarded intent. The delegate carries the two AppKit duties SwiftUI
// does not: activation for a bare `swift run`, and the quit path that
// closes every ControlMaster before the process ends.

import AppKit
import PalanaCore
import SwiftUI

@main
struct PalanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var delegate
    @State private var session = PalanaSession()

    var body: some Scene {
        WindowGroup("pālana") {
            SurfaceView(session: session)
                .frame(minWidth: 720, minHeight: 420)
                // The notebook is light-first for v1 — a dark variant is
                // post-hands work, not a free system toggle.
                .preferredColorScheme(.light)
                .onAppear { delegate.session = session }
        }
        .defaultSize(width: 1120, height: 700)

        // ? ? — the vocabulary as a window that stays up while the
        // hands learn. The single-? card remains the quick glance;
        // never both at once.
        Window("the keys", id: "palana-keys") {
            HelpWindow()
                .preferredColorScheme(.light)
        }
        .defaultPosition(.topTrailing)
    }
}

/// Activation and the quit path.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the scene once the session exists.
    var session: PalanaSession?

    /// A bare `swift run Palana` starts as a background process —
    /// become a regular app and take the front.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Persist, close the doors, then go — nothing outlives the window.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session else { return .terminateNow }
        session.persist()
        Task { @MainActor in
            await session.closeDoors()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Closing the window is quitting — there is no headless mode.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
