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
    /// Whether the settings card is up.
    var settingsVisible = false
    /// True while a text field inside the settings card is focused.
    ///
    /// The key monitor stands down while this is true — typed characters
    /// belong to the field, not the grammar.
    var settingsFieldFocused = false
    /// Asks the surface to open the floating keys window.
    ///
    /// Bumped by a second ? while the card is up — the surface watches
    /// for the change.
    private(set) var floatingHelpTick = 0
    /// The one operation in flight — verb to plan to enactment.
    let operation: OperationModel
    /// The pending multi-key prefix, for the footer.
    private(set) var pendingPrefix = ""
    /// True while the topology overlay is up.
    var fieldVisible = false
    /// The topology overlay's view model — shared with SurfaceView.
    let fieldViewModel: FieldViewModel
    /// The hosts the Field knows — the go-to bar's menu.
    ///
    /// Visible hosts only: hidden aliases (marked `# palana: hide` in the
    /// ssh config) are filtered out. Typed addresses in the path header
    /// are never filtered — the filter is a curtain, not a lock.
    private(set) var hosts: [String] = []
    /// The settings model — rsync flags and host-hide controls.
    let settings: SettingsModel

    private let conduit: SSHConduit
    private let field: Field
    private let engine: Engine
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
        let settingsURL =
            SessionStore.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent("settings.json")
        let settingsModel = SettingsModel(configURL: configURL, settingsURL: settingsURL)
        self.sshConfigURL = configURL
        self.conduit = conduit
        self.settings = settingsModel
        self.field = Field(conduit: conduit, sshConfigText: configText, cache: FieldCache())
        self.recognizer = SequenceRecognizer(bindings: Grammar.bindings)
        self.engine = Engine(conduit: conduit, field: field, listing: Listing(conduit: conduit))
        self.fieldViewModel = FieldViewModel(engine: self.engine)
        self.left = PaneModel(engine: self.engine)
        self.right = PaneModel(engine: self.engine)
        self.operation = OperationModel(engine: self.engine, configuration: configuration, settings: settingsModel)
        left.onDisplayChange = { [weak self] in self?.persist() }
        right.onDisplayChange = { [weak self] in self?.persist() }
        settingsModel.onConfigChanged = { [weak self] in self?.reloadHosts() }
        operation.onFinished = { [weak self] in
            guard let self else { return }
            // Land the cursor on the renamed or created entry before the refresh
            // fires — both panes get it; only the one that holds the entry matches.
            if let name = operation.resultName {
                left.setLandOn(name)
                right.setLandOn(name)
            }
            left.apply(.refresh)
            right.apply(.refresh)
        }
    }

    /// The pane the keyboard drives.
    var focusedPane: PaneModel {
        focusedSide == .left ? left : right
    }

    /// Loads the host list and restores the remembered workbench.
    ///
    /// This Mac leads the list — always present, always reachable, and
    /// the go-to bar's safe default. Hidden aliases are filtered out;
    /// the filter is a curtain, not a lock.
    func start() async {
        reloadHosts()
        guard let snapshot = SessionStore.load(from: SessionStore.defaultURL()) else { return }
        focusedSide = snapshot.focused
        left.restore(snapshot.left)
        right.restore(snapshot.right)
    }

    /// Re-reads `~/.ssh/config` for the host menus.
    ///
    /// The config is the only host registry — pālana never keeps its
    /// own. New aliases appear here the moment the file says so.
    /// `Include` directives are followed, exactly as the Field follows
    /// them. Hidden aliases (`# palana: hide`) are excluded.
    func reloadHosts() {
        let text = (try? String(contentsOf: sshConfigURL, encoding: .utf8)) ?? ""
        let resolve = SSHConfigParser.systemInclude(
            relativeTo: sshConfigURL.deletingLastPathComponent())
        let hidden = SSHConfigParser.hiddenHosts(in: text, including: resolve)
        hosts =
            [Engine.localHost]
            + SSHConfigParser.hosts(in: text, including: resolve).filter { !hidden.contains($0) }
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
            // The grammar lives in the surface window only. The keys
            // panel answers three keys here — Esc closes, ⌘ + / −
            // resize — deterministically, no responder chain to lose.
            if event.window?.identifier?.rawValue == KeysPanelController.identifier {
                let keyCode = event.keyCode
                let chars = event.charactersIgnoringModifiers
                let hasCommand = event.modifierFlags.contains(.command)
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    if keyCode == 53 {
                        KeysPanelController.shared.close()
                        return true
                    }
                    if hasCommand, chars == "=" || chars == "+" {
                        KeysPanelController.shared.adjust(by: 0.1)
                        return true
                    }
                    if hasCommand, chars == "-" {
                        KeysPanelController.shared.adjust(by: -0.1)
                        return true
                    }
                    return false
                }
                return consumed ? nil : event
            }
            let consumed = MainActor.assumeIsolated { self?.handle(event) == true }
            return consumed ? nil : event
        }
    }

    /// Routes one key event through the grammar.
    ///
    /// True means consumed.
    func handle(_ event: NSEvent) -> Bool {
        guard gotoTarget == nil else { return false }
        // While any text field is live — the path headers, the naming field,
        // or the settings rsync flags field — every key belongs to the field.
        guard !left.pathEditing, !right.pathEditing, !operation.isNaming, !settingsFieldFocused else { return false }
        guard let token = Grammar.token(for: event) else { return false }
        // ⌘, reaches settings even while help or the field view is up.
        if token == "cmd-," {
            helpVisible = false
            fieldVisible = false
            settingsVisible.toggle()
            return true
        }
        let overlay = handleActiveOverlay(token)
        if overlay.handled { return overlay.consumed }
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
        // f summons the topology card — only from the main grammar path,
        // only when no chord is pending (c f is copyFilename, not field).
        if token == "f", pendingPrefix.isEmpty {
            fieldVisible = true
            fieldViewModel.summon(hosts: hosts)
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

    /// The panel's keys.
    ///
    /// Enter enacts, Esc dismisses or hides (a running enactment keeps
    /// going), ⌃C cancels — terminal muscle — and ? still summons the
    /// card. After a run ends, the verbs go straight again: y, m, r
    /// start the next operation without an Esc first. The app's own
    /// chords pass through untouched.
    private func handlePanelKey(_ token: String) -> Bool {
        if token == "return" { operation.enact() }
        if token == "esc" { operation.dismissOrCancel() }
        if token == "ctrl-c" { operation.cancelEnactment() }
        if token == "?" { helpVisible = true }
        let runOver =
            operation.phase == .finished || operation.phase == .failed
            || operation.phase == .cancelled
        if runOver {
            // The run is over — the grammar flows again; the next verb
            // clears the transcript and composes fresh.
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
                return !token.contains("cmd-")
            }
        }
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
        case .operationRename:
            beginNaming(.rename)
        case .operationCreate:
            beginNaming(.create)
        default:
            focusedPane.apply(intent)
        }
    }

    /// A verb goes down: the focused pane is the source, the other pane
    /// is the destination, the panel takes it from here.
    func beginOperation(_ operationKind: PlanOperation) {
        let destination = focusedSide == .left ? right : left
        operation.begin(operationKind, source: focusedPane, destination: destination)
    }

    /// R or a: opens the naming field on the focused pane — no destination needed.
    func beginNaming(_ operationKind: PlanOperation) {
        operation.beginNaming(operationKind, source: focusedPane)
    }

    /// The pane the focused one would send toward.
    var otherPane: PaneModel {
        focusedSide == .left ? right : left
    }

    /// The footer's send line.
    ///
    /// Where y and m would send, visible before any verb goes down —
    /// nil when there is nothing to say.
    var sendLine: String? {
        guard !operation.active, gotoTarget == nil, !helpVisible else { return nil }
        guard focusedPane.status == .ready, !focusedPane.operationSubjects.isEmpty else {
            return nil
        }
        guard otherPane.status == .ready, let host = otherPane.state.host else { return nil }
        return "sends → \(host):\(otherPane.state.path)"
    }

    // MARK: - Pane verbs (the divider cluster)

    /// Exchanges the two pointings — both panes re-read, ho-04's budget.
    func swapPanes() {
        guard let leftHost = left.state.host, let rightHost = right.state.host else { return }
        let leftPath = left.state.path
        let rightPath = right.state.path
        left.point(host: rightHost, path: rightPath)
        right.point(host: leftHost, path: leftPath)
    }

    /// Points one side where the other points — the mirror verb.
    func mirror(to side: SessionSnapshot.Side) {
        let source = side == .left ? right : left
        let target = side == .left ? left : right
        guard let host = source.state.host else { return }
        target.point(host: host, path: source.state.path)
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

// MARK: - Help, settings, and field overlay keys

extension PalanaSession {
    /// Routes a token to whichever overlay is currently active.
    ///
    /// Returns `(handled: true, consumed: <verdict>)` for each active
    /// card or panel, or `(handled: false, consumed: false)` when no
    /// overlay is showing — the caller falls through to the main grammar
    /// path. Extracting these four branches here keeps `handle(_:)`
    /// within the cyclomatic limit.
    private func handleActiveOverlay(_ token: String) -> (handled: Bool, consumed: Bool) {
        if helpVisible {
            // The vocabulary card holds the keyboard above everything;
            // app chords pass through, everything else waits.
            handleHelpKey(token)
            return (true, !token.contains("cmd-"))
        }
        if settingsVisible {
            // The settings card holds the keyboard; app chords pass through.
            handleSettingsKey(token)
            return (true, !token.contains("cmd-"))
        }
        if fieldVisible {
            // The topology card holds the keyboard; app chords pass through.
            handleFieldKey(token)
            return (true, !token.contains("cmd-"))
        }
        if operation.panelShowing {
            return (true, handlePanelKey(token))
        }
        return (false, false)
    }

    /// Routes one keystroke while the vocabulary card is up.
    ///
    /// Esc closes; ? trades the card for the floating panel; f trades it
    /// for the field.
    private func handleHelpKey(_ token: String) {
        if token == "esc" { helpVisible = false }
        if token == "?" {
            helpVisible = false
            floatingHelpTick += 1
        }
        if token == "f" {
            helpVisible = false
            fieldVisible = true
            fieldViewModel.summon(hosts: hosts)
        }
    }

    /// Routes one keystroke while the settings card is up.
    ///
    /// Esc dismisses; all other non-cmd keys are swallowed.
    private func handleSettingsKey(_ token: String) {
        if token == "esc" { settingsVisible = false }
    }

    /// Routes one keystroke while the topology overlay is up.
    ///
    /// j/k/down/up move the cursor; l/h/right/left expand and collapse;
    /// r reprobes; f and esc dismiss; tab switches the pane without
    /// closing the card; Enter points the focused pane and dismisses.
    private func handleFieldKey(_ token: String) {
        switch token {
        case "j", "down": fieldViewModel.cursorDown()
        case "k", "up": fieldViewModel.cursorUp()
        case "l", "right": fieldViewModel.toggleExpansion()
        case "h", "left": fieldViewModel.collapse()
        case "r": fieldViewModel.reprobe()
        case "f", "esc": fieldVisible = false
        case "tab":
            // The pointing target follows the focus dot — the card stays.
            focusedSide = focusedSide == .left ? .right : .left
            persist()
        case "return":
            guard let pointing = fieldViewModel.pointing() else { return }
            point(focusedSide, host: pointing.host, path: pointing.path)
            fieldVisible = false
        default: break
        }
    }
}
