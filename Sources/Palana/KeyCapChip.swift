// A small key-cap chip — the visual treatment for key glyphs in transient
// hint lines. Rounded rect background, hairline stroke, mono glyph.
// Height is bounded so the chip never grows its parent row.

import SwiftUI

/// A single key styled as a key-cap chip.
///
/// Used in the plan panel's finished/failed/cancelled hint line to mark
/// each verb key visually. The chip fits within the existing hint-line
/// height — no padding or frame that would push the row taller.
struct KeyCapChip: View {
    /// The key label — one glyph or one short word.
    let label: String
    /// The text size of the surrounding hint line.
    let fontSize: CGFloat

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.groundDeep)
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
struct GoAgainHintLine: View {
    /// The text size of the parent hint line.
    let fontSize: CGFloat

    /// The verb keys in the go-again set, in display order.
    private let keys = ["y", "m", "r", "R", "a", "t", "T"]

    var body: some View {
        HStack(spacing: 4) {
            KeyCapChip(label: "esc", fontSize: fontSize)
            Text("hides")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            Text("·")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
            ForEach(keys, id: \.self) { key in
                KeyCapChip(label: key, fontSize: fontSize)
            }
            Text("go again")
                .font(.system(size: fontSize))
                .foregroundStyle(Theme.inkFaint)
        }
        .fixedSize()
    }
}
