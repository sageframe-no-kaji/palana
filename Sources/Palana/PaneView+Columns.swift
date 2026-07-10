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

import PalanaCore
import SwiftUI

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
        TableColumn("created") { (entry: FileEntry) in
            Text(PaneColumns.dateText(entry.created))
                .foregroundStyle(entry.created == nil ? Theme.inkFaint.opacity(0.5) : Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 110, ideal: 150, max: 190)
        .customizationID(PaneColumns.idCreated)
        .defaultVisibility(.hidden)

        TableColumn("changed") { (entry: FileEntry) in
            Text(PaneColumns.dateText(entry.changed))
                .foregroundStyle(entry.changed == nil ? Theme.inkFaint.opacity(0.5) : Theme.inkFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 110, ideal: 150, max: 190)
        .customizationID(PaneColumns.idChanged)
        .defaultVisibility(.hidden)

        TableColumn("permissions") { (entry: FileEntry) in
            Text(entry.permissions)
                .foregroundStyle(Theme.inkFaint)
                .font(.system(size: 12 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 50, ideal: 60, max: 80)
        .customizationID(PaneColumns.idPermissions)
        .defaultVisibility(.hidden)

        TableColumn("owner") { (entry: FileEntry) in
            Text(entry.owner)
                .foregroundStyle(Theme.inkFaint)
                .font(.system(size: 12 * fontScale, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cursorWash(entry))
        }
        .width(min: 60, ideal: 90, max: 140)
        .customizationID(PaneColumns.idOwner)
        .defaultVisibility(.hidden)

        TableColumn("group") { (entry: FileEntry) in
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
        // Sortable: starred directories gather at the top; the comparator
        // is app-side (starred is not a core SortKey) and lives in PaneModel.
        TableColumn("★") { (entry: FileEntry) in
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
