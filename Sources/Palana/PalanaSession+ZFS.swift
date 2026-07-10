// PalanaSession+ZFS — the mutation route, the ZFS panel key handler, and
// the field-less gather key handler, extracted from PalanaSession.swift
// to keep that file within the line-length budget.

import AppKit
import PalanaCore

// MARK: - ZFS panel key handling

extension PalanaSession {
    /// Routes a key event while the ZFS panel is the key window.
    ///
    /// Esc closes. ↑↓ (keyCodes 126/125) move the dataset tree selection
    /// without rebuilding the hosting view. ⇧⌘← (keyCode 123) points the
    /// left pane at the selected dataset's mountpoint; ⇧⌘→ (keyCode 124)
    /// the right pane — mounted datasets only, silent no-op otherwise.
    /// ⌘1–⌘5 jump to a size; ⌘+/= and ⌘− step — mirroring
    /// `handleKeysPanelKey` exactly. A plain letter matching a ZFS verb's
    /// `keyHint` fires that verb on the currently selected dataset —
    /// the panel stays open and keyboard focus returns to the main window
    /// so the gather field receives input immediately. Everything else
    /// passes through.
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
        // Plain letters only — modifiers would step on menu shortcuts.
        guard !hasCommand, !hasShift,
            let ch = event.charactersIgnoringModifiers,
            ch.count == 1
        else { return false }
        // Match against a ZFS verb's keyHint — fires on the selected dataset.
        // Panel stays open — Esc or ✕ closes it. Focus returns to the main
        // window so the gather field (PlanPanel .naming phase) receives input.
        if let verb = zfsTool.verbs.first(where: { $0.keyHint == ch }) {
            let sel = ZFSPanelController.shared.selection
            guard let host = focusedPane.state.host,
                let dataset = sel.selectedDataset
            else { return true }
            runWorkbenchMutation(verb, on: host, dataset: dataset)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
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
    func runWorkbenchMutation(_ verb: WorkbenchVerb, on host: String, dataset: String) {
        Task {
            guard await zfsMutationGuard(verb: verb, on: host) else { return }
            operation.beginZFSMutation(verb, tool: zfsTool, host: host, dataset: dataset)
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
            operation.beginZFSMutation(verb, tool: zfsTool, host: host, dataset: dataset.name)
        }
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
