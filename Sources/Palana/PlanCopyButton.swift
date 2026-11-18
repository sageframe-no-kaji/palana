// The plan panel's copy button (#3): the plan and every transcript line, as
// plain text, onto the clipboard. The text itself is composed in PalanaCore
// (PlanText.clipboardText), where it is tested.

import AppKit
import PalanaCore
import SwiftUI

/// Copies the plan on screen and its run's output as plain text.
///
/// Live while a plan or a finished run is showing; dimmed and inert while
/// work is in flight, like the verb rail. The glyph turns to a check for a
/// second after a copy.
struct PlanCopyButton: View {
    /// The panel's operation: its plan and transcript.
    let operation: OperationModel
    /// Whether there is something to copy and no work in flight.
    let available: Bool

    @State private var copied = false

    var body: some View {
        Button {
            let notices =
                (operation.plan?.usesProgressiveRsyncMove ?? false)
                ? [OperationModel.progressiveMoveNotice] : []
            let text = PlanText.clipboardText(plan: operation.plan, notices: notices, echo: operation.echo)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Theme.accent : Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .help("copy the plan and its output")
        .disabled(!available)
        .opacity(available ? 1 : 0.35)
    }
}
