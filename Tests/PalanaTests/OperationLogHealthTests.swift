// The operation log's health. Every failure to record used to be
// swallowed — a full disk erased the run record with no one told. Now
// each stage's failure is retained, the first one named, all of them
// counted, and flush and close are explicit. Nothing here touches the
// operator's application-support directory.

import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class OperationLogHealthTests: XCTestCase {
    private var directory = URL(fileURLWithPath: "/")
    private var logURL: URL { directory.appendingPathComponent("operations.log") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-log-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // A read-only directory left behind cannot be removed; open it first.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func scriptedLog(_ sink: ScriptedLogSink) -> OperationLog {
        OperationLog(url: logURL) { _ in sink }
    }

    // MARK: - The real handle

    func testHealthyLogAppendsFlushesAndClosesThroughARealHandle() throws {
        let log = OperationLog(url: logURL)
        log.appendLine("first")
        log.appendRaw("raw\n")
        log.flush()
        log.close()
        XCTAssertTrue(log.isHealthy)
        XCTAssertNil(log.warning)
        XCTAssertNil(log.failure)
        XCTAssertEqual(log.failureCount, 0)
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "first\nraw\n")

        // A write after close reopens and appends — the record continues.
        log.appendLine("after")
        log.close()
        XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "first\nraw\nafter\n")
        XCTAssertTrue(log.isHealthy)
    }

    func testRealHandleWriteFailureIsRetained() {
        // A handle opened read-only refuses the write the way a full disk does.
        let log = OperationLog(url: logURL) { try FileHandle(forReadingFrom: $0) }
        log.appendLine("lost")
        XCTAssertEqual(log.failure?.stage, .write)
        XCTAssertFalse(log.isHealthy)
        XCTAssertEqual(try? String(contentsOf: logURL, encoding: .utf8), "")
    }

    func testDirectoryFailureIsRetainedAndNamesThePath() throws {
        // The would-be directory is a regular file; nothing can be created under it.
        let blocker = directory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent("operations.log")
        let log = OperationLog(url: url)
        log.appendLine("lost")
        XCTAssertEqual(log.failure?.stage, .directory)
        XCTAssertEqual(log.failureCount, 1)
        let warning = try XCTUnwrap(log.warning)
        XCTAssertTrue(warning.hasPrefix("the run record is incomplete — directory failed: "))
        XCTAssertTrue(warning.hasSuffix(url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFileCreationFailureIsRetained() throws {
        // A directory that exists but refuses new files — the permission case.
        try XCTSkipIf(geteuid() == 0, "root creates files anywhere; the permission case cannot be shown")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let log = OperationLog(url: logURL)
        log.appendLine("lost")
        XCTAssertEqual(log.failure, OperationLog.Failure(stage: .open, detail: "the file could not be created"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    // MARK: - Scripted stages

    func testOpenFailureIsRetainedAndRetriedOnTheNextWrite() {
        var attempts = 0
        let log = OperationLog(url: logURL) { _ in
            attempts += 1
            throw ScriptedLogSink.Scripted(step: "open")
        }
        log.appendLine("one")
        log.appendLine("two")
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(log.failure, OperationLog.Failure(stage: .open, detail: "scripted open failure"))
        XCTAssertEqual(log.failureCount, 2)
        XCTAssertEqual(log.warning?.contains("(2 failures)"), true)
    }

    func testSeekFailureIsRetainedAndWritesNothing() {
        let sink = ScriptedLogSink()
        sink.failSeek = true
        let log = scriptedLog(sink)
        log.appendLine("lost")
        XCTAssertEqual(log.failure?.stage, .seek)
        XCTAssertEqual(sink.written.count, 0)
    }

    func testWriteFailureIsRetainedAndTheFirstFailureIsKept() {
        let sink = ScriptedLogSink()
        sink.failWrite = true
        let log = scriptedLog(sink)
        log.appendLine("lost")
        sink.failWrite = false
        sink.failFlush = true
        log.appendLine("kept")
        log.flush()
        XCTAssertEqual(log.failure, OperationLog.Failure(stage: .write, detail: "scripted write failure"))
        XCTAssertEqual(log.failureCount, 2)
        XCTAssertEqual(sink.text, "kept\n")
        XCTAssertEqual(log.warning?.contains("write failed"), true)
        XCTAssertEqual(log.warning?.contains("(2 failures)"), true)
    }

    func testFlushFailureIsRetained() {
        let sink = ScriptedLogSink()
        sink.failFlush = true
        let log = scriptedLog(sink)
        log.appendLine("line")
        log.flush()
        XCTAssertEqual(sink.synchronizeCount, 1)
        XCTAssertEqual(log.failure?.stage, .flush)
        XCTAssertEqual(sink.text, "line\n")
    }

    func testCloseFailureIsRetainedAndTheHandleIsReleased() {
        let sink = ScriptedLogSink()
        sink.failClose = true
        var opens = 0
        let log = OperationLog(url: logURL) { _ in
            opens += 1
            return sink
        }
        log.appendLine("line")
        log.close()
        XCTAssertEqual(sink.closeCount, 1)
        XCTAssertEqual(log.failure?.stage, .close)
        // Released regardless: the next write opens afresh.
        log.appendLine("again")
        XCTAssertEqual(opens, 2)
    }

    func testFlushAndCloseWithoutAnOpenHandleDoNothing() {
        var opens = 0
        let log = OperationLog(url: logURL) { _ in
            opens += 1
            return ScriptedLogSink()
        }
        log.flush()
        log.close()
        log.appendRaw("")
        XCTAssertEqual(opens, 0)
        XCTAssertTrue(log.isHealthy)
    }

    func testDeinitClosesTheHandle() {
        let sink = ScriptedLogSink()
        var log: OperationLog? = scriptedLog(sink)
        log?.appendLine("line")
        XCTAssertEqual(sink.closeCount, 0)
        log = nil
        XCTAssertEqual(sink.closeCount, 1)
    }

    // MARK: - Header

    func testHeaderLineNamesVerbAndRoute() {
        let plan = Plan(
            operation: .copy,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: Locus(host: "jodo", directory: "/tank/a"),
            destination: Locus(host: "chumon", directory: "/tank/b"),
            transport: .local,
            steps: [])
        let line = OperationLog.headerLine(for: plan)
        XCTAssertTrue(line.hasPrefix("── "))
        XCTAssertTrue(line.hasSuffix(" · copy · jodo:/tank/a → chumon:/tank/b"))

        let deletion = Plan(
            operation: .delete,
            classification: .withinHostCopy,
            entries: [],
            totalSize: 0,
            source: Locus(host: "jodo", directory: "/tank/a"),
            destination: nil,
            transport: .local,
            steps: [])
        XCTAssertTrue(OperationLog.headerLine(for: deletion).hasSuffix(" · delete · jodo:/tank/a"))
    }
}
