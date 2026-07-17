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

    /// Toggles the collapsed state of a ZFS pool for the given host.
    ///
    /// Forwarded to `HostMap.togglePool(host:pool:)` — no-op when the pool
    /// is not found in the host's section.
    func togglePool(host: String, pool: String) {
        hostMap?.togglePool(host: host, pool: pool)
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

    /// True while the panel is up — the surface's Esc reaches for an open
    /// glance panel even when the main window holds the keyboard.
    var isOpen: Bool { panel != nil }

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
        // Fullscreen-auxiliary keeps the panel reachable over a fullscreen main
        // window; it no longer joins all Spaces, so it stays on the desktop it
        // was summoned on instead of following across every one (his ask).
        made.collectionBehavior = [.fullScreenAuxiliary]
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
            OverlayHeader(title: "the host map") { HostMapPanelController.shared.close() }
            scrollArea
            panelFooter
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand { HostMapPanelController.shared.close() }
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
                            onTogglePool: { model.togglePool(host: section.alias, pool: $0) },
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
            legend
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    /// The footer line wearing the real marks — the legend shows the
    /// glyphs the rows carry, not stand-ins.
    private var legend: Text {
        Text("esc closes · probe refreshes a host · ")
            + Text(Image(systemName: "externaldrive.fill")).foregroundStyle(Theme.accent)
            + Text(" dataset · ")
            + Text(Image(systemName: "externaldrive"))
            + Text(" mount")
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
    /// Called with the pool name when the operator taps a pool chevron.
    let onTogglePool: (String) -> Void
    /// Called when the operator taps the probe button.
    let onProbe: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            mountLines
            mountFooter
        }
        .padding(.vertical, 8)
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.alias)
                .font(Theme.font(14, weight: .medium))
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
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkFaint)
        } else if probing.contains(section.alias) {
            Text("probing…")
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkFaint)
        } else if let refused = probeErrors[section.alias] {
            Text(refused)
                .font(Theme.font(12))
                .foregroundStyle(Theme.alarm)
        } else if !section.visited {
            Text("never visited")
                .font(Theme.font(12))
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
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                Text("reachable")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.inkFaint)
            }
        case .unreachable(let detail):
            Text("unreachable · \(FieldOverlay.plainRefusal(detail))")
                .font(Theme.font(12))
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
                if section.hasSudoNoPassword { Text("sudo").foregroundStyle(Theme.inkFaint) }
            }
            .font(Theme.font(11))
        }
    }

    @ViewBuilder private var probeButton: some View {
        if !section.isLocal {
            if probing.contains(section.alias) {
                Text("probing…")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkFaint)
            } else {
                Button("probe") { onProbe(section.alias) }
                    .buttonStyle(.plain)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    @ViewBuilder private var mountLines: some View {
        if !section.mounts.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                // Index identity, not target — stacked mounts share a target
                // (two rows on /proc/sys/fs/binfmt_misc in the pool corpus).
                ForEach(Array(section.mounts.enumerated()), id: \.offset) { _, line in
                    mountLineView(line)
                }
            }
            .padding(.leading, 16)
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func mountLineView(_ line: HostMap.MountLine) -> some View {
        switch line {
        case .pool(let poolLine):
            PoolLineView(poolLine: poolLine) { onTogglePool(poolLine.name) }
        case .mount(let mountRow):
            MountRowView(row: mountRow) { onToggleMount(mountRow.target) }
        }
    }

    @ViewBuilder private var mountFooter: some View {
        if !section.isLocal, section.mountsRememberedAt == nil {
            Text("not yet asked — probe gathers the ground")
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
        if section.systemMountCount > 0 {
            Text("\(section.systemMountCount) system mounts not shown")
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
        if let age = section.mountsRememberedAt {
            Text("ground as of \(FieldAge.describe(age, now: Date()))")
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 16)
        }
    }
}

// MARK: - PoolLineView

/// One ZFS pool header row in a host section.
///
/// Pool name at 12pt medium ink, a quiet `zfs pool` tag, the mount count,
/// and the same chevron treatment as mount rows with children.
struct PoolLineView: View {
    /// The pool's display data.
    let poolLine: HostMap.PoolLine
    /// Called when the operator taps the disclosure chevron.
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            poolChevron
            Text(poolLine.name)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text("zfs pool")
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
            Text("\(poolLine.visibleMountCount)")
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
            Spacer()
        }
    }

    /// Disclosure chevron — accent coloured, rotates 90° when expanded.
    ///
    /// A pool with no mounts carries an invisible placeholder to keep
    /// the name column aligned.
    @ViewBuilder private var poolChevron: some View {
        if poolLine.visibleMountCount > 0 {
            Text(Image(systemName: "chevron.right"))
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(poolLine.expanded ? 90 : 0))
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }
        } else {
            Text("").frame(width: 18)
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
            driveMark
            Text(row.target)
                .font(Theme.font(12, weight: .medium))
                .foregroundStyle(Theme.ink)
            Text(row.fstype)
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
            Text(row.source)
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.readOnly {
                Text("ro")
                    .font(Theme.font(10))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
        // Tree indent: 16pt per depth level beyond the section's base —
        // the same step the field card's dataset rows take.
        .padding(.leading, CGFloat(row.depth) * 16)
    }

    /// Disclosure chevron for rows with children — accent coloured, rotates 90° when expanded.
    ///
    /// Childless rows carry an invisible placeholder so the drive mark and
    /// target text stay in one column across all depths.
    @ViewBuilder private var mountChevron: some View {
        if row.childCount > 0 {
            Text(Image(systemName: "chevron.right"))
                .font(Theme.font(11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(row.expanded ? 90 : 0))
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture { onToggle() }
        } else {
            Text("").frame(width: 18)  // leaf — placeholder keeps the drive mark in column
        }
    }

    /// The drive-glyph boundary mark — filled for a dataset mountpoint,
    /// outlined for a plain mount.
    private var driveMark: some View {
        Group {
            if row.isDatasetMountpoint {
                Text(Image(systemName: "externaldrive.fill")).foregroundStyle(Theme.accent)
            } else {
                Text(Image(systemName: "externaldrive")).foregroundStyle(Theme.inkFaint)
            }
        }
        .font(Theme.font(10))
    }
}
