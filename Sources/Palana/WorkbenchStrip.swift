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
            ForEach(Array(session.readsTool.verbs.enumerated()), id: \.element.id) { index, verb in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.inkFaint.opacity(0.18))
                        .frame(height: 1)
                }
                verbButton(verb)
            }
        }
        .frame(width: 96)
        .background(Theme.ground)
        .overlay(alignment: .leading) {
            // The shared left separator — a hairline against the transcript,
            // and the accent focus cue when the terminal holds the keyboard.
            Rectangle()
                .fill(session.terminalFocused ? Theme.accent : Theme.inkFaint.opacity(0.18))
                .frame(width: session.terminalFocused ? 2 : 1)
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint)
        .opacity(enabled ? 1 : 0.5)
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
