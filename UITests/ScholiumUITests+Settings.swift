import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// The fresh fixture's Codex connection stays disconnected. Enabling this
    /// machine-local preference must neither replace its model nor initiate a
    /// connection, and disabling it retains the selection for later use.
    @MainActor
    func testWritingContinuationSettingsSearchAndDisconnectedPreferences() throws {
        let window = openSettingsForTransactionTest()
        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("AI continuation", into: search, in: app)

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

    /// Reminder edits remain a draft until their scoped Save, and reload has
    /// an explicit discard boundary. All persistence belongs to the QA Triptych.
    @MainActor
    func testNotificationSettingsSavesAndSafelyReloadsDraft() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("notifications", in: window)
        let duration = window.popUpButtons["scholium.settings.notifications.duration"]
        let save = window.buttons["scholium.settings.notifications.save"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { save.exists && !save.isEnabled })
        let original = try XCTUnwrap(duration.value as? String)
        let changed = original == "3 days" ? "7 days" : "3 days"

        func chooseChangedDuration() {
            duration.click()
            let option = app.menuItems[changed].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 3))
            option.click()
            XCTAssertEqual(duration.value as? String, changed)
            XCTAssertTrue(waitUntil(timeout: 5) { save.isEnabled })
        }

        chooseChangedDuration()
        selectSettingsCategory("workspace", in: window)
        XCTAssertFalse(save.exists, "Inactive reminder controls must leave the accessibility tree")
        selectSettingsCategory("notifications", in: window)
        XCTAssertEqual(duration.value as? String, changed)
        XCTAssertTrue(save.isEnabled, "Navigation must not save the reminder draft")

        window.buttons["Reload Reminder Timing"].click()
        let discard = window.buttons["Discard Draft and Reload"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        window.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !discard.exists })
        XCTAssertEqual(duration.value as? String, changed)
        XCTAssertTrue(save.isEnabled)

        window.buttons["Reload Reminder Timing"].click()
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                duration.value as? String == original && !save.isEnabled
            }, "Confirmed reload must restore the saved reminder timing")

        chooseChangedDuration()
        save.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !save.isEnabled })
        captureSettingsTransaction(window, named: "settings-reminder-saved")

        relaunchSettingsTransactionApplication()
        let reopened = openSettingsForTransactionTest()
        selectSettingsCategory("notifications", in: reopened)
        let persisted = reopened.popUpButtons["scholium.settings.notifications.duration"]
        XCTAssertTrue(persisted.waitForExistence(timeout: 5))
        XCTAssertEqual(persisted.value as? String, changed)
        XCTAssertFalse(reopened.buttons["scholium.settings.notifications.save"].isEnabled)
    }

    /// Inline edits remain one unapplied draft through navigation and search.
    /// Return in another page must never commit that hidden draft.
    @MainActor
    func testSelectionActionsSettingsRetainsDraftAcrossNavigation() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("writing", in: window)
        let table = window.outlines["scholium.selectionActions.table"]
        let pageSave = window.buttons["scholium.selectionActions.save"]
        let name = window.textFields["scholium.selectionActions.name"]
        let instruction = window.textViews["scholium.selectionActions.prompt"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
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
        XCTAssertFalse(table.staticTexts["QA"].exists)

        click(window.buttons["Add Action"])
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(window.sheets.count, 0, "Ordinary action editing stays in the page")
        XCTAssertFalse(pageSave.isEnabled)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.selectionActions.validation"].exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(name.exists, "Return must not accept an invalid action")
        scrollUntilHittable(name, in: form)
        typeCommittedText("QA", into: name, in: app)
        XCTAssertFalse(pageSave.isEnabled, "An instruction is required as well as a name")
        click(window.buttons["Cancel Action Changes"])
        XCTAssertFalse(name.exists)
        XCTAssertFalse(table.staticTexts["QA"].exists)
        XCTAssertFalse(pageSave.isEnabled, "Cancelling must restore the saved collection")

        click(window.buttons["Add Action"])
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        scrollUntilHittable(name, in: form)
        typeCommittedText("QA", into: name, in: app)
        scrollUntilHittable(instruction, in: form)
        typeCommittedText("Explain the selected passage without editing it.", into: instruction, in: app)
        XCTAssertTrue(pageSave.isEnabled)

        selectSettingsCategory("shortcuts", in: window)
        XCTAssertFalse(table.exists, "Inactive content must leave the accessibility tree")
        app.typeKey(.return, modifierFlags: [])
        selectSettingsCategory("writing", in: window)
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertEqual(name.value as? String, "QA")
        XCTAssertTrue(pageSave.isEnabled, "Return saved a hidden writing draft")

        selectSettingsCategory("notifications", in: window)
        XCTAssertFalse(table.exists)
        app.typeKey(.return, modifierFlags: [])
        selectSettingsCategory("writing", in: window)
        XCTAssertEqual(name.value as? String, "QA")
        XCTAssertTrue(pageSave.isEnabled)

        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("shortcut", into: search, in: app)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.hotkeys"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(table.exists)
        search.buttons["cancel"].click()
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Clearing search must restore the editing page")
        XCTAssertEqual(name.value as? String, "QA")
        XCTAssertTrue(pageSave.isEnabled)
        captureSettingsTransaction(window, named: "settings-selection-actions-retained-draft")

        click(pageSave)
        XCTAssertTrue(waitUntil(timeout: 3) { !pageSave.isEnabled })
        XCTAssertFalse(name.exists)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 3) { !window.exists })
        let restored = openSettingsForTransactionTest()
        XCTAssertEqual(restored.title, "Writing Assistance", "Reopening must restore the selected category")
        XCTAssertTrue(restored.outlines["scholium.selectionActions.table"].waitForExistence(timeout: 5))

        relaunchSettingsTransactionApplication()
        let reopened = openSettingsForTransactionTest()
        selectSettingsCategory("writing", in: reopened)
        XCTAssertTrue(reopened.outlines["scholium.selectionActions.table"].staticTexts["QA"].waitForExistence(timeout: 5))
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
        selectSettingsCategory("notifications", in: window)
        XCTAssertTrue(window.popUpButtons["scholium.settings.notifications.duration"].waitForExistence(timeout: 5))
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
        let reload = window.buttons["scholium.settings.appearance.reload"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        reload.click()
        let repair = window.buttons["Repair Saved Profile"]
        XCTAssertTrue(repair.waitForExistence(timeout: 5))
        XCTAssertTrue(repair.isEnabled)
        typeCommittedText("body font size", into: search, in: app)
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

    /// An invalid field has an effective default, but still needs an explicit
    /// save even when the researcher accepts that value without editing it.
    @MainActor
    func testInvalidReminderTimingSupportsDefaultFieldRepair() throws {
        let settings = triptychDirectory.appendingPathComponent(".scholium/settings.json")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        let expectedDefault = try XCTUnwrap(envelope["attentionDismissalDays"] as? Int)
        envelope["attentionDismissalDays"] = "unavailable-value"
        envelope["retainedFuturePreference"] = "kept"
        try JSONSerialization.data(withJSONObject: envelope).write(to: settings, options: .atomic)
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalNote = try Data(contentsOf: note)
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("notifications", in: window)
        let save = window.buttons["scholium.settings.notifications.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { save.isEnabled })
        save.click()
        XCTAssertTrue(waitUntil(timeout: 10) { !save.isEnabled })
        let repaired = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual(repaired["attentionDismissalDays"] as? Int, expectedDefault)
        XCTAssertEqual(repaired["retainedFuturePreference"] as? String, "kept")
        XCTAssertEqual(try Data(contentsOf: note), originalNote)
        captureSettingsTransaction(window, named: "settings-reminder-field-repaired")
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
    private func selectSettingsCategory(_ key: String, in window: XCUIElement) {
        let category = window.descendants(matching: .any)["scholium.settings.category.\(key)"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        category.click()
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
