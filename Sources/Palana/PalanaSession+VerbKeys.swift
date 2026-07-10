// PalanaSession+VerbKeys — chip-click dispatch for the plan panel's
// go-again hint line. Each chip passes a key string; this routes it
// to the same verb entry-points the physical key uses, so no verb
// logic is duplicated across the two paths.

import PalanaCore
import SwiftUI

// MARK: - Chip clicks (plan panel go-again)

extension PalanaSession {
    /// Routes a chip click in the go-again hint line to the same verb
    /// entry-points the physical key uses — no logic is duplicated.
    ///
    /// `esc` mirrors the panel-priority esc handler in `handlePanelPriorityKey`.
    func handleVerbKey(_ key: String) {
        switch key {
        case "y": beginOperation(.copy)
        case "m": beginOperation(.move)
        case "d": beginOperation(.delete)
        case "r": beginNaming(.rename)
        case "a": beginNaming(.create)
        case "t": beginOperation(.touch)
        case "esc":
            if operation.terminalBusy {
                operation.cancelCommand()
                terminalFocused = true
            } else {
                terminalFocused = false
                operation.hidePanel()
            }
        default:
            break
        }
    }
}
