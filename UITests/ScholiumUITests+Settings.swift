import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
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

    /// The retained nested page may keep its draft, but hidden default actions
    /// must never commit it through either level of Settings navigation.
    @MainActor
    func testSelectionActionsSettingsRetainsDraftAcrossNestedNavigation() throws {
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("interaction", in: window)
        selectInteractionCategory("Selection Actions", in: window)
        let table = window.outlines["scholium.selectionActions.table"]
        let pageSave = window.buttons["Save"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        XCTAssertFalse(pageSave.isEnabled)
        // Machine-local QA preferences can survive a failed earlier run even
        // though this journey has a fresh Triptych. Establish a saved baseline
        // through the same scoped UI before testing cancellation and persistence.
        window.buttons["Restore Defaults"].click()
        pageSave.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !pageSave.isEnabled })
        XCTAssertFalse(table.staticTexts["QA"].exists)

        window.buttons["Add Action"].click()
        let sheet = window.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertFalse(sheet.buttons["Save"].isEnabled)
        XCTAssertTrue(sheet.descendants(matching: .any)["scholium.selectionActions.editor.validation"].exists)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sheet.exists, "Return must not accept an invalid action")
        typeCommittedText("QA", into: sheet.textFields["scholium.selectionActions.name"], in: app)
        XCTAssertFalse(sheet.buttons["Save"].isEnabled, "An instruction is required as well as a name")
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })
        XCTAssertFalse(table.staticTexts["QA"].exists)
        XCTAssertFalse(pageSave.isEnabled, "Cancelling an editor must not change the page draft")

        window.buttons["Add Action"].click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        typeCommittedText("QA", into: sheet.textFields["scholium.selectionActions.name"], in: app)
        typeCommittedText(
            "Explain the selected passage without editing it.",
            into: sheet.textViews["scholium.selectionActions.prompt"],
            in: app
        )
        XCTAssertTrue(sheet.buttons["Save"].isEnabled)
        sheet.buttons["Save"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })
        XCTAssertTrue(table.staticTexts["QA"].waitForExistence(timeout: 3))
        XCTAssertTrue(pageSave.isEnabled, "Saving the child editor must leave an unapplied page draft")

        selectInteractionCategory("Keyboard Shortcuts", in: window)
        XCTAssertFalse(table.exists, "Inactive nested content must leave the accessibility tree")
        app.typeKey(.return, modifierFlags: [])
        selectInteractionCategory("Selection Actions", in: window)
        XCTAssertTrue(table.staticTexts["QA"].waitForExistence(timeout: 3))
        XCTAssertTrue(pageSave.isEnabled, "Return saved a hidden child-page draft")

        selectSettingsCategory("notifications", in: window)
        XCTAssertFalse(table.exists)
        app.typeKey(.return, modifierFlags: [])
        selectSettingsCategory("interaction", in: window)
        XCTAssertTrue(table.waitForExistence(timeout: 3), "Returning must restore the selected child page")
        XCTAssertTrue(table.staticTexts["QA"].exists)
        XCTAssertTrue(pageSave.isEnabled, "Return saved a draft beneath an inactive root page")

        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("shortcut", into: search, in: app)
        XCTAssertTrue(window.descendants(matching: .any)["scholium.hotkeys"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(table.exists, "A matching search must reveal the child editing location")
        search.buttons["cancel"].click()
        XCTAssertTrue(table.waitForExistence(timeout: 5), "Clearing search must restore the prior child page")
        XCTAssertTrue(table.staticTexts["QA"].exists)
        XCTAssertTrue(pageSave.isEnabled, "Search navigation must retain the unsaved action")
        captureSettingsTransaction(window, named: "settings-selection-actions-retained-draft")

        pageSave.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !pageSave.isEnabled })
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 3) { !window.exists })
        let restored = openSettingsForTransactionTest()
        XCTAssertEqual(restored.title, "Interaction", "Reopening must restore the selected root category")
        XCTAssertTrue(restored.outlines["scholium.selectionActions.table"].waitForExistence(timeout: 5))

        relaunchSettingsTransactionApplication()
        let reopened = openSettingsForTransactionTest()
        selectSettingsCategory("interaction", in: reopened)
        selectInteractionCategory("Selection Actions", in: reopened)
        let persisted = reopened.outlines["scholium.selectionActions.table"]
        XCTAssertTrue(persisted.staticTexts["QA"].waitForExistence(timeout: 5))
        XCTAssertFalse(reopened.buttons["Save"].firstMatch.isEnabled)
    }

    @MainActor
    private func openSettingsForTransactionTest() -> XCUIElement {
        app.typeKey(",", modifierFlags: .command)
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
    private func selectInteractionCategory(_ title: String, in window: XCUIElement) {
        let category = window.radioButtons[title]
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
