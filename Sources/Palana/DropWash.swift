// DropWash — the accent wash, inner border, and copy/move caption drawn over a
// pane while a valid drag hovers it. Extracted from PaneView for the line
// budget. The caption names the rule right where the drop lands: copy is the
// default, ⌘ moves — the discoverability the hidden ⌥ never gave.

import SwiftUI

/// The drop-target wash with its verb caption.
///
/// Over the pane itself: the accent wash, the inner border and "drop to copy ·
/// hold ⌘ to move". Over a folder row (`folderName` set): the caption alone,
/// naming the folder — the row carries its own light.
struct DropWash: View {
    /// The folder the drop would land in, or nil for the pane's directory.
    var folderName: String?

    var body: some View {
        ZStack {
            if folderName == nil {
                Theme.accent.opacity(0.08)
                Rectangle().strokeBorder(Theme.accent, lineWidth: 2)
            }
            VStack {
                Spacer()
                Text(Self.caption(folderName: folderName))
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

    /// The caption: where the drop lands and the one modifier.
    static func caption(folderName: String?) -> String {
        guard let folderName else { return "drop to copy · hold ⌘ to move" }
        return "drop into \(folderName)/ to copy · hold ⌘ to move"
    }
}
