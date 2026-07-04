// The FileEntry — the contract the Surface renders and the Plan Engine
// composes against. Bytes are the truth, String is the face: Linux
// filenames promise no encoding, and nothing here pretends they were
// ever text.

import Foundation

/// One directory entry as the Listing reports it.
///
/// Identity is the name bytes — one directory cannot hold two of them.
public struct FileEntry: Sendable, Equatable, Hashable, Identifiable, Codable {
    /// What kind of thing the entry is.
    public enum Kind: String, Codable, Sendable {
        /// A regular file.
        case file
        /// A directory.
        case directory
        /// A symbolic link — ``FileEntry/symlinkTarget`` carries where.
        case symlink
        /// Everything else: sockets, pipes, devices.
        case other
    }

    /// The filename as bytes — the truth commands compose from.
    public var nameData: Data
    /// The entry's kind.
    public var kind: Kind
    /// Size in bytes, as the remote reported it.
    public var size: Int64
    /// Modification time — fractional seconds where the userland gives them.
    public var modified: Date
    /// Permission bits, octal — `644`.
    public var permissions: String
    /// Owning user name.
    public var owner: String
    /// Owning group name.
    public var group: String
    /// Where a symlink points, as bytes. nil for everything else.
    public var symlinkTarget: Data?

    /// Assembles an entry from parsed facts.
    public init(
        nameData: Data,
        kind: Kind,
        size: Int64,
        modified: Date,
        permissions: String,
        owner: String,
        group: String,
        symlinkTarget: Data? = nil
    ) {
        self.nameData = nameData
        self.kind = kind
        self.size = size
        self.modified = modified
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.symlinkTarget = symlinkTarget
    }

    /// The name bytes are the identity.
    public var id: Data { nameData }

    /// The filename for display — lossy UTF-8, never for composition.
    public var name: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: nameData, as: UTF8.self)  // lossy is the point: every name displays
    }

    /// The symlink target for display — lossy UTF-8, never for composition.
    public var symlinkTargetName: String? {
        // swiftlint:disable:next optional_data_string_conversion
        symlinkTarget.map { String(decoding: $0, as: UTF8.self) }  // lossy is the point
    }
}
