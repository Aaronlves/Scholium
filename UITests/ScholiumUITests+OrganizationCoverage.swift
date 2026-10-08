import AppKit
import Darwin
import XCTest

extension ScholiumUITests {
    @MainActor
    func testLibraryDragToRootAndBackPreservesOpenNoteIdentity() throws {
        waitForCurrentDocumentSurface()
        let main = stableWorkspaceWindow(app.windows.firstMatch)
        let mainID = main.identifier
        let vault = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let filename = "QA Autosave A.md"
        let folder = "QA Drag Return"
        let nestedPath = folder + "/" + filename
        let rootURL = vault.appendingPathComponent(filename)
        let nestedURL = vault.appendingPathComponent(nestedPath)
        let originalBytes = try Data(contentsOf: rootURL)
        let identity = try organizationNoteIdentity(at: filename)
        let noteID = try XCTUnwrap(identity["id"] as? String)
        let vaultID = try XCTUnwrap(identity["vaultID"] as? String)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(folder, isDirectory: true), withIntermediateDirectories: false)

        // The native Move command establishes the nested starting state. Both
        // acceptance moves below must complete through actual outline drags.
        organizationContextAction("Move Note…", for: filename)
        let sheet = main.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        typeCommittedText(nestedPath, into: sheet.textFields.firstMatch, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 15) { !sheet.exists && FileManager.default.fileExists(atPath: nestedURL.path) })
        try organizationAssertMovedNote(
            path: nestedPath, absent: rootURL, bytes: originalBytes, noteID: noteID, vaultID: vaultID, mainID: mainID)

        let filters = main.descendants(matching: .any)["scholium.libraryFilters"].firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.click()
        let collapse = app.menuItems["Collapse All Folders"].firstMatch
        if collapse.exists { collapse.click() } else { app.typeKey(.escape, modifierFlags: []) }
        let outline = main.outlines["scholium.noteList"].firstMatch
        let folderRow = outline.descendants(matching: .outlineRow)
            .containing(.any, identifier: "scholium.folderRow." + folder).firstMatch
        XCTAssertTrue(folderRow.waitForExistence(timeout: 10))
        focusWorkspaceWindow(main)
        folderRow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
        app.typeKey(.rightArrow, modifierFlags: [])
        let source = outline.descendants(matching: .outlineRow)
            .containing(.any, identifier: "scholium.noteRow." + nestedPath).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()

        // All other folders are collapsed, leaving a short visible outline.
        // AppKit owns the root insertion gap below its final row; the Library
        // header and an ordinary Note row are deliberately not drop targets.
        let rows = outline.descendants(matching: .outlineRow).allElementsBoundByIndex
        let lastRow = try XCTUnwrap(rows.max { $0.frame.maxY < $1.frame.maxY })
        let viewport = outline.frame.intersection(main.frame)
        let rootY = lastRow.frame.maxY + 14
        XCTAssertLessThan(rootY, viewport.maxY - 4, "The collapsed fixture must expose a visible native root drop gap.")
        let rootDrop = outline.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: 28, dy: rootY - outline.frame.minY))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            .click(forDuration: 0.8, thenDragTo: rootDrop)
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                FileManager.default.fileExists(atPath: rootURL.path)
                    && !FileManager.default.fileExists(atPath: nestedURL.path)
            }, "Dragging below the last Library row must move the Note to the vault root.")
        try organizationAssertMovedNote(
            path: filename, absent: nestedURL, bytes: originalBytes, noteID: noteID, vaultID: vaultID, mainID: mainID)
        organizationCaptureDragBoundary("Library drag to root", window: main)

        let rootRow = outline.descendants(matching: .outlineRow)
            .containing(.any, identifier: "scholium.noteRow." + filename).firstMatch
        XCTAssertTrue(rootRow.waitForExistence(timeout: 5))
        XCTAssertTrue(folderRow.exists)
        rootRow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            .click(forDuration: 0.8, thenDragTo: folderRow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)))
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                FileManager.default.fileExists(atPath: nestedURL.path)
                    && !FileManager.default.fileExists(atPath: rootURL.path)
            }, "The return drag must move the same open Note into its original folder.")
        try organizationAssertMovedNote(
            path: nestedPath, absent: rootURL, bytes: originalBytes, noteID: noteID, vaultID: vaultID, mainID: mainID)
        organizationCaptureDragBoundary("Library drag back to folder", window: main)
    }

    private func organizationNoteIdentity(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: triptychDirectory.appendingPathComponent(".scholium/identities.json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try XCTUnwrap(document["records"] as? [[String: Any]])
        let matches = records.filter { $0["relativePath"] as? String == path }
        XCTAssertEqual(matches.count, 1, "The synthetic Note must have one unambiguous stored identity.")
        return try XCTUnwrap(matches.first)
    }

    @MainActor
    private func organizationAssertMovedNote(
        path: String, absent: URL, bytes: Data, noteID: String, vaultID: String, mainID: String
    ) throws {
        let source = triptychDirectory.appendingPathComponent("01-analyses/" + path)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: absent.path))
        let identity = try organizationNoteIdentity(at: path)
        XCTAssertEqual(identity["id"] as? String, noteID)
        XCTAssertEqual(identity["vaultID"] as? String, vaultID)
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(app.windows[mainID].exists, "Moving a Note must retain its original native window.")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: app.windows[mainID], timeout: 8))
        let sessionURL = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions/" + sessionID.uuidString + ".json")
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                guard let data = try? Data(contentsOf: sessionURL),
                    let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let selected = session["selectedDocument"] as? [String: Any],
                    let open = session["openDocuments"] as? [[String: Any]]
                else { return false }
                return selected["relativePath"] as? String == path
                    && selected["vaultID"] as? String == vaultID
                    && open.count == 1 && open.first?["relativePath"] as? String == path
            }, "The original window must retain the moved Note as its selected, sole document.")
    }

    @MainActor
    private func organizationCaptureDragBoundary(_ name: String, window: XCUIElement) {
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testReviewedChangesHistoryDeletionKeepsTheCurrentNote() throws {
        waitForCurrentDocumentSurface()
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let before = try Data(contentsOf: note)
        var after = before
        let sentence = "Synthetic reviewed history 论证 " + sessionID.uuidString
        after.append(Data(("\n\n" + sentence + "\n").utf8))
        try after.write(to: note)
        let bell = app.toolbars.buttons["Open Triptych Notifications"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        bell.click()
        let item = app.popovers.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "scholium.notification.change.", "QA Autosave A")
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15))
        item.click()
        let changes = app.descendants(matching: .any)["scholium.changes"].firstMatch
        XCTAssertTrue(changes.waitForExistence(timeout: 10))
        let mark = changes.buttons["scholium.changes.markReviewed"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { mark.exists && mark.isEnabled })
        mark.click()
        XCTAssertTrue(waitUntil(timeout: 10) { !mark.exists || !mark.isEnabled })
        XCTAssertEqual(try Data(contentsOf: note), after)
        let history = changes.descendants(matching: .any).matching(identifier: "History").firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.click()
        let historyTable = changes.tables["scholium.changes.history"].firstMatch
        XCTAssertTrue(historyTable.waitForExistence(timeout: 10))
        let row = historyTable.tableRows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.doubleClick()
        let actions = changes.descendants(matching: .any)["scholium.changes.historyActions"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: changes.screenshot())
        capture.name = "Reviewed history retains exact source comparison"
        capture.lifetime = .keepAlways
        add(capture)
        actions.click()
        app.menuItems["Delete from History"].firstMatch.click()
        let cancel = app.sheets["alert"].firstMatch.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        XCTAssertTrue(actions.exists)
        XCTAssertEqual(try Data(contentsOf: note), after)
        actions.click()
        app.menuItems["Delete from History"].firstMatch.click()
        let delete = app.sheets["alert"].firstMatch.buttons["Delete Record"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        // ContentUnavailableView exposes its title and explanation as one
        // native static-text value, rather than a separately labelled title.
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                changes.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "No Reviewed History")).firstMatch.exists
            })
        XCTAssertEqual(try Data(contentsOf: note), after)
        changes.buttons["Close"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !changes.exists })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
    }

    @MainActor
    func testCommittedOrganizationPreservesSourceAndRecoversFromCollision() throws {
        waitForCurrentDocumentSurface()
        let vault = triptychDirectory.appendingPathComponent("01-analyses")
        let original = vault.appendingPathComponent("QA Autosave A.md")
        let bytes = try Data(contentsOf: original)
        let collision = vault.appendingPathComponent("QA Autosave B.md")
        let collisionBytes = try Data(contentsOf: collision)
        let uniqueName = "QA Organization " + sessionID.uuidString
        let duplicate = vault.appendingPathComponent(uniqueName + ".md")
        let moved = vault.appendingPathComponent("格式与检索/" + uniqueName + ".md")

        organizationContextAction("Duplicate…", for: "QA Autosave A.md")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        typeCommittedText(duplicate.lastPathComponent, into: sheet.textFields.firstMatch, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists && FileManager.default.fileExists(atPath: duplicate.path) })
        XCTAssertEqual(try Data(contentsOf: duplicate), bytes)
        XCTAssertEqual(try Data(contentsOf: original), bytes)

        organizationContextAction("Move Note…", for: duplicate.lastPathComponent)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        typeCommittedText("QA Autosave B.md", into: sheet.textFields.firstMatch, in: app)
        app.typeKey(.return, modifierFlags: [])
        let dismiss = sheet.sheets.firstMatch.buttons["Dismiss"].firstMatch
        XCTAssertTrue(dismiss.waitForExistence(timeout: 8), "A collision must report failure without replacing its destination.")
        XCTAssertEqual(try Data(contentsOf: duplicate), bytes)
        XCTAssertEqual(try Data(contentsOf: collision), collisionBytes)
        dismiss.click()
        typeCommittedText("格式与检索/" + uniqueName + ".md", into: sheet.textFields.firstMatch, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists && FileManager.default.fileExists(atPath: moved.path) })
        XCTAssertEqual(try Data(contentsOf: moved), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.path))
        XCTAssertEqual(try Data(contentsOf: original), bytes)

        // Use a unique test-owned source name so the native Trash result can
        // be cleaned by exact path and bytes, without listing the user's Trash.
        organizationContextAction("Duplicate…", for: "QA Autosave A.md")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        typeCommittedText(duplicate.lastPathComponent, into: sheet.textFields.firstMatch, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists && FileManager.default.fileExists(atPath: duplicate.path) })
        let trashDirectory = try FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: duplicate, create: false)
        let trashResult = trashDirectory.appendingPathComponent(duplicate.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashResult.path))
        defer {
            if let trashedBytes = try? Data(contentsOf: trashResult), trashedBytes == bytes {
                do {
                    try FileManager.default.removeItem(at: trashResult)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: trashResult.path))
                } catch {
                    XCTFail("Could not remove the exact test-owned Trash result: \(error)")
                }
            }
        }
        organizationContextAction("Move to Trash…", for: duplicate.lastPathComponent)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertEqual(try Data(contentsOf: duplicate), bytes)
        try requireNativeTrashVerification(for: duplicate)
        organizationContextAction("Move to Trash…", for: duplicate.lastPathComponent)
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let confirmation = XCTAttachment(screenshot: sheet.screenshot())
        confirmation.name = "Synthetic duplicate native Trash confirmation"
        confirmation.lifetime = .keepAlways
        add(confirmation)
        sheet.buttons["Move to Trash"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists && !FileManager.default.fileExists(atPath: duplicate.path) })
        XCTAssertEqual(try Data(contentsOf: trashResult), bytes)
        XCTAssertEqual(try Data(contentsOf: moved), bytes)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    private func requireNativeTrashVerification(for source: URL) throws {
        let directory = try FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: source, create: false)
        // Open the directory without enumerating any private Trash contents.
        // Committing is allowed only when the runner can verify and clean its
        // exact synthetic result; a privacy block must create no more artifacts.
        let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw XCTSkip("macOS blocks native Trash verification and test-owned cleanup (errno \(errno)); commit was not attempted.")
        }
        Darwin.close(descriptor)
    }

    @MainActor
    private func organizationContextAction(_ title: String, for path: String) {
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        let outline = window.outlines["scholium.noteList"].firstMatch
        let row = outline.descendants(matching: .outlineRow).containing(.any, identifier: "scholium.noteRow." + path).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        func rowIsVisible() -> Bool {
            let viewport = outline.frame.intersection(window.frame)
            let frame = row.frame
            return frame.midY >= viewport.minY + 8 && frame.midY <= viewport.maxY - 8
                && frame.width > 20 && frame.height > 8
        }
        for _ in 0..<16 where !rowIsVisible() {
            let viewport = outline.frame.intersection(window.frame)
            let distance = row.frame.midY - viewport.midY
            outline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .scroll(byDeltaX: 0, deltaY: distance > 0 ? -min(distance, 1200) : min(-distance, 1200))
        }
        XCTAssertTrue(rowIsVisible(), "Scroll the actual Library row into view before its pointer context menu.")
        _ = clickLibraryRow(path, rightMouseButton: true)
        let contextMenu = app.menus["scholium.noteRow." + path].firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 5))
        let action = contextMenu.menuItems[title].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        action.click()
    }

    @MainActor
    func testPassageCopyExtractMoveAndMergeHaveExactPreviews() throws {
        app.terminate()
        let vault = triptychDirectory.appendingPathComponent("01-analyses")
        let sourceURL = vault.appendingPathComponent("QA Autosave A.md")
        let destinationURL = vault.appendingPathComponent("QA Autosave B.md")
        let passage = "Synthetic bilingual passage 论证 for exact transfer. ^qa-origin\n"
        let destinationSource = "Destination prose remains intact.\n"
        try Data(passage.utf8).write(to: sourceURL)
        try Data(destinationSource.utf8).write(to: destinationURL)
        app.launch()
        waitForCurrentDocumentSurface()
        selectDocumentMode("Source")
        let editor = app.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        let extractedName = "QA Extract " + sessionID.uuidString
        let extractedURL = vault.appendingPathComponent(extractedName + ".md")

        func openPassageAction(_ title: String) {
            editor.click()
            app.typeKey(.upArrow, modifierFlags: [.command])
            app.menuBars.menuBarItems["Research"].click()
            let command = app.menuItems[title].firstMatch
            XCTAssertTrue(command.waitForExistence(timeout: 5))
            XCTAssertTrue(command.isEnabled)
            command.click()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 8))
        }

        func chooseDestination() {
            let sheet = app.sheets.firstMatch
            let search = sheet.descendants(matching: .any)["scholium.restructure.search"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            typeCommittedText("QA Autosave B", into: search, in: app)
            let table = sheet.tables["scholium.restructure.destinations"].firstMatch
            XCTAssertTrue(table.waitForExistence(timeout: 5))
            let row = table.tableRows.firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.click()
        }

        func previewAndCommit(_ title: String) {
            let sheet = app.sheets.firstMatch
            let confirm = sheet.buttons["scholium.restructure.confirm"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 5) { confirm.isEnabled })
            confirm.click()
            XCTAssertTrue(waitUntil(timeout: 12) { confirm.label == title && confirm.isEnabled })
            let capture = XCTAttachment(screenshot: sheet.screenshot())
            capture.name = title + " exact changed-source preview"
            capture.lifetime = .keepAlways
            add(capture)
            confirm.click()
            XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists })
        }

        openPassageAction("Copy Passage to Note…")
        chooseDestination()
        previewAndCommit("Copy Passage")
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data(passage.utf8))
        let copied = try source(at: destinationURL)
        XCTAssertTrue(copied.hasPrefix(destinationSource))
        XCTAssertTrue(copied.contains("Synthetic bilingual passage 论证 for exact transfer."))
        XCTAssertFalse(copied.contains("^qa-origin"), "Copy assigns a fresh paragraph identity.")

        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: app.windows.firstMatch)
        selectDocumentMode("Source")
        openPassageAction("Extract to New Note…")
        let sheet = app.sheets.firstMatch
        let newPath = sheet.textFields["scholium.restructure.newPath"].firstMatch
        XCTAssertTrue(newPath.waitForExistence(timeout: 5))
        typeCommittedText(extractedName + ".md", into: newPath, in: app)
        sheet.buttons["scholium.restructure.confirm"].click()
        XCTAssertTrue(waitUntil(timeout: 12) { sheet.buttons["Extract Passage"].exists })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), Data(passage.utf8))

        openPassageAction("Extract to New Note…")
        typeCommittedText(extractedName + ".md", into: sheet.textFields["scholium.restructure.newPath"], in: app)
        previewAndCommit("Extract Passage")
        XCTAssertTrue(try source(at: extractedURL).contains(passage.trimmingCharacters(in: .newlines)))
        XCTAssertTrue(try source(at: sourceURL).contains(extractedName + "#^qa-origin"))

        openNote(extractedName + ".md", expectedTitle: extractedName, in: app.windows.firstMatch)
        selectDocumentMode("Source")
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        openPassageAction("Move Passage to Note…")
        chooseDestination()
        previewAndCommit("Move Passage")
        XCTAssertTrue(try source(at: extractedURL).contains("QA Autosave B#^qa-origin"))
        XCTAssertTrue(try source(at: sourceURL).contains("QA Autosave B#^qa-origin"), "Incoming paragraph links follow the transferred identity.")
        XCTAssertTrue(try source(at: destinationURL).contains("^qa-origin"))

        openNote(extractedName + ".md", expectedTitle: extractedName, in: app.windows.firstMatch)
        selectDocumentMode("Source")
        let mergeBytes = try Data(contentsOf: extractedURL)
        let trashDirectory = try FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: extractedURL, create: false)
        let trashResult = trashDirectory.appendingPathComponent(extractedURL.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashResult.path))
        defer {
            if let trashedBytes = try? Data(contentsOf: trashResult), trashedBytes == mergeBytes {
                do {
                    try FileManager.default.removeItem(at: trashResult)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: trashResult.path))
                } catch {
                    XCTFail("Could not remove the exact test-owned Trash result: \(error)")
                }
            }
        }
        app.menuBars.menuBarItems["Research"].click()
        app.menuItems["Merge into Another Note…"].firstMatch.click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        chooseDestination()
        let mergeConfirm = sheet.buttons["scholium.restructure.confirm"].firstMatch
        mergeConfirm.click()
        XCTAssertTrue(waitUntil(timeout: 12) { mergeConfirm.label == "Merge Notes" && mergeConfirm.isEnabled })
        let mergePreview = XCTAttachment(screenshot: sheet.screenshot())
        mergePreview.name = "Merge Notes exact preview before cancellation"
        mergePreview.lifetime = .keepAlways
        add(mergePreview)
        sheet.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertEqual(try Data(contentsOf: extractedURL), mergeBytes)
        try requireNativeTrashVerification(for: extractedURL)
        app.menuBars.menuBarItems["Research"].click()
        app.menuItems["Merge into Another Note…"].firstMatch.click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        chooseDestination()
        previewAndCommit("Merge Notes")
        XCTAssertFalse(FileManager.default.fileExists(atPath: extractedURL.path))
        XCTAssertEqual(try Data(contentsOf: trashResult), mergeBytes)
        XCTAssertTrue(try source(at: destinationURL).hasPrefix(destinationSource))
        XCTAssertTrue(try source(at: destinationURL).contains("论证"))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B"))
    }
}
