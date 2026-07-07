// The Workbench — gates verbs against the Field's cached facts and runs
// read verbs through the Conduit raw. Mutation verbs are named in the
// types and routed to a nil seam; the Plan Engine path is a future ho's
// work. No Surface code lives here. No parsing of read output.

import Foundation

/// A programmer error: a mutation verb reached the read path.
///
/// Route `.mutation` verbs through the Plan Engine. The Workbench's
/// `run` method is the read path only.
public enum WorkbenchError: Error, Sendable, Equatable {
    /// `run(_:of:on:)` was called with a `.mutation` verb. The mutation
    /// path routes through the Plan Engine — this is not that path.
    case notARead
}

/// The tool coordinator.
///
/// Holds a ``Conduit`` and a ``Field`` through their public surface only.
/// No PalanaCore internal is accessed here. The Workbench does not discover,
/// parse, or interpret — it gates and routes.
public struct Workbench: Sendable {
    private let conduit: any Conduit
    private let field: Field

    /// Creates a Workbench over an existing Conduit and Field.
    ///
    /// Both are injected — the app constructs one pair at startup; tests
    /// inject a ``RecordedConduit`` and a seeded ``Field``.
    public init(conduit: any Conduit, field: Field) {
        self.conduit = conduit
        self.field = field
    }

    /// Whether `verb` can be invoked on `host`, from cached facts.
    ///
    /// Never touches the wire — reads the Field's memory only. An unprobed
    /// host is not discovered here; `.reachable` verbs stay available and
    /// `.zfs` verbs report "not yet probed."
    public func availability(of verb: WorkbenchVerb, on host: String) async -> VerbAvailability {
        let facts = await field.facts(for: host)
        return verb.requirement.evaluate(host: host, facts: facts)
    }

    /// Runs a read verb's composed command on `host`.
    ///
    /// Returns the ``RunningCommand`` immediately — the caller drains
    /// stdout and stderr or calls ``RunningCommand/collect()``. No
    /// parsing, no exit-status interpretation: raw output is the contract.
    ///
    /// - Throws: ``WorkbenchError/notARead`` when the verb's kind is
    ///   `.mutation`. Mutation verbs route through the Plan Engine.
    /// - Throws: Any ``ConduitError`` when the door itself fails — a
    ///   nonzero exit status from the remote command is data, not an error.
    public func run(
        _ verb: WorkbenchVerb,
        of tool: any WorkbenchTool,
        on host: String
    ) async throws -> RunningCommand {
        guard case .read = verb.kind else {
            throw WorkbenchError.notARead
        }
        let command = tool.command(for: verb, on: host)
        return try await conduit.run(on: host, command)
    }
}
