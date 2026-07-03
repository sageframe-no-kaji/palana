// The internal driver. Posts real NSEvent key events through the window's
// dispatch path — the same route a keystroke takes minus the HID origin.
// In-process, so no accessibility grant is needed (ho-01 Decision 2).

import AppKit

@MainActor
enum Driver {
    struct Key {
        let code: UInt16
        let scalar: UInt32
    }

    static let down = Key(code: 125, scalar: 0xF701)
    static let up = Key(code: 126, scalar: 0xF700)
    static let pageDown = Key(code: 121, scalar: 0xF72D)
    static let home = Key(code: 115, scalar: 0xF729)
    static let end = Key(code: 119, scalar: 0xF72B)

    static func press(_ key: Key, in window: NSWindow) {
        guard let scalar = UnicodeScalar(key.scalar) else { return }
        let characters = String(Character(scalar))
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: [.function, .numericPad],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: key.code
            )
            if let event { window.sendEvent(event) }
        }
    }

    /// Focuses the row-holding table view so key events land on it.
    static func focusTable(in window: NSWindow) -> Bool {
        guard let content = window.contentView else { return false }
        var queue: [NSView] = [content]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view.className.contains("TableView"), view.acceptsFirstResponder {
                return window.makeFirstResponder(view)
            }
            queue.append(contentsOf: view.subviews)
        }
        return false
    }

    static func run(window: NSWindow, collector: MetricsCollector) async {
        let phases: [(name: String, key: Key, count: Int, hz: Double)] = [
            ("arrows-down", down, 300, 30),
            ("page-down", pageDown, 60, 10),
            ("jump-end-home-end", end, 1, 3),
            ("arrows-up", up, 200, 30),
        ]

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        collector.counters["tableFocused"] = focusTable(in: window) ? 1 : 0

        // Settle before measuring.
        try? await Task.sleep(for: .seconds(1))

        for phase in phases {
            collector.currentPhase = phase.name
            if phase.name == "jump-end-home-end" {
                for key in [end, home, end] {
                    press(key, in: window)
                    try? await Task.sleep(for: .milliseconds(300))
                }
                continue
            }
            for _ in 0..<phase.count {
                press(phase.key, in: window)
                try? await Task.sleep(for: .nanoseconds(UInt64(1_000_000_000 / phase.hz)))
            }
        }
        collector.currentPhase = "done"
    }
}
