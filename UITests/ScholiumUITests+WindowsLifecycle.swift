import AppKit
import CryptoKit
@preconcurrency import XCTest

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

    @MainActor
    func testDocumentTabTransfersThroughSeparateWindowWithSearchAndFind() throws {
        let mainID = app.windows.firstMatch.identifier
        let main = app.windows[mainID]
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalSource = try self.source(at: noteURL)

        _ = clickLibraryRow("QA Autosave B.md", in: main, rightMouseButton: true)
        let noteMenu = app.menus["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(noteMenu.waitForExistence(timeout: 3))
        noteMenu.menuItems["Open in New Tab"].click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 8))
        let tabs = main.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        let firstTab = tabs.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "QA Autosave A")
        ).firstMatch
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        firstTab.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 8))

        let token = " WINDOW-TRANSFER-\(UUID().uuidString)"
        try enterLivePreviewAndAppend(token, in: main)
        focusWorkspaceWindow(main)
        app.typeKey("f", modifierFlags: [.command])
        let mainFind = main.descendants(matching: .any)["scholium.documentFind.query"]
        XCTAssertTrue(mainFind.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !mainFind.exists })
        app.menuBars.menuBarItems["Window"].click()
        let moveOut = app.menuItems["Move to Separate Window"].firstMatch
        XCTAssertTrue(moveOut.waitForExistence(timeout: 3) && moveOut.isEnabled)
        moveOut.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 12) { self.app.windows.count == 2 })
        guard
            let detachedID = app.windows.allElementsBoundByIndex.first(where: {
                $0.identifier != mainID && $0.title == "QA Autosave A"
            })?.identifier
        else {
            XCTFail("The transferred Note must appear in its own Document window.")
            return
        }
        let detached = app.windows[detachedID]
        XCTAssertFalse(detached.descendants(matching: .any)["scholium.librarySurface"].exists)
        XCTAssertFalse(detached.descendants(matching: .any)["scholium.researchInspector"].exists)
        XCTAssertFalse(detached.descendants(matching: .any)["scholium.documentTabs"].exists)
        let detachedEditor = detached.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(
            waitUntil(timeout: 10) { (detachedEditor.value as? String)?.contains(token) == true },
            "The separate window must receive the live source session."
        )

        focusWorkspaceWindow(detached)
        XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: detachedEditor))
        detachedEditor.typeKey("f", modifierFlags: [.command])
        let find = detached.descendants(matching: .any)["scholium.documentFind.query"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        typeCommittedText(token.trimmingCharacters(in: .whitespaces), into: find, in: app)
        let matches = detached.staticTexts["scholium.documentFind.matches"]
        XCTAssertTrue(waitUntil(timeout: 8) { (matches.value as? String) == "Match 1 of 1" })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !find.exists })

        let sourceBeforeFormat = try XCTUnwrap(detachedEditor.value as? String)
        detachedEditor.click()
        detachedEditor.typeKey(.end, modifierFlags: .command)
        detachedEditor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.menuBars.menuBarItems["Format"].click()
        let bold = app.menuItems["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 3) && bold.isEnabled)
        bold.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (detachedEditor.value as? String) != sourceBeforeFormat
            })
        detachedEditor.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (detachedEditor.value as? String) == sourceBeforeFormat
            })

        app.menuBars.menuBarItems["View"].click()
        let advancedAction = app.menuItems["Advanced Search…"].firstMatch
        XCTAssertTrue(advancedAction.waitForExistence(timeout: 3) && advancedAction.isEnabled)
        advancedAction.click()
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 8))
        XCTAssertTrue(advanced.searchFields["scholium.searchField"].waitForExistence(timeout: 5))
        // The auxiliary window is still foreground here; native close returns
        // focus to the detached Document that owns this Search session.
        advanced.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !advanced.exists })
        XCTAssertTrue(detached.exists)

        app.menuBars.menuBarItems["Window"].click()
        let moveBack = app.menuItems["Move to Main Window"].firstMatch
        XCTAssertTrue(moveBack.waitForExistence(timeout: 3) && moveBack.isEnabled)
        moveBack.click()
        XCTAssertTrue(waitUntil(timeout: 12) { !detached.exists && self.app.windows.count == 1 })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 10))
        let returnedEditor = main.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(
            waitUntil(timeout: 8) { (returnedEditor.value as? String)?.contains(token) == true },
            "Moving back must retain the same editable source and mode."
        )
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        XCTAssertEqual(
            tabs.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "QA Autosave B")
            ).count, 1)

        returnedEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                (try? self.source(at: noteURL).contains(token)) == true
            })
        XCTAssertEqual(try self.source(at: noteURL).replacingOccurrences(of: token, with: ""), originalSource)
        app.menuBars.menuBarItems["File"].click()
        let closeTab = app.menuItems["Close Tab"].firstMatch
        XCTAssertTrue(closeTab.waitForExistence(timeout: 3))
        closeTab.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 8))
    }

}
