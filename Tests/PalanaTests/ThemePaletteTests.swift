// ThemePaletteTests — the appearance-aware palette seam (ho-15).
//
// Every token carries a light and a dark value and resolves between them
// through the pure `Palette.resolved(dark:)`, so the whole palette is pinned
// here without a running scene — the file that makes dark mode "a port, not a
// design gamble" checkable. Light is design system §2; dark is the Sharibako
// port (ho-15 Decision 2). If a value drifts, a test fails, not a screen.

import SwiftUI
import Testing

@testable import Palana

@Suite("Theme palette — light and dark, pinned")
struct ThemePaletteTests {
    @Test("resolved picks light or dark by the flag")
    func resolvedPicksByFlag() {
        let palette = Palette(
            light: RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1),
            dark: RGBA(red: 0.7, green: 0.8, blue: 0.9, alpha: 1))
        #expect(palette.resolved(dark: false) == palette.light)
        #expect(palette.resolved(dark: true) == palette.dark)
    }

    @Test("ground — warm paper light, warm near-black dark")
    func ground() {
        #expect(Theme.Token.ground.light == RGBA(red: 0.9804, green: 0.9686, blue: 0.9529, alpha: 1))
        #expect(Theme.Token.ground.dark == RGBA(red: 0.1059, green: 0.1020, blue: 0.0902, alpha: 1))
    }

    @Test("groundDeep — a shade off ground, both ways")
    func groundDeep() {
        #expect(
            Theme.Token.groundDeep.light == RGBA(red: 0.9569, green: 0.9451, blue: 0.9176, alpha: 1))
        #expect(
            Theme.Token.groundDeep.dark == RGBA(red: 0.1412, green: 0.1333, blue: 0.1176, alpha: 1))
    }

    @Test("ink — near-black light, warm off-white dark; never pure")
    func ink() {
        #expect(Theme.Token.ink.light == RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 1))
        #expect(Theme.Token.ink.dark == RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 1))
        // Never pure black or white — the notebook register (design system §2).
        #expect(Theme.Token.ink.light.red > 0)
        #expect(Theme.Token.ink.dark.red < 1)
    }

    @Test("inkFaint — ink at reduced alpha, a touch more present in dark")
    func inkFaint() {
        #expect(
            Theme.Token.inkFaint.light == RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 0.55))
        #expect(
            Theme.Token.inkFaint.dark == RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 0.60))
    }

    @Test("accent — quiet moss, lifted in dark")
    func accent() {
        #expect(Theme.Token.accent.light == RGBA(red: 0.3529, green: 0.4588, blue: 0.3216, alpha: 1))
        #expect(Theme.Token.accent.dark == RGBA(red: 0.4941, green: 0.6078, blue: 0.4471, alpha: 1))
    }

    @Test("panelGround — the cooler data surface")
    func panelGround() {
        #expect(
            Theme.Token.panelGround.light
                == RGBA(red: 0.9294, green: 0.9333, blue: 0.9451, alpha: 1))
        #expect(
            Theme.Token.panelGround.dark
                == RGBA(red: 0.1255, green: 0.1333, blue: 0.1647, alpha: 1))
    }

    @Test("alarm — quiet rust, lifted in dark")
    func alarm() {
        #expect(Theme.Token.alarm.light == RGBA(red: 0.5961, green: 0.3020, blue: 0.2353, alpha: 1))
        #expect(Theme.Token.alarm.dark == RGBA(red: 0.7725, green: 0.4196, blue: 0.3412, alpha: 1))
    }

    @Test("plugin — burnt umber, dark derived distinct from the lifted moss")
    func plugin() {
        #expect(Theme.Token.plugin.light == RGBA(red: 0.58, green: 0.36, blue: 0.18, alpha: 1))
        #expect(Theme.Token.plugin.dark == RGBA(red: 0.75, green: 0.54, blue: 0.32, alpha: 1))
        // Umber stays red-dominant and warm — not the green-dominant moss.
        let umber = Theme.Token.plugin.dark
        let moss = Theme.Token.accent.dark
        #expect(umber.red > umber.green && umber.green > umber.blue)
        #expect(moss.green > moss.red)
    }

    @Test("every token's dark differs from its light — the flip is real")
    func darkAlwaysDiffers() {
        let tokens = [
            Theme.Token.ground, Theme.Token.groundDeep, Theme.Token.ink, Theme.Token.inkFaint,
            Theme.Token.accent, Theme.Token.panelGround, Theme.Token.alarm, Theme.Token.plugin,
        ]
        for token in tokens {
            #expect(token.light != token.dark)
        }
    }
}

@Suite("AppAppearance — the light/dark/system mapping")
struct AppAppearanceTests {
    @Test("colorScheme maps each case; system is nil (follow the OS)")
    func colorSchemeMapping() {
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
    }

    @Test("raw values are stable — the persisted key round-trips")
    func rawValuesStable() {
        #expect(AppAppearance(rawValue: "system") == .system)
        #expect(AppAppearance(rawValue: "light") == .light)
        #expect(AppAppearance(rawValue: "dark") == .dark)
        #expect(AppAppearance(rawValue: "nonsense") == nil)
    }

    @Test("all three cases are offered, each with a label and stable id")
    func allCasesLabelled() {
        #expect(AppAppearance.allCases == [.system, .light, .dark])
        #expect(AppAppearance.system.label == "System")
        #expect(AppAppearance.light.label == "Light")
        #expect(AppAppearance.dark.label == "Dark")
        #expect(AppAppearance.dark.id == "dark")
    }
}
