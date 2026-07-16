// The go-to bar — Finder's ⇧⌘G, pointed at the field. Scaffolding
// with a future: ho-09's field view will point panes at hosts and
// datasets; go-to remains the path-level verb inside a host.

import PalanaCore
import SwiftUI

/// A one-line pointing: host from the Field's list, path typed.
struct GoToBar: View {
    /// The hosts the Field knows.
    let hosts: [String]
    /// Committed pointing goes here.
    let onCommit: (String, String) -> Void
    /// Esc lands here.
    let onCancel: () -> Void

    @State private var host: String
    @State private var path: String

    /// A bar pre-filled with where the pane already points.
    init(
        hosts: [String],
        initialHost: String?,
        initialPath: String,
        onCommit: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.hosts = hosts
        self.onCommit = onCommit
        self.onCancel = onCancel
        _host = State(initialValue: initialHost ?? hosts.first ?? "")
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("go to")
                .font(Theme.font(12, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
            Picker("host", selection: $host) {
                ForEach(menuHosts, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            TextField("path — absolute, or ~/ for home", text: $path)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("go", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.ground)
    }

    /// The Field's hosts, keeping a remembered host that has since
    /// left the config visible rather than silently swapped.
    private var menuHosts: [String] {
        host.isEmpty || hosts.contains(host) ? hosts : [host] + hosts
    }

    private func commit() {
        guard !host.isEmpty else { return }
        onCommit(host, path)
    }
}
