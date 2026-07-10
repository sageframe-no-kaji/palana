// A small key-cap chip — the visual treatment for key glyphs in transient
// hint lines. Rounded rect background, hairline stroke, mono glyph.
// Height is bounded so the chip never grows its parent row.

import SwiftUI

/// A single key styled as a key-cap chip.
///
/// Used in the plan panel's finished/failed/cancelled hint line to mark
/// each verb key visually. The chip fits within the existing hint-line
/// height — no padding or frame that would push the row taller.
///
/// When `onTap` is non-nil the chip renders as a `Button` — clicking it
/// fires the same action the physical key would. Hover slightly lightens
/// the background to signal interactivity, matching `ToolbarGlyphButton`.
struct KeyCapChip: View {
    /// The key label — one glyph or one short word.
    let label: String
    /// The text size of the surrounding hint line.
    let fontSize: CGFloat
    /// Called when the chip is clicked — nil for non-interactive chips.
    var onTap: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        if let onTap {
            Button(action: onTap) { chip }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
        } else {
            chip
        }
    }

    /// The visual chip — shared between interactive and display-only forms.
    private var chip: some View {
        Text(label)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(hovering ? Theme.groundDeep.opacity(0.7) : Theme.groundDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.inkFaint.opacity(0.4), lineWidth: 0.5)
                    )
            )
    }
}

/// The finished/failed/cancelled hint line — verb keys as chips, connective
/// words as plain text.
///
/// Layout: `esc hides · <chips> go again`, all on one inline row.
/// The chips carry `.fixedSize()` so the row's height is governed by the
/// surrounding text, not the chip rendering.
///
/// `onVerbKey` fires when a chip is clicked, passing the key string the
/// physical key would produce. The caller (PlanPanel → PalanaSession) routes
/// it to the same dispatch path the keyboard uses.
struct GoAgainHintLine: View {
    /// The text size of the parent hint line.
    let fontSize: CGFloat
    /// Called when a chip is clicked — the key string passed is the same
    /// token the keyboard grammar would produce for that key.
    var onVerbKey: (String) -> Void = { _ in }

    /// Verb chips with their tooltips, in display order.
    private let verbChips: [(key: String, tip: String)] = [
        ("y", "copy again"),
        ("m", "move again"),
        ("r", "remove"),
        ("R", "rename"),
        ("a", "create"),
        ("t", "touch"),
        ("T", "touch new"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            // esc fires the hide path — same as the panel-priority esc handler.
            KeyCapChip(label: "esc", fontSize: fontSize) { onVerbKey("esc") }
                .help("hide")
            Text("hides")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            Text("·")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            ForEach(verbChips, id: \.key) { chip in
                KeyCapChip(label: chip.key, fontSize: fontSize) { onVerbKey(chip.key) }
                    .help(chip.tip)
            }
            Text("go again")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
        }
        .fixedSize()
    }
}
