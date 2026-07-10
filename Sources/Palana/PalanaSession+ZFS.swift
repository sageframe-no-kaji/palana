// PalanaSession+ZFS — the mutation route, the ZFS panel key handler, and
// the field-less gather key handler, extracted from PalanaSession.swift
// to keep that file within the line-length budget.

import AppKit
import PalanaCore

// MARK: - ZFS panel key handling

extension PalanaSession {
    /// Routes a key event while the ZFS panel is the key window.
    ///
    /// Esc closes. ⌘1–⌘5 jump to a size; ⌘+/= and ⌘− step — mirroring
    /// `handleKeysPanelKey` exactly. A plain letter matching a ZFS verb's
    /// `keyHint` fires that verb — panel closes first so focus returns to
    /// the main window before the gather opens. Everything else passes through.
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
        // Match against a ZFS verb's keyHint.
        if let verb = zfsTool.verbs.first(where: { $0.keyHint == ch }) {
            ZFSPanelController.shared.close()
            runWorkbenchVerb(verb)
            return true
        }
        return false
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

    /// Routes a mutation verb: resolves the dataset, checks availability,
    /// and hands off to the operation gather.
    func runWorkbenchMutation(_ verb: WorkbenchVerb, on host: String) {
        Task {
            let avail = await workbench.availability(of: verb, on: host)
            guard case .available = avail else { return }
            guard !operation.terminalBusy else { return }
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
}
