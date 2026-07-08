// The floating keys panel — AppKit-owned, borderless, ours entirely.
// SwiftUI's Window scene reasserted titlebars, restored stale frames,
// and painted glass bands three rounds running; this panel cannot,
// because the card's ground fills the frame to its rounded edge and
// every behavior is set by hand. Drag the body to move, drag an edge
// to resize (aspect locked), ⌘ + / − or the icons to scale, Esc to
// close — all the doors, one truth.

import AppKit
import SwiftUI

/// Owns the one floating keys panel.
@MainActor
final class KeysPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = KeysPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-keys-window"

    private var panel: NSPanel?
    /// The card's natural size at scale 1, measured from the content.
    private var base = CGSize(width: 640, height: 420)

    private static let scaleRange = 0.7...1.8
    private static let scaleKey = "palana.keysScale"

    private var scale: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.scaleKey)
            return stored == 0 ? 1.0 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.scaleKey) }
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
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let made = KeysPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
        made.contentAspectRatio = base
        made.minSize = CGSize(
            width: base.width * Self.scaleRange.lowerBound,
            height: base.height * Self.scaleRange.lowerBound)
        made.maxSize = CGSize(
            width: base.width * Self.scaleRange.upperBound,
            height: base.height * Self.scaleRange.upperBound)
        made.contentView = NSHostingView(rootView: content(scale: scale))
        made.delegate = self
        made.center()
        panel = made
        made.makeKeyAndOrderFront(nil)
    }

    /// Closes the panel if it is up.
    func close() {
        panel?.close()
    }

    /// One resize step — the icons and ⌘ + / − land here.
    func adjust(by delta: Double) {
        guard let panel else { return }
        let next = clamp(panel.frame.width / base.width + delta)
        scale = next
        var frame = panel.frame
        let size = CGSize(width: base.width * next, height: base.height * next)
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    /// An edge drag lands here — the frame is the truth, the scale
    /// follows it, the content refits.
    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        let next = clamp(panel.frame.width / base.width)
        scale = next
        (panel.contentView as? NSHostingView<KeysPanelContent>)?.rootView = content(scale: next)
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }

    // MARK: - Content

    private func content(scale: Double) -> KeysPanelContent {
        KeysPanelContent(scale: scale) { [weak self] delta in
            self?.adjust(by: delta)
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }
}

/// A borderless panel that can still take the keyboard.
private final class KeysPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The panel's face — the card's ground fills the frame to its rounded
/// edge, so no band can exist between card and window.
struct KeysPanelContent: View {
    /// Text scale, driven by the panel's frame.
    let scale: Double
    /// One resize step, forwarded to the panel.
    let onAdjust: (Double) -> Void

    var body: some View {
        HelpOverlay(
            scale: scale,
            footer: "esc closes · drag an edge, ⌘ + / −, or the icons resize"
        )
        .onDismiss { KeysPanelController.shared.close() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                icon("minus.circle", delta: -0.1)
                icon("plus.circle", delta: 0.1)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func icon(_ systemName: String, delta: Double) -> some View {
        Button {
            onAdjust(delta)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .help(delta > 0 ? "larger (⌘+)" : "smaller (⌘−)")
    }
}
