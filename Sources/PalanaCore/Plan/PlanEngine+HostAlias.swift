// Host aliases inside shell text — extracted from PlanEngine.swift to
// keep that file within the length budget. Same pure contract: an alias
// in the grammar is bare, as it has always been; one outside it is data
// the parser never admitted, and the composed command treats it as
// data. The structured route refuses it at launch; the displayed
// command is never less safe than that refusal.

import Foundation

extension PlanEngine {
    /// The alias as an ssh destination inside a pasteable command.
    ///
    /// An alias inside ``SSHConfigParser/aliasGrammar`` is bare — every
    /// byte is shell-inert and none reads as an option. Anything else
    /// — restored or legacy data that bypassed the parser — is
    /// single-quoted so the shell keeps it one word, and led by `--` so
    /// ssh reads it as a destination and never as an option.
    static func sshDestination(_ alias: String) -> String {
        isPlainAlias(alias) ? alias : "-- \(ShellQuote.quote(alias))"
    }

    /// `-- ` ahead of rsync's paths when the remote alias could read
    /// as an option — `-x:/path` is a flag to rsync's parser, however
    /// the shell quoted it — and nothing for an alias in the grammar.
    static func rsyncPathGuard(for alias: String) -> String {
        isPlainAlias(alias) ? "" : "-- "
    }

    /// The pasteable form of a proxied pipeline, derived from the same
    /// parts the Transports spawn — the two cannot drift.
    static func pipelineCommand(_ pipeline: Pipeline) -> String {
        "ssh \(sshDestination(pipeline.fromHost)) \(ShellQuote.quote(pipeline.fromCommand)) | "
            + "ssh \(sshDestination(pipeline.toHost)) \(ShellQuote.quote(pipeline.toCommand))"
    }

    /// The door's own rule: non-empty and inside the grammar.
    private static func isPlainAlias(_ alias: String) -> Bool {
        !alias.isEmpty && SSHConfigParser.isAlias(alias)
    }
}
