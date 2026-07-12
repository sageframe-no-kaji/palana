// OperationModel+ZFS — the ZFS mutation gather: begin, commit, and the
// post-run refresh. Mirrors the naming-path idiom exactly: a text field
// collects the operator's input, commitZFSGather composes the PlanRequest
// and hands it to the Plan Engine, and phase lands at .ready. Enter
// enacts — nothing else does (Decision 4).

import Foundation
import PalanaCore

extension OperationModel {
    // MARK: - State hygiene

    /// Clears the pending ZFS gather state.
    ///
    /// Called at the top of every non-ZFS begin (`begin`, `beginNaming`,
    /// `beginTouch`) — the pending verb survives `.ready` and `.finished`
    /// (only `reset()` clears it), and a stale one would misroute
    /// `commitNaming` into the ZFS path on the next file rename or create.
    func clearZFSGatherState() {
        pendingZFSVerb = nil
        pendingZFSTool = nil
        pendingZFSHost = nil
        pendingZFSDataset = nil
        zfsRecursive = false
        zfsGatherWantsText = false
        namingContextLines = []
    }

    // MARK: - Begin

    /// Opens a ZFS mutation gather for the given verb, tool, host, and dataset.
    ///
    /// Phase law mirrors `beginNaming`: enacting → re-show; gathering → cancel;
    /// naming → reset; then a fresh gather. Verbs that need text enter the
    /// `.naming` phase so the key monitor stands down and the panel's field
    /// row appears. Verbs with no text (clear-mountpoint) compose immediately
    /// and land at `.ready`.
    func beginZFSMutation(
        _ verb: WorkbenchVerb,
        tool: ZFSMutationTool,
        host: String,
        dataset: String
    ) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        // .idle, .ready, .finished, .failed, .cancelled fall through to a fresh begin.
        panelShowing = true
        requested = .zfs
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        // Symmetric hygiene: a stale file-naming entry must not steer the
        // ZFS gather's prefill or a later commit.
        pendingNamingEntry = nil
        pendingNamingSource = nil
        pendingZFSVerb = verb
        pendingZFSTool = tool
        pendingZFSHost = host
        pendingZFSDataset = dataset
        zfsRecursive = false

        let spec = verb.gather
        // Destroy grows a field when the typed confirmation is on — the
        // word `destroy` is the arm, not a second Enter (his call, this
        // round). The routing and the panel read the flag, not the spec.
        let typedConfirm = verb.id == "zfs-destroy" && confirmDestroyTyped
        let needsText = spec?.needsText == true || typedConfirm
        zfsGatherWantsText = needsText

        if needsText || spec?.offersRecursive == true {
            // Enter the naming phase — the key monitor stands down and the
            // panel's field row renders with the gather label and optional toggle.
            namingLabel = gatherLabel(verb: verb, dataset: dataset)
            namingPrefill = gatherPrefill(verb: verb, dataset: dataset)
            namingContextLines = []
            phase = .naming
            // The snapshot verbs gather a name nobody remembers — read the
            // dataset's snapshots off the wire and show them under the field.
            if verb.id == "zfs-rollback" || verb.id == "zfs-destroy-snapshot" {
                fetchSnapshotContext(host: host, dataset: dataset)
            }
        } else {
            // No text, no toggle (e.g. zfs-clear-mountpoint) — compose now.
            commitZFSGather(nil)
        }
    }

    /// Reads the dataset's snapshot names and drops them into
    /// ``namingContextLines`` for the gather view — oldest first, short
    /// names only (the part after `@`, which is what the field wants).
    ///
    /// Fire-and-forget; lines landing after the gather closed render
    /// nowhere and clear at the next state change.
    private func fetchSnapshotContext(host: String, dataset: String) {
        Task {
            let cmd = "zfs list -H -t snapshot -o name -s creation -- \(ShellQuote.quote(dataset))"
            guard let running = try? await engine.conduit(for: host).run(on: host, cmd),
                let result = try? await running.collect()
            else {
                namingContextLines = ["(could not list snapshots on \(host))"]
                return
            }
            let names = (String(bytes: result.stdout, encoding: .utf8) ?? "")
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard let at = line.firstIndex(of: "@") else { return nil }
                    return String(line[line.index(after: at)...])
                }
            if names.isEmpty {
                // A field that can only fail is a dead end — dismiss the
                // gather and say why in the transcript instead (the hands
                // round sat in front of '(no snapshots)' with nothing
                // sensible to type).
                if phase == .naming, pendingZFSVerb != nil {
                    reset()
                    note("no snapshots on \(dataset) — nothing to act on")
                }
                return
            }
            namingContextLines = names
        }
    }

    // MARK: - Commit

    /// Called by the name field's onSubmit or by a field-less gather.
    ///
    /// nil text signals a field-less gather (destroy, clear-mountpoint). Empty
    /// or all-whitespace text from a text verb dismisses quietly. A rename whose
    /// submitted text equals the prefill (the unedited dataset name) dismisses
    /// quietly — matching commitNaming's posture. A good submission composes the
    /// PlanRequest and lands at .ready; a nil planRequest or a PlanError renders
    /// as a failure or a dismissal.
    func commitZFSGather(_ text: String?) {
        guard let verb = pendingZFSVerb,
            let tool = pendingZFSTool,
            let host = pendingZFSHost,
            let dataset = pendingZFSDataset
        else {
            reset()
            return
        }
        let spec = verb.gather
        let needsText = spec?.needsText == true

        // Trim if we have text; an empty-required dismiss is a reset.
        let trimmedText: String?
        if let raw = text {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            trimmedText = trimmed.isEmpty ? nil : trimmed
        } else {
            trimmedText = nil
        }

        // Destroy with the typed confirmation on: the field's only job is
        // the word. Anything else — empty, a typo, the dataset name —
        // dismisses quietly, and the mutation never composes.
        if verb.id == "zfs-destroy", zfsGatherWantsText {
            guard trimmedText?.lowercased() == "destroy" else {
                reset()
                return
            }
            let input = MutationInput(target: dataset, text: nil, recursive: zfsRecursive)
            compose(verb: verb, tool: tool, host: host, input: input)
            return
        }

        if needsText {
            guard let txt = trimmedText else {
                // Empty required text — dismiss quietly.
                reset()
                return
            }
            // Rename: unchanged name dismisses quietly (the prefill unedited).
            if verb.id == "zfs-rename", txt == dataset {
                reset()
                return
            }
            let input = MutationInput(target: dataset, text: txt, recursive: zfsRecursive)
            compose(verb: verb, tool: tool, host: host, input: input)
        } else {
            // Field-less gather — the recursive toggle is the only operator input.
            let input = MutationInput(target: dataset, text: nil, recursive: zfsRecursive)
            compose(verb: verb, tool: tool, host: host, input: input)
        }
    }

    // MARK: - Post-run refresh

    /// Called from `handle(_:)` when a `.zfs` plan finishes.
    ///
    /// Refreshes panes pointed at the affected host (mountpoint moves and
    /// destroys change what listings show), and kicks one field re-discovery
    /// so the topology fact — dataset names, mountpoints, the ◆ markers,
    /// future verb targeting — carries the new truth. A pane in zfs mode on
    /// the affected host re-renders its own tree from the same fresh
    /// topology instead of a file refresh (ho-10.3 Decision 5) — the
    /// created dataset appears, the destroyed one goes, without leaving
    /// the mode. Fire-and-forget.
    func afterZFSFinished(host: String, left: PaneModel, right: PaneModel) {
        let leftInZFSMode = left.state.host == host && left.paneMode == .zfs
        let rightInZFSMode = right.state.host == host && right.paneMode == .zfs
        if left.state.host == host, left.paneMode == .files { left.apply(.refresh) }
        if right.state.host == host, right.paneMode == .files { right.apply(.refresh) }
        Task {
            // A pane in zfs mode re-reads its own tree — its refresh already
            // runs a cache-then-discover-then-cache pass, so the plain
            // top-level discover below only needs to fire when neither pane
            // is doing that work itself.
            if leftInZFSMode { await left.refreshZFSTree(engine: engine) }
            if rightInZFSMode { await right.refreshZFSTree(engine: engine) }
            if !leftInZFSMode, !rightInZFSMode {
                _ = try? await engine.field.discover(host)
            }
        }
    }

    // MARK: - Private helpers

    /// Builds the MutationInput and runs it through the Plan Engine.
    ///
    /// A nil planRequest dismisses quietly (malformed gather). A PlanError
    /// renders as a failure. A good plan lands at `.ready` — and stops there
    /// (Decision 4: never call enact() here).
    private func compose(
        verb: WorkbenchVerb,
        tool: ZFSMutationTool,
        host: String,
        input: MutationInput
    ) {
        guard let request = tool.planRequest(for: verb, on: host, input: input) else {
            reset()
            return
        }
        do {
            plan = try PlanEngine.plan(request, facts: PlanFacts())
            phase = .ready
            // Decision 4: gather submit composes and renders the plan at .ready.
            // The existing Enter-at-.ready path enacts. No enact() call here.
        } catch {
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
            panelShowing = true
        }
    }

    /// The gather field label — plain sentence, message-grammar voice.
    ///
    /// Uses the real dataset name so the operator knows exactly what they are
    /// naming, into, or acting on.
    private func gatherLabel(verb: WorkbenchVerb, dataset: String) -> String {
        switch verb.id {
        case "zfs-create":
            return "name the new dataset — a child of \(dataset)  (⏎ shows the plan)"
        case "zfs-destroy":
            return confirmDestroyTyped
                ? "type destroy to arm — \(dataset)  (⏎ shows the plan, nothing runs yet)"
                : "destroy \(dataset) — ⏎ shows the plan, nothing runs yet"
        case "zfs-rename":
            return "type the full new name — ⏎ shows the plan"
        case "zfs-snapshot":
            return "name the snapshot — \(dataset)@<name>  (⏎ shows the plan)"
        case "zfs-destroy-snapshot":
            return "name the snapshot to destroy — \(dataset)@<name>  (⏎ shows the plan)"
        case "zfs-rollback":
            return "name the snapshot to roll back to — \(dataset)@<name>  (⏎ shows the plan)"
        case "zfs-set-mountpoint":
            return "type the mountpoint path — ⏎ shows the plan"
        default:
            return verb.gather?.prompt ?? verb.label
        }
    }

    /// The prefill text for the gather field.
    ///
    /// Rename prefills the full current dataset name (selected). All other
    /// text verbs start empty. Field-less verbs never reach this path.
    private func gatherPrefill(verb: WorkbenchVerb, dataset: String) -> String {
        verb.id == "zfs-rename" ? dataset : ""
    }
}
