// Argument assembly — pure, tested without the wire.

import Foundation
import Testing

@testable import PalanaCore

@Suite("SSHConduit argument assembly")
struct SSHConduitArgumentsTests {
    private let configuration = SSHConfiguration(
        controlDirectory: "/tmp/palana-cm-test",
        extraOptions: ["-i", "/keys/id", "-p", "2223"]
    )

    @Test("a multiplexed run carries the ControlMaster triplet and ends host command")
    func multiplexedRun() {
        let args = SSHConduit.arguments(
            host: "jodo", command: "echo ok", configuration: configuration)
        #expect(args.contains("ControlMaster=auto"))
        #expect(args.contains("ControlPath=/tmp/palana-cm-test/%C"))
        #expect(args.contains("ControlPersist=yes"))
        #expect(args.contains("BatchMode=yes"))
        #expect(args.suffix(2) == ["jodo", "echo ok"])
    }

    @Test("extra options ride between the master flags and the host")
    func extraOptionsPlacement() {
        let args = SSHConduit.arguments(
            host: "jodo", command: "true", configuration: configuration)
        let identityIndex = try? #require(args.firstIndex(of: "-i"))
        let hostIndex = try? #require(args.firstIndex(of: "jodo"))
        if let identityIndex, let hostIndex {
            #expect(identityIndex < hostIndex)
        }
    }

    @Test("a control command renders as -O before the host, with no command")
    func controlExit() {
        let args = SSHConduit.arguments(
            host: "jodo", command: nil, configuration: configuration, controlCommand: "exit")
        #expect(args.suffix(3) == ["-O", "exit", "jodo"])
    }

    @Test("multiplexing off drops the ControlMaster triplet")
    func plainRun() {
        let args = SSHConduit.arguments(
            host: "jodo", command: "true", configuration: configuration, multiplex: false)
        #expect(!args.contains("ControlMaster=auto"))
        #expect(args.contains("BatchMode=yes"))
    }

    @Test("the default control directory is short enough for a socket path")
    func controlDirectoryArithmetic() {
        // %C is 40 hex chars + "/" — the macOS sun_path cap is ~104 bytes.
        let socketPath = SSHConfiguration.defaultControlDirectory.count + 41
        #expect(socketPath < 104)
    }
}
