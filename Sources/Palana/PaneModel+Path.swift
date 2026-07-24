// PaneModel+Path — the pane's path arithmetic (UTF-8 v1, per ho-04's named
// limitation), split from PaneModel for the type-body-length budget. Pure
// string ops on POSIX paths, so they hold for local and remote hosts alike;
// `parentPath`/`lastComponent` back the "point at a file → land in its folder"
// reveal.

import Foundation

extension PaneModel {
    nonisolated static func childPath(of path: String, name: String) -> String {
        path == "/" ? "/\(name)" : "\(path)/\(name)"
    }

    nonisolated static func parentPath(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let cut = trimmed.lastIndex(of: "/"), cut != trimmed.startIndex else { return "/" }
        return String(trimmed[..<cut])
    }

    nonisolated static func lastComponent(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let cut = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: cut)...])
    }

    nonisolated static func nameSansExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
