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

    /// The five sizes — window scales from the base at each step.
    static let steps: [Double] = [0.7, 0.85, 1.0, 1.2, 1.4]

    private var panel: NSPanel?

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

    private static let stepKey = "palana.zfsPanelStep"

    /// The persisted step index, clamped on read — persisted state that
    /// crashes must never crash twice (the crash-loop lesson from the keys panel).
    private var stepIndex: Int {
        get {
            guard UserDefaults.standard.object(forKey: Self.stepKey) != nil else { return 2 }
            let stored = UserDefaults.standard.integer(forKey: Self.stepKey)
            return min(max(stored, 0), Self.steps.count - 1)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.stepKey) }
    }

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
        let scale = Self.steps[stepIndex]
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
        // A fullscreen main window stranded the panel out of reach — joining
        // all Spaces and allowing fullscreen auxiliary prevents this.
        made.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: ZFSPanelContent(session: session, scale: scale))
        // The panel's frame is the one truth — the hosting view must not
        // push content size into the window's constraint system.
        hosting.sizingOptions = []
        made.contentView = hosting
        made.delegate = self
        // setFrameAutosaveName persists position only; size is step-authored.
        made.setFrameAutosaveName("palana-zfs-position")
        made.center()
        panel = made
        made.makeKeyAndOrderFront(nil)
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

    /// Jumps to one of the five sizes — ⌘1 through ⌘5.
    func select(step: Int) {
        apply(step: step)
    }

    /// One size step up or down — ⌘ + / − land here.
    func step(by delta: Int) {
        apply(step: stepIndex + delta)
    }

    /// The one place size changes: text scale and window frame together,
    /// top-left corner held (the keys-panel ruling — one sizing authority).
    ///
    /// Never called from a delegate or layout pass.
    private func apply(step: Int) {
        guard let panel else { return }
        let clamped = min(max(step, 0), Self.steps.count - 1)
        guard clamped != stepIndex || panel.frame.width != base.width * Self.steps[clamped] else {
            return
        }
        stepIndex = clamped
        let scale = Self.steps[clamped]
        if let session {
            (panel.contentView as? NSHostingView<ZFSPanelContent>)?.rootView =
                ZFSPanelContent(session: session, scale: scale)
        }
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
