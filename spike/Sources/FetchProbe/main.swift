// Headless probe: exercises the conduit + parser path with no UI.
// Isolates SSH orchestration from SwiftUI when diagnosing hangs.

import Foundation
import PalanaSpikeKit

let env = ProcessInfo.processInfo.environment
let conduit = SpikeConduit(
    identity: env["SPIKE_KEY"] ?? "",
    knownHosts: env["SPIKE_KNOWN_HOSTS"] ?? "/dev/null",
    port: Int(env["SPIKE_PORT"] ?? "2222") ?? 2222,
    destination: env["SPIKE_DEST"] ?? "spike@localhost"
)
let listPath = env["SPIKE_PATH"] ?? "/data"
let command = #"find \#(listPath) -mindepth 1 -printf "%y\t%s\t%T@\t%p\n""#

let clock = ContinuousClock()
let start = clock.now
let data = try await conduit.run(command)
let fetched = clock.now
let entries = SpikeParser.parse(data)
let parsed = clock.now

print("fetch: \(start.duration(to: fetched))")
print("parse: \(fetched.duration(to: parsed))")
print("bytes: \(data.count), entries: \(entries.count)")
print("first: \(entries.first?.name ?? "-"), last: \(entries.last?.name ?? "-")")
