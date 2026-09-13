import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.librarySurface"
            ].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ].waitForExistence(timeout: 5))
        let wordmark = app.descendants(matching: .any)["scholium.wordmark"]
        let search = app.searchFields["scholium.searchField"]
        let notifications = app.buttons["Open Triptych Notifications"]
        XCTAssertFalse(wordmark.exists)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        XCTAssertLessThan(notifications.frame.maxY, search.frame.minY)
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychManagement"].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.folderRow.Attachments"].exists
        )
        XCTAssertFalse(app.toolbars.firstMatch.buttons["Agent Changes"].exists)
        XCTAssertEqual(app.windows.count, 1)

        let sessionsURL =
            homeDirectory
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Window Sessions", isDirectory: true)
        let sessions = try FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension == "json" }
        XCTAssertEqual(
            sessions.count,
            1,
            "A fixture launch without an explicit Session ID must reuse one per-process fallback."
        )
        XCTAssertNotNil(UUID(uuidString: sessions[0].deletingPathExtension().lastPathComponent))
    }

    @MainActor
    func testNativeSidebarToggleAndLibraryTriptychIdentityRemainAvailable() throws {
        waitForCurrentDocumentSurface()
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let wordmark = app.descendants(matching: .any)["scholium.wordmark"]
        XCTAssertFalse(wordmark.exists)
        let hideSidebar = sidebarModeControl("Library")
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(librarySurface.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychManagement"].exists
        )
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()
        XCTAssertTrue(app.menuItems["New Triptych…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Open Triptych"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let organize = app.descendants(matching: .any)[
            "scholium.libraryFilters"
        ].firstMatch
        let create = app.descendants(matching: .any)[
            "scholium.libraryCreate"
        ].firstMatch
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(organize.frame.maxX, create.frame.minX)
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.libraryDisclosureToggle"].exists
        )
        organize.click()
        let collapseAll = app.menuItems["Collapse All Folders"]
        let expandAll = app.menuItems["Expand All Folders"]
        XCTAssertTrue(collapseAll.exists || expandAll.exists)
        app.typeKey(.escape, modifierFlags: [])

        let folderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ]
        let noteRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        XCTAssertEqual(
            noteRow.frame.minX,
            folderRow.frame.minX,
            accuracy: 2,
            "Top-level Folder and Note titles must share one Library text column."
        )
        XCTAssertFalse(app.buttons["Collapse Note"].exists)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Collapse Note"].exists)
        app.typeKey(.escape, modifierFlags: [])

        hideSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                !self.app.descendants(matching: .any)["scholium.librarySurface"].exists
            })
        let showSidebar = sidebarModeControl("Library")
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        showSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 1)

        let shellScreenshot = XCTAttachment(screenshot: window.screenshot())
        shellScreenshot.name = "Full-height editorial Library with native sidebar controls"
        shellScreenshot.lifetime = .keepAlways
        add(shellScreenshot)
    }

    /// Native tabs retain the destination while Library navigation stays native.
    @MainActor
    func testNativeTriptychWorkspaceNavigatorUsesSelectionAndArrowKeys() throws {
        waitForCurrentDocumentSurface()
        let navigator = app.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let topics = navigator.descendants(matching: .any)["Topics"].firstMatch
        XCTAssertTrue(topics.waitForExistence(timeout: 5))
        topics.click()
        let topicNote = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].firstMatch
        XCTAssertTrue(topicNote.waitForExistence(timeout: 8))
        topicNote.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Native workspace tabs and retained Library"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLibraryOrganizationPreservesDocumentAndCancelsMove() throws {
        waitForCurrentDocumentSurface()
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalBytes = try Data(contentsOf: noteURL)
        let organize = app.descendants(matching: .any)["scholium.libraryFilters"].firstMatch
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.click()
        XCTAssertTrue(app.menuItems["Sort By"].firstMatch.waitForExistence(timeout: 5))
        let annotations = app.menuItems["Link Annotations"].firstMatch
        XCTAssertTrue(annotations.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 10) { annotations.isEnabled })
        annotations.click()
        // The standard Triptych intentionally contains annotated links. Combine
        // with malformed managed Metadata, absent from this freshly built fixture.
        organize.click()
        app.menuItems["Malformed Metadata"].firstMatch.click()

        let emptyState = app.descendants(matching: .any)["scholium.libraryEmpty"].firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        let emptyCopy = emptyState.staticTexts.firstMatch
        XCTAssertTrue(accessibilityText(of: emptyCopy).contains("No Matching Notes"))
        XCTAssertFalse(accessibilityText(of: emptyCopy).contains("Create a Note to begin."))
        let emptyScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        emptyScreenshot.name = "Filtered Library retains Document and Clear"
        emptyScreenshot.lifetime = .keepAlways
        add(emptyScreenshot)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        let status = app.descendants(matching: .any)["scholium.libraryFilterStatus"].firstMatch
        let clear = status.buttons["Clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let row = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(status.exists)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let contextMenu = app.menus["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 5))
        let move = contextMenu.menuItems["Move Note…"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(move.isEnabled)
        move.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.textFields.firstMatch.exists)
        let buttons = XCTAttachment(screenshot: sheet.screenshot())
        buttons.name = "Neutral native sheet buttons"
        buttons.lifetime = .keepAlways
        add(buttons)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        XCTAssertTrue(row.exists)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
    }

    @MainActor
    func testNativeCommandButtonsPreserveDefaultDisabledAndCancelActions() throws {
        waitForCurrentDocumentSurface()
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let movedURL = triptychDirectory.appendingPathComponent("01-analyses/QA Button Move.md")
        let originalBytes = try Data(contentsOf: sourceURL)
        let row = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Move Note…"].firstMatch.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let field = sheet.textFields.firstMatch
        field.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        let move = sheet.buttons["Move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) { !move.isEnabled })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sheet.exists)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
        typeCommittedText("QA Button Move.md", into: field, in: app)
        XCTAssertTrue(waitUntil(timeout: 3) { move.isEnabled })
        let ready = XCTAttachment(screenshot: sheet.screenshot())
        ready.name = "Neutral default Move button"
        ready.lifetime = .keepAlways
        add(ready)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertTrue(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: movedURL.path) })
        XCTAssertEqual(try Data(contentsOf: movedURL), originalBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        let movedRow = app.descendants(matching: .any)["scholium.noteRow.QA Button Move.md"].firstMatch
        XCTAssertTrue(movedRow.waitForExistence(timeout: 5))
        movedRow.rightClick()
        app.menuItems["Move to Trash…"].firstMatch.click()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Move to Trash"].exists)
        let destructive = XCTAttachment(screenshot: confirmation.screenshot())
        destructive.name = "Destructive role stays distinct from neutral Cancel"
        destructive.lifetime = .keepAlways
        add(destructive)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !confirmation.exists })
        XCTAssertEqual(try Data(contentsOf: movedURL), originalBytes)
    }

    @MainActor
    func testLibraryRemainsReadableAtItsNativeMinimum() throws {
        waitForCurrentDocumentSurface()

        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            library.frame.width,
            QAWorkspaceMetricContract.libraryMinimumReadableWidth - 1,
            "An expanded Library must not remain below its content-tested readable width."
        )

        for (scope, identifier) in [
            ("Analyses", "Analyses"),
            ("Topics", "Topics"),
            ("Works", "Works"),
        ] {
            let control = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(
                control.frame.height,
                32,
                "The \(scope) scope must remain a single-line control at the Library minimum."
            )
        }

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Library at the 300pt native readable minimum"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testTwoHundredPercentDocumentTextPersistsAcrossEveryMode() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.documentTextSizeMenu"].exists,
            "Text size belongs in the View menu rather than permanent document chrome."
        )

        app.menuBars.menuBarItems["View"].click()
        let documentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(documentTextSizeMenu.waitForExistence(timeout: 3))
        documentTextSizeMenu.hover()
        let twoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(twoHundredPercent.waitForExistence(timeout: 3))
        twoHundredPercent.click()

        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        selectDocumentMode("Edit")
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"].waitForExistence(
                timeout: 8))

        selectDocumentMode("Source")
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))

        selectDocumentMode("Review")
        waitForCurrentDocumentSurface()

        let sessionFile = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                guard let data = try? Data(contentsOf: sessionFile),
                    let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let scale = snapshot["documentTextScale"] as? NSNumber
                else { return false }
                return scale.doubleValue == 2.0
            })

        app.terminate()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        app.menuBars.menuBarItems["View"].click()
        let restoredDocumentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(restoredDocumentTextSizeMenu.waitForExistence(timeout: 3))
        restoredDocumentTextSizeMenu.hover()
        let restoredTwoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(restoredTwoHundredPercent.waitForExistence(timeout: 3))
        XCTAssertFalse(
            restoredTwoHundredPercent.isEnabled,
            "The restored window session must reapply 200% after asynchronous workspace restoration."
        )
        app.typeKey(.escape, modifierFlags: [])
    }

}
