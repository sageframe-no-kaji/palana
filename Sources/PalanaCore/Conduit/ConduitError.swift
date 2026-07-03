// The error taxonomy. Every failure a host can produce surfaces typed at
// the Conduit before anything above it interprets raw process noise.

import Foundation

/// Door-level failures, classified from ssh's own signals.
///
/// A remote command's nonzero exit is NOT one of these — that's data,
/// carried by ``CommandResult``.
public enum ConduitError: Error, Equatable, Sendable {
    /// The ssh process could not be spawned at all.
    case launchFailed(String)
    /// Connection refused, timed out, unresolvable, or unroutable.
    case hostUnreachable(String)
    /// The host answered and rejected the authentication.
    case authenticationDenied(String)
    /// Host key mismatch or unverifiable host key.
    case hostKeyVerificationFailed(String)
    /// An established connection dropped mid-command.
    case connectionLost(String)
    /// ssh exited 255 with stderr the taxonomy does not recognize.
    /// Typed, never swallowed — the raw stderr rides along.
    case sshFailure(exitStatus: Int32, stderr: String)

    /// Pure classification: `(exitStatus, stderr) → ConduitError?`.
    ///
    /// ssh reserves exit 255 for its own failures; any other status is the
    /// remote command's and returns nil. The known ambiguity — a remote
    /// command could itself exit 255 — is ssh's limitation, documented
    /// here and accepted.
    public static func classify(exitStatus: Int32, stderr: String) -> Self? {
        guard exitStatus == 255 else { return nil }
        let text = stderr.lowercased()

        let unreachable = [
            "connection refused", "connection timed out", "operation timed out",
            "no route to host", "could not resolve hostname", "network is unreachable",
            "name or service not known",
        ]
        if unreachable.contains(where: text.contains) {
            return .hostUnreachable(summaryLine(of: stderr))
        }
        if text.contains("permission denied") || text.contains("too many authentication failures") {
            return .authenticationDenied(summaryLine(of: stderr))
        }
        let hostKeyTrouble = [
            "host key verification failed", "remote host identification has changed",
            "no matching host key type",
        ]
        if hostKeyTrouble.contains(where: text.contains) {
            return .hostKeyVerificationFailed(summaryLine(of: stderr))
        }
        let dropped = ["connection closed", "broken pipe", "connection reset"]
        if dropped.contains(where: text.contains) {
            return .connectionLost(summaryLine(of: stderr))
        }
        return .sshFailure(exitStatus: exitStatus, stderr: stderr)
    }

    /// The last non-empty stderr line — ssh puts its verdict there.
    static func summaryLine(of stderr: String) -> String {
        stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? stderr
    }
}
