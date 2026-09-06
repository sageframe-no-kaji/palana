// OperationModel+LocalPlacement — where this Mac's own paths live. A
// local move used to be called an instant rename without any fact; mv
// across volumes is a copy-then-delete, and the plan said "instant"
// over it (2026-09-06 review). The proof is the same one remote hosts
// give — the mount table — read fresh from this machine.

import PalanaCore

extension OperationModel {
    /// The mount table that places a locus: the remembered fact for a
    /// remote host, this Mac's own table read now for the local host.
    func placementMounts(for locus: Locus, remembered: HostFacts?) async -> [Mount]? {
        guard engine.isLocal(locus.host) else { return remembered?.mounts?.value }
        return await localMounts()
    }

    /// This Mac's mount table, read fresh per gather.
    ///
    /// Volumes come and go, and a remembered table could claim a rename
    /// across one that has since arrived. Nil when `mount` fails: an
    /// unproven ground takes the verified copy-then-gated-delete route.
    func localMounts() async -> [Mount]? {
        let command = MountTable.command(forKernel: "Darwin")
        guard
            let result = try? await engine.localConduit
                .run(on: PalanaCore.localHostName, command).collect(),
            result.exitStatus == 0
        else { return nil }
        return MountTable.parseBSD(result.stdoutText)
    }
}
