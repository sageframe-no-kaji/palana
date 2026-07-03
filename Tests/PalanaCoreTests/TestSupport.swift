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
        try parseEnv(envFile)
    }

    static func parseEnv(_ url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var facts: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            facts[String(pair[0])] = String(pair[1])
        }
        return facts
    }

    /// A unique control directory per configuration, so one test's
    /// deferred closeAll can never tear down another test's master
    /// mid-command — observed as a 255-with-empty-stderr flake on CI
    /// when the directory was merely per-process.
    static func freshControlDirectory() -> String {
        let suffix = UUID().uuidString.prefix(8)
        return "/tmp/palana-test-cm-\(ProcessInfo.processInfo.processIdentifier)-\(suffix)"
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
            controlDirectory: freshControlDirectory(),
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

/// The ZFS fixture — the Lima VM's throwaway pool.
///
/// Reached through lima's own ssh config via `-F`. Facts in
/// .fixtures/zfs.env, written by scripts/zfs-fixture.sh. Absent file:
/// the tests skip, visibly.
enum ZFSFixture {
    static let envFile = SSHFixture.repoRoot.appendingPathComponent(".fixtures/zfs.env")

    static var available: Bool {
        FileManager.default.fileExists(atPath: envFile.path)
    }

    static func configuration() throws -> (configuration: SSHConfiguration, host: String) {
        let facts = try SSHFixture.parseEnv(envFile)
        let configuration = SSHConfiguration(
            controlDirectory: SSHFixture.freshControlDirectory(),
            extraOptions: [
                "-F", facts["PALANA_ZFS_SSH_CONFIG"] ?? "",
                "-o", "ConnectTimeout=10",
            ]
        )
        return (configuration, facts["PALANA_ZFS_HOST"] ?? "lima-palana-zfs")
    }
}
