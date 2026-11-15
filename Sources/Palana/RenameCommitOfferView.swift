// The way past a destination with no hard links: what the rename
// commit risks, and the one click that runs it. Shown under a failed
// send-back's transcript while the offer stands.

import SwiftUI

/// The rename commit's explanation and its button.
struct RenameCommitOfferView: View {
    /// Runs the same send-back committed by rename.
    let accept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OperationModel.renameCommitExplanation)
                .foregroundStyle(Theme.inkFaint)
            Button(action: accept) {
                Text("Replace without the safe check")
                    .font(Theme.font(13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.alarm)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
    }
}
