// A host block is a value — composed here, written through SettingsModel's
// backup-and-replace path. Validation is pure and total: every broken rule
// returns a typed error so the surface can name what's wrong, not just that
// something is.

/// Why a ``HostBlock`` refuses to be considered valid.
///
/// One value per broken rule — the surface can enumerate all failures at once
/// and name each field individually.
public enum HostBlockError: Error, Equatable, Sendable {
    /// The alias is empty.
    case aliasEmpty
    /// The alias contains whitespace — ssh `Host` only accepts single tokens.
    case aliasContainsWhitespace
    /// The alias is a wildcard or negation pattern (`*`, `?`, `!`), which is
    /// matching machinery in ssh_config, not a host name.
    case aliasIsWildcard
    /// The alias falls outside the grammar pālana admits —
    /// `[A-Za-z0-9][A-Za-z0-9._-]*` — so it could not be handed to a shell
    /// or to ssh unambiguously (see ``SSHConfigParser/aliasGrammar``).
    case aliasOutsideGrammar
    /// The alias is `local` (any case), the name reserved for this Mac.
    case aliasReserved
    /// The hostname is empty — ssh needs somewhere to connect.
    case hostNameEmpty
    /// The port lies outside the valid TCP range of 1–65535.
    case portOutOfRange(Int)
    /// A field holds a line break or another control character, which
    /// would end the line it is written on and start another directive.
    /// The associated value names the field (`HostName`, `User`,
    /// `IdentityFile`).
    case fieldContainsControlCharacter(String)
    /// The hostname contains whitespace — no host or address does.
    case hostNameContainsWhitespace
}

/// An ssh `Host` block as a value, ready to compose and write.
///
/// Carry only the fields that belong in a block pālana creates. Validation
/// is separate from construction — build the value from whatever the form
/// supplies, call ``validate()`` to learn what's wrong before writing.
public struct HostBlock: Codable, Sendable, Equatable {
    /// The alias the operator types at the ssh prompt — the `Host` keyword's
    /// first argument.
    public var alias: String
    /// The real hostname or IP the alias resolves to (`HostName` keyword).
    public var hostName: String
    /// Optional login user (`User` keyword).
    public var user: String?
    /// Optional port override (`Port` keyword), 1–65535.
    public var port: Int?
    /// Optional path to the identity file (`IdentityFile` keyword).
    public var identityFile: String?

    /// Assembles a host block value.
    ///
    /// Construction never fails — call ``validate()`` to learn which rules the
    /// values break before composing or writing.
    public init(
        alias: String,
        hostName: String,
        user: String? = nil,
        port: Int? = nil,
        identityFile: String? = nil
    ) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.port = port
        self.identityFile = identityFile
    }

    /// Returns every rule this block breaks, one error per failure.
    ///
    /// An empty array means the block is valid and ready to write.
    public func validate() -> [HostBlockError] {
        var errors: [HostBlockError] = []

        // Alias rules — checked in priority order so the surface sees the
        // most specific reason first when multiple rules apply.
        if alias.isEmpty {
            errors.append(.aliasEmpty)
        } else if alias.contains(where: { $0.isWhitespace }) {
            errors.append(.aliasContainsWhitespace)
        } else if SSHConfigParser.isPattern(alias) {
            errors.append(.aliasIsWildcard)
        } else if let exclusion = SSHConfigParser.exclusion(of: alias) {
            switch exclusion {
            case .outsideGrammar: errors.append(.aliasOutsideGrammar)
            case .reserved: errors.append(.aliasReserved)
            }
        }

        // HostName is always required.
        if hostName.isEmpty {
            errors.append(.hostNameEmpty)
        } else if Self.hasControlCharacter(hostName) {
            errors.append(.fieldContainsControlCharacter("HostName"))
        } else if hostName.contains(where: { $0.isWhitespace }) {
            errors.append(.hostNameContainsWhitespace)
        }

        // A line break in any written value would end its line early and
        // start a directive nobody wrote (review 2026-11-18, F08).
        if let userValue = user, Self.hasControlCharacter(userValue) {
            errors.append(.fieldContainsControlCharacter("User"))
        }
        if let id = identityFile, Self.hasControlCharacter(id) {
            errors.append(.fieldContainsControlCharacter("IdentityFile"))
        }

        // Port, when present, must be a legal TCP port.
        if let portValue = port, !(1...65535).contains(portValue) {
            errors.append(.portOutOfRange(portValue))
        }

        return errors
    }

    /// Renders the canonical `Host` block text with four-space indent.
    ///
    /// Only lines that carry a value are emitted — `Host` and `HostName` are
    /// always present; `User`, `Port`, and `IdentityFile` appear only when
    /// non-nil. No trailing blank line inside the block.
    ///
    /// Values are written as ssh_config arguments: one that ssh would split
    /// or reinterpret — whitespace, a quote, a backslash, a `#` — is
    /// double-quoted with `\"` and `\\` escaped, which ssh reads back as
    /// the one argument it was. An `IdentityFile` path's `%` is doubled,
    /// because ssh expands `%` tokens in that keyword. A path with spaces
    /// written bare made ssh reject the whole file, every host in it
    /// (review 2026-11-18, F08). Compose only a block that validates.
    public func compose() -> String {
        var lines: [String] = []
        lines.append("Host \(alias)")
        lines.append("    HostName \(Self.argument(hostName))")
        if let userValue = user, !userValue.isEmpty {
            lines.append("    User \(Self.argument(userValue))")
        }
        if let portValue = port {
            lines.append("    Port \(portValue)")
        }
        if let id = identityFile, !id.isEmpty {
            lines.append("    IdentityFile \(Self.argument(id.replacingOccurrences(of: "%", with: "%%")))")
        }
        return lines.joined(separator: "\n")
    }

    /// One value as a single ssh_config argument.
    ///
    /// Bare when ssh would read it back unchanged; otherwise double-quoted,
    /// with the two characters that end or escape a double-quoted argument
    /// (`"` and `\`) escaped by a backslash.
    static func argument(_ value: String) -> String {
        let special: Set<Character> = [" ", "\t", "\"", "'", "\\", "#", "="]
        guard value.contains(where: { special.contains($0) }) else { return value }
        var escaped = ""
        for character in value {
            if character == "\"" || character == "\\" { escaped.append("\\") }
            escaped.append(character)
        }
        return "\"\(escaped)\""
    }

    /// True when `value` holds a character that would break the line it is
    /// written on — a line break, a NUL, or any other control character.
    static func hasControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}
