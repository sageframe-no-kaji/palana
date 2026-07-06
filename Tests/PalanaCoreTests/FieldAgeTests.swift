// FieldAge formatting tests — pure arithmetic, no fixtures needed.

import Foundation
import Testing

@testable import PalanaCore

@Suite("FieldAge")
struct FieldAgeTests {
    @Test("under 60 seconds reads as just now")
    func under60Seconds() {
        let date = Date(timeIntervalSince1970: 1_000)
        let ref = Date(timeIntervalSince1970: 1_059)
        #expect(FieldAge.describe(date, now: ref) == "just now")
    }

    @Test("between 60 seconds and 1 hour reads as Nm ago")
    func minutesAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 300)  // 5 minutes
        #expect(FieldAge.describe(date, now: ref) == "5m ago")
    }

    @Test("between 1 hour and 1 day reads as Nh ago")
    func hoursAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 10_800)  // 3 hours
        #expect(FieldAge.describe(date, now: ref) == "3h ago")
    }

    @Test("one day or more reads as Nd ago")
    func daysAgo() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 172_800)  // 2 days
        #expect(FieldAge.describe(date, now: ref) == "2d ago")
    }

    @Test("a future date reads as just now")
    func futureDateReadsJustNow() {
        let date = Date(timeIntervalSince1970: 2_000)
        let ref = Date(timeIntervalSince1970: 1_000)  // ref is behind date
        #expect(FieldAge.describe(date, now: ref) == "just now")
    }

    @Test("integer truncation — 89 seconds reads as 1m ago, not 2m ago")
    func integerTruncation() {
        let date = Date(timeIntervalSince1970: 0)
        let ref = Date(timeIntervalSince1970: 89)
        #expect(FieldAge.describe(date, now: ref) == "1m ago")
    }
}
