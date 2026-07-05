// The settings card and the shared form — ⌘, and the gear summon the
// card; the Apple Settings scene renders SettingsForm directly. One
// SettingsModel instance, two surfaces, one truth.
//
// Card pattern: ZStack with a dimmed ground and a centred card,
// mirroring FieldOverlay. Esc dismisses; the grammar stands down while
// the flags field is focused.

import SwiftUI

// MARK: - SettingsForm

/// The shared settings form — two sections over one SettingsModel.
///
/// Rendered by `SettingsCard` inside the card chrome and by the Apple
/// Settings scene directly. Holds the `FocusState` for the rsync flags
/// field and wires the key-monitor stand-down flag on the session.
struct SettingsForm: View {
    /// The settings model — hosts, rsync flags, and config write verbs.
    @Bindable var model: SettingsModel
    /// The session — receives the field-focused stand-down signal.
    var session: PalanaSession

    @FocusState private var flagsFocused: Bool

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
                    }
                }
            }
            .frame(maxHeight: 180)
            if let notice = model.includedFileNotice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
                    .padding(.leading, 8)
            }
        }
    }

    private func hostRow(_ entry: (alias: String, isHidden: Bool)) -> some View {
        HStack {
            Text(entry.alias)
                .font(.system(size: 12))
                .foregroundStyle(entry.isHidden ? Theme.inkFaint : Theme.ink)
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { !entry.isHidden },
                    set: { visible in model.setHidden(!visible, alias: entry.alias) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Transfers

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transfers")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            HStack(spacing: 8) {
                Text("rsync flags")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
                TextField("e.g. --exclude .DS_Store", text: $model.rsyncFlags)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($flagsFocused)
            }
            Text("appended to every rsync command")
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
