// The taxonomy's unit battery. Classification is a pure function, tested
// against stderr shapes — including the corpus captured from the real
// fixture (Fixtures/failure-corpus.json) once it exists.

import Foundation
import Testing

@testable import PalanaCore

@Suite("ConduitError classification")
struct ConduitErrorTests {
    @Test("non-255 exit is the remote command's business, not the door's")
    func remoteExitIsData() {
        #expect(ConduitError.classify(exitStatus: 0, stderr: "") == nil)
        #expect(ConduitError.classify(exitStatus: 7, stderr: "some noise") == nil)
        #expect(ConduitError.classify(exitStatus: 1, stderr: "Permission denied") == nil)
    }

    @Test(
        "unreachable shapes classify as hostUnreachable",
        arguments: [
            "ssh: connect to host jodo port 22: Connection refused",
            "ssh: connect to host 10.0.0.9 port 22: Operation timed out",
            "ssh: connect to host koan port 22: No route to host",
            "ssh: Could not resolve hostname nonesuch: nodename nor servname provided",
            "ssh: connect to host jodo port 22: Network is unreachable",
        ])
    func unreachable(stderr: String) {
        guard case .hostUnreachable = ConduitError.classify(exitStatus: 255, stderr: stderr) else {
            Issue.record("expected hostUnreachable for: \(stderr)")
            return
        }
    }

    @Test("auth rejection classifies as authenticationDenied")
    func authDenied() {
        let stderr = "spike@localhost: Permission denied (publickey,keyboard-interactive)."
        guard case .authenticationDenied = ConduitError.classify(exitStatus: 255, stderr: stderr)
        else {
            Issue.record("expected authenticationDenied")
            return
        }
    }

    @Test("host key trouble classifies as hostKeyVerificationFailed")
    func hostKey() {
        for stderr in [
            "Host key verification failed.",
            "@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @",
        ] {
            guard
                case .hostKeyVerificationFailed = ConduitError.classify(
                    exitStatus: 255, stderr: stderr)
            else {
                Issue.record("expected hostKeyVerificationFailed for: \(stderr)")
                return
            }
        }
    }

    @Test("dropped connections classify as connectionLost")
    func connectionLost() {
        let stderr = "Connection closed by 192.168.1.190 port 22"
        guard case .connectionLost = ConduitError.classify(exitStatus: 255, stderr: stderr) else {
            Issue.record("expected connectionLost")
            return
        }
    }

    @Test("an unmatched 255 stays typed with its stderr — never swallowed")
    func unmatchedIsSSHFailure() {
        let stderr = "something the taxonomy has never seen"
        let classified = ConduitError.classify(exitStatus: 255, stderr: stderr)
        #expect(classified == .sshFailure(exitStatus: 255, stderr: stderr))
    }

    @Test("summary line is the last non-empty stderr line")
    func summaryLine() {
        let stderr = "Warning: banner\n\nssh: connect to host jodo port 22: Connection refused\n"
        #expect(
            ConduitError.summaryLine(of: stderr)
                == "ssh: connect to host jodo port 22: Connection refused")
    }

    @Test("the captured failure corpus classifies with no sshFailure fallthrough")
    func corpusClassifies() throws {
        let url = SSHFixture.repoRoot.appendingPathComponent(
            "Tests/PalanaCoreTests/Fixtures/failure-corpus.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let transcript = try ConduitTranscript(contentsOf: url)
        #expect(!transcript.entries.isEmpty)
        for entry in transcript.entries {
            let classified = ConduitError.classify(exitStatus: entry.exit, stderr: entry.stderr)
            guard let classified else {
                Issue.record("corpus entry did not classify: \(entry.command)")
                continue
            }
            if case .sshFailure = classified {
                Issue.record("corpus entry fell through to sshFailure: \(entry.stderr)")
            }
        }
    }
}
