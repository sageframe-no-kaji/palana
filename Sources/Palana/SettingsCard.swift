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

    @FocusState private var flagsFocused: Bool
    @State private var hostHelpShowing = false
    @State private var addFormShowing = false
    @State private var removingAlias: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hostsSection
            Divider().opacity(0.35)
            transfersSection
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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.allHostEntries, id: \.alias) { entry in
                        hostRow(entry)
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
            if let notice = model.includedFileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
                    .padding(.leading, 8)
            }
            if addFormShowing {
                HostAddForm(model: model, session: session)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            hostsFooter
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

    private var hostsFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button(addFormShowing ? "cancel add" : "add a host") {
                    addFormShowing.toggle()
                    if !addFormShowing {
                        removingAlias = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(addFormShowing ? Theme.inkFaint : Theme.accent)
                Button("reload hosts") {
                    session.reloadHosts()
                    model.refreshConfigText()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
            }
            HStack(spacing: 4) {
                Text("a Host block in the file is a host in the field")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
                Button {
                    hostHelpShowing.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $hostHelpShowing, arrowEdge: .bottom) {
                    hostHelp
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    /// What ~/.ssh/config is and the block that makes a host.
    private var hostHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("pālana's hosts are your ssh hosts — the same file your terminal uses.")
                .font(.system(size: 11))
            Text("Use \"add a host\" above, or add a block directly to ~/.ssh/config:")
                .font(.system(size: 11))
            Text("Host mybox\n    HostName 192.168.1.50\n    User me")
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .background(Theme.groundDeep)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("The − button removes a host's block from the file. The toggle hides it without removing.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
    }

    // MARK: - Transfers

    private var transfersSection: some View {
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
            Color.black.opacity(0.12)
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader
            Divider().opacity(0.35)
            SettingsForm(model: model, session: session)
            Divider().opacity(0.35)
            cardFooter
        }
        .padding(24)
        .frame(width: 400)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Theme.ink.opacity(0.18), radius: 24, y: 8)
    }

    private var cardHeader: some View {
        Text("settings")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.inkFaint)
    }

    private var cardFooter: some View {
        Text("esc closes")
            .font(.system(size: 10))
            .foregroundStyle(Theme.inkFaint)
    }
}
