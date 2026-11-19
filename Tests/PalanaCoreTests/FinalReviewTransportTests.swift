// The 2026-11-18 final review's F06 and F11, live on this Mac.
//
// F06: the direct tar fallback (one end here, the other without rsync)
// must fail when the sending tar fails, not report the partial copy as
// done. The far end is a stand-in ssh that runs the command here.
//
// F11: a legal file name holding an option-shaped word is an operand;
// the enactment check must judge what the shell passes as arguments,
// and still find a source-removal option wherever one is really passed.

import Foundation
import Testing

@testable import PalanaCore

private func file(_ name: String) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: .file,
        size: 1,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

private func enact(_ plan: Plan) async -> (any Error)? {
    do {
        for try await _ in Transports(conduit: LocalConduit()) { _, _, _ in 0 }.enact(plan) {}
        return nil
    } catch {
        return error
    }
}

/// A scratch tree with `from/` and `to/`, and a stand-in ssh on PATH.
private struct TarScratch {
    let root: URL
    var from: URL { root.appendingPathComponent("from") }
    var to: URL { root.appendingPathComponent("to") }
    let fakeBin: URL

    init() throws {
        root = try ProcessFixture.makeDirectory()
        fakeBin = root.appendingPathComponent("bin")
        for directory in [from, to, fakeBin] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let fake = try ProcessFixture.fakeSSH(in: fakeBin)
        try FileManager.default.moveItem(atPath: fake, toPath: fakeBin.appendingPathComponent("ssh").path)
    }

    /// The composed direct-tar plan, pushing (`here → koan`) or pulling,
    /// with the stand-in ssh first on PATH for its one step.
    func plan(pushing: Bool, names: [String]) throws -> Plan {
        let here = Locus(host: PalanaCore.localHostName, directory: pushing ? from.path : to.path)
        let far = Locus(host: "koan", directory: pushing ? to.path : from.path)
        let bare = HostCapability(kernel: "Linux", flavor: .bsd, zfs: nil, rsync: nil)
        var plan = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: pushing ? here : far,
                entries: names.map(file),
                destination: pushing ? far : here),
            facts: pushing ? PlanFacts(destinationCapability: bare) : PlanFacts(sourceCapability: bare))
        #expect(plan.transport == .tarStreamDirect)
        plan.steps[0].command = "PATH=\(ShellQuote.quote(fakeBin.path)):$PATH; " + plan.steps[0].command
        return plan
    }

    func exists(_ url: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path)
    }
}

@Suite("Final review F06 — direct tar fallback statuses", .serialized)
struct FinalReviewTarStatusTests {
    @Test(
        "a selected file vanishing after approval fails the copy, pushing and pulling, and a clean copy still lands",
        arguments: [true, false])
    func producerFailureFails(pushing: Bool) async throws {
        let scratch = try TarScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try Data("x".utf8).write(to: scratch.from.appendingPathComponent("found"))
        try Data("y".utf8).write(to: scratch.from.appendingPathComponent("vanishes"))
        let plan = try scratch.plan(pushing: pushing, names: ["vanishes", "found"])
        try FileManager.default.removeItem(at: scratch.from.appendingPathComponent("vanishes"))

        let error = await enact(plan)
        guard case EnactmentError.stepFailed(_, _, let stderrTail)? = error else {
            Issue.record("a partial tar copy must fail, got \(String(describing: error))")
            return
        }
        #expect(stderrTail.contains("the copy is incomplete"))
        #expect(scratch.exists(scratch.to, "found"), "what did arrive stays; the failure names the rest")

        // The next copy, with every file present, succeeds.
        try Data("z".utf8).write(to: scratch.from.appendingPathComponent("second"))
        #expect(await enact(try scratch.plan(pushing: pushing, names: ["second"])) == nil)
        #expect(scratch.exists(scratch.to, "second"))
    }

    @Test("a failing unpack keeps failing the copy")
    func consumerFailureFails() async throws {
        let scratch = try TarScratch()
        defer { try? FileManager.default.removeItem(at: scratch.root) }
        try Data("x".utf8).write(to: scratch.from.appendingPathComponent("a"))
        let plan = try scratch.plan(pushing: true, names: ["a"])
        try FileManager.default.removeItem(at: scratch.to)
        #expect(await enact(plan) != nil)
    }
}

@Suite("Final review F11 — option-shaped words inside file names")
struct FinalReviewOptionShapedNameTests {
    @Test("a name holding an option-shaped word is an operand in every composed command shape")
    func quotedOperandsAreNotOptions() {
        for command in [
            "rm -rf '/folder/a --remove-source-files b'",
            "rsync -a '/src/a --remove-sent-files b' /dst/",
            "tar -cf - -C /src -- 'a --remove-source-files b' '--remove-sent-files'",
            "ssh koan 'tar -cf - -C /r -- a.txt '\\''a --remove-source-files b'\\'''",
            "ssh -- koan 'rm -rf '\\''/r/x --remove-sent-files y'\\'''",
        ] {
            #expect(!PlanEngine.commandNamesSourceRemoval(command), "\(command)")
        }
    }

    @Test("a source-removal option is still found bare, abbreviated, quoted, or carried by ssh or sh -c")
    func realOptionsAreFound() {
        for command in [
            "rsync -a --remove-source-files /a /b",
            "'/opt/homebrew/bin/rsync' -a --rem /a /b",
            "rsync -a '--remove-source-files' /a /b",
            "rsync -a --rem'ove-sent-files' /a /b",
            "ssh koan 'rsync -a --remove-sent-files /a /b'",
            "ssh -- koan rsync -a --remove-source-files /a /b",
            "sh -c 'rsync --remove-source-files /a /b'",
            "true; rsync --remove-source-files /a /b",
            "ssh koan \"ssh other 'rsync --remove-source-files /a /b'\"",
        ] {
            #expect(PlanEngine.commandNamesSourceRemoval(command), "\(command)")
        }
    }

    @Test("deleting, then copying, a file whose name holds an option-shaped word both run")
    func approvedDeleteAndCopyRun() async throws {
        let root = try ProcessFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "a --remove-source-files b"
        let source = root.appendingPathComponent("from")
        let target = root.appendingPathComponent("to")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: source.appendingPathComponent(name))
        let here = PalanaCore.localHostName

        let copy = try PlanEngine.plan(
            PlanRequest(
                operation: .copy,
                source: Locus(host: here, directory: source.path),
                entries: [file(name)],
                destination: Locus(host: here, directory: target.path)),
            facts: PlanFacts())
        #expect(await enact(copy) == nil)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent(name).path))

        let delete = try PlanEngine.plan(
            PlanRequest(
                operation: .delete,
                source: Locus(host: here, directory: source.path),
                entries: [file(name)],
                destination: nil),
            facts: PlanFacts())
        #expect(await enact(delete) == nil)
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent(name).path))
    }
}
