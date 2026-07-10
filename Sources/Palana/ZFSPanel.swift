// The floating ZFS panel — the first Workbench plugin panel. AppKit-owned,
// borderless, on the FavoritesPanel lineage: NSPanel + SwiftUI content view,
// shared singleton controller, toggle/close API, key handling by window
// identity. The strip keeps only a launcher chip; this panel carries the
// eight verb rows that were invisible when the plan panel was short.
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
        let hosting = NSHostingView(rootView: ZFSPanelContent(session: session))
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

    /// The one place size changes: window frame from the stepped scale,
    /// top-left corner held.
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

    var body: some View {
        VStack(spacing: 0) {
            OverlayHeader(title: "zfs") { ZFSPanelController.shared.close() }
            ZFSPanelView(session: session, selection: ZFSPanelController.shared.selection)
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ZFSPanelView

/// The dataset tree, target line, and verb rows — the panel's working area.
///
/// The dataset tree (``ZFSDatasetTree``) sits between the header and the verb
/// rows. Verbs now fire on the SELECTED dataset from the tree rather than on
/// the dataset containing the focused pane's path — this is the change that
/// makes unmounted datasets reachable for the first time.
///
/// No wire contact — all cache reads are actor-hops to `field.facts(for:)`.
struct ZFSPanelView: View {
    /// The root session — verbs, availability, focused pane, engine.
    let session: PalanaSession
    /// The selection model — shared with the controller's key handler.
    let selection: ZFSPanelSelection

    /// Cached availabilities for the focused host — refreshed when the host changes.
    @State private var availabilities: [String: VerbAvailability] = [:]

    // MARK: - Derived state

    private var focusedHost: String? { session.focusedPane.state.host }
    private var terminalBusy: Bool { session.operation.terminalBusy }
    /// True when the tree has no selection — disables text (mutation) verbs.
    private var noSelection: Bool { selection.selectedDataset == nil }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            targetLine
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
            Divider().opacity(0.35)
            ZFSDatasetTree(session: session, selection: selection)
                .padding(.top, 4)
            Divider().opacity(0.35)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.zfsTool.verbs, id: \.id) { verb in
                        verbRow(verb)
                        Divider().opacity(0.18)
                    }
                }
                .padding(.vertical, 4)
            }
            panelFooter
        }
        // Refresh availabilities when the focused host changes.
        .task(id: focusedHost ?? "") {
            await refreshAvailabilities()
        }
    }

    // MARK: - Target line

    /// Shows the selected dataset and host, or guidance when none is selected.
    @ViewBuilder private var targetLine: some View {
        if let dataset = selection.selectedDataset, let host = focusedHost {
            Text("operates on \(dataset) · \(host)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        } else {
            Text("point a pane at a host — select a dataset in the tree")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    // MARK: - Verb rows

    /// One full-width verb row — label left, key hint right.
    ///
    /// Verbs fire on the selected dataset from the tree. Mutation verbs are
    /// additionally disabled when there is no tree selection (no-topology host).
    private func verbRow(_ verb: WorkbenchVerb) -> some View {
        let avail = resolvedAvailability(for: verb)
        let enabled = !terminalBusy && avail == .available && !(verb.kind == .mutation && noSelection)
        return ZFSVerbRow(
            label: verb.label,
            keyHint: verb.keyHint,
            enabled: enabled,
            help: helpText(for: verb, avail: avail)
        ) {
            guard let host = focusedHost, let dataset = selection.selectedDataset else { return }
            ZFSPanelController.shared.close()
            session.runWorkbenchMutation(verb, on: host, dataset: dataset)
        }
    }

    private func resolvedAvailability(for verb: WorkbenchVerb) -> VerbAvailability {
        // Local honesty: zfs verbs are not applicable on this Mac.
        guard focusedHost != PalanaCore.localHostName else {
            return .unmet("no zfs on this Mac")
        }
        return availabilities[verb.id] ?? .available
    }

    private func helpText(for verb: WorkbenchVerb, avail: VerbAvailability) -> String {
        guard !terminalBusy else { return "\(verb.label) — terminal busy" }
        if case .unmet(let reason) = avail { return reason }
        if verb.kind == .mutation, noSelection { return "\(verb.label) — no dataset selected" }
        return "\(verb.label) on \(focusedHost ?? "—")"
    }

    // MARK: - Footer

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Text(
                "↑↓ choose a dataset · esc closes · letter fires verb · Z opens · ⌘1–⌘5 pick a size · ⌘+/− step"
            )
            .font(.system(size: 10))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Async helpers

    /// Refreshes verb availabilities from the Workbench cache.
    private func refreshAvailabilities() async {
        guard let host = focusedHost else { return }
        for verb in session.zfsTool.verbs {
            availabilities[verb.id] = await session.workbench.availability(of: verb, on: host)
        }
    }
}

// MARK: - ZFSVerbRow

/// One full-width verb row in the ZFS panel.
///
/// Mirrors `StripChip`'s shape scaled up: label left in 12pt semibold,
/// key hint right in accent, hover wash on the whole row. Disabled rows
/// dim and show a tooltip with the unmet reason.
private struct ZFSVerbRow: View {
    let label: String
    let keyHint: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint)
                Spacer()
                Text(keyHint)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 34)
            .background(
                hovering && enabled
                    ? Theme.accent.opacity(0.10)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(help)
        .disabled(!enabled)
    }
}
