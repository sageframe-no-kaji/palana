// Fixtures for the door's lifecycle tests: a fake ssh that records every
// argv it receives and behaves like a master on `-O exit`, and unix
// sockets that stand in for masters alive and dead. Everything lives in
// a throwaway directory under /tmp — never the app's own control
// directory, never ~/.ssh, never a host.

import Foundation

@testable import PalanaCore

enum ControlSocketFixture {
    /// The byte between recorded arguments — one line per invocation.
    static let separator: Character = "\u{1f}"

    /// A fresh, private control directory, short enough for a socket path.
    static func makeControlDirectory(mode: Int = 0o700) throws -> String {
        let path = SSHFixture.freshControlDirectory()
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: mode])
        return path
    }

    /// Writes a fake ssh that records its argv to `log` — one line per
    /// invocation, written whole, so two halves of a pipe never
    /// interleave — then acts: `-O exit` removes the socket named by
    /// ControlPath the way a real master does when asked; anything else
    /// runs the command on this machine, as ``ProcessFixture/fakeSSH(in:)``
    /// does, or exits at once when `executes` is false.
    static func recordingSSH(in directory: URL, log: URL, executes: Bool = true) throws -> String {
        let logPath = ShellQuote.quote(log.path)
        let tail = executes ? "shift\nexec /bin/sh -c \"$1\"" : "exit 0"
        let script = """
            #!/bin/sh
            line=$(printf '%s\\037' "$@")
            printf '%s\\n' "$line" >> \(logPath)
            control=""
            op=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    -o) case "$2" in ControlPath=*) control="${2#ControlPath=}" ;; esac; shift 2 ;;
                    -O) op="$2"; shift 2 ;;
                    -i|-p|-F) shift 2 ;;
                    -*) shift ;;
                    *) break ;;
                esac
            done
            if [ "$op" = exit ]; then
                rm -f "$control"
                exit 0
            fi
            \(tail)

            """
        let url = directory.appendingPathComponent("fake-ssh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    /// Every recorded invocation, each as its argv.
    static func invocations(in log: URL) -> [[String]] {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map { line in
            line.split(separator: separator, omittingEmptySubsequences: false)
                .dropLast()
                .map(String.init)
        }
    }

    /// A socket file nobody listens on — what a crashed master leaves.
    static func plantDeadSocket(at path: String) throws {
        let descriptor = try bound(at: path)
        close(descriptor)
    }

    /// A listening socket — a master, alive.
    ///
    /// The caller closes the returned descriptor when the test is done
    /// with it. The backlog is deep: nothing accepts, and every probe
    /// the door makes sits in it.
    static func plantLiveSocket(at path: String) throws -> Int32 {
        let descriptor = try bound(at: path)
        guard listen(descriptor, 64) == 0 else {
            close(descriptor)
            throw FixtureError.socket("listen: \(String(cString: strerror(errno)))")
        }
        return descriptor
    }

    private static func bound(at path: String) throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw FixtureError.socket("socket: \(String(cString: strerror(errno)))")
        }
        var address = sockaddr_un()
        guard SSHConduit.fill(&address, with: path) else {
            close(descriptor)
            throw FixtureError.socket("path too long for a socket: \(path)")
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
        }
        guard result == 0 else {
            close(descriptor)
            throw FixtureError.socket("bind: \(String(cString: strerror(errno)))")
        }
        return descriptor
    }

    enum FixtureError: Error {
        case socket(String)
    }
}
