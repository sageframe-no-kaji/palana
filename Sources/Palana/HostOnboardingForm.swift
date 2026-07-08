// The guided add-a-host form and the per-host remove confirmation.
// All config writes route through SettingsModel's backup-then-write-then-reload
// path — nothing here touches the file directly.
//
// Key-setup guidance composes and displays `ssh-keygen` / `ssh-copy-id`
// commands as copyable text — it does not execute them. Decision 4 leaves
// running-it to the hands session.
//
// Focus discipline: every TextField releases on focus loss via
// `.onExitCommand { focused = false }` — the same pattern the rsync flags
// field uses so focus is never hoarded.

import PalanaCore
import SwiftUI

// MARK: - OnboardingProbeOutcome

/// The typed outcome of a first-reach probe after a successful add.
enum OnboardingProbeOutcome {
    /// The host is up and the key works.
    case connected
    /// The host answered but refused the key.
    case authDenied(detail: String)
    /// The host could not be reached.
    case unreachable(detail: String)
}

// MARK: - HostAddForm

/// The inline guided add-a-host form.
///
/// Builds a ``HostBlock`` from free-text fields, runs ``HostBlock/validate()``
/// to surface field-named errors, shows the composed block, and requires a
/// confirm before calling ``SettingsModel/addHost(_:)``. After a successful
/// write the form offers (but does not force) a first-reach probe.
struct HostAddForm: View {
    @Bindable var model: SettingsModel
    var session: PalanaSession

    @State private var alias = ""
    @State private var hostName = ""
    @State private var user = ""
    @State private var portText = ""
    @State private var identityFile = ""

    @State private var validationErrors: [HostBlockError] = []
    @State private var composedBlock: String?
    @State private var writeError: String?
    @State private var probeState: ProbeState = .idle

    @FocusState private var aliasFocused: Bool
    @FocusState private var hostNameFocused: Bool
    @FocusState private var userFocused: Bool
    @FocusState private var portFocused: Bool
    @FocusState private var identityFileFocused: Bool

    private enum ProbeState {
        case idle
        case probing
        case done(OnboardingProbeOutcome)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            formFields
            if !validationErrors.isEmpty {
                validationSummary
            }
            if let block = composedBlock {
                composedBlockView(block)
            }
            if let err = writeError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
            }
            formButtons
            probeSection
        }
        .onChange(of: aliasFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
        .onChange(of: hostNameFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
        .onChange(of: userFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
        .onChange(of: portFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
        .onChange(of: identityFileFocused) { _, focused in
            session.settingsFieldFocused = focused
        }
    }

    // MARK: - Fields

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldRow(
                label: "alias",
                placeholder: "mybox",
                text: $alias,
                isFocused: $aliasFocused,
                hasError: validationErrors.contains {
                    $0 == .aliasEmpty || $0 == .aliasContainsWhitespace || $0 == .aliasIsWildcard
                }
            )
            fieldRow(
                label: "hostname",
                placeholder: "192.168.1.50 or host.example.com",
                text: $hostName,
                isFocused: $hostNameFocused,
                hasError: validationErrors.contains { $0 == .hostNameEmpty }
            )
            fieldRow(
                label: "user",
                placeholder: "optional",
                text: $user,
                isFocused: $userFocused,
                hasError: false
            )
            fieldRow(
                label: "port",
                placeholder: "optional — default 22",
                text: $portText,
                isFocused: $portFocused,
                hasError: validationErrors.contains {
                    if case .portOutOfRange = $0 { return true }
                    return false
                }
            )
            fieldRow(
                label: "identity",
                placeholder: "optional — e.g. ~/.ssh/id_ed25519",
                text: $identityFile,
                isFocused: $identityFileFocused,
                hasError: false
            )
        }
    }

    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        hasError: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .frame(width: 52, alignment: .trailing)
                .font(.system(size: 11))
                .foregroundStyle(hasError ? Theme.alarm : Theme.inkFaint)
            TextField(placeholder, text: text)
                .font(.system(size: 12, design: .monospaced))
                .focused(isFocused)
                .onExitCommand { isFocused.wrappedValue = false }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(hasError ? Theme.alarm.opacity(0.6) : Color.clear, lineWidth: 1)
                )
        }
    }

    // MARK: - Validation summary

    private var validationSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(validationErrors.enumerated()), id: \.offset) { _, error in
                Text("· \(describe(error))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
            }
        }
        .padding(.leading, 60)
    }

    private func describe(_ error: HostBlockError) -> String {
        switch error {
        case .aliasEmpty: "alias is required"
        case .aliasContainsWhitespace: "alias must be a single word — no spaces"
        case .aliasIsWildcard: "alias cannot contain * ? ! — those are ssh matching patterns"
        case .hostNameEmpty: "hostname is required"
        case .portOutOfRange(let port): "port \(port) is out of range — must be 1–65535"
        }
    }

    // MARK: - Composed block preview

    private func composedBlockView(_ block: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("block that will be written:")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text(block)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.groundDeep)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Buttons

    private var formButtons: some View {
        HStack(spacing: 8) {
            if composedBlock == nil {
                Button("compose") {
                    runValidateAndCompose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
            } else {
                Button("confirm — write to config") {
                    runWrite()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                Button("back") {
                    composedBlock = nil
                    writeError = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
            }
            Button("cancel") {
                resetForm()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkFaint)
        }
    }

    // MARK: - Probe section

    @ViewBuilder private var probeSection: some View {
        switch probeState {
        case .idle:
            EmptyView()
        case .probing:
            Text("probing \(alias)…")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        case .done(let outcome):
            probeResult(outcome)
        }
    }

    @ViewBuilder
    private func probeResult(_ outcome: OnboardingProbeOutcome) -> some View {
        switch outcome {
        case .connected:
            Text("\(alias) is reachable — key works")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
        case .unreachable(let detail):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(alias) is not reachable — \(detail)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
                Text("the host may be down or the address may be wrong")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
        case .authDenied:
            KeySetupGuidanceView(alias: alias)
        }
    }

    // MARK: - Actions

    private func runValidateAndCompose() {
        writeError = nil
        let port = portText.isEmpty ? nil : Int(portText)
        let block = HostBlock(
            alias: alias,
            hostName: hostName,
            user: user.isEmpty ? nil : user,
            port: port,
            identityFile: identityFile.isEmpty ? nil : identityFile
        )
        // Non-numeric port text that isn't empty is a port error.
        var errors = block.validate()
        if !portText.isEmpty, Int(portText) == nil {
            errors.append(.portOutOfRange(0))
        }
        validationErrors = errors
        guard errors.isEmpty else {
            composedBlock = nil
            return
        }
        composedBlock = block.compose()
    }

    private func runWrite() {
        guard composedBlock != nil else { return }
        let port = portText.isEmpty ? nil : Int(portText)
        let block = HostBlock(
            alias: alias,
            hostName: hostName,
            user: user.isEmpty ? nil : user,
            port: port,
            identityFile: identityFile.isEmpty ? nil : identityFile
        )
        if let reason = model.addHost(block) {
            writeError = reason
            composedBlock = nil
            return
        }
        // Write succeeded — offer first-reach probe.
        let addedAlias = alias
        resetForm()
        probeState = .probing
        Task {
            let outcome = await session.probeHost(alias: addedAlias)
            probeState = .done(outcome)
        }
    }

    private func resetForm() {
        alias = ""
        hostName = ""
        user = ""
        portText = ""
        identityFile = ""
        validationErrors = []
        composedBlock = nil
        writeError = nil
        aliasFocused = false
        hostNameFocused = false
        userFocused = false
        portFocused = false
        identityFileFocused = false
    }
}

// MARK: - KeySetupGuidanceView

/// Inline key-setup guidance — shown when a first-reach probe returns auth denied.
///
/// Shows the exact commands composed against the new alias as copyable text and
/// links to the companion guide. Does not execute any command — Decision 4 leaves
/// running-it to the hands session.
struct KeySetupGuidanceView: View {
    /// The alias that was just added and failed the auth check.
    var alias: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("no usable ssh key — key setup needed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.alarm)
            Text("generate a key (if you don't have one yet):")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            CopyableCommandView(command: "ssh-keygen -t ed25519")
            Text("then install it on \(alias):")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            CopyableCommandView(command: "ssh-copy-id \(alias)")
            Text("the \(alias) block is written — run these in your terminal, then probe again.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            // TODO: firm up the deep-link target when the guide ships.
            if let guideURL = URL(string: "https://ssh-actually.sageframe.net") {
                Link("key setup guide →", destination: guideURL)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(8)
        .background(Theme.groundDeep)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - CopyableCommandView

/// A monospaced command line with a copy-to-clipboard button.
struct CopyableCommandView: View {
    var command: String

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.inkFaint)
            }
            .buttonStyle(.plain)
            .help("copy")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.ground)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - HostRemoveConfirmation

/// The inline remove-confirmation panel for a single host alias.
///
/// Shows the block that will be stripped, requires a confirm, then calls
/// ``SettingsModel/removeHost(alias:)``. This is the "truly remove" action —
/// distinct from the hide toggle which only curtains.
struct HostRemoveConfirmation: View {
    @Bindable var model: SettingsModel
    var alias: String
    var onDismiss: () -> Void

    @State private var writeError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("remove \(alias)?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
            blockPreview
            if let err = writeError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
            }
            actions
        }
        .padding(10)
        .background(Theme.groundDeep)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var blockPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("block that will be stripped:")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text(blockText)
                .font(.system(size: 11, design: .monospaced))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.ground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var blockText: String {
        // Read the block from the live config text so what is shown is
        // exactly what will be removed.
        let lines = model.configText.components(separatedBy: "\n")
        var inBlock = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if inBlock { collected.append(line) }
                continue
            }
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tokens.first?.lowercased() == "host" {
                if inBlock { break }
                if tokens.dropFirst().contains(alias) {
                    inBlock = true
                    collected.append(line)
                }
            } else if inBlock {
                collected.append(line)
            }
        }
        return collected.isEmpty
            ? "Host \(alias)\n    (block not found in top-level config)"
            : collected.joined(separator: "\n")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("remove — write to config") {
                if let reason = model.removeHost(alias: alias) {
                    writeError = reason
                } else {
                    onDismiss()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.alarm)
            Button("cancel") {
                onDismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkFaint)
        }
    }
}
