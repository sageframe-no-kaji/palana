// Conservative path recovery for a resolved address — what happens after
// the grammar has named the host and the path, when that exact path may
// not exist on that host. Pure policy over an injected existence probe:
// the probe is the only thing that touches a filesystem or a wire, and it
// is asked about the resolved host only. No other host is ever searched,
// and nothing here reinterprets the grammar's host decision.
//
// The order is fixed and stops at the first hit: the exact path (a real
// name may end in punctuation, so an exact match is never altered); then
// exactly one trailing prose character removed, accepted only when that
// path exists; then the longest existing directory ancestor, with the
// unresolved remainder carried along for display. `/` is never a recovery
// unless `/` was asked for. Every outcome names what it did, so no caller
// can land somewhere other than the requested address in silence.

import Foundation

/// What an existence probe reports about one absolute path on one host.
public enum PathPresence: Equatable, Sendable {
    /// The path is a directory (a symlink to one counts).
    case directory
    /// The path exists and is not a directory.
    case file
    /// Nothing is there — or nothing the probe is allowed to see.
    case absent
}

/// A probe that answers for one absolute path on the resolved host.
///
/// Throwing means the host could not be asked at all — unreachable, the
/// door refused — and recovery reports that as a lookup failure rather
/// than guessing or asking anyone else.
public typealias PathProbe = @Sendable (String) async throws -> PathPresence

/// Why a resolved address could not be recovered to any destination.
public enum AddressRecoveryError: Error, Equatable, Sendable {
    /// Neither the path, its one-character correction, nor any ancestor
    /// short of `/` exists on the host.
    case notFound(ResolvedAddress)
    /// The host could not be asked — the probe failed before it answered.
    case lookupFailed(ResolvedAddress, reason: String)
}

extension AddressRecoveryError: CustomStringConvertible {
    /// The one line a pane or sheet shows for the refusal.
    public var description: String {
        switch self {
        case .notFound(let address):
            "no such path on \(address.scopeName): \(address.path) — nothing above it exists but /"
        case .lookupFailed(let address, let reason):
            "could not look up \(address.path) on \(address.scopeName): \(reason)"
        }
    }
}

/// Where a resolved address lands, and what it took to get there.
///
/// The destination is always on the requested host. Every case other than
/// ``exact(_:)`` carries a ``notice`` naming the change, and callers show
/// it: a corrected or recovered landing is never presented as the address
/// the operator asked for.
public enum AddressRecovery: Equatable, Sendable {
    /// The requested path exists as written.
    case exact(ResolvedAddress)
    /// The requested path did not exist, but it did once one trailing
    /// prose character came off — `removed` is that character.
    case punctuationCorrected(ResolvedAddress, requested: String, removed: Character)
    /// Neither the path nor its correction exists; the destination is the
    /// longest existing directory above it, and `unresolved` is the rest of
    /// the requested path, relative to that directory.
    case ancestorRecovered(ResolvedAddress, requested: String, unresolved: String)

    /// The address to point at.
    public var destination: ResolvedAddress {
        switch self {
        case .exact(let address), .punctuationCorrected(let address, _, _), .ancestorRecovered(let address, _, _):
            address
        }
    }

    /// The path the operator asked for, before any correction.
    public var requestedPath: String {
        switch self {
        case .exact(let address): address.path
        case .punctuationCorrected(_, let requested, _), .ancestorRecovered(_, let requested, _): requested
        }
    }

    /// True when the destination is not the path as requested.
    public var isCorrected: Bool {
        if case .exact = self { return false }
        return true
    }

    /// One quiet line naming the correction — nil for an exact landing.
    public var notice: String? {
        switch self {
        case .exact:
            nil
        case .punctuationCorrected(let address, _, let removed):
            "found \(Self.lastComponent(of: address.path)) — the pasted address ended in an extra \"\(removed)\""
        case .ancestorRecovered(let address, _, let unresolved):
            "\(unresolved) is not here — stopped at \(address.path), the deepest folder that exists"
        }
    }

    /// The final name in a path — the notice names the file, not the
    /// directory the pane already shows.
    static func lastComponent(of path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// The trailing characters prose attaches to a path.
    ///
    /// Sentence punctuation, closing brackets, closing quotes. Exactly one
    /// of these may come off the end of a path that does not exist, and
    /// only when what remains does. Nothing else is ever removed.
    public static let terminalProse: Set<Character> = [
        ".", ",", ";", ":", "!", "?", ")", "]", "'", "\"", "\u{2019}", "\u{201D}",
    ]

    /// Recovers a resolved address on its own host — the one policy.
    ///
    /// The probe is asked about the resolved host only, one question per
    /// path examined, in this order and stopping at the first hit: the
    /// exact path; the path minus one trailing ``terminalProse`` character;
    /// each ancestor from the nearest upward, accepted only when it is a
    /// directory and is not `/`.
    ///
    /// - Parameters:
    ///   - address: The resolved host and absolute path — `~` must already
    ///     be expanded by the host that owns it.
    ///   - probe: Answers for a path on that host; throws when the host
    ///     cannot be asked.
    /// - Returns: Where to point, with the correction named.
    /// - Throws: ``AddressRecoveryError`` — nothing useful exists, or the
    ///   host could not be asked.
    public static func recover(
        _ address: ResolvedAddress,
        probe: PathProbe
    ) async throws(AddressRecoveryError) -> Self {
        let requested = address.path
        if try await presence(of: requested, address, probe) != .absent {
            return .exact(address)
        }
        if let removed = requested.last, terminalProse.contains(removed) {
            let corrected = String(requested.dropLast())
            if !corrected.isEmpty, try await presence(of: corrected, address, probe) != .absent {
                return .punctuationCorrected(
                    ResolvedAddress(host: address.host, path: corrected, usesCurrentHost: address.usesCurrentHost),
                    requested: requested,
                    removed: removed)
            }
        }
        var ancestor = parent(of: requested)
        while ancestor != "/" {
            if try await presence(of: ancestor, address, probe) == .directory {
                return .ancestorRecovered(
                    ResolvedAddress(host: address.host, path: ancestor, usesCurrentHost: address.usesCurrentHost),
                    requested: requested,
                    unresolved: remainder(of: requested, below: ancestor))
            }
            ancestor = parent(of: ancestor)
        }
        throw .notFound(address)
    }

    /// One probe, with its failure typed as the lookup failing.
    private static func presence(
        of path: String,
        _ address: ResolvedAddress,
        _ probe: PathProbe
    ) async throws(AddressRecoveryError) -> PathPresence {
        do {
            return try await probe(path)
        } catch {
            throw .lookupFailed(address, reason: String(describing: error))
        }
    }

    // MARK: - Path arithmetic

    /// The directory above a POSIX path; `/` is its own parent.
    static func parent(of path: String) -> String {
        let trimmed = trimmingTrailingSlashes(path)
        guard let cut = trimmed.lastIndex(of: "/"), cut != trimmed.startIndex else { return "/" }
        return String(trimmed[..<cut])
    }

    /// The part of `path` below `ancestor`, without the joining slash.
    static func remainder(of path: String, below ancestor: String) -> String {
        let trimmed = trimmingTrailingSlashes(path)
        guard trimmed.hasPrefix(ancestor + "/") else { return trimmed }
        return String(trimmed.dropFirst(ancestor.count + 1))
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        return String(trimmed)
    }
}
