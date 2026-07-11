// The plan panel — monospace's only home in the app, per the design
// language. The Plan's commands display here before enactment, and
// when Enter fires the enactment echoes here live: real commands, real
// output, streaming. The panel renders values and forwards nothing —
// the keyboard's Enter and Esc live in the session.
//
// ho-11 grows a third mode: shell mode swaps the transcript (and the
// tools strip beside it) for the focused pane's live session, full
// panel height. The header stays — orientation never disappears — but
// its hint line trades the phase word for the exit copy while the shell
// shows.

import PalanaCore
import SwiftTerm
import SwiftUI

/// The bottom surface: the plan whole, then the run live.
struct PlanPanel: View {
    /// The operation flow this panel renders.
    var operation: OperationModel
    /// The session — drives the tools strip on the trailing edge.
    var session: PalanaSession
    /// Called when a go-again chip is clicked — the key string is the same
    /// token the keyboard grammar produces for that key, so the session can
    /// route it through the same dispatch path the physical key takes.
    var onVerbKey: (String) -> Void = { _ in }

    @FocusState private var namingFieldFocused: Bool
    @State private var nameText = ""

    private var mono: Font { .system(size: 13 * session.fontScale, design: .monospaced) }
    // The header chrome stays fixed — only the transcript zooms with ⌘+/⌘-.
    private let monoSmall = Font.system(size: 12, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if session.shellVisible, let host = session.shellHost {
                // Full panel height — the strip yields too. The leading
                // engagement line names who has the keyboard, the same
                // vocabulary the strip's edge speaks; ⌘` flips it.
                TerminalHostView(
                    view: session.terminalSessions.session(for: host),
                    fontSize: 13 * session.fontScale,
                    focused: session.shellFocused
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(session.shellFocused ? 1.0 : 0.75)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(
                            session.shellFocused
                                ? Theme.accent : Theme.inkFaint.opacity(0.18)
                        )
                        .frame(width: session.shellFocused ? 2 : 1)
                        .animation(.easeInOut(duration: 0.12), value: session.shellFocused)
                }
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                if operation.phase == .naming {
                                    namingFieldView
                                } else {
                                    // Every ready plan says what Enter does, in
                                    // green, in the terminal — the round-trip's
                                    // callout stays custom when it set one.
                                    if operation.phase == .ready {
                                        Text(
                                            operation.readyCallout
                                                ?? "⏎ press enter to run this plan · esc dismisses it"
                                        )
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .padding(.bottom, 4)
                                    }
                                    if let plan = operation.plan {
                                        planBlock(plan)
                                    }
                                    transcript
                                }
                                Color.clear.frame(height: 1).id("panel-bottom")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .onChange(of: operation.echo.revision) {
                            // The revision moves on every mutation. Watching the
                            // last line missed most of a live run: commits land
                            // above a live progress partial, and the tail's id
                            // and text never change.
                            proxy.scrollTo("panel-bottom", anchor: .bottom)
                        }
                    }
                    // Strip beside the plan/transcript only — not over the naming field.
                    if operation.phase != .naming {
                        WorkbenchStrip(session: session)
                    }
                }
                if let progress = operation.progress {
                    progressBar(progress)
                }
            }
        }
        .font(mono)
        .background(Theme.panelGround)
        .task(id: operation.phase) {
            guard operation.phase == .naming else { return }
            nameText = operation.namingPrefill
            namingFieldFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(phaseWord)
                .foregroundStyle(Theme.ink)
                .fontWeight(.semibold)
            Spacer()
            hintView
        }
        .font(monoSmall)
        .frame(height: 30)
        .padding(.horizontal, 14)
    }

    private var phaseWord: String {
        let verb = operation.requested.map { "\($0.rawValue) · " } ?? ""
        switch operation.phase {
        case .idle: return ""
        case .naming: return "\(verb)naming"
        case .gathering: return "\(verb)checking…"
        case .ready: return "\(verb)the plan"
        case .enacting: return "\(verb)running…"
        case .finished: return "\(verb)done"
        case .failed: return "\(verb)failed"
        case .cancelled: return "\(verb)cancelled"
        }
    }

    /// The Return action, called out as a filled chip.
    ///
    /// Present when a keystroke will fire—the plan ready to enact, or the
    /// naming field awaiting its name. Nil in every resting or in-flight
    /// phase, where nothing is armed.
    private var enactCallout: String? {
        switch operation.phase {
        case .ready: return "⏎ enter runs"
        case .naming: return "⏎ enter commits"
        default: return nil
        }
    }

    /// The phase-specific hint text rendered left of the verb rail's esc chip.
    ///
    /// Returns nil when no per-phase prefix is needed — finished/failed/
    /// cancelled have no extra context worth naming there.
    private var verbRailHintText: String? {
        switch operation.phase {
        case .idle: return nil
        case .naming: return "esc cancel"
        case .gathering: return "⌃c cancels"
        case .ready: return "a new verb rebuilds the plan"
        case .enacting: return "keeps running · ⌃c cancels"
        case .finished, .failed, .cancelled: return nil
        }
    }

    /// Whether the verb chip rail is interactive (full opacity, clickable).
    ///
    /// Enabled in the resting and terminal phases — idle, ready, finished,
    /// failed, cancelled. Dimmed and inert while work is in flight —
    /// gathering, enacting, naming — matching the workbench strip's posture.
    private var verbRailEnabled: Bool {
        switch operation.phase {
        case .idle, .ready, .finished, .failed, .cancelled: return true
        case .gathering, .enacting, .naming: return false
        }
    }

    /// The header hint — a full-height accent block calls out the live Return
    /// action (moss ground, light letters, square to the header lines), the
    /// verb chip rail is always beside it.
    @ViewBuilder private var hintView: some View {
        HStack(spacing: 10) {
            if let callout = enactCallout {
                // Wider block, bigger type than the header line — the armed
                // Return is the one thing the operator must not miss.
                Text(callout)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.ground)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
                    .background(Theme.accent)
            }
            VerbChipRow(
                fontSize: 12,
                enabled: verbRailEnabled,
                hintText: verbRailHintText,
                onVerbKey: onVerbKey
            )
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - The naming field

    @ViewBuilder private var namingFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(operation.namingLabel)
                .foregroundStyle(Theme.accent)
                .fontWeight(.semibold)
            // The model's flag, not the verb's static spec — destroy grows
            // a field when the typed confirmation is on.
            let zfsNeedsTextField =
                operation.pendingZFSVerb == nil
                || operation.zfsGatherWantsText
            if zfsNeedsTextField {
                // Standard file ops and ZFS text verbs both show the field.
                TextField("", text: $nameText)
                    .textFieldStyle(.plain)
                    .focused($namingFieldFocused)
                    .onSubmit { operation.commitNaming(nameText) }
                    .onExitCommand { operation.dismissOrCancel() }
                    .onChange(of: namingFieldFocused) { _, focused in
                        // A click elsewhere must not strand the grammar behind
                        // isNaming — focus loss cancels, the path header's law.
                        if !focused, operation.isNaming {
                            operation.dismissOrCancel()
                        }
                    }
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Theme.accent, lineWidth: 2)
                    )
            } else {
                // Field-less gather (destroy): no text field. The key monitor
                // stands down (isNaming) so typed keys never reach the panes;
                // Return and Esc are routed through the monitor's field-less
                // branch in PalanaSession.handle(_:). Nothing to render here.
                EmptyView()
            }
            if operation.pendingZFSVerb?.gather?.offersRecursive == true {
                Toggle(
                    isOn: Binding(
                        get: { operation.zfsRecursive },
                        set: { operation.zfsRecursive = $0 }
                    )
                ) {
                    Text("recursive — includes everything beneath")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink)
                }
                .toggleStyle(.checkbox)
            }
            // The gather's context — the dataset's snapshot names during a
            // rollback or destroy-snapshot gather, read off the wire so the
            // operator copies instead of remembering.
            if !operation.namingContextLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(operation.namingContextLines, id: \.self) { line in
                        Text(line)
                            .foregroundStyle(Theme.inkFaint)
                            .textSelection(.enabled)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - The plan, whole

    @ViewBuilder
    private func planBlock(_ plan: Plan) -> some View {
        Text("\(plan.operation.rawValue) · \(plan.classification.plainName)")
            .foregroundStyle(Theme.ink)
            .fontWeight(.semibold)
        // The size line is noise beside a ZFS dataset mutation — a dataset
        // command acts on the dataset, not on a counted file selection.
        if plan.operation != .zfs {
            Text(sizeLine(plan))
                .foregroundStyle(plan.totalSizeComplete ? Theme.inkFaint : Theme.alarm)
        }
        if let sentence = plan.collisions?.sentence() {
            Text(sentence)
                .foregroundStyle(Theme.alarm)
        }
        Text(routeLine(plan))
            .foregroundStyle(Theme.inkFaint)
        Text(plan.transport.plainDescription)
            .foregroundStyle(Theme.inkFaint)
        Spacer().frame(height: 8)
        ForEach(Array(plan.steps.enumerated()), id: \.offset) { _, step in
            Text(stepLine(step))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
        }
        Spacer().frame(height: 8)
    }

    private func sizeLine(_ plan: Plan) -> String {
        let count = plan.entries.count
        let bytes = plan.totalSize.formatted(.byteCount(style: .file))
        let floor = plan.totalSizeComplete ? "" : " · this is a floor — a folder couldn't be measured"
        return "\(count) \(count == 1 ? "entry" : "entries") · \(bytes)\(floor)"
    }

    private func routeLine(_ plan: Plan) -> String {
        let from = "\(plan.source.host):\(plan.source.directory)"
        guard let destination = plan.destination else { return from }
        return "\(from) → \(destination.host):\(destination.directory)"
    }

    private func stepLine(_ step: PlanStep) -> String {
        step.gatedOnVerification
            ? "  runs only after the copy above is verified: $ \(step.command)"
            : "$ \(step.command)"
    }

    // MARK: - The run, live

    @ViewBuilder private var transcript: some View {
        if operation.echo.droppedLines > 0 {
            Text("… \(operation.echo.droppedLines) earlier lines")
                .foregroundStyle(Theme.inkFaint)
        }
        ForEach(operation.echo.lines) { line in
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(color(for: line.kind))
                .fontWeight(line.kind == .command ? .semibold : .regular)
                .textSelection(.enabled)
        }
    }

    private func color(for kind: EchoBuffer.Line.Kind) -> SwiftUI.Color {
        switch kind {
        case .command: Theme.ink
        case .stdout: Theme.ink
        case .stderr: Theme.inkFaint
        case .note: Theme.accent
        case .failure: Theme.alarm
        }
    }

    // MARK: - Progress

    private func progressBar(_ report: ProgressReport) -> some View {
        HStack(spacing: 10) {
            if let fraction = report.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.accent)
            } else {
                // An indeterminate bar beats a wrong one.
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }
            Text(report.bytesTransferred.formatted(.byteCount(style: .file)))
                .font(monoSmall)
                .foregroundStyle(Theme.inkFaint)
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
