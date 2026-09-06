// Host aliases inside composed shell text. An alias in the grammar is
// bare, as every existing composition test expects; one outside it —
// data that never passed the parser — is quoted and led by `--`, so a
// pasted command hands ssh the same host and command the structured
// Pipeline carries, and never an option or a second command. The paste
// itself is exercised: /bin/sh runs the displayed text against an ssh
// that records what it was handed.

import Foundation
import Testing

@testable import PalanaCore

private func makeEntry(_ name: String, kind: FileEntry.Kind = .file, size: Int64 = 0) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

@Suite("PlanEngine host aliases")
struct PlanHostAliasTests {
    private let injecting = "jodo;touch /tmp/pwned"
    private let optionShaped = "-oProxyCommand=evil"
    private let hostileSource = Locus(host: "jodo;touch /tmp/pwned", directory: "/tank/media")
    private let hostileDest = Locus(host: "-oProxyCommand=evil", directory: "/rpool/cold")
    private let here = Locus(host: PalanaCore.localHostName, directory: "/Users/op")
    private let oneFile = [makeEntry("a.txt", size: 100)]
    private let zfs = HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil)
    private let rsync = HostCapability(
        kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")

    private func plan(
        _ operation: PlanOperation,
        from source: Locus,
        to destination: Locus,
        entries: [FileEntry]? = nil,
        facts: PlanFacts = PlanFacts()
    ) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: source,
                entries: entries ?? oneFile,
                destination: destination,
                token: "t1"),
            facts: facts)
    }

    @Test("the grammar's aliases stay bare; everything else is quoted behind --")
    func destinationForms() {
        #expect(PlanEngine.sshDestination("jodo") == "jodo")
        #expect(PlanEngine.sshDestination("koan.lan-2_x") == "koan.lan-2_x")
        #expect(PlanEngine.sshDestination(injecting) == "-- 'jodo;touch /tmp/pwned'")
        #expect(PlanEngine.sshDestination(optionShaped) == "-- '-oProxyCommand=evil'")
        #expect(PlanEngine.sshDestination("a b") == "-- 'a b'")
        #expect(PlanEngine.sshDestination("") == "-- ''")
        #expect(PlanEngine.rsyncPathGuard(for: "jodo").isEmpty)
        #expect(PlanEngine.rsyncPathGuard(for: optionShaped) == "-- ")
    }

    @Test("the proxied tar display is the pipeline's own parts, quoted")
    func proxiedTar() throws {
        let plan = try plan(.copy, from: hostileSource, to: hostileDest)
        #expect(plan.transport == .tarStreamProxied)
        let step = try #require(plan.steps.first)
        #expect(
            step.command
                == "ssh -- 'jodo;touch /tmp/pwned' 'tar -cf - -C /tank/media -- a.txt' | "
                + "ssh -- '-oProxyCommand=evil' 'tar -xpf - -C /rpool/cold'")
        let pipeline = try #require(step.pipeline)
        #expect(pipeline.fromHost == injecting)
        #expect(pipeline.toHost == optionShaped)
        #expect(PlanEngine.pipelineCommand(pipeline) == step.command)
    }

    @Test("the direct tar routes quote the far host, pushing and pulling")
    func directTar() throws {
        let push = try plan(.copy, from: here, to: hostileDest)
        #expect(push.transport == .tarStreamDirect)
        #expect(
            push.steps.first?.command
                == "tar -cf - -C /Users/op -- a.txt | ssh -- '-oProxyCommand=evil' 'tar -xpf - -C /rpool/cold'")
        let pull = try plan(.copy, from: hostileSource, to: here)
        #expect(pull.transport == .tarStreamDirect)
        #expect(
            pull.steps.first?.command
                == "ssh -- 'jodo;touch /tmp/pwned' 'tar -cf - -C /tank/media -- a.txt' | tar -xpf - -C /Users/op")
    }

    private var zfsFacts: PlanFacts {
        PlanFacts(
            sourceDataset: ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            destinationDataset: ZFSDataset(name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
            selectionWholeDataset: ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true),
            sourceCapability: zfs,
            destinationCapability: zfs)
    }

    @Test("the forwarded zfs display quotes the receiving host")
    func forwardedZfs() throws {
        var facts = zfsFacts
        facts.agentForwarding = .available
        let plan = try plan(
            .copy,
            from: hostileSource,
            to: hostileDest,
            entries: [makeEntry("media", kind: .directory)],
            facts: facts)
        #expect(plan.transport == .zfsSendReceiveForwarded)
        #expect(
            plan.steps[1].command
                == "zfs send -R -v tank/media@t1 | ssh -- '-oProxyCommand=evil' 'zfs receive -u rpool/cold/media'")
    }

    @Test("the proxied zfs display is the pipeline's own parts, quoted")
    func proxiedZfs() throws {
        let plan = try plan(
            .copy,
            from: hostileSource,
            to: hostileDest,
            entries: [makeEntry("media", kind: .directory)],
            facts: zfsFacts)
        #expect(plan.transport == .zfsSendReceiveProxied)
        let step = plan.steps[1]
        #expect(
            step.command
                == "ssh -- 'jodo;touch /tmp/pwned' 'zfs send -R -v tank/media@t1' | "
                + "ssh -- '-oProxyCommand=evil' 'zfs receive -u rpool/cold/media'")
        let pipeline = try #require(step.pipeline)
        #expect(PlanEngine.pipelineCommand(pipeline) == step.command)
    }

    @Test("rsync's remote spec cannot read as an option: -- precedes the paths")
    func rsyncGuard() throws {
        let forwardedFacts = PlanFacts(
            sourceCapability: rsync, destinationCapability: rsync, agentForwarding: .available)
        let forwarded = try plan(
            .copy,
            from: Locus(host: "jodo", directory: "/tank/media"),
            to: hostileDest,
            facts: forwardedFacts)
        #expect(forwarded.transport == .rsyncAgentForwarded)
        #expect(
            forwarded.steps.first?.command
                == "rsync -a -s --partial --info=progress2 -- /tank/media/a.txt '-oProxyCommand=evil:/rpool/cold/'")
        let direct = try plan(
            .copy,
            from: here,
            to: hostileDest,
            facts: PlanFacts(sourceCapability: rsync, destinationCapability: rsync))
        #expect(direct.transport == .rsyncDirect)
        #expect(
            direct.steps.first?.command
                == "rsync -a -s --partial --info=progress2 -- /Users/op/a.txt '-oProxyCommand=evil:/rpool/cold/'")
        let clean = try plan(
            .copy,
            from: Locus(host: "jodo", directory: "/tank/media"),
            to: Locus(host: "koan", directory: "/rpool/cold"),
            facts: forwardedFacts)
        #expect(
            clean.steps.first?.command
                == "rsync -a -s --partial --info=progress2 /tank/media/a.txt koan:/rpool/cold/")
    }

    @Test("pasted, the displayed pipeline hands ssh the raw alias as a destination and runs nothing else")
    func pasteIsEquivalent() async throws {
        let directory = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("argv.log")
        let recorder = try ControlSocketFixture.recordingSSH(in: directory, log: log, executes: false)
        let marker = directory.appendingPathComponent("pwned").path
        let source = Locus(host: "jodo;touch \(marker)", directory: "/tank/media")
        let plan = try plan(.copy, from: source, to: hostileDest)
        let step = try #require(plan.steps.first)
        let pipeline = try #require(step.pipeline)

        // The paste: the displayed text, run by /bin/sh with the
        // recording ssh first on PATH.
        let shell = "PATH=\(ShellQuote.quote(directory.path)):\"$PATH\"; export PATH; \(step.command)"
        try FileManager.default.copyItem(atPath: recorder, toPath: directory.appendingPathComponent("ssh").path)
        let result = try await SSHConduit.spawn(executable: "/bin/sh", arguments: ["-c", shell]).collect()
        #expect(result.exitStatus == 0)

        // The two halves of a pipe start together; either may log first.
        let calls = ControlSocketFixture.invocations(in: log)
        #expect(calls.count == 2)
        #expect(calls.contains(["--", pipeline.fromHost, pipeline.fromCommand]))
        #expect(calls.contains(["--", pipeline.toHost, pipeline.toCommand]))
        #expect(!FileManager.default.fileExists(atPath: marker))
    }
}
