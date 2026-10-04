import Foundation
@preconcurrency import XCTest

extension ScholiumUITests {
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
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(terms.waitForExistence(timeout: 5))
        for control in [nameField, terms, manager.buttons["Cancel"], manager.buttons["Save"], manager.buttons["New Group"]] {
            XCTAssertTrue(control.exists)
            XCTAssertTrue(manager.frame.contains(control.frame), "Every management field and action must fit the actual native sheet.")
        }
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
