// One pane — a header naming where it points (click the path to type
// a new one), a Table over the rows, an error banner that never steals
// the view, and quiet in-place lines for the unpointed and loading
// states. The Table's selection binding is the cursor; the selection
// set renders as accent marks. The register is the notebook: no
// chrome, one accent, directories by weight and a trailing slash. The
// unfocused pane sits a shade dimmer — the eye finds the live one.

import PalanaCore
import SwiftUI

/// One pane of the two.
struct PaneView: View {
    /// The pane's model.
    let model: PaneModel
    /// Whether the keyboard drives this pane.
    let isFocused: Bool
    /// The Field's hosts, for the header menu.
    let hosts: [String]
    /// Called when a click lands here — focus follows.
    let onFocus: () -> Void
    /// Opens `~/.ssh/config` — the only way hosts are added.
    let onEditConfig: () -> Void
    /// Re-reads the config for the menus.
    let onReloadHosts: () -> Void
    /// Starts an operation with this pane as the source — the session
    /// owns the panel.
    let onOperation: (PlanOperation) -> Void

    @State private var pathDraft = ""
    @FocusState private var pathFieldFocused: Bool
    @State private var sortOrder: [KeyPathComparator<FileEntry>] = [
        KeyPathComparator(\.name, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Theme.ground)
        .overlay {
            if !isFocused {
                Theme.ink.opacity(0.045)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isFocused ? Theme.accent : Theme.inkFaint.opacity(0.25))
                .frame(width: 7, height: 7)
            addressReadout
            if model.isReading {
                Text("reading…")
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            hostMenu
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.groundDeep)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    /// The whole address — text until clicked, one typeable field after.
    ///
    /// `host:path` is the vocabulary, same as the terminal's. A pane
    /// pointed nowhere is one click and one address from somewhere.
    @ViewBuilder private var addressReadout: some View {
        if model.pathEditing {
            TextField("host:path — local: for this Mac, ~ for home", text: $pathDraft)
                .textFieldStyle(.plain)
                .focused($pathFieldFocused)
                .foregroundStyle(Theme.ink)
                .onSubmit { commitAddressDraft() }
                .onExitCommand { endAddressEditing() }
                .onChange(of: pathFieldFocused) { _, focused in
                    if !focused { endAddressEditing() }
                }
        } else if let host = model.state.host {
            HStack(spacing: 2) {
                Text("\(host):")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                Text(model.state.path)
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .onTapGesture { beginAddressEditing() }
            .help("click to type host:path")
        } else {
            Text("nowhere — click to type host:path")
                .foregroundStyle(Theme.inkFaint)
                .onTapGesture { beginAddressEditing() }
        }
    }

    /// The bar's list — every host the config names, then the ways in.
    ///
    /// Right-pinned so it never crosses the pane's edge.
    private var hostMenu: some View {
        HostMenuButton(
            hosts: hosts,
            onChoose: { model.pointAddress("\($0):~") },
            onType: { beginAddressEditing() },
            onEditConfig: onEditConfig,
            onReload: onReloadHosts
        )
        .fixedSize()
    }

    private func beginAddressEditing() {
        pathDraft = model.state.host.map { "\($0):\(model.state.path)" } ?? ""
        model.pathEditing = true
        pathFieldFocused = true
    }

    private func endAddressEditing() {
        model.pathEditing = false
        pathFieldFocused = false
    }

    private func commitAddressDraft() {
        let typed = pathDraft
        endAddressEditing()
        model.pointAddress(typed)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch model.status {
        case .unpointed:
            quietLine(model.lastError ?? "⇧⌘G to go somewhere — or click the bar above and type host:path")
        case .loading:
            quietLine("reading…")
        case .ready:
            table
                .overlay(alignment: .bottom) {
                    if let error = model.lastError {
                        errorBanner(error)
                    }
                }
        }
    }

    /// A failed read over a live listing — say it, stay put.
    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.82), in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }

    private var table: some View {
        ScrollViewReader { proxy in
            innerTable
                .onChange(of: model.state.cursor) { _, cursor in
                    // Keyed moves must keep the cursor on screen — the
                    // Table does not follow programmatic selection on
                    // its own (first hands session's finding).
                    guard let cursor else { return }
                    proxy.scrollTo(cursor)
                }
        }
    }

    private var innerTable: some View {
        Table(model.rows, selection: cursorBinding, sortOrder: $sortOrder) {
            TableColumn("name", value: \.name) { entry in
                nameCell(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cursorWash(entry))
            }
            TableColumn("size", value: \.size) { entry in
                Text(entry.kind == .directory ? "—" : Self.sizeText(entry.size))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(cursorWash(entry))
            }
            .width(min: 60, ideal: 80, max: 110)
            TableColumn("modified", value: \.modified) { entry in
                Text(entry.modified.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cursorWash(entry))
            }
            .width(min: 110, ideal: 150, max: 190)
        }
        .onChange(of: sortOrder) { _, order in
            // A header click re-sorts through the pane's own model — the
            // Table reports the column, the listing keeps its comparators.
            if let first = order.first { model.applySort(from: first) }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .background(TableSelectionStyler())
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            contextMenuItems(for: ids)
        } primaryAction: { ids in
            // A double-click enters the directory or opens the file —
            // single click stays the cursor, so a row can be chosen
            // without being entered.
            onFocus()
            if let id = ids.first {
                model.activate(id)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size.height, initial: true) { _, height in
                        // A page is what the eye can see — keep the
                        // jump keys honest about the window's height.
                        model.pageSize = max(Int(height / 24) - 1, 1)
                    }
            })
    }

    /// The full menu, right-clicked.
    ///
    /// Every verb names its key. The operation verbs aim at the
    /// clicked rows, then the panel takes over exactly as if the key
    /// had gone down.
    @ViewBuilder
    private func contextMenuItems(for ids: Set<FileEntry.ID>) -> some View {
        Button("open / enter") {
            onFocus()
            if let id = ids.first { model.activate(id) }
        }
        .keyboardShortcut(.return, modifiers: [])
        Divider()
        // Native glyphs where AppKit can draw them (its caps display is
        // convention, not case), quiet spaced suffixes for the two-key
        // sequences it cannot — mixed, per the hands.
        Button("copy to other pane") { operate(.copy, ids: ids) }
            .keyboardShortcut("y", modifiers: [])
        Button("move to other pane") { operate(.move, ids: ids) }
            .keyboardShortcut("m", modifiers: [])
        Button("remove — plan first") { operate(.delete, ids: ids) }
            .keyboardShortcut("r", modifiers: [])
        Button("touch — update modified") { operate(.touch, ids: ids) }
            .keyboardShortcut("t", modifiers: [])
        Divider()
        Button("copy path      cc") { model.copyToClipboard(.copyPath, ids: ids) }
        Button("copy filename      cf") { model.copyToClipboard(.copyFilename, ids: ids) }
        Button("copy name without extension      cn") {
            model.copyToClipboard(.copyNameSansExtension, ids: ids)
        }
        Button("copy this directory's path      cd") {
            model.copyToClipboard(.copyDirectory, ids: ids)
        }
        Divider()
        Button(model.state.showHidden ? "hide hidden files" : "show hidden files") {
            model.apply(.toggleHidden)
        }
        .keyboardShortcut(".", modifiers: [])
        Button("refresh") { model.apply(.refresh) }
            .keyboardShortcut("r", modifiers: .command)
    }

    /// Aims the pane's subjects at the clicked rows, then starts the
    /// operation.
    ///
    /// Rows already inside the selection keep the whole selection —
    /// Finder's manners.
    private func operate(_ operation: PlanOperation, ids: Set<FileEntry.ID>) {
        onFocus()
        if !ids.isEmpty, !ids.isSubset(of: model.state.selection) {
            model.state.selection = ids.count > 1 ? ids : []
            model.state.cursor = ids.first
        }
        onOperation(operation)
    }

    private func nameCell(_ entry: FileEntry) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 3, height: 14)
                .opacity(model.state.selection.contains(entry.id) ? 1 : 0)
            Text(displayName(entry))
                .fontWeight(entry.kind == .directory ? .medium : .regular)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            if entry.kind == .symlink, let target = entry.symlinkTargetName {
                Text("→ \(target)")
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
            }
            driveMark(for: entry)
        }
    }

    /// The drive-glyph filesystem boundary mark — filled dataset,
    /// outlined plain mount, nothing otherwise.
    @ViewBuilder
    private func driveMark(for entry: FileEntry) -> some View {
        switch model.boundaryMark(for: entry) {
        case .dataset:
            Text(Image(systemName: "externaldrive.fill"))
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .help("dataset mountpoint — a filesystem boundary")
        case .mount:
            Text(Image(systemName: "externaldrive"))
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .help("mount point — a filesystem boundary")
        case nil:
            EmptyView()
        }
    }

    private func displayName(_ entry: FileEntry) -> String {
        entry.kind == .directory ? "\(entry.name)/" : entry.name
    }

    /// The cursor row's own paint — moss wash, not the system accent.
    private func cursorWash(_ entry: FileEntry) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent.opacity(model.state.cursor == entry.id ? 0.18 : 0))
            .padding(.horizontal, -6)
    }

    private var cursorBinding: Binding<FileEntry.ID?> {
        Binding(
            get: { model.state.cursor },
            set: { clicked in
                // The setter only fires from the Table's own interaction
                // — a click — so focus follows it, and the modifiers
                // carry Finder's selection manners: shift extends from
                // the cursor, ⌘ or ⌥ toggles one row. Keyed moves write
                // the state directly and never pass through here.
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if let clicked, flags.contains(.shift) {
                    model.extendSelection(to: clicked)
                } else if let clicked, !flags.isDisjoint(with: [.command, .option]) {
                    model.toggleSelection(clicked)
                }
                model.state.cursor = clicked
                onFocus()
            })
    }

    /// Sizes as facts — `0 bytes`, never `Zero kB`.
    private static func sizeText(_ size: Int64) -> String {
        size.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    private func quietLine(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
