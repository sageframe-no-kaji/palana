// SSHConfigParser+User — the login lookup behind the sudo-explainer prefill
// (ho-17). Extracted from SSHConfigParser.swift so that file stays within the
// type-body budget; it shares `tokenize` and `maxIncludeDepth`.

import Foundation

extension SSHConfigParser {
    /// The `User` an alias's own `Host` block declares, or `nil` when none.
    ///
    /// A best-effort prefill, not a full ssh resolver: it reads the `User` on
    /// the block that names `alias` exactly, following `Include`s. A user that
    /// only comes from a `Host *` wildcard or a global default is deliberately
    /// *not* resolved — the caller falls back to a clear placeholder rather than
    /// bake a guessed login into a sudoers line. First value wins, as
    /// ssh_config(5) resolves.
    public static func user(
        for alias: String,
        in text: String,
        including resolve: (String) -> [String] = { _ in [] }
    ) -> String? {
        var result: String?
        collectUser(text, alias: alias, depth: 0, resolve: resolve, into: &result)
        return result
    }

    private static func collectUser(
        _ text: String,
        alias: String,
        depth: Int,
        resolve: (String) -> [String],
        into result: inout String?
    ) {
        guard depth <= maxIncludeDepth, result == nil else { return }
        var inMatchingBlock = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let tokens = tokenize(line)
            guard let keyword = tokens.first?.lowercased() else { continue }
            let arguments = Array(tokens.dropFirst())
            switch keyword {
            case "host":
                inMatchingBlock = arguments.contains(alias)
            case "user":
                if inMatchingBlock, result == nil, let value = arguments.first {
                    result = value
                    return
                }
            case "include":
                for path in arguments {
                    for included in resolve(path) where result == nil {
                        collectUser(
                            included,
                            alias: alias,
                            depth: depth + 1,
                            resolve: resolve,
                            into: &result)
                    }
                }
            default:
                continue
            }
        }
    }
}
