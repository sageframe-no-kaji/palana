// A single, consistent close control for every summonable surface.
// Upper-left placement, calm at rest, unmistakably red on hover —
// mirrors the macOS traffic-light red gesture without the full trio.
// Esc continues to close each surface independently; this is an addition.

import SwiftUI

/// The subtle ✕ that sits upper-left on every summonable surface.
///
/// At rest: `Theme.alarm` at low opacity. On hover: full `Theme.alarm`,
/// ✕ clearly visible. Takes an `action` closure so each caller wires
/// it to the surface's existing close path.
struct OverlayCloseButton: View {
    /// The close action — callers wire this to their existing dismiss path.
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        hovering
                            ? Theme.alarm
                            : Theme.alarm.opacity(0.25)
                    )
                    .frame(width: 17, height: 17)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(
                        hovering
                            ? Color.white
                            : Theme.alarm.opacity(0.6)
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("close")
    }
}
