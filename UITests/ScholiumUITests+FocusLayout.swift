import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// One window journey crosses the native Sidebar responder, embedded
    /// editor, View command, and AppKit full-screen lifecycle.
    @MainActor
    func testFocusLayoutRestoresWindowedLayoutAroundNativeFullScreen() throws {
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        selectDocumentMode("Edit")
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let originalSource = try XCTUnwrap(editor.value as? String)
        XCTAssertFalse(originalSource.isEmpty)
        let sidebarSearch = app.searchFields["scholium.searchField"].firstMatch
        let toolbar = app.toolbars.firstMatch
        let mainWindow = app.windows.firstMatch
        func isPresentedInWindow(_ element: XCUIElement) -> Bool {
            guard element.exists else { return false }
            let frame = element.frame
            let windowFrame = mainWindow.frame
            guard frame.minX.isFinite, frame.minY.isFinite,
                frame.width.isFinite, frame.height.isFinite,
                windowFrame.minX.isFinite, windowFrame.minY.isFinite,
                windowFrame.width.isFinite, windowFrame.height.isFinite
            else { return false }
            let visible = frame.intersection(windowFrame)
            return !visible.isNull && visible.width > 0 && visible.height > 0
        }
        XCTAssertTrue(sidebarSearch.waitForExistence(timeout: 5))
        sidebarSearch.click()
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(waitUntil(timeout: 5) { keyboardFocus.evaluate(with: sidebarSearch) })

        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                !isPresentedInWindow(toolbar)
                    && !isPresentedInWindow(sidebarSearch)
                    && keyboardFocus.evaluate(with: editor)
            }, "Focus Layout did not transfer focus from the collapsed Sidebar to the current document.")
        XCTAssertEqual(editor.value as? String, originalSource)

        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                isPresentedInWindow(toolbar) && isPresentedInWindow(sidebarSearch)
            }, "Exiting Focus Layout did not restore the ordinary window chrome and Sidebar.")
        XCTAssertTrue(keyboardFocus.evaluate(with: editor))
        sidebarSearch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { keyboardFocus.evaluate(with: sidebarSearch) })

        let viewMenu = app.menuBars.menuBarItems["View"]
        viewMenu.click()
        let enterFullScreen = app.menuItems["Enter Full Screen"]
        XCTAssertTrue(enterFullScreen.waitForExistence(timeout: 5))
        enterFullScreen.click()
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                !isPresentedInWindow(toolbar) && !isPresentedInWindow(sidebarSearch)
                    && keyboardFocus.evaluate(with: editor)
            }, "Native full screen did not enable Focus Layout.")
        // The Focus shortcut cannot undo the layout enforced by full screen.
        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertFalse(isPresentedInWindow(toolbar))
        viewMenu.click()
        let exitFullScreen = app.menuItems["Exit Full Screen"]
        XCTAssertTrue(exitFullScreen.waitForExistence(timeout: 5))
        exitFullScreen.click()
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                isPresentedInWindow(toolbar) && isPresentedInWindow(sidebarSearch)
            }, "Exiting native full screen did not restore the preceding windowed layout.")
        XCTAssertTrue(keyboardFocus.evaluate(with: editor))
        XCTAssertEqual(editor.value as? String, originalSource)
    }
}
