import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// The fresh fixture's Codex connection stays disconnected. Enabling this
    /// machine-local preference must neither replace its model nor initiate a
    /// connection, and disabling it retains the selection for later use.
    @MainActor
    func testWritingContinuationSettingsSearchAndDisconnectedPreferences() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("workspace", in: window)
        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("AI continuation", into: search, in: app)
        XCTAssertEqual(window.title, "Workspace", "Typing must not select the first search result")
        selectSettingsSearchResult("writing.continuation", in: window)

        let enabled = window.descendants(matching: .any)["scholium.settings.writingContinuation.enabled"].firstMatch
        let model = window.popUpButtons["scholium.settings.writingContinuation.model"]
        let repair = window.staticTexts[
            "Connect and sign in to Codex in Agents & Chat. Your selected model is retained."
        ]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5), "Search must reveal Writing Assistance")
        XCTAssertEqual(window.title, "Writing Assistance")
        XCTAssertFalse(selectionControlIsSelected(enabled), "AI continuation must be opt-in")
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        XCTAssertEqual(model.value as? String, "gpt-5.6-luna")
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(repair.waitForExistence(timeout: 5))

        enabled.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.selectionControlIsSelected(enabled) })
        XCTAssertFalse(model.isEnabled, "A disconnected runtime cannot offer model choices")
        XCTAssertEqual(model.value as? String, "gpt-5.6-luna", "Enabling must not substitute a model")
        XCTAssertTrue(repair.exists, "Offline setup remains explained beside the retained choice")
        captureSettingsTransaction(window, named: "settings-writing-continuation-disconnected")

        enabled.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.selectionControlIsSelected(enabled) })
        XCTAssertEqual(model.value as? String, "gpt-5.6-luna", "Disabling must retain the model")
        XCTAssertFalse(model.isEnabled)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 3) { !window.exists })
    }

    /// Inline edits remain one unapplied draft through navigation and search.
    /// Return in another page must never commit that hidden draft.
    @MainActor
    func testSelectionActionsSettingsRetainsDraftAcrossNavigation() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("writing", in: window)
        let actionRows = window.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.selectionActions.row."))
        let pageSave = window.buttons["scholium.selectionActions.save"]
        let editors = window.descendants(matching: .any).matching(identifier: "scholium.selectionActions.editor")
        let editor = editors.firstMatch
        let name = editor.textFields["scholium.selectionActions.name"]
        let instruction = editor.textViews["scholium.selectionActions.prompt"]
        XCTAssertTrue(actionRows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(pageSave.waitForExistence(timeout: 5))
        let form = settingsContentScrollView(in: window)
        func click(_ button: XCUIElement) {
            scrollUntilHittable(button, in: form)
            button.click()
        }

        // Establish a saved baseline in this disposable machine-preference scope.
        click(window.buttons["Restore Defaults"])
        if pageSave.isEnabled { click(pageSave) }
        XCTAssertTrue(waitUntil(timeout: 3) { !pageSave.isEnabled })
        XCTAssertFalse(actionRows.staticTexts["QA"].exists)

        click(window.buttons["Add Action"])
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(window.sheets.count, 0, "Action editing must remain in the settings page")
        XCTAssertTrue(editor.exists)
        XCTAssertEqual(editors.count, 1, "The editor must expose one container without overwriting its fields' identifiers")
        XCTAssertTrue(window.staticTexts["Edit Selection Action"].exists)
        XCTAssertFalse(pageSave.isEnabled)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.selectionActions.validation"].exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(name.exists, "Return must not accept an invalid action")
        typeCommittedText("QA", into: name, in: app)
        XCTAssertFalse(pageSave.isEnabled, "An instruction is required as well as a name")
        click(editor.buttons["Cancel"])
        XCTAssertFalse(name.exists)
        XCTAssertFalse(actionRows.staticTexts["QA"].exists)
        XCTAssertFalse(pageSave.isEnabled, "Cancelling must restore the saved collection")

        click(window.buttons["Add Action"])
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        typeCommittedText("QA", into: name, in: app)
        scrollUntilHittable(instruction, in: form)
        typeCommittedText("Explain the selected passage without editing it.", into: instruction, in: app)
        XCTAssertEqual(name.value as? String, "QA", "The inline editor must identify the action being edited")
        XCTAssertFalse(pageSave.isEnabled, "A valid unfinished edit must not be committed by the page's Save")
        selectSettingsCategory("shortcuts", in: window)
        XCTAssertFalse(editor.exists, "An inactive inline editor must leave the accessibility tree")
        app.typeKey(.return, modifierFlags: [])
        selectSettingsCategory("writing", in: window)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "QA")
        XCTAssertEqual(instruction.value as? String, "Explain the selected passage without editing it.")
        XCTAssertFalse(pageSave.isEnabled, "Navigation must retain the unfinished edit")
        click(editor.buttons["scholium.selectionActions.done"])
        XCTAssertFalse(name.exists)
        XCTAssertTrue(pageSave.isEnabled)

        selectSettingsCategory("shortcuts", in: window)
        XCTAssertFalse(actionRows.firstMatch.exists, "Inactive content must leave the accessibility tree")
        app.typeKey(.return, modifierFlags: [])
        selectSettingsCategory("writing", in: window)
        XCTAssertTrue(actionRows.staticTexts["QA"].waitForExistence(timeout: 3))
        XCTAssertTrue(pageSave.isEnabled, "Return saved a hidden writing draft")

        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("shortcut", into: search, in: app)
        XCTAssertTrue(actionRows.staticTexts["QA"].exists, "Typing a query must retain the current draft page")
        selectSettingsSearchResult("shortcut.searchResearch", in: window)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.hotkeys"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(actionRows.firstMatch.exists)
        search.buttons["cancel"].click()
        XCTAssertTrue(actionRows.staticTexts["QA"].waitForExistence(timeout: 5), "Clearing search must restore the draft page")
        XCTAssertTrue(pageSave.isEnabled)
        captureSettingsTransaction(window, named: "settings-selection-actions-retained-draft")

        click(pageSave)
        XCTAssertTrue(waitUntil(timeout: 3) { !pageSave.isEnabled })
        XCTAssertFalse(name.exists)
        let rightEdge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -1, dy: 0))
        rightEdge.click(forDuration: 0.15, thenDragTo: rightEdge.withOffset(CGVector(dx: 780 - window.frame.width, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { abs(window.frame.width - 780) < 2 })
        let savedActionEdit = actionRows.allElementsBoundByIndex.last!.buttons["scholium.selectionActions.edit"]
        scrollUntilHittable(savedActionEdit, in: form)
        captureSettingsTransaction(window, named: "settings-selection-actions-minimum-width")
        click(savedActionEdit)
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "QA")
        XCTAssertEqual(window.sheets.count, 0)
        scrollUntilHittable(editor.buttons["Cancel"], in: form)
        XCTAssertGreaterThanOrEqual(editor.frame.minX, form.frame.minX - 1)
        XCTAssertLessThanOrEqual(editor.frame.maxX, form.frame.maxX + 1, "The inline editor must fit the resized settings form")
        let editorAttachment = XCTAttachment(screenshot: window.screenshot())
        editorAttachment.name = "settings-selection-action-editor-minimum-width"
        editorAttachment.lifetime = .keepAlways
        add(editorAttachment)
        click(editor.buttons["Cancel"])
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 3) { !window.exists })
        let restored = openSettingsForTransactionTest()
        XCTAssertEqual(restored.title, "Writing Assistance", "Reopening must restore the selected category")
        XCTAssertTrue(
            restored.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium.selectionActions.row.")
            ).firstMatch.waitForExistence(timeout: 5))

        relaunchSettingsTransactionApplication()
        let reopened = openSettingsForTransactionTest()
        selectSettingsCategory("writing", in: reopened)
        XCTAssertTrue(reopened.staticTexts["QA"].waitForExistence(timeout: 5))
        XCTAssertFalse(reopened.buttons["scholium.selectionActions.save"].isEnabled)
    }

    /// An opaque configuration cannot prevent Settings opening or unrelated
    /// preferences working. Recovery is explicit and preserves exact bad bytes.
    @MainActor
    func testDamagedPortableSettingsRecoverWithoutLosingResearch() throws {
        app.terminate()
        let control = triptychDirectory.appendingPathComponent(".scholium", isDirectory: true)
        let settings = control.appendingPathComponent("settings.json")
        let damaged = Data("{broken settings".utf8)
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalNote = try Data(contentsOf: note)
        try damaged.write(to: settings, options: .atomic)
        relaunchSettingsTransactionApplication()
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("writing", in: window)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.settings.writingContinuation.enabled"].firstMatch.waitForExistence(timeout: 5))
        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("damaged settings", into: search, in: app)
        selectSettingsSearchResult("workspace.settingsRecovery", in: window)
        let restore = window.buttons["scholium.settings.portable.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.click()
        let confirm = window.buttons["Restore Portable Settings Defaults"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        window.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !confirm.exists })
        XCTAssertEqual(try Data(contentsOf: settings), damaged)
        restore.click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        let result = window.staticTexts["scholium.settings.portable.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: settings)) != damaged })
        let copies = try FileManager.default.contentsOfDirectory(at: control, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("settings.recovery-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copies.first)), damaged)
        XCTAssertEqual(try Data(contentsOf: note), originalNote)
        captureSettingsTransaction(window, named: "settings-portable-recovered")
    }

    /// Invalid external reload retains the form and opens a scoped repair
    /// route rather than making document appearance unusable.
    @MainActor
    func testInvalidAppearanceReloadAllowsScopedProfileRepair() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("document", in: window)
        let size = window.textFields["Body font size"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        let styles = homeDirectory.appendingPathComponent("ApplicationSupport/Workspace/Styles", isDirectory: true)
        let url = styles.appendingPathComponent("appearances.json")
        let snippetsURL = styles.appendingPathComponent("snippets.json")
        let snippetsBefore = try? Data(contentsOf: snippetsURL)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var profiles = try XCTUnwrap(manifest["profiles"] as? [[String: Any]])
        var profileSettings = try XCTUnwrap(profiles[0]["settings"] as? [String: Any])
        var body = try XCTUnwrap(profileSettings["body"] as? [String: Any])
        body["alignment"] = "unsupported-value"
        profileSettings["body"] = body
        profiles[0]["settings"] = profileSettings
        manifest["profiles"] = profiles
        let damaged = try JSONSerialization.data(withJSONObject: manifest)
        try damaged.write(to: url, options: .atomic)
        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("configuration file", into: search, in: app)
        selectSettingsSearchResult("appearance.file", in: window)
        let reload = window.buttons["scholium.settings.appearance.reload"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        reload.click()
        let repair = window.buttons["Repair Saved Profile"]
        XCTAssertTrue(repair.waitForExistence(timeout: 5))
        XCTAssertTrue(repair.isEnabled)
        typeCommittedText("body font size", into: search, in: app)
        selectSettingsSearchResult("appearance.bodySize", in: window)
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        XCTAssertTrue(size.isEnabled)
        typeCommittedText("17", into: size, in: app)
        app.typeKey(.tab, modifierFlags: [])
        repair.click()
        XCTAssertTrue(waitUntil(timeout: 10) { !repair.exists })
        let repaired = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let repairedProfiles = try XCTUnwrap(repaired["profiles"] as? [[String: Any]])
        let repairedSettings = try XCTUnwrap(repairedProfiles[0]["settings"] as? [String: Any])
        let repairedBody = try XCTUnwrap(repairedSettings["body"] as? [String: Any])
        XCTAssertEqual(repairedBody["fontSizePoints"] as? Double, 17)
        let backup = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: styles, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("appearances.json.recovery-") })
        XCTAssertEqual(try Data(contentsOf: backup), damaged)
        XCTAssertEqual(try? Data(contentsOf: snippetsURL), snippetsBefore)
        captureSettingsTransaction(window, named: "settings-appearance-repaired")
    }

    @MainActor
    func settingsContentScrollView(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["scholium.settings.pages"].firstMatch.scrollViews.firstMatch
    }

    @MainActor
    private func openSettingsForTransactionTest() -> XCUIElement {
        app.menuBars.menuBarItems["Scholium QA"].click()
        app.menuItems["Settings…"].click()
        let window = app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        return window
    }

    @MainActor
    func selectSettingsCategory(_ key: String, in window: XCUIElement) {
        let nativeLabels: [String: [String]] = [
            "workspace": ["Workspace", "工作区"],
            "document": ["Document", "文稿"],
            "writing": ["Writing", "写作"],
            "agents": ["Agents", "智能体"],
            "shortcuts": ["Shortcuts", "快捷键"],
            "zotero": ["Zotero"],
        ]
        guard let labels = nativeLabels[key] else {
            XCTFail("Unknown settings category: \(key)")
            return
        }
        let matches = window.toolbars.buttons.matching(NSPredicate(format: "label IN %@", labels))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(matches.count, 1, "The native preferences toolbar must have one button for \(key)")
        matches.firstMatch.click()
    }

    @MainActor
    func selectSettingsSearchResult(_ id: String, in window: XCUIElement) {
        let search = window.searchFields["scholium.settings.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let query = search.value as? String
        let result = app.descendants(matching: .any)["scholium.settings.result.\(id)"].firstMatch
        if !result.exists {
            search.click()
        }
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                !self.app.descendants(matching: .any)["scholium.settings.searchResults"].firstMatch.exists
            }, "Choosing a result must close the temporary search presentation")
        XCTAssertEqual(search.value as? String, query, "Choosing a result must preserve the query for another setting")
    }

    @MainActor
    private func relaunchSettingsTransactionApplication() {
        app.terminate()
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 20))
    }

    @MainActor
    private func captureSettingsTransaction(_ window: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
