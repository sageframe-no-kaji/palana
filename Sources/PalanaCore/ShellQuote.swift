// Shell quoting for composed commands — the Listing's cd, the Plan's
// everything. Smart: safe strings stay bare so common plans read clean,
// hostile strings get POSIX single-quote armor. Truth first, then
// readability, in that order.

import Foundation

/// POSIX shell quoting, applied only when needed.
///
/// Public so surface code composing ad-hoc reads (e.g. the snapshot-name
/// context listing) quotes with the same armor the engine uses.
public enum ShellQuote {
    private static let safeCharacters = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/:@%+=,-")

    /// Quotes a value for a POSIX shell, only when needed.
    ///
    /// Bare when every byte is shell-inert and it cannot read as a
    /// flag; otherwise wrapped in single quotes with the POSIX escape —
    /// `'` becomes `'\''`. Newlines ride inside the quotes literally,
    /// which POSIX permits.
    public static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        if !value.hasPrefix("-"), value.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
