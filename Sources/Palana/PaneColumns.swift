// PaneColumns — column definitions extracted from PaneView to keep the
// SwiftUI Table body within a reasonable type-checker window. Nine columns
// in a single Table builder pushed the compiler toward multi-second
// type-check times; pulling them here into @TableColumnBuilder helpers
// brings it back to sub-second.
//
// The `name` column is non-hideable (marked `.required`). Every other
// column carries a `.customizationID` so the platform's header right-click
// gives show/hide for free. Default-visible: name, size, modified. The
// remaining six (created, changed, permissions, owner, group, ★) default to
// hidden and appear on first right-click.

import PalanaCore
import SwiftUI

// MARK: - Column ID registry

/// The canonical customization IDs for every pane column.
///
/// Shared between `PaneColumns` (where columns are built) and `ColumnStore`
/// (which needs to iterate them to extract the hidden set). The order here
/// matches the Table's column order.
enum PaneColumns {
    static let idName = "name"
    static let idSize = "size"
    static let idModified = "modified"
    static let idCreated = "created"
    static let idChanged = "changed"
    static let idPermissions = "permissions"
    static let idOwner = "owner"
    static let idGroup = "group"
    static let idStar = "star"

    /// All column IDs in table order — used by ``ColumnStore`` to extract the
    /// hidden set from a ``TableColumnCustomization`` value.
    static let allIDs: [String] = [
        idName, idSize, idModified, idCreated, idChanged,
        idPermissions, idOwner, idGroup, idStar,
    ]
}

// MARK: - Date formatting

extension PaneColumns {
    /// Formats a date the way the modified column does, or returns `—` for nil.
    static func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
