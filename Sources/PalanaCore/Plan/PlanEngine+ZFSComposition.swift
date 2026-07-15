// ZFS mutation composition — the three composer methods extracted from
// PlanEngine.swift to keep that file within the length limit. Same
// extension, same pure-function contract: no I/O, no Field, no wire.

import Foundation

extension PlanEngine {
    // MARK: - Validation

    /// Validates a `.zfs` request — payload required, names non-empty,
    /// snapshot name must not carry `@`, rename names must differ, and
    /// destroy/rename refuse the pool root (a name with no `/`).
    static func validateZfs(_ request: PlanRequest) throws {
        guard let mutation = request.zfs else {
            throw PlanError.zfsMutationPayloadRequired
        }
        switch mutation {
        case .createDataset, .destroyDataset, .renameDataset:
            try validateZfsDatasetMutation(mutation)
        case .snapshot, .destroySnapshot, .rollback, .setMountpoint, .clearMountpoint, .mount,
            .unmount:
            try validateZfsSnapshotAndPropertyMutation(mutation)
        }
    }

    /// Validates create / destroy / rename — destroy and rename refuse the pool root.
    private static func validateZfsDatasetMutation(_ mutation: ZFSMutation) throws {
        switch mutation {
        case .createDataset(let name, _):
            try requireNonEmpty(name)
        case .destroyDataset(let name, _):
            try requireNonEmpty(name)
            try refusePoolRoot(name)
        case .renameDataset(let from, let to):
            try requireNonEmpty(from)
            try requireNonEmpty(to)
            guard from != to else { throw PlanError.zfsRenameNamesIdentical }
            try refusePoolRoot(from)
        default:
            break
        }
    }

    /// Validates snapshot, destroySnapshot, rollback, setMountpoint,
    /// clearMountpoint, mount, unmount — pool root is legal for all of these.
    private static func validateZfsSnapshotAndPropertyMutation(_ mutation: ZFSMutation) throws {
        switch mutation {
        case .snapshot(let dataset, let name, _):
            try requireNonEmpty(dataset)
            try requireNonEmpty(name)
            guard !name.contains("@") else { throw PlanError.zfsSnapshotNameContainsAt }
        case .destroySnapshot(let dataset, let name):
            try requireNonEmpty(dataset)
            try requireNonEmpty(name)
        case .rollback(let dataset, let name, _):
            try requireNonEmpty(dataset)
            try requireNonEmpty(name)
        case .setMountpoint(let dataset, let path):
            try requireNonEmpty(dataset)
            try requireNonEmpty(path)
            // zfs itself refuses relative paths with an exit-255 spray;
            // the engine says it plainly before anything composes (the
            // hands round typed '~/').
            guard path.hasPrefix("/") else { throw PlanError.zfsMountpointNotAbsolute }
        case .clearMountpoint(let dataset):
            try requireNonEmpty(dataset)
        case .mount(let dataset), .unmount(let dataset):
            // Pool-root mount/unmount is legal — unlike destroy/rename,
            // never refused here.
            try requireNonEmpty(dataset)
        default:
            break
        }
    }

    private static func requireNonEmpty(_ value: String) throws {
        guard !value.isEmpty else { throw PlanError.zfsNameEmpty }
    }

    /// A dataset name with no `/` is the pool root — destroy and rename
    /// must not compose on it (pools are physical; ho-10.1 out of scope).
    private static func refusePoolRoot(_ name: String) throws {
        guard name.contains("/") else { throw PlanError.zfsPoolRootRefused }
    }

    // MARK: - Composition

    /// Routes to the appropriate ZFS composer based on the mutation family.
    static func composeZFSMutation(_ request: PlanRequest) -> [PlanStep] {
        guard let mutation = request.zfs else { return [] }
        let host = Runner.host(request.source.host)
        switch mutation {
        case .createDataset, .destroyDataset, .renameDataset:
            return composeZFSDatasetMutation(mutation, on: host, targetMounted: request.targetMounted)
        case .snapshot, .destroySnapshot, .rollback, .setMountpoint, .clearMountpoint:
            return composeZFSSnapshotAndPropertyMutation(
                mutation, on: host, targetMounted: request.targetMounted)
        case .mount, .unmount:
            return composeZFSMountMutation(mutation, on: host)
        }
    }

    /// Dataset create / destroy / rename — all operate on the dataset name directly.
    ///
    /// A mounted destroy weaves `sudo -n zfs unmount` ahead of `zfs destroy`
    /// — on Linux, destroying a mounted dataset triggers an implicit unmount
    /// that is root-only for the delegated user (ho-10.4-AT-02). Destroy has
    /// no remount step; the dataset is gone.
    private static func composeZFSDatasetMutation(
        _ mutation: ZFSMutation,
        on host: Runner,
        targetMounted: Bool
    ) -> [PlanStep] {
        switch mutation {
        case .createDataset(let name, let mountpoint):
            let namePart = ShellQuote.quote(name)
            let mountPart = mountpoint.map { " -o mountpoint=\(ShellQuote.quote($0))" } ?? ""
            return [
                PlanStep(
                    runsOn: host, command: "zfs create\(mountPart) \(namePart)", role: .create),
                // name,mounted — on delegated Linux creates, mounting is root's job
                // (ho-06.2 law): the transcript shows 'palana/x  no' rather than
                // implying the dataset is mounted when it may not be.
                PlanStep(
                    runsOn: host,
                    command: "zfs list -H -o name,mounted -- \(namePart)",
                    role: .verify),
            ]
        case .destroyDataset(let name, let recursive):
            let namePart = ShellQuote.quote(name)
            let flag = recursive ? " -r" : ""
            var steps: [PlanStep] = []
            if targetMounted {
                steps.append(
                    PlanStep(
                        runsOn: host, command: "sudo -n zfs unmount \(namePart)", role: .property))
            }
            steps.append(
                PlanStep(runsOn: host, command: "zfs destroy\(flag) \(namePart)", role: .delete))
            steps.append(
                PlanStep(
                    runsOn: host, command: "! zfs list -H -o name -- \(namePart)", role: .verify))
            return steps
        case .renameDataset(let from, let to):
            let fromPart = ShellQuote.quote(from)
            let toPart = ShellQuote.quote(to)
            let verifyCmd =
                "zfs list -H -o name -- \(toPart) && ! zfs list -H -o name -- \(fromPart)"
            return [
                PlanStep(
                    runsOn: host, command: "zfs rename -- \(fromPart) \(toPart)", role: .rename),
                PlanStep(runsOn: host, command: verifyCmd, role: .verify),
            ]
        default:
            return []
        }
    }

    /// Snapshot, destroySnapshot, rollback, setMountpoint, clearMountpoint.
    ///
    /// A mounted set/clear-mountpoint weaves `sudo -n zfs unmount` ahead of
    /// the property change and `sudo -n zfs mount` after it — zfs's implicit
    /// unmount is root-only for the delegated user, and the trailing mount
    /// restores the dataset to mounted at its new path, matching what root
    /// does automatically (ho-10.4-AT-02).
    private static func composeZFSSnapshotAndPropertyMutation(
        _ mutation: ZFSMutation,
        on host: Runner,
        targetMounted: Bool
    ) -> [PlanStep] {
        switch mutation {
        case .snapshot(let dataset, let name, let recursive):
            let full = ShellQuote.quote("\(dataset)@\(name)")
            let flag = recursive ? " -r" : ""
            return [
                PlanStep(runsOn: host, command: "zfs snapshot\(flag) \(full)", role: .snapshot),
                PlanStep(
                    runsOn: host,
                    command: "zfs list -H -o name -t snapshot -- \(full)",
                    role: .verify),
            ]
        case .destroySnapshot(let dataset, let name):
            let full = ShellQuote.quote("\(dataset)@\(name)")
            return [
                PlanStep(runsOn: host, command: "zfs destroy \(full)", role: .delete),
                PlanStep(
                    runsOn: host,
                    command: "! zfs list -H -o name -t snapshot -- \(full)",
                    role: .verify),
            ]
        case .rollback(let dataset, let name, let destroysNewer):
            let full = ShellQuote.quote("\(dataset)@\(name)")
            let flag = destroysNewer ? "-r " : ""
            return [
                PlanStep(runsOn: host, command: "zfs rollback \(flag)\(full)", role: .rollback),
                PlanStep(
                    runsOn: host,
                    command: "zfs list -H -o name -t snapshot -- \(full)",
                    role: .verify),
            ]
        case .setMountpoint(let dataset, let path):
            let dsPart = ShellQuote.quote(dataset)
            let pathPart = ShellQuote.quote(path)
            return mountedWrappedProperty(
                command: "zfs set mountpoint=\(pathPart) \(dsPart)",
                verifyCommand: "zfs get -H -o value mountpoint -- \(dsPart)",
                dsPart: dsPart,
                on: host,
                targetMounted: targetMounted)
        case .clearMountpoint(let dataset):
            let dsPart = ShellQuote.quote(dataset)
            return mountedWrappedProperty(
                command: "zfs inherit mountpoint \(dsPart)",
                verifyCommand: "zfs get -H -o value mountpoint -- \(dsPart)",
                dsPart: dsPart,
                on: host,
                targetMounted: targetMounted)
        default:
            return []
        }
    }

    /// Wraps a `.property` mutation command with the implicit-unmount heal.
    ///
    /// When the target is mounted: `sudo -n zfs unmount` before, `sudo -n
    /// zfs mount` after, restoring the dataset to mounted at its new
    /// mountpoint fact — matching what root does automatically
    /// (ho-10.4-AT-02). Unmounted composes unchanged: the property command
    /// and its verify, nothing woven in.
    private static func mountedWrappedProperty(
        command: String,
        verifyCommand: String,
        dsPart: String,
        on host: Runner,
        targetMounted: Bool
    ) -> [PlanStep] {
        var steps: [PlanStep] = []
        if targetMounted {
            steps.append(
                PlanStep(runsOn: host, command: "sudo -n zfs unmount \(dsPart)", role: .property))
        }
        steps.append(PlanStep(runsOn: host, command: command, role: .property))
        if targetMounted {
            steps.append(
                PlanStep(runsOn: host, command: "sudo -n zfs mount \(dsPart)", role: .property))
        }
        steps.append(PlanStep(runsOn: host, command: verifyCommand, role: .verify))
        return steps
    }

    /// Mount / unmount — the escalation reads in the plan like every other
    /// fact of the command; the verify step stays unprivileged.
    private static func composeZFSMountMutation(
        _ mutation: ZFSMutation,
        on host: Runner
    ) -> [PlanStep] {
        switch mutation {
        case .mount(let dataset):
            let dsPart = ShellQuote.quote(dataset)
            return [
                PlanStep(runsOn: host, command: "sudo -n zfs mount \(dsPart)", role: .property),
                PlanStep(
                    runsOn: host,
                    command: "zfs list -H -o name,mounted -- \(dsPart)",
                    role: .verify),
            ]
        case .unmount(let dataset):
            let dsPart = ShellQuote.quote(dataset)
            return [
                PlanStep(runsOn: host, command: "sudo -n zfs unmount \(dsPart)", role: .property),
                PlanStep(
                    runsOn: host,
                    command: "zfs list -H -o name,mounted -- \(dsPart)",
                    role: .verify),
            ]
        default:
            return []
        }
    }
}
