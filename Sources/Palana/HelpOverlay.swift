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

    /// Attaches a dismiss action to the overlay — wired by the card caller
    /// to the same path that esc and `?` already use.
    func onDismiss(_ action: @escaping () -> Void) -> Self {
        var copy = self
        copy.dismissAction = action
        return copy
    }

    private static let leftColumn = [
        HelpSection(
            title: "move",
            rows: [
                HelpRow(keys: "j / k  ↓ / ↑", what: "cursor down / up"),
                HelpRow(keys: "h / l  ← / →", what: "parent / enter directory"),
                HelpRow(keys: "return", what: "enter directory · open file"),
                HelpRow(keys: "gg / G", what: "top / bottom"),
                HelpRow(keys: "⌃d / ⌃u", what: "half page down / up"),
                HelpRow(keys: "pgup / pgdn", what: "page up / down"),
            ]),
        HelpSection(
            title: "select",
            rows: [
                HelpRow(keys: "space", what: "select and advance"),
                HelpRow(keys: "⌘A / esc", what: "select all / clear"),
            ]),
        HelpSection(
            title: "panes",
            rows: [
                HelpRow(keys: "tab", what: "switch pane"),
                HelpRow(keys: "⇧⌘G", what: "go to host : path"),
            ]),
        HelpSection(
            title: "arrange",
            rows: [
                HelpRow(keys: ",n ,s ,m", what: "sort by name, size, modified — again flips"),
                HelpRow(keys: ".", what: "show hidden files"),
                HelpRow(keys: "⌘R", what: "refresh"),
            ]),
    ]

    private static let rightColumn = [
        HelpSection(
            title: "act",
            rows: [
                HelpRow(keys: "y / m", what: "copy / move to the other pane — plan first"),
                HelpRow(keys: "r", what: "remove — plan first, Enter enacts"),
                HelpRow(keys: "R", what: "rename cursor entry — plan first"),
                HelpRow(keys: "a", what: "create (name/ = directory) — plan first"),
                HelpRow(keys: "t", what: "touch — update modified · plan first"),
                HelpRow(keys: "T", what: "touch a new file — names it · plan first"),
            ]),
        HelpSection(
            title: "copy",
            rows: [
                HelpRow(keys: "cc / cd", what: "copy path / directory path"),
                HelpRow(keys: "cf / cn", what: "copy filename / name sans extension"),
            ]),
        HelpSection(
            title: "surfaces",
            rows: [
                HelpRow(keys: "f", what: "field view"),
                HelpRow(keys: "F", what: "host map — floats"),
                HelpRow(keys: "⌘,", what: "settings"),
                HelpRow(keys: "?", what: "this card · ? again floats it"),
            ]),
        HelpSection(
            title: "terminal",
            rows: [
                HelpRow(keys: "`", what: "show / hide the terminal"),
                HelpRow(keys: "⇧tab", what: "engage the terminal · tool reads"),
                HelpRow(keys: "d z s p", what: "df · zfs list · zpool status · zpool list"),
            ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverlayHeader(title: "the keys", onClose: dismissAction)
            VStack(alignment: .leading, spacing: 14 * scale) {
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
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
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
