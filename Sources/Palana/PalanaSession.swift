// The session — the app's one root object. Builds the engine stack,
// owns the two panes and the focus, runs keystrokes through the
// recognizer, restores and persists the workbench. The conduit's
// sessions close when the app quits, because nothing outlives the
// window.
//
// PALANA_SSH_CONFIG points the whole stack at an alternate ssh config
// — the fixture's, during development. Unset, the operator's own
// ~/.ssh/config governs, exactly as it does in the terminal.

import AppKit
import PalanaCore
import SwiftUI

/// The root object — engine, panes, focus, grammar, persistence.
@MainActor
@Observable
final class PalanaSession {
    /// The left pane.
    let left: PaneModel
    /// The right pane.
    let right: PaneModel
    /// Which pane the keyboard drives.
    var focusedSide = SessionSnapshot.Side.left
    /// Non-nil while the go-to bar is up, naming the pane it points.
    var gotoTarget: SessionSnapshot.Side?
    /// Whether the vocabulary card is up.
    var helpVisible = false
    /// The one operation in flight — verb to plan to enactment.
    let operation: OperationModel
    /// The pending multi-key prefix, for the footer.
    private(set) var pendingPrefix = ""
    /// The hosts the Field knows — the go-to bar's menu.
    private(set) var hosts: [String] = []

    private let conduit: SSHConduit
    private let field: Field
    private let sshConfigURL: URL
    private var recognizer: SequenceRecognizer<PaneIntent>
    private var keyMonitor: Any?

    /// Builds the engine stack from the operator's ssh config, or from
    /// `PALANA_SSH_CONFIG` when the environment points elsewhere.
    init() {
        let override = ProcessInfo.processInfo.environment["PALANA_SSH_CONFIG"]
        let configURL =
            override.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
        let extraOptions = override.map { ["-F", $0] } ?? []
        let configuration = SSHConfiguration(extraOptions: extraOptions)
        let conduit = SSHConduit(configuration: configuration)
        let configText = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        self.sshConfigURL = configURL
        self.conduit = conduit
        self.field = Field(conduit: conduit, sshConfigText: configText, cache: FieldCache())
        self.recognizer = SequenceRecognizer(bindings: Grammar.bindings)
        let engine = Engine(conduit: conduit, field: field, listing: Listing(conduit: conduit))
        self.left = PaneModel(engine: engine)
        self.right = PaneModel(engine: engine)
        self.operation = OperationModel(engine: engine, configuration: configuration)
        left.onDisplayChange = { [weak self] in self?.persist() }
        right.onDisplayChange = { [weak self] in self?.persist() }
        operation.onFinished = { [weak self] in
            self?.left.apply(.refresh)
            self?.right.apply(.refresh)
        }
    }

    /// The pane the keyboard drives.
    var focusedPane: PaneModel {
        focusedSide == .left ? left : right
    }

    /// Loads the host list and restores the remembered workbench.
    ///
    /// This Mac leads the list — always present, always reachable, and
    /// the go-to bar's safe default.
    func start() async {
        hosts = [Engine.localHost] + (await field.hosts())
        guard let snapshot = SessionStore.load(from: SessionStore.defaultURL()) else { return }
        focusedSide = snapshot.focused
        left.restore(snapshot.left)
        right.restore(snapshot.right)
    }

    /// Re-reads `~/.ssh/config` for the host menus.
    ///
    /// The config is the only host registry — pālana never keeps its
    /// own. New aliases appear here the moment the file says so.
    func reloadHosts() {
        let text = (try? String(contentsOf: sshConfigURL, encoding: .utf8)) ?? ""
        hosts = [Engine.localHost] + SSHConfigParser.hosts(in: text)
    }

    /// Opens the operator's ssh config in whatever edits it.
    ///
    /// The way into adding a host is the file itself — no dialog, no
    /// parallel registry, no trust ceremony.
    func editSSHConfig() {
        NSWorkspace.shared.open(sshConfigURL)
    }

    // MARK: - Keyboard

    /// Installs the window-level key monitor.
    ///
    /// Consumed keys return nil to AppKit; everything else passes
    /// through untouched.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == true }
            return consumed ? nil : event
        }
    }

    /// Routes one key event through the grammar.
    ///
    /// True means consumed.
    func handle(_ event: NSEvent) -> Bool {
        guard gotoTarget == nil else { return false }
        // While a path is being typed in a header, the letters belong
        // to the field, not the grammar.
        guard !left.pathEditing, !right.pathEditing else { return false }
        guard let token = Grammar.token(for: event) else { return false }
        if operation.active {
            return handlePanelKey(token)
        }
        if helpVisible {
            // The card holds the keyboard: ? or Esc closes, the rest
            // waits so the panes stay put while the eyes are here.
            if token == "esc" || token == "?" { helpVisible = false }
            return true
        }
        if token == "esc" {
            // A pending prefix dies first; a bare Esc clears the selection.
            if pendingPrefix.isEmpty {
                focusedPane.apply(.clearSelection)
            } else {
                recognizer.reset()
                pendingPrefix = ""
            }
            return true
        }
        switch recognizer.press(token) {
        case .matched(let intent):
            pendingPrefix = ""
            dispatch(intent)
            return true
        case .pending(let prefix):
            pendingPrefix = prefix.joined()
            return true
        case .unmatched:
            pendingPrefix = ""
            return false
        }
    }

    /// The panel holds the keyboard: Enter enacts, Esc dismisses or
    /// cancels, plain keys wait — but the app's own chords (quit,
    /// close) pass through untouched.
    private func handlePanelKey(_ token: String) -> Bool {
        if token == "return" { operation.enact() }
        if token == "esc" { operation.dismissOrCancel() }
        return !token.contains("cmd-")
    }

    /// The session's verbs stay here; everything else goes to the pane.
    private func dispatch(_ intent: PaneIntent) {
        switch intent {
        case .switchPane:
            focusedSide = focusedSide == .left ? .right : .left
            persist()
        case .goTo:
            gotoTarget = focusedSide
        case .help:
            helpVisible = true
        case .operationCopy:
            beginOperation(.copy)
        case .operationMove:
            beginOperation(.move)
        case .operationDelete:
            beginOperation(.delete)
        default:
            focusedPane.apply(intent)
        }
    }

    /// A verb goes down: the focused pane is the source, the other pane
    /// is the destination, the panel takes it from here.
    private func beginOperation(_ operationKind: PlanOperation) {
        let destination = focusedSide == .left ? right : left
        operation.begin(operationKind, source: focusedPane, destination: destination)
    }

    /// True when the divider should show where a send would go.
    ///
    /// The practitioner's ask, verbatim: "a subtle directional arrow on
    /// selection showing send direction source→destination pane."
    var showsSendArrow: Bool {
        guard !operation.active, gotoTarget == nil, !helpVisible else { return false }
        guard focusedPane.status == .ready, !focusedPane.operationSubjects.isEmpty else {
            return false
        }
        let other = focusedSide == .left ? right : left
        return other.status == .ready
    }

    /// Points a pane from the go-to bar.
    func point(_ side: SessionSnapshot.Side, host: String, path: String) {
        let pane = side == .left ? left : right
        let cleaned = path.isEmpty ? "/" : path
        pane.point(host: host, path: cleaned)
        gotoTarget = nil
    }

    // MARK: - Persistence and shutdown

    /// Writes the workbench as it stands.
    ///
    /// Failure is not worth a dialog — the next change tries again.
    func persist() {
        let snapshot = SessionSnapshot(
            left: SessionSnapshot.Pane(of: left.state),
            right: SessionSnapshot.Pane(of: right.state),
            focused: focusedSide)
        try? SessionStore.save(snapshot, to: SessionStore.defaultURL())
    }

    /// Closes every ControlMaster — the quit path owns this.
    func closeDoors() async {
        await conduit.closeAll()
    }
}
