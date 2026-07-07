// The vocabulary, summoned — ? brings the card, ? ? trades it for the
// floating keys panel (KeysPanel.swift). Never both: opening either
// closes the other. The card is fixed and ephemeral, a glance. Weird
// key glyphs are spelled as words, the way space and return already
// were — modifiers keep their marks, which render clean. Display copy
// lives here beside the binding table it describes.

import AppKit
import SwiftUI

/// One keystroke's worth of help.
private struct HelpRow: Identifiable {
    let keys: String
    let what: String
    var id: String { keys }
}

/// The keyboard vocabulary — pure display, scaled by its caller.
struct HelpOverlay: View {
    /// Text scale — the card passes 1, the window passes its fit.
    var scale = 1.0
    /// The quiet last line — the card and the window say different things.
    var footer = "? floats this card · esc closes"

    private static let navigation = [
        HelpRow(keys: "j / k  ↓ / ↑", what: "cursor down / up"),
        HelpRow(keys: "h / l  ← / →", what: "parent / enter directory"),
        HelpRow(keys: "return", what: "enter directory · open file"),
        HelpRow(keys: "gg / G", what: "top / bottom"),
        HelpRow(keys: "⌃d / ⌃u", what: "half page down / up"),
        HelpRow(keys: "pgup / pgdn", what: "page up / down"),
        HelpRow(keys: "tab", what: "switch pane"),
        HelpRow(keys: "⇧tab", what: "into the terminal · tool reads"),
        HelpRow(keys: "⇧⌘G", what: "go to host : path"),
    ]

    private static let actions = [
        HelpRow(keys: "space", what: "select and advance"),
        HelpRow(keys: "⌘A / esc", what: "select all / clear"),
        HelpRow(keys: "y / m", what: "copy / move to the other pane — plan first"),
        HelpRow(keys: "r", what: "remove — plan first, Enter enacts"),
        HelpRow(keys: "R", what: "rename cursor entry — plan first"),
        HelpRow(keys: "a", what: "create (name/ = directory) — plan first"),
        HelpRow(keys: "t", what: "touch — update modified · plan first"),
        HelpRow(keys: "T", what: "touch a new file — names it · plan first"),
        HelpRow(keys: "cc / cd", what: "copy path / directory path"),
        HelpRow(keys: "cf / cn", what: "copy filename / name sans extension"),
        HelpRow(keys: ",n ,s ,m", what: "sort by name, size, modified — again flips"),
        HelpRow(keys: ".", what: "show hidden files"),
        HelpRow(keys: "⌘R", what: "refresh"),
        HelpRow(keys: "f", what: "field view"),
        HelpRow(keys: "F", what: "host map — floats"),
        HelpRow(keys: "`", what: "show / hide the terminal panel"),
        HelpRow(keys: "⌘,", what: "settings"),
        HelpRow(keys: "?", what: "this card · ? again floats it"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            Text("the keys")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            HStack(alignment: .top, spacing: 32 * scale) {
                column(Self.navigation)
                column(Self.actions)
            }
            Text(footer)
                .font(.system(size: 10 * scale))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(24 * scale)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
        .fixedSize()
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
