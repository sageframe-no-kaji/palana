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
    /// The ground every view sits on — warm paper, never white.
    static var ground: Color { Token.ground.color }

    /// A slightly deeper ground for headers and the footer.
    static var groundDeep: Color { Token.groundDeep.color }

    /// The ink — near-black light, warm off-white dark; never pure.
    static var ink: Color { Token.ink.color }

    /// Receded ink for secondary facts — paths, dates, counts.
    static var inkFaint: Color { Token.inkFaint.color }

    /// The one interactive accent — quiet moss.
    ///
    /// Cursor row, selection marks, the focused pane's indicator.
    static var accent: Color { Token.accent.color }

    /// The plan panel's ground — the notebook gone a shade cooler.
    static var panelGround: Color { Token.panelGround.color }

    /// Failure ink — quiet rust, the panel's only other voice.
    static var alarm: Color { Token.alarm.color }

    /// The plugin category tint — burnt umber beside the moss accent.
    static var plugin: Color { Token.plugin.color }

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
