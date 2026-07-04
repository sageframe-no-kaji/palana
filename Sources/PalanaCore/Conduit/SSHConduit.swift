// The live conduit. Wraps the system ssh binary via Foundation Process —
// the operator's config, keys, agent, and ProxyJump apply exactly as they
// do in the terminal. One ControlMaster session per host: open on first
// use, reuse thereafter, close on quit.

import Foundation

/// How an ``SSHConduit`` invokes ssh.
///
/// The default is the system binary with multiplexed sessions; tests
/// override `extraOptions` to point at fixtures (identity, port,
/// known-hosts).
public struct SSHConfiguration: Sendable {
    /// Path to the ssh binary.
    ///
    /// The system's, by design — no embedded stack.
    public var sshExecutablePath: String
    /// Socket directory for ControlMaster.
    ///
    /// Kept short by arithmetic: `%C` is 40 hex chars and the macOS
    /// socket-path cap is ~104 bytes, which disqualifies Application
    /// Support's long path.
    public var controlDirectory: String
    /// Options appended to every invocation, `-o Key=Value` or flag pairs.
    public var extraOptions: [String]
    /// ControlPersist value.
    ///
    /// `yes` holds the master until explicit close; a crashed app leaks
    /// masters until the next launch's sweep. Accepted for v1 — the quit
    /// path owns `closeAll()`.
    public var controlPersist: String

    /// Assembles a configuration; every field has a working default.
    public init(
        sshExecutablePath: String = "/usr/bin/ssh",
        controlDirectory: String = Self.defaultControlDirectory,
        extraOptions: [String] = [],
        controlPersist: String = "yes"
    ) {
        self.sshExecutablePath = sshExecutablePath
        self.controlDirectory = controlDirectory
        self.extraOptions = extraOptions
        self.controlPersist = controlPersist
    }

    /// `/tmp/palana-cm-<uid>` — short enough for the socket-path cap.
    public static var defaultControlDirectory: String {
        "/tmp/palana-cm-\(getuid())"
    }
}

/// The single door, live. An actor: `Process` is not Sendable and the
/// per-host session set wants isolation.
public actor SSHConduit: Conduit {
    private let configuration: SSHConfiguration
    private var openedHosts: Set<String> = []

    /// Opens the door with the given invocation shape.
    public init(configuration: SSHConfiguration = SSHConfiguration()) {
        self.configuration = configuration
    }

    /// Argument assembly, pure and tested without the wire.
    static func arguments(
        host: String,
        command: String?,
        configuration: SSHConfiguration,
        multiplex: Bool = true,
        controlCommand: String? = nil
    ) -> [String] {
        var args: [String] = []
        if multiplex {
            args += [
                "-o", "ControlMaster=auto",
                "-o", "ControlPath=\(configuration.controlDirectory)/%C",
                "-o", "ControlPersist=\(configuration.controlPersist)",
            ]
        }
        args += ["-o", "BatchMode=yes"]
        args += configuration.extraOptions
        if let controlCommand {
            args += ["-O", controlCommand]
        }
        args.append(host)
        if let command {
            args.append(command)
        }
        return args
    }

    /// Runs a command through the host's multiplexed session, opening the
    /// master on first use.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        try ensureControlDirectory()
        openedHosts.insert(host)
        return try Self.spawn(
            executable: configuration.sshExecutablePath,
            arguments: Self.arguments(host: host, command: command, configuration: configuration)
        )
    }

    /// Closes the host's master.
    ///
    /// `ssh -O exit`, best-effort.
    public func close(host: String) async {
        openedHosts.remove(host)
        guard
            let control = try? Self.spawn(
                executable: configuration.sshExecutablePath,
                arguments: Self.arguments(
                    host: host,
                    command: nil,
                    configuration: configuration,
                    controlCommand: "exit"
                )
            )
        else { return }
        // Best-effort: drain and await so the master is gone before return.
        _ = try? await control.collect()
    }

    /// Sweeps every opened host.
    ///
    /// The quit path calls this.
    public func closeAll() async {
        for host in openedHosts {
            await close(host: host)
        }
    }

    private func ensureControlDirectory() throws {
        try FileManager.default.createDirectory(
            atPath: configuration.controlDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Thin spawn path on the readabilityHandler drain.
    ///
    /// Never FileHandle.bytes, whose blocking read starved the second
    /// reader and deadlocked against a full pipe (observed, ho-01).
    /// Internal: the test target's local-shell conduit reuses it.
    static func spawn(executable: String, arguments: [String]) throws -> RunningCommand {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Termination handler is set before run() — no race with fast exits.
        let (exitStream, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            throw ConduitError.launchFailed(error.localizedDescription)
        }

        return RunningCommand(
            stdout: stream(from: stdoutPipe.fileHandleForReading),
            stderr: stream(from: stderrPipe.fileHandleForReading)
        ) {
            var status: Int32 = -1
            for await code in exitStream {
                status = code
            }
            return status
        }
    }

    private static func stream(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }
}
