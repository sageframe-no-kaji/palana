// The vocabulary, summoned — ? brings the card, ? ? trades it for the
// floating keys panel (KeysPanel.swift). Never both: opening either
// closes the other. The card is fixed and ephemeral, a glance. Weird
// key glyphs are spelled as words, the way space and return already
// were — modifiers keep their marks, which render clean. Display copy
// lives here beside the binding table it describes, grouped by kind
// and balanced across two columns.

import AppKit
import SwiftUI

/// One keystroke's worth of help.
private struct HelpRow: Identifiable {
    let keys: String
    let what: String
    var id: String { keys }
}

/// A titled group of rows — like things together.
private struct HelpSection: Identifiable {
    let title: String
    let rows: [HelpRow]
    var id: String { title }
}

/// The keyboard vocabulary — pure display, scaled by its caller.
struct HelpOverlay: View {
    /// Text scale — the card passes 1, the window passes its fit.
    var scale = 1.0
    /// The quiet last line — the card and the window say different things.
    var footer = "? floats this card · esc closes"
    /// Called when the operator taps the ✕ close button.
    ///
    /// Set via the `.onDismiss(_:)` modifier — keeps the primary properties
    /// clean and avoids trailing-closure ambiguity at the call site.
    /// The card caller wires this to `session.helpVisible = false`.
    /// The floating panel leaves it nil — the panel manages its own lifecycle.
    var dismissAction: (() -> Void)?
    /// True when a floating panel hosts the card — the panel owns the
    /// ground, the rounded clip, and the window shadow, so the card must
    /// not draw its own (a card shadow clipped inside the panel's rounded
    /// frame reads as a border).
    var chromeless = false

    /// Attaches a dismiss action to the overlay — wired by the card caller
    /// to the same path that esc and `?` already use.
    func onDismiss(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.dismissAction = action
        return copy
    }

    // Five groups — one grammar lesson. Move and select rows are inlined
    // above the group structure: navigation is muscle memory, not a
    // rule-bearing surface.

    private static let prelude = HelpSection(
        title: "navigate",
        rows: [
            HelpRow(keys: "j / k  ↓ / ↑", what: "cursor down / up"),
            HelpRow(keys: "h / l  ← / →", what: "parent / enter directory"),
            HelpRow(keys: "gg / G", what: "top / bottom"),
            HelpRow(keys: "⌃d / ⌃u", what: "half page · space select"),
            HelpRow(keys: "⌘A / esc", what: "select all / clear · tab switch pane"),
            HelpRow(keys: "/", what: "jump — type a name, the cursor chases it"),
        ])

    private static let leftColumn = [
        HelpSection(
            title: "verbs",
            rows: [
                HelpRow(keys: "y", what: "copy to other pane — plan first"),
                HelpRow(keys: "m", what: "move to other pane — plan first"),
                HelpRow(keys: "d", what: "delete — plan first, Enter enacts"),
                HelpRow(keys: "r", what: "rename — opens name field, ⏎ renames"),
                HelpRow(keys: "a", what: "create — name/ for a directory"),
                HelpRow(keys: "t", what: "touch — update modified"),
            ]),
        HelpSection(
            title: "names",
            rows: [
                HelpRow(keys: "r / a", what: "open the name field"),
                HelpRow(keys: "⏎", what: "commit name · renames or creates"),
            ]),
        HelpSection(
            title: "families",
            rows: [
                HelpRow(keys: "c c / c d", what: "copy path / directory path"),
                HelpRow(keys: "c f / c n", what: "copy filename / name sans extension"),
                HelpRow(keys: ", n / , s / , m", what: "sort by name / size / modified"),
                HelpRow(keys: "g g / G", what: "top / bottom"),
            ]),
    ]

    private static let rightColumn = [
        HelpSection(
            title: "surfaces",
            rows: [
                HelpRow(keys: "f", what: "field view"),
                HelpRow(keys: "F", what: "host map — floats"),
                HelpRow(keys: "*", what: "favorites panel"),
                HelpRow(keys: "v", what: "preview — right pane follows left"),
                HelpRow(keys: "`", what: "terminal"),
                HelpRow(keys: "⌘`", what: "live shell — ⌘` moves the keyboard"),
                HelpRow(keys: "?", what: "this card · ? again floats it"),
                HelpRow(keys: "⌘,", what: "settings"),
            ]),
        HelpSection(
            title: "zfs mode",
            rows: [
                HelpRow(keys: "Z", what: "enter / exit the dataset tree"),
                HelpRow(keys: "↑ ↓", what: "walk datasets · a letter fires its verb"),
                HelpRow(keys: "⏎", what: "open a mounted dataset in the pane"),
                HelpRow(keys: "esc", what: "leave zfs mode"),
            ]),
        HelpSection(
            title: "app",
            rows: [
                HelpRow(keys: "⌘R", what: "refresh"),
                HelpRow(keys: "⌘← / ⌘→", what: "back / forward"),
                HelpRow(keys: "⌘+ / ⌘− / ⌘0", what: "zoom in / out / reset"),
                HelpRow(keys: "⌘K", what: "clear terminal"),
                HelpRow(keys: "⇧⌘G", what: "go to host : path"),
                HelpRow(keys: "⇧⌘L", what: "operations log"),
                HelpRow(keys: "8", what: "star highlighted entry"),
                HelpRow(keys: "⌘8", what: "star this folder"),
            ]),
        HelpSection(
            title: "terminal reads",
            rows: [
                HelpRow(keys: "⇧tab", what: "engage · tool reads"),
                HelpRow(keys: "d z s p", what: "df · zfs list · zpool status · zpool list"),
            ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverlayHeader(title: "the keys", onClose: dismissAction)
            VStack(alignment: .leading, spacing: 14 * scale) {
                column([Self.prelude])
                Divider()
                HStack(alignment: .top, spacing: 32 * scale) {
                    column(Self.leftColumn)
                    column(Self.rightColumn)
                }
                marksLegend
                Text("the terminal — a plan before Enter, its live output after; the tool reads land here too")
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Theme.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footer)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, 24 * scale)
            .padding(.bottom, 24 * scale)
            .padding(.top, 6 * scale)
        }
        .background(chromeless ? nil : Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: chromeless ? 0 : 10))
        .shadow(
            color: chromeless ? .clear : Theme.ink.opacity(0.18),
            radius: chromeless ? 0 : 24,
            y: chromeless ? 0 : 8
        )
        .fixedSize()
    }

    /// The pane's drive glyphs, explained — filled is a dataset, hollow a plain mount.
    private var marksLegend: some View {
        HStack(spacing: 18 * scale) {
            HStack(spacing: 5 * scale) {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(Theme.accent)
                Text("zfs dataset")
            }
            HStack(spacing: 5 * scale) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(Theme.inkFaint)
                Text("plain mount — a filesystem boundary")
            }
        }
        .font(.system(size: 10 * scale))
        .foregroundStyle(Theme.inkFaint)
    }

    private func column(_ sections: [HelpSection]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14 * scale, verticalSpacing: 6 * scale) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                GridRow {
                    Text(section.title)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .gridCellColumns(2)
                        .padding(.top, index == 0 ? 0 : 8 * scale)
                }
                ForEach(section.rows) { row in
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
        }
        .font(.system(size: 12 * scale))
        .fixedSize()
    }
}
