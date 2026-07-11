// PalanaSession+Jump — `/` type-to-jump (his ask, round 10: "when you
// type (to jump) is there a way to suppress the hot keys?"). The answer
// is a mode, not suppression: `/` stands the whole verb grammar down and
// every letter becomes content, exactly the discipline path editing and
// the gather field already follow. Esc cancels, ⏎ keeps the cursor
// where the jump put it, arrows hand back to navigation.

import AppKit
import PalanaCore

extension PalanaSession {
    /// Opens the jump — `/` at pane focus, files mode only.
    ///
    /// zfs mode keeps its letters as verbs; a dataset jump is a banked
    /// nicety. Terminal focus keeps its tool letters.
    func beginJump() {
        jumpBuffer = ""
    }

    /// Routes every key while the jump is open.
    ///
    /// True means consumed. Plain characters append and the cursor follows live — prefix
    /// match first, then contains, case-insensitive, in displayed order.
    /// Backspace edits. Esc cancels. ⏎ accepts (the cursor stays).
    /// Arrows accept AND pass through, so walking on from the match
    /// needs no extra keystroke. ⌘ shortcuts keep working.
    func handleJumpKey(_ event: NSEvent) -> Bool {
        guard let buffer = jumpBuffer else { return false }
        if event.modifierFlags.contains(.command) {
            if let token = Grammar.token(for: event) {
                return handleGlobalChord(token)
            }
            return false
        }
        switch event.keyCode {
        case 53:  // esc — cancel, cursor stays where the jump left it
            jumpBuffer = nil
            return true
        case 36, 76:  // return — accept
            jumpBuffer = nil
            return true
        case 125, 126, 123, 124:  // arrows — accept and hand back
            jumpBuffer = nil
            return false
        case 51:  // delete — edit the buffer
            guard !buffer.isEmpty else {
                jumpBuffer = nil
                return true
            }
            jumpBuffer = String(buffer.dropLast())
            jumpCursor()
            return true
        default:
            guard let chars = event.charactersIgnoringModifiers,
                !chars.isEmpty,
                chars.rangeOfCharacter(from: .controlCharacters) == nil
            else { return true }
            jumpBuffer = buffer + chars
            jumpCursor()
            return true
        }
    }

    /// Moves the focused pane's cursor to the buffer's best match.
    ///
    /// Prefix beats contains; displayed order breaks ties; an empty or
    /// matchless buffer moves nothing (the operator sees the buffer in
    /// the footer and keeps typing or edits).
    private func jumpCursor() {
        guard let buffer = jumpBuffer?.lowercased(), !buffer.isEmpty else { return }
        let pane = focusedPane
        let names = pane.rows
        let match =
            names.first { $0.name.lowercased().hasPrefix(buffer) }
            ?? names.first { $0.name.lowercased().contains(buffer) }
        guard let match else { return }
        pane.state.cursor = match.id
    }
}
