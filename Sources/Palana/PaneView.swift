// One pane — a header naming where it points (click the path to type
// a new one), a Table over the rows, an error banner that never steals
// the view, and quiet in-place lines for the unpointed and loading
// states. The Table's selection binding is the cursor; the selection
// set renders as accent marks. The register is the notebook: no
// chrome, one accent, directories by weight and a trailing slash. The
// unfocused pane sits a shade dimmer — the eye finds the live one.

import AppKit
import PalanaCore
import SwiftUI
import UniformTypeIdentifiers

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
    /// Text zoom for the pane's rows — ⌘+ / ⌘- / ⌘0.
    let fontScale: CGFloat
    /// The favorites model — drives the star and the host menu's favorites section.
    let favorites: FavoritesModel
    /// The shared column customization — visibility and widths for both panes.
    let columnStore: ColumnStore
    /// Toggle this pane's location in favorites.
    let onToggleFavorite: () -> Void
    /// A favorite was chosen from the host menu — point the pane.
    let onChooseFavorite: (HostMenuButton.FavoriteEntry) -> Void
    /// Flip a favorite's scope by id.
    let onToggleFavoriteScope: (String) -> Void
    /// Star or unstar a directory entry by its full path on this pane's host.
    let onStarEntry: (String) -> Void
    /// Called when a ``DraggedSelection`` is dropped onto this pane.
    ///
    /// The session resolves it through the standing gather path. The Bool is
    /// whether Option was held at drop time.
    let onDropSelection: (DraggedSelection, Bool) -> Void
    /// Called when a ``DraggedSelection`` is dropped onto a **folder row** (ho-14).
    ///
    /// The session resolves the destination to that folder's path. The
    /// `FileEntry` is the folder; the Bool is whether Option was held.
    let onDropSelectionOntoFolder: (DraggedSelection, FileEntry, Bool) -> Void
    /// Called when Finder file URLs are dropped onto a **folder row** — the
    /// files land inside that folder.
    let onFinderDropOntoFolder: ([URL], FileEntry, Bool) -> Void
    /// Called when Finder file URLs are dropped onto this pane.
    ///
    /// The session resolves them through the local listing and the gather path.
    /// The Bool is whether Option was held at drop time.
    let onFinderDrop: ([URL], Bool) -> Void
    /// Pops the terminal — wired to `OperationModel.showPanel()`.
    let onShowPanel: () -> Void
    /// Called when the back chevron is tapped.
    let onBack: () -> Void
    /// Called when the forward chevron is tapped.
    let onForward: () -> Void
    /// Fires a zfs verb on this pane's tree cursor — the context menu's
    /// route, mirroring the letter-key path (ho-10.3 Decision 4).
    let onZFSVerb: (WorkbenchVerb) -> Void
    /// The zfs mutation verbs, for the pane's context menu in zfs mode —
    /// the session's shared `zfsTool.verbs` list, never hardcoded here.
    let zfsVerbs: [WorkbenchVerb]
    /// The resolved preview state (ho-16).
    ///
    /// Meaningful only while this pane is in `.preview` mode; `.empty` for every
    /// other pane. The surface drives it off the opposite pane's cursor through
    /// the `PreviewController`.
    let previewState: PreviewController.State

    @State private var pathDraft = ""
    @FocusState private var pathFieldFocused: Bool
    @State private var starHovering = false
    @State private var dropTargeted = false
    /// The folder row a valid drag is hovering, if any (ho-14).
    ///
    /// Drives the accent wash on that row; cleared the instant the drag leaves
    /// or drops. Internal (not `private`) so the drop wiring in
    /// `PaneView+FolderDrop.swift` can read and clear it.
    @State var folderDropHoverID: FileEntry.ID?
    @State private var sortOrder: [KeyPathComparator<FileEntry>] = [
        KeyPathComparator(\.name, order: .forward)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            paneFooter
        }
        // zfs mode washes the ground toward the plugin hue at low opacity —
        // the loud, unmistakable boundary ho-10.3 Decision 2 calls for.
        // Layered under Theme.ground so files-mode is untouched.
        .background(Theme.ground)
        .background {
            if model.paneMode == .zfs {
                Theme.plugin.opacity(0.12)
            }
        }
        .overlay {
            if !isFocused {
                Theme.ink.opacity(0.045)
                    .allowsHitTesting(false)
            }
        }
        // The drop wash — accent ground + 2px inner border while a valid
        // drag hovers. Layered above the dim overlay so it is always visible.
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Theme.accent.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .strokeBorder(Theme.accent, lineWidth: 2)
                    )
                    .allowsHitTesting(false)
            }
        }
        // Pane-level drop surface — unified .onDrop handles both DraggedSelection
        // (pane-to-pane, encoded as public.json) and file URLs (Finder). A single
        // modifier avoids the SwiftUI single-drop-destination limit (RC2).
        // RC3: accepts .json (system-declared, conforms to public.data) instead of
        // the undeclared custom identifier that UTType(_:) was silently nil-ing.
        // isTargeted drives the drop-wash overlay.
        .onDrop(
            of: [.json, .fileURL],
            isTargeted: Binding(
                get: { dropTargeted },
                set: { targeted in
                    dropTargeted = targeted && model.status == .ready
                }
            )
        ) { providers in
            handleUnifiedDrop(
                providers: providers,
                model: model,
                onDropSelection: onDropSelection,
                onFinderDrop: onFinderDrop
            )
        }
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    // MARK: - Pane footer

    /// The pane's bottom strip — one terminal popout button, right-pinned.
    ///
    /// Wired to the same show path backtick uses so the operator can
    /// summon the terminal from wherever the mouse happens to be. In zfs
    /// mode this line names the exits instead (ho-10.3 Decision 2) — no
    /// mistaking which activity the pane is in from any distance.
    private var paneFooter: some View {
        HStack {
            if model.paneMode == .zfs {
                Text("↑↓ walk · letter fires verb · ⏎ opens mounted · esc/Z exits zfs mode")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.plugin)
            } else if model.paneMode == .preview {
                Text("previewing the left pane · v or esc exits")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.plugin)
            }
            Spacer()
            ToolbarGlyphButton("rectangle.bottomthird.inset.filled", help: "terminal") {
                onShowPanel()
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 24)
        .background(Theme.groundDeep)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.inkFaint.opacity(0.15))
                .frame(height: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            historyButtons
            Circle()
                .fill(isFocused ? Theme.accent : Theme.inkFaint.opacity(0.25))
                .frame(width: 7, height: 7)
            addressReadout
            if model.isReading {
                Text("reading…")
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
            starButton
            hostMenu
        }
        .font(Theme.font(12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.groundDeep)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    /// The whole address — text until clicked, one typeable field after.
    ///
    /// `host:path` is the vocabulary, same as the terminal's. A pane
    /// pointed nowhere is one click and one address from somewhere. In
    /// zfs mode the header reads `zfs · <host>` instead — no path to
    /// show or type (ho-10.3 Decision 2), untypeable while the mode holds.
    @ViewBuilder private var addressReadout: some View {
        if model.paneMode == .zfs {
            // The boundary wears the plugin chip's own clothes — solid
            // umber, cream letters — so the mode is unmistakable from
            // across the room (his ask, pointing at the strip chip).
            HStack(spacing: 8) {
                Text("ZFS")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.plugin, in: RoundedRectangle(cornerRadius: 4))
                Text(model.state.host ?? "—")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.plugin)
            }
        } else if model.paneMode == .preview {
            // The preview boundary — a plugin-hued chip like zfs mode's, so the
            // mode is unmistakable (ho-16 Decision 1).
            HStack(spacing: 8) {
                Text("VIEW")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.plugin, in: RoundedRectangle(cornerRadius: 4))
                Text("follows the left pane's cursor")
                    .foregroundStyle(Theme.inkFaint)
            }
        } else if model.pathEditing {
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

    /// A star that reflects whether this pane's location is favorited.
    ///
    /// Visible only when the pane has a host. Accent when favorited (or on hover),
    /// inkFaint otherwise. Clicking toggles the favorite for this pane's location.
    @ViewBuilder private var starButton: some View {
        if let host = model.state.host {
            let isFav = favorites.isFavorited(host: host, path: model.state.path)
            let filled = isFav || starHovering
            Button(action: onToggleFavorite) {
                Image(systemName: filled ? "star.fill" : "star")
                    .font(Theme.font(11))
                    .foregroundStyle(filled ? Theme.accent : Theme.inkFaint)
            }
            .buttonStyle(.plain)
            .onHover { starHovering = $0 }
            .help(isFav ? "remove from favorites" : "add to favorites")
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
            onReload: onReloadHosts,
            favorites: favoriteEntries(for: model.state.host),
            onChooseFavorite: onChooseFavorite,
            onToggleFavoriteScope: onToggleFavoriteScope
        )
        .fixedSize()
    }

    /// Back and forward chevrons — dimmed and inert when the stack is empty.
    private var historyButtons: some View {
        HStack(spacing: 2) {
            ToolbarGlyphButton("chevron.left", help: "go back  ⌘←") { onBack() }
                .opacity(model.canGoBack ? 1 : 0.3)
                .allowsHitTesting(model.canGoBack)
            ToolbarGlyphButton("chevron.right", help: "go forward  ⌘→") { onForward() }
                .opacity(model.canGoForward ? 1 : 0.3)
                .allowsHitTesting(model.canGoForward)
        }
    }

    /// Builds the flat entries passed to `HostMenuButton`.
    ///
    /// Global favorites always; host-bound favorites for the pane's current host.
    private func favoriteEntries(for host: String?) -> [HostMenuButton.FavoriteEntry] {
        var entries: [HostMenuButton.FavoriteEntry] = []
        for fav in favorites.global {
            entries.append(
                HostMenuButton.FavoriteEntry(
                    id: fav.id,
                    host: fav.host,
                    path: fav.path,
                    label: fav.label,
                    scope: fav.scope,
                    isGlobal: true))
        }
        if let host {
            for fav in favorites.hostBound(for: host) {
                entries.append(
                    HostMenuButton.FavoriteEntry(
                        id: fav.id,
                        host: fav.host,
                        path: fav.path,
                        label: fav.label,
                        scope: fav.scope,
                        isGlobal: false))
            }
        }
        return entries
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
        if model.paneMode == .zfs {
            // The dataset tree replaces the file Table entirely — the
            // machinery lives in PaneView+ZFSMode.swift to keep this file
            // under the line-length budget.
            zfsTreeContent
        } else if model.paneMode == .preview {
            // The preview of the opposite pane's cursor — content in
            // PaneView+Preview.swift, same line-budget reason.
            previewContent
        } else {
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
    }

    /// A failed read over a live listing — say it, stay put.
    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(11))
            .foregroundStyle(Theme.ground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.ink.opacity(0.82), in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }

    func quietLine(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(Theme.font(12))
                .foregroundStyle(Theme.inkFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Table

extension PaneView {
    var table: some View {
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

    var innerTable: some View {
        // Rows-builder form — required for per-row .draggable(). Nine columns
        // in a single Table builder exceed a reasonable type-check window, so
        // the column groups are split into @TableColumnBuilder helpers in
        // extensions below to keep the compiler happy.
        //
        // Column customization is shared across both panes via `columnStore` so
        // the operator's show/hide choices apply everywhere. The customization
        // binding drives header right-click without a bespoke picker.
        @Bindable var store = columnStore
        return Table(
            of: FileEntry.self,
            selection: cursorBinding,
            sortOrder: $sortOrder,
            columnCustomization: $store.customization
        ) {
            coreColumns()
            extendedColumns(favorites: favorites, model: model)
        } rows: {
            // Each row is draggable. The payload expands to the full selection
            // when the dragged row is within it (Finder's manners); otherwise
            // only the dragged row's name is carried. The selection's names
            // are gathered ONCE per render — a per-row filter would be O(n²)
            // on a dense directory, and the pane cadence is law (ho-07).
            let selectedNames = model.rows
                .filter { model.state.selection.contains($0.id) }
                .map(\.nameData)
            ForEach(model.rows) { entry in
                // itemProvider replaces .draggable — carries the DraggedSelection
                // as JSON under public.json (UTType.json) via NSItemProvider so
                // the drag pasteboard write succeeds without a bundle (RC1) and
                // the drop side accepts the type (RC3; see DragDrop.swift).
                TableRow(entry)
                    .itemProvider {
                        let payload = dragPayload(for: entry, selectedNames: selectedNames)
                        // Qualify the global to resolve the name collision with the
                        // .itemProvider(_:) modifier method on TableRow.
                        return Palana.itemProvider(
                            for: payload, localFileURL: localDragURL(for: entry))
                    }
            }
        }
        .onChange(of: sortOrder) { _, order in
            // A header click re-sorts through the pane's own model — the
            // Table reports the column, the listing keeps its comparators.
            if let first = order.first { model.applySort(from: first, favorites: favorites) }
        }
        .onChange(of: store.customization) { _, _ in
            // Persist hidden-column set whenever the operator changes visibility.
            columnStore.persist()
        }
        .tableStyle(.inset)
        .font(Theme.font(13))
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

    /// Builds the ``DraggedSelection`` payload for a row being dragged.
    ///
    /// When the dragged row is within the selection, the whole selection is
    /// the payload — Finder's muscle. When the row is outside the selection,
    /// only the dragged row's name is carried (one-name drag).
    func dragPayload(for entry: FileEntry, selectedNames: [Data]) -> DraggedSelection {
        let host = model.state.host ?? PalanaCore.localHostName
        let directory = model.state.path
        let names: [Data]
        if model.state.selection.contains(entry.id), !selectedNames.isEmpty {
            // Dragged row is selected — carry the whole selection.
            names = selectedNames
        } else {
            // Dragged row is outside the selection — carry only that row.
            names = [entry.nameData]
        }
        return DraggedSelection(host: host, directory: directory, names: names)
    }

    /// The full menu, right-clicked.
    ///
    /// Every verb names its key. The operation verbs aim at the
    /// clicked rows, then the panel takes over exactly as if the key
    /// had gone down.
    @ViewBuilder
    func contextMenuItems(for ids: Set<FileEntry.ID>) -> some View {
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
        Button("delete — plan first") { operate(.delete, ids: ids) }
            .keyboardShortcut("d", modifiers: [])
        Button("touch — update modified") { operate(.touch, ids: ids) }
            .keyboardShortcut("t", modifiers: [])
        Divider()
        // Creation lives in the empty-space instinct too — name/ makes a
        // directory, same field as `a` (his round: 'need to put create
        // file/directory in right click').
        Button("new file or directory… — name/ for a directory") { operate(.create, ids: []) }
            .keyboardShortcut("a", modifiers: [])
        Button("rename…") { operate(.rename, ids: ids) }
            .keyboardShortcut("R", modifiers: [])
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
        starContextItem(for: ids)
        Button(model.state.showHidden ? "hide hidden files" : "show hidden files") {
            model.apply(.toggleHidden)
        }
        .keyboardShortcut(".", modifiers: [])
        Button("refresh") { model.apply(.refresh) }
            .keyboardShortcut("r", modifiers: .command)
    }

    /// A "star this location" / "unstar this location" menu item when the
    /// first right-clicked entry is a directory.
    ///
    /// Returns an `EmptyView` when no eligible directory entry is found.
    @ViewBuilder
    func starContextItem(for ids: Set<FileEntry.ID>) -> some View {
        let directoryEntry = ids.first.flatMap { id in model.rows.first { $0.id == id } }
            .flatMap { $0.kind == .directory ? $0 : nil }
        if let entry = directoryEntry {
            let entryPath = PaneModel.childPath(of: model.state.path, name: entry.name)
            let isStarred = favorites.isFavorited(host: model.state.host ?? "", path: entryPath)
            Button(isStarred ? "unstar this location" : "star this location    8") {
                onStarEntry(entryPath)
            }
        }
    }

    /// Aims the pane's subjects at the clicked rows, then starts the
    /// operation.
    ///
    /// Rows already inside the selection keep the whole selection —
    /// Finder's manners.
    func operate(_ operation: PlanOperation, ids: Set<FileEntry.ID>) {
        onFocus()
        if !ids.isEmpty, !ids.isSubset(of: model.state.selection) {
            model.state.selection = ids.count > 1 ? ids : []
            model.state.cursor = ids.first
        }
        onOperation(operation)
    }

    /// The real file URL for a drag leaving the app — local pane only.
    ///
    /// A remote entry returns nil: no URL on this Mac can honor it (the
    /// file-promise download drag is a banked follow-up). The URL rides
    /// the drag beside the pane-to-pane payload so files land on any
    /// outside target — a browser upload, Finder, Mail.
    func localDragURL(for entry: FileEntry) -> URL? {
        guard model.state.host == PalanaCore.localHostName else { return nil }
        let base = model.state.path
        let path = base == "/" ? "/\(entry.name)" : "\(base)/\(entry.name)"
        return URL(fileURLWithPath: path)
    }

    func nameCell(_ entry: FileEntry) -> some View {
        // No .onDrag here, deliberately: a cell-level drag source wraps the
        // cell content in its own drag-hosting view, which desyncs SwiftUI's
        // drawn rows from AppKit's hit rects (clicks land one row off; top
        // row unreachable). Bisected to 9808498, proven by removal 2026-07-10.
        // TableRow.itemProvider carries pane-to-pane drag alone.
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
    func driveMark(for entry: FileEntry) -> some View {
        switch model.boundaryMark(for: entry) {
        case .dataset:
            Text(Image(systemName: "externaldrive.fill"))
                .font(Theme.font(10))
                .foregroundStyle(Theme.accent)
                .help("dataset mountpoint — a filesystem boundary")
        case .mount:
            Text(Image(systemName: "externaldrive"))
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .help("mount point — a filesystem boundary")
        case nil:
            EmptyView()
        }
    }

    func displayName(_ entry: FileEntry) -> String {
        entry.kind == .directory ? "\(entry.name)/" : entry.name
    }

    var cursorBinding: Binding<FileEntry.ID?> {
        Binding(
            get: { model.state.cursor },
            set: { clicked in
                // The setter only fires from the Table's own interaction
                // — a click — so focus follows it, and the modifiers
                // carry Finder's selection manners: shift extends from
                // the cursor, ⌘ or ⌥ toggles one row. Keyed moves write
                // the state directly and never pass through here.
                // NSEvent.modifierFlags (the class property, live hardware
                // state) — NOT NSApp.currentEvent: the Table delivers this
                // set AFTER the click event has passed, so currentEvent's
                // flags read empty and shift-click degraded to a plain
                // click (round 9: 'I cant shift selecet').
                let flags = NSEvent.modifierFlags
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
    static func sizeText(_ size: Int64) -> String {
        size.formatted(.byteCount(style: .file, spellsOutZero: false))
    }
}
