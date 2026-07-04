// The vocabulary, summoned — ? brings the card, ? ? trades it for a
// floating window that stays. The layout is absolute: every label one
// line, the card exactly as wide as its content, no reflow ever
// (second hands session: "control the aspect absolutely"). ⌘ + / −
// scale the text, aspect intact; small +/− icons carry the same verbs.
// Display copy lives here beside the binding table it describes —
// pruning the grammar edits both.

import SwiftUI

/// One keystroke's worth of help.
private struct HelpRow: Identifiable {
    let keys: String
    let what: String
    var id: String { keys }
}

/// The keyboard vocabulary as a summonable card.
struct HelpOverlay: View {
    /// Text scale, remembered — the aspect never changes, only the size.
    @AppStorage("palana.keysScale")
    private var scale = 1.0

    private static let scaleRange = 0.7...1.6

    private static let navigation = [
        HelpRow(keys: "j / k  ↓ / ↑", what: "cursor down / up"),
        HelpRow(keys: "h / l  ← / →", what: "parent / enter directory"),
        HelpRow(keys: "return", what: "enter directory · open file"),
        HelpRow(keys: "gg / G", what: "top / bottom"),
        HelpRow(keys: "⌃d / ⌃u", what: "half page down / up"),
        HelpRow(keys: "⇞ / ⇟", what: "page up / down"),
        HelpRow(keys: "⇥", what: "switch pane"),
        HelpRow(keys: "⇧⌘G", what: "go to host : path"),
    ]

    private static let actions = [
        HelpRow(keys: "space", what: "select and advance"),
        HelpRow(keys: "⌘A / esc", what: "select all / clear"),
        HelpRow(keys: "y / m", what: "copy / move to the other pane — plan first"),
        HelpRow(keys: "d", what: "delete — plan first, Enter enacts"),
        HelpRow(keys: "cc / cd", what: "copy path / directory path"),
        HelpRow(keys: "cf / cn", what: "copy filename / name sans extension"),
        HelpRow(keys: ",n ,s ,m", what: "sort by name, size, modified — again flips"),
        HelpRow(keys: ".", what: "show hidden files"),
        HelpRow(keys: "⌘R", what: "refresh"),
        HelpRow(keys: "?", what: "this card · ? again floats it"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            HStack(spacing: 8) {
                Text("the keys")
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                Spacer(minLength: 24)
                scaleButton("minus.circle", by: -0.1, key: "-")
                scaleButton("plus.circle", by: 0.1, key: "=")
            }
            HStack(alignment: .top, spacing: 32 * scale) {
                column(Self.navigation)
                column(Self.actions)
            }
            Text("? or esc closes · ⌘ + / − resize")
                .font(.system(size: 10 * scale))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(24 * scale)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
        .fixedSize()
    }

    /// One quiet resize verb — icon and ⌘-key, same move.
    private func scaleButton(_ systemName: String, by delta: Double, key: KeyEquivalent) -> some View {
        Button {
            scale = min(max(scale + delta, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11 * scale))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(delta > 0 ? "larger text (⌘+)" : "smaller text (⌘−)")
    }

    private func column(_ rows: [HelpRow]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14 * scale, verticalSpacing: 6 * scale) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.keys)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(row.what)
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
            }
        }
        .font(.system(size: 12 * scale))
        .fixedSize()
    }
}
