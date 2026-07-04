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

    /// True whenever the panel is up.
    var active: Bool { phase != .idle }

    /// Fires when an enactment completes — the session refreshes panes.
    ///
    /// Set once, right after construction.
    var onFinished: @MainActor () -> Void = {}

    private let engine: Engine
    private let configuration: SSHConfiguration
    private var gatherTask: Task<Void, Never>?
    private var enactTask: Task<Void, Never>?
    private var probedLocalCapability: HostCapability?

    /// An operation flow over the session's engine.
    init(engine: Engine, configuration: SSHConfiguration) {
        self.engine = engine
        self.configuration = configuration
    }

    // MARK: - Compose

    /// Opens the panel and composes — subjects from the source pane,
    /// destination from the other pane, facts gathered in the open.
    func begin(_ operation: PlanOperation, source: PaneModel, destination: PaneModel) {
        guard phase == .idle else { return }
        guard let sourceHost = source.state.host, source.status == .ready else { return }
        let subjects = source.operationSubjects
        guard !subjects.isEmpty else { return }
        requested = operation
        echo = EchoBuffer()
        progress = nil
        plan = nil
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
            guard !Task.isCancelled else { return }
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
    private func resolveFlavor(_ host: String) async throws -> UserlandFlavor {
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
                echo.appendLine(Self.describe(error), kind: .failure)
                progress = nil
                phase = .failed
            }
        }
    }

    private func handle(_ event: EnactmentEvent) {
        switch event {
        case .stepBegan(_, let step):
            echo.flushAll()
            echo.appendLine("$ \(step.command)", kind: .command)
        case .outputChunk(_, let channel, let data):
            echo.append(data, channel: channel)
        case .progress(let report):
            progress = report
        case .verifying(let host, let command):
            echo.flushAll()
            echo.appendLine("verify on \(host): $ \(command)", kind: .note)
        case .verified(let report):
            echo.appendLine(Self.describe(report), kind: .note)
        case .stepEnded(let index, let exitStatus):
            echo.flushAll()
            progress = nil
            echo.appendLine("step \(index + 1) exited \(exitStatus)", kind: .note)
        case .finished:
            echo.flushAll()
            echo.appendLine("enacted — every step ran, every gate proved", kind: .note)
            phase = .finished
            onFinished()
        }
    }

    // MARK: - Dismiss

    /// Esc — dismisses before Enter, cancels during, closes after.
    func dismissOrCancel() {
        switch phase {
        case .idle:
            break
        case .gathering:
            gatherTask?.cancel()
            reset()
        case .ready, .finished, .failed, .cancelled:
            reset()
        case .enacting:
            enactTask?.cancel()
            echo.flushAll()
            echo.appendLine(
                "cancelled — gated steps never ran; an interrupted transfer can leave "
                    + "partial entries at the destination",
                kind: .failure)
            progress = nil
            phase = .cancelled
        }
    }

    private func reset() {
        phase = .idle
        plan = nil
        echo = EchoBuffer()
        progress = nil
        requested = nil
    }

    // MARK: - Lines

    private func note(_ text: String) {
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
        switch error {
        case PlanError.emptySelection:
            return "nothing selected — there is nothing to plan"
        case PlanError.missingDestination:
            return "the other pane is the destination — point it somewhere first"
        case PlanError.unrepresentableName:
            return "an entry's name does not survive composition — refusing rather than guessing"
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
}
