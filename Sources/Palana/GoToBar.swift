// The go-to bar — Finder's ⇧⌘G, pointed at the field. One address field,
// one authority: the text resolves through the same grammar the pane
// header uses, and the resolved host is shown before Go is possible.
// A pasted bare path replaces the prefilled `host:path` and lands on this
// Mac; a remote host is always named, or borrowed from the pane with `:`.

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

    /// The pane's host — the `:` shorthand borrows it; nil when unpointed.
    let currentHost: String?
    /// The committed address text goes here, exactly as typed.
    let onCommit: (String) -> Void
    /// Esc lands here.
    let onCancel: () -> Void

    @State private var address: String

    /// A bar prefilled with the pane's explicit `host:path`.
    init(
        initialAddress: String,
        currentHost: String?,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.currentHost = currentHost
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
                    .disabled(resolution.resolved == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Theme.ground)
    }

    /// The quiet line under the field: where the address lands, or why
    /// it cannot.
    @ViewBuilder private var resolutionLine: some View {
        switch resolution {
        case .empty:
            Text(" ")
                .font(Theme.font(11))
        case .address(_, let line):
            Text(line)
                .font(Theme.font(11))
                .foregroundStyle(Theme.inkFaint)
                .lineLimit(1)
                .truncationMode(.middle)
        case .refusal(let reason):
            Text(reason)
                .font(Theme.font(11))
                .foregroundStyle(Theme.alarm)
                .lineLimit(2)
        }
    }

    private var resolution: Resolution {
        Self.resolution(of: address, currentHost: currentHost)
    }

    /// Resolves the field's text through the one grammar — pure, so a test
    /// can hold the sheet's preview against what the pane will do.
    static func resolution(of text: String, currentHost: String?) -> Resolution {
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
    static func scopeLine(for resolved: ResolvedAddress) -> String {
        let scope = resolved.isLocal ? "this Mac" : resolved.host
        let prefix = resolved.usesCurrentHost ? "current pane: " : ""
        return "\(prefix)\(scope) · \(resolved.path)"
    }

    private func commit() {
        guard resolution.resolved != nil else { return }
        onCommit(address)
    }
}
