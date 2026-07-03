// Frame instrumentation. A CADisplayLink (NSView.displayLink, macOS 14+)
// records frame timestamps; the collector buckets them per drive phase and
// writes JSON on completion.

import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class MetricsCollector: ObservableObject {
    static let shared = MetricsCollector()

    private(set) var frames: [(phase: String, timestamp: Double)] = []
    var currentPhase = "settle"
    var selectionChanges = 0
    var timings: [String: Double] = [:]
    var counters: [String: Int] = [:]

    func recordFrame(_ timestamp: Double) {
        frames.append((currentPhase, timestamp))
    }

    func physFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.phys_footprint) / 1_048_576
    }

    func phaseStats() -> [[String: Any]] {
        var byPhase: [String: [Double]] = [:]
        var order: [String] = []
        for frame in frames {
            if byPhase[frame.phase] == nil { order.append(frame.phase) }
            byPhase[frame.phase, default: []].append(frame.timestamp)
        }
        return order.map { phase in
            let stamps = byPhase[phase] ?? []
            var intervals: [Double] = []
            for index in 1..<max(stamps.count, 1) {
                intervals.append((stamps[index] - stamps[index - 1]) * 1000)
            }
            intervals.sort()
            func percentile(_ fraction: Double) -> Double {
                guard !intervals.isEmpty else { return 0 }
                let position = Int(Double(intervals.count - 1) * fraction)
                return intervals[position]
            }
            return [
                "phase": phase,
                "frames": stamps.count,
                "medianIntervalMs": (percentile(0.5) * 100).rounded() / 100,
                "p95IntervalMs": (percentile(0.95) * 100).rounded() / 100,
                "maxIntervalMs": (percentile(1.0) * 100).rounded() / 100,
                "hitchesOver33ms": intervals.filter { $0 > 33.4 }.count,
                "hitchesOver100ms": intervals.filter { $0 > 100 }.count,
            ]
        }
    }

    func write(to path: String) {
        let payload: [String: Any] = [
            "timings": timings.mapValues { ($0 * 100).rounded() / 100 },
            "counters": counters,
            "selectionChanges": selectionChanges,
            "phases": phaseStats(),
        ]
        guard let json = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? json.write(to: URL(fileURLWithPath: path))
    }
}

/// Transparent overlay whose only job is owning the display link.
struct FrameMeter: NSViewRepresentable {
    func makeNSView(context: Context) -> FrameMeterView { FrameMeterView() }
    func updateNSView(_ view: FrameMeterView, context: Context) {}
}

final class FrameMeterView: NSView {
    private var link: CADisplayLink?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let displayLink = self.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let timestamp = sender.timestamp
        MainActor.assumeIsolated {
            MetricsCollector.shared.recordFrame(timestamp)
        }
    }
}
