import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// One offline journey proves the fresh preference, retained history and
    /// native draft, repeated hiding, and both durable values across relaunch.
    @MainActor
    func testChatSidebarPreferenceStartsOffAndPreservesDraftThroughRelaunch() throws {
        try prepareAbsentQAPreferences(["scholium.chat.sidebarEnabled"])
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        waitForCurrentDocumentSurface()
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try Data(contentsOf: note)
        XCTAssertFalse(sidebarModeControl("Chat").exists)
        app.terminate()
        let fixture = try seedChatEntryFixture()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launch()
        waitForCurrentDocumentSurface()

        func openVisibilitySettings() -> (XCUIElement, XCUIElement) {
            let window = openSettingsForTransactionTest()
            let search = window.searchFields["scholium.settings.search"]
            typeCommittedText("Chat", into: search, in: app)
            selectSettingsSearchResult("agents.chatSidebar", in: window)
            let toggle = window.checkBoxes["scholium.settings.chatSidebarEnabled"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            return (window, toggle)
        }
        func closeSettings(_ window: XCUIElement) {
            app.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(waitUntil(timeout: 3) { !window.exists })
        }
        let (firstSettings, firstToggle) = openVisibilitySettings()
        XCTAssertFalse(selectionControlIsSelected(firstToggle))
        firstToggle.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.selectionControlIsSelected(firstToggle) })
        closeSettings(firstSettings)
        XCTAssertTrue(sidebarModeControl("Chat").waitForExistence(timeout: 5))
        selectDocumentMode("Edit")
        sidebarModeControl("Chat").click()
        chatDeletionRow(fixture.short.id).click()
        let composer = app.textViews["scholium.chat.message"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, fixture.short.draft)
        let draft = "Retained unsent input — 保留中文、English 与选择。"
        typeCommittedText(draft, into: composer, in: app, clickWithinVisibleFrame: true)

        for iteration in 0..<3 {
            let (settings, toggle) = openVisibilitySettings()
            XCTAssertTrue(selectionControlIsSelected(toggle))
            toggle.click()
            if iteration == 0 {
                resizeProofWindow(settings, toWidth: 780, height: 640)
                let search = settings.searchFields["scholium.settings.search"]
                typeCommittedText("connection", into: search, in: app)
                app.typeKey(.escape, modifierFlags: [])
                let form = settingsContentScrollView(in: settings)
                form.swipeUp(velocity: .slow)
                form.swipeUp(velocity: .slow)
                XCTAssertEqual(search.value as? String, "connection")
            }
            closeSettings(settings)
            XCTAssertTrue(waitUntil(timeout: 5) { !self.sidebarModeControl("Chat").exists && !composer.exists })
            XCTAssertEqual(documentModeState(documentModeControl()), "Edit")
            XCTAssertEqual(try Data(contentsOf: note), original)
            let (reopened, disabled) = openVisibilitySettings()
            XCTAssertFalse(selectionControlIsSelected(disabled))
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    let form = self.settingsContentScrollView(in: reopened)
                    return disabled.isHittable && disabled.frame.intersection(form.frame).height >= disabled.frame.height - 1
                }, "Settings search must reveal the checkbox after retained search and scrolling")
            XCTAssertEqual(reopened.searchFields["scholium.settings.search"].value as? String, "Chat")
            if iteration == 2 {
                resizeProofWindow(reopened, toWidth: 780, height: 640)
                XCTAssertTrue(disabled.isHittable)
                captureSettingsTransaction(reopened, named: "chat-visibility-off-minimum-width")
            }
            disabled.click()
            closeSettings(reopened)
            sidebarModeControl("Chat").click()
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            XCTAssertEqual(composer.value as? String, draft)
            XCTAssertEqual(documentModeState(documentModeControl()), "Edit")
        }

        let (settings, enabled) = openVisibilitySettings()
        XCTAssertTrue(selectionControlIsSelected(enabled))
        enabled.click()
        closeSettings(settings)
        relaunchSettingsTransactionApplication()
        XCTAssertFalse(sidebarModeControl("Chat").exists, "OFF must survive graceful relaunch")
        let (offSettings, offToggle) = openVisibilitySettings()
        XCTAssertFalse(selectionControlIsSelected(offToggle))
        offToggle.click()
        closeSettings(offSettings)
        relaunchSettingsTransactionApplication()
        XCTAssertTrue(sidebarModeControl("Chat").waitForExistence(timeout: 5), "ON must survive graceful relaunch")
        sidebarModeControl("Chat").click()
        chatDeletionRow(fixture.short.id).click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, draft)
        XCTAssertEqual(try Data(contentsOf: note), original)
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.archive)) as? [String: Any])
        let conversations = try XCTUnwrap(archive["conversations"] as? [[String: Any]])
        XCTAssertEqual(conversations.compactMap { ($0["messages"] as? [Any])?.count }.sorted(), [2, 72])
        captureSettingsTransaction(app.windows.firstMatch, named: "chat-visibility-relaunch-retained-draft")
    }

    /// The fresh fixture's Codex connection stays disconnected. Enabling this
    /// machine-local preference must neither replace its model nor initiate a
    /// connection, and disabling it retains the selection for later use.
    @MainActor
    func testWritingContinuationSettingsSearchAndDisconnectedPreferences() throws {
        try prepareAbsentQAPreferences([
            "scholium.writingContinuation.enabled", "scholium.writingContinuation.model", "scholium.writingContinuation.effort",
        ])
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        waitForCurrentDocumentSurface()
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
        resizeSettingsToMinimumWidth(window)
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

    /// The new cleanup route is discoverable at minimum width, binds a real
    /// managed-copy cohort, cancels without effects and retains its empty state.
    @MainActor
    func testUnusedChatMaterialCleanupInspectionAndCancellation() throws {
        waitForCurrentDocumentSurface()
        let protectedBefore = try storageResearchFixtureBytes()
        app.terminate()
        let chat = try seedChatEntryFixture()
        let materials = chat.archive.deletingLastPathComponent().appendingPathComponent("Materials", isDirectory: true)
        try FileManager.default.createDirectory(at: materials, withIntermediateDirectories: true)
        let orphan = materials.appendingPathComponent(UUID().uuidString + ".txt")
        let bytes = Data("Synthetic unused material — preserve on cancellation.\r\n".utf8)
        try bytes.write(to: orphan)
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launch()
        waitForCurrentDocumentSurface()
        let window = openSettingsForTransactionTest()
        selectSettingsCategory("storage", in: window)
        resizeSettingsToMinimumWidth(window)
        typeCommittedText("unused materials", into: window.searchFields["scholium.settings.search"], in: app)
        selectSettingsSearchResult("storage.chatHistory", in: window)
        let inspect = window.buttons["scholium.settings.storage.trashUnusedChatMaterials"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        XCTAssertTrue(inspect.isHittable)
        inspect.click()
        let commit = window.buttons["Move to Trash"].firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        captureSettingsTransaction(window, named: "unused-chat-material-cleanup-confirmation")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !commit.exists })
        XCTAssertEqual(try Data(contentsOf: orphan), bytes)
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        // Only this journey's unreferenced synthetic file is removed by the
        // fixture owner; no product Trash request has been dispatched.
        try FileManager.default.removeItem(at: orphan)
        inspect.click()
        XCTAssertTrue(window.staticTexts["No unused Chat-material files to move to Trash."].waitForExistence(timeout: 15))
        XCTAssertFalse(commit.exists)
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        captureSettingsTransaction(window, named: "unused-chat-material-cleanup-empty")
        window.buttons[XCUIIdentifierCloseWindow].click()
        app.menuBars.menuBarItems["Research"].click()
        let recovery = app.menuItems["Recovery…"].firstMatch
        XCTAssertTrue(recovery.exists && recovery.isEnabled)
        recovery.click()
        let emptyRecovery = app.sheets.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "No Pending Recovery", "No Pending Recovery")
        ).firstMatch
        XCTAssertTrue(emptyRecovery.waitForExistence(timeout: 10))
        XCTAssertTrue(
            (emptyRecovery.value as? String ?? emptyRecovery.label).contains("No interrupted save candidate or recorded file operation needs inspection."))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !emptyRecovery.exists })
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
    }

    /// One native task covers cancellation, real cache cleanup, deferred index
    /// clearing and explicit rebuilding without modifying the research fixture.
    @MainActor
    func testStorageCleanupAndIndexRebuildPreserveResearch() throws {
        waitForCurrentDocumentSurface()
        let protectedBefore = try storageResearchFixtureBytes()
        let support = homeDirectory.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let unknown = support.appendingPathComponent("unknown-test-owner/protected.bin")
        try FileManager.default.createDirectory(at: unknown.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("Synthetic unknown owner — preserve exact bytes.\r\n".utf8)
        try sentinel.write(to: unknown, options: .atomic)
        XCTAssertTrue(waitUntil(timeout: 30) { (try? self.storageProjectionFiles(in: support).isEmpty) == false })
        let cachedBefore = try storageProjectionFiles(in: support)

        var window = openSettingsForTransactionTest()
        selectSettingsCategory("storage", in: window)
        resizeSettingsToMinimumWidth(window)
        for label in ["Workspace", "Document", "Writing", "Agents", "Shortcuts", "Zotero", "Storage"] {
            XCTAssertTrue(window.toolbars.buttons[label].isHittable)
        }
        let total = window.descendants(matching: .any)["scholium.settings.storage.total"].firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        var search = window.searchFields["scholium.settings.search"]
        func reveal(_ id: String, query: String) {
            typeCommittedText(query, into: search, in: app)
            selectSettingsSearchResult(id, in: window)
        }

        reveal("storage.index", query: "clear index")
        let selectedIndex = window.descendants(matching: .any)["scholium.settings.storage.selectedIndexSize"].firstMatch
        XCTAssertTrue(selectedIndex.waitForExistence(timeout: 5))
        XCTAssertFalse(selectedIndex.staticTexts["Not Measured"].exists)
        let clear = window.buttons["scholium.settings.storage.clearIndex"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.click()
        let confirmClear = window.buttons["Clear Index"].firstMatch
        XCTAssertTrue(confirmClear.waitForExistence(timeout: 5))
        window.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !confirmClear.exists })
        XCTAssertFalse(window.staticTexts["Index cleared. Choose Rebuild Index or reopen the Triptych."].exists)
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        XCTAssertEqual(try Data(contentsOf: unknown), sentinel)

        reveal("storage.cache", query: "clear cache")
        let clearCache = window.buttons["scholium.settings.storage.clearProjectionCache"]
        XCTAssertTrue(clearCache.waitForExistence(timeout: 5))
        clearCache.click()
        let result = window.descendants(matching: .any)["scholium.settings.storage.result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(waitUntil(timeout: 20) { !window.descendants(matching: .any)["scholium.settings.storage.progress"].firstMatch.exists })
        XCTAssertFalse(window.descendants(matching: .any)["scholium.settings.storage.error"].firstMatch.exists)
        let cachedAfter = try storageProjectionFiles(in: support)
        XCTAssertLessThan(cachedAfter.count, cachedBefore.count, "The real indexed fixture must release projection-cache files.")

        reveal("storage.index", query: "clear index")
        clear.click()
        XCTAssertTrue(confirmClear.waitForExistence(timeout: 5))
        confirmClear.click()
        let deferred = window.staticTexts["Index cleared. Choose Rebuild Index or reopen the Triptych."]
        XCTAssertTrue(deferred.waitForExistence(timeout: 25))
        XCTAssertTrue(waitUntil(timeout: 20) { !window.descendants(matching: .any)["scholium.settings.storage.progress"].firstMatch.exists })
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        XCTAssertEqual(try Data(contentsOf: unknown), sentinel)
        captureSettingsTransaction(window, named: "settings-storage-cleared-index-deferred")
        let clearedState = try storageSearchIndexState(in: support)
        XCTAssertEqual(clearedState.documentCount, 0)
        XCTAssertGreaterThan(clearedState.sequence, 0)
        XCTAssertEqual(clearedState.manifestLength, 0)

        // A real Settings refresh must borrow metadata without opening the
        // paused Search owner as a new user workspace activation.
        window.buttons[XCUIIdentifierCloseWindow].click()
        window = openSettingsForTransactionTest()
        search = window.searchFields["scholium.settings.search"]
        selectSettingsCategory("workspace", in: window)
        reveal("workspace.settingsRecovery", query: "portable settings")
        let reload = window.buttons["Reload Portable Settings"]
        XCTAssertTrue(reload.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 10) { reload.isEnabled })
        reload.click()
        XCTAssertTrue(waitUntil(timeout: 20) { reload.isEnabled && window.progressIndicators.count == 0 })
        let afterSettingsRefresh = try storageSearchIndexState(in: support)
        XCTAssertEqual(
            afterSettingsRefresh, clearedState, "Opening Settings and completing its explicit metadata reload must preserve the cleared marker and empty index."
        )
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        XCTAssertEqual(try Data(contentsOf: unknown), sentinel)
        reveal("storage.index", query: "rebuild index")

        let rebuild = window.buttons["scholium.settings.storage.rebuildIndex"]
        XCTAssertTrue(rebuild.isEnabled)
        rebuild.click()
        let confirmRebuild = window.buttons["Rebuild Index"].firstMatch
        XCTAssertTrue(confirmRebuild.waitForExistence(timeout: 5))
        confirmRebuild.click()
        XCTAssertTrue(window.staticTexts["Index rebuild completed."].waitForExistence(timeout: 45))
        XCTAssertTrue(waitUntil(timeout: 20) { !window.descendants(matching: .any)["scholium.settings.storage.progress"].firstMatch.exists })
        XCTAssertFalse(window.descendants(matching: .any)["scholium.settings.storage.error"].firstMatch.exists)
        selectSettingsCategory("workspace", in: window)
        selectSettingsCategory("storage", in: window)
        XCTAssertTrue(window.staticTexts["Index rebuild completed."].exists, "The retained page keeps its completed result.")
        captureSettingsTransaction(window, named: "settings-storage-rebuilt-index")
        window.buttons[XCUIIdentifierCloseWindow].click()

        let query = app.searchFields["scholium.searchField"].firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        selectResearchSearchScope("Triptych", in: app)
        typeCommittedText("title:\"QA Topic\"", into: query, in: app)
        XCTAssertTrue(searchResult(named: "QA Topic").waitForExistence(timeout: 15))
        XCTAssertEqual(try storageResearchFixtureBytes(), protectedBefore)
        XCTAssertEqual(try Data(contentsOf: unknown), sentinel)
    }

    private struct StorageSearchIndexState: Equatable {
        let documentCount: Int
        let sequence: Int
        let manifestLength: Int
    }

    /// Read-only SQLite observation is limited to this journey's isolated QA
    /// database; no product reset helper or cached completion message is proof.
    @MainActor
    private func storageSearchIndexState(in support: URL) throws -> StorageSearchIndexState {
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent(".scholium/manifest.json"))) as? [String: Any])
        let id = try XCTUnwrap((manifest["id"] as? String).flatMap(UUID.init(uuidString:)))
        let database = support.appendingPathComponent("Triptychs/\(id.uuidString.lowercased())/indexes/search-v10.sqlite")
        XCTAssertTrue(database.standardizedFileURL.path.hasPrefix(homeDirectory.standardizedFileURL.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path))
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly", "-batch", "-noheader", "-cmd", ".timeout 3000", database.path,
            "SELECT (SELECT count(*) FROM search_documents), sequence, length(source_manifest_hash) FROM search_index_state WHERE singleton = 1;",
        ]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, diagnostic)
        let fields = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|")
        XCTAssertEqual(fields.count, 3)
        return try StorageSearchIndexState(
            documentCount: XCTUnwrap(fields.first.flatMap { Int($0) }),
            sequence: XCTUnwrap(fields.dropFirst().first.flatMap { Int($0) }),
            manifestLength: XCTUnwrap(fields.dropFirst(2).first.flatMap { Int($0) }))
    }

    @MainActor
    private func storageProjectionFiles(in support: URL) throws -> Set<URL> {
        let root = support.appendingPathComponent("Vaults", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: Set<URL> = []
        for case let url as URL in enumerator {
            if url.lastPathComponent.hasSuffix(".catalog.plist") || url.lastPathComponent.hasSuffix(".projection.plist") {
                files.insert(url)
            }
        }
        return files
    }

    @MainActor
    private func storageResearchFixtureBytes() throws -> [URL: Data] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: triptychDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
        var bytes: [URL: Data] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension == "md" || url.path.contains("/.scholium/") else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            bytes[url] = try Data(contentsOf: url)
        }
        XCTAssertFalse(bytes.isEmpty)
        return bytes
    }

    @MainActor
    func settingsContentScrollView(in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["scholium.settings.pages"].firstMatch.scrollViews.firstMatch
    }

    @MainActor
    func openSettingsForTransactionTest() -> XCUIElement {
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
            "storage": ["Storage", "存储"],
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
