// The app's appearance override (ho-15, ported from Sharibako).
//
// A pure UI preference — stored in UserDefaults via `@AppStorage`, read by both
// the window root's `.preferredColorScheme` and the Settings picker off one
// key. The enum and its `colorScheme` mapping live here, out of any SwiftUI
// view, so the mapping is unit-tested without a running scene and carries real
// coverage (the view is the excluded, headless-undrivable part).

import SwiftUI

/// How pālana chooses light or dark.
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the system appearance (no override).
    case system
    /// Force light appearance.
    case light
    /// Force dark appearance.
    case dark

    /// Stable identity for the SwiftUI picker.
    var id: String { rawValue }

    /// The label the Settings picker shows.
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// The `ColorScheme` this override resolves to, or `nil` for "follow the
    /// system" — the value handed to `.preferredColorScheme`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The UserDefaults key shared by the Settings picker and the window root's
    /// `.preferredColorScheme` reader, so both bind to one stored value.
    static let storageKey = "appearance"
}
