// The floating ZFS panel — the first Workbench plugin panel. AppKit-owned,
// borderless, on the FavoritesPanel lineage: NSPanel + SwiftUI content view,
// shared singleton controller, toggle/close API, key handling by window
// identity.
//
// DEMOTED (ho-10.3): the panel is a glance-overview and a launcher now, not
// a mutation surface — its eight verb rows are gone. A pane entering zfs
// mode (the `Z` key, capability-gated) is the one place a zfs verb can
// fire; the panel's tree still shows the topology and opens datasets into
// a pane, either as an ordinary file view or directly into zfs mode. One
// mutation surface, one cursor per pane.
//
// Target line: reads cached facts from the Field (synchronously via the actor)
// to find the dataset the focused pane stands in. Recomputes when the panel
// opens and when the focused pane's host or path changes (.task(id:) on a
// combined identity key). No wire contact.
//
// SIZING IS STEPPED, NOT CONTINUOUS (mirrors the keys panel ruling,
// 2026-07-10): five fixed sizes — ⌘1–⌘5 jump to one, ⌘+/− step —
// edges do not drag. One sizing authority: apply(step:) on the
// controller. Never from a delegate resize callback; never rebuild the
// SwiftUI tree inside a resize or layout pass — the crash history on
// the keys panel encodes why.

import AppKit
import PalanaCore
import SwiftUI

// MARK: - ZFSPanelController

/// Owns the one floating ZFS panel.
@MainActor
final class ZFSPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = ZFSPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-zfs-window"

    private var panel: NSPanel?

    /// True while the panel is up — the surface's Esc reaches for an open
    /// glance panel even when the main window holds the keyboard.
    var isOpen: Bool { panel != nil }

    /// The base size at scale 1.0 (step index 2) — 300 × 600.
    ///
    /// Taller than the original 480 to accommodate the dataset tree above
    /// the verb rows without crowding either section.
    private let base = CGSize(width: 300, height: 600)

    /// The selection model — shared with the key handler so arrow keys
    /// move the selection without rebuilding the hosting SwiftUI tree.
    let selection = ZFSPanelSelection()

    /// The session the panel was shown with — needed to re-render the
    /// content at a new text scale when the size steps (keys-panel pattern).
    private weak var session: PalanaSession?

    /// The hand-persisted window origin — "x,y".
    ///
    /// See show() for why the system frame autosave is not trusted
    /// with this window.
    private static let originKey = "palana.zfsPanelOrigin"

    /// The one master text-zoom factor, shared with the whole surface (his review).
    ///
    /// The window sizes to `base * factor`; no bespoke per-panel step.
    private var scale: Double { TextScale.shared.factor }

    /// Shows the panel, rebuilding only when it is not yet up.
    ///
    /// If the panel is already visible, brings it to front without
    /// rebuilding the hosting view.
    func show(session: PalanaSession) {
        self.session = session
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        let made = ZFSFloatingPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
        let hosting = NSHostingView(rootView: ZFSPanelContent(session: session, scale: scale))
        // The panel's frame is the one truth — the hosting view must not
        // push content size into the window's constraint system.
        hosting.sizingOptions = []
        made.contentView = hosting
        made.delegate = self
        // The panel owns its persistence outright. Frame autosave burned
        // us twice — a stale legacy key, then a frame saved on a
        // disconnected external display — so the machinery loses the
        // pen: origin remembered by hand (clamped to a live screen),
        // size ALWAYS step-authored.
        made.setContentSize(size)
        var placed = false
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let origin = NSPoint(x: parts[0], y: parts[1])
                if NSScreen.screens.contains(where: { $0.visibleFrame.contains(origin) }) {
                    made.setFrameOrigin(origin)
                    placed = true
                }
            }
        }
        if !placed { made.center() }
        panel = made
        made.makeKeyAndOrderFront(nil)
        // Something in the first layout pass squeezes the window to the
        // content's fitting height (width survives, height collapses —
        // the hands round's squat panel, third appearance). The step is
        // the only sizing authority: reassert after ordering front, and
        // once more a turn later for whatever lays out after us.
        made.setContentSize(size)
        DispatchQueue.main.async { [weak made] in
            made?.setContentSize(size)
        }
    }

    /// Toggles the panel — closes when up, opens when not.
    func toggle(session: PalanaSession) {
        if panel != nil {
            close()
        } else {
            show(session: session)
        }
    }

    /// Closes the panel if it is up.
    func close() {
        panel?.close()
    }

    /// Re-applies the current global factor to the open panel.
    ///
    /// Resizes to `base * factor` (top-left held) and re-renders the content.
    /// The surface calls this when ⌘+/−/0 changes the factor. One-way (factor →
    /// frame), no resize delegate — the same clean setFrame the stepped code
    /// made, so none of the old two-authority feedback.
    func applyScale() {
        guard let panel else { return }
        let size = CGSize(width: base.width * scale, height: base.height * scale)
        guard panel.frame.size != size else { return }
        if let session {
            (panel.contentView as? NSHostingView<ZFSPanelContent>)?.rootView =
                ZFSPanelContent(session: session, scale: scale)
        }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let origin = panel?.frame.origin {
            UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
        }
        panel = nil
    }
}

/// A borderless panel that can still take the keyboard.
private final class ZFSFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - ZFSPanelContent

/// The panel's face — ground fills the frame to the rounded edge.
struct ZFSPanelContent: View {
    /// The root session — verbs, availability, focused pane, engine.
    let session: PalanaSession
    /// Text scale, driven by the panel's size step.
    var scale: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            OverlayHeader(title: "zfs overview", scale: scale) { ZFSPanelController.shared.close() }
            ZFSPanelView(
                session: session,
                selection: ZFSPanelController.shared.selection,
                scale: scale
            )
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand { ZFSPanelController.shared.close() }
    }
}

// MARK: - ZFSPanelView

/// The dataset tree and target line — the panel's working area.
///
/// Demoted by ho-10.3: the panel is a glance-overview and a launcher now,
/// not a mutation surface. Its verb rows are gone — every zfs mutation
/// routes through a pane in zfs mode, one cursor, one place a destroy can
/// aim. The tree still shows the topology and still opens mounted
/// datasets into a pane; it has gained "open as zfs mode" alongside
/// "open in pane" (``ZFSDatasetTree``'s row context menu).
///
/// No wire contact — all cache reads are actor-hops to `field.facts(for:)`.
struct ZFSPanelView: View {
    /// The root session — focused pane, engine, mode-entry route.
    let session: PalanaSession
    /// The selection model — shared with the controller's key handler.
    let selection: ZFSPanelSelection
    /// Text scale, driven by the panel's size step — fonts, paddings, and
    /// row heights all multiply by it (the keys-panel ruling).
    var scale: Double = 1.0

    // MARK: - Derived state

    private var focusedHost: String? { session.focusedPane.state.host }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            targetLine
                .padding(.horizontal, 16 * scale)
                .padding(.top, 8 * scale)
                .padding(.bottom, 6 * scale)
            Divider().opacity(0.35)
            ZFSDatasetTree(session: session, selection: selection, scale: scale)
                .padding(.top, 4 * scale)
            panelFooter
        }
    }

    // MARK: - Target line

    /// Shows the selected dataset and host, or guidance when none is selected.
    @ViewBuilder private var targetLine: some View {
        if let dataset = selection.selectedDataset, let host = focusedHost {
            Text("\(dataset) · \(host) — a glance, nothing more. Z makes the focused pane the zfs surface")
                .font(.system(size: 11 * scale, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        } else {
            Text("point a pane at a host — select a dataset in the tree")
                .font(.system(size: 11 * scale))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    // MARK: - Footer

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Text(
                "↑↓ choose · ⇧⌘←/→ open in pane · Z zfs pane mode · esc closes · ⌘1–⌘5 size · ⌘+/− step"
            )
            .font(.system(size: 10 * scale))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 16 * scale)
            .padding(.vertical, 8 * scale)
        }
    }
}
