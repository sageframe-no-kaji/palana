// One pane — a header naming where it points, a Table over the rows,
// and quiet in-place lines for the unpointed, loading, and failed
// states. The Table's selection binding is the cursor; the selection
// set renders as accent marks. The register is the notebook: no
// chrome, one accent, directories by weight and a trailing slash.

import PalanaCore
import SwiftUI

/// One pane of the two.
struct PaneView: View {
    /// The pane's model.
    let model: PaneModel
    /// Whether the keyboard drives this pane.
    let isFocused: Bool
    /// Called when a click lands here — focus follows.
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Theme.ground)
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isFocused ? Theme.accent : Theme.inkFaint.opacity(0.25))
                .frame(width: 7, height: 7)
            if let host = model.state.host {
                Text(host)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                Text(model.state.path)
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("nowhere")
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.groundDeep)
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .unpointed:
            quietLine("⇧⌘G points this pane")
        case .loading:
            quietLine("reading…")
        case .failed(let why):
            quietLine(why)
        case .ready:
            table
        }
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
        Table(model.rows, selection: cursorBinding) {
            TableColumn("name") { entry in
                nameCell(entry)
            }
            TableColumn("size") { entry in
                Text(entry.kind == .directory ? "—" : Self.sizeText(entry.size))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80, max: 110)
            TableColumn("modified") { entry in
                Text(entry.modified.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(Theme.inkFaint)
            }
            .width(min: 110, ideal: 150, max: 190)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .tint(Theme.accent)
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

    /// Sizes as facts — `0 bytes`, never `Zero kB`.
    private static func sizeText(_ size: Int64) -> String {
        size.formatted(.byteCount(style: .file, spellsOutZero: false))
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
        }
    }

    private func displayName(_ entry: FileEntry) -> String {
        entry.kind == .directory ? "\(entry.name)/" : entry.name
    }

    private var cursorBinding: Binding<FileEntry.ID?> {
        Binding(
            get: { model.state.cursor },
            set: {
                // The setter only fires from the Table's own interaction
                // — a click — so focus follows it. Keyed moves write the
                // state directly and never pass through here.
                model.state.cursor = $0
                onFocus()
            })
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
