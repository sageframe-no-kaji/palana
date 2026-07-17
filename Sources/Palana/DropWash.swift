// DropWash — the accent wash, inner border, and copy/move caption drawn over a
// pane while a valid drag hovers it. Extracted from PaneView for the line
// budget. The caption names the rule right where the drop lands: copy is the
// default, ⌘ moves — the discoverability the hidden ⌥ never gave.

import SwiftUI

/// The drop-target wash with its verb caption.
struct DropWash: View {
    var body: some View {
        ZStack {
            Theme.accent.opacity(0.08)
            Rectangle().strokeBorder(Theme.accent, lineWidth: 2)
            VStack {
                Spacer()
                Text("drop to copy · hold ⌘ to move")
                    .font(Theme.font(11, weight: .medium))
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
                    .padding(.bottom, 36)
            }
        }
        .allowsHitTesting(false)
    }
}
