// TextScale — the app-scope holder of the live text-zoom factor (ho-13).
//
// The one @Observable authority for how large the surface's type is. ⌘+ / ⌘− /
// ⌘0 mutate it; `Theme.font(_:)` reads it; every view that draws through the
// factory becomes a dependency and re-renders when it changes. The factor
// persists across launches under the "fontScale" default and clamps on read —
// a corrupt value zooms nothing past legibility (the ho-9 keys-panel law). The
// pure math lives in PalanaCore's `TypeScale`; this class only holds, persists,
// and publishes.

import Foundation
import Observation
import PalanaCore

/// The live, persisted text-scale factor for the whole surface.
@MainActor
@Observable
final class TextScale {
    /// The single instance — `Theme.font(_:)` and the ⌘ handlers talk to this.
    static let shared = TextScale()

    /// The UserDefaults key — the same store `@AppStorage("fontScale")` would use.
    static let storageKey = "fontScale"

    /// The current multiplier, always inside `TypeScale.range`.
    private(set) var factor: Double

    /// Restores the persisted factor, clamped, or the default on a fresh install.
    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.storageKey) == nil {
            factor = TypeScale.defaultScale
        } else {
            factor = TypeScale.clamped(defaults.double(forKey: Self.storageKey))
        }
    }

    /// One step larger — ⌘+ / ⌘=.
    func stepUp() { set(TypeScale.stepped(factor, by: TypeScale.step)) }

    /// One step smaller — ⌘−.
    func stepDown() { set(TypeScale.stepped(factor, by: -TypeScale.step)) }

    /// Back to 1.0 — ⌘0, the escape hatch.
    func reset() { set(TypeScale.defaultScale) }

    /// Clamps, publishes, and persists — the one mutation path.
    private func set(_ newValue: Double) {
        let clamped = TypeScale.clamped(newValue)
        guard clamped != factor else { return }
        factor = clamped
        UserDefaults.standard.set(clamped, forKey: Self.storageKey)
    }
}
