// Where a test is running, when that changes whether it can be honest.

import Foundation

/// Facts about the machine the suite is running on.
enum TestEnvironment {
    /// True on a headless CI runner (GitHub sets `CI=true`).
    ///
    /// A runner has no window server and no interactive login shell. Suites
    /// that build an `NSView` and drive a PTY on the main actor cannot be
    /// faithful there, and a main actor that blocks takes every other
    /// `@MainActor` test down with it — including tests whose own deadlines
    /// then never get a chance to fire. That is the shape of the 30-minute
    /// silent CI hang (2026-08, three weeks of red main): the whole process
    /// froze half a second in, with bounded waits left unbounded because the
    /// actor enforcing them was stuck.
    ///
    /// These suites still run in full locally and in every hands session,
    /// which is where a terminal is real anyway.
    static var isHeadlessCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }
}
