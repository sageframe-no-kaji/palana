// The favorites column's rows — one host's disclosure section and the
// favorite rows inside it. Extracted from FavoritesPanel.swift to keep that
// file within the file-length limit, same move as FavoritesPanelNavigation.
// A row shows its label when it has one and its path when it does not; the
// name field that sets that label opens from `r`, a second click, or the
// row menu.

import AppKit
import PalanaCore
import SwiftUI

// MARK: - FavoriteRenameArming

/// The guard behind the second-click rename in the favorites panel.
enum FavoriteRenameArming {
    /// True when a click should *arm* the name field — never open it outright.
    ///
    /// Two conditions, both required. The row is already the panel's focused
    /// row: a click that merely focuses a row jumps, it never edits. And the
    /// system's double-click interval has passed since the previous click on
    /// that row, so the second click of a double-click cannot arm one either.
    ///
    /// Arming is deliberately not opening. The caller waits out one more
    /// double-click interval and cancels on any further click, which is what
    /// keeps a double-click on an already-focused row a jump rather than a
    /// rename — the predicate alone cannot tell those apart on the first click.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the clicked row already held the panel's cursor.
    ///   - secondsSincePreviousClick: Elapsed time since this row's last click.
    ///   - doubleClickInterval: The system's double-click interval, in seconds.
    /// - Returns: True when the click should arm a rename rather than jump.
    static func shouldArmRename(
        isFocused: Bool,
        secondsSincePreviousClick: TimeInterval,
        doubleClickInterval: TimeInterval
    ) -> Bool {
        isFocused && secondsSincePreviousClick > doubleClickInterval
    }
}

// MARK: - FavoritesGroupView

/// One host's disclosure section in the favorites column.
struct FavoritesGroupView: View {
    /// The group's display data.
    let group: FavoritesOutline.Group
    /// The panel's cursor and edit state.
    let panelModel: FavoritesPanelModel
    /// The operations a row can reach — jump, unstar, scope, label.
    let actions: FavoritesPanelActions
    /// Called when the operator taps the disclosure chevron.
    let onToggle: () -> Void

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
    private var isHeaderSelected: Bool { panelModel.cursor == headerCursorID }

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
            FavoriteRowView(favorite: fav, panelModel: panelModel, actions: actions)
        }
    }
}

// MARK: - FavoriteRowView

/// One favorite entry in the panel — name, unstar control, scope toggle.
struct FavoriteRowView: View {
    /// The favorite to display.
    let favorite: Favorite
    /// The panel's cursor and edit state.
    let panelModel: FavoritesPanelModel
    /// The operations this row can reach — jump, unstar, scope, label.
    let actions: FavoritesPanelActions

    @State private var hovering = false
    /// When this row's name was last clicked — the double-click guard reads it.
    @State private var lastClickAt: Date?
    /// The armed-but-not-yet-open rename, waiting out a possible second click.
    ///
    /// Nothing renames on the click itself: the edit opens only once the
    /// double-click interval passes with no second click, and any click that
    /// arrives first cancels it. That wait is what keeps a double-click a jump.
    @State private var renameTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    /// True when this row is the keyboard cursor's current position.
    var isSelected: Bool { panelModel.cursor == cursorID }

    private var cursorID: String { "fav:\(favorite.id)" }
    private var isEditing: Bool { panelModel.editingID == favorite.id }

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                nameField
            } else {
                nameButton
                if hovering || isSelected {
                    scopeToggleButton
                    unstarButton
                }
            }
        }
        .padding(.leading, 24)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Theme.accent.opacity(isSelected ? 0.18 : 0))
        )
        .id(cursorID)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { rowMenu }
    }

    /// The row's name — the label when it has one, `host:path` when it does not.
    private var nameButton: some View {
        Button(action: handleNameClick) {
            Text(favorite.displayTitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("jump here — \(favorite.host):\(favorite.path)")
    }

    /// The inline name field — ⏎ commits, esc cancels, a click away commits.
    ///
    /// The text lives on the panel model, not here, so a click that lands
    /// somewhere else can still save what was typed.
    private var nameField: some View {
        TextField("name — ⏎ commits, esc cancels", text: draftBinding)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .focused($fieldFocused)
            .onSubmit { actions.commitOpenEdit(on: panelModel) }
            .onExitCommand { panelModel.cancelEditing() }
            .onChange(of: fieldFocused) { _, focused in
                // Belt to the panel's click-catcher: when the field genuinely
                // does lose the keyboard, that is the operator done typing.
                guard !focused, isEditing else { return }
                actions.commitOpenEdit(on: panelModel)
            }
            .onAppear { fieldFocused = true }
    }

    /// The open field's text, held on the panel model.
    private var draftBinding: Binding<String> {
        Binding(
            get: { panelModel.editingText },
            set: { panelModel.editingText = $0 })
    }

    /// The row's own menu — the same operations the keys and controls reach.
    @ViewBuilder private var rowMenu: some View {
        Button("rename…") { panelModel.beginEditing(id: favorite.id, current: favorite.label) }
        Button(scopeToggleTitle) { actions.setScope(favorite.id, targetScope) }
        Divider()
        Button("unstar") { actions.unstar(favorite.id) }
    }

    /// A single click: jump, or arm the name field when the guard allows it.
    private func handleNameClick() {
        // A click on this row ends an edit open on any other row.
        actions.commitOpenEdit(on: panelModel)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastClickAt ?? .distantPast)
        let wasFocused = isSelected
        lastClickAt = now
        // Every click supersedes an armed rename — that is how the second half
        // of a double-click takes the gesture back.
        renameTask?.cancel()
        renameTask = nil
        panelModel.cursor = cursorID
        guard
            FavoriteRenameArming.shouldArmRename(
                isFocused: wasFocused,
                secondsSincePreviousClick: elapsed,
                doubleClickInterval: NSEvent.doubleClickInterval)
        else {
            actions.jump(favorite.host, favorite.path)
            return
        }
        let id = favorite.id
        let label = favorite.label
        let model = panelModel
        renameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled else { return }
            model.beginEditing(id: id, current: label)
        }
    }

    /// A small scope-toggle button — "global" or host alias glyph.
    private var scopeToggleButton: some View {
        Button(
            action: { actions.setScope(favorite.id, targetScope) },
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

    private var scopeToggleTitle: String {
        favorite.scope == .global ? "move to this host" : "promote to global"
    }

    private var scopeHelp: String {
        favorite.scope == .global
            ? "move to this host — leave global"
            : "promote to global — visible on all hosts"
    }

    /// The unstar (remove) button.
    private var unstarButton: some View {
        Button(
            action: { actions.unstar(favorite.id) },
            label: {
                Image(systemName: "star.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
        )
        .buttonStyle(.plain)
        .help("remove from favorites")
    }
}
