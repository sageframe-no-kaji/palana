// The guided add-a-host form and the per-host remove confirmation.
// All config writes route through SettingsModel's backup-then-write-then-reload
// path — nothing here touches the file directly.
//
// Key-setup guidance composes and displays `ssh-keygen` / `ssh-copy-id`
// commands as copyable text — it does not execute them. Decision 4 leaves
// running-it to the hands session.
//
// Focus discipline: while the add form is open, `session.settingsFieldFocused`
// is held true for the form's entire lifetime — set on .onAppear, cleared on
// .onDisappear. This ensures the window key monitor stands down for all fields
// throughout the form, including after validation errors. Individual per-field
// onChange hooks are not needed and have been removed.

import AppKit
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
/// Builds a ``HostBlock`` from free-text fields, validates on the fly,
/// shows a LIVE preview of the composed block, and calls
/// ``SettingsModel/addHost(_:)`` on a single "Add host" action. After a
/// successful write the form closes and signals the parent via `onAdded`.
///
/// Focus discipline: `session.settingsFieldFocused` is held `true` for the
/// form's entire lifetime so the window key monitor stands down while any
/// field is active — including after a validation error when SwiftUI may
/// not report individual field focus reliably.
struct HostAddForm: View {
    @Bindable var model: SettingsModel
    var session: PalanaSession
    /// Called on successful write — parent uses this to close the form
    /// and trigger scroll-to + flash on the new host.
    var onAdded: (String) -> Void
    /// Called when the operator cancels — parent closes the form.
    var onCancel: () -> Void

    @State private var alias = ""
    @State private var hostName = ""
    @State private var user = ""
    @State private var portText = ""
    @State private var identityFile = ""

    @State private var validationErrors: [HostBlockError] = []
    @State private var writeError: String?

    @FocusState private var aliasFocused: Bool
    @FocusState private var hostNameFocused: Bool
    @FocusState private var userFocused: Bool
    @FocusState private var portFocused: Bool
    @FocusState private var identityFileFocused: Bool

    // MARK: - Derived

    /// The HostBlock built from current field values (regardless of validity).
    private var currentBlock: HostBlock {
        let port = portText.isEmpty ? nil : Int(portText)
        // Bare filename (no path separator) → ~/.ssh/<name>
        let identity = resolvedIdentityPath(identityFile)
        return HostBlock(
            alias: alias,
            hostName: hostName,
            user: user.isEmpty ? nil : user,
            port: port,
            identityFile: identity
        )
    }

    /// Live validation errors — recomputed on every field change.
    private var liveErrors: [HostBlockError] {
        var errors = currentBlock.validate()
        if !portText.isEmpty, Int(portText) == nil {
            errors.append(.portOutOfRange(0))
        }
        return errors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            formFields
            if !validationErrors.isEmpty {
                validationSummary
            }
            // Live preview — always visible, updates as the operator types.
            livePreviewView
            if let err = writeError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.alarm)
            }
            formButtons
        }
        .onAppear {
            // Hold the key monitor down for the entire form lifetime — prevents
            // the monitor from eating keystrokes even after a validation error
            // when individual field focus state may be unreliable.
            session.settingsFieldFocused = true
        }
        .onDisappear {
            session.settingsFieldFocused = false
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
            identityFieldRow
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

    /// The identity field row — includes a "Browse…" button for picking a key file.
    private var identityFieldRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("identity")
                .frame(width: 52, alignment: .trailing)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
            TextField("optional — e.g. id_ed25519 or ~/.ssh/id_ed25519", text: $identityFile)
                .font(.system(size: 12, design: .monospaced))
                .focused($identityFileFocused)
                .onExitCommand { identityFileFocused = false }
            Button("Browse…") {
                browseForIdentityFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: 11))
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

    // MARK: - Live preview

    private var livePreviewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("block that will be written:")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Text(currentBlock.compose())
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
            Button("Add host") {
                runAddHost()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .font(.system(size: 12, weight: .medium))
            .controlSize(.regular)
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .tint(Theme.alarm)
            .foregroundStyle(Theme.alarm)
            .font(.system(size: 12))
            .controlSize(.regular)
        }
    }

    // MARK: - Actions

    /// Resolve a bare filename (no `/`) to `~/.ssh/<name>`.
    ///
    /// Paths already containing `/` are returned as-is.
    private func resolvedIdentityPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") { return trimmed }
        // Bare name — expand to ~/.ssh/<name>
        return "~/.ssh/\(trimmed)"
    }

    private func runAddHost() {
        writeError = nil
        let errors = liveErrors
        validationErrors = errors
        guard errors.isEmpty else { return }

        let block = currentBlock
        if let reason = model.addHost(block) {
            writeError = reason
            return
        }
        // Write succeeded — signal the parent to close and scroll.
        let addedAlias = alias
        onAdded(addedAlias)
    }

    // MARK: - Browse

    private func browseForIdentityFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Key"
        panel.message = "Select the private key file for this host"
        panel.showsHiddenFiles = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // Default to ~/.ssh
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        panel.directoryURL = sshDir

        if panel.runModal() == .OK, let url = panel.url {
            // Collapse to ~/... when under home
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            var path = url.path
            if path.hasPrefix(home + "/") {
                path = "~/" + path.dropFirst(home.count + 1)
            } else if path == home {
                path = "~"
            }
            identityFile = path
        }
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
