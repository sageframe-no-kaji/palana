// The floating host map panel — AppKit-owned, borderless, on the KeysPanel
// lineage. The panel shows every host in the config with its remembered facts,
// per-host probe buttons, and the full mount table. Esc closes by window
// identity in the key monitor; F and the server.rack glyph toggle from the
// session. The panel floats independently — field, help, and settings never
// close it. Same law as KeysPanel: content ground fills the frame to its
// rounded edge so no band can appear between card and window.

import AppKit
import PalanaCore
import SwiftUI

// MARK: - HostMapModel

/// The host map panel's view model.
///
/// Thin `@Observable` wrapper over `Field.allFacts()` — holds the rendered
/// map and in-flight probe state, mirrors the `FieldViewModel` pattern.
/// The session owns one instance; the panel reads it.
@MainActor
@Observable
final class HostMapModel {
    /// The display model — nil until `refresh(hosts:)` first runs.
    private(set) var hostMap: HostMap?
    /// Hosts with a probe in flight — the row renders "probing…".
    private(set) var probing: Set<String> = []
    /// Error detail per host from a thrown probe — cleared on the next probe.
    private(set) var probeErrors: [String: String] = [:]

    private let engine: Engine

    /// A view model over the session's engine.
    init(engine: Engine) {
        self.engine = engine
    }

    /// Reads `allFacts()` and rebuilds the map — a cache read, no wire.
    ///
    /// Local first, then config order. Calling while visible refreshes
    /// from the current cache state. Fold state is preserved across calls
    /// via `update(facts:)`; a fresh `HostMap` is built only on first call.
    func refresh(hosts: [String]) {
        Task {
            let localHost = Engine.localHost
            var ordered = [localHost]
            ordered += hosts.filter { $0 != localHost }
            let facts = await engine.field.allFacts()
            if hostMap != nil {
                hostMap?.update(facts: facts)
            } else {
                hostMap = HostMap(hosts: ordered, facts: facts, localHost: localHost)
            }
        }
    }

    /// Toggles the collapsed state of a mount row identified by host alias and target path.
    ///
    /// Forwarded to `HostMap.toggleMount(host:target:)` — no-op when the row has
    /// no children or is not found.
    func toggleMount(host: String, target: String) {
        hostMap?.toggleMount(host: host, target: target)
    }

    /// Probes a remote host — no-op for local or in-flight hosts.
    ///
    /// The row shows "probing…" while the probe runs, then the fresh
    /// verdict and a young age. Mirrors `FieldViewModel.reprobe`.
    func probe(_ host: String) {
        guard host != Engine.localHost else { return }
        guard !probing.contains(host) else { return }
        probing.insert(host)
        probeErrors.removeValue(forKey: host)
        Task {
            do {
                try await engine.field.discover(host)
            } catch {
                probeErrors[host] = Self.describe(error)
            }
            probing.remove(host)
            let facts = await engine.field.allFacts()
            // update(facts:) preserves fold state across the post-probe rebuild.
            hostMap?.update(facts: facts)
        }
    }

    private static func describe(_ error: any Error) -> String {
        if error is ProbeParseError {
            return "answered, but the probe came back unreadable"
        }
        return "\(error)"
    }
}

// MARK: - HostMapPanelController

/// Owns the one floating host map panel.
@MainActor
final class HostMapPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = HostMapPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-hostmap-window"

    private var panel: NSPanel?

    /// Shows the panel, refreshing the model first.
    func show(model: HostMapModel, hosts: [String]) {
        model.refresh(hosts: hosts)
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let made = HostMapPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 520, height: 480)),
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
        made.minSize = CGSize(width: 360, height: 260)
        made.contentView = NSHostingView(rootView: HostMapContent(model: model))
        made.delegate = self
        made.center()
        made.setFrameAutosaveName("palana-hostmap-frame")
        panel = made
        made.makeKeyAndOrderFront(nil)
    }

    /// Toggles the panel — closes when up, opens when not.
    func toggle(model: HostMapModel, hosts: [String]) {
        if panel != nil {
            close()
        } else {
            show(model: model, hosts: hosts)
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
private final class HostMapPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - HostMapContent

/// The panel's face — ground fills the frame to the rounded edge.
struct HostMapContent: View {
    /// The view model driving this panel.
    let model: HostMapModel

    var body: some View {
        VStack(spacing: 0) {
            scrollArea
            panelFooter
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var scrollArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let map = model.hostMap {
                    ForEach(map.sections, id: \.alias) { section in
                        HostSectionView(
                            section: section,
                            probing: model.probing,
                            probeErrors: model.probeErrors,
                            onToggleMount: { model.toggleMount(host: section.alias, target: $0) },
                            onProbe: { model.probe($0) }
                        )
                        Divider().opacity(0.25)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Text("esc closes · probe refreshes a host · ◆ dataset · ◇ mount")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - HostSectionView

/// One host's section in the host map panel.
struct HostSectionView: View {
    /// The host's display data.
    let section: HostMap.HostSection
    /// Hosts with a probe in flight.
    let probing: Set<String>
    /// Error detail per host from a thrown probe.
    let probeErrors: [String: String]
    /// Called with the mount target when the operator taps a mount chevron.
    let onToggleMount: (String) -> Void
    /// Called when the operator taps the probe button.
    let onProbe: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            mountRows
            mountFooter
        }
        .padding(.vertical, 8)
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.alias)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.ink)
            verdict
            Spacer()
            tokens
            probeButton
        }
    }

    @ViewBuilder private var verdict: some View {
        if section.isLocal {
            Text("this machine")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        } else if probing.contains(section.alias) {
            Text("probing…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        } else if let refused = probeErrors[section.alias] {
            Text(refused)
                .font(.system(size: 12))
                .foregroundStyle(Theme.alarm)
        } else if !section.visited {
            Text("never visited")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        } else if let reachability = section.reachability {
            reachabilityVerdict(reachability)
        }
    }

    @ViewBuilder
    private func reachabilityVerdict(_ reachability: Reachability) -> some View {
        switch reachability {
        case .reachable:
            if let date = section.rememberedAt {
                Text("reachable · \(FieldAge.describe(date, now: Date()))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                Text("reachable")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
        case .unreachable(let detail):
            Text("unreachable · \(FieldOverlay.plainRefusal(detail))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.alarm)
        }
    }

    @ViewBuilder private var tokens: some View {
        if !section.isLocal {
            HStack(spacing: 4) {
                if let flavor = section.flavor {
                    Text(flavor.rawValue).foregroundStyle(Theme.inkFaint)
                }
                if section.hasZFS { Text("zfs").foregroundStyle(Theme.inkFaint) }
                if section.hasRsync { Text("rsync").foregroundStyle(Theme.inkFaint) }
            }
            .font(.system(size: 11))
        }
    }

    @ViewBuilder private var probeButton: some View {
        if !section.isLocal {
            if probing.contains(section.alias) {
                Text("probing…")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                Button("probe") { onProbe(section.alias) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    @ViewBuilder private var mountRows: some View {
        if !section.mounts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                // Index identity, not target — stacked mounts share a target
                // (two rows on /proc/sys/fs/binfmt_misc in the pool corpus).
                ForEach(Array(section.mounts.enumerated()), id: \.offset) { _, mount in
                    MountRowView(row: mount) { onToggleMount(mount.target) }
                }
            }
            .padding(.leading, 16)
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var mountFooter: some View {
        if !section.isLocal, section.mountsRememberedAt == nil {
            Text("not yet asked — probe gathers the ground")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
        if section.systemMountCount > 0 {
            Text("\(section.systemMountCount) system mounts not shown")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
        if let age = section.mountsRememberedAt {
            Text("ground as of \(FieldAge.describe(age, now: Date()))")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
    }
}

// MARK: - MountRowView

/// One mount row in a host section.
struct MountRowView: View {
    /// The mount's display data.
    let row: HostMap.MountRow
    /// Called when the operator taps the disclosure chevron.
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            mountChevron
            diamond
            Text(row.target)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(row.fstype)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
            Text(row.source)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.readOnly {
                Text("ro")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
        // Depth-based indent: each level adds 14pt beyond the section's base indent.
        .padding(.leading, CGFloat(row.depth) * 14)
    }

    /// Disclosure chevron for rows with children — accent coloured, rotates 90° when expanded.
    ///
    /// Childless rows carry an invisible placeholder so the ◆/◇ diamond and
    /// target text stay in one column across all depths.
    @ViewBuilder private var mountChevron: some View {
        if row.childCount > 0 {
            Text(Image(systemName: "chevron.right"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(row.expanded ? 90 : 0))
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }
        } else {
            Text("").frame(width: 18)  // leaf — placeholder keeps diamond in column
        }
    }

    private var diamond: some View {
        Group {
            if row.isDatasetMountpoint {
                Text("◆").foregroundStyle(Theme.accent)
            } else {
                Text("◇").foregroundStyle(Theme.inkFaint)
            }
        }
        .font(.system(size: 11))
    }
}
