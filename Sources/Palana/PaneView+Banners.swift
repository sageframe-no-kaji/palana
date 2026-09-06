// PaneView+Banners — the pane's quiet lines: the centered line an
// unpointed or loading pane shows, the error capsule that rides over a
// live table, and the notice bar at its foot. The error banner says a read failed and the pane stayed
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

    /// A typed address that landed somewhere other than as written.
    ///
    /// A bar across the foot of the table, in the accent rather than the
    /// alarm: the pane moved, and says where and why. It leaves on a
    /// click or after five seconds, whichever comes first.
    func noticeBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11))
            .foregroundStyle(Theme.ground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accent.opacity(0.92))
            .contentShape(Rectangle())
            .onTapGesture { model.dismissAddressNotice() }
            .task(id: text) {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                model.dismissAddressNotice()
            }
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
