// PaneView+Banners — the pane's quiet lines: the centered line an
// unpointed or loading pane shows, and the two capsules that ride over a
// live table. The error banner says a read failed and the pane stayed
// put; the notice banner says a typed address landed somewhere other
// than as written — the correction, in the accent rather than the alarm,
// until the next pointing. Split from PaneView.swift for the file-length
// budget, the same move as PaneView+Preview and PaneView+ZFSMode.

import SwiftUI

extension PaneView {
    /// A failed read over a live listing — say it, stay put.
    func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11))
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.82), in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }

    /// A typed address that landed somewhere other than as written — the
    /// correction stays visible until the next pointing, in the accent
    /// rather than the alarm: the pane moved, and says where and why.
    func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11))
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.accent.opacity(0.9), in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }

    func quietLine(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
