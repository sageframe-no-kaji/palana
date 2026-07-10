// The one AppKit reach-in. SwiftUI's Table paints its selected row in
// the system accent and offers no knob — the hands said no to the
// blue, twice. This styler finds the enclosing NSTableView and turns
// its native highlight drawing off; the pane paints the cursor row
// itself in the theme's wash. The first cut silenced once and SwiftUI
// quietly re-painted later — so this one holds a reference and
// re-silences on every selection change and window-key change. If the
// hierarchy changes shape and the table is not found, nothing breaks:
// the system highlight simply stays.

import AppKit
import SwiftUI

/// Silences the Table's native selection drawing, and keeps it silent.
struct TableSelectionStyler: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        context.coordinator.begin(near: probe)
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.enforce()
    }

    /// Holds the found table and re-applies the silence whenever AppKit
    /// has a reason to repaint selection.
    @MainActor
    final class Coordinator {
        private weak var table: NSTableView?
        private weak var probe: NSView?
        // nonisolated(unsafe): written only on the main actor; deinit
        // (nonisolated by definition) must still be able to unhook.
        nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        /// Finds the table — retrying while SwiftUI builds around us.
        func begin(near probe: NSView) {
            self.probe = probe
            for delay in [0.05, 0.25, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    MainActor.assumeIsolated { [weak self] in
                        self?.enforce()
                    }
                }
            }
        }

        /// Applies the silence, hooking notifications the first time.
        ///
        /// Always deferred a runloop turn: `enforce()` is reached from
        /// `updateNSView` — inside SwiftUI's own update pass — and from
        /// notification handlers inside the table's delegate pass. Mutating
        /// the table synchronously in either is a reentrant operation;
        /// AppKit warns today ("reentrant operation in its NSTableView
        /// delegate") and asserts tomorrow.
        func enforce() {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.applySilence()
                }
            }
        }

        /// The one mutation site — only ever reached off-pass.
        private func applySilence() {
            if table == nil, let probe {
                table = Self.findTable(near: probe)
                if let table {
                    watch(table)
                }
            }
            table?.selectionHighlightStyle = .none
        }

        private func watch(_ table: NSTableView) {
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSTableView.selectionDidChangeNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
            ]
            for name in names {
                observers.append(
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        // Deferred a turn: the notification fires inside the
                        // table's own delegate pass, and mutating the table
                        // there is a reentrant operation — AppKit warns today
                        // and will assert tomorrow.
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                self?.table?.selectionHighlightStyle = .none
                            }
                        }
                    })
            }
        }

        private static func findTable(near probe: NSView) -> NSTableView? {
            var ancestor = probe.superview
            var depth = 0
            while let current = ancestor, depth < 6 {
                if let table = firstTableView(in: current) {
                    return table
                }
                ancestor = current.superview
                depth += 1
            }
            return nil
        }

        private static func firstTableView(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for child in view.subviews {
                if let found = firstTableView(in: child) { return found }
            }
            return nil
        }
    }
}
