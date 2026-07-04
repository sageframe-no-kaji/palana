// The Plan Engine's fact tables — classification cell by cell,
// transport selection under every forwarding state, validation
// refusals, and the quoting the whole composition leans on. Command
// text is PlanCompositionTests' business.

import Foundation
import Testing

@testable import PalanaCore

private func makeEntry(_ name: String, kind: FileEntry.Kind = .file, size: Int64 = 0) -> FileEntry {
    FileEntry(
        nameData: Data(name.utf8),
        kind: kind,
        size: size,
        modified: Date(timeIntervalSince1970: 0),
        permissions: "644",
        owner: "op",
        group: "op")
}

private let tank = ZFSDataset(name: "tank", mountpoint: "/tank", mounted: true)
private let tankMedia = ZFSDataset(name: "tank/media", mountpoint: "/tank/media", mounted: true)
private let cold = ZFSDataset(name: "rpool/cold", mountpoint: "/rpool/cold", mounted: true)

private let zfsHost = HostCapability(
    kernel: "Linux", flavor: .gnu, zfs: "zfs-2.2.2", rsync: "rsync  version 3.2.7")
private let plainHost = HostCapability(kernel: "Linux", flavor: .gnu, zfs: nil, rsync: nil)

private func request(
    _ operation: PlanOperation,
    from source: Locus = Locus(host: "jodo", directory: "/tank/media"),
    to destination: Locus? = Locus(host: "koan", directory: "/rpool/cold"),
    entries: [FileEntry] = [makeEntry("a.txt", size: 100)]
) -> PlanRequest {
    PlanRequest(
        operation: operation,
        source: source,
        entries: entries,
        destination: destination,
        token: "t1")
}

@Suite("PlanEngine classification")
struct PlanClassificationTests {
    private let sameHostDest = Locus(host: "jodo", directory: "/tank/other")

    @Test("same host, both datasets known and equal — a true rename")
    func provenRename() {
        let facts = PlanFacts(sourceDataset: tankMedia, destinationDataset: tankMedia)
        let classification = PlanEngine.classify(
            request(.move, to: sameHostDest), facts: facts)
        #expect(classification == .withinDatasetRename)
    }

    @Test("same host, datasets known and different — the named landmine")
    func crossDataset() {
        let facts = PlanFacts(sourceDataset: tankMedia, destinationDataset: tank)
        let classification = PlanEngine.classify(
            request(.move, to: sameHostDest), facts: facts)
        #expect(classification == .crossDatasetCopyPlusDelete)
    }

    @Test("same host, any dataset unknown — conservative, never a claimed rename")
    func unknownIsConservative() {
        for facts in [
            PlanFacts(sourceDataset: tankMedia),
            PlanFacts(destinationDataset: tankMedia),
            PlanFacts(),
        ] {
            let classification = PlanEngine.classify(
                request(.move, to: sameHostDest), facts: facts)
            #expect(classification == .crossDatasetCopyPlusDelete)
        }
    }

    @Test("different hosts — cross-host transfer, datasets irrelevant")
    func crossHost() {
        #expect(PlanEngine.classify(request(.move), facts: PlanFacts()) == .crossHostTransfer)
    }

    @Test("copy classifies by host boundary only")
    func copyShapes() {
        #expect(
            PlanEngine.classify(request(.copy, to: sameHostDest), facts: PlanFacts())
                == .withinHostCopy)
        #expect(PlanEngine.classify(request(.copy), facts: PlanFacts()) == .crossHostCopy)
    }

    @Test("delete classifies as deletion, no destination consulted")
    func deleteShape() {
        #expect(
            PlanEngine.classify(request(.delete, to: nil), facts: PlanFacts()) == .deletion)
    }
}

@Suite("PlanEngine transport")
struct PlanTransportTests {
    private func wholeDatasetFacts(forwarding: ForwardingFact) -> PlanFacts {
        PlanFacts(
            sourceDataset: tank,
            destinationDataset: cold,
            selectionWholeDataset: tankMedia,
            sourceCapability: zfsHost,
            destinationCapability: zfsHost,
            agentForwarding: forwarding)
    }

    @Test("local classifications never pick a wire transport")
    func localStaysLocal() {
        let sameHostDest = Locus(host: "jodo", directory: "/tank/other")
        let plan = try? PlanEngine.plan(request(.move, to: sameHostDest), facts: PlanFacts())
        #expect(plan?.transport == .local)
    }

    @Test("forwarding available with rsync both ends selects rsync agent-forwarded")
    func forwardedRsync() {
        let facts = PlanFacts(
            sourceCapability: zfsHost,
            destinationCapability: zfsHost,
            agentForwarding: .available)
        let transport = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: facts)
        #expect(transport == .rsyncAgentForwarded)
    }

    @Test("forwarding unavailable or unprobed selects the tar stream proxy")
    func proxyFloor() {
        for forwarding in [ForwardingFact.unavailable, .unprobed] {
            let facts = PlanFacts(
                sourceCapability: zfsHost,
                destinationCapability: zfsHost,
                agentForwarding: forwarding)
            let transport = PlanEngine.transport(
                for: .crossHostTransfer,
                request: request(.move),
                facts: facts)
            #expect(transport == .tarStreamProxied, "forwarding=\(forwarding)")
        }
    }

    @Test("rsync missing on either end falls to tar even when forwarded")
    func rsyncAbsenceFallsToTar() {
        for (source, destination) in [(zfsHost, plainHost), (plainHost, zfsHost)] {
            let facts = PlanFacts(
                sourceCapability: source,
                destinationCapability: destination,
                agentForwarding: .available)
            let transport = PlanEngine.transport(
                for: .crossHostTransfer,
                request: request(.move),
                facts: facts)
            #expect(transport == .tarStreamProxied)
        }
    }

    @Test("openrsync on the sender is not modern rsync — tar carries it")
    func openrsyncFallsToTar() {
        let openrsyncHost = HostCapability(
            kernel: "Darwin", flavor: .bsd, zfs: nil, rsync: "openrsync: protocol version 29")
        let facts = PlanFacts(
            sourceCapability: openrsyncHost,
            destinationCapability: zfsHost,
            agentForwarding: .available)
        let transport = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: facts)
        #expect(transport == .tarStreamProxied)
    }

    @Test("unknown capabilities select tar — the conservative truth")
    func unknownCapabilitiesFallToTar() {
        let facts = PlanFacts(agentForwarding: .available)
        let transport = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: facts)
        #expect(transport == .tarStreamProxied)
    }

    @Test("whole datasets both ends select zfs send/receive, auth path named")
    func zfsGate() {
        let forwarded = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: wholeDatasetFacts(forwarding: .available))
        #expect(forwarded == .zfsSendReceiveForwarded)
        let proxied = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: wholeDatasetFacts(forwarding: .unprobed))
        #expect(proxied == .zfsSendReceiveProxied)
    }

    @Test("the zfs gate closes when the destination is not exactly a mountpoint")
    func gateNeedsMountpointRoot() {
        var facts = wholeDatasetFacts(forwarding: .available)
        let deeper = Locus(host: "koan", directory: "/rpool/cold/sub")
        let transport = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move, to: deeper),
            facts: facts)
        #expect(transport == .rsyncAgentForwarded)

        // No zfs at the destination but rsync present — the zfs gate
        // closes and rsync still carries it.
        facts.destinationCapability = HostCapability(
            kernel: "Linux", flavor: .gnu, zfs: nil, rsync: "rsync  version 3.2.7")
        let noZfs = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: facts)
        #expect(noZfs == .rsyncAgentForwarded)

        facts = wholeDatasetFacts(forwarding: .available)
        facts.selectionWholeDataset = nil
        let subtree = PlanEngine.transport(
            for: .crossHostTransfer,
            request: request(.move),
            facts: facts)
        #expect(subtree == .rsyncAgentForwarded, "a subtree is a file-level operation")
    }
}

@Suite("PlanEngine refusals and the Plan value")
struct PlanValueTests {
    @Test("an empty selection refuses")
    func emptySelection() {
        #expect(throws: PlanError.emptySelection) {
            _ = try PlanEngine.plan(request(.move, entries: []), facts: PlanFacts())
        }
    }

    @Test("move and copy without a destination refuse; delete does not")
    func destinationRequired() throws {
        #expect(throws: PlanError.missingDestination) {
            _ = try PlanEngine.plan(request(.move, to: nil), facts: PlanFacts())
        }
        #expect(throws: PlanError.missingDestination) {
            _ = try PlanEngine.plan(request(.copy, to: nil), facts: PlanFacts())
        }
        let plan = try PlanEngine.plan(request(.delete, to: nil), facts: PlanFacts())
        #expect(plan.classification == .deletion)
    }

    @Test("a name that does not round-trip UTF-8 refuses, bytes carried")
    func unrepresentableName() {
        var bytes = Data("caf".utf8)
        bytes.append(0xE9)  // Latin-1 é — invalid UTF-8
        var entry = makeEntry("x")
        entry.nameData = bytes
        #expect(throws: PlanError.unrepresentableName(bytes)) {
            _ = try PlanEngine.plan(request(.move, entries: [entry]), facts: PlanFacts())
        }
    }

    @Test("total size sums the selection")
    func totalSize() throws {
        let entries = [makeEntry("a", size: 100), makeEntry("b", size: 41)]
        let plan = try PlanEngine.plan(request(.copy, entries: entries), facts: PlanFacts())
        #expect(plan.totalSize == 141)
    }

    @Test("a Plan round-trips through JSON whole — plans are values")
    func codableRoundTrip() throws {
        let plan = try PlanEngine.plan(
            request(.move), facts: PlanFacts(agentForwarding: .available))
        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(Plan.self, from: data)
        #expect(decoded == plan)
    }
}

@Suite("ShellQuote")
struct ShellQuoteTests {
    @Test("safe strings stay bare — plans read clean")
    func bareWhenSafe() {
        #expect(ShellQuote.quote("/tank/media/a.txt") == "/tank/media/a.txt")
        #expect(ShellQuote.quote("tank/media@t1") == "tank/media@t1")
        #expect(ShellQuote.quote("koan:/rpool/cold/") == "koan:/rpool/cold/")
    }

    @Test("hostile strings get armor")
    func quotedWhenHostile() {
        #expect(ShellQuote.quote("with space") == "'with space'")
        #expect(ShellQuote.quote("new\nline") == "'new\nline'")
        #expect(ShellQuote.quote("it's") == #"'it'\''s'"#)
        #expect(ShellQuote.quote("a;rm x") == "'a;rm x'")
        #expect(ShellQuote.quote("$HOME") == "'$HOME'")
    }

    @Test("flag-shaped and empty strings never pass bare")
    func edgeShapes() {
        #expect(ShellQuote.quote("-rf") == "'-rf'")
        #expect(ShellQuote.quote("") == "''")
    }
}
