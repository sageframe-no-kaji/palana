// PalanaSession+ZFS — the mutation route, the ZFS panel key handler, and
// the field-less gather key handler, extracted from PalanaSession.swift
// to keep that file within the line-length budget.

import AppKit
import PalanaCore

// MARK: - ZFS panel key handling

extension PalanaSession {
    /// Routes a key event while the ZFS panel is the key window.
    ///
    /// Demoted by ho-10.3: the panel no longer mutates, so its key handler
    /// no longer matches a verb's `keyHint` — that letter now belongs to
    /// whatever the panel's tree happens to show, not a fired verb. Esc
    /// closes. ↑↓ (keyCodes 126/125) move the dataset tree selection
    /// without rebuilding the hosting view. ⇧⌘← (keyCode 123) points the
    /// left pane at the selected dataset's mountpoint; ⇧⌘→ (keyCode 124)
    /// the right pane — mounted datasets only, silent no-op otherwise.
    /// ⌘1–⌘5 jump to a size; ⌘+/= and ⌘− step — mirroring
    /// `handleKeysPanelKey` exactly. Everything else passes through.
    func handleZFSPanelKey(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let chars = event.charactersIgnoringModifiers
        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        // Esc — close the panel; pass nothing further.
        if keyCode == 53 {
            ZFSPanelController.shared.close()
            return true
        }
        // ⇧⌘← / ⇧⌘→ — point left or right pane at the selected dataset.
        if hasCommand, hasShift {
            if keyCode == 123 || keyCode == 124 {
                pointPaneAtSelectedDataset(keyCode == 123 ? left : right)
                return true
            }
        }
        // ↑ / ↓ — move tree selection (no modifiers).
        if !hasCommand, !hasShift {
            if keyCode == 126 {
                moveTreeSelectionUp()
                return true
            }
            if keyCode == 125 {
                moveTreeSelectionDown()
                return true
            }
        }
        // Sizing keys — ⌘+/= step up, ⌘− step down, ⌘1–⌘5 jump.
        if hasCommand, chars == "=" || chars == "+" {
            ZFSPanelController.shared.step(by: 1)
            return true
        }
        if hasCommand, chars == "-" {
            ZFSPanelController.shared.step(by: -1)
            return true
        }
        if hasCommand, let chars, let digit = Int(chars), (1...5).contains(digit) {
            ZFSPanelController.shared.select(step: digit - 1)
            return true
        }
        return false
    }

    /// Points a pane at the selected dataset's mountpoint.
    ///
    /// Silent no-op when no dataset is selected, the dataset is not
    /// effectively mounted (mounted == false or mountpoint not a "/"-path),
    /// or no host is focused.
    private func pointPaneAtSelectedDataset(_ pane: PaneModel) {
        let sel = ZFSPanelController.shared.selection
        guard let dataset = sel.selectedFullDataset,
            dataset.mounted,
            dataset.mountpoint.hasPrefix("/"),
            let host = focusedPane.state.host
        else { return }
        pane.point(host: host, path: dataset.mountpoint)
    }

    /// Asks the tree selection to move one step up, re-reading cached datasets.
    private func moveTreeSelectionUp() {
        Task {
            guard let host = focusedPane.state.host, host != PalanaCore.localHostName else { return }
            let topology = await sessionEngine.field.facts(for: host)?.zfsTopology?.value ?? []
            let sorted = topology.sorted { $0.name < $1.name }
            ZFSPanelController.shared.selection.moveUp(in: sorted)
        }
    }

    /// Asks the tree selection to move one step down, re-reading cached datasets.
    private func moveTreeSelectionDown() {
        Task {
            guard let host = focusedPane.state.host, host != PalanaCore.localHostName else { return }
            let topology = await sessionEngine.field.facts(for: host)?.zfsTopology?.value ?? []
            let sorted = topology.sorted { $0.name < $1.name }
            ZFSPanelController.shared.selection.moveDown(in: sorted)
        }
    }
}

// MARK: - Text-entry priority (the top of `handle(_:)`)

extension PalanaSession {
    /// The verdict from the text-entry priority check at the top of `handle`.
    enum TextEntryPriorityOutcome {
        /// Fully handled — `handle(_:)` returns this consumed verdict.
        case handled(Bool)
        /// Not a text-entry case — the caller continues routing the event.
        case continueRouting
    }

    /// The text-entry priority check at the top of `handle(_:)` — field-less
    /// ZFS gather routing and the "every key belongs to a live text field"
    /// guard.
    ///
    /// Lives here (not `PalanaSession.swift`, where it is called) because
    /// its first branch is ZFS-gather-specific, and to keep `handle(_:)`'s
    /// cyclomatic complexity and that file's line count in budget.
    func handleTextEntryPriority(_ event: NSEvent) -> TextEntryPriorityOutcome {
        // Field-less ZFS gather: isNaming stands the monitor down so typed
        // keys never reach the panes. Return and Esc are handled here. The
        // model's flag decides, not the verb's static spec — destroy grows
        // a field when the typed confirmation is on.
        if operation.isFieldlessZFSGather {
            return .handled(handleFieldlessZFSGatherKey(event))
        }
        // The jump owns every plain key while it is open (round 10) —
        // text entry like the rest, routed here to keep handle() within
        // its complexity budget.
        if jumpBuffer != nil {
            return .handled(handleJumpKey(event))
        }
        // While any text field is live, every key belongs to the field.
        guard !left.pathEditing, !right.pathEditing, !operation.isNaming,
            !settingsFieldFocused
        else { return .handled(false) }
        return .continueRouting
    }
}

// MARK: - ZFS pane mode (ho-10.3)

extension PalanaSession {
    /// Esc's body inside `handlePanelPriorityKey` — cancels a busy command,
    /// or does a pure hide that also exits a pane's zfs mode when the
    /// focused pane is in it (ho-10.3 Decision 3).
    ///
    /// Extracted here (from `PalanaSession.swift`, where the switch lives)
    /// to keep that file within the line-length budget and the switch's
    /// cyclomatic complexity in budget.
    func handlePanelPriorityEsc() {
        if operation.terminalBusy {
            operation.cancelCommand()
            terminalFocused = true
            return
        }
        terminalFocused = false
        // A shell is waiting underneath: esc hands the panel back to it —
        // dismiss the result, keep the panel up, the shell resurfaces.
        // Without this, esc hid the panel and the shell key re-showed the
        // same stale result — a loop with no visible road to the shell
        // (round 10: 'I am here. how do i get to the shell?').
        let dismissable: [OperationModel.Phase] = [.ready, .finished, .failed, .cancelled]
        if shellMode, dismissable.contains(operation.phase) {
            operation.dismissOrCancel()
            operation.showPanel()
        } else {
            operation.hidePanel()
        }
        if focusedPane.paneMode == .zfs { focusedPane.exitZFSMode() }
    }

    /// `Z` while the terminal holds focus: toggles zfs mode on the focused pane.
    ///
    /// Esc is the pane's own exit (handled in the panel-priority and main
    /// Esc paths); `Z` here only enters, or exits if already in the mode —
    /// a second `Z` is the quick way back out without reaching for Esc.
    /// Entry is capability-gated: a host with no `zfsTopology` fact refuses
    /// with a plain sentence in the transcript rather than showing an
    /// empty tree.
    func toggleZFSPaneMode() {
        let pane = focusedPane
        if pane.paneMode == .zfs {
            pane.exitZFSMode()
            return
        }
        enterZFSMode(on: pane, host: pane.state.host)
    }

    /// Capability-gated entry into zfs mode on a specific pane.
    ///
    /// Shared by `toggleZFSPaneMode` (the `Z` key, always the focused pane)
    /// and the panel's "open as zfs mode" context-menu item (which may name
    /// left or right explicitly, focus or not). A host with no `zfsTopology`
    /// fact — including the local Mac, which is never probed — refuses with
    /// a plain sentence in the transcript rather than showing an empty tree.
    func enterZFSMode(on pane: PaneModel, host: String?) {
        guard let host else {
            operation.appendToolError("point a pane at a host first")
            return
        }
        guard host != PalanaCore.localHostName else {
            operation.appendToolError("no zfs on this Mac")
            return
        }
        Task {
            let facts = await sessionEngine.field.facts(for: host)
            let avail = CapabilityRequirement.zfs.evaluate(host: host, facts: facts)
            guard case .available = avail else {
                if case .unmet(let reason) = avail {
                    operation.appendToolError(reason)
                }
                return
            }
            pane.enterZFSMode()
            await pane.refreshZFSTree(engine: sessionEngine)
        }
    }

    /// Fires a zfs verb on the focused pane's tree cursor when it is in zfs
    /// mode and `token` matches one of the tool's key hints.
    ///
    /// Extracted from `handle(_:)` to keep that function's complexity in
    /// budget — the whole check-and-fire lives here as one branch point
    /// rather than two.
    func handleZFSPaneModeLetterKey(_ token: String) -> Bool {
        guard focusedPane.paneMode == .zfs,
            let verb = zfsTool.verbs.first(where: { $0.keyHint == token })
        else { return false }
        runZFSPaneModeVerb(verb)
        return true
    }

    /// Fires a zfs verb on the focused pane's tree cursor.
    ///
    /// The pane IS the mutation surface in zfs mode — one cursor, the row
    /// the operator is standing on. Silent no-op without a host or a
    /// selected dataset (an empty tree, or the pre-select rules not
    /// having landed on anything yet). Routes through the same
    /// `runWorkbenchMutation(_:on:dataset:)` the panel used to call
    /// directly — gathers, plan-then-Enter, pool-root refusal, and typed
    /// destroy are all unchanged (Decision 4).
    func runZFSPaneModeVerb(_ verb: WorkbenchVerb) {
        runZFSPaneModeVerb(verb, on: focusedPane)
    }

    /// Fires a zfs verb on a specific pane's tree cursor.
    ///
    /// Used by the pane's own context menu, which may render for a pane
    /// that is not the focused one — the row the operator right-clicked
    /// is always this pane's cursor, focus or not (Finder's manners).
    func runZFSPaneModeVerb(_ verb: WorkbenchVerb, on pane: PaneModel) {
        guard let host = pane.state.host, let dataset = pane.zfsSelectedDataset else { return }
        let mounted = pane.zfsSelectedFullDataset?.mounted ?? false
        runWorkbenchMutation(verb, on: host, dataset: dataset, mounted: mounted)
    }
}

// MARK: - ZFS gather keys

extension PalanaSession {
    /// Handles keys during a field-less ZFS gather (e.g. destroy).
    ///
    /// Return commits the gather; Esc dismisses. Every other plain key is
    /// swallowed — there is no field to receive it, and an unconsumed arrow
    /// would reach the Table's native handling and move its selection behind
    /// the grammar's back. ⌘-chords pass through untouched: no surface
    /// swallows them (ho-9.7's law — ⌘Q, ⌘, and the menus keep working).
    func handleFieldlessZFSGatherKey(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.contains(.command) else { return false }
        guard let token = Grammar.token(for: event) else { return true }
        if token == "return" {
            operation.commitNaming("")
            return true
        }
        if token == "esc" {
            operation.dismissOrCancel()
            return true
        }
        // Swallowed — the gather owns the keyboard until it commits or dies.
        return true
    }

    /// Routes a read verb through the Conduit and into the transcript.
    func runWorkbenchRead(_ verb: WorkbenchVerb, on host: String) {
        Task {
            let avail = await workbench.availability(of: verb, on: host)
            guard case .available = avail else { return }
            guard !operation.terminalBusy else { return }
            do {
                let stream = try await workbench.run(verb, of: readsTool, on: host)
                let cmd = readsTool.command(for: verb, on: host)
                await operation.runToolRead(header: "\(cmd) · \(host)", stream: stream)
            } catch {
                operation.appendToolError("read failed: \(error)")
            }
        }
    }

    /// Routes a mutation verb using the SELECTED dataset from the ZFS panel tree.
    ///
    /// This is the primary path when the ZFS panel is open — the caller has
    /// already resolved which dataset to target from the tree selection.
    /// Skips the `datasetContaining` path-search used by the pane-anchored variant.
    /// `mounted` carries the dataset's mounted fact so the composed plan can
    /// weave the implicit-unmount heal (ho-10.4-AT-02); defaults false for
    /// callers that have not resolved it.
    func runWorkbenchMutation(
        _ verb: WorkbenchVerb, on host: String, dataset: String, mounted: Bool = false
    ) {
        Task {
            guard await zfsMutationGuard(verb: verb, on: host) else { return }
            guard !refusesPoolRoot(verb, dataset: dataset) else { return }
            operation.beginZFSMutation(
                verb, tool: zfsTool, host: host, dataset: dataset, mounted: mounted)
        }
    }

    /// Routes a mutation verb: resolves the dataset from the focused pane's path,
    /// checks availability, and hands off to the operation gather.
    ///
    /// Used by the terminal-focus letter path (via `runWorkbenchVerb`) and by
    /// any caller that does not have an explicit dataset selection.
    func runWorkbenchMutation(_ verb: WorkbenchVerb, on host: String) {
        Task {
            guard await zfsMutationGuard(verb: verb, on: host) else { return }
            // Resolve the containing dataset from the focused pane's path.
            let path = focusedPane.state.path
            guard let topology = await sessionEngine.field.facts(for: host)?.zfsTopology?.value,
                let dataset = ZFSTopology.datasetContaining(path, in: topology)
            else {
                operation.appendToolError("no dataset holds \(path) on \(host)")
                return
            }
            guard !refusesPoolRoot(verb, dataset: dataset.name) else { return }
            operation.beginZFSMutation(
                verb, tool: zfsTool, host: host, dataset: dataset.name, mounted: dataset.mounted)
        }
    }

    /// Refuses destroy and rename aimed at a pool root with a plain sentence.
    ///
    /// A dataset name with no "/" is the pool root. The Plan Engine holds
    /// the same invariant (`zfsPoolRootRefused`); this is the early surface
    /// so the operator never types into a doomed gather.
    private func refusesPoolRoot(_ verb: WorkbenchVerb, dataset: String) -> Bool {
        guard verb.id == "zfs-destroy" || verb.id == "zfs-rename" else { return false }
        guard !dataset.contains("/") else { return false }
        operation.appendToolError(
            "\(verb.label) refuses \(dataset) — that is the pool root; pālana manages datasets, never the pool itself"
        )
        return true
    }

    /// Shared availability and busy guard for all mutation routes.
    ///
    /// Returns `true` when the verb may proceed; `false` when it should abort.
    private func zfsMutationGuard(verb: WorkbenchVerb, on host: String) async -> Bool {
        let avail = await workbench.availability(of: verb, on: host)
        guard case .available = avail else { return false }
        guard !operation.terminalBusy else { return false }
        return true
    }
}
