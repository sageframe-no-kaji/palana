// The tools strip — verb buttons on the plan panel's trailing edge.
// One button per verb, aimed at the focused pane's host. Read verbs
// drop raw output into the transcript; mutation verbs open a gather.
// Dims while an operation owns the terminal; a subtle accent bar
// brightens while the terminal holds keyboard focus.
//
// The strip is now TWO COLUMNS side by side: a plugins column (burnt
// umber/light orange, solid chips) on the left, then a reads column
// (accent) on the right. Each column scrolls independently, so the
// plugin launcher is always visible even when the plan panel is at
// minimum height. A 1pt hairline separates them.

import PalanaCore
import SwiftUI

/// A narrow two-column strip of Workbench verbs pinned to the plan
/// panel's trailing edge.
///
/// Left column: plugin launchers (burnt umber / light orange, solid
/// chips with cream text), starting with the ZFS panel opener. Right
/// column: system reads chips (accent styling). Each column scrolls
/// independently. A 1pt hairline divides them.
struct WorkbenchStrip: View {
    /// The root session — verbs, focus flag, operation state.
    var session: PalanaSession

    /// Cached availabilities for the focused host — refreshed when the host changes.
    @State private var availabilities: [String: VerbAvailability] = [:]

    private var focusedHost: String? { session.focusedPane.state.host }
    private var terminalBusy: Bool { session.operation.terminalBusy }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Plugins column — solid burnt-umber chips, cream text
            ScrollView {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.plugin.opacity(0.18))
                        .frame(height: 1)
                    zfsLauncher
                    Rectangle()
                        .fill(Theme.plugin.opacity(0.18))
                        .frame(height: 1)
                }
            }
            .frame(width: 88)
            .frame(maxHeight: .infinity)
            .background(Theme.plugin.opacity(0.05))

            // MARK: Column separator — the reads column's green engagement
            // line lives here, back beside the regular chips (his call).
            Rectangle()
                .fill(session.terminalFocused ? Theme.accent : Theme.inkFaint.opacity(0.18))
                .frame(width: session.terminalFocused ? 2 : 1)
                .frame(maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.12), value: session.terminalFocused)

            // MARK: Reads column
            ScrollView {
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
            }
            .frame(width: 88)
            .frame(maxHeight: .infinity)
            .background(Theme.ground)
        }
        .overlay(alignment: .leading) {
            // The strip's outer edge belongs to the plugins column — its
            // engagement line speaks the plugin hue, not the accent.
            Rectangle()
                .fill(session.terminalFocused ? Theme.plugin : Theme.inkFaint.opacity(0.18))
                .frame(width: session.terminalFocused ? 2 : 1)
                .animation(.easeInOut(duration: 0.12), value: session.terminalFocused)
        }
        .task(id: focusedHost ?? "") {
            await refreshAvailabilities()
        }
    }

    /// The ZFS panel launcher — one chip, key hint "Z", toggles the panel.
    ///
    /// Solid plugin chip: burnt-umber ground, cream text and key hint,
    /// hover slightly lighter.
    private var zfsLauncher: some View {
        PluginChip(
            label: "zfs…",
            keyHint: "Z",
            enabled: !terminalBusy,
            showKey: session.terminalFocused,
            help: "open the zfs panel"
        ) {
            ZFSPanelController.shared.toggle(session: session)
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
        // Refresh only the reads tool verbs — ZFS availability lives in ZFSPanel.
        for verb in session.readsTool.verbs {
            availabilities[verb.id] = await session.workbench.availability(of: verb, on: host)
        }
    }
}

/// One read chip — accent styling, key hint shown while engaged.
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

/// One plugin chip — solid burnt-umber ground, cream text and key hint.
///
/// Solid chips: the label and key hint render in `Theme.ground` (cream)
/// over a `Theme.plugin` fill. Hover brightens the fill slightly via an
/// opacity blend. Disabled chips dim to 0.5. Matches `StripChip`'s
/// shape and dimensions.
private struct PluginChip: View {
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
                            .foregroundStyle(Theme.ground)
                            .padding(.horizontal, 10)
                    }
                }
                // Solid burnt-umber fill; hover adds a white sheen.
                .background(
                    Theme.plugin
                        .overlay(hovering && enabled ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.ground)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(help)
        .disabled(!enabled)
    }
}
