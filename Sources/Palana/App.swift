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

    /// The appearance override — System / Light / Dark, off one stored key the
    /// Settings picker also binds (ho-15). `.system` (nil) follows the OS live.
    @AppStorage(AppAppearance.storageKey)
    private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup("pālana") {
            SurfaceView(session: session)
                .frame(minWidth: 720, minHeight: 420)
                .preferredColorScheme(appearance.colorScheme)
                .onAppear { delegate.session = session }
        }
        .defaultSize(width: 1120, height: 700)
        Settings {
            // The same SettingsModel that drives the in-window card.
            // Both surfaces observe one instance — the practitioner's
            // preference reads the same whether reached by ⌘, the gear,
            // or the Apple Settings menu item.
            SettingsForm(model: session.settings, session: session)
                .padding(24)
                .frame(minWidth: 360)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

/// Activation and the quit path.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the scene once the session exists.
    var session: PalanaSession?

    /// A bare `swift run Palana` starts as a background process —
    /// become a regular app and take the front.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SIGPIPE's default is silent process death, and this app owns
        // descriptors that close underneath it by design (PTY sessions
        // ending, ControlMaster sockets). A stray write must surface as
        // EPIPE to the writer, never kill the app — the natural-exit
        // crash (ho-11 hands session) was exactly this.
        signal(SIGPIPE, SIG_IGN)
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
