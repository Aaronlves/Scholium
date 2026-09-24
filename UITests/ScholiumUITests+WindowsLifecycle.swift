import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testLivePreviewUsesDocumentModeMenuForSourceTransition() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)

        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertEqual(documentModeState(mode), "Edit", "Source must be entered through the document-mode menu")

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertEqual(documentModeState(mode), "Source")
    }

    @MainActor
    func testNewWindowCreatesIndependentDocumentSurface() throws {
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count >= 2 })
        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
    }

}
