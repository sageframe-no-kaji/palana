// The floating favorites column panel — AppKit-owned, borderless, on the
// HostMapPanel lineage. The panel shows favorites organized by machine with
// chevron-disclosure groups. * and the star glyph toggle from the session.
// The panel floats independently — field, help, and settings never close it.
// Same law as HostMapPanel: content ground fills the frame to its rounded
// edge so no band can appear between card and window.

import AppKit
import PalanaCore
import SwiftUI

// MARK: - FavoritesJumpTarget

/// Which pane(s) a favorite jump lands in.
enum FavoritesJumpTarget: Equatable {
    /// The left pane only.
    case left
    /// The right pane only.
    case right
    /// Both panes at once.
    case both
}

// MARK: - FavoritesPanelModel

/// The favorites panel's fold-state model.
///
/// Thin `@Observable` wrapper over the set of collapsed group keys. The
/// session owns one instance; the panel reads it. The favorites list itself
/// is read live from `FavoritesModel` — this model holds only UI state.
@MainActor
@Observable
final class FavoritesPanelModel {
    /// The group keys the operator has closed.
    ///
    /// Empty by default — all sections arrive visible so a newly starred
    /// host's group is open on first sight.
    private(set) var collapsed: Set<String> = []

    /// The keyboard cursor's stable id — `"hdr:<groupKey>"` or `"fav:<id>"`.
    ///
    /// `nil` until the operator first uses keyboard nav; the session
    /// clamps it to the first row on first use. Survives list changes
    /// by id — the session re-resolves the index each keypress.
    var cursor: String?

    /// Where a jump lands — the arrow cluster selects it, the panel shows it.
    ///
    /// Defaults to the focused pane's side when the column opens (the session
    /// sets it); the operator can then click for the other pane or for both.
    var jumpTarget: FavoritesJumpTarget = .left

    /// The favorite id whose inline name field is open, or nil when none is.
    ///
    /// One field at a time — `r`, the second click, and the row menu all set
    /// this. While it is non-nil the panel's letter grammar stands down so the
    /// operator's typing reaches the field.
    private(set) var editingID: String?

    /// Opens the inline name field on the given favorite, moving the cursor there.
    func beginEditing(id: String) {
        cursor = "fav:\(id)"
        editingID = id
    }

    /// Closes the inline name field without committing.
    func cancelEditing() {
        editingID = nil
    }

    /// Toggles the collapsed state of the given group key.
    ///
    /// A key absent from `collapsed` is added (section closes); a key present
    /// is removed (section opens).
    func toggle(key: String) {
        if collapsed.contains(key) {
            collapsed.remove(key)
        } else {
            collapsed.insert(key)
        }
    }

    /// Removes a key from the collapsed set (expands that group).
    func expand(key: String) {
        collapsed.remove(key)
    }

    /// Inserts a key into the collapsed set (collapses that group).
    func collapse(key: String) {
        collapsed.insert(key)
    }
}

// MARK: - FavoritesPanelActions

/// The panel's outward operations, handed in when it opens.
///
/// Carried as one value so the panel's door stays a three-argument call as
/// the row's vocabulary grows. Every one of these is an existing session
/// operation — the panel is glue, never a second implementation.
struct FavoritesPanelActions {
    /// Jump to a favorite (host, path).
    let jump: (String, String) -> Void
    /// Remove a favorite by id.
    let unstar: (String) -> Void
    /// Flip a favorite's scope.
    let setScope: (String, FavoriteScope) -> Void
    /// Commit a name field (id, label — nil clears the label).
    let setLabel: (String, String?) -> Void
}

// MARK: - FavoritesPanelController

/// Owns the one floating favorites column panel.
@MainActor
final class FavoritesPanelController: NSObject, NSWindowDelegate {
    /// The single instance — the surface talks to this.
    static let shared = FavoritesPanelController()

    /// The name the key monitor recognizes.
    static let identifier = "palana-favorites-window"

    private var panel: NSPanel?

    /// True while the panel is up — the surface's Esc reaches for an open
    /// glance panel even when the main window holds the keyboard.
    var isOpen: Bool { panel != nil }

    /// Shows the panel.
    ///
    /// If the panel is already up, brings it to front without rebuilding.
    func show(
        favoritesModel: FavoritesModel,
        panelModel: FavoritesPanelModel,
        actions: FavoritesPanelActions
    ) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        // A field left open when the panel last closed does not reopen with it.
        panelModel.cancelEditing()
        let made = FavoritesFloatingPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 300, height: 480)),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        made.identifier = NSUserInterfaceItemIdentifier(Self.identifier)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hasShadow = true
        made.level = .floating
        made.isMovableByWindowBackground = true
        // Fullscreen-auxiliary keeps the panel reachable over a fullscreen main
        // window; it no longer joins all Spaces, so it stays on the desktop it
        // was summoned on instead of following across every one (his ask).
        made.collectionBehavior = [.fullScreenAuxiliary]
        made.minSize = CGSize(width: 240, height: 200)
        made.contentView = NSHostingView(
            rootView: FavoritesContent(
                favoritesModel: favoritesModel,
                panelModel: panelModel,
                actions: actions))
        made.delegate = self
        made.center()
        made.setFrameAutosaveName("palana-favorites-frame")
        panel = made
        made.makeKeyAndOrderFront(nil)
    }

    /// Toggles the panel — closes when up, opens when not.
    func toggle(
        favoritesModel: FavoritesModel,
        panelModel: FavoritesPanelModel,
        actions: FavoritesPanelActions
    ) {
        if panel != nil {
            close()
        } else {
            show(favoritesModel: favoritesModel, panelModel: panelModel, actions: actions)
        }
    }

    /// Closes the panel if it is up.
    func close() {
        panel?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        panel = nil
    }
}

/// A borderless panel that can still take the keyboard.
private final class FavoritesFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - FavoritesContent

/// The panel's face — ground fills the frame to the rounded edge.
struct FavoritesContent: View {
    /// The live favorites list — read directly; @Observable propagates changes.
    let favoritesModel: FavoritesModel
    /// The panel's fold state.
    let panelModel: FavoritesPanelModel
    /// The operations a row can reach — jump, unstar, scope, label.
    let actions: FavoritesPanelActions

    var body: some View {
        VStack(spacing: 0) {
            OverlayHeader(title: "favorites") { FavoritesPanelController.shared.close() }
            panelHeader
            scrollArea
            panelFooter
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onExitCommand {
            // Esc unwinds one layer: an open name field first, the panel after.
            if panelModel.editingID == nil {
                FavoritesPanelController.shared.close()
            } else {
                panelModel.cancelEditing()
            }
        }
    }

    /// The destination selector — three arrows choose where a jump lands.
    private var panelHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                targetArrow("arrow.left", .left, "left pane")
                targetArrow("arrow.left.arrow.right", .both, "both panes")
                targetArrow("arrow.right", .right, "right pane")
            }
            .padding(4)
            .background(Capsule().fill(Theme.groundDeep))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider().opacity(0.35)
        }
    }

    /// One arrow in the destination selector — filled when it is the target.
    private func targetArrow(
        _ systemName: String, _ target: FavoritesJumpTarget, _ help: String
    ) -> some View {
        let active = panelModel.jumpTarget == target
        return Button(
            action: { panelModel.jumpTarget = target },
            label: {
                Image(systemName: systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? Theme.ground : Theme.accent)
                    .frame(width: 30, height: 22)
                    .background(Capsule().fill(active ? Theme.accent : Color.clear))
            }
        )
        .buttonStyle(.plain)
        .help(help)
    }

    private var scrollArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = FavoritesOutline.groups(
                        from: favoritesModel.all,
                        collapsed: panelModel.collapsed)
                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups) { group in
                            FavoritesGroupView(
                                group: group,
                                panelModel: panelModel,
                                actions: actions
                            ) {
                                panelModel.toggle(key: group.key)
                            }
                            Divider().opacity(0.25)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: panelModel.cursor) { _, newCursor in
                if let id = newCursor {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Text("no favorites yet")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("star a directory with 8 or the ★ in the address bar")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Spacer(minLength: 24)
        }
    }

    private var panelFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.35)
            Text("esc closes · r renames · 8 stars · * opens")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}
