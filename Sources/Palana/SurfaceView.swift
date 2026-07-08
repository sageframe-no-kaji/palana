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
            // The trailing cluster — the name and the three glyphs in one
            // bubble wearing the center swap cluster's groundDeep capsule.
            // The opaque fill overrides the toolbar's own system glass.
            ToolbarItem(placement: .primaryAction) {
                trailingCluster
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

    /// The trailing cluster — the name, then the glyphs in a capsule.
    ///
    /// pālana stands free to the left in its own script; the three glyphs
    /// wear the swap cluster's groundDeep capsule. It is one toolbar item so
    /// macOS adds no grouping glass — the name wears no bubble.
    private var trailingCluster: some View {
        HStack(spacing: 12) {
            Text("पालन")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.inkFaint)
                .help("pālana")
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
        }
        // Nudge the cluster left off the window's rounded corner, its right
        // edge landing near the footer text's own inset.
        .padding(.trailing, 8)
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
