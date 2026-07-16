// PaneView+Preview — the preview pane's content and info card (ho-16).
//
// A pane in preview mode renders what the PreviewController resolved from the
// opposite pane's cursor: scrollable monospace text, a QuickLook view, or an
// info-only card. The info card always renders — from facts already on the
// FileEntry — so the pane is never blank, even for a remote source or an
// unreadable kind. The routing that chose the branch is PalanaCore's tested
// PreviewRouter; this file is the declarative view over its verdict.
//
// The recursive size ◆ (ho-06.5) is not a FileEntry fact — it is measured only
// at plan time — so the card carries the facts pālana already holds on the
// entry. Surfacing a cached recursive size is a follow-up.

import PalanaCore
import SwiftUI

extension PaneView {
    /// The pane's content while in preview mode.
    @ViewBuilder var previewContent: some View {
        switch previewState {
        case .empty:
            quietLine("point the left pane at a file — this pane previews it")
        case .loading(let entry):
            previewLayout(entry) { quietLine("reading…") }
        case .text(let entry, let text):
            previewLayout(entry) { previewText(text) }
        case .quickLook(let entry, let url):
            previewLayout(entry) { QuickLookView(url: url) }
        case .infoOnly(let entry):
            previewLayout(entry) { quietLine("no content preview for this kind") }
        case .remote(let entry):
            previewLayout(entry) { quietLine("binary preview is local-only for now") }
        }
    }

    /// The info card on top, the content below — the card always renders so the
    /// pane is never blank.
    @ViewBuilder
    private func previewLayout(_ entry: FileEntry, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            previewInfoCard(entry)
            Divider().opacity(0.3)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The info card — the facts pālana already holds on the entry.
    private func previewInfoCard(_ entry: FileEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(displayName(entry))
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .textSelection(.enabled)
            infoRow("kind", previewKindLabel(entry))
            if entry.kind == .file {
                infoRow("size", Self.sizeText(entry.size))
            }
            infoRow("modified", PaneColumns.dateText(entry.modified))
            if let created = entry.created {
                infoRow("created", PaneColumns.dateText(created))
            }
            if let changed = entry.changed {
                infoRow("changed", PaneColumns.dateText(changed))
            }
            infoRow("perms", "\(entry.permissions) · \(entry.owner):\(entry.group)")
            if let target = entry.symlinkTargetName {
                infoRow("target", "→ \(target)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.groundDeep)
    }

    /// One label-and-value line of the info card.
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Theme.font(10))
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(Theme.font(11))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The plain word for an entry's kind.
    private func previewKindLabel(_ entry: FileEntry) -> String {
        switch entry.kind {
        case .file: return "file"
        case .directory: return "directory"
        case .symlink: return "symlink"
        case .other: return "other"
        }
    }

    /// The scrollable monospace body for a local text file (design system §3 —
    /// a file's literal content is data truth), with a truncation footer past
    /// the cap.
    private func previewText(_ text: PreviewText) -> some View {
        VStack(spacing: 0) {
            ScrollView([.vertical, .horizontal]) {
                Text(text.text.isEmpty ? "(empty file)" : text.text)
                    .font(Theme.font(12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            if text.truncated {
                Text("… truncated at 256 KB")
                    .font(Theme.font(10))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.groundDeep)
            }
        }
    }
}
