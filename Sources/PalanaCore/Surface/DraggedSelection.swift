// The drag payload and drop decision — the engine half of drag-and-drop.
// A DraggedSelection carries the address of a selection (host, directory,
// entry names as bytes) across the drag pasteboard. DropDecision.decide
// is the pure function that maps payload + target + modifier to an action
// or a refusal. Transferable conformance lives in the app target (Decision 1).

import Foundation

/// The typed drag payload: the address of a selection on a remote (or local) host.
///
/// Carries source host, source directory, and entry names as raw bytes —
/// the same byte-honest idiom as ``FileEntry/nameData``. Round-trips through
/// `Codable` losslessly; `JSONEncoder` base64-encodes the byte arrays.
/// Do not conform to `Transferable` here — that is app-target currency.
public struct DraggedSelection: Codable, Sendable, Equatable {
    /// The ssh alias of the source host, or `PalanaCore.localHostName` for this Mac.
    public var host: String

    /// The source directory path on that host.
    public var directory: String

    /// The selected entry names as raw bytes — encoding-agnostic, matching ``FileEntry/nameData``.
    public var names: [Data]

    /// Assembles a drag payload.
    ///
    /// - Parameters:
    ///   - host: The ssh alias or `PalanaCore.localHostName`.
    ///   - directory: The source directory path.
    ///   - names: Entry names as byte arrays; order preserved.
    public init(host: String, directory: String, names: [Data]) {
        self.host = host
        self.directory = directory
        self.names = names
    }
}

/// What happens when a drag lands.
///
/// Produced by ``DropDecision/decide(payload:targetHost:targetDirectory:optionHeld:)`` —
/// a pure function in `PalanaCore`, tested.
public enum DropDecision: Equatable, Sendable {
    /// Compose a plan with the given operation — copy or move.
    case compose(PlanOperation)

    /// The drop landed on the pane it came from — same host, same directory
    /// after trailing-slash normalization.
    case refuseSamePlace

    /// The drag carried no names — nothing to compose.
    case refuseEmpty

    /// The pure drop decision function.
    ///
    /// Given a payload, a target host and directory, and whether the option
    /// key was held at drop time, returns what should happen:
    /// - `.refuseEmpty` when `payload.names` is empty.
    /// - `.refuseSamePlace` when host and directory match after trailing-slash normalization.
    /// - `.compose(.move)` when `optionHeld` is `true`.
    /// - `.compose(.copy)` otherwise.
    ///
    /// - Parameters:
    ///   - payload: The drag payload from the source pane.
    ///   - targetHost: The ssh alias of the destination pane's host.
    ///   - targetDirectory: The current directory of the destination pane.
    ///   - optionHeld: Whether the Option key was held at the moment of drop.
    /// - Returns: The resolved ``DropDecision``.
    public static func decide(
        payload: DraggedSelection,
        targetHost: String,
        targetDirectory: String,
        optionHeld: Bool
    ) -> Self {
        guard !payload.names.isEmpty else { return .refuseEmpty }

        let normalizedSource = normalizePath(payload.directory)
        let normalizedTarget = normalizePath(targetDirectory)

        if payload.host == targetHost && normalizedSource == normalizedTarget {
            return .refuseSamePlace
        }

        return optionHeld ? .compose(.move) : .compose(.copy)
    }

    /// Strips a trailing slash unless the path is exactly `/`.
    private static func normalizePath(_ path: String) -> String {
        guard path != "/" else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
