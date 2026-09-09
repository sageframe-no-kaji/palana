// Manifest bytes for transcripts — the four NUL-terminated fields the
// real command writes, composed by hand so a RecordedConduit can play
// back a source and a destination that agree, or that do not.

import Foundation

@testable import PalanaCore

enum ManifestFixture {
    /// The SHA-256 of "hello" — a stable digest for fixtures.
    static let helloDigest = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
    /// The SHA-256 of "world" — a different stable digest.
    static let worldDigest = "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7"

    /// One record: kind letter, size, payload, name — each NUL-terminated.
    static func record(_ kind: String, size: String = "", payload: String = "", name: String) -> String {
        "\(kind)\u{0}\(size)\u{0}\(payload)\u{0}\(name)\u{0}"
    }

    /// A regular-file record.
    static func file(_ name: String, size: Int = 5, digest: String = helloDigest) -> String {
        record("f", size: "\(size)", payload: digest, name: name)
    }

    /// A directory record.
    static func directory(_ name: String) -> String {
        record("d", name: name)
    }

    /// A symlink record.
    static func symlink(_ name: String, target: String) -> String {
        record("l", payload: target, name: name)
    }

    /// The manifest command for a directory and names — the exact
    /// string a transcript must carry.
    static func command(_ directory: String, _ names: [String]) -> String {
        TransferManifest.command(directory: directory, names: names)
    }
}
