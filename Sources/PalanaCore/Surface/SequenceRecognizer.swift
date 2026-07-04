// The key-sequence recognizer — the machine that turns a keystroke
// stream into intents through a binding table. gg and cc are two-key
// sequences, so the machine holds a pending prefix and a table lookup,
// nothing more. Generic over the intent so the tests need no grammar
// and the grammar needs no tests here beyond this machine's own.

/// Recognizes key sequences against a binding table.
///
/// Keys are opaque tokens — the Surface decides how a `KeyPress`
/// becomes a token. Sequences share prefixes freely: `c` pending
/// against `cc` and `cd` resolves on the second key.
public struct SequenceRecognizer<Intent: Sendable>: Sendable {
    /// What one keystroke did.
    public enum Outcome {
        /// A sequence completed.
        case matched(Intent)
        /// The stroke extended a prefix — more keys decide.
        case pending([String])
        /// No binding wants it. The prefix is cleared.
        case unmatched
    }

    private let bindings: [[String]: Intent]

    /// The keys held while a multi-key sequence is in flight — the
    /// footer renders this so a pending `c` or `g` is visible.
    public private(set) var prefix: [String] = []

    /// A recognizer over a binding table.
    public init(bindings: [[String]: Intent]) {
        self.bindings = bindings
    }

    /// Feeds one key token through the machine.
    ///
    /// A dead-end sequence retries the key alone before giving up, so
    /// a stray prefix never eats the next real command — `g` then `j`
    /// still moves the cursor.
    public mutating func press(_ key: String) -> Outcome {
        let candidate = prefix + [key]
        if let intent = bindings[candidate] {
            prefix = []
            return .matched(intent)
        }
        if extendsSomeBinding(candidate) {
            prefix = candidate
            return .pending(candidate)
        }
        prefix = []
        guard candidate.count > 1 else { return .unmatched }
        if let intent = bindings[[key]] {
            return .matched(intent)
        }
        if extendsSomeBinding([key]) {
            prefix = [key]
            return .pending([key])
        }
        return .unmatched
    }

    /// Drops any pending prefix — Esc's half of the job.
    public mutating func reset() {
        prefix = []
    }

    /// True when some binding is longer than the candidate and starts
    /// with it.
    private func extendsSomeBinding(_ candidate: [String]) -> Bool {
        bindings.keys.contains { sequence in
            sequence.count > candidate.count && Array(sequence.prefix(candidate.count)) == candidate
        }
    }
}
