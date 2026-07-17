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
/// Produced by ``DropDecision/decide(payload:targetHost:targetDirectory:moveHeld:)`` —
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
    /// Copy is the default; the move modifier (⌘, read by the surface) escalates
    /// to a move. Given a payload, a target host and directory, and whether that
    /// modifier was held at drop time, returns what should happen:
    /// - `.refuseEmpty` when `payload.names` is empty.
    /// - `.refuseSamePlace` when host and directory match after trailing-slash normalization.
    /// - `.compose(.move)` when `moveHeld` is `true`.
    /// - `.compose(.copy)` otherwise.
    ///
    /// - Parameters:
    ///   - payload: The drag payload from the source pane.
    ///   - targetHost: The ssh alias of the destination pane's host.
    ///   - targetDirectory: The current directory of the destination pane.
    ///   - moveHeld: Whether the move modifier (⌘) was held at the moment of drop.
    /// - Returns: The resolved ``DropDecision``.
    public static func decide(
        payload: DraggedSelection,
        targetHost: String,
        targetDirectory: String,
        moveHeld: Bool
    ) -> Self {
        guard !payload.names.isEmpty else { return .refuseEmpty }

        let normalizedSource = normalizePath(payload.directory)
        let normalizedTarget = normalizePath(targetDirectory)

        if payload.host == targetHost && normalizedSource == normalizedTarget {
            return .refuseSamePlace
        }

        return moveHeld ? .compose(.move) : .compose(.copy)
    }

    /// The drop decision for a drag that lands on a **folder row** (ho-14).
    ///
    /// The destination is the folder itself, not the pane's current directory:
    /// the caller resolves `folderPath` to the pane's directory + the folder's
    /// name. Two refusals sit ahead of the standard decision:
    /// - **Self-into-self** — the folder is one of the dragged items (same host,
    ///   the folder lives in the drag's own source directory, and its name is in
    ///   the selection). Refused the same way any self-drop is.
    /// - **Files already here** — the folder *is* the source directory; this
    ///   falls through to ``decide(payload:targetHost:targetDirectory:moveHeld:)``,
    ///   whose same-place check catches it.
    ///
    /// Otherwise the folder is a genuine destination and the decision is
    /// `.compose(.move)` under the move modifier (⌘) or `.compose(.copy)` — the
    /// exact vocabulary the pane-level drop already speaks.
    ///
    /// - Parameters:
    ///   - payload: The drag payload from the source pane.
    ///   - targetHost: The ssh alias of the pane hosting the folder row.
    ///   - folderPath: The folder's full path (its parent is the target pane's
    ///     current directory).
    ///   - folderNameData: The folder's name bytes, for the self-in-selection
    ///     check — byte-honest, matching ``FileEntry/nameData`` and `payload.names`.
    ///   - moveHeld: Whether the move modifier (⌘) was held at the moment of drop.
    /// - Returns: The resolved ``DropDecision``.
    public static func decideOntoFolder(
        payload: DraggedSelection,
        targetHost: String,
        folderPath: String,
        folderNameData: Data,
        moveHeld: Bool
    ) -> Self {
        guard !payload.names.isEmpty else { return .refuseEmpty }

        // The folder is itself one of the dragged items — same host, the folder
        // lives in the drag's own source directory, and its name is in the
        // selection. Refuse the self-drop.
        let folderIsInSelection =
            payload.host == targetHost
            && normalizePath(payload.directory) == parentDirectory(of: folderPath)
            && payload.names.contains(folderNameData)
        if folderIsInSelection {
            return .refuseSamePlace
        }

        // Otherwise the folder is the destination; the standard decision draws
        // the copy/move line and catches "the files already live here".
        return decide(
            payload: payload,
            targetHost: targetHost,
            targetDirectory: folderPath,
            moveHeld: moveHeld)
    }

    /// Strips a trailing slash unless the path is exactly `/`.
    private static func normalizePath(_ path: String) -> String {
        guard path != "/" else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// The parent directory of a path — the folder's containing directory,
    /// normalized (no trailing slash, `/` for a top-level child).
    private static func parentDirectory(of path: String) -> String {
        let trimmed = normalizePath(path)
        guard let cut = trimmed.lastIndex(of: "/") else { return trimmed }
        let parent = String(trimmed[..<cut])
        return parent.isEmpty ? "/" : parent
    }
}
