// The header's host menu, popped by hand. SwiftUI's Menu drops its
// list wherever AppKit pleases — off the pane's edge, the hands said
// no. This button computes the menu's size first and pops it with its
// right edge pinned to the button's right, so the list unfolds
// leftward and stays inside the pane.

import AppKit
import PalanaCore
import SwiftUI

/// The ▾ button and its right-pinned menu.
struct HostMenuButton: NSViewRepresentable {
    /// The Field's hosts.
    let hosts: [String]
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
    /// Toggle a favorite's scope (promote to global / move to this host).
    let onToggleFavoriteScope: (String) -> Void

    /// A flat entry the menu renders — carries id, display title, and scope for the toggle label.
    struct FavoriteEntry: Sendable {
        let id: String
        let host: String
        let path: String
        let label: String?
        let scope: FavoriteScope
        let isGlobal: Bool

        var displayTitle: String { label ?? "\(host):\(path)" }
        var scopeToggleTitle: String { isGlobal ? "move to this host" : "promote to global" }
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

            // Hosts section.
            for host in parent.hosts {
                let item = NSMenuItem(
                    title: "\(host):~", action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = host
                menu.addItem(item)
            }

            // Favorites section — global always, host-bound for this pane's host.
            if !parent.favorites.isEmpty {
                menu.addItem(.separator())
                let header = NSMenuItem(title: "favorites", action: nil, keyEquivalent: "")
                header.isEnabled = false
                menu.addItem(header)
                for fav in parent.favorites {
                    addFavoriteItems(fav, to: menu)
                }
            }

            menu.addItem(.separator())
            menu.addItem(action("type an address…", #selector(typeAddress)))
            menu.addItem(action("edit ~/.ssh/config…", #selector(editConfig)))
            menu.addItem(action("reload hosts", #selector(reload)))
            let origin = NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.maxY + 6)
            menu.popUp(positioning: nil, at: origin, in: sender)
        }

        /// Builds the jump item and a scope-toggle item for one favorite.
        private func addFavoriteItems(_ fav: FavoriteEntry, to menu: NSMenu) {
            // Jump item.
            let item = NSMenuItem(
                title: fav.displayTitle,
                action: #selector(chooseFavorite(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = fav
            menu.addItem(item)

            // Scope-toggle item — indented under the jump item.
            let toggle = NSMenuItem(
                title: "  \(fav.scopeToggleTitle)",
                action: #selector(toggleFavoriteScope(_:)),
                keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = fav.id
            menu.addItem(toggle)
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
            if let fav = item.representedObject as? FavoriteEntry {
                parent.onChooseFavorite(fav)
            }
        }

        @objc
        private func toggleFavoriteScope(_ item: NSMenuItem) {
            if let id = item.representedObject as? String {
                parent.onToggleFavoriteScope(id)
            }
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
