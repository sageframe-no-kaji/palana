// The forwarding probe — the system design's "probed once, remembered,"
// built at last. The verdict rides stdout so ssh's 255 stays what it
// is: the door to the source failing, never a fact about the hop.

import Foundation
import Testing

@testable import PalanaCore

@Suite("ForwardingFact probe")
struct ForwardingFactTests {
    private static let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_751_500_800) }

    private func tempCache() -> FieldCache {
        FieldCache(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("palana-fwd-\(UUID().uuidString)")
                .appendingPathComponent("field-cache.json"))
    }

    private func makeField(entries: [ConduitTranscript.Entry], cache: FieldCache? = nil) -> Field {
        Field(
            conduit: RecordedConduit(transcript: ConduitTranscript(entries: entries)),
            hosts: ["jodo", "koan"],
            cache: cache ?? tempCache(),
            now: Self.clock)
    }

    @Test("the probe command is batch-mode, five-second door, verdict on stdout")
    func probeCommandShape() {
        let command = Field.forwardingProbeCommand(to: "koan")
        #expect(
            command
                == "ssh -o BatchMode=yes -o ConnectTimeout=5 koan true 2>/dev/null && echo forwarded || echo blocked")
    }

    @Test("a hostile alias is quoted before it reaches the source shell")
    func probeCommandQuotesAlias() {
        let command = Field.forwardingProbeCommand(to: "bad;host")
        #expect(command.contains("'bad;host'"))
    }

    @Test("forwarded on stdout records available")
    func forwardedRecordsAvailable() async {
        let field = makeField(entries: [
            .init(
                host: "jodo",
                command: Field.forwardingProbeCommand(to: "koan"),
                stdout: "forwarded\n",
                stderr: "",
                exit: 0)
        ])
        let fact = await field.forwardingFact(from: "jodo", to: "koan")
        #expect(fact == .available)
    }

    @Test("blocked on stdout records unavailable")
    func blockedRecordsUnavailable() async {
        let field = makeField(entries: [
            .init(
                host: "jodo",
                command: Field.forwardingProbeCommand(to: "koan"),
                stdout: "blocked\n",
                stderr: "",
                exit: 0)
        ])
        let fact = await field.forwardingFact(from: "jodo", to: "koan")
        #expect(fact == .unavailable)
    }

    @Test("a door failure answers unprobed and records nothing")
    func doorFailureIsUnprobed() async {
        let field = makeField(entries: [
            .init(
                host: "jodo",
                command: Field.forwardingProbeCommand(to: "koan"),
                stdout: "",
                stderr: "ssh: connect to host jodo port 22: Connection refused",
                exit: 255)
        ])
        let fact = await field.forwardingFact(from: "jodo", to: "koan")
        #expect(fact == .unprobed)
        let remembered = await field.facts(for: "jodo")?.forwarding
        #expect(remembered == nil)
    }

    @Test("a garbled verdict answers unprobed and records nothing")
    func garbledVerdictIsUnprobed() async {
        let field = makeField(entries: [
            .init(
                host: "jodo",
                command: Field.forwardingProbeCommand(to: "koan"),
                stdout: "motd of the day\n",
                stderr: "",
                exit: 0)
        ])
        let fact = await field.forwardingFact(from: "jodo", to: "koan")
        #expect(fact == .unprobed)
    }

    @Test("probed once, remembered — the second ask never touches the wire")
    func rememberedSkipsWire() async {
        // One transcript entry only: a second wire trip would throw
        // UnrecordedCommand and fail the test through the door fact.
        let field = makeField(entries: [
            .init(
                host: "jodo",
                command: Field.forwardingProbeCommand(to: "koan"),
                stdout: "forwarded\n",
                stderr: "",
                exit: 0)
        ])
        let first = await field.forwardingFact(from: "jodo", to: "koan")
        let second = await field.forwardingFact(from: "jodo", to: "koan")
        #expect(first == .available)
        #expect(second == .available)
    }

    @Test("the fact survives the cache round trip into a fresh Field")
    func cacheRoundTrip() async {
        let cache = tempCache()
        let probed = makeField(
            entries: [
                .init(
                    host: "jodo",
                    command: Field.forwardingProbeCommand(to: "koan"),
                    stdout: "forwarded\n",
                    stderr: "",
                    exit: 0)
            ],
            cache: cache)
        _ = await probed.forwardingFact(from: "jodo", to: "koan")
        // A fresh Field over an empty transcript: memory must answer.
        let fresh = makeField(entries: [], cache: cache)
        let fact = await fresh.forwardingFact(from: "jodo", to: "koan")
        #expect(fact == .available)
        let dated = await fresh.facts(for: "jodo")?.forwarding?["koan"]
        #expect(dated?.discoveredAt == Self.clock())
    }
}
