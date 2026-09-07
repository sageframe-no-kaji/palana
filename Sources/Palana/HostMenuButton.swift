// The header's host menu, popped by hand. SwiftUI's Menu drops its
// list wherever AppKit pleases — off the pane's edge, the hands said
// no. This button computes the menu's size first and pops it with its
// right edge pinned to the button's right, so the list unfolds
// leftward and stays inside the pane.
//
// The menu's lines are composed by a pure function (`lines(...)`) so
// the AppKit rendering is a straight walk over values a test can hold.
// An unreadable config is not an empty one: when the file could not be
// read the menu says so, right under the host list, in one line.

import AppKit
import PalanaCore
import SwiftUI

/// What the host menu says under its list when the config is not whole.
///
/// Produced by `SettingsModel`, fed to the menu by the pane. `readFailure`
/// is the typed reason the file could not be read or decoded;
/// `refusedAliasCount` is how many `Host` tokens the parser refused
/// (the reserved `local`, tokens outside the alias grammar) — the
/// settings card names each one.
struct HostMenuDiagnostic: Equatable, Sendable {
    /// Why the config could not be read, `nil` when it was.
    let readFailure: SSHConfigReadError?
    /// How many aliases the parser refused; the settings card lists them.
    let refusedAliasCount: Int

    /// A readable config with nothing refused — the menu shows no notice.
    static let clear = Self(readFailure: nil, refusedAliasCount: 0)
}

/// One line of the menu, before AppKit sees it.
struct HostMenuLine: Equatable, Sendable {
    /// What the line does when chosen — or that it does nothing.
    enum Kind: Equatable, Sendable {
        /// Jump to a host's home.
        case host(String)
        /// A ruled gap.
        case separator
        /// The "favorites" caption; inert.
        case favoritesHeader
        /// Jump to a favorite by id.
        case favorite(id: String)
        /// A diagnostic; inert, read only.
        case notice
        /// Open the typed-address field.
        case typeAddress
        /// Open the config in its editor.
        case editConfig
        /// Re-read the config.
        case reload
    }

    let kind: Kind
    let title: String
    let isEnabled: Bool
}

/// The ▾ button and its right-pinned menu.
struct HostMenuButton: NSViewRepresentable {
    /// The Field's hosts.
    let hosts: [String]
    /// What to say under the host list when the config is not whole.
    let diagnostic: HostMenuDiagnostic
    /// A host was chosen — go to its home.
    let onChoose: (String) -> Void
    /// The typed-address field was asked for.
    let onType: () -> Void
    /// Open `~/.ssh/config`.
    let onEditConfig: () -> Void
    /// Re-read the config.
    let onReload: () -> Void
    /// Global favorites (always shown) and host-bound favorites for this pane's host.
    ///
    /// Passed in from outside — the NSView never reaches into the session.
    let favorites: [FavoriteEntry]
    /// A favorite was chosen — point the pane.
    let onChooseFavorite: (FavoriteEntry) -> Void

    /// A flat entry the menu renders — carries id, display title, and scope.
    ///
    /// The scope rides along so choosing the favorite can rebuild it; the
    /// menu never offers to change it — that toggle lives in the
    /// favorites panel, where there is room to read it.
    struct FavoriteEntry: Equatable, Sendable {
        let id: String
        let host: String
        let path: String
        let label: String?
        let scope: FavoriteScope

        var displayTitle: String { label ?? "\(host):\(path)" }
    }

    /// Composes the menu's lines in order: hosts, then any notice, then
    /// favorites, then the ways in.
    ///
    /// The notice lines sit right under the host list so a short list is
    /// explained where it is read. A refused-alias count points at the
    /// settings card, which names each token and why. Pure, so it is
    /// `nonisolated` — the view's main-actor isolation is not needed here.
    nonisolated static func lines(
        hosts: [String],
        favorites: [FavoriteEntry],
        diagnostic: HostMenuDiagnostic
    ) -> [HostMenuLine] {
        var lines: [HostMenuLine] = []
        for host in hosts {
            lines.append(HostMenuLine(kind: .host(host), title: "\(host):~", isEnabled: true))
        }
        if let failure = diagnostic.readFailure {
            lines.append(HostMenuLine(kind: .notice, title: readFailureTitle(failure), isEnabled: false))
        }
        if diagnostic.refusedAliasCount > 0 {
            let count = diagnostic.refusedAliasCount
            let noun = count == 1 ? "host" : "hosts"
            lines.append(
                HostMenuLine(kind: .notice, title: "\(count) \(noun) not listed — see settings", isEnabled: false))
        }
        if !favorites.isEmpty {
            lines.append(HostMenuLine(kind: .separator, title: "", isEnabled: false))
            lines.append(HostMenuLine(kind: .favoritesHeader, title: "favorites", isEnabled: false))
            for fav in favorites {
                lines.append(HostMenuLine(kind: .favorite(id: fav.id), title: fav.displayTitle, isEnabled: true))
            }
        }
        lines.append(HostMenuLine(kind: .separator, title: "", isEnabled: false))
        lines.append(HostMenuLine(kind: .typeAddress, title: "type an address…", isEnabled: true))
        lines.append(HostMenuLine(kind: .editConfig, title: "edit ~/.ssh/config…", isEnabled: true))
        lines.append(HostMenuLine(kind: .reload, title: "reload hosts", isEnabled: true))
        return lines
    }

    /// One line naming the file and the system's word on why it did not read.
    ///
    /// The path is shown with `~` for the home directory, the way the
    /// operator wrote it; a trailing full stop on the system's reason is
    /// dropped so the line ends where the menu does.
    nonisolated static func readFailureTitle(_ failure: SSHConfigReadError) -> String {
        switch failure {
        case .unreadable(let path, let reason):
            let trimmed = reason.hasSuffix(".") ? String(reason.dropLast()) : reason
            return "\(abbreviated(path)) could not be read — \(trimmed)"
        case .notUTF8(let path):
            return "\(abbreviated(path)) could not be read — not UTF-8 text"
        }
    }

    nonisolated private static func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(
            systemSymbolName: "chevron.down", accessibilityDescription: "hosts")
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.pop(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.parent = self
    }

    /// Builds and pops the menu, right edge pinned.
    @MainActor
    final class Coordinator: NSObject {
        var parent: HostMenuButton

        init(parent: HostMenuButton) {
            self.parent = parent
        }

        @objc
        func pop(_ sender: NSButton) {
            let menu = NSMenu()
            let lines = HostMenuButton.lines(
                hosts: parent.hosts, favorites: parent.favorites, diagnostic: parent.diagnostic)
            for line in lines {
                menu.addItem(item(for: line))
            }
            let origin = NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.maxY + 6)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        /// Renders one composed line as an AppKit item.
        private func item(for line: HostMenuLine) -> NSMenuItem {
            switch line.kind {
            case .separator:
                return .separator()
            case .host(let host):
                let item = action(line.title, #selector(choose(_:)))
                item.representedObject = host
                return item
            case .favorite(let id):
                let item = action(line.title, #selector(chooseFavorite(_:)))
                item.representedObject = id
                return item
            case .favoritesHeader, .notice:
                let item = NSMenuItem(title: line.title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                return item
            case .typeAddress:
                return action(line.title, #selector(typeAddress))
            case .editConfig:
                return action(line.title, #selector(editConfig))
            case .reload:
                return action(line.title, #selector(reload))
            }
        }

        private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            return item
        }

        @objc
        private func choose(_ item: NSMenuItem) {
            if let host = item.representedObject as? String {
                parent.onChoose(host)
            }
        }

        @objc
        private func chooseFavorite(_ item: NSMenuItem) {
            guard let id = item.representedObject as? String,
                let fav = parent.favorites.first(where: { $0.id == id })
            else { return }
            parent.onChooseFavorite(fav)
        }

        @objc
        private func typeAddress() {
            parent.onType()
        }

        @objc
        private func editConfig() {
            parent.onEditConfig()
        }

        @objc
        private func reload() {
            parent.onReload()
        }
    }
}
