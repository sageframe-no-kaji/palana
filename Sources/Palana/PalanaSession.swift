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
    /// The host map panel's view model — shared with HostMapPanelController.
    let hostMapModel: HostMapModel
    /// The hosts the Field knows — the go-to bar's menu.
    ///
    /// Visible hosts only: hidden aliases (marked `# palana: hide` in the
    /// ssh config) are filtered out. Typed addresses in the path header
    /// are never filtered — the filter is a curtain, not a lock.
    private(set) var hosts: [String] = []
    /// The settings model — rsync flags and host-hide controls.
    let settings: SettingsModel

    /// The tool coordinator — aimed at each host via the routing conduit.
    let workbench: Workbench
    /// The built-in system reads tool — stateless, shared with the strip.
    let readsTool: SystemReadsTool
    /// True while the keyboard points into the terminal strip.
    var terminalFocused = false

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
        self.workbench = Workbench(conduit: RoutingConduit(remote: conduit), field: field)
        self.readsTool = SystemReadsTool()
        self.recognizer = SequenceRecognizer(bindings: Grammar.bindings)
        self.engine = Engine(conduit: conduit, field: field, listing: Listing(conduit: conduit))
        self.fieldViewModel = FieldViewModel(engine: self.engine)
        self.hostMapModel = HostMapModel(engine: self.engine)
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
            if event.window?.identifier?.rawValue == HostMapPanelController.identifier {
                let keyCode = event.keyCode
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    if keyCode == 53 {
                        HostMapPanelController.shared.close()
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
        guard !terminalFocused else { return handleTerminalFocusKey(token) }
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
        // f, F, and backtick bypass the recognizer — only from the main grammar
        // path, only when no chord is pending (c f is copyFilename, not field).
        if handleMainSpecialKey(token) { return true }
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

    /// Panel priority keys — consumed while the panel is visible, regardless of phase.
    ///
    /// Grammar flows while the panel is showing: only this small set is
    /// handled here; all other tokens (navigation, verbs, chords) fall
    /// through to the main grammar path exactly as when the panel is hidden.
    /// This means the operator can walk trees, switch panes, and fire new
    /// verbs without hiding the panel first.
    ///
    /// - esc / backtick: pure visibility hide — phase and work untouched.
    /// - return: enacts only when a plan is ready; otherwise falls through
    ///   so Enter walks/opens in the pane.
    /// - ⌃C: cancels an enactment or a composition; not a priority key in
    ///   other phases.
    /// - ?: help card. f/F: field card / host map.
    private func handlePanelPriorityKey(_ token: String) -> Bool {
        switch token {
        case "esc":
            // Pure visibility hide in every phase — work continues untouched.
            // The Esc that follows (panel now gone) clears the selection.
            terminalFocused = false
            operation.hidePanel()
            return true
        case "`":
            terminalFocused = false
            operation.hidePanel()
            return true
        case "return":
            // Arms only when a plan is ready; otherwise Enter walks/opens in the pane.
            guard operation.phase == .ready else { return false }
            operation.enact()
            return true
        case "ctrl-c":
            if operation.phase == .enacting {
                operation.cancelEnactment()
            } else if operation.phase == .gathering {
                operation.cancelGathering()
            } else {
                return false
            }
            return true
        case "?":
            helpVisible = true
            return true
        case "f":
            helpVisible = false
            fieldVisible = true
            fieldViewModel.summon(hosts: hosts)
            return true
        case "F":
            HostMapPanelController.shared.toggle(model: hostMapModel, hosts: hosts)
            return true
        default:
            return false
        }
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
        case .operationTouch:
            beginOperation(.touch)
        case .operationTouchNew:
            // T: names a new file or directory then composes a create plan.
            // The create engine already handles both files and directories
            // (trailing / = directory); only the naming prompt differs.
            operation.beginNaming(
                .create,
                source: focusedPane,
                labelOverride: "touch: new file name  (trailing / = directory)")
        default:
            focusedPane.apply(intent)
        }
    }

    /// A verb goes down: the focused pane is the source, the other pane
    /// is the destination, the panel takes it from here.
    ///
    /// touch stays in place — no destination, no gathering; the plan
    /// composes the moment the verb lands.
    func beginOperation(_ operationKind: PlanOperation) {
        guard operationKind != .touch else {
            operation.beginTouch(source: focusedPane)
            return
        }
        let destination = focusedSide == .left ? right : left
        operation.begin(operationKind, source: focusedPane, destination: destination)
    }

    /// R or a: opens the naming field on the focused pane — no destination needed.
    func beginNaming(_ operationKind: PlanOperation) {
        operation.beginNaming(operationKind, source: focusedPane)
    }

    /// ⌘⇧L: points the focused pane at the operations log's directory and
    /// seats the cursor on operations.log — the run record, one keystroke away.
    ///
    /// The log lives on this Mac. If no run has written it yet the file is
    /// absent, the landing simply misses, and the pane shows the directory —
    /// nothing is fabricated to make the cursor land.
    func revealOperationsLog() {
        let logURL = OperationLog.defaultURL()
        focusedPane.setLandOn(logURL.lastPathComponent)
        focusedPane.point(host: Engine.localHost, path: logURL.deletingLastPathComponent().path)
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
    /// Handles f, F, and backtick — the three tokens that bypass the recognizer.
    ///
    /// All three are gated on `pendingPrefix.isEmpty` so multi-key chords
    /// (`c f` = copyFilename) are not intercepted. Returns true when consumed.
    /// Backtick (`` ` ``) shows the plan panel; phase and work are untouched.
    private func handleMainSpecialKey(_ token: String) -> Bool {
        guard pendingPrefix.isEmpty else { return false }
        if token == "f" {
            fieldVisible = true
            fieldViewModel.summon(hosts: hosts)
            return true
        }
        if token == "F" {
            HostMapPanelController.shared.toggle(model: hostMapModel, hosts: hosts)
            return true
        }
        if token == "`" {
            operation.showPanel()
            return true
        }
        if token == "cmd-shift-l" {
            revealOperationsLog()
            return true
        }
        if token == "shift-tab" {
            if !operation.panelShowing { operation.showPanel() }
            terminalFocused = true
            return true
        }
        return false
    }

    /// Routes a token to whichever overlay is currently active.
    ///
    /// Returns `(handled: true, consumed: <verdict>)` for each active
    /// card or panel, or `(handled: false, consumed: false)` when no
    /// overlay is showing — the caller falls through to the main grammar
    /// path. Extracting these four branches here keeps `handle(_:)`
    /// within the cyclomatic limit.
    ///
    /// The plan panel is not modal: only its priority set is consumed here;
    /// everything else falls through to the main grammar path so navigation
    /// and verbs work exactly as when the panel is hidden.
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
            // Grammar flows — only the priority set is consumed here.
            if handlePanelPriorityKey(token) { return (true, true) }
            return (false, false)
        }
        return (false, false)
    }

    /// Routes one keystroke while the vocabulary card is up.
    ///
    /// Esc closes; ? trades the card for the floating panel; f trades it
    /// for the field; F closes help and toggles the host map panel.
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
        if token == "F" {
            helpVisible = false
            HostMapPanelController.shared.toggle(model: hostMapModel, hosts: hosts)
        }
    }

    /// Routes one keystroke while the settings card is up.
    ///
    /// Esc dismisses; f trades settings for the field card; F toggles the
    /// host map panel (settings stays up — the map floats independent).
    /// All other non-cmd keys are swallowed.
    private func handleSettingsKey(_ token: String) {
        if token == "esc" { settingsVisible = false }
        if token == "f" {
            settingsVisible = false
            fieldVisible = true
            fieldViewModel.summon(hosts: hosts)
        }
        if token == "F" {
            HostMapPanelController.shared.toggle(model: hostMapModel, hosts: hosts)
        }
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

// MARK: - Workbench and terminal focus

extension PalanaSession {
    /// Routes a key press while the keyboard points into the terminal strip.
    ///
    /// Panel priority keys (esc, backtick) are handled earlier and clear
    /// `terminalFocused` — this path covers tab, shift-tab, the tool key
    /// hints, and everything else while the strip holds focus.
    func handleTerminalFocusKey(_ token: String) -> Bool {
        switch token {
        case "tab", "shift-tab", "esc":
            terminalFocused = false
        default:
            // A key hint fires the matching verb; all other keys are swallowed
            // so the pane grammar stays suspended while the strip holds focus.
            if let verb = readsTool.verbs.first(where: { $0.keyHint == token }) {
                runWorkbenchVerb(verb)
            }
        }
        return true
    }

    /// Runs a Workbench read verb against the focused host.
    ///
    /// Checks availability, starts the read, and drains raw output into the
    /// transcript. Phase is never touched — a read is not an operation.
    func runWorkbenchVerb(_ verb: WorkbenchVerb) {
        guard !operation.active else { return }
        guard let host = focusedPane.state.host else { return }
        // Local honesty: zfs verbs are not applicable on this Mac.
        guard !(verb.requirement == .zfs && host == PalanaCore.localHostName) else { return }
        Task {
            let avail = await workbench.availability(of: verb, on: host)
            guard case .available = avail else { return }
            guard !operation.active else { return }
            do {
                let stream = try await workbench.run(verb, of: readsTool, on: host)
                let cmd = readsTool.command(for: verb, on: host)
                await operation.runToolRead(header: "\(cmd) · \(host)", stream: stream)
            } catch {
                operation.appendToolError("read failed: \(error)")
            }
        }
    }
}
