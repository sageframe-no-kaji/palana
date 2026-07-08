// The plan panel — monospace's only home in the app, per the design
// language. The Plan's commands display here before enactment, and
// when Enter fires the enactment echoes here live: real commands, real
// output, streaming. The panel renders values and forwards nothing —
// the keyboard's Enter and Esc live in the session.

import PalanaCore
import SwiftUI

/// The bottom surface: the plan whole, then the run live.
struct PlanPanel: View {
    /// The operation flow this panel renders.
    var operation: OperationModel
    /// The session — drives the tools strip on the trailing edge.
    var session: PalanaSession

    @FocusState private var namingFieldFocused: Bool
    @State private var nameText = ""

    private let mono = Font.system(size: 12, design: .monospaced)
    private let monoSmall = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if operation.phase == .naming {
                                namingFieldView
                            } else {
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
            Text(hint)
                .foregroundStyle(hintColor)
        }
        .font(monoSmall)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var phaseWord: String {
        let verb = operation.requested.map { "\($0.rawValue) · " } ?? ""
        switch operation.phase {
        case .idle: return ""
        case .naming: return "\(verb)naming"
        case .gathering: return "\(verb)composing…"
        case .ready: return "\(verb)the plan"
        case .enacting: return "\(verb)running"
        case .finished: return "\(verb)done"
        case .failed: return "\(verb)failed"
        case .cancelled: return "\(verb)cancelled"
        }
    }

    /// The hint's color signals whether Return is live.
    ///
    /// Moss when a keystroke will fire—the plan is ready to enact, or the
    /// naming field is waiting for its name. Quiet ink while the panel is
    /// composing or running (waiting for a response) or resting, so "go"
    /// and "hold" never wear the same color.
    private var hintColor: Color {
        switch operation.phase {
        case .ready, .naming: return Theme.accent
        default: return Theme.inkFaint
        }
    }

    private var hint: String {
        switch operation.phase {
        case .idle: return "esc hides"
        case .naming: return "⏎ commit · esc cancel"
        case .gathering: return "esc hides · ⌃c cancels"
        case .ready: return "⏎ enact · esc hides · a new verb recomposes"
        case .enacting: return "esc hides, keeps running · ⌃c cancels"
        case .finished, .failed, .cancelled: return "esc hides · y m r R a t T go again"
        }
    }

    // MARK: - The naming field

    @ViewBuilder private var namingFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(operation.namingLabel)
                .foregroundStyle(Theme.inkFaint)
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
        }
    }

    // MARK: - The plan, whole

    @ViewBuilder
    private func planBlock(_ plan: Plan) -> some View {
        Text("\(plan.operation.rawValue) · \(plan.classification.rawValue)")
            .foregroundStyle(Theme.ink)
            .fontWeight(.semibold)
        Text(sizeLine(plan))
            .foregroundStyle(plan.totalSizeComplete ? Theme.inkFaint : Theme.alarm)
        Text(routeLine(plan))
            .foregroundStyle(Theme.inkFaint)
        Text("transport: \(plan.transport.rawValue)")
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
        let floor = plan.totalSizeComplete ? "" : " · a floor — a subtree refused its walk"
        return "\(count) \(count == 1 ? "entry" : "entries") · \(bytes)\(floor)"
    }

    private func routeLine(_ plan: Plan) -> String {
        let from = "\(plan.source.host):\(plan.source.directory)"
        guard let destination = plan.destination else { return from }
        return "\(from) → \(destination.host):\(destination.directory)"
    }

    private func stepLine(_ step: PlanStep) -> String {
        step.gatedOnVerification
            ? "  gated on verification: $ \(step.command)"
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

    private func color(for kind: EchoBuffer.Line.Kind) -> Color {
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
