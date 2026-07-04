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
}
