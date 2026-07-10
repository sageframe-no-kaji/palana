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

/// The panel's selection state — one dataset name, or nil when the topology
/// is absent.
///
/// @Observable so SwiftUI sees granular changes: only the rows that gained
/// or lost the highlight re-render. The controller owns the single instance;
/// the view reads it via the controller reference.
@MainActor
@Observable
final class ZFSPanelSelection {
    /// The currently selected dataset name — nil before facts arrive.
    private(set) var selectedDataset: String?

    /// Replaces the selection — called from tap gestures and the key handler.
    func select(dataset: String?) {
        selectedDataset = dataset
    }

    /// Moves the selection one step toward the start of the ordered list.
    ///
    /// Wraps from the top to the bottom. No-op when the list is empty.
    func moveUp(in datasets: [ZFSDataset]) {
        guard !datasets.isEmpty else { return }
        let names = datasets.map(\.name)
        guard let current = selectedDataset, let idx = names.firstIndex(of: current) else {
            selectedDataset = names.last
            return
        }
        selectedDataset = names[(idx + names.count - 1) % names.count]
    }

    /// Moves the selection one step toward the end of the ordered list.
    ///
    /// Wraps from the bottom to the top. No-op when the list is empty.
    func moveDown(in datasets: [ZFSDataset]) {
        guard !datasets.isEmpty else { return }
        let names = datasets.map(\.name)
        guard let current = selectedDataset, let idx = names.firstIndex(of: current) else {
            selectedDataset = names.first
            return
        }
        selectedDataset = names[(idx + 1) % names.count]
    }
}

// MARK: - ZFSDatasetTree

/// The scrollable dataset tree embedded between the header and the verb rows.
///
/// Reads facts from the cache asynchronously (actor-hop, no wire). Keyed on
/// a composite of pane identity and operation phase so a `.finished`
/// transition triggers a re-read and the tree reflects the new topology.
struct ZFSDatasetTree: View {
    /// The root session — for cache access.
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
                                isSelected: selection.selectedDataset == dataset.name
                            ) {
                                selection.select(dataset: dataset.name)
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

    /// Reads facts from the cache and rebuilds the sorted dataset list.
    ///
    /// No-op for the local Mac (no ZFS there) and when no host is focused.
    /// Selects the dataset containing the focused path on first load, then
    /// falls back to the first root dataset if none matches.
    private func refreshTree() async {
        guard let host = focusedHost, host != PalanaCore.localHostName else {
            datasets = []
            selection.select(dataset: nil)
            return
        }
        let topology = await session.sessionEngine.field.facts(for: host)?.zfsTopology?.value ?? []
        let sorted = topology.sorted { $0.name < $1.name }
        datasets = sorted

        // Pre-select: prefer the dataset containing the current path.
        let path = focusedPath
        if let containing = ZFSTopology.datasetContaining(path, in: topology) {
            // Only change selection when it is nil or no longer valid.
            if selectionIsStale(in: sorted) {
                selection.select(dataset: containing.name)
            }
        } else if selectionIsStale(in: sorted) {
            selection.select(dataset: sorted.first?.name)
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
private struct ZFSDatasetRow: View {
    let dataset: ZFSDataset
    let depth: Int
    let isSelected: Bool
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
    }

    // MARK: - Sub-views

    @ViewBuilder private var mountpointAnnotation: some View {
        if !dataset.mountpoint.isEmpty, dataset.mountpoint != "none" {
            Text(annotationText)
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
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

    /// The mountpoint text shown alongside the name.
    private var annotationText: String {
        switch dataset.mountpoint {
        case "legacy": "legacy"
        case "none": "none"
        default: dataset.mountpoint
        }
    }
}
