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
    /// Finite by default: a master idles this long after its last
    /// session and then exits on its own, so a crashed app's masters
    /// outlive it by at most this interval. The quit path still owns
    /// `closeAll()`, and a fresh door's first use sweeps whatever an
    /// earlier run left in the control directory.
    public var controlPersist: String

    /// Assembles a configuration; every field has a working default.
    public init(
        sshExecutablePath: String = "/usr/bin/ssh",
        controlDirectory: String = Self.defaultControlDirectory,
        extraOptions: [String] = [],
        controlPersist: String = Self.defaultControlPersist
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

    /// `10m` — long enough that an operator pausing between commands
    /// keeps a warm session, short enough that an orphaned master is
    /// gone before it is forgotten.
    public static let defaultControlPersist = "10m"
}

/// The single door, live. An actor: `Process` is not Sendable and the
/// per-host session set wants isolation.
public actor SSHConduit: Conduit {
    private let configuration: SSHConfiguration
    private var openedHosts: Set<String> = []
    /// The one startup sweep; every run awaits it before spawning.
    private var sweep: Task<Void, Never>?

    /// Opens the door with the given invocation shape.
    public init(configuration: SSHConfiguration = SSHConfiguration()) {
        self.configuration = configuration
    }

    /// Argument assembly, pure and tested without the wire.
    ///
    /// Throws before assembling anything when `host` is not a plain
    /// alias — see ``validateDestination(_:)``. Every ssh the door or
    /// the pipeline spawns passes through here, so nothing outside the
    /// alias grammar reaches an argv.
    static func arguments(
        host: String,
        command: String?,
        configuration: SSHConfiguration,
        multiplex: Bool = true,
        controlCommand: String? = nil
    ) throws -> [String] {
        try validateDestination(host)
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
            // The remote command runs under `sh -c` — the door promises
            // POSIX regardless of the far side's login shell. A fish
            // login shell rejects POSIX conditionals, and the probe
            // against such a host returned silence (ho-07's session).
            args.append("sh -c \(ShellQuote.quote(command))")
        }
        return args
    }

    /// Runs a command through the host's multiplexed session, opening the
    /// master on first use.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        let arguments = try Self.arguments(host: host, command: command, configuration: configuration)
        try await prepareControlDirectory()
        openedHosts.insert(host)
        return try Self.spawn(executable: configuration.sshExecutablePath, arguments: arguments)
    }

    /// Closes the host's master.
    ///
    /// `ssh -O exit`, best-effort.
    public func close(host: String) async {
        openedHosts.remove(host)
        guard
            let arguments = try? Self.arguments(
                host: host, command: nil, configuration: configuration, controlCommand: "exit"),
            let control = try? Self.spawn(
                executable: configuration.sshExecutablePath, arguments: arguments)
        else { return }
        // Best-effort: drain and await so the master is gone before return.
        _ = try? await control.collect()
    }

    /// Sweeps every opened host, then unlinks any socket left without
    /// a master.
    ///
    /// The quit path calls this.
    public func closeAll() async {
        for host in openedHosts {
            await close(host: host)
        }
        removeDeadSockets()
    }

    /// Creates and checks the control directory on every use; sweeps
    /// it once, before this door's first master, holding every run
    /// until the sweep is done so a master being born is never mistaken
    /// for one that died.
    private func prepareControlDirectory() async throws {
        try Self.ensureControlDirectory(configuration.controlDirectory)
        if sweep == nil {
            sweep = Task { await self.sweepStaleSockets() }
        }
        await sweep?.value
    }

    /// Closes or removes what an earlier run left in the control
    /// directory.
    ///
    /// A socket whose master still answers belongs to a run that never
    /// reached `closeAll()` — a crash — and is asked to exit; a socket
    /// nobody answers is the file that crash left behind and is
    /// unlinked. A master that declines to exit keeps its socket: with
    /// a finite ControlPersist it is on its way out regardless.
    private func sweepStaleSockets() async {
        for socket in Self.controlSockets(in: configuration.controlDirectory)
        where Self.socketAnswers(at: socket) {
            await exitSession(at: socket)
        }
        removeDeadSockets()
    }

    /// Unlinks every socket in the control directory nobody answers.
    private func removeDeadSockets() {
        for socket in Self.controlSockets(in: configuration.controlDirectory)
        where !Self.socketAnswers(at: socket) {
            unlink(socket)
        }
    }

    /// `ssh -O exit` against one socket by path.
    ///
    /// The destination is a placeholder: a control command reads the
    /// socket named by ControlPath and never resolves or connects to
    /// the host, which ssh wants only for config lookup.
    private func exitSession(at socketPath: String) async {
        guard
            let arguments = try? Self.arguments(
                host: Self.sweepHost,
                command: nil,
                configuration: configuration,
                multiplex: false,
                controlCommand: "exit"),
            let control = try? Self.spawn(
                executable: configuration.sshExecutablePath,
                arguments: ["-o", "ControlPath=\(socketPath)"] + arguments)
        else { return }
        _ = try? await control.collect()
    }

    /// The alias named on a sweep's `-O exit` — inside the grammar, and
    /// no config need define it.
    static let sweepHost = "palana-sweep"

    /// Thin spawn path on the readabilityHandler drain.
    ///
    /// Never FileHandle.bytes, whose blocking read starved the second
    /// reader and deadlocked against a full pipe (observed, ho-01).
    /// Internal: the test target's local-shell conduit reuses it.
    ///
    /// The child is the leader of its own process group, so the
    /// returned command's termination reaches every process the
    /// command spawned — a shell's children included — not only the
    /// one the door started.
    static func spawn(executable: String, arguments: [String]) throws -> RunningCommand {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let process = try OwnedProcess.spawn(
            executable: executable,
            arguments: arguments,
            stdout: stdoutPipe,
            stderr: stderrPipe)
        return RunningCommand(
            stdout: stream(from: stdoutPipe.fileHandleForReading),
            stderr: stream(from: stderrPipe.fileHandleForReading),
            exitStatus: { await process.exit() },
            terminate: { grace in process.terminate(killAfter: grace) })
    }

    /// Chunks a pipe's read end as data arrives; closes it when the
    /// stream ends, whichever side ends it.
    static func stream(from handle: FileHandle) -> AsyncStream<Data> {
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
                OwnedProcess.closeQuietly(handle)
            }
        }
    }
}

// MARK: - Destinations

extension SSHConduit {
    /// Refuses a host that is not a plain alias, before anything spawns.
    ///
    /// The parser admits only ``SSHConfigParser/aliasGrammar`` into the
    /// registry, but a restored session or a legacy cache can carry a
    /// name that never passed it. ssh reads a leading `-` as an option
    /// and a remote `sh -c` reads metacharacters as syntax, so the door
    /// checks the grammar again at the last moment before launch. The
    /// reserved `local` is refused with the rest: it is this machine,
    /// never a destination.
    static func validateDestination(_ host: String) throws {
        guard !host.isEmpty, SSHConfigParser.isAlias(host) else {
            throw ConduitError.launchFailed(
                "refused ssh destination \(String(reflecting: host)): "
                    + "not a host alias (\(SSHConfigParser.aliasGrammar))")
        }
    }
}

// MARK: - Control directory

extension SSHConduit {
    /// Creates the control directory if needed and refuses it unless it
    /// is a real directory, owned by this user, closed to everyone else.
    ///
    /// The directory lives under a world-writable `/tmp`. Another user
    /// who planted a directory or a symlink at the path first would own
    /// every socket ssh creates there; a mode that lets group or other
    /// in would let them reach the authenticated masters. Either way
    /// the door stays shut and says why.
    static func ensureControlDirectory(_ path: String) throws {
        var status = stat()
        if lstat(path, &status) != 0 {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            guard lstat(path, &status) == 0 else {
                throw ConduitError.launchFailed(
                    "control directory \(path): \(String(cString: strerror(errno)))")
            }
        }
        let problem = controlDirectoryProblem(
            uid: status.st_uid,
            mode: status.st_mode,
            isDirectory: status.st_mode & S_IFMT == S_IFDIR)
        if let problem {
            throw ConduitError.launchFailed("control directory \(path) \(problem)")
        }
    }

    /// Why a control directory is unsafe, or `nil` when it is not.
    ///
    /// Pure, so the wrong-owner case is testable without a second user.
    static func controlDirectoryProblem(uid: uid_t, mode: mode_t, isDirectory: Bool) -> String? {
        guard isDirectory else { return "is not a directory" }
        guard uid == getuid() else { return "is owned by uid \(uid), not \(getuid())" }
        guard mode & 0o077 == 0 else {
            let shown = String(mode & 0o777, radix: 8)
            return "is open to others (mode \(shown); expected 700)"
        }
        return nil
    }

    /// The socket files in the control directory, sorted by path.
    static func controlSockets(in directory: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.map { "\(directory)/\($0)" }
            .filter { path in
                var status = stat()
                return lstat(path, &status) == 0 && status.st_mode & S_IFMT == S_IFSOCK
            }
            .sorted()
    }

    /// True when something answers at the socket — a master, alive.
    ///
    /// A refused connect is a socket whose master is gone: the file
    /// outlived the process, which is exactly what a crash leaves.
    static func socketAnswers(at path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_un()
        guard fill(&address, with: path) else { return false }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, length)
            }
        }
        return result == 0
    }

    /// Writes `path` into the address; false when it does not fit.
    static func fill(_ address: inout sockaddr_un, with path: String) -> Bool {
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() {
                buffer[index] = UInt8(bitPattern: byte)
            }
        }
        return true
    }
}

// MARK: - Process ownership

/// A child process the door owns: its group, its exit, its signals.
///
/// Spawned as the leader of a fresh process group so termination
/// reaches everything the command forked. Exit is observed by a
/// dedicated reaper thread and can be awaited by any number of
/// callers; signals are sent at most once each and never after exit,
/// so a reused pid can never receive a stale kill.
final class OwnedProcess: @unchecked Sendable {
    /// The child's pid — also its process-group id.
    let pid: pid_t

    private let lock = NSLock()
    private var status: Int32?
    private var signalsSent: Set<Int32> = []
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    private init(pid: pid_t) {
        self.pid = pid
        let reaper = Thread { [self] in
            var raw: Int32 = 0
            var result = waitpid(pid, &raw, 0)
            while result == -1, errno == EINTR {
                result = waitpid(pid, &raw, 0)
            }
            finish(result == pid ? Self.exitStatus(fromWaitStatus: raw) : -1)
        }
        reaper.name = "palana.reap.\(pid)"
        reaper.start()
    }

    /// Spawns `executable` with the pipes' write ends as its stdout and
    /// stderr, `/dev/null` (or the given pipe's read end) as its stdin.
    ///
    /// Every other descriptor is closed in the child, and the child's
    /// ends are closed here once it holds them, so the read ends reach
    /// end-of-file exactly when the process group lets go of them.
    static func spawn(
        executable: String,
        arguments: [String],
        stdin: Pipe? = nil,
        stdout: Pipe,
        stderr: Pipe
    ) throws -> OwnedProcess {
        // Close-on-exec on every end: a process forked elsewhere in the
        // app (a terminal's shell, another door's child) must not
        // inherit these, or a pipe outlives the command it belongs to —
        // end-of-file never arrives, and a dead consumer never turns
        // into a broken pipe for its producer.
        for pipe in [stdin, stdout, stderr].compactMap({ $0 }) {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
            }
        }
        let stdinDescriptor: Int32
        if let stdin {
            stdinDescriptor = stdin.fileHandleForReading.fileDescriptor
        } else {
            stdinDescriptor = open("/dev/null", O_RDONLY)
        }
        defer {
            if let stdin {
                closeQuietly(stdin.fileHandleForReading)
            } else {
                close(stdinDescriptor)
            }
            closeQuietly(stdout.fileHandleForWriting)
            closeQuietly(stderr.fileHandleForWriting)
        }
        guard stdinDescriptor >= 0 else {
            throw ConduitError.launchFailed("could not open /dev/null for the child's stdin")
        }
        return try spawn(
            executable: executable,
            arguments: arguments,
            stdinDescriptor: stdinDescriptor,
            stdoutDescriptor: stdout.fileHandleForWriting.fileDescriptor,
            stderrDescriptor: stderr.fileHandleForWriting.fileDescriptor)
    }

    private static func spawn(
        executable: String,
        arguments: [String],
        stdinDescriptor: Int32,
        stdoutDescriptor: Int32,
        stderrDescriptor: Int32
    ) throws -> OwnedProcess {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Fresh group, default signal dispositions (the app ignores
        // SIGPIPE; its children must not inherit that), nothing masked.
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        var noSignal = sigset_t()
        sigemptyset(&noSignal)
        posix_spawnattr_setsigmask(&attributes, &noSignal)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags =
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
            | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stdoutDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrDescriptor, STDERR_FILENO)

        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        defer {
            for pointer in argv {
                free(pointer)
            }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &actions, &attributes, argv, environ)
        guard result == 0 else {
            throw ConduitError.launchFailed("\(executable): \(String(cString: strerror(result)))")
        }
        return OwnedProcess(pid: pid)
    }

    /// Asks the group to stop, then makes it: SIGTERM now, SIGKILL
    /// after `grace` if anything in the group is still alive.
    ///
    /// Idempotent — a second call changes nothing.
    func terminate(killAfter grace: Duration) {
        guard signal(SIGTERM) else { return }
        let nanoseconds =
            grace.components.seconds * 1_000_000_000 + grace.components.attoseconds / 1_000_000_000
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
            _ = self.signal(SIGKILL)
        }
    }

    /// Awaits the group leader's exit; any number of callers may.
    func exit() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
                return
            }
            waiters.append(continuation)
            lock.unlock()
        }
    }

    /// True once the leader has been reaped.
    var hasExited: Bool {
        lock.withLock { status != nil }
    }

    /// Sends `signal` to the group once; never after exit.
    ///
    /// Returns whether it was sent.
    @discardableResult
    private func signal(_ signal: Int32) -> Bool {
        lock.withLock {
            guard status == nil, !signalsSent.contains(signal) else { return false }
            signalsSent.insert(signal)
            return kill(-pid, signal) == 0
        }
    }

    private func finish(_ exitStatus: Int32) {
        lock.lock()
        status = exitStatus
        let resumed = waiters
        waiters = []
        lock.unlock()
        for waiter in resumed {
            waiter.resume(returning: exitStatus)
        }
    }

    /// A shell's reading of a wait status: the exit code, or 128 plus
    /// the signal that ended the process.
    static func exitStatus(fromWaitStatus raw: Int32) -> Int32 {
        let low = raw & 0x7f
        if low == 0 {
            return (raw >> 8) & 0xff
        }
        return 128 + low
    }

    /// Detaches any reader and closes the handle; a handle already
    /// closed is left alone.
    static func closeQuietly(_ handle: FileHandle) {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}
