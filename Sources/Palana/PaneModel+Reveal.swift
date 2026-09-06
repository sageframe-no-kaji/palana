// Revealing in Finder — the local pane's "open in Finder" resolution and
// the byte-accurate path plumbing it rides on. Split from PaneModel.swift
// when the exact-path boundary pushed that file past the lint budget; the
// behavior is unchanged.

import AppKit
import Foundation
import PalanaCore

// MARK: - Revealing in Finder (local panes only)

/// What a right-click on a local pane resolves to for "open in Finder".
///
/// Two shapes, because Finder answers them with two different calls: rows are
/// *revealed* (selected inside their folder), a bare directory is *opened*.
enum RevealTarget: Equatable {
    /// Reveal these absolute paths, byte-accurate, selected in a Finder window.
    case entries([Data])
    /// Open this directory — the pane's own, right-clicked on empty space.
    case directory(String)
}

extension PaneModel {
    /// Resolves a right-click into what Finder should show.
    ///
    /// Selection manners match ``PaneView/operate(_:ids:)`` and
    /// `dragPayload(for:selectedNames:)` exactly: a clicked row inside the
    /// selection carries the whole selection; a clicked row outside it carries
    /// only itself; an empty click resolves to the pane's own directory.
    /// Entry paths come back in the listing's canonical byte order so the
    /// result is stable.
    ///
    /// - Parameters:
    ///   - directory: The pane's current directory path.
    ///   - selection: The pane's selected entry ids (name bytes).
    ///   - ids: The right-clicked entry ids; empty for a click on open space.
    /// - Returns: The entries to reveal, or the directory to open.
    nonisolated static func revealTargets(
        directory: String,
        selection: Set<Data>,
        ids: Set<Data>
    ) -> RevealTarget {
        guard !ids.isEmpty else { return .directory(directory) }
        let inSelection = !selection.isEmpty && ids.isSubset(of: selection)
        let names = (inSelection ? selection : ids)
            .sorted { $0.lexicographicallyPrecedes($1) }
        return .entries(names.map { childPathData(of: directory, name: $0) })
    }

    /// Joins a directory path and a raw name into an absolute path, byte-accurate.
    ///
    /// The byte-honest twin of ``childPath(of:name:)``: the name never passes
    /// through `String`, so a name that is not valid UTF-8 survives the join
    /// intact instead of arriving at Finder with replacement characters.
    nonisolated static func childPathData(of path: String, name: Data) -> Data {
        var joined = Data(path == "/" ? "/".utf8 : "\(path)/".utf8)
        joined.append(name)
        return joined
    }

    /// Builds a file URL from raw path bytes without a lossy `String` hop.
    ///
    /// `URL(fileURLWithPath:)` takes a `String`, which cannot carry a non-UTF-8
    /// name. `NSURL` is the initializer here, not its Swift `URL` twin: the
    /// overlay's `URL(fileURLWithFileSystemRepresentation:…)` replaces bytes
    /// that are not valid UTF-8 with U+FFFD, while `NSURL`'s carries them
    /// through untouched (measured 2026-07-27). A NUL terminator is appended
    /// because the initializer wants a C string — POSIX names cannot contain
    /// NUL, so nothing is truncated.
    nonisolated static func fileURL(forPathBytes bytes: Data) -> URL {
        var cString = bytes.map { Int8(bitPattern: $0) }
        cString.append(0)
        return NSURL(
            fileURLWithFileSystemRepresentation: cString,
            isDirectory: false,
            relativeTo: nil) as URL
    }

    /// Shows the right-clicked rows — or the pane's directory — in Finder.
    ///
    /// Local panes only: a remote path names nothing this Mac can open, and the
    /// menu item is absent there. The resolution lives in
    /// ``revealTargets(directory:selection:ids:)``; this hands the result to
    /// `NSWorkspace`.
    func revealInFinder(ids: Set<FileEntry.ID>) {
        guard isLocalPane else { return }
        switch Self.revealTargets(directory: state.path, selection: state.selection, ids: ids) {
        case .entries(let paths):
            NSWorkspace.shared.activateFileViewerSelecting(paths.map(Self.fileURL(forPathBytes:)))
        case .directory(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}
