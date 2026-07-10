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
import SwiftUI

/// Owns the one floating keys panel.
@MainActor
final class KeysPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = KeysPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-keys-window"

    /// The five sizes — text and window scale together, one value.
    static let steps: [Double] = [0.7, 0.85, 1.0, 1.2, 1.4]

    private var panel: NSPanel?
    /// The card's natural size at scale 1, measured from the content.
    private var base = CGSize(width: 640, height: 420)

    private static let stepKey = "palana.keysStep"

    /// The persisted step index, clamped on read — persisted state that
    /// misbehaves must never misbehave twice (the crash-loop lesson).
    private var stepIndex: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.stepKey) != nil else { return 2 }
            let stored = UserDefaults.standard.integer(forKey: Self.stepKey)
            return min(max(stored, 0), Self.steps.count - 1)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.stepKey) }
    }

    /// Summons the panel, measuring the card first so the frame is the
    /// card and nothing else.
    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let probe = NSHostingView(rootView: content(scale: 1))
        base = probe.fittingSize
        let scale = Self.steps[stepIndex]
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
        // A fullscreen main window stranded the panel out of reach — joining
        // all Spaces and allowing fullscreen auxiliary prevents this.
        made.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

    /// Jumps to one of the five sizes — ⌘1 through ⌘5.
    func select(step: Int) {
        apply(step: step)
    }

    /// One size step up or down — the icons and ⌘ + / − land here.
    func step(by delta: Int) {
        apply(step: stepIndex + delta)
    }

    /// The one place size changes: text scale and window frame together,
    /// top-left corner held.
    private func apply(step: Int) {
        guard let panel else { return }
        let clamped = min(max(step, 0), Self.steps.count - 1)
        guard clamped != stepIndex || panel.frame.width != base.width * Self.steps[clamped] else {
            return
        }
        stepIndex = clamped
        let scale = Self.steps[clamped]
        (panel.contentView as? NSHostingView<KeysPanelContent>)?.rootView = content(scale: scale)
        var frame = panel.frame
        let size = CGSize(width: base.width * scale, height: base.height * scale)
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
        KeysPanelContent(scale: scale) { [weak self] delta in
            self?.step(by: delta)
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
    /// One size step, forwarded to the panel — ±1.
    let onStep: (Int) -> Void

    /// Builds the face.
    init(scale: Double, onStep: @escaping (Int) -> Void) {
        self.scale = scale
        self.onStep = onStep
    }

    var body: some View {
        HelpOverlay(
            scale: scale,
            footer: "esc closes · ⌘1–⌘5 pick a size · ⌘ + / − or the icons step",
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
