// AboutWindow — pālana's About, a small custom window rather than the system
// panel. The layout follows the Sharibako / m4Bookmaker About: the app mark in a
// disc, the version, the maker, two outward links, and a one-line note on the
// launch update check. A single titled window, summoned from the App menu; the
// links and version all read from `Links` so the site and the number move in one
// place.

import AppKit
import SwiftUI

/// Owns the single About window and its lifetime.
@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    /// The one instance the App menu talks to.
    static let shared = AboutWindowController()

    private var window: NSWindow?

    /// Summons the About window, or brings it front if already up.
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: AboutView { [weak self] in self?.window?.close() })
        let made = NSWindow(contentViewController: hosting)
        made.title = "About pālana"
        made.styleMask = [.titled, .closable]
        made.titlebarAppearsTransparent = true
        made.isMovableByWindowBackground = true
        made.backgroundColor = NSColor(Theme.ground)
        made.delegate = self
        made.center()
        window = made
        made.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

/// The About window's face — icon, version, maker, links, update note, OK.
struct AboutView: View {
    /// Dismisses the window (the OK button and its default-action Return).
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            appMark
                .frame(width: 92, height: 92)
                .padding(.top, 24)
            Text("Version \(Links.appVersion)")
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.top, 20)
            maker
                .padding(.top, 12)
            links
                .padding(.top, 20)
            updateNote
                .padding(.top, 20)
            Button("OK", action: onClose)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 18)
                .padding(.bottom, 22)
        }
        .frame(width: 360)
        .background(Theme.ground)
    }

    /// The app icon, clipped to a disc to echo the reference mark.
    private var appMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(Circle())
    }

    private var maker: some View {
        VStack(spacing: 2) {
            Text("by Andrew T. Marcus")
            Text("Sageframe")
        }
        .font(Theme.font(13))
        .foregroundStyle(Theme.inkFaint)
    }

    private var links: some View {
        HStack(spacing: 26) {
            Link(destination: Links.github) {
                Text("GitHub")
            }
            Link(destination: Links.coffee) {
                Label("Support", systemImage: "heart.fill")
            }
        }
        .font(Theme.font(14, weight: .semibold))
        .tint(Theme.accent)
    }

    /// The launch update-check note, worded to match the Help-menu opt-out.
    private static let updateBlurb =
        "Checks GitHub for the latest version on launch "
        + "(turn off: Help → Check for Updates on Startup)."

    private var updateNote: some View {
        VStack(spacing: 5) {
            Text(Self.updateBlurb)
                .multilineTextAlignment(.center)
            Link("How the check works", destination: Links.help)
        }
        .font(Theme.font(11))
        .foregroundStyle(Theme.inkFaint)
        .tint(Theme.accent)
        .padding(.horizontal, 28)
    }
}
