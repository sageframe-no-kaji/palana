// ZFSMutationTool — the Workbench tool for ZFS mutations. Eight verbs, each
// composing a ZFSMutation the Plan Engine turns into a command the operator
// reads before Enter runs it. The Workbench's read path never sees these;
// the app routes .mutation verbs through planRequest(for:on:input:).

import Foundation

/// The ZFS mutation tool.
///
/// Exposes eight mutation verbs covering the dataset and snapshot lifecycle:
/// create, destroy, rename; snapshot, destroy snapshot, rollback; set and
/// clear the mountpoint. Every verb requires a probed `zfsTopology` fact —
/// the host must have ZFS — and composes a ``PlanRequest`` the Plan Engine
/// turns into the command the operator reads before Enter.
public struct ZFSMutationTool: WorkbenchTool {
    /// `"zfs"` — the stable tool identifier.
    public let id = "zfs"
    /// `"zfs"` — the display label.
    public let label = "zfs"

    /// The eight ZFS mutation verbs.
    public let verbs: [WorkbenchVerb] = [
        WorkbenchVerb(
            id: "zfs-create",
            label: "new dataset",
            keyHint: "c",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "name the new dataset — a child of where you stand",
                needsText: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-destroy",
            label: "destroy",
            keyHint: "x",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "destroy this dataset",
                needsText: false,
                offersRecursive: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-rename",
            label: "rename",
            keyHint: "r",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "type the full new name",
                needsText: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-snapshot",
            label: "snapshot",
            keyHint: "n",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "name the snapshot",
                needsText: true,
                offersRecursive: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-destroy-snapshot",
            label: "destroy snapshot",
            keyHint: "k",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "name the snapshot to destroy",
                needsText: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-rollback",
            label: "roll back",
            keyHint: "b",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "name the snapshot to roll back to",
                needsText: true,
                offersRecursive: true,
                toggleLabel: "roll back past newer snapshots — destroys them"
            )
        ),
        WorkbenchVerb(
            id: "zfs-set-mountpoint",
            label: "set mountpoint",
            keyHint: "m",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "type the mountpoint path",
                needsText: true
            )
        ),
        WorkbenchVerb(
            id: "zfs-clear-mountpoint",
            label: "clear mountpoint",
            keyHint: "i",
            requirement: .zfs,
            kind: .mutation,
            gather: GatherSpec(
                prompt: "clear the mountpoint — the dataset inherits its parent's",
                needsText: false
            )
        ),
    ]

    /// Creates the ZFS mutation tool.
    public init() {}

    /// Not called for mutation verbs — returns the verb id as a sentinel.
    ///
    /// The Workbench's read path (`run`) refuses `.mutation` verbs with
    /// ``WorkbenchError/notARead`` before reaching this method. The app routes
    /// mutations through ``planRequest(for:on:input:)`` instead.
    public func command(for verb: WorkbenchVerb, on host: String) -> String {
        verb.id
    }

    /// Composes a ``PlanRequest`` for the given mutation verb and gathered input.
    ///
    /// Returns nil when `input.target` is empty, when `verb.id` is unknown, or
    /// when a verb that needs text receives nil, empty, or whitespace-only text.
    /// The app treats a nil return as a dismissal — the operator supplied
    /// nothing actionable and the compose does not reach the Plan Engine.
    public func planRequest(
        for verb: WorkbenchVerb,
        on host: String,
        input: MutationInput
    ) -> PlanRequest? {
        let target = input.target
        guard !target.isEmpty else { return nil }
        guard let mutation = mutation(for: verb.id, target: target, input: input) else {
            return nil
        }
        return PlanRequest(
            operation: .zfs,
            source: Locus(host: host, directory: target),
            entries: [],
            destination: nil,
            zfs: mutation
        )
    }
}

// MARK: - Private helpers

extension ZFSMutationTool {
    /// Trims whitespace from `text`; returns nil when the result is empty or
    /// when `text` itself is nil.
    private func trimmed(_ text: String?) -> String? {
        guard let text else { return nil }
        let result = text.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    /// Builds the ``ZFSMutation`` for a verb id and gathered input.
    ///
    /// Returns nil for unknown verb ids or when a needsText verb receives
    /// nil, empty, or whitespace-only text. Caller guards the empty-target
    /// case before invoking this.
    private func mutation(
        for verbId: String,
        target: String,
        input: MutationInput
    ) -> ZFSMutation? {
        switch verbId {
        case "zfs-create":
            return mutateCreate(target: target, input: input)
        case "zfs-destroy":
            return .destroyDataset(name: target, recursive: input.recursive)
        case "zfs-rename":
            return mutateRename(target: target, input: input)
        case "zfs-snapshot":
            return mutateSnapshot(target: target, input: input)
        case "zfs-destroy-snapshot":
            guard let text = trimmed(input.text) else { return nil }
            return .destroySnapshot(dataset: target, name: text)
        case "zfs-rollback":
            guard let text = trimmed(input.text) else { return nil }
            return .rollback(dataset: target, name: text, destroysNewer: input.recursive)
        case "zfs-set-mountpoint":
            guard let text = trimmed(input.text) else { return nil }
            return .setMountpoint(dataset: target, path: text)
        case "zfs-clear-mountpoint":
            return .clearMountpoint(dataset: target)
        default:
            return nil
        }
    }

    private func mutateCreate(target: String, input: MutationInput) -> ZFSMutation? {
        guard let text = trimmed(input.text) else { return nil }
        return .createDataset(name: "\(target)/\(text)", mountpoint: nil)
    }

    private func mutateRename(target: String, input: MutationInput) -> ZFSMutation? {
        guard let text = trimmed(input.text) else { return nil }
        return .renameDataset(from: target, to: text)
    }

    private func mutateSnapshot(target: String, input: MutationInput) -> ZFSMutation? {
        guard let text = trimmed(input.text) else { return nil }
        return .snapshot(dataset: target, name: text, recursive: input.recursive)
    }
}
