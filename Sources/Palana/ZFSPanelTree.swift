// ZFSPanelTree — the dataset tree inside the ZFS panel. The selection model
// lives here (ZFSPanelSelection, @Observable), owned by ZFSPanelController
// so the key handler can move the selection without touching the SwiftUI
// hosting view. The tree view (ZFSDatasetTree) observes it and re-renders
// only the changed row.
//
// Visual vocabulary mirrors FieldOverlay.datasetRow exactly — ink/inkFaint,
// 12pt, depth-indented — scaled to the panel's narrower column.
// Unmounted/legacy/none datasets render dimmed but SELECTABLE — reaching
// them is the point.

import PalanaCore
import SwiftUI

// MARK: - ZFSPanelSelection

/// The panel's selection state — one dataset name and its full record,
/// or nil when the topology is absent.
///
/// @Observable so SwiftUI sees granular changes: only the rows that gained
/// or lost the highlight re-render. The controller owns the single instance;
/// the view reads it via the controller reference.
///
/// `selectedFullDataset` is always kept in sync with `selectedDataset` so
/// callers that need mounted state or the mountpoint path do not have to
/// re-search the topology list.
@MainActor
@Observable
final class ZFSPanelSelection {
    /// The currently selected dataset name — nil before facts arrive.
    private(set) var selectedDataset: String?

    /// The full record for the selected dataset — nil when nothing is selected.
    ///
    /// Kept in sync with `selectedDataset`; both update together in every
    /// `select(dataset:in:)` call.
    private(set) var selectedFullDataset: ZFSDataset?

    /// Replaces the selection by name only — used by the key handler which
    /// only has the sorted names list.
    ///
    /// Also accepts an optional `datasets` list to resolve the full record;
    /// pass nil when unavailable and the full-dataset field clears.
    func select(dataset: String?) {
        selectedDataset = dataset
        selectedFullDataset = nil
    }

    /// Replaces the selection with a full dataset record.
    ///
    /// Preferred call site — both fields update atomically.
    func select(fullDataset: ZFSDataset?) {
        selectedDataset = fullDataset?.name
        selectedFullDataset = fullDataset
    }

    /// Resolves the full record after a name-only selection.
    ///
    /// Called by the tree after `moveUp`/`moveDown` to restore the full
    /// record from the sorted list.
    func resolveFullDataset(in datasets: [ZFSDataset]) {
        guard let name = selectedDataset else {
            selectedFullDataset = nil
            return
        }
        selectedFullDataset = datasets.first { $0.name == name }
    }

    /// Moves the selection one step toward the start of the ordered list.
    ///
    /// Wraps from the top to the bottom. No-op when the list is empty.
    func moveUp(in datasets: [ZFSDataset]) {
        guard !datasets.isEmpty else { return }
        let names = datasets.map(\.name)
        guard let current = selectedDataset, let idx = names.firstIndex(of: current) else {
            selectedDataset = names.last
            selectedFullDataset = datasets.last
            return
        }
        let newIdx = (idx + names.count - 1) % names.count
        selectedDataset = names[newIdx]
        selectedFullDataset = datasets[newIdx]
    }

    /// Moves the selection one step toward the end of the ordered list.
    ///
    /// Wraps from the bottom to the top. No-op when the list is empty.
    func moveDown(in datasets: [ZFSDataset]) {
        guard !datasets.isEmpty else { return }
        let names = datasets.map(\.name)
        guard let current = selectedDataset, let idx = names.firstIndex(of: current) else {
            selectedDataset = names.first
            selectedFullDataset = datasets.first
            return
        }
        let newIdx = (idx + 1) % names.count
        selectedDataset = names[newIdx]
        selectedFullDataset = datasets[newIdx]
    }
}

// MARK: - ZFSDatasetTree

/// The scrollable dataset tree embedded between the header and the verb rows.
///
/// Reads facts from the cache asynchronously (actor-hop, no wire). Keyed on
/// a composite of pane identity and operation phase so a `.finished`
/// transition triggers a re-read and the tree reflects the new topology.
struct ZFSDatasetTree: View {
    /// The root session — for cache access and pane pointing.
    let session: PalanaSession
    /// The selection model owned by the controller — shared with the key handler.
    let selection: ZFSPanelSelection

    /// The focused host — nil for the local Mac or when no pane points anywhere.
    private var focusedHost: String? { session.focusedPane.state.host }
    /// The focused pane's current path.
    private var focusedPath: String { session.focusedPane.state.path }
    /// Combined key: host, path, and operation phase — so `.finished` re-reads.
    private var treeKey: String {
        "\(focusedHost ?? "")|\(focusedPath)|\(session.operation.phase)"
    }

    /// The sorted dataset list — populated from the cache, empty until read.
    @State private var datasets: [ZFSDataset] = []

    var body: some View {
        Group {
            if datasets.isEmpty {
                Text("no topology cached — reprobe the host to populate the tree")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(datasets, id: \.name) { dataset in
                            ZFSDatasetRow(
                                dataset: dataset,
                                depth: depth(of: dataset),
                                isSelected: selection.selectedDataset == dataset.name,
                                session: session,
                                verbsForDataset: verbsForDataset
                            ) {
                                selection.select(fullDataset: dataset)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 180)
            }
        }
        .task(id: treeKey) {
            await refreshTree()
        }
    }

    // MARK: - Private helpers

    /// Returns the depth of a dataset in the namespace.
    ///
    /// Depth is the count of "/" separators beyond the pool name:
    /// `tank` → 0, `tank/data` → 1, `tank/data/photos` → 2.
    private func depth(of dataset: ZFSDataset) -> Int {
        max(0, dataset.name.components(separatedBy: "/").count - 1)
    }

    /// True when the current selection is absent or no longer present in the list.
    ///
    /// Used to decide whether `refreshTree` should reassign the selection.
    private func selectionIsStale(in sorted: [ZFSDataset]) -> Bool {
        guard let current = selection.selectedDataset else { return true }
        return !sorted.contains { $0.name == current }
    }

    /// Fires a verb on a given dataset — selects the row first, then routes
    /// through the same explicit-dataset path the letter keys use.
    ///
    /// Used by the context menu to ensure a right-click on a non-selected
    /// row targets that row, not the previously selected one.
    private func verbsForDataset(_ dataset: ZFSDataset) -> [WorkbenchVerb] {
        session.zfsTool.verbs
    }

    /// Reads facts from the cache and rebuilds the sorted dataset list.
    ///
    /// No-op for the local Mac (no ZFS there) and when no host is focused.
    /// Selects the dataset containing the focused path on first load, then
    /// falls back to the first root dataset if none matches.
    private func refreshTree() async {
        guard let host = focusedHost, host != PalanaCore.localHostName else {
            datasets = []
            selection.select(fullDataset: nil)
            return
        }
        let topology = await session.sessionEngine.field.facts(for: host)?.zfsTopology?.value ?? []
        let sorted = topology.sorted { $0.name < $1.name }
        datasets = sorted

        // Pre-select, cursor first: when the pane's cursor sits on a
        // directory that IS a mounted dataset's mountpoint, that dataset is
        // what the operator is aiming at — not the one merely containing the
        // directory they stand in (the two-cursor failure, fifth block).
        // Falls back to the containing dataset, then the first root.
        guard selectionIsStale(in: sorted) else { return }
        let path = focusedPath
        let cursorAimed = session.focusedPane.cursorEntry.flatMap { entry in
            ZFSTopology.wholeDatasetSelection(
                entries: [entry], sourceDirectory: path, datasets: topology)
        }
        if let aimed = cursorAimed {
            selection.select(fullDataset: aimed)
        } else if let containing = ZFSTopology.datasetContaining(path, in: topology) {
            selection.select(fullDataset: containing)
        } else {
            selection.select(fullDataset: sorted.first)
        }
    }
}

// MARK: - ZFSDatasetRow

/// One row in the dataset tree.
///
/// Mirrors FieldOverlay.datasetRow visual vocabulary: ink for the name,
/// inkFaint for the mountpoint annotation, dimmed at 0.6 opacity for
/// unmounted/legacy/none datasets. Dimmed rows remain selectable —
/// reaching unmounted datasets is the point of this tree.
///
/// A context menu duplicates the eight ZFS verbs (on THIS row's dataset,
/// whether or not it is currently selected), a divider, then
/// "open in left pane" / "open in right pane" (mounted datasets only).
private struct ZFSDatasetRow: View {
    let dataset: ZFSDataset
    let depth: Int
    let isSelected: Bool
    /// The root session — used by the context menu to fire verbs and point panes.
    let session: PalanaSession
    /// Returns the verb list — passed from the tree so the row need not
    /// hold a reference to the ZFS tool directly.
    let verbsForDataset: (ZFSDataset) -> [WorkbenchVerb]
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(leafName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                mountpointAnnotation
                unmountedSuffix
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.leading, CGFloat(depth) * 12)
            .frame(minHeight: 26)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(mounted ? 1.0 : 0.6)
        .onHover { hovering = $0 }
        .contextMenu { contextMenuContent }
    }

    // MARK: - Context menu

    /// The context menu: eight ZFS verbs on this dataset, then pane-open items.
    ///
    /// Selects this row before firing so the verb rows and the context menu
    /// always agree on which dataset is targeted. Verb availability mirrors
    /// the verb-row logic: disabled when the terminal is busy, when the verb
    /// is a mutation and the host has no ZFS, or when this is the local Mac.
    @ViewBuilder private var contextMenuContent: some View {
        let host = session.focusedPane.state.host
        let localMac = host == nil || host == PalanaCore.localHostName
        let busy = session.operation.terminalBusy
        ForEach(verbsForDataset(dataset), id: \.id) { verb in
            let isMutation = verb.kind == .mutation
            let disabled = busy || (isMutation && localMac)
            Button(verb.label) {
                // Select this row first — the verb targets THIS dataset.
                ZFSPanelController.shared.selection.select(fullDataset: dataset)
                guard let targetHost = host, !localMac else { return }
                session.runWorkbenchMutation(verb, on: targetHost, dataset: dataset.name)
                NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            }
            .disabled(disabled)
        }
        Divider()
        Button("open in left pane") {
            ZFSPanelController.shared.selection.select(fullDataset: dataset)
            session.left.point(host: host ?? "", path: dataset.mountpoint)
        }
        .disabled(!mounted || host == nil)
        Button("open in right pane") {
            ZFSPanelController.shared.selection.select(fullDataset: dataset)
            session.right.point(host: host ?? "", path: dataset.mountpoint)
        }
        .disabled(!mounted || host == nil)
    }

    // MARK: - Sub-views

    @ViewBuilder private var mountpointAnnotation: some View {
        if dataset.mountpoint.isEmpty || dataset.mountpoint == "none" {
            // No annotation for bare "none" — the "· unmounted" suffix covers it.
            EmptyView()
        } else if dataset.mountpoint == "legacy" {
            Text("legacy")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        } else if mounted {
            // Effectively mounted — show the path.
            Text(dataset.mountpoint)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        } else {
            // Has a path-style mountpoint but is not mounted — show path + unmounted tag.
            Text("\(dataset.mountpoint) · unmounted")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        }
    }

    /// Explicit unmounted annotation for datasets with no path-style mountpoint.
    ///
    /// Datasets where `mounted` is false and the mountpoint is "none" or empty
    /// receive a standalone "· unmounted" label so the dim-alone state is never
    /// the only signal.
    @ViewBuilder private var unmountedSuffix: some View {
        if !mounted, dataset.mountpoint == "none" || dataset.mountpoint.isEmpty {
            Text("· unmounted")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isSelected ? Theme.accent.opacity(0.10) : (hovering ? Theme.accent.opacity(0.05) : Color.clear))
            .padding(.horizontal, -4)
    }

    // MARK: - Helpers

    /// The last path component of the dataset name — avoids repeating the
    /// full ancestry in the indented tree.
    private var leafName: String { dataset.name.components(separatedBy: "/").last ?? dataset.name }

    /// Whether the dataset is effectively mounted with a real path.
    private var mounted: Bool { dataset.mounted && dataset.mountpoint.hasPrefix("/") }
}
