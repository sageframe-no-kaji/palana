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
/// No titlebar, no border, no white space: the card IS the window
/// (second hands session: "it was better before"). Esc closes it.
/// One truth, three doors: drag the frame (aspect forced by the
/// window itself), ⌘ + / −, or the +/− icons — all move the same
/// remembered scale. The window's identifier tells the session's key
/// monitor to stand down while this window is key.
struct HelpWindow: View {
    /// The name the key monitor stands down for.
    static let windowIdentifier = "palana-keys-window"

    /// The remembered scale — shared truth for every resize door.
    @AppStorage("palana.keysScale")
    private var scale = 1.0

    @State private var window: NSWindow?
    /// The card's natural size at scale 1 — measured, not guessed, so
    /// the frame hugs the card exactly and the aspect is the card's own.
    @State private var base: CGSize?

    @Environment(\.dismissWindow)
    private var dismissWindow

    private static let scaleRange = 0.7...1.8

    var body: some View {
        Group {
            if let base {
                GeometryReader { geometry in
                    card(scale: geometry.size.width / base.width)
                }
            } else {
                // First frame: natural size at the remembered scale,
                // measured once to learn the card's true aspect.
                card(scale: scale)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.onAppear {
                                base = CGSize(
                                    width: geometry.size.width / scale,
                                    height: geometry.size.height / scale)
                            }
                        })
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                scaleButton("minus.circle", by: -0.1, key: "-")
                scaleButton("plus.circle", by: 0.1, key: "=")
            }
            .padding(12)
        }
        .background(WindowChrome { self.window = $0 })
        .onChange(of: base) { _, measured in
            guard let measured, let window else { return }
            window.contentAspectRatio = measured
            window.minSize = CGSize(
                width: measured.width * Self.scaleRange.lowerBound,
                height: measured.height * Self.scaleRange.lowerBound)
            window.setContentSize(
                CGSize(width: measured.width * scale, height: measured.height * scale))
        }
        .onExitCommand {
            dismissWindow(id: "palana-keys")
        }
        .onDisappear {
            // The frame is the truth when the window closes — remember
            // it so the next summon opens at the same size.
            if let base, let width = window?.frame.width {
                scale = clamp(width / base.width)
            }
        }
    }

    private func card(scale: Double) -> some View {
        HelpOverlay(
            scale: scale,
            footer: "esc closes · drag, ⌘ + / −, or the icons resize"
        )
    }

    private func scaleButton(_ systemName: String, by delta: Double, key: KeyEquivalent) -> some View {
        Button {
            guard let window, let base else { return }
            let next = clamp(window.frame.width / base.width + delta)
            scale = next
            window.setContentSize(
                CGSize(width: base.width * next, height: base.height * next))
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

/// Strips the window to the card: no titlebar, no buttons, clear
/// ground, movable by its body — and named so the key monitor knows.
private struct WindowChrome: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async {
            guard let window = probe.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(HelpWindow.windowIdentifier)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            onWindow(window)
        }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
