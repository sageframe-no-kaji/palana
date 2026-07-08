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
    /// The hostname is empty — ssh needs somewhere to connect.
    case hostNameEmpty
    /// The port lies outside the valid TCP range of 1–65535.
    case portOutOfRange(Int)
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
        } else if !SSHConfigParser.isAlias(alias) {
            errors.append(.aliasIsWildcard)
        }

        // HostName is always required.
        if hostName.isEmpty {
            errors.append(.hostNameEmpty)
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
    public func compose() -> String {
        var lines: [String] = []
        lines.append("Host \(alias)")
        lines.append("    HostName \(hostName)")
        if let userValue = user, !userValue.isEmpty {
            lines.append("    User \(userValue)")
        }
        if let portValue = port {
            lines.append("    Port \(portValue)")
        }
        if let id = identityFile, !id.isEmpty {
            lines.append("    IdentityFile \(id)")
        }
        return lines.joined(separator: "\n")
    }
}
