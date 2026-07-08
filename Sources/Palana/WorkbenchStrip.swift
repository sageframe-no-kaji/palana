// The tools strip — read-only buttons on the plan panel's trailing edge.
// One button per verb, aimed at the focused pane's host, dropping raw
// output into the transcript. Dims while an operation owns the terminal;
// a subtle accent bar brightens while the terminal holds keyboard focus.

import PalanaCore
import SwiftUI

/// A narrow vertical column of Workbench read verbs pinned to the plan
/// panel's trailing edge.
struct WorkbenchStrip: View {
    /// The root session — verbs, focus flag, operation state.
    var session: PalanaSession

    /// Cached availabilities for the focused host — refreshed when the host changes.
    @State private var availabilities: [String: VerbAvailability] = [:]

    private var focusedHost: String? { session.focusedPane.state.host }
    private var terminalBusy: Bool { session.operation.terminalBusy }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(session.readsTool.verbs, id: \.id) { verb in
                verbButton(verb)
            }
        }
        .frame(width: 100)
        .padding(.vertical, 4)
        .background(Theme.panelGround)
        .overlay(alignment: .leading) {
            // Accent bar on the leading edge — the quiet focus cue.
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 2)
                .opacity(session.terminalFocused ? 0.65 : 0)
                .animation(.easeInOut(duration: 0.12), value: session.terminalFocused)
        }
        .task(id: focusedHost ?? "") {
            await refreshAvailabilities()
        }
    }

    @ViewBuilder
    private func verbButton(_ verb: WorkbenchVerb) -> some View {
        let avail = resolvedAvailability(for: verb)
        let enabled = !terminalBusy && avail == .available
        Button {
            session.runWorkbenchVerb(verb)
        } label: {
            Text(verb.label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint)
        .help(helpText(for: verb, avail: avail))
        .disabled(!enabled)
    }

    private func resolvedAvailability(for verb: WorkbenchVerb) -> VerbAvailability {
        // Local honesty: zfs verbs are not applicable on this Mac. AT-01's
        // .zfs evaluation returns "not yet probed" for nil facts, but the
        // local host is never probed — "not yet probed" misreads the truth.
        guard verb.requirement != .zfs || focusedHost != PalanaCore.localHostName else {
            return .unmet("no zfs on this Mac")
        }
        return availabilities[verb.id] ?? .available
    }

    private func helpText(for verb: WorkbenchVerb, avail: VerbAvailability) -> String {
        guard !terminalBusy else { return "\(verb.label) — terminal busy" }
        if case .unmet(let reason) = avail { return reason }
        return "\(verb.label) on \(focusedHost ?? "—")"
    }

    private func refreshAvailabilities() async {
        guard let host = focusedHost else { return }
        for verb in session.readsTool.verbs {
            availabilities[verb.id] = await session.workbench.availability(of: verb, on: host)
        }
    }
}
