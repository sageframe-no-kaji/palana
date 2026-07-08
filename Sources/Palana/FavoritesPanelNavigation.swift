// FavoritesPanelNavigation — keyboard navigation handlers for the floating
// favorites column panel. Extracted from PalanaSession to keep that file
// within the file-length limit. All methods extend PalanaSession.

import AppKit
import PalanaCore

// MARK: - Favorites panel keyboard navigation

extension PalanaSession {
    /// Routes a raw NSEvent from the favorites panel window.
    ///
    /// Reads the raw event (not Grammar.token) so shift-arrow and plain-arrow
    /// are distinguishable — the token builder drops Shift for arrow keys.
    /// Returns true when the event is consumed; the monitor swallows it.
    @MainActor
    func handleFavoritesPanelKey(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let hasShift = event.modifierFlags.contains(.shift)
        let hasCommand = event.modifierFlags.contains(.command)
        if keyCode == 53 {
            FavoritesPanelController.shared.close()
            return true
        }
        // ⌘Z — panel-scoped undo.
        if hasCommand, !hasShift, event.charactersIgnoringModifiers?.lowercased() == "z" {
            favorites.undo()
            return true
        }
        let rows = FavoritesOutline.flatRows(
            from: favorites.all, collapsed: favoritesPanelModel.collapsed)
        guard !rows.isEmpty else { return false }
        guard
            let cursorID = favoritesPanelModel.cursor,
            let cursorIndex = rows.firstIndex(where: { $0.cursorID == cursorID })
        else {
            favoritesPanelModel.cursor = rows[0].cursorID
            return true
        }
        let currentRow = rows[cursorIndex]
        let arrowConsumed = handleFavoritesPanelArrow(
            keyCode: keyCode,
            hasShift: hasShift,
            rows: rows,
            cursorIndex: cursorIndex,
            currentRow: currentRow)
        if arrowConsumed { return true }
        if let ch = event.charactersIgnoringModifiers?.lowercased(), !hasCommand, !hasShift {
            return handleFavoritesPanelLetter(
                ch,
                rows: rows,
                cursorIndex: cursorIndex,
                currentRow: currentRow)
        }
        return false
    }

    /// Handles arrow key and return codes for the favorites panel.
    func handleFavoritesPanelArrow(
        keyCode: UInt16,
        hasShift: Bool,
        rows: [FavoritesOutline.Row],
        cursorIndex: Int,
        currentRow: FavoritesOutline.Row
    ) -> Bool {
        switch keyCode {
        case 125:  // down arrow
            if hasShift, case .favorite(let fav) = currentRow {
                // shift-down: demote to host scope; cursor stays on the same id.
                favorites.setScope(id: fav.id, .host)
            } else if !hasShift {
                favoritesPanelModel.cursor = rows[min(cursorIndex + 1, rows.count - 1)].cursorID
            }
            return true
        case 126:  // up arrow
            if hasShift, case .favorite(let fav) = currentRow {
                // shift-up: promote to global scope; cursor stays on the same id.
                favorites.setScope(id: fav.id, .global)
            } else if !hasShift {
                favoritesPanelModel.cursor = rows[max(cursorIndex - 1, 0)].cursorID
            }
            return true
        case 124:  // right — expand or jump
            favPanelExpand(currentRow)
            return true
        case 123:  // left — collapse
            favPanelCollapse(currentRow)
            return true
        case 36:  // return — toggle header / jump favorite
            switch currentRow {
            case .header(let key): favoritesPanelModel.toggle(key: key)
            case .favorite(let fav): favPanelJump(fav)
            }
            return true
        default:
            return false
        }
    }

    /// Handles letter keys (j/k/l/h) for the favorites panel.
    func handleFavoritesPanelLetter(
        _ ch: String,
        rows: [FavoritesOutline.Row],
        cursorIndex: Int,
        currentRow: FavoritesOutline.Row
    ) -> Bool {
        switch ch {
        case "j":
            favoritesPanelModel.cursor = rows[min(cursorIndex + 1, rows.count - 1)].cursorID
            return true
        case "k":
            favoritesPanelModel.cursor = rows[max(cursorIndex - 1, 0)].cursorID
            return true
        case "l":
            favPanelExpand(currentRow)
            return true
        case "h":
            favPanelCollapse(currentRow)
            return true
        default:
            return false
        }
    }

    /// Opens a header or jumps a favorite (right / l).
    func favPanelExpand(_ row: FavoritesOutline.Row) {
        switch row {
        case .header(let key): favoritesPanelModel.expand(key: key)
        case .favorite(let fav): favPanelJump(fav)
        }
    }

    /// Collapses a header or collapses the parent group of a favorite (left / h).
    func favPanelCollapse(_ row: FavoritesOutline.Row) {
        switch row {
        case .header(let key):
            favoritesPanelModel.collapse(key: key)
        case .favorite(let fav):
            let parentKey = favPanelParentKey(for: fav)
            favoritesPanelModel.collapse(key: parentKey)
            favoritesPanelModel.cursor = "hdr:\(parentKey)"
        }
    }

    /// Jumps to a favorite through the column's selected target, panel open.
    ///
    /// The arrow cluster decides left, right, or both. The column stays up so
    /// the operator can jump again — same as a mouse-click jump. Esc, `*`, or
    /// the titlebar star closes it.
    func favPanelJump(_ fav: Favorite) {
        jumpFavorite(host: fav.host, path: fav.path)
    }

    /// Points the selected pane(s) at a favorite's location.
    ///
    /// The arrow cluster in the column chooses left, right, or both.
    func jumpFavorite(host: String, path: String) {
        switch favoritesPanelModel.jumpTarget {
        case .left: left.point(host: host, path: path)
        case .right: right.point(host: host, path: path)
        case .both:
            left.point(host: host, path: path)
            right.point(host: host, path: path)
        }
    }

    /// Resolves the group key that owns a given favorite.
    func favPanelParentKey(for fav: Favorite) -> String {
        favorites.all.first { $0.id == fav.id }
            .map { $0.scope == .global ? "global" : $0.host }
            ?? fav.host
    }
}
