// The 2026-11-18 final review's F03 (owner ruling: fence and prove).
//
// No ZFS pool is reachable from this suite, so the fence and the guarded
// release run as composed under /bin/sh and dash against a stand-in `zfs`
// that answers from a scratch state directory and logs every call. This
// proves the programs' control flow — which commands run, in what order,
// and what each refusal leaves — not real ZFS semantics; `written@` and
// `zfs unmount` themselves are exercised only by the gated ZFS fixture.

import Foundation
import Testing

@testable import PalanaCore

/// A scratch world for the stand-in `zfs`.
private struct ZFSStandIn {
    let root: URL
    var state: URL { root.appendingPathComponent("state") }
    var bin: URL { root.appendingPathComponent("bin") }

    init(tree: [(String, Bool)], busy: [String] = [], written: [String] = ["0"], getFails: Bool = false) throws {
        root = try ProcessFixture.makeDirectory()
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let listing = tree.sorted { $0.0 > $1.0 }.map { "\($0.0)\t\($0.1 ? "yes" : "no")" }
        try (listing.joined(separator: "\n") + "\n").write(
            to: state.appendingPathComponent("tree"), atomically: true, encoding: .utf8)
        try (busy.joined(separator: "\n") + "\n").write(
            to: state.appendingPathComponent("busy"), atomically: true, encoding: .utf8)
        try (written.joined(separator: "\n") + "\n").write(
            to: state.appendingPathComponent("written"), atomically: true, encoding: .utf8)
        if getFails { try Data().write(to: state.appendingPathComponent("getfail")) }
        let script = """
            #!/bin/sh
            S="$ZFS_STATE"
            printf '%s\\n' "$*" >> "$S/log"
            case "$1" in
            list) cat "$S/tree" ;;
            unmount) if grep -qxF -- "$2" "$S/busy"; then echo "cannot unmount '$2': busy" >&2; exit 1; fi ;;
            get) [ -f "$S/getfail" ] && exit 1; cat "$S/written"
                # Real `zfs get -r` lists snapshots unless -t narrows it, and
                # a snapshot's written@ against itself reads "-" (OpenZFS
                # 2.2.2; reproduced on the fixture pool, pass 2 F03).
                case " $* " in *" -t filesystem,volume "*) ;; *) sed 's/.*/-/' "$S/written" ;; esac ;;
            esac
            exit 0

            """
        let zfs = bin.appendingPathComponent("zfs")
        try script.write(to: zfs, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: zfs.path)
        // sudo -n stands aside: it logs that it was asked, then runs the command.
        let sudo = bin.appendingPathComponent("sudo")
        try "#!/bin/sh\nprintf 'sudo %s\\n' \"$*\" >> \"$ZFS_STATE/log\"\nshift\nexec \"$@\"\n".write(
            to: sudo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sudo.path)
    }

    /// Runs `program` under `shell` with the stand-in first on PATH.
    func run(_ program: String, shell: String = "/bin/sh") throws -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", program]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = bin.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["ZFS_STATE"] = state.path
        process.environment = environment
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    /// Every stand-in call, in order.
    var calls: [String] {
        ((try? String(contentsOf: state.appendingPathComponent("log"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
    }

    func tearDown() { try? FileManager.default.removeItem(at: root) }
}

private let shells = ["/bin/sh", "/bin/dash"].filter { FileManager.default.isExecutableFile(atPath: $0) }

@Suite("Final review F03 — the ZFS move's fence and proof")
struct FinalReviewZFSReleaseTests {
    private let fence = ZFSReleaseGuard.fenceCommand(host: "jodo", dataset: "tank/media")
    private let release = ZFSReleaseGuard.guardedSourceRelease(host: "jodo", dataset: "tank/media", token: "t1")

    @Test(
        "the fence unmounts every mounted dataset, children first, and leaves unmounted ones alone", arguments: shells)
    func fenceUnmountsTree(shell: String) throws {
        let world = try ZFSStandIn(tree: [
            ("tank/media", true), ("tank/media/photos", true), ("tank/media/raw", false),
        ])
        defer { world.tearDown() }
        let result = try world.run(fence, shell: shell)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(
            world.calls == [
                "list -H -o name,mounted -r -S name tank/media",
                "sudo -n zfs unmount tank/media/photos",
                "unmount tank/media/photos",
                "sudo -n zfs unmount tank/media",
                "unmount tank/media",
            ])
        #expect(result.stderr.contains("tank/media is unmounted for the move"))
    }

    @Test(
        "a busy dataset stops the move before anything is sent, and what was unmounted is mounted again",
        arguments: shells)
    func busyFenceRefusesAndRemounts(shell: String) throws {
        let world = try ZFSStandIn(
            tree: [("tank/media", true), ("tank/media/a", true), ("tank/media/b", true)],
            busy: ["tank/media"])
        defer { world.tearDown() }
        let result = try world.run(fence, shell: shell)
        #expect(result.status == 1)
        #expect(result.stderr.contains("palana-refused: jodo:tank/media — a dataset in it could not be unmounted"))
        #expect(!result.stderr.contains("is unmounted for the move"))
        #expect(
            world.calls.filter { !$0.hasPrefix("sudo ") } == [
                "list -H -o name,mounted -r -S name tank/media",
                "unmount tank/media/b",
                "unmount tank/media/a",
                "unmount tank/media",
                "mount tank/media/a",
                "mount tank/media/b",
            ])
        #expect(world.calls.contains("sudo -n zfs mount tank/media/a"))
    }

    @Test("an unreadable tree stops the fence")
    func unreadableTreeStops() throws {
        let world = try ZFSStandIn(tree: [])
        defer { world.tearDown() }
        let program = fence.replacingOccurrences(of: "zfs list", with: "false && zfs list")
        #expect(try world.run(program).status == 1)
        #expect(!world.calls.contains { $0.hasPrefix("unmount") })
    }

    @Test("nothing written since the snapshot: the source is destroyed", arguments: shells)
    func quiescentSourceReleased(shell: String) throws {
        let world = try ZFSStandIn(tree: [("tank/media", false)], written: ["0", "0"])
        defer { world.tearDown() }
        let result = try world.run(release, shell: shell)
        #expect(result.status == 0, "\(result.stderr)")
        #expect(
            world.calls == [
                "get -t filesystem,volume -H -p -r -o value written@t1 tank/media", "destroy -r tank/media",
            ])
    }

    @Test("the proof reads live datasets only: an unrestricted query would see the operation's own snapshot")
    func operationSnapshotIsNotEvidence() throws {
        let world = try ZFSStandIn(tree: [("tank/media", false)], written: ["0"])
        defer { world.tearDown() }
        // The pass-1 program, without -t: the stand-in answers as OpenZFS
        // does, with the @t1 snapshot's "-" row, and the clean move fails.
        let unrestricted = release.replacingOccurrences(of: "zfs get -t filesystem,volume ", with: "zfs get ")
        #expect(try world.run(unrestricted).status == ZFSReleaseGuard.sourceKeptExitStatus)
        #expect(try world.run(release).status == 0)
    }

    @Test(
        "written to, a newer child, or unreadable: the source is kept and named, never destroyed",
        arguments: [(["0", "4096"], false), (["0", "-"], false), (["0"], true), ([], false)])
    func changedSourceKept(written: [String], getFails: Bool) throws {
        let world = try ZFSStandIn(tree: [("tank/media", false)], written: written, getFails: getFails)
        defer { world.tearDown() }
        let program = written.isEmpty ? release.replacingOccurrences(of: "zfs get", with: "true || zfs get") : release
        let result = try world.run(program)
        #expect(result.status == ZFSReleaseGuard.sourceKeptExitStatus)
        #expect(!world.calls.contains { $0.hasPrefix("destroy") })
        let notes = RecoveryNote.notes(in: result.stderr, host: "jodo")
        #expect(notes.count == 1)
        #expect(notes.first?.kind == .retained)
        #expect(notes.first?.detail.hasPrefix("jodo:tank/media — ") == true)
        #expect(notes.first?.detail.contains("zfs mount brings it back") == true)
    }

    @Test("a whole move in sequence: fence, then a release that finds a write, keeps the source")
    func successiveFenceThenRefusedRelease() throws {
        let world = try ZFSStandIn(tree: [("tank/media", true)], written: ["12"])
        defer { world.tearDown() }
        #expect(try world.run(fence).status == 0)
        #expect(try world.run(release).status == ZFSReleaseGuard.sourceKeptExitStatus)
        #expect(!world.calls.contains { $0.hasPrefix("destroy") })
        #expect(world.calls.first { $0.hasPrefix("unmount") } == "unmount tank/media")
    }

    @Test("both programs parse under every shell here")
    func programsParse() throws {
        for shell in shells {
            for program in [fence, release] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: shell)
                process.arguments = ["-n", "-c", program]
                try process.run()
                process.waitUntilExit()
                #expect(process.terminationStatus == 0, "\(shell)")
            }
        }
    }
}

@Suite("Final review F03 — the composed move and its binding")
struct FinalReviewZFSMovePlanTests {
    private func facts() -> PlanFacts {
        PlanFacts(
            sourceDataset: ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true),
            destinationDataset: ZFSDataset(name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true),
            selectionWholeDataset: ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true),
            sourceCapability: HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
            destinationCapability: HostCapability(kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: nil),
            agentForwarding: .available)
    }

    private func plan(_ operation: PlanOperation) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: Locus(host: "jodo", directory: "/tank"),
                entries: [
                    FileEntry(
                        nameData: Data("media".utf8),
                        kind: .directory,
                        size: 0,
                        modified: Date(timeIntervalSince1970: 0),
                        permissions: "755",
                        owner: "op",
                        group: "op")
                ],
                destination: Locus(host: "koan", directory: "/rpool/cold"),
                token: "t1"),
            facts: facts())
    }

    @Test("a move fences before its snapshot and releases through the proof; a copy is unchanged")
    func composition() throws {
        let move = try plan(.move)
        #expect(move.steps.map(\.role) == [.snapshot, .snapshot, .transfer, .cleanup, .delete])
        #expect(move.steps[0].command == ZFSReleaseGuard.fenceCommand(host: "jodo", dataset: "tank/media"))
        #expect(move.steps[1].command == "zfs snapshot -r tank/media@t1")
        #expect(
            move.steps[4].command
                == ZFSReleaseGuard.guardedSourceRelease(host: "jodo", dataset: "tank/media", token: "t1"))
        #expect(move.steps.filter(\.gatedOnVerification) == move.zfsReleaseGuard?.releaseSteps)
        let copy = try plan(.copy)
        #expect(copy.steps.map(\.role) == [.snapshot, .transfer, .cleanup, .cleanup])
        #expect(!copy.steps.contains { $0.command.contains("unmount") || $0.command.contains("written@") })
    }

    @Test("enactment runs the fence first and, when the proof keeps the source, fails with the retained note")
    func enactmentKeepsChangedSource() async throws {
        let move = try plan(.move)
        let verify = "zfs list -H -o name rpool/cold/media"
        let kept =
            "palana-retained: jodo:tank/media — it was written to after the snapshot that was sent, so the source"
            + " is kept · it is unmounted · zfs mount brings it back\n"
        var entries = move.steps.map { step in
            ConduitTranscript.Entry(
                host: step.runsOn == .host("koan") ? "koan" : "jodo",
                command: step.command,
                stdout: "",
                stderr: step.role == .delete ? kept : "",
                exit: step.role == .delete ? ZFSReleaseGuard.sourceKeptExitStatus : 0)
        }
        entries.append(.init(host: "koan", command: verify, stdout: "rpool/cold/media\n", stderr: "", exit: 0))
        let conduit = RecordedConduit(transcript: ConduitTranscript(entries: entries))
        var events: [EnactmentEvent] = []
        await #expect(throws: EnactmentError.self) {
            for try await event in Transports(conduit: conduit) { _, _, _ in 0 }.enact(move) {
                events.append(event)
            }
        }
        let began = events.compactMap { event -> Int? in
            if case .stepBegan(let index, _) = event { return index }
            return nil
        }
        #expect(began == [0, 1, 2, 3, 4])
        #expect(
            events.contains { event in
                if case .recovery(let note) = event { return note.detail.hasPrefix("jodo:tank/media — ") }
                return false
            })
    }
}
