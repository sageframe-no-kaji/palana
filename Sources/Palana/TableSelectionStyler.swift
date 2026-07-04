// The one AppKit reach-in. SwiftUI's Table paints its selected row in
// the system accent and offers no knob — the hands said no to the
// blue. This styler finds the enclosing NSTableView and turns its
// native highlight drawing off; the pane paints the cursor row itself
// in the theme's wash. Selection behavior is untouched — only the
// drawing moves. If the hierarchy changes shape and the table is not
// found, nothing breaks: the system highlight simply stays.

import AppKit
import SwiftUI

/// Silences the Table's native selection drawing.
struct TableSelectionStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        DispatchQueue.main.async { Self.silenceTableHighlight(near: probe) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.silenceTableHighlight(near: nsView) }
    }

    /// Walks up from the probe, searching each ancestor's subtree for
    /// the nearest NSTableView.
    private static func silenceTableHighlight(near probe: NSView) {
        var ancestor = probe.superview
        var depth = 0
        while let current = ancestor, depth < 6 {
            if let table = firstTableView(in: current) {
                table.selectionHighlightStyle = .none
                return
            }
            ancestor = current.superview
            depth += 1
        }
    }

    private static func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let found = firstTableView(in: child) { return found }
        }
        return nil
    }
}
