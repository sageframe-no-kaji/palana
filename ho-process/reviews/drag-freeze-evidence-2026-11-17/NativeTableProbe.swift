// Diagnostic only. No SwiftUI, runtime method replacement, network or transfers.
import AppKit
import os

private let selectionType = NSPasteboard.PasteboardType("net.sageframe.palana.internal-selection")

struct Payload: Codable {
    let host: String
    let directory: String
    let names: [String]
}

struct Entry {
    let name: String
    let url: URL
    let folder: Bool
}

@MainActor
final class Pane: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    let scroll = NSScrollView()
    let remote: Bool
    let directory: URL
    let entries: [Entry]
    var report: (String) -> Void = { _ in }
    let log = Logger(subsystem: "net.sageframe.palana.nativeprobe", category: "drag")

    init(directory: URL, remote: Bool) throws {
        self.directory = directory
        self.remote = remote
        entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ).map { url in
            Entry(name: url.lastPathComponent, url: url,
                  folder: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        super.init()
        let column = NSTableColumn(identifier: .init("name"))
        column.title = remote ? "Remote-format fixture (no network)" : "Local fixture"
        column.width = 430
        table.addTableColumn(column)
        table.headerView = NSTableHeaderView()
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([selectionType, .fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(remote ? [] : .copy, forLocal: false)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("name")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let field = NSTextField(labelWithString: "")
            field.font = .systemFont(ofSize: 13)
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = entries[row].name + (entries[row].folder ? "/" : "")
        return cell
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard entries.indices.contains(row) else { return nil }
        let indexes = tableView.selectedRowIndexes.contains(row) ? tableView.selectedRowIndexes : IndexSet(integer: row)
        let payload = Payload(host: remote ? "fixture" : "local", directory: directory.path,
                              names: indexes.map { entries[$0].name })
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        let item = NSPasteboardItem()
        item.setData(data, forType: selectionType)
        if !remote { item.setString(entries[row].url.absoluteString, forType: .fileURL) }
        log.notice("WRITER remote=\(self.remote) row=\(row) selected=\(indexes.count)")
        return item
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        // Observe only: never change formation, images, frames or animation.
        log.notice("BEGIN seq=\(session.draggingSequenceNumber) remote=\(self.remote) rows=\(rowIndexes.count)")
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        log.notice("END seq=\(session.draggingSequenceNumber) operation=\(operation.rawValue)")
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingPasteboard.availableType(from: [selectionType, .fileURL]) != nil else { return [] }
        tableView.setDropRow(entries.indices.contains(row) && entries[row].folder ? row : -1, dropOperation: .on)
        return NSEvent.modifierFlags.contains(.command) ? .move : .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let data = info.draggingPasteboard.data(forType: selectionType),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return false }
        let target = entries.indices.contains(row) ? entries[row].name : "pane"
        report("Received \(payload.names.count) item(s) from \(payload.host) → \(target). Nothing copied or moved.")
        log.notice("DROP seq=\(info.draggingSequenceNumber) count=\(payload.names.count) remoteTarget=\(self.remote)")
        return true
    }
}

@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    let panes: [Pane]
    var window: NSWindow?

    init(root: URL) throws {
        let local = root.appendingPathComponent("local", isDirectory: true)
        let remote = root.appendingPathComponent("remote", isDirectory: true)
        for folder in [local, remote] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder"), withIntermediateDirectories: true)
            for name in ["3ping.txt", "a.txt", "b.txt"] {
                let file = folder.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: file.path) {
                    try Data("Disposable native drag fixture\n".utf8).write(to: file)
                }
            }
        }
        panes = try [Pane(directory: local, remote: false), Pane(directory: remote, remote: true)]
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 241, y: 180, width: 909, height: 650),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Palana Native Drag Probe — NOT A RELEASE"
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content
        let status = NSTextField(wrappingLabelWithString: "Diagnostic: drops only report receipt. No files are copied or moved between panes.")
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        let split = NSStackView(views: panes.map(\.scroll))
        split.orientation = .horizontal
        split.distribution = .fillEqually
        split.spacing = 4
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            status.heightAnchor.constraint(equalToConstant: 36)
        ])
        for pane in panes { pane.report = { status.stringValue = $0 } }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Native Drag Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = menu
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func check() throws {
        for pane in panes {
            pane.table.reloadData()
            pane.table.selectRowIndexes(IndexSet([0, 2]), byExtendingSelection: false)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let writers = [0, 2].compactMap { pane.tableView(pane.table, pasteboardWriterForRow: $0) }
            precondition(writers.count == 2 && board.writeObjects(writers))
            precondition(board.pasteboardItems?.count == 2)
            for item in board.pasteboardItems ?? [] {
                let payload = try JSONDecoder().decode(Payload.self, from: item.data(forType: selectionType)!)
                precondition(payload.names.count == 2)
                precondition(item.types.contains(.fileURL) == !pane.remote)
            }
            pane.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            precondition(pane.table.selectedRowIndexes == IndexSet(integer: 1))
        }
        print("PASS: local/remote-format group payloads, local URLs only, programmatic selection. Native drag not tested.")
    }
}

@main
enum Main {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        let root = ProcessInfo.processInfo.environment["PALANA_PROBE_ROOT"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("palana-native-drag-probe").path
        let probe = try Probe(root: URL(fileURLWithPath: root))
        if CommandLine.arguments.contains("--check") { try probe.check(); return }
        app.setActivationPolicy(.regular)
        app.delegate = probe
        withExtendedLifetime(probe) { app.run() }
    }
}
