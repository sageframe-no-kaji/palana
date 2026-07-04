// The sequence recognizer — the keystroke machine, pinned with a toy
// grammar. The real binding table is the Surface's data; this battery
// proves the machine under every shape the table can take.

import Testing

@testable import PalanaCore

@Suite("SequenceRecognizer")
struct SequenceRecognizerTests {
    private enum Toy: Equatable {
        case down
        case top
        case copyPath
        case copyDir
        case sortName
    }

    private static let bindings: [[String]: Toy] = [
        ["j"]: .down,
        ["g", "g"]: .top,
        ["c", "c"]: .copyPath,
        ["c", "d"]: .copyDir,
        [",", "n"]: .sortName,
    ]

    private func makeRecognizer() -> SequenceRecognizer<Toy> {
        SequenceRecognizer(bindings: Self.bindings)
    }

    @Test("a single-key binding matches immediately")
    func singleKey() {
        var recognizer = makeRecognizer()
        guard case .matched(let intent) = recognizer.press("j") else {
            Issue.record("expected a match")
            return
        }
        #expect(intent == .down)
        #expect(recognizer.prefix.isEmpty)
    }

    @Test("a two-key sequence goes pending, then matches")
    func twoKey() {
        var recognizer = makeRecognizer()
        guard case .pending(let prefix) = recognizer.press("g") else {
            Issue.record("expected pending")
            return
        }
        #expect(prefix == ["g"])
        guard case .matched(let intent) = recognizer.press("g") else {
            Issue.record("expected a match")
            return
        }
        #expect(intent == .top)
    }

    @Test("sequences sharing a prefix resolve on the second key")
    func sharedPrefix() {
        var recognizer = makeRecognizer()
        _ = recognizer.press("c")
        guard case .matched(let intent) = recognizer.press("d") else {
            Issue.record("expected a match")
            return
        }
        #expect(intent == .copyDir)
    }

    @Test("a dead-end sequence retries the key alone — g then j still moves")
    func deadEndRetries() {
        var recognizer = makeRecognizer()
        _ = recognizer.press("g")
        guard case .matched(let intent) = recognizer.press("j") else {
            Issue.record("expected the retried key to match")
            return
        }
        #expect(intent == .down)
        #expect(recognizer.prefix.isEmpty)
    }

    @Test("a dead end whose key opens a new sequence goes pending on it")
    func deadEndReopens() {
        var recognizer = makeRecognizer()
        _ = recognizer.press("g")
        guard case .pending(let prefix) = recognizer.press("c") else {
            Issue.record("expected pending on the reopened prefix")
            return
        }
        #expect(prefix == ["c"])
    }

    @Test("an unknown key is unmatched and clears nothing it should keep")
    func unknownKey() {
        var recognizer = makeRecognizer()
        guard case .unmatched = recognizer.press("z") else {
            Issue.record("expected unmatched")
            return
        }
        #expect(recognizer.prefix.isEmpty)
    }

    @Test("reset drops a pending prefix")
    func reset() {
        var recognizer = makeRecognizer()
        _ = recognizer.press("c")
        recognizer.reset()
        #expect(recognizer.prefix.isEmpty)
        guard case .matched(let intent) = recognizer.press("j") else {
            Issue.record("expected a clean match after reset")
            return
        }
        #expect(intent == .down)
    }
}
