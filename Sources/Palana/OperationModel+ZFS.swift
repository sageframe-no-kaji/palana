// OperationModel+ZFS — the ZFS mutation gather: begin, commit, and the
// post-run refresh. Mirrors the naming-path idiom exactly: a text field
// collects the operator's input, commitZFSGather composes the PlanRequest
// and hands it to the Plan Engine, and phase lands at .ready. Enter
// enacts — nothing else does (Decision 4).
//
// The plan stands on fresh topology, twice: the compose reads the host
// before it names a dataset, and Enter re-reads it before the first
// step runs. Memory of an earlier visit is shown, never obeyed.

import Foundation
import PalanaCore

/// A ZFS gather refused before the engine saw it — the sentence is the
/// whole error, in the panel's voice.
struct ZFSGatherRefusal: Error, CustomStringConvertible {
    /// What the panel says.
    let description: String
}

extension OperationModel {
    // MARK: - State hygiene

    /// Clears the pending ZFS gather state.
    ///
    /// Called at the top of every non-ZFS begin (`begin`, `beginNaming`,
    /// `beginTouch`) — the pending verb survives `.ready` and `.finished`
    /// (only `reset()` clears it), and a stale one would misroute
    /// `commitNaming` into the ZFS path on the next file rename or create.
    /// A snapshot-context read still in flight is cancelled with it.
    func clearZFSGatherState() {
        snapshotContextTask?.cancel()
        snapshotContextTask = nil
        pendingZFSVerb = nil
        pendingZFSTool = nil
        pendingZFSHost = nil
        pendingZFSDataset = nil
        pendingZFSMounted = false
        zfsRecursive = false
        zfsGatherWantsText = false
        namingContextLines = []
    }

    // MARK: - The recursive toggle's keyboard path

    /// Flips `zfsRecursive` when the pending gather offers the choice.
    ///
    /// A no-op passthrough when no ZFS gather is pending or its verb does
    /// not offer recursive (`offersRecursive == false`) — space during a
    /// destroy-only or clear-mountpoint gather touches nothing. Shared by
    /// both key routes: `handleFieldlessZFSGatherKey` (destroy) and
    /// `handleTextEntryPriority`'s ZFS branch (snapshot, rollback) —
    /// see Ho-10.4-AT-03's decision for why space and not `r`.
    func toggleZFSRecursiveIfOffered() {
        guard pendingZFSVerb?.gather?.offersRecursive == true else { return }
        zfsRecursive.toggle()
    }

    // MARK: - Begin

    /// Opens a ZFS mutation gather for the given verb, tool, host, and dataset.
    ///
    /// Phase law mirrors `beginNaming`: enacting → re-show; gathering → cancel;
    /// naming → reset; then a fresh gather. Verbs that need text enter the
    /// `.naming` phase so the key monitor stands down and the panel's field
    /// row appears. Verbs with no text (clear-mountpoint) compose immediately
    /// and land at `.ready`.
    ///
    /// `mounted` is the surface's remembered fact, carried for the label;
    /// the compose reads the dataset's real state before it composes.
    func beginZFSMutation(
        _ verb: WorkbenchVerb,
        tool: ZFSMutationTool,
        host: String,
        dataset: String,
        mounted: Bool = false
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
        // This gather supersedes any snapshot read still in flight — a
        // late answer from the last one lands nowhere.
        snapshotContextTask?.cancel()
        snapshotContextTask = nil
        zfsGatherGeneration += 1
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
        pendingZFSMounted = mounted
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
                fetchSnapshotContext(host: host, dataset: dataset, verb: verb)
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
    /// The read belongs to the gather that started it: it captures the
    /// gather's generation, host, dataset, and verb, and commits its
    /// answer only while all four still name the current gather. A read
    /// that outlives its gather — cancelled, or simply late — changes
    /// nothing, so one dataset's snapshots never show under another's
    /// field and one dataset's empty list never dismisses another's gather.
    private func fetchSnapshotContext(host: String, dataset: String, verb: WorkbenchVerb) {
        let generation = zfsGatherGeneration
        snapshotContextTask = Task {
            let names: [String]?
            do {
                names = try await engine.field.snapshotNames(of: dataset, on: host)
            } catch {
                names = nil
            }
            guard !Task.isCancelled,
                isCurrentZFSGather(generation: generation, host: host, dataset: dataset, verb: verb)
            else { return }
            guard let names else {
                namingContextLines = ["(could not list snapshots on \(host))"]
                return
            }
            if names.isEmpty {
                // A field that can only fail is a dead end — dismiss the
                // gather and say why in the transcript instead (the hands
                // round sat in front of '(no snapshots)' with nothing
                // sensible to type).
                reset()
                // reset() hides the panel — re-show it so the
                // explanation is READ, not buried (the hands round
                // watched the panel flash and vanish, then found
                // the note later by hand).
                showPanel()
                note("no snapshots on \(dataset) — nothing to act on")
                return
            }
            namingContextLines = names
        }
    }

    /// Whether a captured gather identity is still the one on screen.
    private func isCurrentZFSGather(
        generation: Int, host: String, dataset: String, verb: WorkbenchVerb
    ) -> Bool {
        phase == .naming
            && generation == zfsGatherGeneration
            && pendingZFSVerb?.id == verb.id
            && pendingZFSHost == host
            && pendingZFSDataset == dataset
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
            let input = MutationInput(
                target: dataset, text: nil, recursive: zfsRecursive, mounted: pendingZFSMounted)
            compose(verb: verb, tool: tool, host: host, input: input)
            return
        }

        if needsText {
            guard let txt = trimmedText else {
                // Empty required text — dismiss quietly.
                reset()
                return
            }
            // The snapshot verbs validate against the listed truth: a name
            // not in the list composes a plan that can only fail (the
            // hands round typed the confirm word 'destroy' into a
            // rollback's NAME field and met 'dataset does not exist').
            // Context lines starting with "(" are notes, not names.
            if verb.id == "zfs-rollback" || verb.id == "zfs-destroy-snapshot" {
                let known = namingContextLines.filter { !$0.hasPrefix("(") }
                if !known.isEmpty, !known.contains(txt) {
                    reset()
                    appendToolError(
                        "no snapshot named \(txt) on \(dataset) — it has: \(known.joined(separator: ", "))"
                    )
                    return
                }
            }
            // Rename: unchanged name dismisses quietly (the prefill unedited).
            if verb.id == "zfs-rename", txt == dataset {
                reset()
                return
            }
            let input = MutationInput(
                target: dataset, text: txt, recursive: zfsRecursive, mounted: pendingZFSMounted)
            compose(verb: verb, tool: tool, host: host, input: input)
        } else {
            // Field-less gather — the recursive toggle is the only operator input.
            let input = MutationInput(
                target: dataset, text: nil, recursive: zfsRecursive, mounted: pendingZFSMounted)
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

    // MARK: - Pre-enactment confirmation

    /// Re-reads every host a plan is bound to and confirms the bound
    /// datasets still answer as they did — before anything runs.
    ///
    /// Each read goes through ``Field/refresh(_:)``, so what is compared
    /// was on the wire moments ago. A host that will not answer, a read
    /// no newer than the plan's, a dataset gone or moved: every one
    /// throws, and `enact()` lands the plan at `.failed` with nothing run.
    func confirmTopologyBinding(_ binding: TopologyBinding, of plan: Plan) async throws {
        var fresh: [String: HostFacts] = [:]
        for host in binding.hosts {
            note("re-reading zfs on \(host) before anything runs…")
            do {
                fresh[host] = try await engine.field.refresh(host)
            } catch let error as FieldError {
                throw TopologyBindingError.unavailable(host: host, detail: "\(error)")
            }
        }
        try Task.checkCancellation()
        try plan.confirmTopology(fresh: fresh)
        let names = binding.bound.map(\.dataset.name).joined(separator: ", ")
        note("\(names) — as read when the plan composed")
    }

    // MARK: - Private helpers

    /// Reads the host fresh, then builds the MutationInput and runs it
    /// through the Plan Engine.
    ///
    /// The gather phase holds while the host answers. A nil planRequest
    /// dismisses quietly (malformed gather). A refusal or PlanError renders
    /// as a failure. A good plan lands at `.ready` bound to the read it
    /// stood on — and stops there (Decision 4: never call enact() here).
    private func compose(
        verb: WorkbenchVerb,
        tool: ZFSMutationTool,
        host: String,
        input: MutationInput
    ) {
        phase = .gathering
        panelShowing = true
        gatherTask = Task {
            await composeOverFreshTopology(verb: verb, tool: tool, host: host, input: input)
        }
    }

    /// The compose body: one wire read, then the engine.
    ///
    /// The target dataset must exist in the read, and must read exactly
    /// as memory last showed it — a dataset whose mountpoint or mounted
    /// state moved since the surface chose it is refused, because the
    /// choice may have been made by a path that now belongs to another
    /// dataset. Memory carries the fresh read afterward, so the next
    /// choice is made on the truth.
    private func composeOverFreshTopology(
        verb: WorkbenchVerb,
        tool: ZFSMutationTool,
        host: String,
        input: MutationInput
    ) async {
        do {
            let remembered = await engine.field.facts(for: host)?.zfsTopology?.value
                .first { $0.name == input.target }
            note("reading zfs on \(host)…")
            let fresh = try await engine.field.refresh(host)
            guard !Task.isCancelled else { return }
            if let failure = fresh.zfsTopologyUnavailable?.value {
                throw ZFSGatherRefusal(
                    description:
                        "the zfs topology on \(host) could not be read — \(failure.detail); "
                        + "the plan was not composed")
            }
            if case .unmet(let reason) = verb.requirement.evaluate(host: host, facts: fresh) {
                throw ZFSGatherRefusal(description: reason)
            }
            guard let datasets = fresh.zfsTopology?.value, let generation = fresh.generation else {
                throw ZFSGatherRefusal(description: "\(host) has no zfs topology to compose over")
            }
            guard let target = datasets.first(where: { $0.name == input.target }) else {
                throw ZFSGatherRefusal(
                    description:
                        "\(input.target) on \(host) no longer exists — the topology changed since it "
                        + "was shown; the tree has been re-read, choose again")
            }
            if let remembered, remembered != target {
                throw ZFSGatherRefusal(
                    description:
                        "\(target.name) on \(host) changed since it was shown — "
                        + "\(remembered.changes(to: target)); the tree has been re-read, choose again")
            }
            var freshInput = input
            freshInput.mounted = target.mounted
            guard let request = tool.planRequest(for: verb, on: host, input: freshInput) else {
                reset()
                return
            }
            var composed = try PlanEngine.plan(request, facts: PlanFacts())
            composed.topologyBinding = TopologyBinding(bound: [
                TopologyBinding.Bound(
                    host: host, role: .target, dataset: target, generation: generation)
            ])
            plan = composed
            phase = .ready
            // Decision 4: gather submit composes and renders the plan at .ready.
            // The existing Enter-at-.ready path enacts. No enact() call here.
        } catch {
            guard !Task.isCancelled else { return }
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
                ? "type DESTROY to arm — \(dataset)  (⏎ shows the plan, nothing runs yet)"
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
