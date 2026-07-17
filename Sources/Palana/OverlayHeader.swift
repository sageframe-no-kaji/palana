// The in-flow title bar shared by every summonable surface —
// ✕ on the left, surface title beside it. In-flow means it is the
// first element of the surface's VStack, so content starts below it
// with no overlap.

import SwiftUI

/// The quasi-title-bar row at the top of every summonable surface.
///
/// An HStack: `OverlayCloseButton` on the left (shown only when
/// `onClose` is supplied), the surface title beside it, then a spacer.
///
/// Usage:
/// ```swift
/// VStack(alignment: .leading, spacing: 14) {
///     OverlayHeader(title: "settings") { SettingsPanelController.shared.close() }
///     // ... content ...
/// }
/// ```
struct OverlayHeader: View {
    /// The surface's display title — shown at all times.
    let title: String
    /// Text scale — stepped panels pass their step's scale; others default to 1.
    var scale: Double = 1.0
    /// The close action — when non-nil the ✕ button is shown.
    var onClose: (() -> Void)?

    init(title: String, scale: Double = 1.0, onClose: (() -> Void)? = nil) {
        self.title = title
        self.scale = scale
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 8) {
            if let onClose {
                OverlayCloseButton(action: onClose)
            }
            Text(title)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Spacer()
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}
