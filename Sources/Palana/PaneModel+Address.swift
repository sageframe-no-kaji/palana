// PaneModel+Address — the one funnel every typed address goes through, and
// the local-first rule behind a bare absolute path. Extracted from
// PaneModel.swift to keep that file within the file-length limit, same move
// as PaneModel+Path and PaneModel+ZFSMode.
//
// The classification itself lives in PalanaCore's TypedAddress; what a bare
// path *resolves to* is a Surface judgement and lives here.

import Foundation
import PalanaCore

/// Where a colon-free absolute path resolved to.
enum BarePathResolution: Equatable {
    /// It exists on this Mac — point here.
    case here(String)
    /// It is absent here but present on the pane's remote host — point there.
    case there(host: String, path: String)
    /// Neither place has it — refuse, naming both.
    case nowhere(path: String, remoteHost: String?)
}

extension PaneModel {
    /// Points from a typed address — the one funnel for every entry point.
    ///
    /// `host:path` points at that host. A bare alias means that host's home.
    /// A bare absolute path names no host, so it resolves local first: if it
    /// exists on this Mac the pane points here, otherwise the pane's remote
    /// host is tried, and a path found in neither place refuses by name.
    func pointAddress(_ address: String) {
        guard let typed = TypedAddress.classify(address) else { return }
        switch typed {
        case .hostPath(let host, let path): point(host: host, path: path)
        case .host(let alias): point(host: alias, path: "~")
        case .barePath(let path): pointBarePath(path)
        }
    }

    /// Resolves a bare absolute path against this Mac first, then a remote host.
    ///
    /// Local first is the decided order: the dominant case is a path pasted
    /// from Finder or another Mac app. A path that exists in both places
    /// resolves here — an operator who means the remote one types `host:path`.
    /// `existsThere` is never awaited when the local check succeeds, so no
    /// network round trip precedes a local hit.
    ///
    /// - Parameters:
    ///   - path: The `/`-leading path, exactly as typed.
    ///   - remoteHost: The pane's host when it is a remote one, nil otherwise.
    ///   - existsHere: The local existence check.
    ///   - existsThere: The remote existence check — one round trip, at most.
    /// - Returns: Where to point, or the refusal.
    ///
    /// MainActor-isolated, not `nonisolated`: the remote probe closure reaches
    /// the pane's engine, and keeping both checks in one isolation domain is
    /// what lets them stay plain closures under strict concurrency.
    static func resolveBarePath(
        _ path: String,
        remoteHost: String?,
        existsHere: (String) async -> Bool,
        existsThere: (String) async -> Bool
    ) async -> BarePathResolution {
        if await existsHere(path) { return .here(path) }
        guard let remoteHost else { return .nowhere(path: path, remoteHost: nil) }
        if await existsThere(path) { return .there(host: remoteHost, path: path) }
        return .nowhere(path: path, remoteHost: remoteHost)
    }

    /// The refusal line for a path found in neither place — both are named.
    nonisolated static func bareRefusal(path: String, remoteHost: String?) -> String {
        guard let remoteHost else { return "not found on this Mac: \(path)" }
        return "not found on this Mac or \(remoteHost): \(path)"
    }
}
