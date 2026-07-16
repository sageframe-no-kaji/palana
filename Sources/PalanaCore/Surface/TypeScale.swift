// TypeScale — the pure arithmetic of the surface's text zoom (ho-13).
//
// Lives in PalanaCore so the whole of the scale story — the multiply, the
// clamp, the step, the default — is verified in PalanaCoreTests without a
// running scene. The app's `TextScale` observable holds the live factor and
// persists it; this enum owns only the math, so `Theme.font(_:)` and the tests
// read one source of truth for what a scale means.

import Foundation

/// The pure math of the universal text-scale factor.
///
/// A single `factor` multiplies every font size on the surface so the whole
/// thing zooms coherently (design system §3 — "thread a single scale factor
/// rather than hard-coding sizes"). This enum is the contract: the legible
/// range, the step, the reset default, and the two pure operations the app and
/// the tests both call.
public enum TypeScale {
    /// The legible bounds for the factor — a tight range so the design system's
    /// 10–14pt world stays coherent (ho-13 Decision 3).
    public static let range: ClosedRange<Double> = 0.8...1.6

    /// One ⌘+ / ⌘− nudge.
    public static let step: Double = 0.1

    /// The reset value — what ⌘0 restores and a fresh install starts at.
    public static let defaultScale: Double = 1.0

    /// Pins a factor into the legible range.
    ///
    /// Applied on every mutation and on read of a persisted value, so a
    /// corrupt or out-of-range stored factor can never zoom the surface past
    /// legibility (the ho-9 keys-panel law: persisted state that misbehaves
    /// must never misbehave twice).
    public static func clamped(_ factor: Double) -> Double {
        // NaN survives min/max, so name it and fall back to the default.
        guard factor.isFinite else { return defaultScale }
        return min(max(factor, range.lowerBound), range.upperBound)
    }

    /// The factor after a step of `delta`, clamped back into range.
    public static func stepped(_ factor: Double, by delta: Double) -> Double {
        clamped(factor + delta)
    }

    /// A base point size multiplied by the factor — the one place `size * scale`
    /// is computed, so no view spells the multiply itself.
    public static func scaled(_ size: Double, by factor: Double) -> Double {
        size * factor
    }
}
