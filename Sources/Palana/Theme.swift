// The notebook palette, in placeholder values — warm quiet ground,
// near-black ink, one interactive accent. The hands session prunes
// these; a design-polish ho follows if the gap demands one. Monospace
// appears nowhere in this file on purpose: it is reserved for ho-08's
// plan panel.

import SwiftUI

/// The surface's colors — two or three, per the design language.
enum Theme {
    /// The ground every view sits on — warm paper, not white.
    static let ground = Color(red: 0.979, green: 0.970, blue: 0.951)

    /// A slightly deeper ground for headers and the footer.
    static let groundDeep = Color(red: 0.955, green: 0.943, blue: 0.918)

    /// The ink — near-black, never pure black.
    static let ink = Color(red: 0.114, green: 0.106, blue: 0.094)

    /// Receded ink for secondary facts — paths, dates, counts.
    static let inkFaint = Color(red: 0.114, green: 0.106, blue: 0.094).opacity(0.55)

    /// The one interactive accent — quiet moss.
    ///
    /// Cursor row, selection marks, the focused pane's indicator.
    static let accent = Color(red: 0.353, green: 0.459, blue: 0.322)

    /// The plan panel's ground — the notebook gone a shade cooler.
    ///
    /// A very subtle slate over the deep ground (second hands session:
    /// "maybe a VERY subtle slate blue. like 5%").
    static let panelGround = Color(red: 0.929, green: 0.933, blue: 0.943)

    /// Failure ink — quiet rust, the panel's only other voice.
    ///
    /// Reserved for typed failures and incomplete-size floors; a
    /// placeholder value like the rest, pruned by the hands sessions.
    static let alarm = Color(red: 0.596, green: 0.302, blue: 0.235)

    /// The plugin category tint — muted ochre/amber beside the moss accent.
    ///
    /// Distinguishes the plugins column and its chips from system reads
    /// without competing with accent or alarm; same saturation family.
    static let plugin = Color(red: 0.62, green: 0.48, blue: 0.22)
}
