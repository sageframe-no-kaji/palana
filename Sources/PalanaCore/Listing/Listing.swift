// The Listing — remote directory reading, one command per read. The
// flavor fact from ho-03's probe selects the command path; the caller
// passes it in, because the Listing holds no Field and discovers
// nothing. Same taxonomy discipline as the Conduit, one layer up: the
// Conduit types door failures, the Listing types read failures.

import Foundation

/// Read failures, classified from the listing command's stderr.
///
/// A door-level failure is not one of these — ``ConduitError`` throws
/// through untouched.
public enum ListingError: Error, Equatable, Sendable {
    /// The directory does not exist.
    case directoryNotFound(path: String)
    /// The directory exists and refused us.
    case permissionDenied(path: String)
    /// The path names something that is not a directory.
    case notADirectory(path: String)
    /// The command failed some other way — typed, never swallowed.
    case listingFailed(exitStatus: Int32, stderr: String)
    /// The command succeeded but its output did not parse. A fixture or
    /// userland surprise, worth surfacing loudly.
    case malformedListing

    /// Classifies a nonzero listing exit from its stderr.
    static func classify(path: String, exitStatus: Int32, stderr: String) -> Self {
        let text = stderr.lowercased()
        if text.contains("no such file or directory") {
            return .directoryNotFound(path: path)
        }
        if text.contains("permission denied") {
            return .permissionDenied(path: path)
        }
        if text.contains("not a directory") {
            return .notADirectory(path: path)
        }
        return .listingFailed(exitStatus: exitStatus, stderr: stderr)
    }
}

/// Remote directory reading over the Conduit.
public struct Listing: Sendable {
    private let conduit: any Conduit

    /// A listing over the given door.
    public init(conduit: any Conduit) {
        self.conduit = conduit
    }

    /// The exact command a listing runs for a path on a flavor —
    /// exposed so tests and transcripts pin it.
    public static func command(for path: String, flavor: UserlandFlavor) -> String {
        switch flavor {
        case .gnu: GNUListingParser.command(for: path)
        case .bsd: BSDListingParser.command(for: path)
        case .busybox: BusyBoxListingParser.command(for: path)
        }
    }

    /// Reads one directory in one round trip.
    ///
    /// Entries return sorted by name bytes — a deterministic contract;
    /// display order is ``PaneState``'s business. The flavor comes from
    /// the Field's capability fact, passed by the caller.
    public func list(
        on host: String,
        path: String,
        flavor: UserlandFlavor
    ) async throws -> [FileEntry] {
        let result = try await conduit.run(on: host, Self.command(for: path, flavor: flavor))
            .collect()
        guard result.exitStatus == 0 else {
            throw ListingError.classify(
                path: path, exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        return switch flavor {
        case .gnu: try GNUListingParser.parse(result.stdout)
        case .bsd: try BSDListingParser.parse(result.stdout)
        case .busybox: try BusyBoxListingParser.parse(result.stdoutText)
        }
    }

    /// The exact command a file read runs — exposed so tests pin it.
    public static func readFileCommand(for path: String) -> String {
        "cat \(ShellQuote.quote(path))"
    }

    /// Reads one file's bytes in one round trip.
    ///
    /// The Surface's open verb — the pane fetches, writes a temp copy,
    /// and hands it to the system. Composition stays here because the
    /// Surface never composes shell commands.
    public func readFile(on host: String, path: String) async throws -> Data {
        let result = try await conduit.run(on: host, Self.readFileCommand(for: path)).collect()
        guard result.exitStatus == 0 else {
            throw ListingError.classify(
                path: path, exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        return result.stdout
    }

    /// The recursive size fact for each path, one round trip.
    ///
    /// The plan gathers these fresh, per plan — a size promise with a
    /// timestamp is still a lie. Composition and parsing live in
    /// ``TreeSize``.
    public func treeSizes(
        on host: String,
        paths: [String],
        flavor: UserlandFlavor
    ) async throws -> [RecursiveSize] {
        guard !paths.isEmpty else { return [] }
        // BusyBox's find cannot walk by type — no facts, and the plan
        // shows the inode floor with its flag, ho-06.5's honesty.
        guard flavor != .busybox else { return [] }
        let command = TreeSize.command(for: paths, flavor: flavor)
        let result = try await conduit.run(on: host, command).collect()
        guard result.exitStatus == 0 else {
            throw ListingError.listingFailed(
                exitStatus: result.exitStatus, stderr: result.stderrText)
        }
        return try TreeSize.parse(result.stdoutText, expecting: paths.count)
    }
}
