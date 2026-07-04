// The operator's own machine as a conduit — /bin/sh -c through the
// same spawn path the wire uses, host ignored. Born as test
// infrastructure for live Darwin coverage; promoted when the first
// hands session asked to point a pane at this Mac. Same door shape,
// no wire, no session lifecycle to manage.

import Foundation

/// A conduit into the local shell.
///
/// `run` ignores the host and speaks to `/bin/sh -c` directly. The
/// Surface's local pane rides this — everything above the door stays
/// identical, which is the point of the door.
public struct LocalConduit: Conduit {
    /// A local door — nothing to configure, the shell is the shell.
    public init() {}

    /// Runs a command in the local shell, host ignored.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        try SSHConduit.spawn(executable: "/bin/sh", arguments: ["-c", command])
    }

    /// No sessions exist locally — nothing to close.
    public func close(host: String) async {}

    /// No sessions exist locally — nothing to close.
    public func closeAll() async {}
}
