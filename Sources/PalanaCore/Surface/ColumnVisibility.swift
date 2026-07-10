// ColumnVisibility — the on-disk column configuration for the pane table.
//
// Lives in PalanaCore so it is testable: encode/decode round-trips and
// silent-fail on corrupt input can be verified in PalanaCoreTests without
// depending on the app target. The app's ColumnStore wraps this shape and
// adds the TableColumnCustomization binding (which is not Codable, so only
// visibility — not widths — survives relaunch).

import Foundation

/// The set of column IDs the operator has hidden.
///
/// Used as the on-disk representation because ``SwiftUI/TableColumnCustomization``
/// is not ``Codable``. Widths are not persisted — they live only in the in-process
/// customization value and reset on relaunch. This is the named escape hatch
/// from Ho-9.8-AT-02 Decision 4.
public struct ColumnVisibility: Codable, Sendable, Equatable {
    /// The customization IDs of columns the operator has hidden.
    public var hiddenIDs: [String]

    /// An empty visibility (all columns at their defaults).
    public init(hiddenIDs: [String] = []) {
        self.hiddenIDs = hiddenIDs
    }
}
