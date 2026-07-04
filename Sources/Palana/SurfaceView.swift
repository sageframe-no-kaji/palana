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
                pane(session.left, side: .left)
                pane(session.right, side: .right)
            }
            .overlay {
                if session.showsSendArrow {
                    sendArrow
                }
            }
            if session.operation.active {
                Divider()
                PlanPanel(operation: session.operation)
                    .frame(minHeight: 160, idealHeight: 280, maxHeight: 320)
            }
            Divider()
            footer
        }
        .background(Theme.ground)
    }

    /// The send direction, visible before any verb goes down — the
    /// subjects would travel from the focused pane toward the other.
    private var sendArrow: some View {
        Image(systemName: session.focusedSide == .left ? "arrow.right" : "arrow.left")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent.opacity(0.85))
            .padding(7)
            .background(Circle().fill(Theme.groundDeep))
            .overlay(Circle().stroke(Theme.accent.opacity(0.25), lineWidth: 1))
            .allowsHitTesting(false)
    }

    private func pane(_ model: PaneModel, side: SessionSnapshot.Side) -> some View {
        PaneView(
            model: model,
            isFocused: session.focusedSide == side,
            hosts: session.hosts,
            onFocus: { session.focusedSide = side },
            onEditConfig: { session.editSSHConfig() },
            onReloadHosts: { session.reloadHosts() }
        )
        .frame(minWidth: 320)
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
