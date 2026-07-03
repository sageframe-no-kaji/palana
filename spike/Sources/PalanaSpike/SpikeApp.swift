// The ho-01 spike app. Fetches one real listing over SSH, renders 5,000
// rows in a SwiftUI Table, drives keyboard navigation internally, and
// writes frame metrics to JSON on completion. Throwaway.

import AppKit
import PalanaSpikeKit
import QuartzCore
import SwiftUI

private struct SpikeConfig {
    static let env = ProcessInfo.processInfo.environment
    static let identity = env["SPIKE_KEY"] ?? ""
    static let knownHosts = env["SPIKE_KNOWN_HOSTS"] ?? "/dev/null"
    static let destination = env["SPIKE_DEST"] ?? "spike@localhost"
    static let port = Int(env["SPIKE_PORT"] ?? "2222") ?? 2222
    static let listPath = env["SPIKE_PATH"] ?? "/data"
    static let metricsPath = env["SPIKE_METRICS"] ?? "/tmp/spike-metrics.json"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Watchdog: a hung run writes what it has and exits nonzero
        // instead of eating the session's minutes silently.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            MetricsCollector.shared.counters["watchdogFired"] = 1
            MetricsCollector.shared.write(to: SpikeConfig.metricsPath)
            exit(2)
        }
    }
}

@main
struct SpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("palana spike — ho-01") {
            ContentView()
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}

struct ContentView: View {
    @State private var entries: [SpikeEntry] = []
    @State private var selection: SpikeEntry.ID?
    @State private var status = "fetching listing over ssh…"

    private let collector = MetricsCollector.shared

    var body: some View {
        Group {
            if entries.isEmpty {
                ProgressView(status)
            } else {
                table
            }
        }
        .task { await fetch() }
    }

    private var table: some View {
        Table(entries, selection: $selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Size") { entry in
                Text(entry.kind == "directory" ? "—" : format(bytes: entry.size))
                    .monospacedDigit()
            }
            .width(90)
            TableColumn("Modified") { entry in
                Text(entry.mtime, format: .dateTime.year().month().day().hour().minute())
            }
            .width(150)
            TableColumn("Kind", value: \.kind).width(80)
        }
        .overlay(FrameMeter().allowsHitTesting(false))
        .onChange(of: selection) { collector.selectionChanges += 1 }
        .onAppear {
            collector.timings["tableAppearAt"] = CACurrentMediaTime()
            collector.counters["footprintMBAtAppear"] = Int(collector.physFootprintMB())
            selection = entries.first?.id
            Task { await driveAndFinish() }
        }
    }

    private func fetch() async {
        let conduit = SpikeConduit(
            identity: SpikeConfig.identity,
            knownHosts: SpikeConfig.knownHosts,
            port: SpikeConfig.port,
            destination: SpikeConfig.destination
        )
        let command = #"find \#(SpikeConfig.listPath) -mindepth 1 -printf "%y\t%s\t%T@\t%p\n""#
        do {
            let fetchStart = CACurrentMediaTime()
            let data = try await conduit.run(command)
            let fetchEnd = CACurrentMediaTime()
            let parsed = SpikeParser.parse(data)
            let parseEnd = CACurrentMediaTime()
            collector.timings["fetchMs"] = (fetchEnd - fetchStart) * 1000
            collector.timings["parseMs"] = (parseEnd - fetchEnd) * 1000
            collector.counters["entryCount"] = parsed.count
            collector.timings["entriesSetAt"] = CACurrentMediaTime()
            entries = parsed
        } catch {
            status = "fetch failed: \(error)"
            collector.counters["fetchFailed"] = 1
            try? await Task.sleep(for: .seconds(1))
            finish()
        }
    }

    private func driveAndFinish() async {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else {
            collector.counters["noWindow"] = 1
            finish()
            return
        }
        await Driver.run(window: window, collector: collector)
        if let selected = selection {
            collector.counters["finalSelectionIndex"] = selected
        }
        collector.counters["footprintMBAtEnd"] = Int(collector.physFootprintMB())
        finish()
    }

    private func finish() {
        // First-render proxy: table appearance to the first frame after it.
        if let appearAt = collector.timings["tableAppearAt"],
            let firstFrame = collector.frames.first(where: { $0.timestamp > appearAt })
        {
            collector.timings["firstFrameAfterAppearMs"] = (firstFrame.timestamp - appearAt) * 1000
        }
        collector.write(to: SpikeConfig.metricsPath)
        NSApp.terminate(nil)
    }

    private func format(bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
