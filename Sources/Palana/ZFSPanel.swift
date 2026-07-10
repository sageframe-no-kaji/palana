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

    /// Shows the panel, rebuilding only when it is not yet up.
    ///
    /// If the panel is already visible, brings it to front without
    /// rebuilding the hosting view.
    func show(session: PalanaSession) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let made = ZFSFloatingPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 300, height: 480)),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
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
        made.minSize = CGSize(width: 240, height: 260)
        made.contentView = NSHostingView(rootView: ZFSPanelContent(session: session))
        made.delegate = self
        made.center()
        made.setFrameAutosaveName("palana-zfs-frame")
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
            ZFSPanelView(session: session)
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ZFSPanelView

/// The scrollable verb list and target line — the panel's working area.
///
/// Resolves the focused dataset from cached Field facts whenever the focused
/// pane's host or path changes. No wire contact — the `task` calls the
/// actor's synchronous cache read via `await` (actor-hop only, no I/O).
struct ZFSPanelView: View {
    /// The root session — verbs, availability, focused pane, engine.
    let session: PalanaSession

    /// Cached availabilities for the focused host — refreshed when the host changes.
    @State private var availabilities: [String: VerbAvailability] = [:]

    /// The dataset the focused pane stands in — nil until the first cache read.
    ///
    /// When non-nil the target line shows "operates on <dataset> · <host>";
    /// when nil it shows the guidance sentence.
    @State private var targetDataset: String?

    // MARK: - Derived state

    private var focusedHost: String? { session.focusedPane.state.host }
    private var focusedPath: String { session.focusedPane.state.path }
    private var terminalBusy: Bool { session.operation.terminalBusy }

    /// The task identity — recompute whenever host or path changes.
    private var paneKey: String { "\(focusedHost ?? "")|\(focusedPath)" }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            targetLine
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
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
        // Refresh the target dataset when the focused pane moves.
        .task(id: paneKey) {
            await refreshTargetDataset()
        }
    }

    // MARK: - Target line

    /// Shows which dataset the verbs will operate on, or guidance when none.
    @ViewBuilder private var targetLine: some View {
        if let dataset = targetDataset, let host = focusedHost {
            Text("operates on \(dataset) · \(host)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        } else {
            Text("point a pane inside a dataset — verbs aim where you stand")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    // MARK: - Verb rows

    /// One full-width verb row — label left, key hint right.
    private func verbRow(_ verb: WorkbenchVerb) -> some View {
        let avail = resolvedAvailability(for: verb)
        let enabled = !terminalBusy && avail == .available
        return ZFSVerbRow(
            label: verb.label,
            keyHint: verb.keyHint,
            enabled: enabled,
            help: helpText(for: verb, avail: avail)
        ) {
            ZFSPanelController.shared.close()
            session.runWorkbenchVerb(verb)
        }
    }

    private func resolvedAvailability(for verb: WorkbenchVerb) -> VerbAvailability {
        // Local honesty: zfs verbs are not applicable on this Mac. The .zfs
        // evaluation returns "not yet probed" for nil facts, but this Mac is
        // never probed — "not yet probed" misreads the truth.
        guard focusedHost != PalanaCore.localHostName else {
            return .unmet("no zfs on this Mac")
        }
        return availabilities[verb.id] ?? .available
    }

    private func helpText(for verb: WorkbenchVerb, avail: VerbAvailability) -> String {
        guard !terminalBusy else { return "\(verb.label) — terminal busy" }
        if case .unmet(let reason) = avail { return reason }
        return "\(verb.label) on \(focusedHost ?? "—")"
    }

    // MARK: - Footer

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Text("esc closes · letter fires verb · Z opens")
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

    /// Resolves which dataset the focused pane stands in — cache read, no wire.
    private func refreshTargetDataset() async {
        guard let host = focusedHost, host != PalanaCore.localHostName else {
            targetDataset = nil
            return
        }
        let path = focusedPath
        let dataset = await session.sessionEngine.field.datasetContaining(path: path, on: host)
        targetDataset = dataset?.name
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
