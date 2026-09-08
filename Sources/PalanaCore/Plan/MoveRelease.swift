// The move's release — what authorises a delete, and the POSIX-sh
// program that freezes the source before anything is proved about it.
//
// A move used to manifest the source, manifest the destination, and
// then release a Boolean gate. Manifests are snapshots, not a binding:
// a source edited after its manifest could be deleted without ever
// reaching the destination, and a destination changed after its
// manifest could authorise that deletion from stale evidence
// (2026-09-08 audit). Here the source's top-level entries are first
// moved into a visible, operation-owned directory beside them — a
// rename on the same filesystem, so nothing is copied and nothing is
// lost — and only those frozen bytes are manifested and then removed.
// A newly created entry at an original pathname is a different object
// living at a name this operation no longer holds, and it is never
// touched.

import Foundation

/// The frozen source a move's delete is bound to.
///
/// Carried on the plan so enactment manifests the quarantine rather
/// than the pathnames the operator has since released, and so a plan
/// composed before this binding existed cannot release a delete at all.
public struct MoveRelease: Codable, Sendable, Equatable {
    /// The host the source lives on.
    public var host: String

    /// The directory the entries were selected in.
    public var sourceDirectory: String

    /// The operation-owned directory the entries are frozen in.
    public var quarantineDirectory: String

    /// The selected entries' bare names, as they stand in the quarantine.
    public var names: [String]

    /// The operation token — makes the quarantine identity unique.
    public var token: String

    /// Binds a delete to a frozen source.
    ///
    /// - Parameters:
    ///   - host: The host the source lives on.
    ///   - sourceDirectory: The directory the entries were selected in.
    ///   - names: The selected entries' bare names.
    ///   - token: The operation token.
    public init(host: String, sourceDirectory: String, names: [String], token: String) {
        self.host = host
        self.sourceDirectory = sourceDirectory
        self.quarantineDirectory = Self.quarantineDirectory(in: sourceDirectory, token: token)
        self.names = names
        self.token = token
    }

    /// The quarantine's bare name, unique to the operation.
    ///
    /// Deliberately not hidden: a source left here by an interrupted
    /// move must be findable by looking, not by knowing.
    public static func quarantineName(token: String) -> String { "palana-recover-\(token)" }

    /// The quarantine's full path under a source directory.
    public static func quarantineDirectory(in source: String, token: String) -> String {
        source == "/" ? "/\(quarantineName(token: token))" : "\(source)/\(quarantineName(token: token))"
    }

    /// The sentence naming where an interrupted move left the source.
    public var recoverySentence: String {
        "the source is set aside at \(host):\(quarantineDirectory) — nothing was deleted"
    }

    /// The freeze — one rename per selected entry into the quarantine.
    ///
    /// Runs before any manifest. Creating the directory with a bare
    /// `mkdir` refuses a name that already exists, so one operation's
    /// quarantine can never be another's. A rename that fails leaves
    /// every byte where it stands and names the directory to look in.
    ///
    /// - Returns: One POSIX-sh program.
    public func quarantineProgram() -> String {
        let directory = ShellQuote.quote(quarantineDirectory)
        let paths =
            names
            .map { ShellQuote.quote(sourceDirectory == "/" ? "/\($0)" : "\(sourceDirectory)/\($0)") }
            .joined(separator: " ")
        let refused = ShellQuote.quote(
            "palana-refused: \(host):\(quarantineDirectory) could not be created — nothing was moved or deleted")
        let retained = ShellQuote.quote(
            "palana-retained: \(host):\(quarantineDirectory) — "
                + "the source was not fully set aside; nothing was deleted")
        return [
            "mkdir -- \(directory) || { echo \(refused) >&2; exit 3; }",
            "mv -- \(paths) \(directory)/ || { echo \(retained) >&2; exit 3; }",
        ].joined(separator: "; ")
    }

    /// The release — the frozen bytes removed, and nothing else.
    public func releaseProgram() -> String {
        "rm -rf -- \(ShellQuote.quote(quarantineDirectory))"
    }
}

/// The evidence that authorises a move's delete.
///
/// Not a Boolean: the delete's authority is this value, carrying the
/// frozen source's identity and both manifests that were read of it
/// after the freeze. Enactment refuses a delete it cannot produce one
/// for.
public struct MoveReleaseAuthorization: Sendable, Equatable {
    /// The frozen source the delete is bound to.
    public var release: MoveRelease
    /// The manifest of the quarantined source, read after the freeze.
    public var source: TransferManifest
    /// The manifest of the destination, read after the freeze.
    public var destination: TransferManifest

    /// Records what authorised a delete.
    ///
    /// - Parameters:
    ///   - release: The frozen source.
    ///   - source: The quarantined source's manifest.
    ///   - destination: The destination's manifest.
    public init(release: MoveRelease, source: TransferManifest, destination: TransferManifest) {
        self.release = release
        self.source = source
        self.destination = destination
    }

    /// The source entry the destination does not carry identically, if any.
    ///
    /// The subset rule: entries the destination holds beyond these are
    /// its own — a merge keeps what stood there. Nil means every frozen
    /// source entry is represented at the destination.
    public var firstUnmatched: String? { source.firstUnmatched(in: destination) }
}
