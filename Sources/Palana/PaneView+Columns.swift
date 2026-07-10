// PaneView+Columns — the nine table columns, extracted from PaneView.swift
// to keep that file within the 500-line swiftlint limit and to give the
// SwiftUI type-checker a smaller body to check per file.
//
// Columns are split into two @TableColumnBuilder helpers:
//   coreColumns   — name (non-hideable), size, modified
//   extendedColumns — created, changed, permissions, owner, group, ★
//
// The star cell helper lives here too because it is an implementation detail
// of the ★ column.
//
// Sorting notes for the extended columns:
//   permissions, owner, group — String is Comparable; use value: keyPath directly.
//   created, changed          — Date? is not Comparable; use OptionalDateComparator
//                               so the Table header emits a valid sortOrder entry.
//   ★                         — not a FileEntry fact; uses StarMarkerComparator over
//                               \.kind as a routing token. PaneModel.applySort maps
//                               the \.kind keypath to a starred-first partition when
//                               it arrives from the ★ column (see ROUTING TOKEN note).

import PalanaCore
import SwiftUI

// MARK: - Custom comparators for extended columns

/// A `SortComparator` for `Date?` fields.
///
/// Nils sort last in **both** directions — a column of dashes never
/// shuffles when the direction flips. This mirrors `PaneState.sortedEntries`'s
/// own `compareOptionalNilsLast` semantics.
///
/// The comparator exists primarily to give the Table a typed sort descriptor
/// so header clicks emit a `KeyPathComparator<FileEntry>` that `applySort`
/// can route. The actual ordering is always done by `PaneModel.applySort`
/// → `PaneState.sortedEntries`.
struct OptionalDateComparator: SortComparator {
    typealias Compared = Date?

    var order: SortOrder = .forward

    /// Compares two optional dates with nils last in both directions.
    func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending  // nil is always last
        case (_, nil): return .orderedAscending  // non-nil before nil
        case (let lv?, let rv?):
            if lv < rv { return order == .forward ? .orderedAscending : .orderedDescending }
            if lv > rv { return order == .forward ? .orderedDescending : .orderedAscending }
            return .orderedSame
        }
    }
}

/// A routing-token comparator for the ★ column.
///
/// The ★ column cannot carry a real `FileEntry` fact (starred is an
/// app-side registry, not a `FileEntry` property). To give the Table
/// a sortable column — so header clicks emit a `KeyPathComparator<FileEntry>`
/// that `applySort` can intercept — the column uses `\.kind` as its keypath
/// with this marker comparator. `PaneModel.applySort` recognises the `\.kind`
/// keypath as the ★ routing token and performs the starred-first partition.
///
/// The `compare` implementation is intentionally a no-op identity: the
/// Table's sort machinery is never the authority for ★ order. The session's
/// `applySort` reorders `rows` directly after the header click fires.
struct StarMarkerComparator: SortComparator {
    typealias Compared = FileEntry.Kind

    var order: SortOrder = .forward

    func compare(_ lhs: FileEntry.Kind, _ rhs: FileEntry.Kind) -> ComparisonResult {
        // No actual ordering — ★ sort is app-side (starred partition).
        // `applySort` rewrites `rows` when it receives the \.kind token.
        .orderedSame
    }
}

// MARK: - Column extensions

extension PaneView {
    // MARK: Core columns (name, size, modified)

    /// The three columns present before ho-9.8: name (non-hideable), size, modified.
    @TableColumnBuilder<FileEntry, KeyPathComparator<FileEntry>>
    func coreColumns() -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        TableColumn("name", value: \.name) { entry in
            nameCell(entry)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .customizationID(PaneColumns.idName)
        // The name column is always visible — the platform's `.required` marks it
        // as non-hideable in the header right-click menu.
        .disabledCustomizationBehavior(.visibility)

        TableColumn("size", value: \.size) { entry in
            Text(entry.kind == .directory ? "—" : Self.sizeText(entry.size))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(cursorWash(entry))
        }
        .width(min: 60, ideal: 80, max: 110)
        .customizationID(PaneColumns.idSize)

        TableColumn("modified", value: \.modified) { entry in
            Text(PaneColumns.dateText(entry.modified))
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 110, ideal: 150, max: 190)
        .customizationID(PaneColumns.idModified)
    }

    // MARK: Extended columns (created, changed, permissions, owner, group, ★)

    /// The six new ho-9.8 columns — all default-hidden, shown via header right-click.
    ///
    /// `favorites` and `model` are explicit parameters to avoid capture-related
    /// strict-concurrency diagnostics inside the result-builder closure.
    @TableColumnBuilder<FileEntry, KeyPathComparator<FileEntry>>
    func extendedColumns(
        favorites: FavoritesModel,
        model: PaneModel
    ) -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        // Date? columns: not Comparable, so use explicit comparator so the
        // header emits a KeyPathComparator<FileEntry> that applySort can route.
        createdColumn()
        changedColumn()

        // String columns: Comparable, plain value: keypath form.
        TableColumn("permissions", value: \.permissions) { entry in
            Text(entry.permissions)
                .foregroundStyle(Theme.inkFaint)
                .font(.system(size: 12 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 50, ideal: 60, max: 80)
        .customizationID(PaneColumns.idPermissions)
        .defaultVisibility(.hidden)

        TableColumn("owner", value: \.owner) { entry in
            Text(entry.owner)
                .foregroundStyle(Theme.inkFaint)
                .font(.system(size: 12 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 60, ideal: 90, max: 140)
        .customizationID(PaneColumns.idOwner)
        .defaultVisibility(.hidden)

        TableColumn("group", value: \.group) { entry in
            Text(entry.group)
                .foregroundStyle(Theme.inkFaint)
                .font(.system(size: 12 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 60, ideal: 90, max: 140)
        .customizationID(PaneColumns.idGroup)
        .defaultVisibility(.hidden)

        // ★ column — header is the glyph, narrow fixed width.
        // Click toggles favorites via the same path as the `8` key.
        //
        // ROUTING TOKEN: ★ is not a FileEntry fact (favorites are app-side).
        // We use \.kind with StarMarkerComparator as a routing token so the
        // Table header can emit a KeyPathComparator<FileEntry>. The comparator
        // itself is a no-op identity; PaneModel.applySort recognises \.kind
        // arriving from this column and performs the starred partition instead
        // of a normal sort. \.kind is safe here — no other column uses it as
        // a comparator keypath.
        starColumn(favorites: favorites, model: model)
    }

    // MARK: Optional-date columns

    /// The `created` column — `Date?`, not Comparable; sorts via `OptionalDateComparator`.
    ///
    /// Extracted into its own helper so the trailing closure's explicit parameter
    /// type annotation `(entry: FileEntry) in` sits on the same line as `{`, which
    /// satisfies the `closure_parameter_position` rule.
    func createdColumn() -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        TableColumn("created", value: \.created, comparator: OptionalDateComparator()) { entry in
            Text(PaneColumns.dateText(entry.created))
                .foregroundStyle(entry.created == nil ? Theme.inkFaint.opacity(0.5) : Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 110, ideal: 150, max: 190)
        .customizationID(PaneColumns.idCreated)
        .defaultVisibility(.hidden)
    }

    /// The `changed` column — `Date?`, not Comparable; sorts via `OptionalDateComparator`.
    func changedColumn() -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        TableColumn("changed", value: \.changed, comparator: OptionalDateComparator()) { entry in
            Text(PaneColumns.dateText(entry.changed))
                .foregroundStyle(entry.changed == nil ? Theme.inkFaint.opacity(0.5) : Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 110, ideal: 150, max: 190)
        .customizationID(PaneColumns.idChanged)
        .defaultVisibility(.hidden)
    }

    // MARK: Star column

    /// The `★` column — routing-token sort via `StarMarkerComparator` on `\.kind`.
    ///
    /// See `ROUTING TOKEN` comment in `extendedColumns` for the design rationale.
    /// Extracted here so the closure parameter sits on the same line as `{`.
    func starColumn(
        favorites: FavoritesModel,
        model: PaneModel
    ) -> some TableColumnContent<FileEntry, KeyPathComparator<FileEntry>> {
        TableColumn("★", value: \.kind, comparator: StarMarkerComparator()) { entry in
            starCell(entry, favorites: favorites, model: model)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(cursorWash(entry))
        }
        .width(min: 24, ideal: 28, max: 32)
        .customizationID(PaneColumns.idStar)
        .defaultVisibility(.hidden)
    }

    // MARK: Star cell

    /// The ★ cell — filled accent on favorited directories, nothing on files.
    ///
    /// Click toggles via `onStarEntry`. Files show nothing: a favorite is a
    /// location, not a file. Table row hover is a known dead end — the click
    /// target is the cell itself.
    @ViewBuilder
    func starCell(
        _ entry: FileEntry,
        favorites: FavoritesModel,
        model: PaneModel
    ) -> some View {
        if entry.kind == .directory {
            let entryPath = PaneModel.childPath(of: model.state.path, name: entry.name)
            let host = model.state.host ?? ""
            let isStarred = favorites.isFavorited(host: host, path: entryPath)
            Button(
                action: { onStarEntry(entryPath) },
                label: {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(isStarred ? Theme.accent : Theme.inkFaint.opacity(0.4))
                }
            )
            .buttonStyle(.plain)
            .help(isStarred ? "remove from favorites" : "add to favorites")
        }
    }
}
