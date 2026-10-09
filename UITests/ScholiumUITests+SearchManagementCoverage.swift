import AppKit
import Foundation
@preconcurrency import XCTest

extension ScholiumUITests {
    /// Exercises Search entirely inside the Library, including compact recovery states.
    @MainActor
    func testSidebarSearchRemainsReadableAndRestoresLibrary() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_INCREASE_CONTRAST"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_TRANSPARENCY"] = "1"
        app.launch()
        waitForCurrentDocumentSurface()
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let originalNotes = try searchManagementNoteBytes()
        let field = workspace.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        // Query setup must not depend on the host's selected input method.
        // Restore only our clipboard write, preserving any intervening user copy.
        func enterQuery(_ text: String) throws {
            let pasteboard = NSPasteboard.general
            let savedItems =
                pasteboard.pasteboardItems?.map { item in
                    item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { values, type in
                        values[type] = item.data(forType: type)
                    }
                } ?? []
            try setPasteboardText(text)
            let ownedChangeCount = pasteboard.changeCount
            defer {
                if pasteboard.changeCount == ownedChangeCount {
                    pasteboard.clearContents()
                    if !savedItems.isEmpty {
                        pasteboard.writeObjects(
                            savedItems.map { values in
                                let item = NSPasteboardItem()
                                for (type, data) in values { item.setData(data, forType: type) }
                                return item
                            })
                    }
                }
            }
            field.click()
            field.typeKey("a", modifierFlags: [.command])
            field.typeKey("v", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == text })
        }

        func capture(_ name: String) {
            XCTAssertFalse(app.windows["scholium.advancedSearchWindow"].exists)
            XCTAssertTrue(workspace.frame.contains(field.frame))
            let attachment = XCTAttachment(screenshot: workspace.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        selectResearchSearchScope("This Vault", in: app)
        try enterQuery("syn")
        let completion = workspace.buttons["synthetic, Search term"].firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 20))
        field.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(completion.isSelected)
        capture("Normal Search selected suggestion Light")
        field.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == "synthetic" })
        XCTAssertTrue(searchResult(named: "QA Autosave A", in: workspace).waitForExistence(timeout: 10))

        try enterQuery("synthetic 编辑")
        XCTAssertTrue(searchResult(named: "QA Autosave B", in: workspace).waitForExistence(timeout: 10))
        XCTAssertTrue(workspace.buttons["编辑, Search term"].firstMatch.waitForExistence(timeout: 10))
        capture("Normal Search bilingual results Light")
        // Dismiss only suggestions, then move the native keyboard target to B.
        field.typeKey(.escape, modifierFlags: [])
        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.downArrow, modifierFlags: [])
        capture("Normal Search selected result Light")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 10))
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteList"].waitForExistence(timeout: 5))

        try enterQuery("\"unfinished")
        let invalid = workspace.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "Invalid Search Query")
        ).firstMatch
        XCTAssertTrue(invalid.waitForExistence(timeout: 10))
        XCTAssertTrue(accessibilityText(of: invalid).contains("The quoted phrase is not closed."))
        XCTAssertTrue(workspace.frame.contains(invalid.frame))
        capture("Normal Search invalid query Light")
        try enterQuery("qa-absent-sidebar-result")
        let empty = workspace.descendants(matching: .any)["scholium.searchEmpty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        capture("Normal Search empty results Light")

        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        resizeProofWindow(workspace, toWidth: 780, height: 640)
        try enterQuery("合成")
        selectResearchSearchScope("Triptych", in: app)
        XCTAssertEqual(field.value as? String, "合成", "Changing scope must preserve normal Search input.")
        let populatedResults = workspace.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.searchResult."))
        XCTAssertTrue(waitUntil(timeout: 20) { populatedResults.count > 2 })
        capture("Normal Search populated Triptych Dark narrow")

        try enterQuery("synthetic 编辑")
        XCTAssertTrue(searchResult(named: "QA Autosave A", in: workspace).waitForExistence(timeout: 10))
        capture("Normal Search bilingual results Dark narrow")
        XCTAssertTrue(workspace.buttons["编辑, Search term"].firstMatch.waitForExistence(timeout: 10))
        field.typeKey(.escape, modifierFlags: [])
        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.downArrow, modifierFlags: [])
        capture("Normal Search selected result Dark narrow")
        field.buttons["cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == "" })
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteList"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 5))
        capture("Normal Search cleared to Library Dark narrow")
        XCTAssertEqual(try searchManagementNoteBytes(), originalNotes)
    }

    /// Keeps bilingual Search content and its native actions readable at both densities.
    @MainActor
    func testSearchPresentationFitsCompactAndAdvancedLayouts() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_INCREASE_CONTRAST"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_TRANSPARENCY"] = "1"
        app.launch()
        waitForCurrentDocumentSurface()
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let originalNotes = try searchManagementNoteBytes()

        func capture(_ element: XCUIElement, named name: String) {
            let attachment = XCTAttachment(screenshot: element.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("This Vault", in: app)
        typeCommittedText("syn", into: field, in: app)
        let completion = advanced.buttons["synthetic, Search term"].firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 20))
        field.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(completion.isSelected)
        capture(advanced, named: "Search proportional suggestions Light")
        completion.click()
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == "synthetic" })

        typeCommittedText("synthetic 编辑", into: field, in: app)
        let result = searchResult(named: "QA Autosave A", in: advanced)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        capture(advanced, named: "Search bilingual excerpts Light")
        typeCommittedText(#"title:"QA Autosave A""#, into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        capture(advanced, named: "Search title match Light")

        advanced.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !advanced.exists })
        let compactField = workspace.searchFields["scholium.searchField"]
        typeCommittedText("synthetic 编辑", into: compactField, in: app)
        XCTAssertTrue(searchResult(named: "QA Autosave A", in: workspace).waitForExistence(timeout: 10))
        capture(workspace, named: "Search compact bilingual results Light")

        focusWorkspaceWindow(workspace)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        resizeProofWindow(advanced, toWidth: 600, height: 412)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(advanced.frame.contains(result.frame))
        capture(advanced, named: "Search bilingual excerpts Dark minimum width")

        let manager = openSearchTermGroupManager(in: advanced)
        manager.buttons["New Group"].click()
        typeCommittedText("Bilingual alternatives 双语词群", into: manager.textFields["Group Name"], in: app)
        typeCommittedText("synthetic\n编辑", into: manager.textViews["Terms, one per line"], in: app)
        assertSearchManagerLayout(manager, in: advanced, name: "Search proportional term editor Dark minimum width")
        manager.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        XCTAssertEqual(field.value as? String, "synthetic 编辑")

        typeCommittedText("qa-absent-visual-result", into: field, in: app)
        XCTAssertTrue(advanced.staticTexts["No Search Results"].waitForExistence(timeout: 10))
        capture(advanced, named: "Search empty results Dark minimum width")
        typeCommittedText("synthetic 编辑", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(try searchManagementNoteBytes(), originalNotes)
    }

    /// One native management journey owns the distinction between reusable input
    /// groups, the visible query, and persisted Saved Search definitions.
    @MainActor
    func testSavedSearchAndTermGroupManagementPreservesExplicitQueries() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launch()
        waitForCurrentDocumentSurface()
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let originalNotes = try searchManagementNoteBytes()
        let storage = homeDirectory.appendingPathComponent("ApplicationSupport/Workspace")
        let groupFile = storage.appendingPathComponent("search-term-groups.json")
        let savedFile = storage.appendingPathComponent("saved-searches.json")
        let groupName = "QA Alternatives 词群"
        let revisedGroupName = "QA Revised Alternatives 词群"
        let savedName = "QA Saved Alternatives"
        let renamedSavedName = "QA Renamed Alternatives"
        let terms = "晨光样本\naurora-fixture"
        let insertedQuery = #"("晨光样本" OR "aurora-fixture")"#
        let query = #"title:"QA Topic" AND ("晨光样本" OR "aurora-fixture") AND NOT "qa-absent-management""#

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("Triptych", in: app)
        typeCommittedText("", into: field, in: app)

        resizeProofWindow(advanced, toWidth: 600, height: 412)
        var manager = openSearchTermGroupManager(in: advanced)
        assertSearchManagerLayout(manager, in: advanced, name: "Term Groups Light at minimum size")
        manager.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        focusWorkspaceWindow(workspace)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: 5) { field.isHittable }, "Advanced Search must return to the foreground.")
        manager = openSearchTermGroupManager(in: advanced)
        assertSearchManagerLayout(manager, in: advanced, name: "Term Groups Dark at minimum size")
        XCTAssertFalse(manager.buttons["Save"].isEnabled, "An empty group must not be committed.")
        XCTAssertFalse(manager.buttons["Delete Group"].isEnabled)
        manager.buttons["New Group"].click()
        let nameField = manager.textFields["Group Name"]
        let termEditor = manager.textViews["Terms, one per line"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(termEditor.waitForExistence(timeout: 5))
        typeCommittedText(groupName, into: nameField, in: app)
        typeCommittedText(terms, into: termEditor, in: app)
        assertSearchManagerLayout(manager, in: advanced, name: "Term Groups bilingual draft at minimum size")
        XCTAssertTrue(manager.buttons["Save"].isEnabled)
        XCTAssertFalse(manager.buttons["New Group"].isEnabled, "An unsaved group cannot be silently discarded.")
        manager.buttons["Save"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.searchManagementRecords(at: groupFile, collectionKey: "groups")?.first?["terms"] as? [String]
                    == ["晨光样本", "aurora-fixture"]
            })

        let insertionMenu = openSearchManagementMenu("Insert Term Group", in: advanced)
        let insert = insertionMenu.menuItems[groupName].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 5))
        insert.click()
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == insertedQuery })
        typeCommittedText(query, into: field, in: app)
        XCTAssertTrue(searchResult(named: "QA Topic", in: advanced).waitForExistence(timeout: 20))

        let explain = advanced.buttons["Explain Query"]
        XCTAssertTrue(waitUntil(timeout: 5) { explain.isEnabled })
        explain.click()
        let explanation = advanced.popovers.containing(.scrollView, identifier: "scholium.searchExplanation").firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        let expressionText = explanation.scrollViews["scholium.searchExplanation"].staticTexts.firstMatch
        XCTAssertTrue(expressionText.waitForExistence(timeout: 5))
        let expectedExpression =
            "(title contains ‘qa topic’ AND (text contains ‘晨光样本’ OR text contains ‘aurora-fixture’) AND NOT (text contains ‘qa-absent-management’))"
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.accessibilityText(of: expressionText) == "Triptych\n" + expectedExpression
            }, "Explain Query must retain the actual conjunction, alternatives and negation nesting.")
        let explanationAttachment = XCTAttachment(screenshot: explanation.screenshot())
        explanationAttachment.name = "Search explicit term alternatives and nested explanation"
        explanationAttachment.lifetime = .keepAlways
        add(explanationAttachment)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !explanation.exists })
        XCTAssertTrue(advanced.exists, "Dismissing the query explanation must keep Advanced Search open.")
        XCTAssertEqual(field.value as? String, query)
        XCTAssertTrue(waitUntil(timeout: 5) { field.isHittable })
        XCTAssertTrue(waitUntil(timeout: 5) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: field) })

        let savedSearchesMenu = openSearchManagementMenu("Saved Searches", in: advanced)
        savedSearchesMenu.menuItems["Save Current Search…"].click()
        let saveSheet = advanced.sheets.firstMatch
        XCTAssertTrue(saveSheet.waitForExistence(timeout: 5))
        typeCommittedText(savedName, into: saveSheet.textFields.firstMatch, in: app)
        saveSheet.buttons["Save"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !saveSheet.exists })
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.searchManagementRecords(at: savedFile)?.first?["name"] as? String == savedName
            })
        let savedRecords = try XCTUnwrap(searchManagementRecords(at: savedFile))
        XCTAssertEqual(savedRecords.count, 1)
        let savedID = try XCTUnwrap(savedRecords.first?["id"] as? String)
        let definition = try XCTUnwrap(savedRecords.first?["definition"] as? [String: Any])
        XCTAssertEqual(definition["query"] as? String, query)
        XCTAssertEqual(definition["presentationScope"] as? String, "triptych")
        XCTAssertEqual(Set(definition.keys), ["contractVersion", "query", "presentationScope"])
        let originalSavedBytes = try Data(contentsOf: savedFile)
        let originalGroupBytes = try Data(contentsOf: groupFile)

        manager = openSearchTermGroupManager(in: advanced)
        manager.staticTexts[groupName].click()
        let selectedName = manager.textFields["Group Name"]
        XCTAssertTrue(waitUntil(timeout: 5) { selectedName.value as? String == groupName })
        typeCommittedText("QA Cancelled Draft", into: selectedName, in: app)
        XCTAssertFalse(manager.buttons["New Group"].isEnabled)
        XCTAssertFalse(manager.buttons["Delete Group"].isEnabled)
        manager.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        XCTAssertEqual(try Data(contentsOf: groupFile), originalGroupBytes)
        XCTAssertEqual(try Data(contentsOf: savedFile), originalSavedBytes)
        XCTAssertEqual(field.value as? String, query)

        manager = openSearchTermGroupManager(in: advanced)
        manager.staticTexts[groupName].click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                manager.textFields["Group Name"].value as? String == groupName
            })
        typeCommittedText(revisedGroupName, into: manager.textFields["Group Name"], in: app)
        typeCommittedText("replacement literal", into: manager.textViews["Terms, one per line"], in: app)
        manager.buttons["Save"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.searchManagementRecords(at: groupFile, collectionKey: "groups")?.first?["name"] as? String
                    == revisedGroupName
            })
        XCTAssertEqual(field.value as? String, query, "Editing a group must not rewrite the visible query.")
        XCTAssertEqual(try Data(contentsOf: savedFile), originalSavedBytes)

        manager = openSearchTermGroupManager(in: advanced)
        manager.staticTexts[revisedGroupName].click()
        XCTAssertTrue(waitUntil(timeout: 5) { manager.buttons["Delete Group"].isEnabled })
        manager.buttons["Delete Group"].click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.searchManagementRecords(at: groupFile, collectionKey: "groups")?.isEmpty == true
            })
        XCTAssertFalse(manager.staticTexts[revisedGroupName].exists)
        XCTAssertFalse(manager.buttons["Delete Group"].isEnabled)
        manager.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !manager.exists })
        XCTAssertEqual(field.value as? String, query)
        XCTAssertEqual(try Data(contentsOf: savedFile), originalSavedBytes)
        let remainingGroupsMenu = openSearchManagementMenu("Insert Term Group", in: advanced)
        XCTAssertFalse(remainingGroupsMenu.menuItems[revisedGroupName].exists)
        app.typeKey(.escape, modifierFlags: [])

        performSavedSearchAction("Rename…", named: savedName, in: advanced)
        let renameSheet = advanced.sheets.firstMatch
        XCTAssertTrue(renameSheet.waitForExistence(timeout: 5))
        typeCommittedText(renamedSavedName, into: renameSheet.textFields.firstMatch, in: app)
        renameSheet.buttons["Rename"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !renameSheet.exists })
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.searchManagementRecords(at: savedFile)?.first?["name"] as? String == renamedSavedName
            })
        let renamedRecord = try XCTUnwrap(searchManagementRecords(at: savedFile)?.first)
        XCTAssertEqual(renamedRecord["id"] as? String, savedID)
        XCTAssertEqual(renamedRecord["definition"] as? NSDictionary, definition as NSDictionary)

        selectResearchSearchScope("This Vault", in: app)
        typeCommittedText("qa-absent-management", into: field, in: app)
        XCTAssertTrue(advanced.staticTexts["No Search Results"].waitForExistence(timeout: 15))
        performSavedSearchAction("Run Search", named: renamedSavedName, in: advanced)
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == query })
        XCTAssertTrue(advanced.staticTexts["Triptych"].exists, "Running a Saved Search restores its explicit scope.")
        XCTAssertTrue(searchResult(named: "QA Topic", in: advanced).waitForExistence(timeout: 20))
        XCTAssertTrue(advanced.exists)

        performSavedSearchAction("Delete", named: renamedSavedName, in: advanced)
        XCTAssertTrue(waitUntil(timeout: 5) { self.searchManagementRecords(at: savedFile)?.isEmpty == true })
        XCTAssertEqual(field.value as? String, query, "Deleting a Saved Search must not rewrite the active query.")
        let remainingSearchesMenu = openSearchManagementMenu("Saved Searches", in: advanced)
        XCTAssertFalse(remainingSearchesMenu.menuItems[renamedSavedName].exists)
        XCTAssertTrue(remainingSearchesMenu.menuItems["Save Current Search…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(try searchManagementNoteBytes(), originalNotes, "Search management must leave every Note byte unchanged.")
    }

    @MainActor
    private func assertSearchManagerLayout(_ manager: XCUIElement, in advanced: XCUIElement, name: String) {
        let nameField = manager.textFields["Group Name"]
        let terms = manager.textViews["Terms, one per line"]
        let hint = manager.staticTexts["1–24 terms; each is inserted as literal text."]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        for control in [nameField, terms, hint, manager.buttons["Cancel"], manager.buttons["Save"], manager.buttons["New Group"]] {
            XCTAssertTrue(control.exists)
            XCTAssertTrue(manager.frame.contains(control.frame), "Every management field and action must fit the actual native sheet.")
        }
        XCTAssertLessThanOrEqual(hint.frame.maxY, manager.buttons["Save"].frame.minY, "The term limit must remain above the fixed footer.")
        XCTAssertGreaterThanOrEqual(advanced.frame.width, manager.frame.width - 2)
        let capture = XCTAttachment(screenshot: manager.screenshot())
        capture.name = name
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor
    private func openSearchManagementMenu(_ title: String, in advanced: XCUIElement) -> XCUIElement {
        let button = advanced.menuButtons[title]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "The named Search management menu is unavailable: \(title)")
        XCTAssertTrue(waitUntil(timeout: 5) { button.isHittable }, "The Search management menu must be in the foreground.")
        button.click()
        let anchor = title == "Saved Searches" ? "Save Current Search…" : "Manage Term Groups…"
        let menu = app.menus.containing(.menuItem, identifier: anchor).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "The native Search popup must contain its management action.")
        return menu
    }

    @MainActor
    private func openSearchTermGroupManager(in advanced: XCUIElement) -> XCUIElement {
        let menu = openSearchManagementMenu("Insert Term Group", in: advanced)
        let action = menu.menuItems["Manage Term Groups…"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.click()
        let manager = advanced.sheets.firstMatch
        XCTAssertTrue(manager.waitForExistence(timeout: 5))
        XCTAssertTrue(manager.buttons["New Group"].waitForExistence(timeout: 5))
        return manager
    }

    @MainActor
    private func performSavedSearchAction(_ action: String, named name: String, in advanced: XCUIElement) {
        let menu = openSearchManagementMenu("Saved Searches", in: advanced)
        let savedSearch = menu.menuItems[name]
        XCTAssertTrue(savedSearch.waitForExistence(timeout: 5))
        savedSearch.hover()
        let item = savedSearch.menuItems[action]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
    }

    private func searchManagementRecords(at url: URL, collectionKey: String? = nil) -> [[String: Any]]? {
        guard let bytes = try? Data(contentsOf: url),
            let document = try? JSONSerialization.jsonObject(with: bytes)
        else { return nil }
        if let collectionKey {
            return (document as? [String: Any])?[collectionKey] as? [[String: Any]]
        }
        return document as? [[String: Any]]
    }

    private func searchManagementNoteBytes() throws -> [String: Data] {
        var notes: [String: Data] = [:]
        for role in ["01-analyses", "02-topics", "03-works"] {
            let root = triptychDirectory.appendingPathComponent(role)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension.lowercased() == "md" {
                notes[url.path] = try Data(contentsOf: url)
            }
        }
        return notes
    }
}
