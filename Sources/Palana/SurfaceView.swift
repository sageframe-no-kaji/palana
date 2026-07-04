// The window's content — two panes over a split, one footer line, the
// go-to sheet. The key monitor installs here and the session restore
// runs here, once, when the surface appears.

import PalanaCore
import SwiftUI

/// The Surface: dual panes, footer, go-to.
struct SurfaceView: View {
    /// The root object.
    @Bindable var session: PalanaSession

    var body: some View {
        panes
            .overlay {
                if session.helpVisible {
                    HelpOverlay()
                }
            }
            .sheet(item: $session.gotoTarget) { side in
                gotoBar(for: side)
            }
            .task {
                session.installKeyMonitor()
                await session.start()
            }
    }

    private var panes: some View {
        VStack(spacing: 0) {
            HSplitView {
                PaneView(
                    model: session.left,
                    isFocused: session.focusedSide == .left
                ) {
                    session.focusedSide = .left
                }
                .frame(minWidth: 320)
                PaneView(
                    model: session.right,
                    isFocused: session.focusedSide == .right
                ) {
                    session.focusedSide = .right
                }
                .frame(minWidth: 320)
            }
            Divider()
            footer
        }
        .background(Theme.ground)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text(entriesLine)
            if selectionCount > 0 {
                Text("\(selectionCount) selected")
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if !session.pendingPrefix.isEmpty {
                Text(session.pendingPrefix)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.accent)
            }
            Text(sortLine)
            Text("? keys")
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.inkFaint)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Theme.groundDeep)
    }

    private var entriesLine: String {
        "\(session.focusedPane.rows.count) entries"
    }

    private var selectionCount: Int {
        session.focusedPane.state.selection.count
    }

    private var sortLine: String {
        let sort = session.focusedPane.state.sort
        let arrow = sort.ascending ? "↑" : "↓"
        let hidden = session.focusedPane.state.showHidden ? " · hidden shown" : ""
        return "\(sort.key.rawValue) \(arrow)\(hidden)"
    }

    private func gotoBar(for side: SessionSnapshot.Side) -> some View {
        let pane = side == .left ? session.left : session.right
        return GoToBar(
            hosts: session.hosts,
            initialHost: pane.state.host,
            initialPath: pane.state.host == nil ? "/" : pane.state.path,
            onCommit: { host, path in session.point(side, host: host, path: path) },
            onCancel: { session.gotoTarget = nil })
    }
}

extension SessionSnapshot.Side: Identifiable {
    /// The raw name identifies the side for sheet presentation.
    public var id: String { rawValue }
}
