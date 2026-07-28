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

    @Test("beginEditing opens the field, seeds the text, and moves the cursor")
    func beginEditingMovesCursor() {
        let panel = FavoritesPanelModel()
        panel.beginEditing(id: "koan:/tank/media", current: "media pool")
        #expect(panel.editingID == "koan:/tank/media")
        #expect(panel.editingText == "media pool")
        #expect(panel.cursor == "fav:koan:/tank/media")
    }

    @Test("an unlabelled favorite opens an empty field")
    func beginEditingWithNoLabel() {
        let panel = FavoritesPanelModel()
        panel.beginEditing(id: "koan:/tank/media", current: nil)
        #expect(panel.editingText.isEmpty)
    }

    @Test("cancelEditing closes the field, drops the text, keeps the cursor")
    func cancelEditingKeepsCursor() {
        let panel = FavoritesPanelModel()
        panel.beginEditing(id: "koan:/tank/media", current: "media pool")
        panel.cancelEditing()
        #expect(panel.editingID == nil)
        #expect(panel.editingText.isEmpty)
        #expect(panel.cursor == "fav:koan:/tank/media")
    }

    /// The click-away path his hands found dead: anything can commit the field.
    @Test("commitOpenEdit saves the model-held text and closes the field")
    func commitOpenEditSaves() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let favorites = makeModel(at: url)
        let panel = FavoritesPanelModel()
        let actions = FavoritesPanelActions(
            jump: { _, _ in },
            unstar: { _ in },
            setScope: { _, _ in },
            setLabel: { id, label in favorites.setLabel(id: id, label: label) })

        panel.beginEditing(id: "koan:/tank/media", current: nil)
        panel.editingText = "job search"
        actions.commitOpenEdit(on: panel)

        #expect(favorites.all.first?.label == "job search")
        #expect(panel.editingID == nil)
    }

    @Test("commitOpenEdit with no field open touches nothing")
    func commitOpenEditNoOp() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let favorites = makeModel(at: url)
        let panel = FavoritesPanelModel()
        var setLabelCalls = 0
        let actions = FavoritesPanelActions(
            jump: { _, _ in },
            unstar: { _ in },
            setScope: { _, _ in },
            setLabel: { _, _ in setLabelCalls += 1 })

        actions.commitOpenEdit(on: panel)
        #expect(setLabelCalls == 0)
        #expect(favorites.all.first?.label == nil)
    }
}

// MARK: - Click arming

@Suite("favorite rename — the second-click guard")
struct FavoriteRenameArmingTests {
    @Test("a click that only focuses a row never arms a rename")
    func unfocusedRowJumps() {
        #expect(
            !FavoriteRenameArming.shouldArmRename(
                isFocused: false, secondsSincePreviousClick: 10, doubleClickInterval: 0.5))
    }

    @Test("the second click of a double-click jumps, it does not arm")
    func withinDoubleClickIntervalJumps() {
        #expect(
            !FavoriteRenameArming.shouldArmRename(
                isFocused: true, secondsSincePreviousClick: 0.2, doubleClickInterval: 0.5))
    }

    @Test("a later single click on the focused row arms the rename")
    func focusedRowAfterIntervalArms() {
        #expect(
            FavoriteRenameArming.shouldArmRename(
                isFocused: true, secondsSincePreviousClick: 1.2, doubleClickInterval: 0.5))
    }

    @Test("the interval boundary itself does not arm — strictly later does")
    func boundaryIsNotArmed() {
        #expect(
            !FavoriteRenameArming.shouldArmRename(
                isFocused: true, secondsSincePreviousClick: 0.5, doubleClickInterval: 0.5))
    }

    /// The bug his hands found: a double-click on an already-focused row.
    ///
    /// The first click passes the predicate — the row is focused and the last
    /// click was long ago — so opening the field there and then turned every
    /// double-click into a rename. Arming instead of opening is the fix: the
    /// second click arrives inside the interval, fails the predicate, and
    /// cancels what the first click armed.
    @Test("a double-click on an already-focused row arms, then takes it back")
    func doubleClickOnFocusedRowNeverRenames() {
        let first = FavoriteRenameArming.shouldArmRename(
            isFocused: true, secondsSincePreviousClick: 30, doubleClickInterval: 0.5)
        #expect(first, "the first click arms — it must not open the field outright")
        let second = FavoriteRenameArming.shouldArmRename(
            isFocused: true, secondsSincePreviousClick: 0.1, doubleClickInterval: 0.5)
        #expect(!second, "the second click jumps, and cancels what the first armed")
    }
}
