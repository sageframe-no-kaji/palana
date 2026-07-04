// Scratch timing probe — measures the exact read path the pane runs
// for local:/private/tmp. Deleted after the number is read.

import Foundation
import Testing

@testable import PalanaCore

@Suite("Scratch: tmp timing")
struct TmpTimingScratch {
    @Test("time the local /private/tmp read path")
    func timeTmpRead() async throws {
        let listing = Listing(conduit: LocalConduit())
        let clock = ContinuousClock()
        var count = 0
        let elapsed = try await clock.measure {
            count = try await listing.list(on: "local", path: "/private/tmp", flavor: .bsd).count
        }
        print("SCRATCH-TIMING /private/tmp: \(count) entries in \(elapsed)")
        let again = try await clock.measure {
            count = try await listing.list(on: "local", path: "/private/tmp", flavor: .bsd).count
        }
        print("SCRATCH-TIMING second read: \(count) entries in \(again)")
    }
}
