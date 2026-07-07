// The Workbench vocabulary — verbs, their requirements, their availability,
// and the protocol any tool conforms to. The Workbench holds the Conduit
// and the Field; a tool holds neither. The tool composes; the Workbench runs.

import Foundation

/// The routing axis of a verb.
///
/// A `read` verb's composed command runs through the Conduit and returns raw
/// output. A `mutation` verb composes a ``PlanRequest`` the Plan Engine
/// classifies and the operator arms — the mutation path is named here and
/// honored by the routing, not built in v1.
public enum VerbKind: Sendable, Equatable {
    /// Run the composed command through the Conduit; return raw output.
    case read
    /// Compose a ``PlanRequest`` for the Plan Engine to classify. Not
    /// built in v1 — the ZFS tool's ho fills this in.
    case mutation
}

/// What a verb needs from the Field's cached facts to be enabled.
public enum CapabilityRequirement: Sendable, Equatable {
    /// Enabled unless the host is *known* unreachable. Unprobed hosts stay
    /// available — the run is its own reachability test.
    case reachable
    /// Enabled only when a `zfsTopology` fact is present for the host —
    /// probed and zfs-bearing. Absent facts mean "not yet probed", not "no zfs".
    case zfs

    /// Whether the requirement is met, given cached facts for the host.
    ///
    /// Never touches the wire. Nil facts mean the host has not been probed;
    /// the requirement interprets that conservatively per its own rule.
    public func evaluate(host: String, facts: HostFacts?) -> VerbAvailability {
        switch self {
        case .reachable:
            // Only explicitly unreachable blocks the verb. Unprobed stays
            // available — df's own output is the reachability test.
            if case .unreachable = facts?.reachability?.value {
                return .unmet("\(host) is unreachable")
            }
            return .available

        case .zfs:
            guard let facts else {
                return .unmet("\(host) not yet probed—probe from the field or map")
            }
            guard facts.zfsTopology != nil else {
                return .unmet("\(host) has no zfs")
            }
            return .available
        }
    }
}

/// Whether a verb can be invoked.
///
/// The `String` in `unmet` is a plain sentence — the disabled button's tooltip.
public enum VerbAvailability: Sendable, Equatable {
    /// The verb can be invoked.
    case available
    /// The verb cannot be invoked; the reason is a human-readable sentence.
    case unmet(String)
}

/// One action a tool exposes.
public struct WorkbenchVerb: Sendable {
    /// Stable identifier — unique within a tool.
    public let id: String
    /// Display label.
    public let label: String
    /// Keyboard hint — one letter by convention; the app owns final binding.
    public let keyHint: String
    /// What the host must offer for this verb to be available.
    public let requirement: CapabilityRequirement
    /// Whether this verb routes through the Conduit or the Plan Engine.
    public let kind: VerbKind

    /// Assembles a verb.
    public init(
        id: String,
        label: String,
        keyHint: String,
        requirement: CapabilityRequirement,
        kind: VerbKind
    ) {
        self.id = id
        self.label = label
        self.keyHint = keyHint
        self.requirement = requirement
        self.kind = kind
    }
}

/// A tool registered with the ``Workbench``.
///
/// A tool declares verbs and composes what each verb produces — a command
/// string for read verbs, a ``PlanRequest`` for mutation verbs. The
/// Workbench owns gating and execution; the tool owns composition only.
public protocol WorkbenchTool: Sendable {
    /// Stable identifier for the tool.
    var id: String { get }
    /// Display label.
    var label: String { get }
    /// The verbs this tool exposes.
    var verbs: [WorkbenchVerb] { get }

    /// The command a read verb composes for a host.
    ///
    /// The tool composes; the Workbench runs. This is never called for a
    /// `.mutation` verb — that path routes through ``planRequest(for:on:)``.
    func command(for verb: WorkbenchVerb, on host: String) -> String
}

extension WorkbenchTool {
    /// A mutation verb's plan request — `nil` by default.
    ///
    /// Mutation tools override this and return a real ``PlanRequest`` for
    /// the Plan Engine to classify. The ``Workbench`` routes a `.mutation`
    /// verb through the Plan Engine, not through the Conduit — the ZFS
    /// tool's future ho fills this path in. Do not call this for read verbs.
    public func planRequest(for verb: WorkbenchVerb, on host: String) -> PlanRequest? {
        nil
    }
}
