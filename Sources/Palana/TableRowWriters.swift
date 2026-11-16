// TableRowWriters — the pasteboard item a dragged row hands the table.
//
// The table's drag stays SwiftUI's and AppKit's own (0.8's mechanics): the
// table starts it, flocks it, and asks its data source for one pasteboard
// writer per dragged row. SwiftUI's answer is an item that writes the row's
// file URL lazily, which macOS cannot pass to Finder or a browser
// (rowPasteboardWriter, DragOut.swift). This answers that one question for a
// pane's table — the data source's outlineView(_:pasteboardWriterForItem:) —
// with pālana's writer when it has one, and SwiftUI's otherwise. Nothing
// else about the drag changes.

import AppKit
import ObjectiveC
import SwiftUI
import os

/// Attaches pālana's row writers to the enclosing pane table.
struct TableRowWriters: NSViewRepresentable {
    /// pālana's writer for a table row, or nil to keep SwiftUI's.
    let writer: @MainActor (Int) -> (any NSPasteboardWriting)?

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        context.coordinator.writer = writer
        context.coordinator.begin(near: probe)
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.writer = writer
        context.coordinator.recheck(near: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Finds the table and keeps the hook attached to it.
    @MainActor
    final class Coordinator {
        var writer: (@MainActor (Int) -> (any NSPasteboardWriting)?)?
        private weak var table: NSTableView?

        /// Finds the table — retrying while SwiftUI builds around the probe.
        func begin(near probe: NSView) {
            for delay in [0.05, 0.25, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak probe] in
                    MainActor.assumeIsolated {
                        guard let self, let probe else { return }
                        self.attachIfNeeded(near: probe)
                    }
                }
            }
        }

        /// Re-attaches when SwiftUI has swapped the table out — deferred a
        /// turn, since this runs inside SwiftUI's update pass.
        func recheck(near probe: NSView) {
            DispatchQueue.main.async { [weak self, weak probe] in
                MainActor.assumeIsolated {
                    guard let self, let probe else { return }
                    self.attachIfNeeded(near: probe)
                }
            }
        }

        private func attachIfNeeded(near probe: NSView) {
            guard table?.window == nil, let found = Self.findTable(near: probe) else { return }
            table = found
            RowWriterHook.install(on: found) { [weak self] row in
                self?.writer?(row)
            }
        }

        /// The table whose frame matches the probe's.
        ///
        /// The probe is the table's background, so they share a frame;
        /// walking up to the first table found can land on the other pane's.
        private static func findTable(near probe: NSView) -> NSTableView? {
            guard let root = probe.window?.contentView, probe.bounds.width > 0 else { return nil }
            let target = probe.convert(probe.bounds, to: nil)
            func distance(_ table: NSTableView) -> CGFloat {
                let frameView: NSView = table.enclosingScrollView ?? table
                let frame = frameView.convert(frameView.bounds, to: nil)
                return abs(frame.minX - target.minX) + abs(frame.minY - target.minY)
                    + abs(frame.width - target.width) + abs(frame.height - target.height)
            }
            let best = tableViews(in: root).min { distance($0) < distance($1) }
            guard let best, distance(best) < 8 else { return nil }
            return best
        }

        private static func tableViews(in view: NSView) -> [NSTableView] {
            if let table = view as? NSTableView { return [table] }
            return view.subviews.flatMap(tableViews(in:))
        }
    }
}

/// The one runtime reach-in: the table data source's
/// `outlineView(_:pasteboardWriterForItem:)` asks a hooked table first.
@MainActor
enum RowWriterHook {
    /// pālana's writer for a row, or nil to keep SwiftUI's.
    typealias Hook = @MainActor (Int) -> (any NSPasteboardWriting)?

    private final class HookBox {
        let hook: Hook
        init(_ hook: @escaping Hook) { self.hook = hook }
    }

    /// A writer crossing `assumeIsolated` within one main-thread call.
    private struct Answer: @unchecked Sendable {
        // @unchecked: built and returned inside one main-thread call; it
        // only crosses assumeIsolated's boundary, never a thread.
        let writer: (any NSPasteboardWriting)?
    }

    private typealias WriterFor = @convention(c) (AnyObject, Selector, NSOutlineView, AnyObject?) -> AnyObject?
    private typealias WriterBlock = @convention(block) (AnyObject, NSOutlineView, AnyObject?) -> AnyObject?
    // nonisolated(unsafe): only its address is used, as the associated-object key.
    nonisolated(unsafe) private static var hookKey: UInt8 = 0
    private static var patched: Set<ObjectIdentifier> = []
    nonisolated private static let logger = Logger(subsystem: "net.sageframe.palana", category: "dragout")

    /// Attaches `hook` to `table` and patches its data source's class once.
    static func install(on table: NSTableView, hook: @escaping Hook) {
        objc_setAssociatedObject(table, &hookKey, HookBox(hook), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let selector = NSSelectorFromString("outlineView:pasteboardWriterForItem:")
        guard let source = table.dataSource, let sourceClass = object_getClass(source),
            !patched.contains(ObjectIdentifier(sourceClass)),
            let method = class_getInstanceMethod(sourceClass, selector)
        else { return }
        patched.insert(ObjectIdentifier(sourceClass))
        let original = unsafeBitCast(method_getImplementation(method), to: WriterFor.self)
        let block: WriterBlock = { source, outline, item in
            let answer = MainActor.assumeIsolated { () -> Answer in
                guard let box = objc_getAssociatedObject(outline, &hookKey) as? HookBox else {
                    return Answer(writer: nil)
                }
                let row = outline.row(forItem: item)
                let writer = box.hook(row)
                logger.info(
                    "row writer: row \(row, privacy: .public) of \(outline.numberOfRows, privacy: .public), pālana's: \(writer != nil, privacy: .public)"
                )
                return Answer(writer: writer)
            }
            return answer.writer ?? original(source, selector, outline, item)
        }
        class_replaceMethod(sourceClass, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method))
    }
}
