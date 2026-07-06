// The field overlay — the topology card. FieldViewModel is the thin
// @Observable wrapper over FieldOutline; FieldOverlay is the pure
// SwiftUI surface over it. f summons, j/k/l/h navigate, r reprobes,
// Enter points, esc and f again dismiss. Decision 1 chose an in-window
// overlay deliberately — no NSPanel, no sheet.

import PalanaCore
import SwiftUI

// MARK: - FieldViewModel

/// The topology overlay's view model.
///
/// Thin shell over `FieldOutline` — holds the outline and in-flight
/// probe state, delegates every transition to the outline's mutations.
/// The session owns one instance; the view reads it.
@MainActor
@Observable
final class FieldViewModel {
    /// The rendered display model — nil until `summon(hosts:)` first runs.
    private(set) var outline: FieldOutline?
    /// Hosts with a probe in flight — the row renders "probing…".
    private(set) var probing: Set<String> = []
    /// Error detail per host from a thrown probe — cleared on the next reprobe.
    private(set) var probeErrors: [String: String] = [:]

    private let engine: Engine

    /// A view model over the session's engine.
    init(engine: Engine) {
        self.engine = engine
    }

    /// Reads `allFacts()` and builds the outline — a cache read, no wire.
    ///
    /// The local host leads the list. Calling while visible refreshes
    /// the outline from the current cache state.
    func summon(hosts: [String]) {
        Task {
            let localHost = Engine.localHost
            var ordered = [localHost]
            ordered += hosts.filter { $0 != localHost }
            let facts = await engine.field.allFacts()
            outline = FieldOutline(hosts: ordered, facts: facts, localHost: localHost)
        }
    }

    /// Moves the cursor one row toward the end.
    func cursorDown() { outline?.cursorDown() }

    /// Moves the cursor one row toward the top.
    func cursorUp() { outline?.cursorUp() }

    /// Expands the host row under the cursor.
    func expand() { outline?.expand() }

    /// Collapses the host under the cursor, or its host when on a dataset.
    func collapse() { outline?.collapse() }

    /// Toggles the expansion of the host row under the cursor.
    func toggleExpansion() { outline?.toggleExpansion() }

    /// Moves the cursor to the given index — for mouse interaction.
    func moveCursor(to index: Int) { outline?.moveCursor(to: index) }

    /// Resolves the cursor's pointing target — nil for non-pointable rows.
    func pointing() -> FieldOutline.Pointing? { outline?.pointing() }

    /// Reprobes the host under the cursor — no-op for local or in-flight hosts.
    ///
    /// The row shows "probing…" while the probe runs, then the fresh
    /// verdict and a young age.
    func reprobe() {
        guard let host = outline?.hostUnderCursor() else { return }
        guard host != Engine.localHost else { return }
        guard !probing.contains(host) else { return }
        probing.insert(host)
        probeErrors.removeValue(forKey: host)
        Task {
            do {
                try await engine.field.discover(host)
            } catch {
                probeErrors[host] = Self.describe(error)
            }
            probing.remove(host)
            let newFacts = await engine.field.allFacts()
            outline?.update(facts: newFacts)
        }
    }

    /// One quiet sentence for the card — the pane's error voice.
    ///
    /// `discover` records unreachability as a fact, so the only throw
    /// that reaches here is the probe answering unreadably.
    private static func describe(_ error: any Error) -> String {
        if error is ProbeParseError {
            return "answered, but the probe came back unreadable"
        }
        return "\(error)"
    }
}

// MARK: - FieldOverlay

/// The topology overlay card — centered over the panes, panes dimmed beneath.
struct FieldOverlay: View {
    /// The view model driving this card.
    let viewModel: FieldViewModel
    /// Called when the operator double-clicks a row that resolves a pointing.
    let onPoint: (FieldOutline.Pointing) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader
            Divider().opacity(0.35)
            linesArea
            Divider().opacity(0.35)
            cardFooter
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
    }

    private var cardHeader: some View {
        Text("the field")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.inkFaint)
    }

    private var linesArea: some View {
        // Scroll-follow, the first hands session's first finding — the
        // cursor never walks below the fold unseen.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let outline = viewModel.outline {
                        ForEach(outline.lines.indices, id: \.self) { i in
                            fieldRow(outline.lines[i], index: i, isCursor: i == outline.cursor)
                                .id(i)
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .onChange(of: viewModel.outline?.cursor) { _, cursor in
                guard let cursor else { return }
                proxy.scrollTo(cursor)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ line: FieldOutline.Line, index: Int, isCursor: Bool) -> some View {
        switch line {
        case .host(let hl):
            hostRow(hl, index: index, isCursor: isCursor)
        case .dataset(let dl):
            datasetRow(dl, index: index, isCursor: isCursor)
        }
    }

    private func hostRow(_ hl: FieldOutline.HostLine, index: Int, isCursor: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            disclosureTriangle(hl, index: index)
            Text(hl.alias)
                .fontWeight(.medium)
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 80, alignment: .leading)
            hostVerdict(hl)
            Spacer()
            hostTokens(hl)
        }
        .font(.system(size: 12))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(cursorWash(isCursor))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.moveCursor(to: index)
            if let pt = viewModel.pointing() { onPoint(pt) }
        }
        .onTapGesture(count: 1) {
            viewModel.moveCursor(to: index)
        }
    }

    /// The disclosure triangle for a host row with datasets, or an invisible
    /// placeholder that keeps the alias column aligned when datasets are absent.
    ///
    /// Sized to be seen and hit — "the little arrow is TINY" (round 3).
    @ViewBuilder
    private func disclosureTriangle(_ hl: FieldOutline.HostLine, index: Int) -> some View {
        if hl.datasetCount > 0 {
            Text(Image(systemName: "chevron.right"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(hl.expanded ? 90 : 0))
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.moveCursor(to: index)
                    viewModel.toggleExpansion()
                }
        } else {
            Text("").frame(width: 18)  // aliases stay in one column
        }
    }

    @ViewBuilder
    private func hostVerdict(_ hl: FieldOutline.HostLine) -> some View {
        if hl.isLocal {
            Text("this machine")
                .foregroundStyle(Theme.inkFaint)
        } else if viewModel.probing.contains(hl.alias) {
            Text("probing…")
                .foregroundStyle(Theme.inkFaint)
        } else if let refused = viewModel.probeErrors[hl.alias] {
            Text(refused)
                .foregroundStyle(Theme.alarm)
        } else if !hl.visited {
            Text("never visited")
                .foregroundStyle(Theme.inkFaint)
        } else if let reachability = hl.reachability {
            switch reachability {
            case .reachable:
                reachableText(hl)
            case .unreachable(let detail):
                Text("unreachable · \(Self.plainRefusal(detail))")
                    .foregroundStyle(Theme.alarm)
            }
        }
    }

    /// The key-shaped refusal in plain language — "what if someone
    /// doesn't have ssh keypairs set up correctly?" (third session).
    /// ho-9.5's onboarding walks the fix; until then the map names it.
    static func plainRefusal(_ detail: String) -> String {
        guard detail.localizedCaseInsensitiveContains("permission denied") else { return detail }
        return "no usable ssh key — key setup needed · \(detail)"
    }

    @ViewBuilder
    private func reachableText(_ hl: FieldOutline.HostLine) -> some View {
        if let date = hl.rememberedAt {
            Text("reachable · \(FieldAge.describe(date, now: Date()))")
                .foregroundStyle(Theme.inkFaint)
        } else {
            Text("reachable")
                .foregroundStyle(Theme.inkFaint)
        }
    }

    @ViewBuilder
    private func hostTokens(_ hl: FieldOutline.HostLine) -> some View {
        if !hl.isLocal {
            HStack(spacing: 4) {
                if let flavor = hl.flavor {
                    Text(flavor.rawValue)
                        .foregroundStyle(Theme.inkFaint)
                }
                if hl.hasZFS { Text("zfs").foregroundStyle(Theme.inkFaint) }
                if hl.hasRsync { Text("rsync").foregroundStyle(Theme.inkFaint) }
                if hl.datasetCount > 0 {
                    // The cue that l has something to expand.
                    Text("\(hl.datasetCount) datasets")
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .font(.system(size: 11))
        }
    }

    private func datasetRow(_ dl: FieldOutline.DatasetLine, index: Int, isCursor: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            datasetDisclosureTriangle(dl, index: index)
            Text(dl.name)
                .foregroundStyle(dl.pointable ? Theme.ink : Theme.inkFaint)
            Text(dl.mountpoint)
                .foregroundStyle(Theme.inkFaint)
            Spacer()
        }
        .font(.system(size: 12))
        .opacity(dl.pointable ? 1.0 : 0.6)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        // Depth-based indent: each level adds 14pt; base alignment comes
        // from the horizontal padding and the 18pt chevron placeholder.
        .padding(.leading, CGFloat(dl.depth) * 14)
        .background(cursorWash(isCursor))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            viewModel.moveCursor(to: index)
            if let pt = viewModel.pointing() { onPoint(pt) }
        }
        .onTapGesture(count: 1) {
            viewModel.moveCursor(to: index)
        }
    }

    /// The disclosure chevron for a dataset row with children, or an invisible
    /// placeholder that keeps the name column aligned for leaf rows.
    ///
    /// Same accent-colored, rotating treatment as the host row's chevron —
    /// 18pt frame so the hit target is findable.
    @ViewBuilder
    private func datasetDisclosureTriangle(_ dl: FieldOutline.DatasetLine, index: Int) -> some View {
        if dl.childCount > 0 {
            Text(Image(systemName: "chevron.right"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .rotationEffect(.degrees(dl.expanded ? 90 : 0))
                .frame(width: 18, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.moveCursor(to: index)
                    viewModel.toggleExpansion()
                }
        } else {
            Text("").frame(width: 18)  // leaf — placeholder keeps name in column
        }
    }

    private func cursorWash(_ isCursor: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent.opacity(isCursor ? 0.18 : 0))
            .padding(.horizontal, -6)
    }

    private var cardFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("↵ / dbl-click point  ·  l toggle  ·  r re-probe  ·  esc dismiss")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text("~ is the remote user's home  ·  grey = unmounted, not a place")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
