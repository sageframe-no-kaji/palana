// The vocabulary, summoned — ? brings the card, ? ? trades it for a
// floating window that stays. Never both: opening either closes the
// other. The card is fixed and ephemeral, a glance; the window owns
// size, and every way in reaches the same truth — drag the frame
// (aspect held), ⌘ + / −, or the small +/− icons. Weird key glyphs
// are spelled as words, the way space and return already were —
// modifiers keep their marks, which render clean. Display copy lives
// here beside the binding table it describes.

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
        HelpRow(keys: "⇧⌘G", what: "go to host : path"),
    ]

    private static let actions = [
        HelpRow(keys: "space", what: "select and advance"),
        HelpRow(keys: "⌘A / esc", what: "select all / clear"),
        HelpRow(keys: "y / m", what: "copy / move to the other pane — plan first"),
        HelpRow(keys: "r", what: "remove — plan first, Enter enacts"),
        HelpRow(keys: "cc / cd", what: "copy path / directory path"),
        HelpRow(keys: "cf / cn", what: "copy filename / name sans extension"),
        HelpRow(keys: ",n ,s ,m", what: "sort by name, size, modified — again flips"),
        HelpRow(keys: ".", what: "show hidden files"),
        HelpRow(keys: "⌘R", what: "refresh"),
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

/// The floating keys window — the card itself, chromeless.
///
/// The window hugs the card exactly — no margins, no glass, the
/// scene hides the titlebar and resizability tracks content, so the
/// frame cannot disagree with the card. Two doors move the one
/// remembered scale: ⌘ + / − and the +/− icons. Esc closes, handled
/// by the session's key monitor by window identity.
struct HelpWindow: View {
    /// The name the key monitor recognizes.
    static let windowIdentifier = "palana-keys-window"

    /// The remembered scale — shared truth for both resize doors.
    @AppStorage("palana.keysScale")
    private var scale = 1.0

    private static let scaleRange = 0.7...1.8

    var body: some View {
        HelpOverlay(
            scale: scale,
            footer: "esc closes · ⌘ + / − or the icons resize"
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                scaleButton("minus.circle", by: -0.1, key: "-")
                scaleButton("plus.circle", by: 0.1, key: "=")
            }
            .padding(12)
        }
        .background(WindowChrome())
    }

    private func scaleButton(_ systemName: String, by delta: Double, key: KeyEquivalent) -> some View {
        Button {
            scale = min(
                max(scale + delta, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(delta > 0 ? "larger (⌘+)" : "smaller (⌘−)")
    }
}

/// Names the window for the key monitor and strips what the scene
/// style leaves behind — clear ground, movable by the card's body.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(HelpWindow.windowIdentifier)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
