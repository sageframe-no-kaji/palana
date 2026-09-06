// PaneModel+Address — the one funnel every typed address goes through.
// Extracted from PaneModel.swift to keep that file within the file-length
// limit, same move as PaneModel+Path and PaneModel+ZFSMode.
//
// Normalization, the grammar, host resolution, and the recovery policy all
// live in PalanaCore (TypedAddress, AddressRecovery); the pane contributes
// two facts — its current host, for the `:` shorthand, and the probe that
// asks the resolved host whether a path exists — and then points or
// refuses. A bare path is this Mac by grammar, not by probing: the probe
// runs on the host the grammar already chose and never on any other.

import Foundation
import PalanaCore

extension PaneModel {
    /// Points from a typed address — the one funnel for every entry point.
    ///
    /// The header field and the go-to sheet both land here with the raw
    /// text; ``resolveAddress(_:currentHost:)`` decides host and path,
    /// ``recover(_:)`` decides where on that host the pane can land, and
    /// the pane either points there — with the correction posted as a
    /// notice — or shows the refusal in place. A destination that then
    /// turns out to be a file is the read's business: it lands in the
    /// parent with the file revealed, exactly as for any other pointing.
    func pointAddress(_ address: String) {
        switch Self.resolveAddress(address, currentHost: state.host) {
        case .success(let resolved):
            recoverAndPoint(resolved)
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

    /// Where a resolved address lands on its own host — the authoritative
    /// recovery, shared by the go-to sheet's preview and the pointing.
    ///
    /// `~` is expanded by the host that owns it first, so the policy only
    /// ever sees absolute paths; the probe then runs on that host and no
    /// other. A host that cannot be asked is a lookup failure, never a
    /// reason to try somewhere else.
    ///
    /// - Parameter resolved: The host and path the grammar chose.
    /// - Returns: The recovery, with any correction named, or the refusal.
    func recover(_ resolved: ResolvedAddress) async -> Result<AddressRecovery, AddressRecoveryError> {
        var absolute = resolved
        if resolved.path == "~" || resolved.path.hasPrefix("~/") {
            do {
                let expanded = try await resolveTilde(resolved.path, host: resolved.host)
                absolute = ResolvedAddress(
                    host: resolved.host, path: expanded, usesCurrentHost: resolved.usesCurrentHost)
            } catch {
                return .failure(.lookupFailed(resolved, reason: String(describing: error)))
            }
        }
        do {
            return .success(try await AddressRecovery.recover(absolute, probe: probe(for: resolved.host)))
        } catch {
            return .failure(error)
        }
    }

    /// Recovers, then points — or refuses in place.
    private func recoverAndPoint(_ resolved: ResolvedAddress) {
        recoveryTask?.cancel()
        beginAddressRecovery()
        recoveryTask = Task {
            let outcome = await recover(resolved)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .success(let recovery):
                pendingAddressNotice = recovery.notice
                point(host: recovery.destination.host, path: recovery.destination.path)
            case .failure(let refusal):
                refuseAddress(refusal.description)
            }
        }
    }

    /// The existence probe for one host: the filesystem for this Mac, one
    /// `test` round trip through that host's listing otherwise.
    private func probe(for host: String) -> PathProbe {
        if isLocalHost(host) {
            return { path in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .absent }
                return isDirectory.boolValue ? .directory : .file
            }
        }
        let listing = listing(for: host)
        return { path in
            do {
                return try await listing.presence(on: host, path: path)
            } catch {
                throw ProbeFailure(description: Self.describe(error))
            }
        }
    }

    /// A remote probe that did not answer — the host's failure, in the
    /// pane's own words, carried as the lookup failure's reason.
    private struct ProbeFailure: Error, CustomStringConvertible {
        let description: String
    }
}
