// Tests for PaneHistory — browser-style back/forward stack.

import Testing

@testable import PalanaCore

@Suite("PaneHistory")
struct PaneHistoryTests {
    let loc1 = PaneLocation(host: "box", path: "/a")
    let loc2 = PaneLocation(host: "box", path: "/b")
    let loc3 = PaneLocation(host: "box", path: "/c")

    // MARK: - Initial state

    @Test
    func initiallyEmpty() {
        let hist = PaneHistory()
        #expect(!hist.canGoBack)
        #expect(!hist.canGoForward)
    }

    // MARK: - push

    @Test
    func pushRecordsInBackStack() {
        var hist = PaneHistory()
        hist.push(loc1)
        #expect(hist.canGoBack)
        #expect(!hist.canGoForward)
    }

    @Test
    func pushClearsForwardStack() {
        var hist = PaneHistory()
        // Set up a forward entry by pushing then going back.
        hist.push(loc1)
        _ = hist.back(current: loc2)
        #expect(hist.canGoForward)
        // A new push must clear it.
        hist.push(loc3)
        #expect(!hist.canGoForward)
    }

    // MARK: - back

    @Test
    func backReturnsPreviousLocation() {
        var hist = PaneHistory()
        hist.push(loc1)
        let result = hist.back(current: loc2)
        #expect(result == loc1)
    }

    @Test
    func backMovesCurrentToForwardStack() {
        var hist = PaneHistory()
        hist.push(loc1)
        _ = hist.back(current: loc2)
        #expect(hist.canGoForward)
    }

    @Test
    func backReturnsNilWhenEmpty() {
        var hist = PaneHistory()
        let result = hist.back(current: loc1)
        #expect(result == nil)
    }

    @Test
    func backDoesNotMutateForwardWhenEmpty() {
        var hist = PaneHistory()
        _ = hist.back(current: loc1)
        #expect(!hist.canGoForward)
    }

    // MARK: - forward

    @Test
    func forwardReturnsNextLocation() {
        var hist = PaneHistory()
        hist.push(loc1)
        _ = hist.back(current: loc2)
        let result = hist.forward(current: loc1)
        #expect(result == loc2)
    }

    @Test
    func forwardMovesCurrentToBackStack() {
        var hist = PaneHistory()
        hist.push(loc1)
        _ = hist.back(current: loc2)
        _ = hist.forward(current: loc1)
        #expect(hist.canGoBack)
    }

    @Test
    func forwardReturnsNilWhenEmpty() {
        var hist = PaneHistory()
        let result = hist.forward(current: loc1)
        #expect(result == nil)
    }

    // MARK: - canGoBack / canGoForward reflect stack state

    @Test
    func canGoBackReflectsBackStack() {
        var hist = PaneHistory()
        #expect(!hist.canGoBack)
        hist.push(loc1)
        #expect(hist.canGoBack)
        _ = hist.back(current: loc2)
        #expect(!hist.canGoBack)
    }

    @Test
    func canGoForwardReflectsForwardStack() {
        var hist = PaneHistory()
        #expect(!hist.canGoForward)
        hist.push(loc1)
        _ = hist.back(current: loc2)
        #expect(hist.canGoForward)
        _ = hist.forward(current: loc1)
        #expect(!hist.canGoForward)
    }

    // MARK: - Multi-step

    @Test
    func multiStepNavigation() {
        var hist = PaneHistory()
        hist.push(loc1)
        hist.push(loc2)
        // Back from loc3 to loc2, then to loc1.
        let back1 = hist.back(current: loc3)
        #expect(back1 == loc2)
        let back2 = hist.back(current: loc2)
        #expect(back2 == loc1)
        // Forward from loc1 through loc2 to loc3.
        let fwd1 = hist.forward(current: loc1)
        #expect(fwd1 == loc2)
        let fwd2 = hist.forward(current: loc2)
        #expect(fwd2 == loc3)
    }
}
