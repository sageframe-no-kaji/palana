// PaneModel+History — per-pane back/forward navigation, wired into
// the commit path. New navigations push; back/forward walk without pushing.

import PalanaCore

extension PaneModel {
    /// True when the back stack has entries.
    var canGoBack: Bool { history.canGoBack }
    /// True when the forward stack has entries.
    var canGoForward: Bool { history.canGoForward }

    /// Goes back one step in this pane's history.
    ///
    /// No-ops when the back stack is empty or the pane has no current location.
    func historyBack() {
        guard let current = currentLocation, history.canGoBack else { return }
        guard let previous = history.back(current: current) else { return }
        navigateToHistory(previous)
    }

    /// Goes forward one step in this pane's history.
    ///
    /// No-ops when the forward stack is empty or the pane has no current location.
    func historyForward() {
        guard let current = currentLocation, history.canGoForward else { return }
        guard let next = history.forward(current: current) else { return }
        navigateToHistory(next)
    }

    // MARK: - Private

    private var currentLocation: PaneLocation? {
        guard let host = state.host else { return nil }
        return PaneLocation(host: host, path: state.path)
    }

    /// Reads a history location without pushing onto the back stack.
    ///
    /// Sets the flag that tells `commit(host:path:entries:)` to skip
    /// the history push — the stacks were already updated by `back` or
    /// `forward` above.
    private func navigateToHistory(_ location: PaneLocation) {
        isHistoryNavigation = true
        point(host: location.host, path: location.path)
    }
}
