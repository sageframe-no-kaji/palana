// Controllable local child processes for the ownership tests. Every
// process here is a shell on this machine writing into a fresh
// temporary directory — no host, no wire, nothing the tests cannot
// kill. The fake ssh stands in for the binary so the pipeline's two
// halves can be spawned exactly as the Transports spawn them.

import Foundation

@testable import PalanaCore

enum ProcessFixture {
    /// A fresh directory for pid files, markers, and the fake ssh.
    static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-process-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes an executable that stands in for ssh: options dropped,
    /// the host ignored, the command handed to `/bin/sh` here.
    ///
    /// The Conduit's argument shape is `-o K=V … host "sh -c '…'"`, so
    /// the script skips option pairs, drops the host, and executes
    /// what remains — the same command a real host would run.
    static func fakeSSH(in directory: URL) throws -> String {
        let script = """
            #!/bin/sh
            while [ $# -gt 0 ]; do
                case "$1" in
                    -o|-O|-i|-p|-F) shift 2 ;;
                    -*) shift ;;
                    *) break ;;
                esac
            done
            shift
            exec /bin/sh -c "$1"

            """
        let url = directory.appendingPathComponent("fake-ssh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// A shell fragment that records the running shell's pid at `url`.
    static func recordPid(at url: URL) -> String {
        "echo $$ > \(ShellQuote.quote(url.path))"
    }

    /// The pid a shell recorded at `url`, once it has.
    static func pid(at url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let value = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return value
    }

    /// Whether a process with `pid` still exists — a zombie counts,
    /// which is why liveness is polled rather than read once.
    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Polls `condition` every 20 ms until it holds or `timeout` passes.
    @discardableResult
    static func waitUntil(
        timeout: Duration = .seconds(5),
        _ condition: @Sendable () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Waits for the pid file to appear, then returns its pid.
    static func awaitPid(at url: URL) async -> pid_t? {
        await waitUntil { pid(at: url) != nil }
        return pid(at: url)
    }

    /// Waits for the process to be gone.
    static func awaitDeath(of pid: pid_t) async -> Bool {
        await waitUntil { !isAlive(pid) }
    }
}
