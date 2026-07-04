// The vocabulary, summoned — ? brings it, ? or Esc dismisses it. The
// first hands session asked "which grammar?"; the answer belongs in
// the app, not in a notification. Display copy lives here beside the
// binding table it describes — pruning the grammar edits both.

import SwiftUI

/// One keystroke's worth of help.
private struct HelpRow: Identifiable {
    let keys: String
    let what: String
    var id: String { keys }
}

/// The keyboard vocabulary as a summonable card.
struct HelpOverlay: View {
    private static let navigation = [
        HelpRow(keys: "j / k  ↓ / ↑", what: "cursor down / up"),
        HelpRow(keys: "h / l  ← / →", what: "parent / enter dir · open file"),
        HelpRow(keys: "return", what: "enter directory · open file"),
        HelpRow(keys: "gg / G", what: "top / bottom"),
        HelpRow(keys: "⌃d / ⌃u", what: "half page down / up"),
        HelpRow(keys: "⇞ / ⇟", what: "page up / down"),
        HelpRow(keys: "⇥", what: "switch pane"),
        HelpRow(keys: "⇧⌘G", what: "point pane at host : path"),
    ]

    private static let actions = [
        HelpRow(keys: "space", what: "select and advance"),
        HelpRow(keys: "⌘A / esc", what: "select all / clear"),
        HelpRow(keys: "cc / cd", what: "copy path / directory path"),
        HelpRow(keys: "cf / cn", what: "copy filename / name sans extension"),
        HelpRow(keys: ",n ,s ,m", what: "sort by name, size, modified — again flips"),
        HelpRow(keys: ".", what: "show hidden files"),
        HelpRow(keys: "⌘R", what: "refresh"),
        HelpRow(keys: "?", what: "this card"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("the keys")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            HStack(alignment: .top, spacing: 32) {
                column(Self.navigation)
                column(Self.actions)
            }
            Text("? or esc closes")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(24)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
    }

    private func column(_ rows: [HelpRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.keys)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.ink)
                    Text(row.what)
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .font(.system(size: 12))
    }
}
