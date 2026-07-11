// PaneModel+ZFSMode — the pane's zfs mode (ho-10.3). A pane in zfs mode
// renders dataset rows instead of files: the tree machinery promoted from
// ZFSPanelTree, one cursor per pane, the file state untouched underneath.
//
// PaneState/PaneIntent (core) never learn about this — `state.host` and
// `state.path` are the file cursor, and zfs mode never writes them except
// on the one deliberate exit-into-mountpoint move (Enter on a mounted
// dataset), which is an ordinary `point()` call like any navigation. Every
// other transition (enter, walk, exit via Esc) leaves `state` untouched, so
// "preserved and restored" falls out of simply never touching it.

import PalanaCore

extension PaneModel {
    /// What a pane renders: its files, or a host's dataset tree.
    enum Mode: Equatable {
        /// The ordinary file listing.
        case files
        /// The dataset tree — verbs target `zfsSelectedDataset`.
        case zfs
    }

    // MARK: - Entry and exit

    /// Enters zfs mode on this pane.
    ///
    /// No-op without a host — zfs mode has nothing to show. The file
    /// cursor and path are untouched; only `paneMode` and the tree state
    /// change. Call `refreshZFSTree` afterward to populate the tree.
    func enterZFSMode() {
        guard state.host != nil else { return }
        paneMode = .zfs
    }

    /// Leaves zfs mode, restoring the file view exactly as it stood.
    ///
    /// `state` was never touched while in zfs mode (aside from a
    /// deliberate Enter-into-mountpoint, which calls `point()` and exits
    /// through `exitZFSModeIntoMountpoint` instead), so there is nothing
    /// to restore — flipping the mode flag is the whole operation.
    func exitZFSMode() {
        paneMode = .files
        zfsDatasets = []
        zfsSelectedDataset = nil
    }

    // MARK: - Intent routing

    /// Redirects the file-cursor intents to the tree walk while in zfs mode.
    ///
    /// Everything else that has no dataset-row meaning is a quiet no-op.
    /// Called from `apply(_:)`.
    func applyZFSModeIntent(_ intent: PaneIntent) {
        switch intent {
        case .cursorDown: zfsCursorDown()
        case .cursorUp: zfsCursorUp()
        case .descendOrOpen: zfsEnterSelected()
        default: break  // sort, selection, ascend/descend: no meaning on a dataset row
        }
    }

    // MARK: - Tree walk

    /// Moves the dataset selection up one row, wrapping at the top.
    func zfsCursorUp() {
        guard !zfsDatasets.isEmpty else { return }
        let names = zfsDatasets.map(\.name)
        guard let current = zfsSelectedDataset, let idx = names.firstIndex(of: current) else {
            zfsSelectedDataset = names.last
            return
        }
        zfsSelectedDataset = names[(idx + names.count - 1) % names.count]
    }

    /// Moves the dataset selection down one row, wrapping at the bottom.
    func zfsCursorDown() {
        guard !zfsDatasets.isEmpty else { return }
        let names = zfsDatasets.map(\.name)
        guard let current = zfsSelectedDataset, let idx = names.firstIndex(of: current) else {
            zfsSelectedDataset = names.first
            return
        }
        zfsSelectedDataset = names[(idx + 1) % names.count]
    }

    /// The full record for the selected dataset, if any.
    var zfsSelectedFullDataset: ZFSDataset? {
        guard let name = zfsSelectedDataset else { return nil }
        return zfsDatasets.first { $0.name == name }
    }

    /// Enter on the selected dataset: exits zfs mode into its mountpoint
    /// when it is mounted; silent no-op otherwise (matching the panel's
    /// `⇧⌘←/→` posture — an unmounted dataset has nowhere to point).
    func zfsEnterSelected() {
        guard let dataset = zfsSelectedFullDataset,
            dataset.mounted, dataset.mountpoint.hasPrefix("/"),
            let host = state.host
        else { return }
        exitZFSMode()
        point(host: host, path: dataset.mountpoint)
    }

    // MARK: - Refresh

    /// Rebuilds the dataset list from the Field: cache first, then one
    /// wire discovery, then a re-read — the same two-pass shape
    /// `ZFSDatasetTree.refreshTree` uses, so a dataset mounted or created
    /// since the last probe appears without an extra keypress.
    ///
    /// No-op for the local Mac or an unpointed pane. Pre-selects the
    /// dataset the pane's path stands in when the current selection is
    /// stale or absent — cursor-aimed first, then containing, then the
    /// first root.
    func refreshZFSTree(engine: Engine) async {
        guard let host = state.host, !engine.isLocal(host) else {
            zfsDatasets = []
            zfsSelectedDataset = nil
            return
        }
        await readZFSCache(host: host, engine: engine)
        _ = try? await engine.field.discover(host)
        await readZFSCache(host: host, engine: engine)
    }

    /// One cache read plus the pre-select rules — no wire contact.
    private func readZFSCache(host: String, engine: Engine) async {
        let topology = await engine.field.facts(for: host)?.zfsTopology?.value ?? []
        let sorted = topology.sorted { $0.name < $1.name }
        zfsDatasets = sorted
        guard zfsSelectionIsStale(in: sorted) else { return }
        let path = state.path
        let cursorAimed = cursorEntry.flatMap { entry in
            ZFSTopology.wholeDatasetSelection(
                entries: [entry], sourceDirectory: path, datasets: topology)
        }
        if let aimed = cursorAimed {
            zfsSelectedDataset = aimed.name
        } else if let containing = ZFSTopology.datasetContaining(path, in: topology) {
            zfsSelectedDataset = containing.name
        } else {
            zfsSelectedDataset = sorted.first?.name
        }
    }

    private func zfsSelectionIsStale(in sorted: [ZFSDataset]) -> Bool {
        guard let current = zfsSelectedDataset else { return true }
        return !sorted.contains { $0.name == current }
    }
}
