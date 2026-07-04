// One door over two — "local" is a host (second hands session's word),
// and a plan can name this machine and a remote in the same breath. The
// router dispatches by the reserved name so the Transports enact mixed
// plans unchanged, which is the point of the door.

import Foundation

/// A conduit that routes by host name.
///
/// The reserved name goes to the local shell; everything else goes to
/// the wire. Nothing above the door knows there are two.
public struct RoutingConduit: Conduit {
    /// The reserved name for the operator's own machine.
    public let localName: String

    private let local: LocalConduit
    private let remote: any Conduit

    /// A router over the wire door, with the local door built in.
    public init(
        remote: any Conduit,
        localName: String = PalanaCore.localHostName,
        local: LocalConduit = LocalConduit()
    ) {
        self.remote = remote
        self.localName = localName
        self.local = local
    }

    /// Runs on this machine when the host is the reserved name, over the
    /// wire otherwise.
    public func run(on host: String, _ command: String) async throws -> RunningCommand {
        host == localName
            ? try await local.run(on: host, command)
            : try await remote.run(on: host, command)
    }

    /// Closes the remote session; the local door has none.
    public func close(host: String) async {
        guard host != localName else { return }
        await remote.close(host: host)
    }

    /// Closes every remote session.
    public func closeAll() async {
        await remote.closeAll()
    }
}
