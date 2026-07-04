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
                            fieldRow(outline.lines[i], isCursor: i == outline.cursor)
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
    private func fieldRow(_ line: FieldOutline.Line, isCursor: Bool) -> some View {
        switch line {
        case .host(let hl):
            hostRow(hl, isCursor: isCursor)
        case .dataset(let dl):
            datasetRow(dl, isCursor: isCursor)
        }
    }

    private func hostRow(_ hl: FieldOutline.HostLine, isCursor: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
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
                Text("unreachable · \(detail)")
                    .foregroundStyle(Theme.alarm)
            }
        }
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

    private func datasetRow(_ dl: FieldOutline.DatasetLine, isCursor: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(dl.name)
                .foregroundStyle(dl.pointable ? Theme.ink : Theme.inkFaint)
                .padding(.leading, 20)
            Text(dl.mountpoint)
                .foregroundStyle(Theme.inkFaint)
            Spacer()
        }
        .font(.system(size: 12))
        .opacity(dl.pointable ? 1.0 : 0.6)
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(cursorWash(isCursor))
    }

    private func cursorWash(_ isCursor: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent.opacity(isCursor ? 0.18 : 0))
            .padding(.horizontal, -6)
    }

    private var cardFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("↵ point  ·  l expand  ·  r re-probe  ·  esc dismiss")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text("~ is the remote user's home")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
