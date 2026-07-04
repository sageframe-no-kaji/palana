// The header's host menu, popped by hand. SwiftUI's Menu drops its
// list wherever AppKit pleases — off the pane's edge, the hands said
// no. This button computes the menu's size first and pops it with its
// right edge pinned to the button's right, so the list unfolds
// leftward and stays inside the pane.

import AppKit
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
            for host in parent.hosts {
                let item = NSMenuItem(
                    title: "\(host):~", action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = host
                menu.addItem(item)
            }
            menu.addItem(.separator())
            menu.addItem(action("type an address…", #selector(typeAddress)))
            menu.addItem(action("edit ~/.ssh/config…", #selector(editConfig)))
            menu.addItem(action("reload hosts", #selector(reload)))
            let origin = NSPoint(x: sender.bounds.maxX - menu.size.width, y: sender.bounds.maxY + 6)
            menu.popUp(positioning: nil, at: origin, in: sender)
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
