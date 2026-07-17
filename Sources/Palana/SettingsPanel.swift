// SettingsPanel — settings as a floating panel, the same glass as the keys,
// favorites, host-map, and zfs cards (his ask: "all the same"). The controller
// mirrors the others; the content reuses `SettingsForm`, so the panel and the
// Apple Settings scene render one set of controls. Unlike the glance panels this
// one hosts text fields (rsync flags, the add-host form) — it becomes key and
// the key monitor passes every non-Esc key through to the field editor.

import AppKit
import SwiftUI

/// Owns the single settings panel and its lifetime.
@MainActor
final class SettingsPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = SettingsPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-settings-window"

    private var panel: NSPanel?

    /// True while the panel is up — the surface's Esc reaches for an open
    /// glance panel even when the main window holds the keyboard.
    var isOpen: Bool { panel != nil }

    /// Shows the panel, refreshing the config text first.
    ///
    /// If the panel is already up, brings it to front without rebuilding.
    func show(model: SettingsModel, session: PalanaSession) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        model.refreshConfigText()
        let made = SettingsFloatingPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 420, height: 560)),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        made.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hasShadow = true
        made.level = .floating
        made.isMovableByWindowBackground = true
        // Fullscreen-auxiliary keeps the panel reachable over a fullscreen main
        // window without joining every Space — the same behavior as the others.
        made.collectionBehavior = [.fullScreenAuxiliary]
        made.minSize = CGSize(width: 360, height: 300)
        made.contentView = NSHostingView(
            rootView: SettingsPanelContent(model: model, session: session))
        made.delegate = self
        made.center()
        made.setFrameAutosaveName("palana-settings-frame")
        panel = made
        made.makeKeyAndOrderFront(nil)
    }

    /// Toggles the panel — closes when up, opens when not.
    func toggle(model: SettingsModel, session: PalanaSession) {
        if panel != nil {
            close()
        } else {
            show(model: model, session: session)
        }
    }

    /// Closes the panel if it is up.
    func close() {
        panel?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

/// A borderless panel that can still take the keyboard — text fields need it.
private final class SettingsFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The panel's face — the header, the shared form in a scroll, a hint footer.
struct SettingsPanelContent: View {
    /// The settings model — hosts, rsync flags, and config write verbs.
    @Bindable var model: SettingsModel
    /// The session — receives the field-focused stand-down signal.
    var session: PalanaSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverlayHeader(title: "settings") { SettingsPanelController.shared.close() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsForm(model: model, session: session)
                    Divider().opacity(0.35)
                    Text("esc closes")
                        .font(Theme.font(10))
                        .foregroundStyle(Theme.inkFaint)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 6)
            }
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand { SettingsPanelController.shared.close() }
        .onDisappear {
            model.clearNotice()
            session.settingsFieldFocused = false
        }
    }
}
