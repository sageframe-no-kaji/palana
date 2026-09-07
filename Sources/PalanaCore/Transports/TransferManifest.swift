// The transfer manifest — the gate's evidence for file moves. A count
// was never identity: two trees with the same number of objects can
// differ in every byte, and a count taken by piping `find` into `wc`
// answers 0 with status 0 when find itself failed (2026-09-06 review).
// The manifest names every object under the selection with its kind,
// size, symlink target, and SHA-256, on both ends, and the delete runs
// only when every source entry is carried identically at the
// destination — entries already standing there before a merge do not
// count against the source (2026-09-07). One POSIX-sh program per end;
// no probe, no dependency — a host without a SHA-256 tool says so and
// the gate stays closed.

import Foundation

/// Every object under a selection, named with its kind and content.
///
/// Entries are sorted by name bytes, so two manifests of the same tree
/// compare equal whatever order `find` walked them in.
public struct TransferManifest: Sendable, Equatable {
    /// What an object is.
    public enum Kind: Character, Sendable, Equatable {
        /// A regular file — carries a size and a digest.
        case file = "f"
        /// A directory — its contents are their own entries.
        case directory = "d"
        /// A symbolic link — carries its target, never followed.
        case symlink = "l"
        /// Anything else — fifo, socket, device — named and typed only.
        case other = "o"
    }

    /// One object under the selection.
    public struct Entry: Sendable, Equatable {
        /// The path relative to the transfer directory, byte-exact.
        public var name: Data
        /// The object's kind.
        public var kind: Kind
        /// Byte count, regular files only.
        public var size: Int64?
        /// Lowercase SHA-256 hex, regular files only.
        public var digest: String?
        /// The link's target, byte-exact, symlinks only.
        public var linkTarget: Data?

        /// Assembles an entry.
        public init(
            name: Data,
            kind: Kind,
            size: Int64? = nil,
            digest: String? = nil,
            linkTarget: Data? = nil
        ) {
            self.name = name
            self.kind = kind
            self.size = size
            self.digest = digest
            self.linkTarget = linkTarget
        }

        /// The name for display — lossy UTF-8, never for composition.
        public var displayName: String {
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: name, as: UTF8.self)
        }
    }

    /// The entries, sorted by name bytes.
    public var entries: [Entry]

    /// Wraps entries, sorting them by name bytes.
    public init(entries: [Entry]) {
        self.entries = entries.sorted { $0.name.lexicographicallyPrecedes($1.name) }
    }

    // MARK: - The command

    /// The digest tools, in preference order, each answering SHA-256 on
    /// standard input.
    ///
    /// GNU coreutils and BusyBox carry `sha256sum`, macOS and the BSDs
    /// carry `shasum`, and `openssl` is the last resort every userland
    /// with TLS has. Nothing weaker is ever substituted — a host with
    /// none of these fails the manifest.
    static let digestTools = [
        ("sha256sum", "sha256sum"),
        ("shasum", "shasum -a 256"),
        ("openssl", "openssl dgst -sha256"),
    ]

    /// The per-batch program `find -exec` runs, one record per object.
    ///
    /// Four NUL-terminated fields per record — kind, size, digest or
    /// link target, relative name — so names may hold any byte,
    /// newline included. Sizes come from `ls -ldn` (a stat, not a
    /// read); digests from the resolved tool reading the file on
    /// standard input, so an unreadable file fails the redirection and
    /// the record is never written. Every field is shape-checked: a
    /// masked pipeline failure yields an empty size or digest, and an
    /// empty size or digest exits 3. `${d#*= }` strips openssl's
    /// `(stdin)= ` prefix and is a no-op for the sum tools.
    static let entryProgram = [
        "for f; do r=${f#./}",
        #"if [ -L "$f" ]; then t=$(readlink "$f") || exit 3"#,
        #"printf "l\0\0%s\0%s\0" "$t" "$r""#,
        #"elif [ -d "$f" ]; then printf "d\0\0\0%s\0" "$r""#,
        #"elif [ -f "$f" ]; then s=$(ls -ldn "$f" | awk "NR==1{print \$5}")"#,
        #"case $s in ""|*[!0-9]*) echo "size unreadable: $r" >&2; exit 3;; esac"#,
        #"d=$($PALANA_DG < "$f") || { echo "unreadable: $r" >&2; exit 3; }"#,
        "d=${d#*= }; d=${d%% *}",
        #"case $d in ""|*[!0-9a-f]*) echo "digest malformed: $r" >&2; exit 3;; esac"#,
        #"[ ${#d} -eq 64 ] || { echo "digest malformed: $r" >&2; exit 3; }"#,
        #"printf "f\0%s\0%s\0%s\0" "$s" "$d" "$r""#,
        #"else printf "o\0\0\0%s\0" "$r"; fi; done"#,
    ].joined(separator: "; ")

    /// The command that writes the manifest for `names` under `directory`.
    ///
    /// Runs in the directory so every name is relative on both ends.
    /// Refuses before walking when any selected name is absent (a
    /// dangling symlink still counts as present), resolves the SHA-256
    /// tool or exits 3, then walks with `find -P` — links are recorded,
    /// never followed — batching objects through ``entryProgram``. Any
    /// nonzero status anywhere is the command's status: the caller
    /// treats it as verification unavailable, and the gate stays closed.
    public static func command(directory: String, names: [String]) -> String {
        let paths = names.map { ShellQuote.quote("./\($0)") }.joined(separator: " ")
        let resolve = digestTools.map { tool, invocation in
            "command -v \(tool) >/dev/null 2>&1; then PALANA_DG=\(ShellQuote.quote(invocation))"
        }
        let tried = digestTools.map(\.0).joined(separator: ", ")
        return [
            "cd \(ShellQuote.quote(directory)) || exit 3",
            "for n in \(paths); do [ -e \"$n\" ] || [ -L \"$n\" ] || { echo \"missing: $n\" >&2; exit 3; }; done",
            "if \(resolve.joined(separator: "; elif "))",
            "else echo 'no sha256 tool (tried \(tried))' >&2; exit 3; fi",
            "export PALANA_DG",
            "find \(paths) -exec sh -c \(ShellQuote.quote(entryProgram)) palana-manifest {} + || exit 3",
        ].joined(separator: "; ")
    }

    // MARK: - Parsing

    /// Why a manifest's bytes could not be read as one.
    public enum ParseError: Error, Equatable, Sendable {
        /// The byte count of NUL-terminated fields was not a multiple of four.
        case truncatedRecord
        /// A kind letter outside `f`, `d`, `l`, `o`.
        case unknownKind(String)
        /// A regular file whose size field is not a non-negative integer.
        case malformedSize(name: String)
        /// A regular file whose digest is not 64 lowercase hex characters.
        case malformedDigest(name: String)
        /// The same relative name appeared twice.
        case duplicateName(String)
    }

    /// Parses the command's standard output.
    ///
    /// Strict: any record that does not fit the contract fails the whole
    /// parse, because a manifest that is partly readable proves nothing.
    public static func parse(_ data: Data) throws -> Self {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        // Every field ends in NUL, so the split ends with one empty piece.
        guard fields.count % 4 == 1, fields.last?.isEmpty == true else {
            throw ParseError.truncatedRecord
        }
        var entries: [Entry] = []
        var seen = Set<Data>()
        for index in stride(from: 0, to: fields.count - 1, by: 4) {
            let entry = try parseRecord(
                kind: fields[index],
                size: fields[index + 1],
                payload: fields[index + 2],
                name: fields[index + 3])
            guard seen.insert(entry.name).inserted else {
                throw ParseError.duplicateName(entry.displayName)
            }
            entries.append(entry)
        }
        return Self(entries: entries)
    }

    private static func parseRecord(
        kind kindField: Data.SubSequence,
        size sizeField: Data.SubSequence,
        payload: Data.SubSequence,
        name nameField: Data.SubSequence
    ) throws -> Entry {
        let kindText = String(bytes: kindField, encoding: .utf8) ?? ""
        guard kindText.count == 1, let kind = Kind(rawValue: Character(kindText)) else {
            throw ParseError.unknownKind(kindText)
        }
        let name = Data(nameField)
        // Lossy on purpose — the name is for the error message only;
        // the entry keeps the exact bytes.
        // swiftlint:disable:next optional_data_string_conversion
        let displayName = String(decoding: name, as: UTF8.self)
        switch kind {
        case .file:
            guard
                let sizeText = String(bytes: sizeField, encoding: .utf8),
                let size = Int64(sizeText), size >= 0
            else {
                throw ParseError.malformedSize(name: displayName)
            }
            guard
                let digest = String(bytes: payload, encoding: .utf8),
                digest.count == 64, digest.allSatisfy(Self.isLowercaseHex)
            else {
                throw ParseError.malformedDigest(name: displayName)
            }
            return Entry(name: name, kind: .file, size: size, digest: digest)
        case .symlink:
            return Entry(name: name, kind: .symlink, linkTarget: Data(payload))
        case .directory, .other:
            return Entry(name: name, kind: kind)
        }
    }

    private static func isLowercaseHex(_ character: Character) -> Bool {
        character.isASCII && (character.isNumber || ("a"..."f").contains(character))
    }

    // MARK: - Reading

    /// The selected names the manifest does not carry as top-level entries.
    ///
    /// A manifest that omits a selected name is not evidence — `find`
    /// was masked, or the walk never reached it. Empty means every
    /// selected name is present.
    public func missingNames(from names: [String]) -> [String] {
        let present = Set(entries.map(\.name))
        return names.filter { !present.contains(Data($0.utf8)) }
    }

    /// The first of this manifest's entries that `other` does not carry.
    ///
    /// Absent there, or present with a different kind, size, digest, or
    /// link target. Nil when every entry is carried identically.
    /// The subset rule, not equality: entries `other` holds beyond
    /// these are its own business. Under a merge the destination keeps
    /// what stood there before, and that is no evidence against the
    /// source; a source entry it cannot account for is.
    public func firstUnmatched(in other: Self) -> String? {
        let theirs = Dictionary(other.entries.map { ($0.name, $0) }) { first, _ in first }
        return entries.first { theirs[$0.name] != $0 }?.displayName
    }
}
