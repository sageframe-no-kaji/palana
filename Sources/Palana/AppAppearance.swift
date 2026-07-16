// The app's appearance override (ho-15, ported from Sharibako).
//
// A pure UI preference — stored in UserDefaults via `@AppStorage`, read by both
// the window root's `.preferredColorScheme` and the Settings picker off one
// key. The enum and its `colorScheme` mapping live here, out of any SwiftUI
// view, so the mapping is unit-tested without a running scene and carries real
// coverage (the view is the excluded, headless-undrivable part).

import AppKit
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

    /// The `NSAppearance` this override resolves to, or `nil` for "follow the
    /// system" — set on `NSApp` so the floating AppKit panels (keys, host map,
    /// zfs, favorites) obey the override too, not just the SwiftUI main window
    /// (his review: the cards weren't respecting light/dark).
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// The currently-stored override, read straight from UserDefaults — for the
    /// non-SwiftUI code (the app delegate, the panel controllers) that can't
    /// hold an `@AppStorage`.
    static var current: Self {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(Self.init(rawValue:)) ?? .system
    }

    /// The UserDefaults key shared by the Settings picker, the window root's
    /// `.preferredColorScheme`, and `NSApp.appearance`, so all bind one value.
    static let storageKey = "appearance"
}
