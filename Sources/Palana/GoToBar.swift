// The go-to bar — Finder's ⇧⌘G, pointed at the field. One address field,
// one authority: the text resolves through the same grammar the pane
// header uses, and the resolved host is shown before Go is possible.
// A pasted bare path replaces the prefilled `host:path` and lands on this
// Mac; a remote host is always named, or borrowed from the pane with `:`.
//
// Under the scope line the sheet previews what the pane's recovery will
// do with the address — the same function the commit runs, so the sheet
// never promises a landing the pane will not make: an exact path reads
// plain, a trailing-punctuation correction or an ancestor landing says so
// in the accent, and a path nothing can recover reads as its refusal.

import PalanaCore
import SwiftUI

/// A one-line pointing, resolved as it is typed.
struct GoToBar: View {
    /// What the field resolves to, recomputed on every keystroke.
    enum Resolution: Equatable {
        /// The field is empty — nothing to say, Go stays off.
        case empty
        /// A parsed address and the scope line that names where it lands.
        case address(ResolvedAddress, line: String)
        /// A refusal, shown in place; Go stays off.
        case refusal(String)

        /// The address when the text parses, nil otherwise.
        var resolved: ResolvedAddress? {
            if case .address(let resolved, _) = self { return resolved }
            return nil
        }
    }

    /// What the pane's recovery says the address will do — asked after
    /// the text settles, through the same function the commit uses.
    enum Preview: Equatable {
        /// Not asked yet, or the host has not answered.
        case pending
        /// Where the pane will land, with any correction named.
        case recovered(AddressRecovery)
        /// Nothing on that host can be pointed at; Go stays off.
        case refused(String)
    }

    /// How long the text rests before the host is asked — a paste settles
    /// at once; a remote host is not probed on every keystroke.
    static let previewDelay = Duration.milliseconds(250)

    /// The pane's host — the `:` shorthand borrows it; nil when unpointed.
    let currentHost: String?
    /// The pane's recovery — the authority the preview and the commit share.
    let recover: @MainActor (ResolvedAddress) async -> Result<AddressRecovery, AddressRecoveryError>
    /// The committed address text goes here, exactly as typed.
    let onCommit: (String) -> Void
    /// Esc lands here.
    let onCancel: () -> Void

    @State private var address: String
    @State private var preview = Preview.pending

    /// A bar prefilled with the pane's explicit `host:path`.
    init(
        initialAddress: String,
        currentHost: String?,
        recover: @escaping @MainActor (ResolvedAddress) async -> Result<AddressRecovery, AddressRecoveryError>,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentHost = currentHost
        self.recover = recover
        self.onCommit = onCommit
        self.onCancel = onCancel
        _address = State(initialValue: initialAddress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("go to")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            TextField("host:path — local: for this Mac, : for this pane's host, ~ for home", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            resolutionLine
            HStack {
                Spacer()
                Button("cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("go", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canGo)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Theme.ground)
        .task(id: resolution.resolved) { await previewRecovery(of: resolution.resolved) }
    }

    /// The quiet line under the field: where the address lands, or why
    /// it cannot.
    @ViewBuilder private var resolutionLine: some View {
        switch resolution {
        case .empty:
            Text(" ")
                .font(Theme.font(11))
        case .address(_, let line):
            previewLine(scope: line)
        case .refusal(let reason):
            refusalLine(reason)
        }
    }

    /// The scope line as the grammar wrote it, or as the recovery rewrote it.
    @ViewBuilder
    private func previewLine(scope: String) -> some View {
        switch preview {
        case .pending:
            scopeText(scope, color: Theme.inkFaint)
        case .recovered(let recovery):
            scopeText(Self.previewLine(for: recovery), color: recovery.isCorrected ? Theme.accent : Theme.inkFaint)
        case .refused(let reason):
            refusalLine(reason)
        }
    }

    private func scopeText(_ line: String, color: Color) -> some View {
        Text(line)
            .font(Theme.font(11))
            .foregroundStyle(color)
            .lineLimit(2)
            .truncationMode(.middle)
    }

    private func refusalLine(_ reason: String) -> some View {
        Text(reason)
            .font(Theme.font(11))
            .foregroundStyle(Theme.alarm)
            .lineLimit(2)
    }

    private var resolution: Resolution {
        Self.resolution(of: address, currentHost: currentHost)
    }

    /// Go is possible when the text parses and the host has not refused it.
    private var canGo: Bool {
        guard resolution.resolved != nil else { return false }
        if case .refused = preview { return false }
        return true
    }

    /// Resolves the field's text through the one grammar — pure, so a test
    /// can hold the sheet's preview against what the pane will do.
    nonisolated static func resolution(of text: String, currentHost: String?) -> Resolution {
        switch PaneModel.resolveAddress(text, currentHost: currentHost) {
        case .success(let resolved):
            .address(resolved, line: scopeLine(for: resolved))
        case .failure(.empty):
            .empty
        case .failure(let refusal):
            .refusal(refusal.description)
        }
    }

    /// `this Mac · /Users/…`, `koan · /srv/…`, or `current pane: koan · /srv/…`.
    nonisolated static func scopeLine(for resolved: ResolvedAddress) -> String {
        let prefix = resolved.usesCurrentHost ? "current pane: " : ""
        return "\(prefix)\(resolved.scopeName) · \(resolved.path)"
    }

    /// The line once the recovery has answered: the destination's scope
    /// line, and — when the pane will not land exactly where the text
    /// said — the correction, named.
    nonisolated static func previewLine(for recovery: AddressRecovery) -> String {
        let scope = scopeLine(for: recovery.destination)
        guard let notice = recovery.notice else { return scope }
        return "\(scope) — \(notice)"
    }

    /// Asks the pane's recovery once the text has rested.
    private func previewRecovery(of resolved: ResolvedAddress?) async {
        preview = .pending
        guard let resolved else { return }
        try? await Task.sleep(for: Self.previewDelay)
        guard !Task.isCancelled else { return }
        let outcome = await recover(resolved)
        guard !Task.isCancelled else { return }
        switch outcome {
        case .success(let recovery): preview = .recovered(recovery)
        case .failure(let refusal): preview = .refused(refusal.description)
        }
    }

    private func commit() {
        guard canGo else { return }
        onCommit(address)
    }
}
