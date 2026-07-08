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
            VStack(spacing: 0) {
                ForEach(session.readsTool.verbs, id: \.id) { verb in
                    Rectangle()
                        .fill(Theme.inkFaint.opacity(0.18))
                        .frame(height: 1)
                    chip(verb)
                }
                Rectangle()
                    .fill(Theme.inkFaint.opacity(0.18))
                    .frame(height: 1)
            }
            .background(Theme.ground)
            Spacer(minLength: 0)
        }
        .frame(width: 108)
        .frame(maxHeight: .infinity)
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

    private func chip(_ verb: WorkbenchVerb) -> some View {
        let avail = resolvedAvailability(for: verb)
        return StripChip(
            label: verb.label,
            keyHint: verb.keyHint,
            enabled: !terminalBusy && avail == .available,
            showKey: session.terminalFocused,
            help: helpText(for: verb, avail: avail)
        ) { session.runWorkbenchVerb(verb) }
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

/// One read chip — a uniform cell that highlights on hover, its key hint set
/// bigger and spaced like a menu shortcut, shown only while engaged.
private struct StripChip: View {
    let label: String
    let keyHint: String
    let enabled: Bool
    let showKey: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 28)
                .overlay(alignment: .trailing) {
                    if showKey {
                        Text(keyHint)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                    }
                }
                .background(hovering && enabled ? Theme.accent.opacity(0.10) : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.ink : Theme.inkFaint)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(help)
        .disabled(!enabled)
    }
}
