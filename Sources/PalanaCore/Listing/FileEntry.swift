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

    // MARK: — Coding keys

    private enum CodingKeys: String, CodingKey {
        case nameData, kind, size, modified, permissions, owner, group, symlinkTarget
        case created, changed
    }

    // MARK: — Stored properties

    /// The filename as bytes — the truth commands compose from.
    public var nameData: Data
    /// The entry's kind.
    public var kind: Kind
    /// Size in bytes, as the remote reported it.
    public var size: Int64
    /// Modification time — fractional seconds where the userland gives them.
    public var modified: Date
    /// Creation time — BSD only; nil on GNU and BusyBox.
    ///
    /// Absent from pre-9.8 cache and session data on disk; decodes to nil.
    public var created: Date?
    /// Status-change time — BSD and GNU (`%C@`); nil on BusyBox.
    ///
    /// Absent from pre-9.8 cache and session data on disk; decodes to nil.
    public var changed: Date?
    /// Permission bits, octal — `644`.
    public var permissions: String
    /// Owning user name.
    public var owner: String
    /// Owning group name.
    public var group: String
    /// Where a symlink points, as bytes. nil for everything else.
    public var symlinkTarget: Data?

    // MARK: — Init

    /// Assembles an entry from parsed facts.
    public init(
        nameData: Data,
        kind: Kind,
        size: Int64,
        modified: Date,
        created: Date? = nil,
        changed: Date? = nil,
        permissions: String,
        owner: String,
        group: String,
        symlinkTarget: Data? = nil
    ) {
        self.nameData = nameData
        self.kind = kind
        self.size = size
        self.modified = modified
        self.created = created
        self.changed = changed
        self.permissions = permissions
        self.owner = owner
        self.group = group
        self.symlinkTarget = symlinkTarget
    }

    // MARK: — Codable

    /// Decodes an entry, tolerating absent ``created`` and ``changed``
    /// fields so pre-9.8 cache and session files still load.
    public init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        nameData = try keyed.decode(Data.self, forKey: .nameData)
        kind = try keyed.decode(Kind.self, forKey: .kind)
        size = try keyed.decode(Int64.self, forKey: .size)
        modified = try keyed.decode(Date.self, forKey: .modified)
        created = try keyed.decodeIfPresent(Date.self, forKey: .created)
        changed = try keyed.decodeIfPresent(Date.self, forKey: .changed)
        permissions = try keyed.decode(String.self, forKey: .permissions)
        owner = try keyed.decode(String.self, forKey: .owner)
        group = try keyed.decode(String.self, forKey: .group)
        symlinkTarget = try keyed.decodeIfPresent(Data.self, forKey: .symlinkTarget)
    }

    /// Encodes all fields including the optional timestamps.
    public func encode(to encoder: any Encoder) throws {
        var keyed = encoder.container(keyedBy: CodingKeys.self)
        try keyed.encode(nameData, forKey: .nameData)
        try keyed.encode(kind, forKey: .kind)
        try keyed.encode(size, forKey: .size)
        try keyed.encode(modified, forKey: .modified)
        try keyed.encodeIfPresent(created, forKey: .created)
        try keyed.encodeIfPresent(changed, forKey: .changed)
        try keyed.encode(permissions, forKey: .permissions)
        try keyed.encode(owner, forKey: .owner)
        try keyed.encode(group, forKey: .group)
        try keyed.encodeIfPresent(symlinkTarget, forKey: .symlinkTarget)
    }

    /// The name bytes are the identity.
    public var id: Data { nameData }

    /// True for dotfiles — judged on the bytes, not the face.
    public var isHidden: Bool { nameData.first == UInt8(ascii: ".") }

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
