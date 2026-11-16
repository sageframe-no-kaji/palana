// DragOutPlan — what a drag out of a pane delivers to the rest of the Mac.
//
// Pure: from the pane's host and directory, the dragged names and the
// pane's listed entries, to one outbound item per dragged entry. A local
// entry is its path; a remote regular file is a download promised at the
// drop; everything a drop cannot honor is a refusal the transcript names.
// No I/O — the Surface turns the items into item providers.

import Foundation

/// One dragged entry, as it leaves the pane.
public enum DragOutItem: Sendable, Equatable {
    /// A file or folder on this Mac — the receiver gets its URL.
    case localFile(path: String)
    /// A regular file on a remote host — downloaded when the drop lands.
    case remoteFile(host: String, path: String, size: Int64)
    /// An entry a drag cannot deliver, with why.
    case refused(name: String, reason: DragOutRefusal)
}

/// Why a dragged entry does not leave the pane.
public enum DragOutRefusal: Sendable, Equatable {
    /// A remote folder — v1.0 downloads files only.
    case remoteFolder(location: String)
    /// A remote symlink — the listing does not say what it points at, so
    /// a folder behind it cannot be told from a file.
    case remoteLink(location: String)
    /// A remote device, socket or pipe — nothing to download.
    case remoteSpecial(location: String)
    /// A remote file larger than a drag will download.
    case tooLarge(location: String, limit: Int64)
    /// A name whose bytes no path string carries exactly.
    case unrepresentableName
    /// The name is no longer in the pane's listing.
    case notListed

    /// The transcript line for this refusal — one per refused entry.
    public func line(name: String) -> String {
        switch self {
        case .remoteFolder(let location):
            "\(location) is a folder — drag out files, or copy it to a local pane first"
        case .remoteLink(let location):
            "\(location) is a link — drag out the file it points to, or copy it to a local pane first"
        case .remoteSpecial(let location):
            "\(location) is not a regular file — nothing to download"
        case .tooLarge(let location, let limit):
            "\(location) is larger than \(limit.formatted(.byteCount(style: .memory))) — copy it to a local pane instead"
        case .unrepresentableName:
            "\(name) — this name is not valid UTF-8, so no path can carry it out of the pane"
        case .notListed:
            "\(name) is no longer listed here — refresh and drag again"
        }
    }
}

/// Composes a drag-out from a pane's state.
///
/// Pure: no I/O, no AppKit.
public enum DragOutPlan {
    /// The most a drag downloads from a remote host, per file — 1 GiB.
    ///
    /// Drag-out is a convenience: the receiver waits on the drop until the
    /// bytes land. Anything bigger is a copy to a local pane, with a plan.
    public static let remoteCeiling: Int64 = 1 << 30

    /// The names a drag carries — Finder's manners.
    ///
    /// When the dragged row is inside the selection, the whole selection is
    /// dragged, in listing order. Otherwise only the dragged row.
    ///
    /// - Parameters:
    ///   - dragged: The name of the row under the mouse.
    ///   - selectedInOrder: The selected names, in listing order.
    /// - Returns: The names the drag carries, in order.
    public static func names(dragged: Data, selectedInOrder: [Data]) -> [Data] {
        selectedInOrder.contains(dragged) ? selectedInOrder : [dragged]
    }

    /// One outbound item per dragged name, in the order given.
    ///
    /// - Parameters:
    ///   - host: The pane's host; ``PalanaCore/localHostName`` is this Mac.
    ///   - directory: The pane's directory.
    ///   - names: The dragged names (see ``names(dragged:selectedInOrder:)``).
    ///   - entries: The pane's listing — kind and size come from here.
    /// - Returns: One item per name, refusals included.
    public static func items(
        host: String,
        directory: String,
        names: [Data],
        entries: [FileEntry]
    ) -> [DragOutItem] {
        let byName = Dictionary(entries.map { ($0.nameData, $0) }) { first, _ in first }
        return names.map { name in
            guard let entry = byName[name] else {
                return .refused(name: displayName(name), reason: .notListed)
            }
            return item(for: entry, host: host, directory: directory)
        }
    }

    /// The outbound item for one listed entry.
    static func item(for entry: FileEntry, host: String, directory: String) -> DragOutItem {
        guard let exact = entry.exactName else {
            return .refused(name: entry.name, reason: .unrepresentableName)
        }
        let path = join(directory, exact)
        if host == PalanaCore.localHostName {
            // A local URL carries folders, links and files alike — the
            // receiver (Finder, a browser) decides what it accepts.
            return .localFile(path: path)
        }
        let location = "\(host):\(path)"
        switch entry.kind {
        case .file:
            guard entry.size <= remoteCeiling else {
                return .refused(name: exact, reason: .tooLarge(location: location, limit: remoteCeiling))
            }
            return .remoteFile(host: host, path: path, size: entry.size)
        case .directory:
            return .refused(name: exact, reason: .remoteFolder(location: location))
        case .symlink:
            return .refused(name: exact, reason: .remoteLink(location: location))
        case .other:
            return .refused(name: exact, reason: .remoteSpecial(location: location))
        }
    }

    /// Joins a directory and a name, `/` without doubling.
    static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// A name for display only — lossy, never for composition.
    private static func displayName(_ data: Data) -> String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)  // lossy is the point: every name displays
    }
}
