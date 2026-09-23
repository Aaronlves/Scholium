import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testNativeReadEditPreservesTheDocumentSurface() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")
        let editor = app.textViews["scholium.document.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let source = editor.value as? String
        XCTAssertFalse((source ?? "").isEmpty)
        selectDocumentMode("Read")
        XCTAssertEqual(documentModeState(mode), "Read")
        XCTAssertEqual(editor.value as? String, source)
        selectDocumentMode("Edit")
        XCTAssertEqual(editor.value as? String, source)
        app.menuBars.menuBarItems["View"].click()
        let modes = app.menuItems["Document Mode"].firstMatch
        modes.hover()
        XCTAssertFalse(app.menuItems["Source"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testNewWindowCreatesIndependentDocumentSurface() throws {
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count >= 2 })
        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
    }

}
