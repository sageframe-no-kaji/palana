// The shell's caret rests when the panes have the keyboard (hands
// session 2026-09-08): "The cursor HAS to stop blinking when the terminal
// pane is not focussed. AND it should get lighter even when it is — get
// fairly washed out." The decision is a pure policy over SwiftTerm's
// CursorStyle, pinned for every style here; the view half builds one
// ShellTerminalView with NO process started — no PTY, no ssh — rests and
// wakes it, and reads the caret's style, color, and blink animation back.

import AppKit
import SwiftTerm
import Testing

@testable import Palana

@Suite("ShellCaretPolicy: the rest, style by style")
struct ShellCaretPolicyTests {
    // Computed, not stored: SwiftTerm's CursorStyle is not Sendable, so a
    // stored static would be flagged as shared mutable state.
    private static var blinking: [CursorStyle] { [.blinkBlock, .blinkBar, .blinkUnderline] }
    private static var steady: [CursorStyle] { [.steadyBlock, .steadyBar, .steadyUnderline] }

    @Test("steady keeps the shape and drops the blink")
    func steadyKeepsShape() {
        #expect(ShellCaretPolicy.steady(.blinkBlock) == .steadyBlock)
        #expect(ShellCaretPolicy.steady(.blinkBar) == .steadyBar)
        #expect(ShellCaretPolicy.steady(.blinkUnderline) == .steadyUnderline)
        for style in Self.steady {
            #expect(ShellCaretPolicy.steady(style) == style, "\(style)")
        }
    }

    @Test("blinks names the three blinking styles and no others")
    func blinksClassifies() {
        for style in Self.blinking {
            #expect(ShellCaretPolicy.blinks(style), "\(style)")
        }
        for style in Self.steady {
            #expect(!ShellCaretPolicy.blinks(style), "\(style)")
        }
    }

    @Test("the shell's request shows unchanged while the shell holds the keyboard")
    func activeShowsTheRequest() {
        for style in Self.blinking + Self.steady {
            #expect(ShellCaretPolicy.style(requested: style, resting: false) == style, "\(style)")
        }
    }

    @Test("resting never blinks, whatever the shell asked for")
    func restingNeverBlinks() {
        for style in Self.blinking + Self.steady {
            let shown = ShellCaretPolicy.style(requested: style, resting: true)
            #expect(!ShellCaretPolicy.blinks(shown), "\(style)")
            #expect(shown == ShellCaretPolicy.steady(style), "\(style)")
        }
    }

    @Test("caretRest — the ink's RGB, washed well under inkFaint, both appearances")
    func caretRestToken() {
        #expect(
            Theme.Token.caretRest.light == RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 0.30))
        #expect(
            Theme.Token.caretRest.dark == RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 0.35))
        for isDark in [false, true] {
            let rest = Theme.Token.caretRest.resolved(dark: isDark)
            let ink = Theme.Token.ink.resolved(dark: isDark)
            let faint = Theme.Token.inkFaint.resolved(dark: isDark)
            #expect(rest.red == ink.red && rest.green == ink.green && rest.blue == ink.blue, "dark: \(isDark)")
            #expect(rest.alpha < faint.alpha, "dark: \(isDark)")
        }
    }
}

/// The view half: SwiftTerm's caret is an AppKit view, so the proof builds
/// one. `ShellTerminalView(frame:)` alone starts nothing — `startProcess`
/// is never called, so no shell and no PTY exist here.
@MainActor
@Suite("ShellTerminalView: the caret rests and wakes", .enabled(if: !TestEnvironment.isHeadlessCI))
struct ShellTerminalViewCaretTests {
    /// The sRGB components `color` draws with under the named appearance —
    /// how a dynamic `NSColor` is read back without a window.
    private static func components(of color: NSColor, dark: Bool) -> RGBA? {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
        var resolved: RGBA?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            resolved = RGBA(
                red: srgb.redComponent,
                green: srgb.greenComponent,
                blue: srgb.blueComponent,
                alpha: srgb.alphaComponent)
        }
        return resolved
    }

    private static func close(_ lhs: RGBA?, _ rhs: RGBA) -> Bool {
        guard let lhs else { return false }
        let tolerance = 0.002
        return abs(lhs.red - rhs.red) < tolerance && abs(lhs.green - rhs.green) < tolerance
            && abs(lhs.blue - rhs.blue) < tolerance && abs(lhs.alpha - rhs.alpha) < tolerance
    }

    /// SwiftTerm's caret is the one subview of its own class; its layer
    /// carries the opacity animation while it blinks and nothing while it
    /// is steady.
    private static func caretLayer(in view: ShellTerminalView) throws -> CALayer {
        let caret = view.subviews.first { String(describing: type(of: $0)) == "CaretView" }
        return try #require(caret?.layer)
    }

    private static func caretBlinks(in view: ShellTerminalView) throws -> Bool {
        try caretLayer(in: view).animation(forKey: "opacity") != nil
    }

    @Test("resting: steady, washed in caretRest, text left to the terminal's foreground; waking restores")
    func restsAndWakes() throws {
        let view = ShellTerminalView(frame: .zero)
        let activeColor = view.caretColor
        #expect(!view.caretResting)
        #expect(view.requestedCaretStyle == view.terminal.options.cursorStyle)
        #expect(view.shownCaretStyle == .blinkBlock, "SwiftTerm's default is a blinking block")
        #expect(view.caretTextColor == nil)

        view.setCaretResting(true)
        #expect(view.caretResting)
        #expect(view.shownCaretStyle == .steadyBlock)
        #expect(view.requestedCaretStyle == .blinkBlock, "the shell's request is remembered, not overwritten")
        #expect(Self.close(Self.components(of: view.caretColor, dark: false), Theme.Token.caretRest.light))
        #expect(Self.close(Self.components(of: view.caretColor, dark: true), Theme.Token.caretRest.dark))
        #expect(view.caretTextColor == nil, "the glyph under a resting caret keeps the terminal's foreground")
        #expect(try !Self.caretBlinks(in: view), "no opacity animation on the resting caret's layer")

        view.setCaretResting(false)
        #expect(!view.caretResting)
        #expect(view.shownCaretStyle == .blinkBlock)
        #expect(view.caretColor == activeColor, "the color from before the rest comes back")
        #expect(try Self.caretBlinks(in: view), "the shell's blink is back")
    }

    @Test("a DECSCUSR blink request arriving while resting shows steady; it takes effect on waking")
    func requestWhileRestingStaysSteady() throws {
        let view = ShellTerminalView(frame: .zero)
        view.setCaretResting(true)
        view.cursorStyleChanged(source: view.terminal, newStyle: .blinkBar)
        #expect(view.requestedCaretStyle == .blinkBar)
        #expect(view.shownCaretStyle == .steadyBar)
        #expect(try !Self.caretBlinks(in: view))

        view.setCaretResting(false)
        #expect(view.shownCaretStyle == .blinkBar, "the bar the shell asked for, blinking again")
        #expect(try Self.caretBlinks(in: view))
    }

    @Test("a steady request from the shell stays steady across rest and wake")
    func steadyRequestStaysSteady() throws {
        let view = ShellTerminalView(frame: .zero)
        view.cursorStyleChanged(source: view.terminal, newStyle: .steadyUnderline)
        view.setCaretResting(true)
        #expect(view.shownCaretStyle == .steadyUnderline)
        view.setCaretResting(false)
        #expect(view.shownCaretStyle == .steadyUnderline)
        #expect(try !Self.caretBlinks(in: view))
    }

    @Test("setCaretResting is idempotent — a repeated rest does not capture its own wash as the active color")
    func restIsIdempotent() {
        let view = ShellTerminalView(frame: .zero)
        let activeColor = view.caretColor
        view.setCaretResting(true)
        view.setCaretResting(true)
        view.setCaretResting(false)
        #expect(view.caretColor == activeColor)
        #expect(view.shownCaretStyle == .blinkBlock)
    }
}
