// The operation flow — verb to plan to enactment to refreshed panes.
// The panel composes in the open: facts gather with their names shown,
// the Plan renders whole exactly once, and Enter arms only after it is
// readable. The Surface still composes nothing — every command here
// was composed by the engine and is shown before it runs.

import Foundation
import PalanaCore
import SwiftUI

/// One operation at a time: gathering, the plan, the enactment echo.
@MainActor
@Observable
final class OperationModel {
    /// Where the panel stands.
    enum Phase: Equatable {
        /// No operation — the panel is down.
        case idle
        /// The operator is typing a name — the panel shows the name field.
        case naming
        /// Facts on their way in, named as they land.
        case gathering
        /// The plan is on screen, whole. Enter is armed.
        case ready
        /// Enter fired — the echo is live.
        case enacting
        /// Every step ran, every gate proved.
        case finished
        /// A step, a gate, or the composition refused. Stays on screen.
        case failed
        /// The operator stopped it. Gated steps never ran.
        case cancelled
    }

    /// Where the panel stands.
    private(set) var phase = Phase.idle
    /// The composed plan, whole, once ready.
    private(set) var plan: Plan?
    /// The panel's transcript — gathering notes, then the run.
    private(set) var echo = EchoBuffer()
    /// The transfer step's latest progress observation.
    private(set) var progress: ProgressReport?
    /// What was asked — names the panel while the plan composes.
    private(set) var requested: PlanOperation?
    /// The label shown during naming — old name for rename, the hint for create.
    private(set) var namingLabel: String = ""
    /// The text the name field starts with — old name for rename, empty for create.
    private(set) var namingPrefill: String = ""
    /// The bare result name set when naming commits — the session lands the cursor here.
    private(set) var resultName: String?

    /// True whenever an operation exists, on screen or not.
    var active: Bool { phase != .idle }

    /// True while a command occupies the terminal — being composed, armed and
    /// awaiting Enter, or running.
    ///
    /// The tools strip greys out through all of it: no read may land while a
    /// plan is in process (the safety), and the emboldened enact chip is what
    /// the eye should reach for instead. Read buttons are live only in the
    /// resting phases — idle, finished, failed, cancelled.
    var terminalBusy: Bool { phase == .gathering || phase == .ready || phase == .enacting }

    /// True while the naming field is live — the key monitor stands down.
    var isNaming: Bool { phase == .naming }

    /// Whether the panel is on screen — the view, not the work.
    ///
    /// An enactment keeps running when the panel hides (second hands
    /// session: "the same terminal session running in the background").
    private(set) var panelShowing = false

    /// Fires when an enactment completes — the session refreshes panes.
    ///
    /// Set once, right after construction.
    var onFinished: @MainActor () -> Void = {}

    let engine: Engine
    private let configuration: SSHConfiguration
    private let settings: SettingsModel
    private let log: OperationLog
    private var gatherTask: Task<Void, Never>?
    private var enactTask: Task<Void, Never>?
    private var probedLocalCapability: HostCapability?
    private var pendingNamingEntry: FileEntry?
    private var pendingNamingSource: Locus?

    /// An operation flow over the session's engine.
    init(engine: Engine, configuration: SSHConfiguration, settings: SettingsModel) {
        self.engine = engine
        self.configuration = configuration
        self.settings = settings
        self.log = OperationLog()
    }

    // MARK: - Compose

    /// Opens the panel and composes — subjects from the source pane,
    /// destination from the other pane, facts gathered in the open.
    ///
    /// One enactment at a time: a new verb during a running enactment
    /// re-shows the panel and stops there. Any other active phase yields:
    /// gathering is cancelled and replaced; ready, finished, failed, and
    /// cancelled clear for a fresh begin.
    func begin(_ operation: PlanOperation, source: PaneModel, destination: PaneModel) {
        // One enactment at a time — a verb while running re-shows the panel.
        if phase == .enacting {
            panelShowing = true
            return
        }
        // A verb while composing cancels the gather; the new verb takes over.
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        // Naming is unreachable here (isNaming stands the monitor down), but
        // reset cleanly if somehow reached so the begin proceeds fresh.
        if phase == .naming { reset() }
        // .idle, .ready, .finished, .failed, .cancelled fall through to a fresh begin.
        guard let sourceHost = source.state.host, source.status == .ready else { return }
        panelShowing = true
        let subjects = source.operationSubjects
        guard !subjects.isEmpty else { return }
        requested = operation
        echo = EchoBuffer()
        progress = nil
        plan = nil
        // A stale name from a prior rename/create must not steer this
        // run's cursor landing.
        resultName = nil
        let sourceLocus = Locus(host: sourceHost, directory: source.state.path)
        var destinationLocus: Locus?
        if operation != .delete {
            guard let destinationHost = destination.state.host, destination.status == .ready else {
                phase = .failed
                echo.appendLine("the other pane is the destination — point it somewhere first", kind: .failure)
                return
            }
            destinationLocus = Locus(host: destinationHost, directory: destination.state.path)
        }
        phase = .gathering
        gatherTask = Task {
            await gather(
                operation, source: sourceLocus, destination: destinationLocus, subjects: subjects)
        }
    }

    private func gather(
        _ operation: PlanOperation,
        source: Locus,
        destination: Locus?,
        subjects: [FileEntry]
    ) async {
        do {
            var facts = PlanFacts()
            let sourceFacts = try await ensureFacts(source.host)
            var destinationFacts: HostFacts?
            if let destination {
                destinationFacts = try await ensureFacts(destination.host)
            }
            facts.sourceCapability =
                engine.isLocal(source.host)
                ? await localCapability() : sourceFacts?.capability?.value
            if let destination {
                facts.destinationCapability =
                    engine.isLocal(destination.host)
                    ? await localCapability() : destinationFacts?.capability?.value
            }
            if let topology = sourceFacts?.zfsTopology?.value {
                facts.sourceDataset = ZFSTopology.datasetContaining(
                    source.directory, in: topology)
                facts.selectionWholeDataset = ZFSTopology.wholeDatasetSelection(
                    entries: subjects, sourceDirectory: source.directory, datasets: topology)
            }
            if let destination, let topology = destinationFacts?.zfsTopology?.value {
                facts.destinationDataset = ZFSTopology.datasetContaining(
                    destination.directory, in: topology)
            }
            if let destination, needsForwardingFact(source: source, destination: destination) {
                note("asking whether \(source.host) reaches \(destination.host)…")
                facts.agentForwarding = await engine.field.forwardingFact(
                    from: source.host, to: destination.host)
            }
            let directories = subjects.filter { $0.kind == .directory }
            if !directories.isEmpty {
                note("measuring \(directories.count) \(directories.count == 1 ? "directory" : "directories")…")
                let flavor = try await resolveFlavor(source.host)
                let paths = directories.map {
                    PaneModel.childPath(of: source.directory, name: $0.name)
                }
                let sizes = try await engine.listing(for: source.host)
                    .treeSizes(on: source.host, paths: paths, flavor: flavor)
                for (directory, size) in zip(directories, sizes) {
                    facts.recursiveSizes[directory.id] = size
                }
            }
            await gatherCollisionsIfNeeded(destination: destination, subjects: subjects, into: &facts)
            guard !Task.isCancelled else { return }
            facts.rsyncOperatorFlags = settings.effectiveRsyncFlags
            let request = PlanRequest(
                operation: operation,
                source: source,
                entries: subjects,
                destination: destination,
                token: Self.mintToken())
            plan = try PlanEngine.plan(request, facts: facts)
            phase = .ready
        } catch {
            guard !Task.isCancelled else { return }
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
        }
    }

    /// The forwarding question exists only between two distinct
    /// remotes — this machine at either end authenticates itself.
    private func needsForwardingFact(source: Locus, destination: Locus) -> Bool {
        destination.host != source.host
            && !engine.isLocal(source.host)
            && !engine.isLocal(destination.host)
    }

    /// This Mac's own capability — probed once per session, in memory.
    ///
    /// The engine flags rsync commands by the running side's rsync;
    /// this machine's answer decides whether progress2 rides.
    private func localCapability() async -> HostCapability? {
        if let probedLocalCapability { return probedLocalCapability }
        guard
            let result = try? await engine.localConduit
                .run(on: PalanaCore.localHostName, CapabilityProbe.command).collect(),
            let capability = try? CapabilityProbe.parse(result.stdoutText)
        else { return nil }
        probedLocalCapability = capability
        return capability
    }

    /// Remembered facts, or one discovery when the host was never met.
    private func ensureFacts(_ host: String) async throws -> HostFacts? {
        guard !engine.isLocal(host) else { return nil }
        if let facts = await engine.field.facts(for: host) { return facts }
        note("discovering \(host)…")
        return try await engine.field.discover(host)
    }

    /// The flavor fact — this Mac is BSD, remotes answer from memory or
    /// one discovery round trip.
    func resolveFlavor(_ host: String) async throws -> UserlandFlavor {
        if engine.isLocal(host) { return .bsd }
        if let flavor = await engine.field.facts(for: host)?.capability?.value.flavor {
            return flavor
        }
        let facts = try await engine.field.discover(host)
        guard let flavor = facts.capability?.value.flavor else {
            throw ListingError.listingFailed(exitStatus: -1, stderr: "no capability fact")
        }
        return flavor
    }

    // MARK: - Enact

    /// Enter — runs the plan exactly as read, echoing everything.
    func enact() {
        guard phase == .ready, let plan else { return }
        phase = .enacting
        // Open the log session: blank separator then the run header.
        log.appendLine("")
        log.appendLine(OperationLog.headerLine(for: plan))
        let transports = Transports(
            conduit: RoutingConduit(remote: engine.conduit), configuration: configuration)
        enactTask = Task {
            do {
                for try await event in transports.enact(plan) {
                    handle(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                echo.flushAll()
                let errorText = Self.describe(error)
                echo.appendLine(errorText, kind: .failure)
                log.appendLine("! \(errorText)")
                progress = nil
                phase = .failed
                // A failure never stays off-screen.
                panelShowing = true
            }
        }
    }

    private func handle(_ event: EnactmentEvent) {
        switch event {
        case .stepBegan(_, let step):
            echo.flushAll()
            echo.appendLine("$ \(step.command)", kind: .command)
            log.appendLine("$ \(step.command)")
        case .outputChunk(_, let channel, let data):
            echo.append(data, channel: channel)
            // Log raw decoded output — chunks carry their own newlines.
            // Lossy decode on purpose: the log shows what arrived, the same
            // policy EchoBuffer applies for display.
            // swiftlint:disable:next optional_data_string_conversion
            let text = String(decoding: data, as: UTF8.self)
            if !text.isEmpty { log.appendRaw(text) }
        case .progress(let report):
            progress = report
        case .verifying(let host, let command):
            echo.flushAll()
            echo.appendLine("verify on \(host): $ \(command)", kind: .note)
            log.appendLine("# verify on \(host): $ \(command)")
        case .verified(let report):
            let reportText = Self.describe(report)
            echo.appendLine(reportText, kind: .note)
            log.appendLine("# \(reportText)")
        case .stepEnded(let index, let exitStatus):
            echo.flushAll()
            progress = nil
            echo.appendLine("step \(index + 1) exited \(exitStatus)", kind: .note)
            log.appendLine("# step \(index + 1) exited \(exitStatus)")
        case .finished:
            echo.flushAll()
            echo.appendLine("enacted — every step ran, every gate proved", kind: .note)
            log.appendLine("# enacted — every step ran, every gate proved")
            phase = .finished
            onFinished()
            // A run that finished off-screen closes its own books.
            if !panelShowing {
                reset()
            }
        }
    }

    // MARK: - Dismiss and cancel

    /// Esc — the view's verb, never the work's.
    ///
    /// Dismisses before Enter, hides during (the work continues),
    /// closes after. Cancelling is ⌃C's job, terminal muscle.
    func dismissOrCancel() {
        switch phase {
        case .idle:
            break
        case .naming:
            reset()
        case .gathering:
            gatherTask?.cancel()
            reset()
        case .ready, .finished, .failed, .cancelled:
            reset()
        case .enacting:
            panelShowing = false
        }
    }

    /// Backtick from the main grammar — shows the panel without starting an operation.
    ///
    /// Phase is never touched. Showing an idle panel is fine — the operator
    /// sees an empty terminal that says what it is. `hidePanel()` is the partner.
    func showPanel() {
        panelShowing = true
    }

    /// Backtick from within the panel — pure visibility hide, phase untouched.
    ///
    /// An enactment in progress keeps running exactly as Esc-hide does today;
    /// neither the work nor the phase is changed. `dismissOrCancel()` handles Esc.
    func hidePanel() {
        panelShowing = false
    }

    /// ⌃C — stops a running enactment where Esc only hides it.
    func cancelEnactment() {
        guard phase == .enacting else { return }
        enactTask?.cancel()
        echo.flushAll()
        echo.appendLine(
            "cancelled — gated steps never ran; an interrupted transfer can leave "
                + "partial entries at the destination",
            kind: .failure)
        progress = nil
        phase = .cancelled
        panelShowing = true
    }

    /// ⌃C during composition — stops the in-flight gather and resets.
    ///
    /// The cancelled gather's task checks `Task.isCancelled` and returns
    /// silently; no failure path fires. The panel stays visible with the
    /// cancellation noted.
    func cancelGathering() {
        guard phase == .gathering else { return }
        gatherTask?.cancel()
        gatherTask = nil
        echo.flushAll()
        echo.appendLine("cancelled — composition stopped", kind: .failure)
        phase = .cancelled
        panelShowing = true
    }

    /// First Esc on a command in process — cancel it, but stay open.
    ///
    /// A composing or armed plan resets to idle; a running transfer is cancelled
    /// (⌃C's path, with its partial-transfer warning left in the transcript). The
    /// panel stays open showing the cancelled state, so the *second* Esc is what
    /// closes the terminal — one keystroke is never both acts at once (too abrupt).
    func cancelCommand() {
        switch phase {
        case .gathering: cancelGathering()
        case .enacting: cancelEnactment()
        case .ready: reset()
        default: break
        }
        panelShowing = true
    }

    private func reset() {
        phase = .idle
        plan = nil
        echo = EchoBuffer()
        progress = nil
        requested = nil
        panelShowing = false
        namingLabel = ""
        namingPrefill = ""
        resultName = nil
        pendingNamingEntry = nil
        pendingNamingSource = nil
    }
}

// MARK: - Lines

extension OperationModel {
    func note(_ text: String) {
        echo.appendLine(text, kind: .note)
    }

    /// Uniquifies composed snapshot names — the engine is pure and
    /// mints nothing, so the caller stamps the moment.
    private static func mintToken() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "palana-\(formatter.string(from: Date()))"
    }

    private static func describe(_ report: VerificationReport) -> String {
        switch report {
        case .counts(let source, let destination):
            let verdict = source == destination ? "match" : "MISMATCH"
            return "counted \(source) at source, \(destination) at destination — \(verdict)"
        case .datasetReceived(let name, let exists):
            return exists
                ? "dataset \(name) exists at the destination"
                : "dataset \(name) is MISSING at the destination"
        }
    }

    /// One sentence per failure — typed errors say what they are.
    private static func describe(_ error: any Error) -> String {
        if let text = describePlanError(error) { return text }
        switch error {
        case EnactmentError.stepFailed(let index, let status, let stderrTail):
            let tail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            return "step \(index + 1) failed (\(status))\(tail.isEmpty ? "" : ": \(tail)")"
        case EnactmentError.verificationFailed:
            return "verification did not match — gated steps never ran, the source stands untouched"
        case EnactmentError.verificationUnavailable(let host, let detail):
            return "the count on \(host) could not run — the gate stays closed: \(detail)"
        case EnactmentError.malformedPlan(let detail):
            return "the plan's shape was not one enactment knows — worth reporting: \(detail)"
        case ListingError.permissionDenied(let path):
            return "permission denied: \(path)"
        case ListingError.listingFailed(_, let stderr):
            return "a fact could not be gathered: \(stderr)"
        case let conduitError as ConduitError:
            return "\(conduitError)"
        default:
            return "\(error)"
        }
    }

    /// Translates PlanError cases to one-sentence descriptions, nil for non-PlanErrors.
    private static func describePlanError(_ error: any Error) -> String? {
        switch error {
        case PlanError.emptySelection:
            return "nothing selected — there is nothing to plan"
        case PlanError.missingDestination:
            return "the other pane is the destination — point it somewhere first"
        case PlanError.unrepresentableName:
            return "an entry's name does not survive composition — refusing rather than guessing"
        case PlanError.renameRequiresOneEntry:
            return "rename operates on one entry — cursor on exactly one"
        case PlanError.targetNameRequired:
            return "a name is required"
        case PlanError.targetNameUnchanged:
            return "the name did not change"
        case PlanError.targetNameContainsSeparator:
            return "a name cannot contain path separators"
        case PlanError.entriesForbiddenForCreate:
            return "create needs an empty selection — deselect first"
        case PlanError.destinationForbidden:
            return "rename and create stay in the source directory — no destination"
        default:
            return nil
        }
    }
}

// MARK: - Tool reads

extension OperationModel {
    /// Writes a Workbench read into the transcript without changing phase.
    ///
    /// The strip's scrollback — successive reads accumulate; `begin` resets
    /// `echo` when a real operation starts so the plan's claim is never blurred.
    func runToolRead(header: String, stream: RunningCommand) async {
        showPanel()
        echo.appendLine("── \(header)", kind: .note)
        for await chunk in stream.stdout {
            echo.append(chunk, channel: .stdout)
        }
        for await chunk in stream.stderr {
            echo.append(chunk, channel: .stderr)
        }
        echo.flushAll()
    }

    /// Writes a tool-level failure into the transcript without changing phase.
    func appendToolError(_ text: String) {
        showPanel()
        echo.appendLine(text, kind: .failure)
    }

    /// ⌘K — clears the terminal transcript, phase untouched.
    func clearTranscript() {
        echo = EchoBuffer()
    }
}

// MARK: - Touch

extension OperationModel {
    /// t: opens the panel and composes a touch plan immediately — no
    /// gathering, no naming. touch needs no facts: it stays in place
    /// and the exit status is its verification.
    ///
    /// Subjects follow the same law as the other verbs — the selection
    /// when non-empty, else the cursor entry. Phase law mirrors `begin`.
    func beginTouch(source: PaneModel) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        guard let sourceHost = source.state.host, source.status == .ready else { return }
        let subjects = source.operationSubjects
        guard !subjects.isEmpty else { return }
        panelShowing = true
        requested = .touch
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        let request = PlanRequest(
            operation: .touch,
            source: Locus(host: sourceHost, directory: source.state.path),
            entries: subjects,
            token: Self.mintToken())
        do {
            plan = try PlanEngine.plan(request, facts: PlanFacts())
            phase = .ready
        } catch {
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
        }
    }
}

// MARK: - Naming

extension OperationModel {
    /// Opens the panel with a name field for rename or create.
    ///
    /// For rename the field prefills with the cursor entry's name and selects
    /// all text. For create the field is empty. While the field is live, the
    /// key monitor stands down — typed letters belong to the field.
    /// `labelOverride` replaces the default create label — T uses this to
    /// give the touch-new entry point its own descriptive prompt.
    /// Phase law mirrors `begin`.
    func beginNaming(_ operation: PlanOperation, source: PaneModel, labelOverride: String? = nil) {
        if phase == .enacting {
            panelShowing = true
            return
        }
        if phase == .gathering {
            gatherTask?.cancel()
            gatherTask = nil
        }
        if phase == .naming { reset() }
        guard let sourceHost = source.state.host, source.status == .ready else { return }
        if operation == .rename {
            guard let entry = source.cursorEntry else { return }
            pendingNamingEntry = entry
            namingPrefill = entry.name
            namingLabel = "rename: \(entry.name)"
        } else {
            pendingNamingEntry = nil
            namingPrefill = ""
            namingLabel = labelOverride ?? "create  (trailing / = directory)"
        }
        pendingNamingSource = Locus(host: sourceHost, directory: source.state.path)
        requested = operation
        echo = EchoBuffer()
        progress = nil
        plan = nil
        resultName = nil
        phase = .naming
        panelShowing = true
    }

    /// Called by the name field's onSubmit — builds the plan or dismisses quietly.
    ///
    /// An empty or unchanged (rename) name dismisses without a plan. A name the
    /// engine refuses renders as a failure in the panel. A good name composes
    /// immediately — rename and create need no fact gathering.
    func commitNaming(_ name: String) {
        guard phase == .naming, let operation = requested,
            let source = pendingNamingSource
        else {
            reset()
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            reset()
            return
        }
        if operation == .rename, let entry = pendingNamingEntry, trimmed == entry.name {
            reset()
            return
        }
        let entries: [FileEntry] =
            operation == .rename
            ? (pendingNamingEntry.map { [$0] } ?? [])
            : []
        // The bare name for cursor landing — create directory names carry a trailing
        // slash in the request (signals mkdir) but land without it.
        let bareName: String =
            operation == .create && trimmed.hasSuffix("/")
            ? String(trimmed.dropLast())
            : trimmed
        let request = PlanRequest(
            operation: operation,
            source: source,
            entries: entries,
            destination: nil,
            token: Self.mintToken(),
            targetName: trimmed
        )
        do {
            plan = try PlanEngine.plan(request, facts: PlanFacts())
            resultName = bareName
            phase = .ready
        } catch {
            echo.appendLine(Self.describe(error), kind: .failure)
            phase = .failed
            panelShowing = true
        }
    }
}
