// PreviewRouter — the pure routing of the preview pane (ho-16).
//
// A pane in preview mode shows the file the *other* pane's cursor is on. This
// enum owns the decisions that don't need a running scene: is the source local
// or remote, is the file text or a quick-look type, and how a capped read
// decodes. The app layer does the I/O (reading the head, hosting QLPreviewView);
// everything decidable from a name, a host, and a head of bytes lives here and
// is unit-tested, so the routing that decides what the operator sees is checked
// truth, not a screen.

import Foundation

/// What the preview pane should render for the file under the source cursor.
public enum PreviewKind: Equatable, Sendable {
    /// A local text file — read it (capped) and show it scrollable, monospace.
    case text
    /// A local non-text, quick-lookable file — image, PDF, media — via QuickLook.
    case quickLook
    /// A local file that is not previewable as content (directory, symlink,
    /// device) — the info card renders, the content pane does not.
    case infoOnly
    /// The source cursor is on a remote file — the info card plus the honest
    /// "content preview is local-only for now" line. Never a fetch (ho-16 v1).
    case remoteInfoOnly
}

/// A capped, decoded text preview and whether the read hit the cap.
public struct PreviewText: Equatable, Sendable {
    /// The decoded text, at most `cap` bytes' worth.
    public let text: String
    /// True when the file was larger than the cap and the tail was dropped.
    public let truncated: Bool

    /// Assembles a capped text preview.
    public init(text: String, truncated: Bool) {
        self.text = text
        self.truncated = truncated
    }
}

/// The pure routing and reading rules of the preview pane.
public enum PreviewRouter {
    /// The read cap for local text — first 256 KB (ho-16 Decision 4).
    ///
    /// So a multi-GB log never hangs the UI; QuickLook streams large files itself.
    public static let textCap = 256 * 1024

    /// How much of a file's head the text sniff inspects.
    public static let sniffWindow = 8192

    /// The ceiling for fetching a remote binary to preview (ho-18) — 25 MB.
    ///
    /// Catches virtually every photo and PDF, skips videos and disk images. A
    /// remote binary above this stays the info card + local-only line, never a
    /// fetch. Gated on the listing's known `size`, before any wire read.
    public static let remoteBinaryCap = 25 * 1024 * 1024

    /// The binary extensions worth fetching from a remote host to preview —
    /// images, PDF, SVG (ho-18).
    ///
    /// Video, audio, and archives are deliberately absent: too large, and
    /// QuickLook can't stream them over the wire.
    public static let previewableBinaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif",
        "bmp", "webp", "ico", "pdf", "svg",
    ]

    /// The text-family extensions (lowercased, no leading dot) — ho-16 Decision 2.
    ///
    /// `.md`, configs, code, logs, and kin. Extensionless files (dotfiles,
    /// `Makefile`, `README`) are not here — they fall to the content sniff.
    public static let textExtensions: Set<String> = [
        // Prose and docs
        "md", "markdown", "txt", "text", "log", "rst", "adoc", "asciidoc", "org", "tex", "bib",
        // Config and data
        "conf", "cfg", "config", "yaml", "yml", "toml", "json", "jsonc", "ini", "env",
        "properties", "xml", "plist", "csv", "tsv", "diff", "patch",
        // Web
        "html", "htm", "css", "scss", "sass", "less",
        // Code
        "js", "jsx", "ts", "tsx", "mjs", "cjs", "py", "rb", "go", "rs", "swift",
        "c", "h", "cpp", "cc", "cxx", "hpp", "hh", "m", "mm", "java", "kt", "kts",
        "scala", "clj", "cljs", "ex", "exs", "erl", "hs", "ml", "php", "pl", "pm",
        "lua", "r", "jl", "dart", "groovy", "gradle", "cmake", "mk", "make",
        // Shells and scripts
        "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "sql", "awk", "sed",
        // Lockfiles and manifests that are text
        "lock", "sum", "mod", "gemspec", "podspec",
    ]

    /// The lowercased extension of a filename, or `nil` when there is none.
    ///
    /// A leading-dot name with no further dot (`.bashrc`, `.gitignore`) has no
    /// extension — it is a dotfile, routed by the content sniff, not by a name
    /// like "bashrc".
    public static func fileExtension(of name: String) -> String? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = name[name.index(after: dot)...].lowercased()
        return ext.isEmpty ? nil : ext
    }

    /// True when `name` carries a known text-family extension.
    public static func isTextExtension(_ name: String) -> Bool {
        guard let ext = fileExtension(of: name) else { return false }
        return textExtensions.contains(ext)
    }

    /// True when a file's head reads as text: no NUL byte and valid UTF-8.
    ///
    /// Only the first ``sniffWindow`` bytes are inspected. A multibyte UTF-8
    /// character cut at the window's tail is tolerated — up to three trailing
    /// bytes are dropped before deciding, so a valid text file is never called
    /// binary because the window split a character. An empty file reads as text.
    public static func looksLikeText(head: Data) -> Bool {
        guard !head.isEmpty else { return true }
        let window = head.prefix(sniffWindow)
        // A NUL byte is the strongest binary signal.
        if window.contains(0) { return false }
        // Clean UTF-8 all the way through — text.
        if String(bytes: window, encoding: .utf8) != nil { return true }
        // The only tolerated failure is a multibyte character cut at the tail:
        // strip trailing continuation bytes (0x80–0xBF) and one lead byte
        // (≥0xC0), then require the remainder to decode. A stray invalid byte
        // mid-stream (an 0xFF, a bad sequence) is not rescued this way — it is
        // binary, not a truncated character.
        var bytes = Array(window)
        var dropped = 0
        while let last = bytes.last, (0x80...0xBF).contains(last), dropped < 3 {
            bytes.removeLast()
            dropped += 1
        }
        if let last = bytes.last, last >= 0xC0 {
            bytes.removeLast()
        }
        return String(bytes: bytes, encoding: .utf8) != nil
    }

    /// Routes the file under the source cursor to a preview kind.
    ///
    /// - Parameters:
    ///   - isLocal: Whether the source pane's host is this Mac. Remote → the
    ///     honest local-only card, never a fetch (ho-16 Decision 5).
    ///   - entry: The ``FileEntry`` under the source cursor.
    ///   - contentHead: The first bytes of the local file, for the extensionless
    ///     sniff. `nil` when unread or not applicable.
    /// - Returns: The ``PreviewKind`` the pane should render.
    public static func route(isLocal: Bool, entry: FileEntry, contentHead: Data?) -> PreviewKind {
        guard isLocal else { return .remoteInfoOnly }
        guard entry.kind == .file else { return .infoOnly }
        // A known extension decides without reading: text family → text, any
        // other extension (images, PDF, media, archives) → quick-look.
        if let ext = fileExtension(of: entry.name) {
            return textExtensions.contains(ext) ? .text : .quickLook
        }
        // Extensionless — sniff the head. Text when it reads as text; otherwise
        // hand it to QuickLook. A missing head defaults to quick-look.
        guard let head = contentHead else { return .quickLook }
        return looksLikeText(head: head) ? .text : .quickLook
    }

    /// Decodes a read into a capped text preview.
    ///
    /// Past `cap` bytes the tail is dropped and `truncated` is set, so the view
    /// can show a "… (truncated)" footer. Decoding is lossy on purpose — a byte
    /// that isn't valid UTF-8 shows as the replacement character rather than
    /// blanking the preview.
    public static func decodeCapped(_ data: Data, cap: Int = textCap) -> PreviewText {
        if data.count > cap {
            let head = data.prefix(cap)
            // swiftlint:disable:next optional_data_string_conversion
            return PreviewText(text: String(decoding: head, as: UTF8.self), truncated: true)
        }
        // Lossy on purpose — an odd byte shows as the replacement character
        // rather than blanking the preview (same idiom as FileEntry.name).
        // swiftlint:disable:next optional_data_string_conversion
        return PreviewText(text: String(decoding: data, as: UTF8.self), truncated: false)
    }

    /// What to do for the file under a **remote** cursor (ho-18).
    public enum RemotePlan: Equatable, Sendable {
        /// Read a bounded head over the wire and show text (or sniff an
        /// extensionless file's head).
        case text
        /// Fetch the whole file (it is under the cap) and show it via QuickLook.
        case fetchBinary
        /// Show the info card + the honest local-only line — too big, not
        /// previewable, or not a file. Never a fetch.
        case infoOnly
    }

    /// Routes a remote cursor's file, size-gated on facts already held.
    ///
    /// Text (by extension) and extensionless files read a bounded head; a
    /// previewable-binary extension under ``remoteBinaryCap`` is fetched whole;
    /// everything else stays info-only. No fetch is ever planned that would have
    /// to be aborted for size.
    ///
    /// - Parameter entry: The ``FileEntry`` under the remote cursor.
    /// - Returns: The ``RemotePlan``.
    public static func remotePlan(entry: FileEntry) -> RemotePlan {
        guard entry.kind == .file else { return .infoOnly }
        // Extensionless → sniff via the head read (the text branch handles it).
        guard let ext = fileExtension(of: entry.name) else { return .text }
        if textExtensions.contains(ext) { return .text }
        if previewableBinaryExtensions.contains(ext), entry.size <= Int64(remoteBinaryCap) {
            return .fetchBinary
        }
        return .infoOnly
    }
}
