// Shared fixture plumbing. Integration tests read connection facts from
// .fixtures/sshd.env at the repo root — written by scripts/sshd-fixture.sh
// locally and by scripts/ci-sshd-fixture.sh on the CI runner. The tests
// don't know which fixture they got. No file: the tests skip, visibly.

import Foundation

@testable import PalanaCore

enum SSHFixture {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let envFile = repoRoot.appendingPathComponent(".fixtures/sshd.env")

    static var available: Bool {
        FileManager.default.fileExists(atPath: envFile.path)
    }

    static func facts() throws -> [String: String] {
        let text = try String(contentsOf: envFile, encoding: .utf8)
        var facts: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            facts[String(pair[0])] = String(pair[1])
        }
        return facts
    }

    /// A per-process control directory so tests never reuse a master
    /// opened by an earlier run.
    static var controlDirectory: String {
        "/tmp/palana-test-cm-\(ProcessInfo.processInfo.processIdentifier)"
    }

    static func configuration(
        identityKey: String = "PALANA_FIXTURE_IDENTITY",
        knownHostsMode: KnownHostsMode = .fixture,
        portOverride: String? = nil
    ) throws -> (configuration: SSHConfiguration, host: String) {
        let facts = try facts()
        let identity = facts[identityKey] ?? ""
        let knownHosts: String
        let strict: String
        switch knownHostsMode {
        case .fixture:
            knownHosts = facts["PALANA_FIXTURE_KNOWN_HOSTS"] ?? "/dev/null"
            strict = "accept-new"
        case .emptyStrict:
            knownHosts = "/dev/null"
            strict = "yes"
        }
        let port = portOverride ?? facts["PALANA_FIXTURE_PORT"] ?? "22"
        let configuration = SSHConfiguration(
            controlDirectory: controlDirectory,
            extraOptions: [
                "-i", identity,
                "-p", port,
                "-o", "UserKnownHostsFile=\(knownHosts)",
                "-o", "StrictHostKeyChecking=\(strict)",
                "-o", "IdentitiesOnly=yes",
                "-o", "ConnectTimeout=5",
            ]
        )
        return (configuration, facts["PALANA_FIXTURE_HOST"] ?? "localhost")
    }

    enum KnownHostsMode {
        case fixture
        case emptyStrict
    }
}
