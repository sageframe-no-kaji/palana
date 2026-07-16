// The settings card and the shared form — ⌘, and the gear summon the
// card; the Apple Settings scene renders SettingsForm directly. One
// SettingsModel instance, two surfaces, one truth.
//
// Card pattern: ZStack with a dimmed ground and a centred card,
// mirroring FieldOverlay. Esc dismisses; the grammar stands down while
// the flags field is focused. First Esc defocuses the field via
// .onExitCommand; second Esc reaches handleSettingsKey and closes.

import SwiftUI

// MARK: - SettingsForm

/// The shared settings form — two sections over one SettingsModel.
///
/// Rendered by `SettingsCard` inside the card chrome and by the Apple
/// Settings scene directly. Holds the `FocusState` for the rsync flags
/// field and wires the key-monitor stand-down flag on the session.
struct SettingsForm: View {
    /// The settings model — hosts, rsync flags, exclude flags, and config write verbs.
    @Bindable var model: SettingsModel
    /// The session — receives the field-focused stand-down signal.
    var session: PalanaSession

    /// The appearance override — bound to the same key the window root reads
    /// (ho-15), so flipping it here recolors the whole surface at once.
    @AppStorage(AppAppearance.storageKey)
    private var appearance: AppAppearance = .system

    @FocusState private var flagsFocused: Bool
    @State private var hostHelpShowing = false
    @State private var configViewShowing = false
    @State private var addFormShowing = false
    @State private var removingAlias: String?

    /// The alias just successfully added — used to scroll-to and flash it.
    @State private var flashAlias: String?
    /// Controls the highlight wash opacity for the newly added host.
    @State private var flashOpacity: Double = 0

    /// Brief "Added ✓ alias" confirmation shown in the footer after a write.
    @State private var addedConfirmation: String?

    /// Probe state — persists after the form closes so the result is visible.
    @State private var probeAlias: String?
    @State private var probeState: ProbeState = .idle

    private enum ProbeState {
        case idle
        case probing
        case done(OnboardingProbeOutcome)
    }

    /// Hosts sorted: visible hosts keep ssh-config order; hidden hosts sink to the bottom.
    ///
    /// The scroll-to and flash rely on this stable ordering.
    private var sortedHostEntries: [(alias: String, isHidden: Bool)] {
        let all = model.allHostEntries
        let visible = all.filter { !$0.isHidden }
        let hidden = all.filter { $0.isHidden }
        return visible + hidden
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hostsSection
            Divider().opacity(0.35)
            transfersSection
            Divider().opacity(0.35)
            workbenchSection
            Divider().opacity(0.35)
            appearanceSection
        }
        .onChange(of: flagsFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
    }

    // MARK: - Hosts

    private var hostsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hosts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sortedHostEntries, id: \.alias) { entry in
                            hostRow(entry)
                                .background(
                                    // Flash highlight — accent wash that fades
                                    flashAlias == entry.alias
                                        ? Theme.accent.opacity(flashOpacity * 0.18)
                                        : Color.clear
                                )
                                .id(entry.alias)
                            if removingAlias == entry.alias {
                                HostRemoveConfirmation(
                                    model: model,
                                    alias: entry.alias
                                ) {
                                    removingAlias = nil
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                .onChange(of: flashAlias) { _, alias in
                    guard let alias else { return }
                    // Scroll to the new host and trigger the flash.
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(alias, anchor: .center)
                    }
                    // Fade the accent wash in then out.
                    flashOpacity = 1.0
                    withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
                        flashOpacity = 0
                    }
                }
            }
            if let notice = model.includedFileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
                    .padding(.leading, 8)
            }
            if addFormShowing {
                HostAddForm(
                    model: model,
                    session: session,
                    onAdded: { alias in
                        addFormShowing = false
                        addedConfirmation = "Added ✓ \(alias)"
                        flashAlias = alias
                        // Clear confirmation after a beat.
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            addedConfirmation = nil
                        }
                        // Clear flash alias so repeated adds re-trigger the flash.
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            flashAlias = nil
                        }
                        // First-reach probe.
                        probeAlias = alias
                        probeState = .probing
                        Task {
                            let outcome = await session.probeHost(alias: alias)
                            probeState = .done(outcome)
                        }
                    },
                    onCancel: {
                        addFormShowing = false
                    }
                )
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
            hostsFooter
            probeSection
        }
    }

    private func hostRow(_ entry: (alias: String, isHidden: Bool)) -> some View {
        HStack {
            Text(entry.alias)
                .font(.system(size: 14))
                .foregroundStyle(entry.isHidden ? Theme.inkFaint : Theme.ink)
            Spacer()
            // Remove affordance — distinct from the hide toggle.
            // Shows the block it will strip and confirms before writing.
            Button {
                removingAlias = removingAlias == entry.alias ? nil : entry.alias
            } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        removingAlias == entry.alias ? Theme.alarm : Theme.inkFaint.opacity(0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("remove this host from ~/.ssh/config")
            Toggle(
                "",
                isOn: Binding(
                    get: { !entry.isHidden },
                    set: { visible in model.setHidden(!visible, alias: entry.alias) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Footer

    private var hostsFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Added confirmation — shown briefly after a successful write.
            if let confirmation = addedConfirmation {
                Text(confirmation)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
            }
            // Base footer — only shown when the add form is closed.
            if !addFormShowing {
                HStack(spacing: 10) {
                    Button("Add a host") {
                        addFormShowing = true
                        removingAlias = nil
                        probeState = .idle
                        probeAlias = nil
                        addedConfirmation = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .font(.system(size: 12, weight: .medium))
                    .controlSize(.regular)
                    Button("View config") {
                        configViewShowing.toggle()
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .controlSize(.small)
                    .popover(isPresented: $configViewShowing, arrowEdge: .bottom) {
                        SSHConfigViewer(configText: model.configText)
                    }
                    Button("Reload hosts") {
                        session.reloadHosts()
                        model.refreshConfigText()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkFaint)
                    .controlSize(.small)
                    Button {
                        hostHelpShowing.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $hostHelpShowing, arrowEdge: .bottom) {
                        hostHelp
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    /// Probe section — shown after a successful add (below the footer).
    @ViewBuilder private var probeSection: some View {
        switch probeState {
        case .idle:
            EmptyView()
        case .probing:
            Text("probing \(probeAlias ?? "")…")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
                .padding(.horizontal, 8)
        case .done(let outcome):
            probeResult(outcome)
                .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func probeResult(_ outcome: OnboardingProbeOutcome) -> some View {
        let name = probeAlias ?? ""
        switch outcome {
        case .connected:
            Text("\(name) is reachable — key works")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        case .unreachable(let detail):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) is not reachable — \(detail)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
                Text("the host may be down or the address may be wrong")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
        case .authDenied:
            KeySetupGuidanceView(alias: name)
        }
    }

    // MARK: - Help popover

    /// What ~/.ssh/config is and the block that makes a host.
    private var hostHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("pālana's hosts are your ssh hosts — the same file your terminal uses.")
                .font(.system(size: 11))
            Text("Use \"Add a host\" above, or add a block directly to ~/.ssh/config:")
                .font(.system(size: 11))
            Text("Host mybox\n    HostName 192.168.1.50\n    User me")
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Theme.groundDeep)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("The − button removes a host's block from the file. The toggle hides it without removing.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Divider().opacity(0.3)
            Button("Edit ~/.ssh/config externally") {
                let configPath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".ssh/config")
                NSWorkspace.shared.open(configPath)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(Theme.accent)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }
}

// MARK: - Transfers section

extension SettingsForm {
    var transfersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transfers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Toggle("skip .DS_Store", isOn: $model.excludeDSStore)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .tint(Theme.accent)
                .font(.system(size: 12))
            Toggle("skip AppleDouble files (._*)", isOn: $model.excludeAppleDouble)
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .tint(Theme.accent)
                .font(.system(size: 12))
            Divider().opacity(0.25)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("ask before sending saved edits back", isOn: $model.askBeforeSendingBack)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .font(.system(size: 12))
                Text("off: save is save — edits go back to the server on their own")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 2)
            }
            HStack(spacing: 8) {
                Text("more flags")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                TextField("e.g. --checksum", text: $model.rsyncFlags)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($flagsFocused)
                    .onExitCommand { flagsFocused = false }
            }
            Text("always on: -a, --partial resume · progress when the rsync speaks it")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 8)
        }
    }
}

// MARK: - Appearance section

extension SettingsForm {
    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Appearance")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Picker("", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("System follows the Mac; Light and Dark override it.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
                .padding(.leading, 2)
        }
    }
}

// MARK: - Workbench section

extension SettingsForm {
    var workbenchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workbench")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("zfs destroy asks you to type it", isOn: $model.confirmDestroyTyped)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .font(.system(size: 12))
                Text("on: the word destroy arms the verb · off: Enter shows the plan directly")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - SettingsCard

/// The in-window settings card — dimmed ground, centred panel, Esc dismisses.
///
/// Mirrors the `FieldOverlay` card pattern. Contains `SettingsForm` so
/// the card and the Apple Settings scene render the same controls.
struct SettingsCard: View {
    /// The settings model — hosts, rsync flags, and config write verbs.
    @Bindable var model: SettingsModel
    /// The session — receives the field-focused stand-down signal.
    var session: PalanaSession

    var body: some View {
        ZStack {
            // The dimming scrim — ink over the world, the design system's
            // depth idiom (§4), so no view spells a raw hue (ho-15).
            Theme.ink.opacity(0.12)
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverlayHeader(title: "settings") { session.settingsVisible = false }
            VStack(alignment: .leading, spacing: 14) {
                SettingsForm(model: model, session: session)
                Divider().opacity(0.35)
                cardFooter
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 6)
        }
        .frame(width: 400)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
    }

    private var cardFooter: some View {
        Text("esc closes")
            .font(.system(size: 10))
            .foregroundStyle(Theme.inkFaint)
    }
}

/// A read-only popover showing the current `~/.ssh/config` contents.
///
/// Monospaced and scrollable, text-selectable but not editable — the
/// external editor (the ⓘ popover's link) is the way to change the file.
struct SSHConfigViewer: View {
    /// The config text to display.
    let configText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("~/.ssh/config")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Divider().opacity(0.4)
            ScrollView([.vertical, .horizontal]) {
                Text(configText.isEmpty ? "(empty)" : configText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(width: 380, height: 260)
            .background(Theme.groundDeep)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(14)
        .frame(width: 410)
    }
}
