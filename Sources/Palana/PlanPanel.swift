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

    private let mono = Font.system(size: 12, design: .monospaced)
    private let monoSmall = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if let plan = operation.plan {
                            planBlock(plan)
                        }
                        transcript
                        Color.clear.frame(height: 1).id("panel-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: operation.echo.lines.last?.id) {
                    proxy.scrollTo("panel-bottom", anchor: .bottom)
                }
                .onChange(of: operation.echo.lines.last?.text) {
                    proxy.scrollTo("panel-bottom", anchor: .bottom)
                }
            }
            if let progress = operation.progress {
                progressBar(progress)
            }
        }
        .font(mono)
        .background(Theme.panelGround)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Text(phaseWord)
                .foregroundStyle(Theme.ink)
                .fontWeight(.semibold)
            Spacer()
            Text(hint)
                .foregroundStyle(Theme.inkFaint)
        }
        .font(monoSmall)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var phaseWord: String {
        let verb = operation.requested.map { "\($0.rawValue) · " } ?? ""
        switch operation.phase {
        case .idle: return ""
        case .gathering: return "\(verb)composing…"
        case .ready: return "\(verb)the plan"
        case .enacting: return "\(verb)running"
        case .finished: return "\(verb)done"
        case .failed: return "\(verb)failed"
        case .cancelled: return "\(verb)cancelled"
        }
    }

    private var hint: String {
        switch operation.phase {
        case .idle, .gathering: return "esc dismiss"
        case .ready: return "⏎ enact · esc dismiss"
        case .enacting: return "esc cancel"
        case .finished, .failed, .cancelled: return "esc close"
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
