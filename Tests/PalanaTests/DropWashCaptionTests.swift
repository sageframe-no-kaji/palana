// DropWashCaptionTests — the drop caption names where a drop lands: the
// pane's own directory, or the folder row under the pointer.

import Testing

@testable import Palana

@MainActor
@Suite("Drop caption")
struct DropWashCaptionTests {
    @Test("over the pane, the caption states the verb and the modifier")
    func pane() {
        #expect(DropWash.caption(folderName: nil) == "drop to copy · hold ⌘ to move")
    }

    @Test("over a folder row, the caption names the folder")
    func folder() {
        #expect(DropWash.caption(folderName: "fade") == "drop into fade/ to copy · hold ⌘ to move")
    }
}
