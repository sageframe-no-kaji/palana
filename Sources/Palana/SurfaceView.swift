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
            .overlay {
                if session.settingsVisible {
                    SettingsCard(model: session.settings, session: session)
                }
            }
            .overlay {
                if session.fieldVisible {
                    FieldOverlay(viewModel: session.fieldViewModel) { pointing in
                        session.point(
                            session.focusedSide,
                            host: pointing.host,
                            path: pointing.path)
                        session.fieldVisible = false
                    }
                }
            }
            .sheet(item: $session.gotoTarget) { side in
                gotoBar(for: side)
            }
            .onChange(of: session.floatingHelpTick) {
                // ? ? — the card trades itself for the panel that stays.
                KeysPanelController.shared.show()
            }
            .onChange(of: session.helpVisible) { _, visible in
                // Never both: help summons, the field, settings, and panel yield.
                if visible {
                    KeysPanelController.shared.close()
                    session.fieldVisible = false
                    session.settingsVisible = false
                }
            }
            .onChange(of: session.settingsVisible) { _, visible in
                // Settings card and help/field are mutually exclusive.
                if visible {
                    session.helpVisible = false
                    session.fieldVisible = false
                    session.settings.refreshConfigText()
                } else {
                    session.settings.clearNotice()
                    session.settingsFieldFocused = false
                }
            }
            .onChange(of: session.fieldVisible) { _, visible in
                // Field view and settings are mutually exclusive.
                if visible {
                    session.settingsVisible = false
                }
            }
            .task {
                session.installKeyMonitor()
                await session.start()
            }
    }

    private var panes: some View {
        VStack(spacing: 0) {
            VSplitView {
                paneArea
                    .frame(minHeight: 220)
                if session.operation.panelShowing {
                    PlanPanel(operation: session.operation, session: session)
                        .frame(minHeight: 130, idealHeight: 280)
                }
            }
            Divider()
            footer
        }
        .background(Theme.ground)
        .toolbar {
            // The titlebar's empty center — the one home that never
            // covers a pane and never drifts on resize (the seam
            // overlay managed both).
            ToolbarItem(placement: .principal) {
                paneVerbs
            }
            // pālana — its own platter, filled and stroked in the titlebar's
            // own color so the capsule vanishes into the bar and the name
            // reads as free text (its opaque fill still hides the OS glass).
            ToolbarItem(placement: .primaryAction) {
                nameMark
            }
            // The three glyphs in the swap cluster's groundDeep capsule.
            ToolbarItem(placement: .primaryAction) {
                glyphCluster
            }
        }
    }

    private var paneArea: some View {
        HSplitView {
            pane(session.left, side: .left)
            pane(session.right, side: .right)
        }
    }

    /// The pane verbs — mirror either way, swap both.
    private var paneVerbs: some View {
        HStack(spacing: 0) {
            paneVerb("arrow.left", help: "point left where right points") {
                session.mirror(to: .left)
            }
            .disabled(session.right.state.host == nil)
            paneVerb("arrow.left.arrow.right", help: "swap the panes") {
                session.swapPanes()
            }
            .disabled(session.left.state.host == nil || session.right.state.host == nil)
            paneVerb("arrow.right", help: "point right where left points") {
                session.mirror(to: .right)
            }
            .disabled(session.left.state.host == nil)
        }
        .background(Capsule().fill(Theme.groundDeep))
        .overlay(Capsule().stroke(Theme.inkFaint.opacity(0.25), lineWidth: 1))
    }

    /// pālana on its own platter, colored to vanish into the titlebar.
    ///
    /// The opaque capsule covers the toolbar's system glass (the swap cluster
    /// proves an opaque fill hides it); filled and stroked in the titlebar's
    /// own ground, the capsule itself disappears and the name reads as free
    /// text. Nudged a little left, a size larger than the glyphs.
    private var nameMark: some View {
        Text("पालन")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.ground))
            .overlay(Capsule().stroke(Theme.ground, lineWidth: 1))
            .padding(.trailing, 6)
            .help("pālana")
    }

    /// The three glyphs in the swap cluster's groundDeep capsule.
    ///
    /// A blended `Theme.ground` capsule sits underneath, sized past the bubble
    /// to cover the OS glass platter — the platter's white is hidden by the
    /// blended layer, and the groundDeep bubble floats on top of the bar.
    private var glyphCluster: some View {
        HStack(spacing: 0) {
            paneVerb("server.rack", help: "the host map — F") {
                HostMapPanelController.shared.toggle(
                    model: session.hostMapModel,
                    hosts: session.hosts
                )
            }
            paneVerb("gearshape", help: "settings — ⌘,") {
                session.helpVisible = false
                session.fieldVisible = false
                session.settingsVisible.toggle()
            }
            paneVerb("questionmark", help: "the keys — ? on the keyboard") {
                session.settingsVisible = false
                session.fieldVisible = false
                session.helpVisible.toggle()
            }
        }
        .background(Capsule().fill(Theme.groundDeep))
        .overlay(Capsule().stroke(Theme.inkFaint.opacity(0.25), lineWidth: 1))
        .padding(6)
        .background(Capsule().fill(Theme.ground))
    }

    private func paneVerb(
        _ systemName: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func pane(_ model: PaneModel, side: SessionSnapshot.Side) -> some View {
        PaneView(
            model: model,
            isFocused: session.focusedSide == side,
            hosts: session.hosts,
            onFocus: { session.focusedSide = side },
            onEditConfig: { session.editSSHConfig() },
            onReloadHosts: { session.reloadHosts() },
            onOperation: { operation in
                session.focusedSide = side
                session.beginOperation(operation)
            }
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
            if let sendLine = session.sendLine {
                Text(sendLine)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if session.operation.phase == .enacting, !session.operation.panelShowing {
                // The hidden terminal's heartbeat — the work continues.
                Text("transfer running — ` brings the panel back")
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
        .padding(.horizontal, 20)  // 20 clears the window's rounded corners (was 12)
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
