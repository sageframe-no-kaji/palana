// The floating keys panel — AppKit-owned, borderless, ours entirely.
// SwiftUI's Window scene reasserted titlebars, restored stale frames,
// and painted glass bands three rounds running; this panel cannot,
// because the card's ground fills the frame to its rounded edge and
// every behavior is set by hand.
//
// SIZING IS STEPPED, NOT CONTINUOUS (his ruling, 2026-07-10): the panel
// has five fixed sizes — ⌘1–⌘5 jump to one, ⌘ + / − and the icons step
// through them, and the edges do not drag. Window size and text scale
// are ONE value applied in ONE place. The continuous system before this
// had two authorities (the frame and the scale) correcting each other
// through a resize delegate — it crashed twice mid-constraint-pass and
// then drew a window whose content disagreed with its frame. One
// authority, no feedback loop, nothing to fight.

import AppKit
import PalanaCore
import SwiftUI

/// Owns the one floating keys panel.
@MainActor
final class KeysPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = KeysPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-keys-window"

    private var panel: NSPanel?

    /// True while the card is up — the surface's Esc reaches for an open
    /// glance panel even when the main window holds the keyboard.
    var isOpen: Bool { panel != nil }

    /// The card's natural size at scale 1, measured from the content.
    private var base = CGSize(width: 640, height: 420)
    /// The live zfs verbs to render in the floating card — set by `show`.
    private var zfsVerbs: [WorkbenchVerb] = []

    /// The one master text-zoom factor, shared with the whole surface (his review).
    ///
    /// The window sizes to `base * factor`; there is no bespoke per-panel step.
    private var scale: Double { TextScale.shared.factor }

    /// Summons the panel, measuring the card first so the frame is the card.
    ///
    /// The live zfs verbs render in the card.
    func show(zfsVerbs: [WorkbenchVerb] = []) {
        self.zfsVerbs = zfsVerbs
        if let panel {
            // Already up — refresh the content so the verbs are current.
            (panel.contentView as? NSHostingView<KeysPanelContent>)?.rootView =
                content(scale: scale)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let probe = NSHostingView(rootView: content(scale: 1))
        base = probe.fittingSize
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let made = KeysPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        made.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hasShadow = true
        made.level = .floating
        made.isMovableByWindowBackground = true
        // Fullscreen-auxiliary keeps the panel reachable over a fullscreen main
        // window; it no longer joins all Spaces, so it stays on the desktop it
        // was summoned on instead of following across every one (his ask).
        made.collectionBehavior = [.fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: content(scale: scale))
        // The panel's frame is the one truth — the hosting view must not
        // push content size into the window's constraint system.
        hosting.sizingOptions = []
        made.contentView = hosting
        made.delegate = self
        made.center()
        panel = made
        made.makeKeyAndOrderFront(nil)
    }

    /// Closes the panel if it is up.
    func close() {
        panel?.close()
    }

    /// Opens the panel, or closes it if already up — the single `?` toggle now
    /// that the in-window card is gone (his review: one help surface).
    func toggle(zfsVerbs: [WorkbenchVerb] = []) {
        if panel != nil {
            close()
        } else {
            show(zfsVerbs: zfsVerbs)
        }
    }

    /// Re-applies the current global factor to the open panel.
    ///
    /// Resizes the window to `base * factor` (top-left held) and re-renders the
    /// content. The surface calls this when ⌘+/−/0 changes the factor. One-way
    /// (factor → frame), no resize delegate — none of the old two-authority
    /// feedback that crashed the continuous system; the setFrame is the same
    /// clean move the stepped code made.
    func applyScale() {
        guard let panel else { return }
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        guard panel.frame.size != size else { return }
        (panel.contentView as? NSHostingView<KeysPanelContent>)?.rootView = content(scale: scale)
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    // MARK: - Content

    private func content(scale: Double) -> KeysPanelContent {
        KeysPanelContent(scale: scale, zfsVerbs: zfsVerbs) { delta in
            // The ± icons drive the one master zoom, same as ⌘+/− (his review).
            if delta > 0 { TextScale.shared.stepUp() } else { TextScale.shared.stepDown() }
        }
    }
}

/// A borderless panel that can still take the keyboard.
private final class KeysPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The panel's face — the card's ground fills the frame to its rounded
/// edge, so no band can exist between card and window.
struct KeysPanelContent: View {
    /// Text scale, driven by the panel's step.
    let scale: Double
    /// The live zfs verbs to render in the card.
    let zfsVerbs: [WorkbenchVerb]
    /// One size step, forwarded to the panel — ±1.
    let onStep: (Int) -> Void

    /// Builds the face.
    init(scale: Double, zfsVerbs: [WorkbenchVerb], onStep: @escaping (Int) -> Void) {
        self.scale = scale
        self.zfsVerbs = zfsVerbs
        self.onStep = onStep
    }

    var body: some View {
        HelpOverlay(
            scale: scale,
            zfsVerbs: zfsVerbs,
            footer: "esc closes · ⌘ + / − / 0 zoom — the one master size",
            chromeless: true
        )
        .onDismiss { KeysPanelController.shared.close() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                icon("minus.circle", delta: -1)
                icon("plus.circle", delta: 1)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func icon(_ systemName: String, delta: Int) -> some View {
        Button {
            onStep(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .help(delta > 0 ? "larger (⌘+)" : "smaller (⌘−)")
    }
}
