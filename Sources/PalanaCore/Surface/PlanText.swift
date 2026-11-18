// The plan panel's words, as plain text — one source for what the panel
// draws and what its copy button puts on the clipboard (#3), plus the
// grouping that lets program output keep its columns (#12).

import Foundation

/// A run of consecutive transcript lines of one sort.
///
/// Program output (stdout and stderr) is laid out unwrapped so tables such
/// as `zpool status` keep their columns; commands, notes, and failures wrap.
public struct EchoRun: Sendable, Equatable, Identifiable {
    /// True for program output, false for the panel's own lines.
    public var isOutput: Bool
    /// The lines in order.
    public var lines: [EchoLine]
    /// The first line's id — stable while the run grows at its tail.
    public var id: Int { lines.first?.id ?? -1 }
}

/// Plain-text renderings of a plan and its run.
public enum PlanText {
    /// `copy · copy to another machine`.
    public static func heading(_ plan: Plan) -> String {
        "\(plan.operation.rawValue) · \(plan.classification.plainName)"
    }

    /// `3 entries · 41.3 GB`, with a floor warning when a folder could not be measured.
    public static func sizeLine(_ plan: Plan) -> String {
        let count = plan.entries.count
        let bytes = plan.totalSize.formatted(.byteCount(style: .file))
        let floor = plan.totalSizeComplete ? "" : " · this is a floor — a folder couldn't be measured"
        return "\(count) \(count == 1 ? "entry" : "entries") · \(bytes)\(floor)"
    }

    /// `jodo:/tank/a → koan:/rpool/b`, or the source alone when there is no destination.
    public static func routeLine(_ plan: Plan) -> String {
        let from = "\(plan.source.host):\(plan.source.directory)"
        guard let destination = plan.destination else { return from }
        return "\(from) → \(destination.host):\(destination.directory)"
    }

    /// `$ command`, or the gated form for a step that waits on verification.
    public static func stepLine(_ step: PlanStep) -> String {
        step.gatedOnVerification
            ? "  runs only after the copy above is verified: $ \(step.command)"
            : "$ \(step.command)"
    }

    /// Every line the panel shows for a plan, in order.
    ///
    /// - Parameters:
    ///   - plan: The plan to render.
    ///   - notices: Warnings the app adds beneath the transport line (the
    ///     progressive-move warning lives with the app's copy).
    /// - Returns: The lines, with an empty line between the plan's facts and its steps.
    public static func planLines(_ plan: Plan, notices: [String] = []) -> [String] {
        var lines = [heading(plan)]
        // A dataset mutation acts on a dataset, not on a counted selection.
        if plan.operation != .zfs { lines.append(sizeLine(plan)) }
        if let sentence = plan.collisions?.sentence() { lines.append(sentence) }
        lines.append(routeLine(plan))
        lines.append(plan.transport.plainDescription)
        lines += notices
        if let notice = plan.metadataNotice { lines.append(notice) }
        lines.append("")
        lines += plan.steps.map(stepLine)
        return lines
    }

    /// The plan, then the run's output, as one plain-text block (#3).
    ///
    /// Live partial lines are included. When the buffer has dropped its
    /// oldest lines, a `… N earlier lines` line says so, so the cap stays
    /// visible in what is pasted.
    ///
    /// - Parameters:
    ///   - plan: The plan on screen, if any.
    ///   - notices: Warnings the app shows under the plan's transport line.
    ///   - echo: The run's transcript.
    /// - Returns: Plain text, one panel line per text line.
    public static func clipboardText(plan: Plan?, notices: [String] = [], echo: EchoBuffer) -> String {
        var lines: [String] = []
        if let plan {
            lines += planLines(plan, notices: notices)
            lines.append("")
        }
        if echo.droppedLines > 0 {
            lines.append("… \(echo.droppedLines) earlier lines")
        }
        lines += echo.lines.map(\.text)
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Groups consecutive transcript lines into output and non-output runs (#12).
    public static func runs(_ lines: [EchoLine]) -> [EchoRun] {
        var runs: [EchoRun] = []
        for line in lines {
            let output = line.kind == .stdout || line.kind == .stderr
            if let last = runs.last, last.isOutput == output {
                runs[runs.count - 1].lines.append(line)
            } else {
                runs.append(EchoRun(isOutput: output, lines: [line]))
            }
        }
        return runs
    }
}
