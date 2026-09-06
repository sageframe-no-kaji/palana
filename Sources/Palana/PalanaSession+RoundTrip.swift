// PalanaSession+RoundTrip — wires the round-trip center into the session.
// The session owns the center, connects the pane callbacks, echoes the
// transcript line at registration, and refreshes the watcher baseline
// after a finished upload.

import PalanaCore

extension PalanaSession {
    /// Installs the round-trip center, wires pane registration callbacks,
    /// and hooks the operation model's finish path for baseline refresh.
    ///
    /// Called once from `init()` after all members are initialised.
    func wireRoundTripCenter() {
        // The center asks the model one question — is the panel free — and
        // hands it one action — send this upload. Closures rather than a
        // model reference keep the center depending on only what it needs.
        roundTripCenter.isPanelFree = { [weak operation] in
            guard let operation else { return false }
            switch operation.phase {
            case .idle, .finished, .failed, .cancelled:
                return true
            case .naming, .gathering, .ready, .enacting:
                return false
            }
        }
        roundTripCenter.deliverUpload = { [weak operation] record in
            operation?.beginRoundTripUpload(record: record)
        }

        // Both panes call the same handler — a remote open on either side registers.
        let register: @MainActor (RoundTripRecord) -> Void = { [weak self] record in
            self?.registerRoundTrip(record: record)
        }
        left.onRoundTripRegistered = register
        right.onRoundTripRegistered = register

        // After any enactment finishes, check whether a round-trip upload just
        // completed and refresh its watcher baseline so the send itself doesn't
        // immediately re-offer.
        let previousOnFinished = operation.onFinished
        operation.onFinished = { [weak self] in
            previousOnFinished()
            self?.handleRoundTripFinished()
        }
    }

    /// Registers a round-trip record, starts its watcher, and names the
    /// watch in the transcript (Decision 5 — one line, no new surface).
    ///
    /// - Parameter record: The record produced by the pane's remote open.
    func registerRoundTrip(record: RoundTripRecord) {
        roundTripCenter.register(record: record)
        // Transcript note — echoed through the same path gather notes use.
        // The panel is NOT popped here (Decision 5: one line, no new
        // surface). The line tells the truth of the current setting.
        if operation.askBeforeSendingBack {
            operation.note("watching \(record.fetched.name) — a save offers to send it back")
        } else {
            operation.note("watching \(record.fetched.name) — saves go back to \(record.host) on their own")
        }
    }

    /// Called after every enactment finishes.
    ///
    /// The center carries the exact record identity of any upload it
    /// delivered, so it refreshes only that one watcher's baseline — an
    /// ordinary copy into a watched directory, or a sibling record in it,
    /// touches nothing. Advancing the baseline stops the upload's own stat
    /// change from triggering an immediate re-offer.
    private func handleRoundTripFinished() {
        roundTripCenter.uploadDidFinish()
    }

    // MARK: - Star operations (extracted here from PalanaSession.swift to stay within file-length limit)

    /// Stars or unstars the focused pane's current directory.
    ///
    /// A guard on `state.host` ensures the pane is pointed somewhere.
    /// The toggle removes if already favorited, adds host-bound if not.
    func starFocusedDirectory() {
        guard let host = focusedPane.state.host else { return }
        favorites.toggle(host: host, path: focusedPane.state.path)
    }

    /// Stars or unstars the highlighted entry when it is a directory.
    ///
    /// If the cursor entry is absent or is not a directory, this is a no-op —
    /// favorites are directories in v1.
    func starHighlightedEntry() {
        guard let entry = focusedPane.cursorEntry else { return }
        guard entry.kind == .directory else { return }
        guard let host = focusedPane.state.host else { return }
        let path = PaneModel.childPath(of: focusedPane.state.path, name: entry.name)
        favorites.toggle(host: host, path: path)
    }
}
