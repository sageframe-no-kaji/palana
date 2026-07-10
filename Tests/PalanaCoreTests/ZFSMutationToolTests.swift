// ZFSMutationToolTests — the ZFSMutationTool battery. Covers verb declarations,
// gather specs, PlanRequest composition per verb, nil-guard paths (empty target,
// empty/whitespace text, unknown verb), and a smoke round-trip through PlanEngine.

import Foundation
import Testing

@testable import PalanaCore

// MARK: - Shared fixtures

private let tool = ZFSMutationTool()
private let host = "jodo"
private let target = "tank/data"

private func input(
    target: String = "tank/data",
    text: String? = nil,
    recursive: Bool = false
) -> MutationInput {
    MutationInput(target: target, text: text, recursive: recursive)
}

private func matchedVerb(_ id: String) throws -> WorkbenchVerb {
    try #require(tool.verbs.first { $0.id == id })
}

/// A test case for the shared-invariant suite — verb id plus optional compose parameters.
private struct VerbCase {
    var verbId: String
    var text: String?
    var recursive: Bool

    init(_ verbId: String, text: String? = nil, recursive: Bool = false) {
        self.verbId = verbId
        self.text = text
        self.recursive = recursive
    }
}

// MARK: - Tool identity and verb declarations

@Suite("ZFSMutationTool — identity and verbs")
struct ZFSMutationToolIdentityTests {
    @Test("tool id and label")
    func identity() {
        #expect(tool.id == "zfs")
        #expect(tool.label == "zfs")
    }

    @Test("exactly eight verbs")
    func verbCount() {
        #expect(tool.verbs.count == 8)
    }

    @Test("all verbs are mutation kind")
    func allMutationKind() {
        for verb in tool.verbs {
            #expect(verb.kind == .mutation)
        }
    }

    @Test("all verbs require zfs capability")
    func allRequireZfs() {
        for verb in tool.verbs {
            #expect(verb.requirement == .zfs)
        }
    }

    @Test("verb ids match the declared table")
    func verbIds() {
        let expectedIds = [
            "zfs-create",
            "zfs-destroy",
            "zfs-rename",
            "zfs-snapshot",
            "zfs-destroy-snapshot",
            "zfs-rollback",
            "zfs-set-mountpoint",
            "zfs-clear-mountpoint",
        ]
        #expect(tool.verbs.map(\.id) == expectedIds)
    }
}

// MARK: - GatherSpec per verb

@Suite("ZFSMutationTool — gather specs")
struct ZFSMutationToolGatherSpecTests {
    @Test("zfs-create: needsText true, offersRecursive false")
    func gatherCreate() throws {
        let spec = try #require(try matchedVerb("zfs-create").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == false)
    }

    @Test("zfs-destroy: needsText false, offersRecursive true")
    func gatherDestroy() throws {
        let spec = try #require(try matchedVerb("zfs-destroy").gather)
        #expect(spec.needsText == false)
        #expect(spec.offersRecursive == true)
    }

    @Test("zfs-rename: needsText true, offersRecursive false")
    func gatherRename() throws {
        let spec = try #require(try matchedVerb("zfs-rename").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == false)
    }

    @Test("zfs-snapshot: needsText true, offersRecursive true")
    func gatherSnapshot() throws {
        let spec = try #require(try matchedVerb("zfs-snapshot").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == true)
    }

    @Test("zfs-destroy-snapshot: needsText true, offersRecursive false")
    func gatherDestroySnapshot() throws {
        let spec = try #require(try matchedVerb("zfs-destroy-snapshot").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == false)
    }

    @Test("zfs-rollback: needsText true, offersRecursive false")
    func gatherRollback() throws {
        let spec = try #require(try matchedVerb("zfs-rollback").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == false)
    }

    @Test("zfs-set-mountpoint: needsText true, offersRecursive false")
    func gatherSetMountpoint() throws {
        let spec = try #require(try matchedVerb("zfs-set-mountpoint").gather)
        #expect(spec.needsText == true)
        #expect(spec.offersRecursive == false)
    }

    @Test("zfs-clear-mountpoint: needsText false, offersRecursive false")
    func gatherClearMountpoint() throws {
        let spec = try #require(try matchedVerb("zfs-clear-mountpoint").gather)
        #expect(spec.needsText == false)
        #expect(spec.offersRecursive == false)
    }
}

// MARK: - planRequest composition per verb

@Suite("ZFSMutationTool — planRequest composition")
struct ZFSMutationToolCompositionTests {
    // MARK: Helpers

    private func compose(
        _ verbId: String,
        text: String? = nil,
        recursive: Bool = false
    ) throws -> PlanRequest {
        let foundVerb = try matchedVerb(verbId)
        return try #require(
            tool.planRequest(
                for: foundVerb,
                on: host,
                input: input(target: target, text: text, recursive: recursive)
            )
        )
    }

    // MARK: Shared request invariants

    private let allVerbCases: [VerbCase] = [
        VerbCase("zfs-create", text: "media"),
        VerbCase("zfs-destroy"),
        VerbCase("zfs-rename", text: "tank/archive"),
        VerbCase("zfs-snapshot", text: "snap1"),
        VerbCase("zfs-destroy-snapshot", text: "snap1"),
        VerbCase("zfs-rollback", text: "snap1"),
        VerbCase("zfs-set-mountpoint", text: "/mnt/data"),
        VerbCase("zfs-clear-mountpoint"),
    ]

    @Test("every verb: operation is .zfs, entries empty, destination nil")
    func sharedInvariants() throws {
        for verbCase in allVerbCases {
            let request = try compose(verbCase.verbId, text: verbCase.text, recursive: verbCase.recursive)
            #expect(request.operation == .zfs)
            #expect(request.entries.isEmpty)
            #expect(request.destination == nil)
        }
    }

    @Test("every verb: locus host and directory match the input target")
    func sharedLocus() throws {
        for verbCase in allVerbCases {
            let request = try compose(verbCase.verbId, text: verbCase.text, recursive: verbCase.recursive)
            #expect(request.source.host == host)
            #expect(request.source.directory == target)
        }
    }

    // MARK: zfs-create

    @Test("create: composes child name from target + text")
    func createChildName() throws {
        let request = try compose("zfs-create", text: "media")
        #expect(request.zfs == .createDataset(name: "tank/data/media", mountpoint: nil))
    }

    @Test("create: mountpoint is nil — set-mountpoint verb handles that")
    func createNoMountpoint() throws {
        let request = try compose("zfs-create", text: "archive")
        if case .createDataset(_, let mp) = request.zfs {
            #expect(mp == nil)
        } else {
            Issue.record("expected createDataset mutation")
        }
    }

    // MARK: zfs-destroy

    @Test("destroy: non-recursive flag passes through")
    func destroyNonRecursive() throws {
        let request = try compose("zfs-destroy", recursive: false)
        #expect(request.zfs == .destroyDataset(name: target, recursive: false))
    }

    @Test("destroy: recursive flag passes through")
    func destroyRecursive() throws {
        let request = try compose("zfs-destroy", recursive: true)
        #expect(request.zfs == .destroyDataset(name: target, recursive: true))
    }

    // MARK: zfs-rename

    @Test("rename: gathered text becomes the full new name")
    func renameVerbatim() throws {
        let newName = "tank/archive"
        let request = try compose("zfs-rename", text: newName)
        #expect(request.zfs == .renameDataset(from: target, to: newName))
    }

    // MARK: zfs-snapshot

    @Test("snapshot: non-recursive flag passes through")
    func snapshotNonRecursive() throws {
        let request = try compose("zfs-snapshot", text: "snap1", recursive: false)
        #expect(request.zfs == .snapshot(dataset: target, name: "snap1", recursive: false))
    }

    @Test("snapshot: recursive flag passes through")
    func snapshotRecursive() throws {
        let request = try compose("zfs-snapshot", text: "snap1", recursive: true)
        #expect(request.zfs == .snapshot(dataset: target, name: "snap1", recursive: true))
    }

    // MARK: zfs-destroy-snapshot

    @Test("destroy-snapshot: dataset and snapshot name compose correctly")
    func destroySnapshot() throws {
        let request = try compose("zfs-destroy-snapshot", text: "snap1")
        #expect(request.zfs == .destroySnapshot(dataset: target, name: "snap1"))
    }

    // MARK: zfs-rollback

    @Test("rollback: dataset and snapshot name compose correctly")
    func rollback() throws {
        let request = try compose("zfs-rollback", text: "snap1")
        #expect(request.zfs == .rollback(dataset: target, name: "snap1"))
    }

    // MARK: zfs-set-mountpoint

    @Test("set-mountpoint: path passes through verbatim")
    func setMountpoint() throws {
        let request = try compose("zfs-set-mountpoint", text: "/mnt/data")
        #expect(request.zfs == .setMountpoint(dataset: target, path: "/mnt/data"))
    }

    // MARK: zfs-clear-mountpoint

    @Test("clear-mountpoint: no text needed, composes correctly")
    func clearMountpoint() throws {
        let request = try compose("zfs-clear-mountpoint")
        #expect(request.zfs == .clearMountpoint(dataset: target))
    }
}

// MARK: - Nil-guard paths

@Suite("ZFSMutationTool — nil guards")
struct ZFSMutationToolNilGuardTests {
    @Test("empty target returns nil for all verbs")
    func emptyTargetReturnsNil() throws {
        let emptyInput = MutationInput(target: "", text: "something")
        for foundVerb in tool.verbs {
            #expect(tool.planRequest(for: foundVerb, on: host, input: emptyInput) == nil)
        }
    }

    private let needsTextIds = [
        "zfs-create",
        "zfs-rename",
        "zfs-snapshot",
        "zfs-destroy-snapshot",
        "zfs-rollback",
        "zfs-set-mountpoint",
    ]

    @Test("nil text returns nil for every needsText verb")
    func nilTextForNeedsTextVerbs() throws {
        let nilInput = MutationInput(target: target, text: nil)
        for verbId in needsTextIds {
            let foundVerb = try #require(tool.verbs.first { $0.id == verbId })
            #expect(tool.planRequest(for: foundVerb, on: host, input: nilInput) == nil)
        }
    }

    @Test("empty string text returns nil for every needsText verb")
    func emptyTextForNeedsTextVerbs() throws {
        let emptyInput = MutationInput(target: target, text: "")
        for verbId in needsTextIds {
            let foundVerb = try #require(tool.verbs.first { $0.id == verbId })
            #expect(tool.planRequest(for: foundVerb, on: host, input: emptyInput) == nil)
        }
    }

    @Test("whitespace-only text returns nil for every needsText verb")
    func whitespaceTextForNeedsTextVerbs() throws {
        let whitespaceInput = MutationInput(target: target, text: "   ")
        for verbId in needsTextIds {
            let foundVerb = try #require(tool.verbs.first { $0.id == verbId })
            #expect(tool.planRequest(for: foundVerb, on: host, input: whitespaceInput) == nil)
        }
    }

    @Test("text is trimmed before composing")
    func textTrimsWhitespace() throws {
        let snapshotVerb = try #require(tool.verbs.first { $0.id == "zfs-snapshot" })
        let paddedInput = MutationInput(target: target, text: "  snap1  ")
        let request = try #require(
            tool.planRequest(for: snapshotVerb, on: host, input: paddedInput)
        )
        #expect(request.zfs == .snapshot(dataset: target, name: "snap1", recursive: false))
    }

    @Test("unknown verb id returns nil")
    func unknownVerbReturnsNil() {
        let unknownVerb = WorkbenchVerb(
            id: "zfs-clone",
            label: "clone",
            keyHint: "l",
            requirement: .zfs,
            kind: .mutation
        )
        let result = tool.planRequest(
            for: unknownVerb,
            on: host,
            input: MutationInput(target: target, text: "snap1")
        )
        #expect(result == nil)
    }

    @Test("read-shaped verb id returns nil")
    func readVerbReturnsNil() {
        let readVerb = WorkbenchVerb(
            id: "zfs-list",
            label: "zfs list",
            keyHint: "z",
            requirement: .zfs,
            kind: .read
        )
        let result = tool.planRequest(
            for: readVerb,
            on: host,
            input: MutationInput(target: target)
        )
        #expect(result == nil)
    }
}

// MARK: - Reshaped seam: default-nil check

@Suite("WorkbenchTool seam — planRequest(for:on:input:) default nil")
struct WorkbenchToolSeamTests {
    @Test("a tool that does not override planRequest(for:on:input:) returns nil")
    func defaultNilForNonMutationTool() {
        let readsTool = SystemReadsTool()
        let anyVerb = readsTool.verbs[0]
        let result = readsTool.planRequest(
            for: anyVerb,
            on: host,
            input: MutationInput(target: target)
        )
        #expect(result == nil)
    }
}

// MARK: - Round-trip smoke: tool-built request through PlanEngine

@Suite("ZFSMutationTool — PlanEngine round-trip smoke")
struct ZFSMutationToolRoundTripTests {
    private func planVia(verbId: String, text: String? = nil) throws -> Plan {
        let foundVerb = try #require(tool.verbs.first { $0.id == verbId })
        let request = try #require(
            tool.planRequest(
                for: foundVerb,
                on: host,
                input: MutationInput(target: target, text: text)
            )
        )
        return try PlanEngine.plan(request, facts: PlanFacts())
    }

    @Test("create: tool-built request yields steps from PlanEngine")
    func createRoundTrip() throws {
        let plan = try planVia(verbId: "zfs-create", text: "media")
        #expect(!plan.steps.isEmpty)
        #expect(plan.classification == .zfsMutation)
    }

    @Test("destroy: tool-built request yields steps from PlanEngine")
    func destroyRoundTrip() throws {
        let plan = try planVia(verbId: "zfs-destroy")
        #expect(!plan.steps.isEmpty)
        #expect(plan.classification == .zfsMutation)
    }

    @Test("snapshot: tool-built request yields steps from PlanEngine")
    func snapshotRoundTrip() throws {
        let plan = try planVia(verbId: "zfs-snapshot", text: "snap1")
        #expect(!plan.steps.isEmpty)
        #expect(plan.classification == .zfsMutation)
    }

    @Test("set-mountpoint: tool-built request yields steps from PlanEngine")
    func setMountpointRoundTrip() throws {
        let plan = try planVia(verbId: "zfs-set-mountpoint", text: "/mnt/data")
        #expect(!plan.steps.isEmpty)
        #expect(plan.classification == .zfsMutation)
    }

    @Test("clear-mountpoint: tool-built request yields steps from PlanEngine")
    func clearMountpointRoundTrip() throws {
        let plan = try planVia(verbId: "zfs-clear-mountpoint")
        #expect(!plan.steps.isEmpty)
        #expect(plan.classification == .zfsMutation)
    }
}
