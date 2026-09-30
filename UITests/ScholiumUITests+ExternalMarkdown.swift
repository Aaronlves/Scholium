import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    func testExternalMarkdownLaunchServicesImportAndLifecyclePreserveExactSource() throws {
        let originalMainID = app.windows.firstMatch.identifier
        let firstName = try XCTUnwrap(externalQARegisteredTriptychNames().first)
        let secondRoot = testDirectory.appendingPathComponent("Second Triptych", isDirectory: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        // Clone the three standard fixture roles, never the portable identity
        // or machine registration of the already configured first Triptych.
        for role in ["01-analyses", "02-topics", "03-works"] {
            try FileManager.default.copyItem(
                at: triptychDirectory.appendingPathComponent(role, isDirectory: true),
                to: secondRoot.appendingPathComponent(role, isDirectory: true)
            )
        }
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["New Triptych…"].click()
        let connect = app.buttons["scholium.bootstrap.connectExisting"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.click()
        for (directory, role) in [("01-analyses", "Analyses"), ("02-topics", "Topics"), ("03-works", "Works")] {
            chooseSetupFolder(secondRoot.appendingPathComponent(directory, isDirectory: true), role: role)
        }
        authorizePortableFolder(secondRoot)
        let complete = app.buttons["Connect and Open"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(complete.isEnabled)
        complete.click()
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                self.app.windows.count == 2
                    && !self.app.descendants(matching: .any)["scholium.bootstrap"].exists
                    && (try? self.externalQARegisteredTriptychNames().count) == 2
            }, "The second standard Triptych must finish its native registration before import selection.")
        let secondName = try XCTUnwrap(externalQARegisteredTriptychNames().first { $0 != firstName })
        let secondMainID = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first {
                $0.identifier.hasPrefix("scholium-main-") && $0.identifier != originalMainID
            }
        ).identifier
        let secondMain = app.windows[secondMainID]

        let filename = "QA External Markdown.md"
        let externalURL = testDirectory.appendingPathComponent(filename)
        let originalBytes = Data(
            "\u{FEFF}---\r\nsummary: 'Synthetic external Markdown' # retained comment\r\n---\r\n\r\n# Outside Triptych\r\n\r\nOriginal external passage.\r\n"
                .utf8)
        try originalBytes.write(to: externalURL)
        try externalQALaunchServicesOpen(externalURL)
        let external = externalQAWindow(filename)
        XCTAssertTrue(external.waitForExistence(timeout: 15))
        let mode = external.descendants(matching: .any)["scholium.externalMarkdown.mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.value as? String, "Review", "An external opening must begin in Review.")
        XCTAssertFalse(external.textViews["Markdown source editor"].exists)
        XCTAssertEqual(try Data(contentsOf: externalURL), originalBytes)
        resizeProofWindow(external, toWidth: 420, height: 420)
        let narrowShot = XCTAttachment(screenshot: external.screenshot())
        narrowShot.name = "External Markdown — minimum document window"
        narrowShot.lifetime = .keepAlways
        add(narrowShot)
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(
            app.menuItems["Import to Triptych…"].isEnabled,
            "Import must retain its menu route when the native toolbar is narrow.")
        app.typeKey(.escape, modifierFlags: [])
        resizeProofWindow(external, toWidth: 880, height: 700)
        try externalQALaunchServicesOpen(externalURL)
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 3 })
        XCTAssertEqual(
            app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'scholium-external-markdown-' AND title BEGINSWITH %@", filename)).count, 1,
            "Reopening a file must reveal its one external session.")

        let savedToken = "SAVED-\(UUID().uuidString)"
        let editor = externalQASourceEditor(in: external)
        try externalQAAppend(savedToken, to: editor)
        editor.typeKey("s", modifierFlags: [.command])
        let savedBytes = originalBytes + Data(savedToken.utf8)
        XCTAssertTrue(
            waitUntil(timeout: 10) { (try? Data(contentsOf: externalURL)) == savedBytes },
            "Save must preserve the original BOM, CRLF, YAML and comments outside the inserted range.")

        let importToken = "-IMPORT-\(UUID().uuidString)"
        try externalQAAppend(importToken, to: editor)
        let importButton = external.buttons["scholium.externalMarkdown.import"]
        XCTAssertTrue(waitUntil(timeout: 8) { importButton.isEnabled })
        importButton.click()
        let triptychPicker = app.popUpButtons["scholium.externalMarkdown.import.triptych"].firstMatch
        let workspacePicker = app.popUpButtons["scholium.externalMarkdown.import.workspace"].firstMatch
        XCTAssertTrue(triptychPicker.waitForExistence(timeout: 10))
        triptychPicker.click()
        XCTAssertTrue(app.menuItems[firstName].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems[secondName].exists, "Both registered Triptychs must be available in the same import sheet.")
        app.menuItems[firstName].click()
        workspacePicker.click()
        app.menuItems["Works"].click()
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !triptychPicker.exists })
        XCTAssertFalse(FileManager.default.fileExists(atPath: triptychDirectory.appendingPathComponent("03-works/\(filename)").path))
        XCTAssertEqual(try Data(contentsOf: externalURL), savedBytes)
        XCTAssertTrue((editor.value as? String ?? "").contains(importToken), "Cancel must retain unsaved external input.")

        XCTAssertTrue(waitUntil(timeout: 8) { importButton.isEnabled })
        importButton.click()
        XCTAssertTrue(triptychPicker.waitForExistence(timeout: 10))
        triptychPicker.click()
        app.menuItems[secondName].click()
        workspacePicker.click()
        app.menuItems["Topics"].click()
        let importShot = XCTAttachment(screenshot: external.screenshot())
        importShot.name = "External Markdown — selected Triptych and Topics"
        importShot.lifetime = .keepAlways
        add(importShot)
        let confirm = app.buttons["scholium.externalMarkdown.import.confirm"].firstMatch
        XCTAssertTrue(confirm.isEnabled)
        confirm.click()
        let importedURL = secondRoot.appendingPathComponent("02-topics/\(filename)")
        let importedBytes = savedBytes + Data(importToken.utf8)
        XCTAssertTrue(
            waitUntil(timeout: 20) { (try? Data(contentsOf: importedURL)) == importedBytes },
            "Import must copy the exact current buffer into the selected role of the selected Triptych.")
        let importedWindowTitle = "QA External Markdown – \(secondName)"
        XCTAssertTrue(waitForDocumentTitle(importedWindowTitle, in: secondMain, timeout: 20))
        XCTAssertTrue(external.exists, "Import must retain the original external session.")
        XCTAssertEqual(try Data(contentsOf: externalURL), savedBytes, "Import must not save the original file.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: triptychDirectory.appendingPathComponent("02-topics/\(filename)").path))
        try externalQALaunchServicesOpen(importedURL)
        XCTAssertTrue(waitForDocumentTitle(importedWindowTitle, in: secondMain, timeout: 10))
        XCTAssertEqual(app.windows.count, 3, "A registered Note file must reveal its managed document instead of another external window.")

        try externalQALaunchServicesOpen(externalURL)
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.firstMatch.identifier == external.identifier })
        XCTAssertTrue((editor.value as? String ?? "").contains(importToken), "Revealing the original after import must retain its dirty editor.")
        externalQAFocus(external)
        app.typeKey("w", modifierFlags: [.command])
        let closeSheet = external.sheets.firstMatch
        XCTAssertTrue(closeSheet.waitForExistence(timeout: 10))
        XCTAssertTrue(closeSheet.buttons["Cancel"].exists)
        XCTAssertTrue(closeSheet.buttons["Discard Changes"].exists)
        let saveOnClose = closeSheet.buttons["Save"]
        XCTAssertTrue(saveOnClose.waitForExistence(timeout: 5))
        saveOnClose.click()
        XCTAssertTrue(waitUntil(timeout: 10) { !external.exists })
        XCTAssertEqual(try Data(contentsOf: externalURL), importedBytes, "Close must flush and save retained external edits.")
        try externalQALaunchServicesOpen(externalURL)
        let reopened = externalQAWindow(filename)
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        let reopenedMode = reopened.descendants(matching: .any)["scholium.externalMarkdown.mode"].firstMatch
        XCTAssertTrue(reopenedMode.waitForExistence(timeout: 10))
        XCTAssertEqual(reopenedMode.value as? String, "Review")
        let reopenedEditor = externalQASourceEditor(in: reopened)
        let quitToken = "-QUIT-\(UUID().uuidString)"
        try externalQAAppend(quitToken, to: reopenedEditor)
        XCTAssertEqual(try Data(contentsOf: externalURL), importedBytes)
        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 15) { self.app.state == .notRunning }, "Quit must wait for the external editor's final source flush.")
        XCTAssertEqual(try Data(contentsOf: externalURL), importedBytes + Data(quitToken.utf8))
        XCTAssertEqual(try Data(contentsOf: importedURL), importedBytes, "Later original-file edits must leave the imported Note unchanged.")

        // Launch Services now starts a fresh process with the QA bundle's empty
        // isolated home, rather than XCTest's already configured test home.
        // Opening an outside file must work before any Triptych is registered.
        try externalQALaunchServicesOpen(externalURL, withoutFixtureStartup: true)
        let coldExternal = externalQAWindow(filename)
        XCTAssertTrue(coldExternal.waitForExistence(timeout: 15))
        XCTAssertTrue(coldExternal.buttons["scholium.externalMarkdown.import"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.windows.count == 1 })
        XCTAssertEqual(app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'scholium-main-' ")).count, 0)
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["New Triptych…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        coldExternal.buttons["scholium.externalMarkdown.import"].click()
        XCTAssertTrue(app.staticTexts["No Triptych Available"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["New Triptych…"].isEnabled)
        app.buttons["Cancel"].firstMatch.click()
        externalQAFocus(coldExternal)
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.windows.count == 0 })
        try externalQALaunchServicesOpen(nil)
        XCTAssertTrue(
            app.buttons["scholium.bootstrap.connectExisting"].waitForExistence(timeout: 15),
            "A normal reopen after an external cold launch must offer Triptych setup.")
        XCTAssertEqual(try Data(contentsOf: externalURL), importedBytes + Data(quitToken.utf8))
    }

    @MainActor
    func testExternalMarkdownToolbarAndImportSheetLayout() throws {
        let originalURL = testDirectory.appendingPathComponent("QA External Controls.md")
        let originalBytes = Data("\u{FEFF}# 外部阅读 External reading\r\n\r\nSynthetic passage.\r\n".utf8)
        try originalBytes.write(to: originalURL)
        try externalQALaunchServicesOpen(originalURL)
        let external = externalQAWindow(originalURL.lastPathComponent)
        XCTAssertTrue(external.waitForExistence(timeout: 15))
        let mode = external.descendants(matching: .any)["scholium.externalMarkdown.mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.value as? String, "Review")
        external.buttons["scholium.externalMarkdown.find"].click()
        let query = external.searchFields["scholium.documentFind.query"].firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        typeCommittedText("Synthetic", into: query, in: app)
        let matches = external.descendants(matching: .any)["scholium.documentFind.matches"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { matches.value as? String == "Match 1 of 1" })
        mode.click()
        for name in ["Review", "Edit", "Source"] { XCTAssertTrue(external.menuItems[name].exists) }
        external.menuItems["Edit"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { mode.value as? String == "Edit" && mode.isEnabled })
        let editor = externalQASourceEditor(in: external)
        XCTAssertEqual(mode.value as? String, "Source")
        XCTAssertGreaterThan(mode.frame.width, 50, "The current mode label needs room beyond the native disclosure arrow.")
        XCTAssertTrue(waitUntil(timeout: 5) { matches.value as? String == "Match 1 of 1" })
        external.buttons["scholium.documentFind.close"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !query.exists })
        let token = "CONTROLS-\(UUID().uuidString)"
        try externalQAAppend(token, to: editor)
        XCTAssertFalse(external.buttons["Save"].exists, "Save belongs in More and File, without a second ambiguous toolbar icon.")
        let more = external.descendants(matching: .any)["scholium.externalMarkdown.more"].firstMatch
        XCTAssertTrue(more.exists)
        more.click()
        XCTAssertTrue(external.menuItems["Save"].isEnabled)
        for name in ["Find", "Reveal Original in Finder", "Close Window"] { XCTAssertTrue(external.menuItems[name].isEnabled) }
        external.menuItems["Save"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: originalURL)) == originalBytes + Data(token.utf8) })
        let toolbarShot = XCTAttachment(screenshot: external.screenshot())
        toolbarShot.name = "External Markdown — grouped native toolbar"
        toolbarShot.lifetime = .keepAlways
        add(toolbarShot)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Document Text Size"].firstMatch.hover()
        XCTAssertTrue(app.menuItems["200%"].firstMatch.isEnabled)
        app.menuItems["200%"].firstMatch.click()
        XCTAssertTrue((editor.value as? String ?? "").contains(token), "Changing presentation must retain the same source editor and text.")
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Document Text Size"].firstMatch.hover()
        XCTAssertFalse(app.menuItems["200%"].firstMatch.isEnabled)
        app.menuItems["Actual Size (100%)"].firstMatch.click()
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        resizeProofWindow(external, toWidth: 420, height: 420)
        let narrow = XCTAttachment(screenshot: external.screenshot())
        narrow.name = "External Markdown — compact native controls"
        narrow.lifetime = .keepAlways
        add(narrow)
        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["Import to Triptych…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        resizeProofWindow(external, toWidth: 880, height: 700)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Light"].firstMatch.click()
        external.buttons["scholium.externalMarkdown.import"].click()
        let sheet = external.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let workspace = sheet.popUpButtons["scholium.externalMarkdown.import.workspace"].firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        workspace.click()
        app.menuItems["Topics"].click()
        let heading = sheet.descendants(matching: .any)["Import to Triptych…"].firstMatch
        let cancel = sheet.buttons["Cancel"].firstMatch
        let confirm = sheet.buttons["scholium.externalMarkdown.import.confirm"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { confirm.isEnabled })
        let bounds = sheet.frame
        print("Import sheet \(bounds), heading \(heading.frame), Cancel \(cancel.frame), Import \(confirm.frame)")
        XCTAssertGreaterThanOrEqual(heading.frame.minX - bounds.minX, 19)
        XCTAssertGreaterThanOrEqual(heading.frame.minY - bounds.minY, 19)
        XCTAssertGreaterThanOrEqual(bounds.maxX - confirm.frame.maxX, 19)
        XCTAssertGreaterThanOrEqual(bounds.maxY - cancel.frame.maxY, 19)
        let selected = XCTAttachment(screenshot: external.screenshot())
        selected.name = "External Markdown — inset import sheet"
        selected.lifetime = .keepAlways
        add(selected)
        external.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes + Data(token.utf8))
        XCTAssertTrue((editor.value as? String ?? "").contains(token))
        let viewport = external.webViews.firstMatch
        let frameBeforeConflict = viewport.frame
        let dirtyToken = "UNSAVED-\(UUID().uuidString)"
        try externalQAAppend(dirtyToken, to: editor)
        let externalBytes = Data("# Concurrent editor\r\nChanged on disk.\r\n".utf8)
        try externalBytes.write(to: originalURL, options: .atomic)
        let issue = external.descendants(matching: .any)["scholium.externalMarkdown.issue"].firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertEqual(viewport.frame, frameBeforeConflict, "Conflict feedback must overlay the retained document, preserving its viewport.")
        mode.click()
        XCTAssertFalse(external.menuItems["Review"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Document Mode"].firstMatch.hover()
        XCTAssertFalse(app.menuBars.menuItems["Review"].firstMatch.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
        let conflictShot = XCTAttachment(screenshot: external.screenshot())
        conflictShot.name = "External Markdown — source-preserving conflict overlay"
        conflictShot.lifetime = .keepAlways
        add(conflictShot)
        external.buttons["Reload from Disk"].click()
        let cancelReload = external.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelReload.waitForExistence(timeout: 5))
        cancelReload.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !cancelReload.exists })
        XCTAssertTrue((editor.value as? String ?? "").contains(dirtyToken))
        XCTAssertEqual(try Data(contentsOf: originalURL), externalBytes)
    }

    @MainActor
    func testExternalAndManagedSaveShortcutsUseTheSharedMenuRegistry() throws {
        let mainID = app.windows.firstMatch.identifier
        let managedURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let managedBefore = try Data(contentsOf: managedURL)
        let originalURL = testDirectory.appendingPathComponent("QA Menu Save.md")
        let originalBefore = Data("\u{FEFF}# External menu save\r\n".utf8)
        try originalBefore.write(to: originalURL)
        try externalQALaunchServicesOpen(originalURL)
        let external = externalQAWindow(originalURL.lastPathComponent)
        XCTAssertTrue(external.waitForExistence(timeout: 15))
        let externalEditor = externalQASourceEditor(in: external)
        let externalToken = "EXTERNAL-MENU-\(UUID().uuidString)"
        try externalQAAppend(externalToken, to: externalEditor)
        externalEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: originalURL)) == originalBefore + Data(externalToken.utf8) })

        try externalQALaunchServicesOpen(managedURL)
        let main = app.windows[mainID]
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.firstMatch.identifier == mainID })
        selectDocumentMode("Source", in: main)
        let managedEditor = main.textViews["Markdown source editor"].firstMatch
        XCTAssertTrue(managedEditor.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 8) { managedEditor.isHittable })
        let managedToken = "MANAGED-MENU-\(UUID().uuidString)"
        try externalQAAppend(managedToken, to: managedEditor)
        managedEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: managedURL)) == managedBefore + Data(managedToken.utf8) })
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBefore + Data(externalToken.utf8))
    }

    private func externalQARegisteredTriptychNames() throws -> [String] {
        let registryURL = homeDirectory.appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
        let registry = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any])
        let triptychs = try XCTUnwrap(registry["triptychs"] as? [[String: Any]])
        return try triptychs.map { try XCTUnwrap($0["name"] as? String) }
    }

    private func externalQALaunchServicesOpen(_ url: URL?, withoutFixtureStartup: Bool = false) throws {
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let bundle = sourceRoot.appendingPathComponent(".build/qa-runtime/registered/Scholium-Codex-QA-Do-Not-Use.app")
        XCTAssertEqual(Bundle(url: bundle)?.bundleIdentifier, "com.scholium.qa", "Open With verification must target the registered disposable QA bundle.")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments =
            ["-a", bundle.path]
            + (withoutFixtureStartup ? ["--env", "SCHOLIUM_UI_TEST_WORKSPACE_ROOT="] : [])
            + (url.map { [$0.path] } ?? [])
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "Launch Services must deliver the Markdown URL to the running QA app.")
    }

    @MainActor
    private func externalQAWindow(_ filename: String) -> XCUIElement {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH 'scholium-external-markdown-' AND title BEGINSWITH %@", filename)).firstMatch
    }

    @MainActor
    private func externalQAFocus(_ window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).click()
    }

    @MainActor
    private func externalQASourceEditor(in window: XCUIElement) -> XCUIElement {
        externalQAFocus(window)
        let mode = window.descendants(matching: .any)["scholium.externalMarkdown.mode"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.click()
        window.menuItems["Source"].click()
        let editor = window.textViews["Markdown source editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 8) { editor.isHittable })
        return editor
    }

    @MainActor
    private func externalQAAppend(_ token: String, to editor: XCUIElement) throws {
        editor.click()
        editor.typeKey(.end, modifierFlags: [.command])
        try setPasteboardText(token)
        editor.typeKey("v", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { (editor.value as? String ?? "").contains(token) })
    }
}
