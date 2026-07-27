// What the operator typed into an address field, classified before any
// pointing happens. Pure: a string in, one of three shapes out. The
// resolution — which host a bare path belongs to — is the Surface's call;
// this only names what was typed.

import Foundation

/// A typed address, classified into the three shapes a pane can point at.
///
/// The classification is unambiguous because a host alias cannot begin with
/// `/`: anything `/`-leading is a path, anything with a colon is `host:path`,
/// and everything else is a host alias.
public enum TypedAddress: Equatable, Sendable {
    /// `host:path` — a colon was present. An empty path resolves to `~`.
    case hostPath(host: String, path: String)

    /// A bare absolute path — `/`-leading, no colon, no host named.
    ///
    /// The Surface decides which machine it belongs to; the address itself
    /// does not say.
    case barePath(String)

    /// A bare host alias — everything colon-free that is not `/`-leading.
    ///
    /// `~`-leading input lands here too: `~` names the pane host's home and is
    /// not part of the bare-path rule.
    case host(String)

    /// Classifies trimmed input, or nil when there is nothing to point at.
    ///
    /// Nil for empty input and for a colon with no host before it (`:/tank`) —
    /// both of which the pane treats as a no-op rather than an error.
    ///
    /// - Parameter input: The raw typed or pasted text.
    /// - Returns: The classified address, or nil when the input names nothing.
    public static func classify(_ input: String) -> Self? {
        let typed = input.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return nil }
        if let colon = typed.firstIndex(of: ":") {
            let host = String(typed[..<colon])
            guard !host.isEmpty else { return nil }
            let path = String(typed[typed.index(after: colon)...])
            return .hostPath(host: host, path: path.isEmpty ? "~" : path)
        }
        if typed.hasPrefix("/") { return .barePath(typed) }
        return .host(typed)
    }
}
