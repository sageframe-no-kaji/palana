// PaneModel+Address — the one funnel every typed address goes through.
// Extracted from PaneModel.swift to keep that file within the file-length
// limit, same move as PaneModel+Path and PaneModel+ZFSMode.
//
// Normalization, the grammar, and host resolution all live in PalanaCore's
// TypedAddress; the pane contributes exactly one fact — its current host,
// for the `:` shorthand — and then points or refuses. A bare path is this
// Mac by grammar, not by probing: nothing here asks any host whether a
// path exists before deciding where it belongs.

import Foundation
import PalanaCore

extension PaneModel {
    /// Points from a typed address — the one funnel for every entry point.
    ///
    /// The header field and the go-to sheet both land here with the raw
    /// text; ``resolveAddress(_:currentHost:)`` decides host and path, and
    /// the pane either points there or shows the refusal in place. A path
    /// that then turns out to be a file, absent, or unreadable is the
    /// read's business, exactly as for any other pointing.
    func pointAddress(_ address: String) {
        switch Self.resolveAddress(address, currentHost: state.host) {
        case .success(let resolved):
            point(host: resolved.host, path: resolved.path)
        case .failure(let refusal):
            refuseAddress(refusal.description)
        }
    }

    /// What a typed address points at from a pane on `currentHost` — pure.
    ///
    /// - Parameters:
    ///   - address: The raw typed or pasted text.
    ///   - currentHost: The pane's host, nil when it points nowhere.
    /// - Returns: The resolved host and path, or the refusal to show.
    nonisolated static func resolveAddress(
        _ address: String,
        currentHost: String?
    ) -> Result<ResolvedAddress, AddressParseError> {
        do {
            return .success(try TypedAddress.resolve(address, currentHost: currentHost))
        } catch {
            return .failure(error)
        }
    }
}
