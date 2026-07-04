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

/// The floating keys window — the scalable face of the same card.
///
/// One truth, three doors: drag the frame (aspect forced by the
/// window itself), ⌘ + / −, or the +/− icons. All of them move the
/// same remembered scale.
struct HelpWindow: View {
    /// The remembered scale — shared truth for every resize door.
    @AppStorage("palana.keysScale")
    private var scale = 1.0

    @State private var window: NSWindow?

    /// The card's logical size at scale 1 — the aspect every resize keeps.
    private static let base = CGSize(width: 640, height: 452)
    private static let scaleRange = 0.7...1.8

    var body: some View {
        GeometryReader { geometry in
            HelpOverlay(
                scale: geometry.size.width / Self.base.width,
                footer: "drag, ⌘ + / −, or the icons — same size, three doors"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                scaleButton("minus.circle", by: -0.1, key: "-")
                scaleButton("plus.circle", by: 0.1, key: "=")
            }
            .padding(10)
        }
        .background(
            WindowChrome { chromed in
                chromed.contentAspectRatio = Self.base
                chromed.minSize = CGSize(
                    width: Self.base.width * Self.scaleRange.lowerBound,
                    height: Self.base.height * Self.scaleRange.lowerBound)
                chromed.setContentSize(
                    CGSize(width: Self.base.width * scale, height: Self.base.height * scale))
                window = chromed
            }
        )
        .onDisappear {
            // The frame is the truth when the window closes — remember
            // it so the next summon opens at the same size.
            if let width = window?.frame.width {
                scale = clamp(width / Self.base.width)
            }
        }
    }

    private func scaleButton(_ systemName: String, by delta: Double, key: KeyEquivalent) -> some View {
        Button {
            guard let window else { return }
            let next = clamp(window.frame.width / Self.base.width + delta)
            scale = next
            window.setContentSize(
                CGSize(width: Self.base.width * next, height: Self.base.height * next))
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key, modifiers: .command)
        .help(delta > 0 ? "larger (⌘+)" : "smaller (⌘−)")
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }
}

/// Reaches the hosting NSWindow once it exists — aspect and size are
/// window truths, not view truths.
private struct WindowChrome: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            if let window = probe.window {
                configure(window)
            }
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
