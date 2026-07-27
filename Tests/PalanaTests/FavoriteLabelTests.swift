// FavoriteLabelTests — the operator-given name on a star: setting it,
// clearing it, undoing it, and the guard that decides whether a single click
// on an already-focused row opens the name field or jumps.

import Foundation
import PalanaCore
import Testing

@testable import Palana

@Suite("favorite labels — set, clear, undo, persist")
@MainActor
struct FavoriteLabelTests {
    // MARK: - Helpers

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("palana-label-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    /// A model holding one host-bound favorite at `koan:/tank/media`.
    private func makeModel(at url: URL) -> FavoritesModel {
        let model = FavoritesModel(url: url)
        model.add(host: "koan", path: "/tank/media", scope: .host)
        return model
    }

    // MARK: - Set, persist, reload

    @Test("a label set on a favorite survives a reload from disk")
    func setPersistsAndReloads() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "media pool")
        #expect(model.all.first?.label == "media pool")

        let reloaded = FavoritesModel(url: url)
        #expect(reloaded.all.first?.label == "media pool")
    }

    @Test("the label is trimmed on the way in")
    func trimsWhitespace() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "  media pool  ")
        #expect(model.all.first?.label == "media pool")
    }

    @Test(
        "empty, whitespace-only, and nil text all clear the label",
        arguments: [nil, "", "   ", "\n\t "])
    func clearsOnEmpty(text: String?) {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "media pool")
        model.setLabel(id: "koan:/tank/media", label: text)
        #expect(model.all.first?.label == nil)

        let reloaded = FavoritesModel(url: url)
        #expect(reloaded.all.first?.label == nil)
    }

    @Test("setting a label on an unknown id changes nothing")
    func unknownIDIsANoOp() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/nowhere", label: "ghost")
        #expect(model.all.first?.label == nil)
        #expect(model.all.count == 1)
    }

    // MARK: - Undo

    @Test("undo restores the prior label")
    func undoRestoresPriorLabel() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "media pool")
        model.setLabel(id: "koan:/tank/media", label: "the pool")
        #expect(model.all.first?.label == "the pool")

        model.undo()
        #expect(model.all.first?.label == "media pool")

        model.undo()
        #expect(model.all.first?.label == nil)
    }

    @Test("undo after a clear restores the label that was cleared")
    func undoRestoresClearedLabel() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "media pool")
        model.setLabel(id: "koan:/tank/media", label: "")
        #expect(model.all.first?.label == nil)

        model.undo()
        #expect(model.all.first?.label == "media pool")
    }

    // MARK: - Scope carries the label through

    @Test("promoting a labelled favorite keeps its label")
    func scopeChangeKeepsLabel() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let model = makeModel(at: url)
        model.setLabel(id: "koan:/tank/media", label: "media pool")
        model.setScope(id: "koan:/tank/media", .global)
        #expect(model.all.first?.label == "media pool")
        #expect(model.all.first?.scope == .global)
    }

    // MARK: - Display rule

    @Test("a labelled favorite displays its label; an unlabelled one its path")
    func displayRulePrefersLabel() {
        let labelled = Favorite(host: "koan", path: "/tank/media", scope: .host, label: "media pool")
        let bare = Favorite(host: "koan", path: "/tank/media", scope: .host)
        #expect(labelled.displayTitle == "media pool")
        #expect(bare.displayTitle == "koan:/tank/media")
    }

    @Test("the ▾ host menu follows the same display rule")
    func hostMenuPrefersLabel() {
        let labelled = HostMenuButton.FavoriteEntry(
            id: "koan:/tank/media",
            host: "koan",
            path: "/tank/media",
            label: "media pool",
            scope: .host,
            isGlobal: false)
        let bare = HostMenuButton.FavoriteEntry(
            id: "koan:/tank/media",
            host: "koan",
            path: "/tank/media",
            label: nil,
            scope: .host,
            isGlobal: false)
        #expect(labelled.displayTitle == "media pool")
        #expect(bare.displayTitle == "koan:/tank/media")
    }

    // MARK: - Panel edit state

    @Test("beginEditing opens the field and moves the cursor to that row")
    func beginEditingMovesCursor() {
        let panel = FavoritesPanelModel()
        panel.beginEditing(id: "koan:/tank/media")
        #expect(panel.editingID == "koan:/tank/media")
        #expect(panel.cursor == "fav:koan:/tank/media")
    }

    @Test("cancelEditing closes the field and leaves the cursor where it was")
    func cancelEditingKeepsCursor() {
        let panel = FavoritesPanelModel()
        panel.beginEditing(id: "koan:/tank/media")
        panel.cancelEditing()
        #expect(panel.editingID == nil)
        #expect(panel.cursor == "fav:koan:/tank/media")
    }
}

// MARK: - Click arming

@Suite("favorite rename — the second-click guard")
struct FavoriteRenameArmingTests {
    @Test("a click that only focuses a row never edits")
    func unfocusedRowJumps() {
        #expect(
            !FavoriteRenameArming.shouldBeginEdit(
                isFocused: false, secondsSincePreviousClick: 10, doubleClickInterval: 0.5))
    }

    @Test("the second click of a double-click jumps, it does not edit")
    func withinDoubleClickIntervalJumps() {
        #expect(
            !FavoriteRenameArming.shouldBeginEdit(
                isFocused: true, secondsSincePreviousClick: 0.2, doubleClickInterval: 0.5))
    }

    @Test("a later single click on the focused row edits")
    func focusedRowAfterIntervalEdits() {
        #expect(
            FavoriteRenameArming.shouldBeginEdit(
                isFocused: true, secondsSincePreviousClick: 1.2, doubleClickInterval: 0.5))
    }

    @Test("the interval boundary itself does not arm — strictly later does")
    func boundaryIsNotArmed() {
        #expect(
            !FavoriteRenameArming.shouldBeginEdit(
                isFocused: true, secondsSincePreviousClick: 0.5, doubleClickInterval: 0.5))
    }
}
