// PalanaSession+PanelKeys — the settings panel's key handler and the shared
// zoom chord, split from PalanaSession.swift for the line budget. The key
// monitor routes each floating panel here by window identity; Esc closes and
// ⌘+/−/0 zoom, and for settings every other key passes through to the field
// editor untouched.

import AppKit

extension PalanaSession {
    /// Routes a key event while the settings panel is the key window.
    ///
    /// Esc closes; ⌘+/−/0 drive the one master zoom. Everything else returns
    /// false so the event flows on to the field editor — the rsync-flags and
    /// add-host text fields need their keystrokes.
    func handleSettingsPanelKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            SettingsPanelController.shared.close()
            return true
        }
        guard event.modifierFlags.contains(.command) else { return false }
        return applyZoomChord(event.charactersIgnoringModifiers)
    }

    /// Drives the one master text scale from a ⌘+/−/0 chord.
    ///
    /// Shared by the panel key handlers. Returns true when the chord matched.
    func applyZoomChord(_ chars: String?) -> Bool {
        switch chars {
        case "=", "+":
            TextScale.shared.stepUp()
            return true
        case "-":
            TextScale.shared.stepDown()
            return true
        case "0":
            TextScale.shared.reset()
            return true
        default:
            return false
        }
    }
}
