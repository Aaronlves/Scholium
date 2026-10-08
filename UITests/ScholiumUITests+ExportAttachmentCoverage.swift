import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    func testAuthorizedRealZoteroRefreshStyleAndCancelPreserveManuscriptFields() throws {
        guard ProcessInfo.processInfo.environment["SCHOLIUM_QA_REAL_ZOTERO"] == "1",
            ProcessInfo.processInfo.environment["SCHOLIUM_QA_KEEP_ARTIFACTS"] == "1"
        else {
            throw XCTSkip("Run this authorized Zotero journey alone, retaining its disposable manuscript and recovery state.")
        }
        let runningZotero = NSRunningApplication.runningApplications(withBundleIdentifier: "org.zotero.zotero")
        XCTAssertEqual(runningZotero.count, 1, "This journey never launches or restarts the researcher's Zotero.")
        let zoteroPID = try XCTUnwrap(runningZotero.first?.processIdentifier)
        let zotero = XCUIApplication(bundleIdentifier: "org.zotero.zotero")
        let preferences = zotero.windows["Zotero - Document Preferences"]
        let picker = zotero.windows["Citation Dialog"]
        XCTAssertFalse(preferences.exists || picker.exists, "Do not take over an existing researcher citation operation.")
        let cleanup: @MainActor () -> Void = {
            guard self.testRun?.failureCount ?? 0 > 0 else { return }
            guard let qa = self.app else { return }
            // Fail closed before any XCTest action can abort this block.
            self.app = nil
            // Only this journey's dialogs are owned; Zotero stays running.
            for dialog in [preferences, picker] where dialog.exists {
                let cancel = dialog.buttons["Cancel"].firstMatch
                if cancel.exists && cancel.isEnabled { cancel.click() }
            }
            let dialogsClosed = self.waitUntil(timeout: 10) { !preferences.exists && !picker.exists }
            if dialogsClosed && self.realZoteroWaitForFailedJourneyCleanup(in: qa) {
                self.app = qa
            } else {
                // Base tearDown must not kill the callback owner while its
                // remote cleanup is uncertain. This opt-in journey runs alone.
                XCTFail("Zotero cleanup is unconfirmed. The isolated QA process and manuscript were retained; stop native journeys until recovery is complete.")
            }
        }
        addTeardownBlock { await cleanup() }
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try String(contentsOf: noteURL, encoding: .utf8)
        let editor = enterLivePreview(in: workspace)
        editor.typeKey(.end, modifierFlags: .command)
        realZoteroCommand("Citation…")
        XCTAssertTrue(preferences.waitForExistence(timeout: 15))
        realZoteroSelectStyle("APA Style 7th edition", in: preferences)
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let search = picker.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("Slaves of the Passions")
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                picker.staticTexts.containing(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "Slaves of the Passions", "Slaves of the Passions"))
                    .count > 0
            },
            "The authorized published-item fixture must resolve in Zotero; never substitute another source.")
        search.typeKey(.return, modifierFlags: [])
        let accept = picker.buttons["Accept"]
        XCTAssertTrue(waitUntil(timeout: 8) { accept.isEnabled })
        XCTAssertTrue(picker.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Schroeder, 2007")).firstMatch.exists)
        accept.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !picker.exists && (try? self.realZoteroFields(at: noteURL).count) == 1 })
        let citation = try realZoteroFields(at: noteURL)
        XCTAssertEqual(citation.first?["kind"], "citation")
        XCTAssertTrue(try String(contentsOf: noteURL, encoding: .utf8).contains(original))
        realZoteroAttachSource(noteURL, name: "real-zotero-citation-inserted")

        app.activate()
        let bibliographyEditor = enterLivePreview(in: workspace)
        bibliographyEditor.typeKey(.end, modifierFlags: .command)
        bibliographyEditor.typeKey(.return, modifierFlags: [])
        bibliographyEditor.typeKey(.return, modifierFlags: [])
        realZoteroCommand("Bibliography…")
        XCTAssertTrue(waitUntil(timeout: 15) { (try? self.realZoteroFields(at: noteURL).count) == 2 })
        let beforeRefresh = try realZoteroFields(at: noteURL)
        XCTAssertEqual(beforeRefresh.map { $0["kind"] ?? "" }, ["citation", "bibliography"])
        XCTAssertEqual(beforeRefresh.first?["id"], citation.first?["id"])
        realZoteroAttachSource(noteURL, name: "real-zotero-before-refresh")

        // Make successful Refresh observable even when Zotero renders the
        // same text: a concurrent editor invalidates only this disposable
        // manuscript's accepted-field signatures, preserving all field bytes.
        try realZoteroInvalidateAcceptance(at: noteURL)
        let stale = workspace.descendants(matching: .any)["scholium.document.citations.stale"]
        let issue = workspace.descendants(matching: .any)["scholium.document.citations.issue"]
        let unresolved = workspace.descendants(matching: .any)["scholium.document.citations.unresolved"]
        XCTAssertTrue(stale.waitForExistence(timeout: 15))
        let expectedSignatures = beforeRefresh.map { ["id": $0["id"]!, "code": $0["code"]!] }
        realZoteroCommand("Refresh Citations", nested: true)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (try? self.realZoteroDocument(at: noteURL)["acceptedFields"] as? [[String: String]]) == expectedSignatures
                    && !stale.exists && !issue.exists && !unresolved.exists
            }, "Refresh must replace the persisted stale witness with both accepted fields and clear the citation notice.")
        realZoteroWaitForIdle()
        XCTAssertEqual(try realZoteroFields(at: noteURL).map { $0["id"] }, beforeRefresh.map { $0["id"] })
        XCTAssertEqual(try realZoteroFields(at: noteURL).map { $0["kind"] }, beforeRefresh.map { $0["kind"] })
        XCTAssertTrue(try String(contentsOf: noteURL, encoding: .utf8).contains(original))
        realZoteroAttachSource(noteURL, name: "real-zotero-after-refresh")

        let beforeStyle = try Data(contentsOf: noteURL)
        realZoteroCommand("Citation Style…", nested: true)
        XCTAssertTrue(preferences.waitForExistence(timeout: 15))
        realZoteroSelectStyle("Chicago Manual of Style 18th edition (author-date)", in: preferences)
        XCTAssertTrue(waitUntil(timeout: 15) { (try? Data(contentsOf: noteURL)) != beforeStyle && !preferences.exists })
        realZoteroWaitForIdle()
        let styledFields = try realZoteroFields(at: noteURL)
        XCTAssertEqual(styledFields.map { $0["id"] }, beforeRefresh.map { $0["id"] })
        XCTAssertEqual(styledFields.map { $0["kind"] }, beforeRefresh.map { $0["kind"] })
        XCTAssertTrue(styledFields[0]["text"]?.contains("Schroeder") == true)
        XCTAssertTrue(styledFields[1]["text"]?.localizedCaseInsensitiveContains("Slaves of the Passions") == true)
        let styleData = try XCTUnwrap(realZoteroDocument(at: noteURL)["data"] as? String)
        XCTAssertTrue(
            styleData.contains("/chicago") && styleData.contains("author-date"), "The accepted document must use the selected Chicago author-date style.")
        XCTAssertFalse(issue.exists || unresolved.exists || stale.exists)
        realZoteroAttachSource(noteURL, name: "real-zotero-after-style-change")
        app.activate()
        focusWorkspaceWindow(workspace)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            waitUntil(timeout: 12) { (try? Data(contentsOf: noteURL)) == beforeStyle }, "One Undo must restore exact source before the accepted style change.")

        realZoteroCommand("Citation Style…", nested: true)
        XCTAssertTrue(preferences.waitForExistence(timeout: 15))
        let pendingStyle = preferences.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@ OR value == %@",
                "Chicago Manual of Style 18th edition (author-date)", "Chicago Manual of Style 18th edition (author-date)")
        ).firstMatch
        XCTAssertTrue(pendingStyle.waitForExistence(timeout: 5))
        pendingStyle.click()
        preferences.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { !preferences.exists })
        realZoteroWaitForIdle()
        selectDocumentMode("Source", in: workspace)
        let sourceEditor = workspace.textViews["Markdown source editor"].firstMatch
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        XCTAssertEqual(
            sourceEditor.value as? String, String(data: beforeStyle, encoding: .utf8),
            "Cancellation must preserve the current editor source, not only the previous saved file.")
        selectDocumentMode("Review", in: workspace)
        XCTAssertEqual(try Data(contentsOf: noteURL), beforeStyle, "Cancellation must retain both exact fields and document metadata.")
        XCTAssertFalse(issue.exists || unresolved.exists || stale.exists)
        realZoteroAttachSource(noteURL, name: "real-zotero-cancelled-style")
        XCTAssertEqual(NSRunningApplication.runningApplications(withBundleIdentifier: "org.zotero.zotero").map(\.processIdentifier), [zoteroPID])
        selectDocumentMode("Review", in: workspace)
        let shot = XCTAttachment(screenshot: workspace.screenshot())
        shot.name = "Real Zotero citation and bibliography after Refresh, style Undo and cancellation"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func realZoteroWaitForFailedJourneyCleanup(in application: XCUIApplication) -> Bool {
        application.activate()
        application.menuBars.menuBarItems["Insert"].click()
        let insertion = application.menuItems["Citation…"].firstMatch
        application.menuItems["Citations"].firstMatch.hover()
        let cancel = application.menuItems["Cancel Citation Operation"].firstMatch
        let idle = waitUntil(timeout: 15) { insertion.exists && insertion.isEnabled && cancel.exists && !cancel.isEnabled }
        application.typeKey(.escape, modifierFlags: [])
        application.typeKey(.escape, modifierFlags: [])
        return idle && !application.descendants(matching: .any)["scholium.document.citations.issue"].exists
    }

    @MainActor
    private func realZoteroCommand(_ title: String, nested: Bool = false) {
        app.activate()
        app.menuBars.menuBarItems["Insert"].click()
        if nested { app.menuItems["Citations"].firstMatch.hover() }
        let command = app.menuItems[title].firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        XCTAssertTrue(command.isEnabled)
        command.click()
    }

    @MainActor
    private func realZoteroSelectStyle(_ style: String, in preferences: XCUIElement) {
        let hierarchy = XCTAttachment(string: preferences.debugDescription)
        hierarchy.name = "Zotero document style controls"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let choice = preferences.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", style, style)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.click()
        preferences.buttons["OK"].click()
        XCTAssertTrue(waitUntil(timeout: 10) { !preferences.exists })
    }

    @MainActor
    private func realZoteroWaitForIdle() {
        app.activate()
        app.menuBars.menuBarItems["Insert"].click()
        app.menuItems["Citations"].firstMatch.hover()
        let cancel = app.menuItems["Cancel Citation Operation"].firstMatch
        let refresh = app.menuItems["Refresh Citations"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 15) { cancel.exists && !cancel.isEnabled && refresh.isEnabled })
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(.escape, modifierFlags: [])
    }

    private func realZoteroFields(at url: URL) throws -> [[String: String]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: "(?:scholium-zotero:1:|<!--scholium-zotero-field:1:)([A-Za-z0-9+/=]+)")
        return try expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let range = try XCTUnwrap(Range(match.range(at: 1), in: text))
            let data = try XCTUnwrap(Data(base64Encoded: String(text[range])))
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        }
    }

    private func realZoteroDocument(at url: URL) throws -> [String: Any] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: "<!--scholium-zotero-document:1:([A-Za-z0-9+/=]+)-->")
        let match = try XCTUnwrap(expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: text))
        let data = try XCTUnwrap(Data(base64Encoded: String(text[range])))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func realZoteroInvalidateAcceptance(at url: URL) throws {
        var text = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(pattern: "<!--scholium-zotero-document:1:([A-Za-z0-9+/=]+)-->")
        let match = try XCTUnwrap(expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: text))
        var document = try realZoteroDocument(at: url)
        document["acceptedFields"] = [[String: String]]()
        let payload = try JSONSerialization.data(withJSONObject: document).base64EncodedString()
        text.replaceSubrange(range, with: payload)
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func realZoteroAttachSource(_ url: URL, name: String) {
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNativeHTMLAndDOCXExportUseUnsavedSourceWithoutSavingTheNote() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000, appearance: .light)
        app.launch()
        waitForCurrentDocumentSurface()
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try Data(contentsOf: noteURL)
        let addition = """


            Native export body 中文 😀.

            A **bold export** and [native link](https://example.test/export) with a note[^export].

            [^export]: Native editable footnote 中文.
            """
        selectDocumentMode("Source", in: workspace)
        let editor = workspace.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.isHittable })
        editor.click()
        editor.typeKey(.end, modifierFlags: [.command])
        try coveragePaste(addition, into: editor)
        XCTAssertTrue(waitUntil(timeout: 8) { (editor.value as? String ?? "").contains("Native export body 中文 😀.") })
        XCTAssertEqual(try Data(contentsOf: noteURL), original)

        let exports = testDirectory.appendingPathComponent("native-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let htmlURL = exports.appendingPathComponent("native-note.html")
        let htmlPreview = coverageOpenExportPreview(from: workspace)
        coverageSelectExportFormat("HTML", in: htmlPreview)
        coverageCapture(htmlPreview, name: "native-html-export-unsaved-preview")

        // Cancel the actual Save panel before making the same export again.
        htmlPreview.buttons["Export"].firstMatch.click()
        let cancelledPanel = htmlPreview.sheets.firstMatch
        XCTAssertTrue(cancelledPanel.waitForExistence(timeout: 5))
        cancelledPanel.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !cancelledPanel.exists })
        XCTAssertTrue(htmlPreview.exists)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: noteURL), original)

        try coverageExportPreview(htmlPreview, to: htmlURL)
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        XCTAssertTrue(html.lowercased().contains("<!doctype html>"))
        XCTAssertTrue(html.contains("Native export body 中文 😀."))
        XCTAssertTrue(html.contains("<strong>bold export</strong>"))
        XCTAssertTrue(html.contains("https://example.test/export"))
        XCTAssertTrue(html.contains("Native editable footnote 中文."))
        XCTAssertFalse(html.contains("summary:"), "YAML is excluded by the initial export choice.")
        XCTAssertEqual(try Data(contentsOf: noteURL), original)

        let docxURL = exports.appendingPathComponent("native-note.docx")
        let noticeText = "Word keeps editable text, headings, hyperlinks and footnotes; tables flatten, while images and exact line spacing are omitted."
        let lightPreview = coverageOpenExportPreview(from: workspace)
        coverageSelectExportFormat("Word (.docx)", in: lightPreview)
        let lightNotice = lightPreview.staticTexts[noticeText].firstMatch
        XCTAssertTrue(lightNotice.waitForExistence(timeout: 10))
        coverageCapture(lightPreview, name: "native-docx-export-unsaved-light-preview")
        resizeProofWindow(lightPreview, toWidth: 640, height: 480)
        XCTAssertTrue(lightNotice.isHittable)
        XCTAssertTrue(lightPreview.frame.contains(lightNotice.frame), "The DOCX scope notice must remain readable at the preview's minimum size.")
        coverageCapture(lightPreview, name: "native-docx-export-light-minimum-size-notice")
        lightPreview.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !lightPreview.exists })
        XCTAssertFalse(FileManager.default.fileExists(atPath: docxURL.path))
        XCTAssertEqual(try Data(contentsOf: noteURL), original)
        XCTAssertTrue((editor.value as? String ?? "").contains("Native export body 中文 😀."))

        focusWorkspaceWindow(workspace)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        let wordPreview = coverageOpenExportPreview(from: workspace)
        coverageSelectExportFormat("Word (.docx)", in: wordPreview)
        let notice = wordPreview.staticTexts[noticeText].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        resizeProofWindow(wordPreview, toWidth: 640, height: 480)
        XCTAssertTrue(notice.isHittable)
        XCTAssertTrue(wordPreview.frame.contains(notice.frame), "The DOCX scope notice must remain readable at the preview's minimum size.")
        coverageCapture(wordPreview, name: "native-docx-export-dark-minimum-size-notice")
        XCTAssertEqual(try Data(contentsOf: noteURL), original)
        XCTAssertTrue((editor.value as? String ?? "").contains("Native export body 中文 😀."))
        try coverageExportPreview(wordPreview, to: docxURL)
        let wordData = try Data(contentsOf: docxURL)
        XCTAssertTrue(wordData.starts(with: [0x50, 0x4B]))
        let documentXML = try XMLDocument(data: coverageDOCXPart("word/document.xml", at: docxURL))
        let footnotesXML = try XMLDocument(data: coverageDOCXPart("word/footnotes.xml", at: docxURL))
        let relationships = try XMLDocument(data: coverageDOCXPart("word/_rels/document.xml.rels", at: docxURL))
        XCTAssertTrue(documentXML.stringValue?.contains("Native export body 中文 😀.") == true)
        XCTAssertFalse(try documentXML.nodes(forXPath: "//*[local-name()='footnoteReference']").isEmpty)
        XCTAssertTrue(footnotesXML.stringValue?.contains("Native editable footnote 中文.") == true)
        XCTAssertEqual(
            try relationships.nodes(forXPath: "//*[local-name()='Relationship' and @Target='https://example.test/export' and @TargetMode='External']").count,
            1)
        let editable = try NSAttributedString(
            data: wordData,
            options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
            documentAttributes: nil)
        XCTAssertTrue(editable.string.contains("Native export body 中文 😀."))
        XCTAssertEqual(try Data(contentsOf: noteURL), original, "Export must leave the exact saved Note untouched.")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertTrue((editor.value as? String ?? "").contains("Native export body 中文 😀."))
    }

    @MainActor
    func testNativeAttachmentAndImageInsertionPreserveFilesAndReturnFromQuickLook() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000)
        app.launch()
        waitForCurrentDocumentSurface()
        let workspace = stableWorkspaceWindow(app.windows.firstMatch)
        let vault = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let noteURL = vault.appendingPathComponent("QA Autosave A.md")
        let originalNote = try String(contentsOf: noteURL, encoding: .utf8)
        let inputs = testDirectory.appendingPathComponent("attachment-inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        let copiedInput = inputs.appendingPathComponent("Copy Evidence.txt")
        let referencedInput = inputs.appendingPathComponent("Reference Evidence.txt")
        let imageInput = inputs.appendingPathComponent("Figure Sample.png")
        let imageAlt = "Figure Sample"
        let documentBytes = Data("Synthetic attachment 中文. Preserve this exact original.\n".utf8)
        let referenceBytes = Data("Synthetic original reference 中文. Keep this file in place.\n".utf8)
        try documentBytes.write(to: copiedInput)
        try referenceBytes.write(to: referencedInput)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 18, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        for y in 3..<15 {
            for x in 3..<21 {
                bitmap.setColor(NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.72, alpha: 1), atX: x, y: y)
            }
        }
        let imageBytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try imageBytes.write(to: imageInput)

        let editor = enterLivePreview(in: workspace)
        try coverageAppendLineBreak(to: editor)
        coverageOpenInsertionMenu("Attach a Copy…", in: "File")
        let cancelledPanel = workspace.sheets["open-panel"].firstMatch
        XCTAssertTrue(cancelledPanel.waitForExistence(timeout: 5))
        cancelledPanel.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !cancelledPanel.exists })
        XCTAssertFalse((editor.value as? String ?? "").contains(copiedInput.lastPathComponent))
        XCTAssertEqual(try Data(contentsOf: noteURL), Data(originalNote.utf8))

        coverageOpenInsertionMenu("Attach a Copy…", in: "File")
        try coverageChooseFile(copiedInput, in: workspace)
        XCTAssertTrue(waitUntil(timeout: 10) { (editor.value as? String ?? "").contains(copiedInput.lastPathComponent) })
        try coverageAppendLineBreak(to: editor)
        coverageOpenInsertionMenu("Reference Original…", in: "File")
        try coverageChooseFile(referencedInput, in: workspace)
        XCTAssertTrue(waitUntil(timeout: 10) { (editor.value as? String ?? "").contains(referencedInput.lastPathComponent) })
        try coverageAppendLineBreak(to: editor)
        coverageOpenInsertionMenu("Import Image…", in: "Insert")
        try coverageChooseFile(imageInput, in: workspace)
        selectDocumentMode("Source", in: workspace)
        let sourceEditor = workspace.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { (sourceEditor.value as? String ?? "").contains("![" + imageAlt + "](") })
        sourceEditor.click()
        sourceEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? String(contentsOf: noteURL, encoding: .utf8))?.contains("![Figure Sample](Attachments/") == true })
        let insertedSource = try String(contentsOf: noteURL, encoding: .utf8)
        let copyDestination = try coverageCopiedDestination(
            named: copiedInput.lastPathComponent, expectedFilename: copiedInput.lastPathComponent, in: insertedSource, isImage: false)
        let imageDestination = try coverageCopiedDestination(named: imageAlt, expectedFilename: imageInput.lastPathComponent, in: insertedSource, isImage: true)
        let referenceDestination = referencedInput.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: true)
        let copyLink = "[Copy Evidence.txt](\(copyDestination))"
        let referenceLink = "[Reference Evidence.txt](\(referenceDestination))"
        let imageLink = "![Figure Sample](\(imageDestination))"
        let expectedSource = originalNote + "\n" + copyLink + "\n" + referenceLink + "\n" + imageLink
        XCTAssertEqual(insertedSource, expectedSource, "Insertion must add ordinary exact Markdown links at the editor caret.")
        let copiedFile = vault.appendingPathComponent(try XCTUnwrap(copyDestination.removingPercentEncoding))
        let copiedImage = vault.appendingPathComponent(try XCTUnwrap(imageDestination.removingPercentEncoding))
        XCTAssertEqual(try Data(contentsOf: copiedFile), documentBytes)
        XCTAssertEqual(try Data(contentsOf: copiedImage), imageBytes)
        XCTAssertEqual(try Data(contentsOf: copiedInput), documentBytes)
        XCTAssertEqual(try Data(contentsOf: referencedInput), referenceBytes)
        XCTAssertEqual(try Data(contentsOf: imageInput), imageBytes)
        coverageCapture(workspace, name: "native-attachment-and-image-exact-markdown")

        // Removing the image's authored relationship through Undo must retain
        // the owned copy. Redo restores that same URL rather than importing again.
        sourceEditor.typeKey("z", modifierFlags: [.command])
        sourceEditor.typeKey("s", modifierFlags: [.command])
        let withoutImage = originalNote + "\n" + copyLink + "\n" + referenceLink + "\n"
        XCTAssertTrue(waitUntil(timeout: 10) { (try? String(contentsOf: noteURL, encoding: .utf8)) == withoutImage })
        XCTAssertEqual(try Data(contentsOf: copiedImage), imageBytes)
        sourceEditor.typeKey("z", modifierFlags: [.command, .shift])
        sourceEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? String(contentsOf: noteURL, encoding: .utf8)) == expectedSource })

        selectDocumentMode("Review", in: workspace)
        XCTAssertTrue(workspace.images[imageAlt].waitForExistence(timeout: 10))
        coverageCapture(workspace, name: "native-attachment-review-image")
        for name in [copiedInput.lastPathComponent, referencedInput.lastPathComponent] {
            let link = workspace.links[name].firstMatch
            XCTAssertTrue(link.waitForExistence(timeout: 10))
            link.click()
            let preview = app.windows["Quick Look"].firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 10), "The authored file link must reach system Quick Look for that exact file.")
            let filename = preview.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@ OR value == %@ OR title == %@", name, name, name)
            ).firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 5), "Quick Look must identify the exact authored file.")
            coverageCapture(preview, name: "native-quick-look-\((name as NSString).deletingPathExtension)")
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 5) { !preview.exists })
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: workspace))
            XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Review")
            XCTAssertEqual(try Data(contentsOf: noteURL), Data(expectedSource.utf8))
        }
        XCTAssertEqual(try Data(contentsOf: copiedFile), documentBytes)
        XCTAssertEqual(try Data(contentsOf: copiedInput), documentBytes)
        XCTAssertEqual(try Data(contentsOf: referencedInput), referenceBytes)
        XCTAssertEqual(try Data(contentsOf: imageInput), imageBytes)
    }

    @MainActor
    private func coverageOpenExportPreview(from workspace: XCUIElement) -> XCUIElement {
        focusWorkspaceWindow(workspace)
        app.menuBars.menuBarItems["File"].click()
        let action = app.menuItems["Export Note…"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        action.click()
        let preview = app.windows.matching(NSPredicate(format: "title CONTAINS %@", "— Export Note")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        return preview
    }

    @MainActor
    private func coverageSelectExportFormat(_ format: String, in preview: XCUIElement) {
        let formats = ["Format", "PDF", "HTML", "Word (.docx)"]
        let control = preview.toolbars.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@ OR title IN %@", formats, formats)).firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        control.click()
        let item = app.menuItems[format].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        let export = preview.buttons["Export"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 20) { export.exists && export.isEnabled })
    }

    @MainActor
    private func coverageExportPreview(_ preview: XCUIElement, to destination: URL) throws {
        let export = preview.buttons["Export"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { export.isEnabled })
        export.click()
        let panel = preview.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let name = panel.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeKey("a", modifierFlags: [.command])
        try coveragePaste(destination.lastPathComponent, into: name)
        try coverageGoToFolder(destination.deletingLastPathComponent(), panel: panel)
        if panel.exists {
            let confirm = panel.buttons["Export"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 5) { confirm.isEnabled })
            confirm.click()
        }
        XCTAssertTrue(waitUntil(timeout: 20) { FileManager.default.fileExists(atPath: destination.path) })
        XCTAssertTrue(waitUntil(timeout: 5) { !preview.exists })
    }

    @MainActor
    private func coverageOpenInsertionMenu(_ title: String, in menu: String) {
        app.menuBars.menuBarItems[menu].click()
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { item.isEnabled })
        item.click()
    }

    @MainActor
    private func coverageChooseFile(_ file: URL, in workspace: XCUIElement) throws {
        let panel = workspace.sheets["open-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        try coverageGoToFolder(file, panel: panel)
        if panel.exists {
            let confirm = panel.buttons["OKButton"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 5) { confirm.isEnabled })
            confirm.click()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
    }

    @MainActor
    private func coverageGoToFolder(_ location: URL, panel: XCUIElement) throws {
        app.typeKey("g", modifierFlags: [.command, .shift])
        let sheet = app.sheets.matching(NSPredicate(format: "identifier != %@", panel.identifier)).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let path = sheet.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.click()
        path.typeKey("a", modifierFlags: [.command])
        try coveragePaste(location.path, into: path)
        let go = sheet.buttons.allElementsBoundByIndex.reversed().first {
            $0.isEnabled && !["Cancel", "Close", "CancelButton", "CloseButton"].contains($0.label)
                && !["CancelButton", "CloseButton", "OKButton"].contains($0.identifier)
        }
        if let go { go.click() } else { path.typeKey(.return, modifierFlags: []) }
        if !waitUntil(timeout: 2) { !sheet.exists } { path.typeKey(.return, modifierFlags: []) }
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
    }

    @MainActor
    private func coverageAppendLineBreak(to editor: XCUIElement) throws {
        editor.typeKey(.end, modifierFlags: [.command])
        try coveragePaste("\n", into: editor)
    }

    @MainActor
    private func coveragePaste(_ text: String, into element: XCUIElement) throws {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { representations, type in
                representations[type] = item.data(forType: type)
            }
        }
        try setPasteboardText(text)
        let ownedChangeCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == ownedChangeCount {
                pasteboard.clearContents()
                if let saved {
                    pasteboard.writeObjects(
                        saved.map { representations in
                            let item = NSPasteboardItem()
                            representations.forEach { item.setData($0.value, forType: $0.key) }
                            return item
                        })
                }
            }
        }
        element.typeKey("v", modifierFlags: [.command])
    }

    private func coverageCopiedDestination(named label: String, expectedFilename: String, in source: String, isImage: Bool) throws -> String {
        let pattern =
            (isImage ? "!" : "(?<!!)")
            + "\\[" + NSRegularExpression.escapedPattern(for: label) + "\\]\\((Attachments/[^)]+)\\)"
        let regex = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
        let destination = (source as NSString).substring(with: match.range(at: 1))
        let components = destination.split(separator: "/").map(String.init)
        guard components.count == 3 else {
            XCTFail("The copied file must have one owned UUID folder: \(destination).")
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try XCTUnwrap(UUID(uuidString: components[1]))
        XCTAssertEqual(components[2].removingPercentEncoding, expectedFilename)
        return destination
    }

    private func coverageDOCXPart(_ part: String, at archive: URL) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, part]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "The exported DOCX must contain \(part).")
        return data
    }

    @MainActor
    private func coverageCapture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
