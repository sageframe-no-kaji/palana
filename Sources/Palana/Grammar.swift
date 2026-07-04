// The binding table — the Surface's half of the grammar, declarative
// data over the core's machinery. yazi's verbs under Mac muscle
// memory, committed as the starting vocabulary and pruned by the
// practitioner's hands. Pruning edits this table, nothing else.

import AppKit
import PalanaCore

/// The keyboard grammar: bindings and the event-to-token mapping.
enum Grammar {
    /// The starting vocabulary.
    ///
    /// Esc is absent on purpose — it clears a pending prefix before it
    /// clears the selection, which is the session's call, not the
    /// recognizer's.
    static let bindings: [[String]: PaneIntent] = [
        ["j"]: .cursorDown,
        ["down"]: .cursorDown,
        ["k"]: .cursorUp,
        ["up"]: .cursorUp,
        ["h"]: .ascend,
        ["left"]: .ascend,
        ["l"]: .descend,
        ["right"]: .descend,
        ["return"]: .descend,
        ["g", "g"]: .cursorToTop,
        ["home"]: .cursorToTop,
        ["G"]: .cursorToBottom,
        ["end"]: .cursorToBottom,
        ["ctrl-d"]: .cursorHalfPageDown,
        ["ctrl-u"]: .cursorHalfPageUp,
        ["pgdn"]: .cursorPageDown,
        ["pgup"]: .cursorPageUp,
        ["space"]: .toggleSelectionAndAdvance,
        ["cmd-a"]: .selectAll,
        ["tab"]: .switchPane,
        ["c", "c"]: .copyPath,
        ["c", "d"]: .copyDirectory,
        ["c", "f"]: .copyFilename,
        ["c", "n"]: .copyNameSansExtension,
        ["."]: .toggleHidden,
        [",", "n"]: .sortByName,
        [",", "s"]: .sortBySize,
        [",", "m"]: .sortByModified,
        ["cmd-r"]: .refresh,
        ["cmd-shift-g"]: .goTo,
    ]

    /// Key codes for the non-character keys, ANSI layout.
    private static let specialKeys: [UInt16: String] = [
        36: "return",
        48: "tab",
        49: "space",
        53: "esc",
        115: "home",
        116: "pgup",
        119: "end",
        121: "pgdn",
        123: "left",
        124: "right",
        125: "down",
        126: "up",
    ]

    /// Turns a key event into a grammar token, or nil for events the
    /// grammar has no opinion about — those pass through to the system.
    static func token(for event: NSEvent) -> String? {
        let flags = event.modifierFlags
        guard !flags.contains(.option) else { return nil }
        var mods: [String] = []
        if flags.contains(.command) { mods.append("cmd") }
        if flags.contains(.control) { mods.append("ctrl") }
        if let base = specialKeys[event.keyCode] {
            return assemble(mods, base)
        }
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return nil }
        // With cmd or ctrl held, shift is named explicitly and the
        // letter lowercases — cmd-shift-g, not cmd-G. Bare keys keep
        // their case: G is its own verb.
        if mods.isEmpty {
            return chars
        }
        if flags.contains(.shift) { mods.append("shift") }
        return assemble(mods, chars.lowercased())
    }

    /// Joins modifiers and base into one token.
    private static func assemble(_ mods: [String], _ base: String) -> String {
        mods.isEmpty ? base : (mods + [base]).joined(separator: "-")
    }
}
