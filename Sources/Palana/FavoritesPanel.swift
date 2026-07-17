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
        onJump: @escaping (String, String) -> Void,
        onUnstar: @escaping (String) -> Void,
        onSetScope: @escaping (String, FavoriteScope) -> Void
    ) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
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
                onJump: onJump,
                onUnstar: onUnstar,
                onSetScope: onSetScope))
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
        onJump: @escaping (String, String) -> Void,
        onUnstar: @escaping (String) -> Void,
        onSetScope: @escaping (String, FavoriteScope) -> Void
    ) {
        if panel != nil {
            close()
        } else {
            show(
                favoritesModel: favoritesModel,
                panelModel: panelModel,
                onJump: onJump,
                onUnstar: onUnstar,
                onSetScope: onSetScope)
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
    /// Called when the operator jumps to a favorite (host, path).
    let onJump: (String, String) -> Void
    /// Called when the operator removes a favorite by id.
    let onUnstar: (String) -> Void
    /// Called when the operator flips a favorite's scope.
    let onSetScope: (String, FavoriteScope) -> Void

    var body: some View {
        VStack(spacing: 0) {
            OverlayHeader(title: "favorites") { FavoritesPanelController.shared.close() }
            panelHeader
            scrollArea
            panelFooter
        }
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                cursor: panelModel.cursor,
                                onToggle: { panelModel.toggle(key: group.key) },
                                onJump: onJump,
                                onUnstar: onUnstar,
                                onSetScope: onSetScope)
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
            Text("esc closes · 8 stars · * opens")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }
}

// MARK: - FavoritesGroupView

/// One host's disclosure section in the favorites column.
struct FavoritesGroupView: View {
    /// The group's display data.
    let group: FavoritesOutline.Group
    /// The keyboard cursor's stable id — used to highlight the selected row.
    let cursor: String?
    /// Called when the operator taps the disclosure chevron.
    let onToggle: () -> Void
    /// Called when the operator jumps to a favorite.
    let onJump: (String, String) -> Void
    /// Called when the operator removes a favorite.
    let onUnstar: (String) -> Void
    /// Called when the operator flips a favorite's scope.
    let onSetScope: (String, FavoriteScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeader
            if group.expanded {
                favoriteRows
            }
        }
        .padding(.vertical, 8)
    }

    private var headerCursorID: String { "hdr:\(group.key)" }
    private var isHeaderSelected: Bool { cursor == headerCursorID }

    private var groupHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            groupChevron
            Text(group.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("\(group.favorites.count)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.accent.opacity(isHeaderSelected ? 0.18 : 0))
        )
        .id(headerCursorID)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
    }

    /// Disclosure chevron — accent coloured, rotates 90° when expanded.
    private var groupChevron: some View {
        Text(Image(systemName: "chevron.right"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .rotationEffect(.degrees(group.expanded ? 90 : 0))
            .frame(width: 18, alignment: .center)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var favoriteRows: some View {
        ForEach(group.favorites) { fav in
            FavoriteRowView(
                favorite: fav,
                isSelected: cursor == "fav:\(fav.id)",
                onJump: { onJump(fav.host, fav.path) },
                onUnstar: { onUnstar(fav.id) },
                onSetScope: { newScope in onSetScope(fav.id, newScope) })
        }
    }
}

// MARK: - FavoriteRowView

/// One favorite entry in the panel — path, unstar control, scope toggle.
struct FavoriteRowView: View {
    /// The favorite to display.
    let favorite: Favorite
    /// True when this row is the keyboard cursor's current position.
    let isSelected: Bool
    /// Called when the operator jumps to this favorite.
    let onJump: () -> Void
    /// Called when the operator unstars this favorite.
    let onUnstar: () -> Void
    /// Called when the operator flips the scope.
    let onSetScope: (FavoriteScope) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onJump) {
                Text(displayTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("jump here — \(favorite.host):\(favorite.path)")

            if hovering || isSelected {
                scopeToggleButton
                unstarButton
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.accent.opacity(isSelected ? 0.18 : 0))
        )
        .id("fav:\(favorite.id)")
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var displayTitle: String {
        favorite.label ?? "\(favorite.host):\(favorite.path)"
    }

    /// A small scope-toggle button — "global" or host alias glyph.
    private var scopeToggleButton: some View {
        Button(
            action: { onSetScope(targetScope) },
            label: {
                Image(systemName: scopeGlyph)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
        )
        .buttonStyle(.plain)
        .help(scopeHelp)
    }

    private var targetScope: FavoriteScope {
        favorite.scope == .global ? .host : .global
    }

    private var scopeGlyph: String {
        favorite.scope == .global ? "pin.fill" : "pin"
    }

    private var scopeHelp: String {
        favorite.scope == .global
            ? "move to this host — leave global"
            : "promote to global — visible on all hosts"
    }

    /// The unstar (remove) button.
    private var unstarButton: some View {
        Button(action: onUnstar) {
            Image(systemName: "star.slash")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
        .buttonStyle(.plain)
        .help("remove from favorites")
    }
}
