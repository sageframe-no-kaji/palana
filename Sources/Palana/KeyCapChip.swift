// A small key-cap chip — the visual treatment for key glyphs in hint lines.
// Rounded rect background, hairline stroke, mono glyph.
// Height is bounded so the chip never grows its parent row.

import SwiftUI

/// A single key styled as a key-cap chip.
///
/// Used in the plan panel's verb rail to mark each key visually. The chip
/// fits within the existing hint-line height — no padding or frame that
/// would push the row taller.
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

/// The persistent verb chip rail — always present in the plan panel header.
///
/// Layout: `<phase-hint-text> · esc hides · <verb chips> go again`, all on
/// one inline row. The chips carry `.fixedSize()` so the row's height is
/// governed by the surrounding text, not the chip rendering.
///
/// `enabled` controls interactivity. When `true` (idle, ready, finished,
/// failed, cancelled) the chips are clickable at full opacity. When `false`
/// (gathering, enacting, naming) the rail dims to ~0.35 and swallows hits —
/// the same safety story as the workbench strip's greying.
///
/// `hintText` is an optional phase-specific string rendered to the left of
/// the esc chip. The caller supplies the appropriate string per phase.
///
/// `onVerbKey` fires when a chip is clicked (enabled only), passing the key
/// string the physical key would produce. The caller (PlanPanel → PalanaSession)
/// routes it through the same dispatch path the keyboard uses.
struct VerbChipRow: View {
    /// The text size of the parent hint area.
    let fontSize: CGFloat
    /// Whether the chips are active (clickable, full opacity).
    ///
    /// `false` during gathering, enacting, and naming — the same phases the
    /// workbench greys.
    let enabled: Bool
    /// Optional phase-specific hint text rendered to the left of the esc chip.
    var hintText: String?
    /// Called when an enabled chip is clicked — the key string is the same
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
            if let hint = hintText {
                Text(hint)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.inkFaint)
                Text("·")
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.inkFaint)
            }
            // esc fires the hide path — same as the panel-priority esc handler.
            KeyCapChip(label: "esc", fontSize: fontSize, onTap: enabled ? { onVerbKey("esc") } : nil)
                .help(enabled ? "hide" : "hide (not available while running)")
            Text("hides")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            Text("·")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            ForEach(verbChips, id: \.key) { chip in
                KeyCapChip(label: chip.key, fontSize: fontSize, onTap: enabled ? { onVerbKey(chip.key) } : nil)
                    .help(enabled ? chip.tip : "\(chip.tip) (not available while running)")
            }
            Text("go again")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
        }
        .fixedSize()
        .opacity(enabled ? 1 : 0.35)
        .allowsHitTesting(enabled)
    }
}
