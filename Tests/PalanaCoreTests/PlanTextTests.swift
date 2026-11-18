// The plan panel's words as plain text (#3), output runs that keep their
// columns (#12), and retained notes that stay one line per path (#10).

import Foundation
import Testing

@testable import PalanaCore

@Suite("PlanText — the panel's words, the copy text, and output runs")
struct PlanTextTests {
    private func entry(_ name: String) -> FileEntry {
        FileEntry(
            nameData: Data(name.utf8),
            kind: .file,
            size: 2048,
            modified: Date(timeIntervalSince1970: 0),
            permissions: "644",
            owner: "op",
            group: "op")
    }

    private func plan(_ operation: PlanOperation = .copy) throws -> Plan {
        try PlanEngine.plan(
            PlanRequest(
                operation: operation,
                source: Locus(host: "jodo", directory: "/tank/media"),
                entries: [entry("a.bin")],
                destination: Locus(host: "koan", directory: "/rpool/cold"),
                token: "t1"),
            facts: PlanFacts(
                sourceCapability: HostCapability(
                    kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.4.1"),
                destinationCapability: HostCapability(
                    kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.4.1"),
                agentForwarding: .available))
    }

    private func chunk(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - The plan's lines

    @Test("the plan's lines run heading, size, collisions, route, transport, notices, a gap, then each step")
    func planLines() throws {
        let plan = try plan()
        let lines = PlanText.planLines(plan, notices: ["a notice"])
        // No collision facts were gathered, so the plan carries that warning.
        let collision = try #require(plan.collisions?.sentence())
        let expected =
            [
                "copy · \(plan.classification.plainName)",
                PlanText.sizeLine(plan),
                collision,
                "jodo:/tank/media → koan:/rpool/cold",
                plan.transport.plainDescription,
                "a notice",
                "",
            ] + plan.steps.map { "$ \($0.command)" }
        #expect(lines == expected)
    }

    @Test("a dataset mutation has no size line")
    func zfsHasNoSize() throws {
        var plan = try plan()
        plan.operation = .zfs
        #expect(!PlanText.planLines(plan).contains(PlanText.sizeLine(plan)))
    }

    @Test("a plan with no destination shows the source alone")
    func routeWithoutDestination() throws {
        var plan = try plan()
        plan.destination = nil
        #expect(PlanText.routeLine(plan) == "jodo:/tank/media")
    }

    @Test("an unmeasured folder makes the size a floor")
    func sizeFloor() throws {
        var plan = try plan()
        plan.totalSizeComplete = false
        #expect(PlanText.sizeLine(plan).hasSuffix("this is a floor — a folder couldn't be measured"))
    }

    @Test("a gated step names the verification it waits on")
    func gatedStep() {
        let step = PlanStep(runsOn: .host("jodo"), command: "rm -rf /x", role: .delete, gatedOnVerification: true)
        #expect(PlanText.stepLine(step) == "  runs only after the copy above is verified: $ rm -rf /x")
    }

    // MARK: - The copy text (#3)

    @Test("the copy text is the plan, a gap, then every transcript line in order")
    func clipboardPlanAndOutput() throws {
        let plan = try plan()
        var echo = EchoBuffer()
        echo.appendLine("$ rsync …", kind: .command)
        echo.append(chunk("first\nsecond\n"), channel: .stdout)
        let text = PlanText.clipboardText(plan: plan, echo: echo)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.first == PlanText.heading(plan))
        #expect(Array(lines.suffix(3)) == ["$ rsync …", "first", "second"])
        #expect(lines.contains("$ \(plan.steps[0].command)"))
    }

    @Test("an empty buffer copies the plan alone, with no trailing blank lines")
    func clipboardEmptyBuffer() throws {
        let plan = try plan()
        let text = PlanText.clipboardText(plan: plan, echo: EchoBuffer())
        let last = try #require(plan.steps.last)
        #expect(text.hasSuffix("$ \(last.command)"))
    }

    @Test("a live partial line is copied too")
    func clipboardLivePartial() {
        var echo = EchoBuffer()
        echo.append(chunk("done line\n12,345  40%"), channel: .stdout)
        let text = PlanText.clipboardText(plan: nil, echo: echo)
        #expect(text == "done line\n12,345  40%")
    }

    @Test("dropped lines are announced before the kept ones")
    func clipboardDroppedLines() {
        var echo = EchoBuffer(cap: 2)
        for index in 1...5 { echo.appendLine("line \(index)", kind: .note) }
        let text = PlanText.clipboardText(plan: nil, echo: echo)
        #expect(text.hasPrefix("… \(echo.droppedLines) earlier lines\n"))
        #expect(text.hasSuffix("line 5"))
    }

    // MARK: - Output runs (#12)

    @Test("consecutive output lines group into one run; the panel's own lines into another")
    func runs() {
        var echo = EchoBuffer()
        echo.appendLine("$ zpool status", kind: .command)
        echo.append(chunk("  pool: tank\n  state: ONLINE\n"), channel: .stdout)
        echo.append(chunk("warning\n"), channel: .stderr)
        echo.appendLine("done", kind: .note)
        let runs = PlanText.runs(echo.lines)
        #expect(runs.map(\.isOutput) == [false, true, false])
        #expect(runs[1].lines.map(\.text) == ["  pool: tank", "  state: ONLINE", "warning"])
        #expect(runs[1].id == runs[1].lines[0].id)
        #expect(PlanText.runs([]).isEmpty)
    }

    // MARK: - Retained notes stay one line (#10)

    @Test("line breaks in a retained path are written out")
    func displayPath() {
        #expect(PlanEngine.retainedDisplayPath("/a\nb\rc") == "/a\\nb\\rc")
        #expect(PlanEngine.retainedDisplayPath("/plain") == "/plain")
    }

    @Test(
        "a retained path with a newline is one note under sh and dash",
        arguments: ["/bin/sh", "/bin/dash"])
    func newlinePathOneNote(shell: String) throws {
        guard FileManager.default.isExecutableFile(atPath: shell) else { return }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-newline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let odd = root.appendingPathComponent("two\nlines.txt")
        let plain = root.appendingPathComponent("it's here.txt")
        try Data("x".utf8).write(to: odd)
        try Data("x".utf8).write(to: plain)
        let gone = root.appendingPathComponent("gone.txt").path

        let command = PlanEngine.leftoverSourceReport(
            sources: [odd.path, plain.path, gone], host: "local")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", command]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(bytes: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let notes = output.split(separator: "\n").map(String.init)

        #expect(process.terminationStatus != 0)
        #expect(notes.count == 2)
        #expect(notes[0].contains("two\\nlines.txt"))
        #expect(notes[1].contains("it's here.txt"))
        #expect(notes.allSatisfy { $0.hasPrefix("palana-retained: local:") })
    }
}
