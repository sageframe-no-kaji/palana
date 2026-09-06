// An ssh config as read from disk — the exact bytes and the text they
// decode to, or a typed reason why neither is available. A config edit
// starts from a document and ends by replacing the same bytes; a read that
// cannot produce one refuses every edit. Absence is not failure: an
// unconfigured machine is a field with no named hosts.

import Foundation

/// Why an ssh config could not be read.
public enum SSHConfigReadError: Error, Equatable, Sendable {
    /// The path exists but its bytes could not be read — permissions, a
    /// directory at the path, an I/O fault. `reason` is the system's word.
    case unreadable(path: String, reason: String)
    /// The bytes are not valid UTF-8. Editing them as text would alter
    /// bytes the edit never meant to touch, so no edit is offered.
    case notUTF8(path: String)
}

/// The ssh config as it stands on disk.
///
/// `text` re-encodes to `bytes` exactly — the constructor verifies the
/// round trip — so a transform of the text changes only the bytes it
/// intends to. `posixPermissions` rides along so a replacement keeps the
/// file's mode.
public struct SSHConfigDocument: Equatable, Sendable {
    /// The file's bytes, exactly; empty when the file is absent.
    public let bytes: Data
    /// The bytes decoded as UTF-8, byte-for-byte reversible.
    public let text: String
    /// False when no file exists at the path.
    public let exists: Bool
    /// The file's mode bits, `nil` when the file is absent.
    public let posixPermissions: Int?

    /// The document for a path with no file.
    public static let absent = Self(bytes: Data(), text: "", exists: false, posixPermissions: nil)

    /// Decodes `bytes` strictly.
    ///
    /// Throws ``SSHConfigReadError/notUTF8(path:)`` when the bytes do not
    /// survive a decode-encode round trip unchanged.
    public init(bytes: Data, path: String, posixPermissions: Int?) throws(SSHConfigReadError) {
        // The lossy decode is verified byte-for-byte on the next line; the
        // failable `String(bytes:encoding:)` would drop a leading BOM and
        // break that exactness.
        // swiftlint:disable:next optional_data_string_conversion
        let decoded = String(decoding: bytes, as: UTF8.self)
        guard decoded.utf8.elementsEqual(bytes) else { throw .notUTF8(path: path) }
        self.init(bytes: bytes, text: decoded, exists: true, posixPermissions: posixPermissions)
    }

    /// A document from text pālana composed itself — the bytes are the
    /// text's UTF-8.
    public init(text: String, posixPermissions: Int?) {
        self.init(bytes: Data(text.utf8), text: text, exists: true, posixPermissions: posixPermissions)
    }

    private init(bytes: Data, text: String, exists: Bool, posixPermissions: Int?) {
        self.bytes = bytes
        self.text = text
        self.exists = exists
        self.posixPermissions = posixPermissions
    }

    /// Reads the file at `url`.
    ///
    /// A missing file is ``absent``. Anything else that stops the bytes
    /// from arriving is ``SSHConfigReadError/unreadable(path:reason:)``;
    /// bytes that are not UTF-8 are ``SSHConfigReadError/notUTF8(path:)``.
    /// Nothing is ever read as an empty configuration by mistake.
    public static func read(at url: URL) throws(SSHConfigReadError) -> Self {
        let path = url.path
        let bytes: Data
        switch rawBytes(at: url) {
        case .absent:
            return .absent
        case .failed(let reason):
            throw .unreadable(path: path, reason: reason)
        case .bytes(let data):
            bytes = data
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes?[.posixPermissions] as? Int
        return try Self(bytes: bytes, path: path, posixPermissions: permissions)
    }

    /// The outcome of reading a file's bytes, before any decoding.
    private enum RawRead {
        case absent
        case bytes(Data)
        case failed(reason: String)
    }

    /// Reads the bytes, telling a missing file apart from a failed read.
    ///
    /// Kept untyped on purpose: the Swift 6.2 compiler crashes in IR
    /// generation when an `NSError` catch sits inside a typed-throws body.
    private static func rawBytes(at url: URL) -> RawRead {
        do {
            return .bytes(try Data(contentsOf: url))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
                return .absent
            }
            return .failed(reason: error.localizedDescription)
        }
    }
}
