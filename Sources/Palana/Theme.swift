// The notebook palette — warm quiet ground, near-black ink, one moss accent,
// one rust alarm. Every token is now appearance-aware (ho-15): a light value
// (design system §2, authoritative) and a warm-dark sibling ported from
// Sharibako, which built dark mode for this exact design system first. The
// dark half stays warm — never pure black or white — so the notebook voice
// survives the flip.
//
// The port is Sharibako's RGBA / Palette / dynamic-NSColor pattern: each token
// carries both values and resolves between them with no asset catalog. The
// pure `resolved(dark:)` seam is unit-tested per token, so the palette carries
// real coverage and is not the excluded, headless-undrivable part (only the
// declarative `View` bodies are).
//
// Views still read `Theme.ground`, `Theme.accent`, etc. as `Color` exactly as
// before — those accessors now resolve through the palette. The light/dark
// truth lives on `Theme.Token.*`, which the tests pin.

import AppKit
import PalanaCore
import SwiftUI

/// A single sRGB color with alpha, as plain `Double` components.
///
/// `Sendable` by construction (all `Double`), so the dynamic-`NSColor`
/// provider closure can capture it without crossing a concurrency boundary
/// with a non-`Sendable` `NSColor`.
struct RGBA: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// The concrete `NSColor` for these components, in the sRGB space.
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// This color laid over an opaque `ground` — plain source-over, the same
    /// arithmetic the compositor does when a translucent wash sits on a pane.
    ///
    /// The pure seam for the pane-shade tokens: the tests read the composite
    /// through here so "the inactive pane is darker" is a checked number, not
    /// a screenshot.
    func over(_ ground: Self) -> Self {
        Self(
            red: red * alpha + ground.red * (1 - alpha),
            green: green * alpha + ground.green * (1 - alpha),
            blue: blue * alpha + ground.blue * (1 - alpha),
            alpha: 1)
    }

    /// Relative luminance (WCAG 2, sRGB linearised) — 0 is black, 1 is white.
    ///
    /// The one number "darker than" is measured on; alpha is ignored, so
    /// composite first (`over(_:)`) when the color is a wash.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// A token's light and dark values, and the machinery to resolve between them.
struct Palette: Sendable, Equatable {
    /// The value in light appearance (design system §2).
    let light: RGBA
    /// The value in dark appearance (ho-15, ported from Sharibako).
    let dark: RGBA

    /// The raw components for a given appearance — the pure, tested seam both
    /// the dynamic color and the tests read, so neither drifts from the other.
    func resolved(dark isDark: Bool) -> RGBA {
        isDark ? dark : light
    }

    /// An appearance-aware `NSColor` that re-resolves on appearance change.
    ///
    /// No asset catalog — the dynamic provider re-runs whenever the effective
    /// appearance flips; the closure captures only the `Sendable` `self`.
    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return resolved(dark: isDark).nsColor
        }
    }

    /// The SwiftUI `Color` the views consume.
    var color: Color {
        Color(nsColor: nsColor)
    }
}

/// The surface's colors — appearance-aware tokens, per the design language.
enum Theme {
    // Each token is resolved ONCE into a `Color` that wraps a *dynamic*
    // `NSColor` — so it stays appearance-aware (re-resolving on the light/dark
    // flip) while costing nothing per access. Computed accessors here allocated
    // a fresh dynamic `NSColor` on every read, which the Table's per-cell color
    // reads turned into a navigation stutter (ho-13/15 review). `let`, not
    // `var`, is the fix.

    /// The ground every view sits on — warm paper, never white.
    static let ground: Color = Token.ground.color

    /// A slightly deeper ground for headers and the footer.
    static let groundDeep: Color = Token.groundDeep.color

    /// The ink — near-black light, warm off-white dark; never pure.
    static let ink: Color = Token.ink.color

    /// Receded ink for secondary facts — paths, dates, counts.
    static let inkFaint: Color = Token.inkFaint.color

    /// The one interactive accent — quiet moss.
    ///
    /// Cursor row, selection marks, the focused pane's indicator.
    static let accent: Color = Token.accent.color

    /// The plan panel's ground — the notebook gone a shade cooler.
    static let panelGround: Color = Token.panelGround.color

    /// Failure ink — quiet rust, the panel's only other voice.
    static let alarm: Color = Token.alarm.color

    /// The plugin category tint — burnt umber beside the moss accent.
    static let plugin: Color = Token.plugin.color

    /// The wash over the pane the keyboard is not in — a translucent shade
    /// that darkens header, rows, and foot together so the live pane is the
    /// brighter of the two.
    static let paneShade: Color = Token.paneShade.color

    /// The hairline around the pane the keyboard is in — the accent at low
    /// alpha, one point, drawn inside the pane's bounds.
    static let paneEdge: Color = Token.paneEdge.color

    /// The light/dark values per token — the pure, unit-tested seam.
    ///
    /// Light is design system §2 (authoritative); dark is the Sharibako port
    /// (ho-15 Decision 2). `plugin` is pālana-specific — Sharibako has no
    /// umber — so its dark is derived by the same "lift toward warm + bright"
    /// ratio the accent and alarm pairs show, and reads distinct from the
    /// lifted moss.
    enum Token {
        static let ground = Palette(
            light: RGBA(red: 0.9804, green: 0.9686, blue: 0.9529, alpha: 1),
            dark: RGBA(red: 0.1059, green: 0.1020, blue: 0.0902, alpha: 1))

        static let groundDeep = Palette(
            light: RGBA(red: 0.9569, green: 0.9451, blue: 0.9176, alpha: 1),
            dark: RGBA(red: 0.1412, green: 0.1333, blue: 0.1176, alpha: 1))

        static let ink = Palette(
            light: RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 1),
            dark: RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 1))

        static let inkFaint = Palette(
            light: RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 0.55),
            dark: RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 0.60))

        static let accent = Palette(
            light: RGBA(red: 0.3529, green: 0.4588, blue: 0.3216, alpha: 1),
            dark: RGBA(red: 0.4941, green: 0.6078, blue: 0.4471, alpha: 1))

        static let panelGround = Palette(
            light: RGBA(red: 0.9294, green: 0.9333, blue: 0.9451, alpha: 1),
            dark: RGBA(red: 0.1255, green: 0.1333, blue: 0.1647, alpha: 1))

        static let alarm = Palette(
            light: RGBA(red: 0.5961, green: 0.3020, blue: 0.2353, alpha: 1),
            dark: RGBA(red: 0.7725, green: 0.4196, blue: 0.3412, alpha: 1))

        static let plugin = Palette(
            light: RGBA(red: 0.58, green: 0.36, blue: 0.18, alpha: 1),
            dark: RGBA(red: 0.75, green: 0.54, blue: 0.32, alpha: 1))

        /// The inactive pane's shade.
        ///
        /// Hands session, 2026-09-07: "make the non active pane darker
        /// still". Light is the ink hue at 0.09 — double the 0.045 wash it
        /// replaces. Dark is black at 0.30: the
        /// ink there is off-white, and washing with it *lightened* the
        /// inactive pane; a black wash scales the warm ground toward black
        /// and keeps its hue, so the inactive pane recedes in both
        /// appearances. No new hue — the composite is pinned in the tests.
        static let paneShade = Palette(
            light: RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 0.09),
            dark: RGBA(red: 0, green: 0, blue: 0, alpha: 0.30))

        /// The active pane's hairline.
        ///
        /// The accent's own RGB at 0.40 in both appearances — low enough to
        /// read as a line, not a frame.
        static let paneEdge = Palette(
            light: RGBA(red: 0.3529, green: 0.4588, blue: 0.3216, alpha: 0.40),
            dark: RGBA(red: 0.4941, green: 0.6078, blue: 0.4471, alpha: 0.40))
    }
}

extension Theme {
    /// The one font factory the whole in-window surface draws through.
    ///
    /// ⌘+ / ⌘− / ⌘0 zoom every chip, footer, path, row, and panel by the one
    /// persisted factor (ho-13; design system §3 — "thread a single scale
    /// factor rather than hard-coding sizes"). `size` is the design-system
    /// point size; the multiply is `TypeScale`'s pure math over the live
    /// factor.
    ///
    /// Reading `TextScale.shared.factor` (an `@Observable` property) inside a
    /// view's body registers that view as a dependency of the factor, so the
    /// surface re-renders live on every zoom — no threading a scale param
    /// through the tree.
    ///
    /// The floating AppKit panels (the keys panel, the zfs and host-map
    /// overlays) keep their own stepped `* scale` sizing and deliberately do
    /// NOT route here — ⌘+ must never double-scale a window that resizes
    /// itself. SwiftTerm's terminal font is likewise its own path (ho-13
    /// out-of-scope).
    @MainActor
    static func font(
        _ size: Double,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(
            size: TypeScale.scaled(size, by: TextScale.shared.factor),
            weight: weight,
            design: design)
    }
}
