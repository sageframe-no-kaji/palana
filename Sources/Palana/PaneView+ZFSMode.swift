// PaneView+ZFSMode — the pane's dataset tree (ho-10.3). Visual vocabulary
// mirrors ZFSPanelTree.ZFSDatasetRow: ink for the name, inkFaint for the
// mountpoint annotation, dimmed-but-selectable for unmounted datasets. The
// difference from the panel's row is the mutation surface: this row fires
// verbs on ITS pane's cursor through the session callback, never the
// panel's selection model — one cursor per pane, not a shared one.
//
// Extracted from PaneView.swift to keep that file under the swiftlint
// file-length budget.

import PalanaCore
import SwiftUI

extension PaneView {
    /// The dataset tree filling the pane's content area in zfs mode.
    ///
    /// Reads from the pane's own `zfsDatasets`/`zfsSelectedDataset` — no
    /// wire contact here. `refreshZFSTree` does the cache-then-discover
    /// work; it runs once on entry (`PalanaSession.enterZFSMode`) and again
    /// on the post-run signal (`OperationModel.afterZFSFinished`, ho-10.3
    /// Decision 5) — never from this view directly.
    var zfsTreeContent: some View {
        Group {
            if model.zfsDatasets.isEmpty {
                quietLine("no topology cached — reprobe the host to populate the tree")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.zfsDatasets, id: \.name) { dataset in
                            ZFSPaneDatasetRow(
                                dataset: dataset,
                                depth: zfsDatasetDepth(dataset),
                                isSelected: model.zfsSelectedDataset == dataset.name,
                                onSelect: { model.zfsSelectedDataset = dataset.name },
                                verbs: zfsVerbs,
                                onVerb: { verb in
                                    model.zfsSelectedDataset = dataset.name
                                    onZFSVerb(verb)
                                },
                                onOpenInPane: dataset.mounted && dataset.mountpoint.hasPrefix("/")
                                    ? {
                                        model.zfsSelectedDataset = dataset.name
                                        model.zfsEnterSelected()
                                    } : nil
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// The depth of a dataset in the namespace.
    ///
    /// The count of "/" separators beyond the pool name, mirroring
    /// `ZFSDatasetTree`'s rule.
    func zfsDatasetDepth(_ dataset: ZFSDataset) -> Int {
        max(0, dataset.name.components(separatedBy: "/").count - 1)
    }
}

/// One row in the pane's dataset tree.
///
/// Unlike `ZFSPanelTree.ZFSDatasetRow` (which fires through the shared
/// panel selection), this row's context menu and click both write to the
/// pane's own `zfsSelectedDataset` — the one cursor this pane owns.
private struct ZFSPaneDatasetRow: View {
    let dataset: ZFSDataset
    let depth: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let verbs: [WorkbenchVerb]
    let onVerb: (WorkbenchVerb) -> Void
    /// Non-nil only for mounted datasets — "open here" in the context menu.
    let onOpenInPane: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(leafName)
                    .font(Theme.font(12))
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
        // Double-click descends into a mounted dataset — the same move as
        // keyboard Enter (the hands round clicked a mounted row and read
        // the silence as breakage; files double-click descends, so must
        // this). Unmounted rows: quiet no-op, matching Enter.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onOpenInPane?() }
        )
        .opacity(mounted ? 1.0 : 0.6)
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(verbs, id: \.id) { verb in
                Button(verb.label) {
                    onVerb(verb)
                }
            }
            if let onOpenInPane {
                Divider()
                Button("open here") { onOpenInPane() }
            }
        }
    }

    @ViewBuilder private var mountpointAnnotation: some View {
        if dataset.mountpoint.isEmpty || dataset.mountpoint == "none" {
            if !mounted {
                Text("· unmounted")
                    .font(Theme.font(10))
                    .foregroundStyle(Theme.inkFaint)
            }
        } else if dataset.mountpoint == "legacy" {
            Text("legacy")
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        } else if mounted {
            Text(dataset.mountpoint)
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        } else {
            Text("\(dataset.mountpoint) · unmounted")
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(
                isSelected
                    ? Theme.plugin.opacity(0.14)
                    : (hovering ? Theme.plugin.opacity(0.06) : Color.clear)
            )
            .padding(.horizontal, -4)
    }

    private var leafName: String { dataset.name.components(separatedBy: "/").last ?? dataset.name }

    private var mounted: Bool { dataset.mounted && dataset.mountpoint.hasPrefix("/") }
}
