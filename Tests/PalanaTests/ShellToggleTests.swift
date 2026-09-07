// ⌘` always reaches the shell (hands session 2026-09-07). The practitioner
// composed a plan, pressed ⌘`, and nothing happened — round 9's 'decline
// silently while the plan owns the panel' had become the trap. Then, from
// the shell, he clicked a pane and pressed m: the key went to the PTY or
// nowhere. These tests pin the policy that replaces the decline, the two
// failing cases exactly as he hit them, the running-phase overlay that
// cancels nothing, and the click that hands the keyboard back.
//
// No PTY is ever spawned: the shell's view is never rendered, so the
// terminal store is never summoned. No pane is ever pointed for real —
// the host is a string on the pane state, and the one verb fired lands
// on a phase that stops it before any gather.

import AppKit
import PalanaCore
import XCTest

@testable import Palana

@MainActor
final class ShellToggleTests: XCTestCase {
    private typealias Phase = OperationModel.Phase
    private typealias Situation = ShellTogglePolicy.Situation

    private static let allPhases: [Phase] = [
        .idle, .naming, .gathering, .ready, .enacting, .finished, .failed, .cancelled,
    ]
    private static let settledPhases: [Phase] = [.naming, .ready, .finished, .failed, .cancelled]
    private static let runningPhases: [Phase] = [.gathering, .enacting]
    private static let bools = [false, true]

    private static func situation(
        _ mode: Bool, _ focused: Bool, _ showing: Bool, _ phase: Phase, host: Bool
    ) -> Situation {
        Situation(shellMode: mode, shellFocused: focused, panelShowing: showing, phase: phase, hasHost: host)
    }

    // MARK: - The policy, every combination

    /// No host: refused in every phase, whatever the shell flags say.
    func testNoHostRefusesEverywhere() {
        for phase in Self.allPhases {
            for mode in Self.bools {
                for focused in Self.bools {
                    for showing in Self.bools {
                        let situation = Self.situation(mode, focused, showing, phase, host: false)
                        XCTAssertEqual(ShellTogglePolicy.decide(situation), .refuseNoHost, "\(situation)")
                    }
                }
            }
        }
    }

    /// Idle: the shell on screen with the keyboard releases; everything else summons.
    func testIdleReleasesOnlyWhenTheShellHoldsTheKeyboard() {
        for mode in Self.bools {
            for focused in Self.bools {
                for showing in Self.bools {
                    let situation = Self.situation(mode, focused, showing, .idle, host: true)
                    let expected: ShellTogglePolicy.Action = mode && focused && showing ? .release : .summon
                    XCTAssertEqual(ShellTogglePolicy.decide(situation), expected, "\(situation)")
                }
            }
        }
    }

    /// A settled operation owning the panel is dismissed first, always —
    /// round 9's decline is gone.
    func testSettledPhasesDismissThenSummon() {
        for phase in Self.settledPhases {
            for mode in Self.bools {
                for focused in Self.bools {
                    for showing in Self.bools {
                        let situation = Self.situation(mode, focused, showing, phase, host: true)
                        XCTAssertEqual(ShellTogglePolicy.decide(situation), .dismissThenSummon, "\(situation)")
                    }
                }
            }
        }
    }

    /// A live run is never dismissed: the shell overlays it, and a second
    /// ⌘` hands the keyboard (and the panel) back to the run.
    func testRunningPhasesSummonOrRelease() {
        for phase in Self.runningPhases {
            for mode in Self.bools {
                for focused in Self.bools {
                    for showing in Self.bools {
                        let situation = Self.situation(mode, focused, showing, phase, host: true)
                        let expected: ShellTogglePolicy.Action = mode && focused && showing ? .release : .summon
                        XCTAssertEqual(ShellTogglePolicy.decide(situation), expected, "\(situation)")
                    }
                }
            }
        }
    }

    /// The visibility law: idle shows the shell focused or not; a live run
    /// shows it only while it holds the keyboard; settled phases never.
    func testShellShowsLaw() {
        for phase in Self.allPhases {
            for focused in Self.bools {
                let situation = Situation(
                    shellMode: true, shellFocused: focused, panelShowing: true, phase: phase, hasHost: true)
                let expected: Bool
                switch phase {
                case .idle: expected = true
                case .gathering, .enacting: expected = focused
                default: expected = false
                }
                XCTAssertEqual(ShellTogglePolicy.shellShows(situation), expected, "\(situation)")
            }
        }
        let hidden = Situation(shellMode: true, shellFocused: true, panelShowing: false, phase: .idle, hasHost: true)
        XCTAssertFalse(ShellTogglePolicy.shellShows(hidden))
        let noHost = Situation(shellMode: true, shellFocused: true, panelShowing: true, phase: .idle, hasHost: false)
        XCTAssertFalse(ShellTogglePolicy.shellShows(noHost))
    }

    // MARK: - The session, as he hit it

    /// A session whose focused pane names a host — no wire, no read.
    private func makeSession(pointed: Bool = true) -> PalanaSession {
        let session = PalanaSession()
        if pointed { session.left.state.host = "koan" }
        return session
    }

    /// The plan is showing ("move · the plan"); ⌘` goes to the shell with
    /// the plan dismissed.
    func testPlanShowingYieldsShellFocusedWithTheOperationDismissed() {
        let session = makeSession()
        session.operation.requested = .move
        session.operation.phase = .ready
        session.operation.panelShowing = true
        XCTAssertFalse(session.shellVisible)

        session.toggleShellKeyboard()

        XCTAssertTrue(session.shellMode)
        XCTAssertTrue(session.shellFocused)
        XCTAssertTrue(session.shellVisible)
        XCTAssertEqual(session.operation.phase, .idle)
        XCTAssertNil(session.operation.requested)
        XCTAssertTrue(session.operation.panelShowing)
    }

    /// A finished, failed, or cancelled result is showing; ⌘` goes to the
    /// shell with the result dismissed — the same road.
    func testResultShowingYieldsShellFocusedWithTheResultDismissed() {
        for phase in [Phase.finished, .failed, .cancelled] {
            let session = makeSession()
            session.shellMode = true
            session.operation.phase = phase
            session.operation.panelShowing = true

            session.toggleShellKeyboard()

            XCTAssertTrue(session.shellFocused, "\(phase)")
            XCTAssertTrue(session.shellVisible, "\(phase)")
            XCTAssertEqual(session.operation.phase, .idle, "\(phase)")
        }
    }

    /// A live run: ⌘` shows the shell over it and cancels nothing; ⌘`
    /// again hands the keyboard back and the transcript returns, the run
    /// still live.
    func testRunningShowsTheShellAndCancelsNothing() {
        for phase in Self.runningPhases {
            let session = makeSession()
            session.operation.requested = .move
            session.operation.phase = phase
            session.operation.panelShowing = true

            session.toggleShellKeyboard()
            XCTAssertTrue(session.shellMode, "\(phase)")
            XCTAssertTrue(session.shellFocused, "\(phase)")
            XCTAssertTrue(session.shellVisible, "\(phase)")
            XCTAssertEqual(session.operation.phase, phase, "\(phase)")
            XCTAssertEqual(session.operation.requested, .move, "\(phase)")

            session.toggleShellKeyboard()
            XCTAssertFalse(session.shellFocused, "\(phase)")
            XCTAssertFalse(session.shellVisible, "\(phase)")
            XCTAssertTrue(session.operation.panelShowing, "\(phase)")
            XCTAssertEqual(session.operation.phase, phase, "\(phase)")
        }
    }

    /// The run's panel is hidden (backtick stashed it); ⌘` brings the
    /// panel back showing the shell, the run untouched.
    func testRunningWithHiddenPanelSummonsTheShell() {
        let session = makeSession()
        session.operation.phase = .enacting
        session.operation.panelShowing = false

        session.toggleShellKeyboard()

        XCTAssertTrue(session.operation.panelShowing)
        XCTAssertTrue(session.shellVisible)
        XCTAssertEqual(session.operation.phase, .enacting)
    }

    /// A failure under the shell pulls the keyboard back; the transcript
    /// shows the failure.
    func testFailureUnderTheShellResurfacesTheTranscript() {
        let session = makeSession()
        session.operation.phase = .enacting
        session.operation.panelShowing = true
        session.toggleShellKeyboard()
        XCTAssertTrue(session.shellVisible)

        session.resurfaceTranscriptOnFailure()
        session.operation.phase = .failed

        XCTAssertFalse(session.shellFocused)
        XCTAssertFalse(session.shellVisible)
        XCTAssertTrue(session.shellMode, "shell mode is the standing choice — it survives the failure")
    }

    /// No pointed pane: the note, and nothing else moves.
    func testNoHostKeepsTheNote() {
        let session = makeSession(pointed: false)

        session.toggleShellKeyboard()

        XCTAssertFalse(session.shellMode)
        XCTAssertFalse(session.shellFocused)
        XCTAssertFalse(session.shellVisible)
        XCTAssertTrue(session.operation.echo.lines.contains { $0.text == "point a pane at a host first" })
    }

    /// Not in shell mode, idle: ⌘` enters it with the keyboard — the
    /// original summon, unchanged.
    func testIdleSummonEntersShellModeFocused() {
        let session = makeSession()

        session.toggleShellKeyboard()
        XCTAssertTrue(session.shellMode)
        XCTAssertTrue(session.shellFocused)
        XCTAssertTrue(session.shellVisible)

        session.toggleShellKeyboard()
        XCTAssertFalse(session.shellFocused)
        XCTAssertTrue(session.shellVisible, "the shell stays on screen, dimmed, while the panes drive")
    }

    /// ⌘` arriving through the shell-mode stand-down rides the same policy.
    func testShellModeChordReleasesThroughThePolicy() throws {
        let session = makeSession()
        session.toggleShellKeyboard()
        XCTAssertTrue(session.shellFocused)

        XCTAssertFalse(session.handleShellModeKey(try Self.keyEvent("m", keyCode: 46)), "m belongs to the PTY")
        XCTAssertTrue(session.shellFocused)

        XCTAssertTrue(session.handleShellModeKey(try Self.keyEvent("`", keyCode: 50, modifiers: .command)))
        XCTAssertFalse(session.shellFocused)
    }

    // MARK: - The click hands the keyboard back

    /// Clicking a pane releases the shell's keyboard; the shell stays on
    /// screen in the idle gap.
    func testClickOnAPaneHandsTheKeyboardBack() {
        let session = makeSession()
        session.right.state.host = "koan"
        session.toggleShellKeyboard()
        XCTAssertTrue(session.shellFocused)

        session.focusPane(.right)

        XCTAssertEqual(session.focusedSide, .right)
        XCTAssertFalse(session.shellFocused)
        XCTAssertTrue(session.shellVisible)
    }

    /// From the shell over a live run, a click returns the transcript and
    /// the next verb key reaches `beginOperation` — the run re-shows its
    /// panel — instead of the PTY.
    func testVerbAfterClickReachesBeginOperation() throws {
        let session = makeSession()
        session.operation.phase = .enacting
        session.operation.panelShowing = true
        session.toggleShellKeyboard()
        XCTAssertTrue(session.shellVisible)

        session.focusPane(.left)
        XCTAssertFalse(session.shellFocused)
        XCTAssertFalse(session.shellVisible, "the transcript is back over the run")

        // Stash the run's panel so the verb's effect is visible: a verb
        // during an enactment re-shows the panel (`OperationModel.begin`).
        session.operation.hidePanel()
        XCTAssertTrue(session.handle(try Self.keyEvent("m", keyCode: 46)), "m is the pane's verb now")
        XCTAssertTrue(session.operation.panelShowing)
        XCTAssertEqual(session.operation.phase, .enacting, "nothing cancelled")
    }

    /// The hit test behind the click monitor: the terminal or anything
    /// inside it keeps the keyboard; any other view, or none, releases.
    func testClickLandsOnShellWalksTheViewTree() {
        let terminal = NSView(frame: .zero)
        let inside = NSView(frame: .zero)
        terminal.addSubview(inside)
        let elsewhere = NSView(frame: .zero)

        XCTAssertTrue(PalanaSession.clickLandsOnShell(terminal, terminal: terminal))
        XCTAssertTrue(PalanaSession.clickLandsOnShell(inside, terminal: terminal))
        XCTAssertFalse(PalanaSession.clickLandsOnShell(elsewhere, terminal: terminal))
        XCTAssertFalse(PalanaSession.clickLandsOnShell(nil, terminal: terminal))
    }

    /// A click reaching the release path with no shell summoned changes nothing.
    func testClickAwayWithoutAShellIsInert() throws {
        let session = makeSession()
        session.toggleShellKeyboard()
        let click = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1))

        session.releaseShellKeyboardIfClickedAway(click)

        XCTAssertTrue(session.shellFocused, "no session was ever summoned — the flag stands")
    }

    // MARK: - Events

    private static func keyEvent(
        _ chars: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: chars,
                charactersIgnoringModifiers: chars,
                isARepeat: false,
                keyCode: keyCode))
    }
}
