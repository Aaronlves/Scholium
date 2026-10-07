import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    func testKeptPassagesSurviveResearchNavigationAndSourceLoss() throws {
        // Enrich only the journey-owned copy's existing anchors while QA is
        // down. The standard Triptych remains a 500-Note fixture.
        app.terminate()
        let draftURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let relatedURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave B.md")
        let linkedURL = triptychDirectory.appendingPathComponent("02-topics/QA Topic.md")
        let workURL = triptychDirectory.appendingPathComponent("03-works/QA Work.md")
        let selectedWord = "keepzephyr"
        let relatedText = "keptrelatedprobe keepquartz keepzephyr. This exact synthetic paragraph remains a kept snapshot. 末尾限定：它不是证据。"
        let linkedText = "keptlinkprobe: [[QA Autosave A|retained connection]] belongs to this Topic. Keeping it changes no source."
        let additions = [
            (draftURL, "\n\nreplacementcobalt replacementtundra\n\nkeepquartz " + selectedWord),
            (relatedURL, "\n\n" + relatedText),
            (linkedURL, "\n\n" + linkedText),
            (workURL, "\n\nkeptreplacementprobe replacementcobalt replacementtundra."),
        ]
        for (url, suffix) in additions { try write(source(at: url) + suffix, to: url) }
        let originalBytes = try additions.map { ($0.0, try Data(contentsOf: $0.0)) }
        let draftSource = try source(at: draftURL)
        let relatedSource = try source(at: relatedURL)
        let linkedBytes = try Data(contentsOf: linkedURL)
        let workSource = try source(at: workURL)
        defer {
            try? Data(relatedSource.utf8).write(to: relatedURL)
            try? linkedBytes.write(to: linkedURL)
        }
        app.launchArguments += [
            "-colorScheme", "light",
            "-scholium.chat.sidebarEnabled", "NO",
        ]
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 45))
        waitForCurrentDocumentSurface()
        let workspace = app.windows["scholium-main-\(sessionID.uuidString)"].firstMatch
        focusWorkspaceWindow(workspace)
        XCTAssertFalse(sidebarModeControl("Chat", in: workspace).exists)
        selectDocumentMode("Source", in: workspace)
        let editor = workspace.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == draftSource })
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.typeKey("j", modifierFlags: [.command, .shift])

        func passage(_ prefix: String, containing marker: String) -> XCUIElement {
            workspace.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, marker)).firstMatch
        }
        let related = passage("scholium.related.card.", containing: "keptrelatedprobe")
        XCTAssertTrue(waitUntil(timeout: 30) { related.exists && related.isEnabled })
        let keptControls = workspace.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.kept.open."))
        XCTAssertEqual(keptControls.count, 0)

        // Cancelling the passage's native menu preserves the writing selection.
        related.rightClick()
        let keepMenu = app.menuItems["Keep Passage"].firstMatch
        XCTAssertTrue(keepMenu.waitForExistence(timeout: 5))
        for title in ["Open Source", "Insert Paragraph Link"] {
            XCTAssertTrue(app.menuItems[title].firstMatch.exists)
        }
        XCTAssertFalse(app.menuItems["Add to Chat"].firstMatch.exists, "Chat-off must hide the passage's Chat command.")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !keepMenu.exists })
        XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, draftSource)
        related.rightClick()
        XCTAssertTrue(keepMenu.waitForExistence(timeout: 5) && keepMenu.isEnabled)
        keepMenu.click()
        let keptRelated = passage("scholium.kept.open.", containing: "keptrelatedprobe")
        XCTAssertTrue(keptRelated.waitForExistence(timeout: 8))
        XCTAssertEqual(keptControls.count, 1)
        XCTAssertTrue(keptRelated.label.contains(relatedText))
        let keptRelatedID = keptRelated.identifier
        let relatedIdentity = String(keptRelatedID.dropFirst("scholium.kept.open.".count))
        XCTAssertTrue(
            workspace.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "scholium.kept.snapshot." + relatedIdentity)
            ).firstMatch.exists)
        XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, draftSource)

        // Keeping must retain the selected writing range and its Undo owner.
        app.typeKey("q", modifierFlags: [])
        let replacedSource = String(draftSource.dropLast(selectedWord.count)) + "q"
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == replacedSource })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == draftSource })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 8) { (try? Data(contentsOf: draftURL)) == Data(draftSource.utf8) })
        XCTAssertTrue(waitUntil(timeout: 15) { related.exists && related.isEnabled })
        related.rightClick()
        XCTAssertTrue(app.menuItems["Remove Kept Passage"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuItems["Keep Passage"].firstMatch.exists, "An already-kept occurrence must expose removal rather than a duplicate Keep action.")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(keptControls.count, 1)

        // A new writing focus replaces ordinary results but retains the kept
        // source independently of the current Related seed.
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: .command)
        editor.typeKey(.upArrow, modifierFlags: [])
        editor.typeKey(.upArrow, modifierFlags: [])
        app.typeKey("j", modifierFlags: [.command, .shift])
        let replacement = passage("scholium.related.card.", containing: "keptreplacementprobe")
        XCTAssertTrue(waitUntil(timeout: 30) { replacement.exists && replacement.isEnabled })
        XCTAssertFalse(related.exists)
        XCTAssertEqual(keptRelated.identifier, keptRelatedID)

        _ = selectResearchInspectorDirection("incoming")
        let linked = passage("scholium.links.occurrence.", containing: "keptlinkprobe")
        XCTAssertTrue(linked.waitForExistence(timeout: 10))
        linked.rightClick()
        let keepLink = app.menuItems["Keep Passage"].firstMatch
        XCTAssertTrue(keepLink.waitForExistence(timeout: 5) && keepLink.isEnabled)
        keepLink.click()
        let keptLinked = passage("scholium.kept.open.", containing: "keptlinkprobe")
        XCTAssertTrue(keptLinked.waitForExistence(timeout: 8))
        let keptLinkedID = keptLinked.identifier
        func assertKeptSnapshots() {
            XCTAssertEqual(keptControls.count, 2)
            XCTAssertEqual(keptRelated.identifier, keptRelatedID)
            XCTAssertEqual(keptLinked.identifier, keptLinkedID)
            XCTAssertTrue(keptRelated.label.contains(relatedText))
            XCTAssertTrue(keptLinked.label.contains("Keeping it changes no source."))
        }
        assertKeptSnapshots()
        let filter = workspace.searchFields["scholium.links.search"].firstMatch
        typeCommittedText("no-such-kept-fixture-link", into: filter, in: app)
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.connections.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(linked.exists)
        assertKeptSnapshots()
        filter.typeKey("a", modifierFlags: .command)
        filter.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(linked.waitForExistence(timeout: 5))

        let navigator = workspace.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        navigator.descendants(matching: .any)["Works"].firstMatch.click()
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Work.md"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
        assertKeptSnapshots()
        let inspector = workspace.descendants(matching: .any)["scholium.researchInspector"].firstMatch
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(keptRelated.waitForExistence(timeout: 5))
        assertKeptSnapshots()
        openNote("QA Work.md", expectedTitle: "QA Work", in: workspace)
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == workSource })
        assertKeptSnapshots()
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        let light = XCTAttachment(screenshot: workspace.screenshot())
        light.name = "Kept Related and Links snapshots after Note departure — Light"
        light.lifetime = .keepAlways
        add(light)

        // Opening now must use the kept entry, after the original Related
        // result and its seed have both departed. Back returns to the writer.
        let back = workspace.toolbars.buttons["Back"].firstMatch
        keptRelated.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: workspace, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == relatedSource })
        assertKeptSnapshots()
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertTrue(back.isEnabled)
        back.click()
        XCTAssertTrue(waitForDocumentTitle("QA Work", in: workspace, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == workSource })

        let changedSource = relatedSource.replacingOccurrences(of: "keptrelatedprobe", with: "revisedrelatedprobe")
        try write(changedSource, to: relatedURL)
        keptRelated.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: workspace, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == changedSource })
        assertKeptSnapshots()
        XCTAssertEqual(try Data(contentsOf: relatedURL), Data(changedSource.utf8))
        let changedNotice = workspace.descendants(matching: .any)["scholium.kept.error"].firstMatch
        XCTAssertTrue(changedNotice.waitForExistence(timeout: 5), "Changed source must explain why the captured passage cannot supply its old location.")
        changedNotice.buttons["Dismiss"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !changedNotice.exists })
        let revisionNotice = workspace.descendants(matching: .any)["scholium.operationIssue"].firstMatch
        if revisionNotice.exists { revisionNotice.buttons["Dismiss"].firstMatch.click() }
        back.click()
        XCTAssertTrue(waitForDocumentTitle("QA Work", in: workspace, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == workSource })

        let ordinaryFrame = workspace.frame
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        resizeProofWindow(workspace, toWidth: 780, height: 640)
        assertKeptSnapshots()
        try FileManager.default.removeItem(at: linkedURL)
        keptLinked.click()
        let error = workspace.descendants(matching: .any)["scholium.kept.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertEqual(documentTitle(in: workspace), "QA Work")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, workSource)
        assertKeptSnapshots()
        let unavailable = XCTAttachment(screenshot: workspace.screenshot())
        unavailable.name = "Missing kept source preserves writing and snapshots — Dark narrow"
        unavailable.lifetime = .keepAlways
        add(unavailable)
        error.buttons["Dismiss"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !error.exists })
        resizeProofWindow(workspace, toWidth: ordinaryFrame.width, height: ordinaryFrame.height)

        func removeKept(_ controlID: String) {
            let identity = String(controlID.dropFirst("scholium.kept.open.".count))
            let row = workspace.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "scholium.kept.row." + identity)
            ).firstMatch
            XCTAssertTrue(row.exists)
            let passage = row.buttons.matching(NSPredicate(format: "identifier == %@", controlID)).firstMatch
            XCTAssertTrue(passage.exists)
            passage.rightClick()
            let remove = app.menuItems["Remove Kept Passage"].firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.click()
        }
        removeKept(keptLinkedID)
        XCTAssertTrue(waitUntil(timeout: 5) { keptControls.count == 1 && !keptLinked.exists })
        XCTAssertEqual(keptRelated.identifier, keptRelatedID)
        removeKept(keptRelatedID)
        XCTAssertTrue(waitUntil(timeout: 5) { keptControls.count == 0 })
        XCTAssertFalse(workspace.staticTexts["Kept Passages"].firstMatch.exists)
        XCTAssertEqual(documentTitle(in: workspace), "QA Work")
        XCTAssertEqual(editor.value as? String, workSource)
        try linkedBytes.write(to: linkedURL)
        try Data(relatedSource.utf8).write(to: relatedURL)
        for (url, bytes) in originalBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        // Existing tearDown owns the single QA process and fixture directory.
        // Owner tests verify idempotence, stale locators and window teardown.
    }

    @MainActor
    func testKeptPassageNativeKeyboardContextMenu() throws {
        // AppKit documents this as the host's Keyboard navigation preference,
        // distinct from Accessibility Full Keyboard Access. No per-app override
        // or system-setting mutation substitutes for that prerequisite.
        try XCTSkipUnless(
            NSApplication.shared.isFullKeyboardAccessEnabled,
            "Requires System Settings > Keyboard > Keyboard navigation; the host setting is off. No system setting was changed.")
        waitForCurrentDocumentSurface()
        let workspace = app.windows["scholium-main-\(sessionID.uuidString)"].firstMatch
        focusWorkspaceWindow(workspace)
        let navigator = workspace.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        navigator.descendants(matching: .any)["Works"].firstMatch.click()
        openNote("QA Work.md", expectedTitle: "QA Work", in: workspace)
        selectDocumentMode("Source", in: workspace)
        let workURL = triptychDirectory.appendingPathComponent("03-works/QA Work.md")
        let topicURL = triptychDirectory.appendingPathComponent("02-topics/QA Topic.md")
        let originalBytes = try [workURL, topicURL].map { ($0, try Data(contentsOf: $0)) }
        let workSource = try source(at: workURL)
        let editor = workspace.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == workSource })
        _ = selectResearchInspectorDirection("incoming")
        let incoming = workspace.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "scholium.links.occurrence.", "QA Topic"
            )
        ).firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 10))
        let keptControls = workspace.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.kept.open."))
        XCTAssertEqual(keptControls.count, 0)
        incoming.rightClick()
        let keep = app.menuItems["Keep Passage"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 5) && keep.isEnabled)
        keep.click()
        let kept = keptControls.firstMatch
        XCTAssertTrue(kept.waitForExistence(timeout: 8))
        XCTAssertEqual(keptControls.count, 1)
        let keptID = kept.identifier
        let keptText = kept.label

        // Retain an exact source selection before moving through native focus.
        let selection = "---"
        XCTAssertTrue(workSource.hasPrefix(selection))
        editor.click()
        editor.typeKey(.home, modifierFlags: .command)
        for _ in selection { editor.typeKey(.rightArrow, modifierFlags: .shift) }
        let filter = workspace.searchFields["scholium.links.search"].firstMatch
        // The host prerequisite permits native button traversal; actual AX
        // focus and the context menu must still be proved inside this QA app.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let nativeTypes: [XCUIElement.ElementType] = [
            .button, .checkBox, .radioButton, .searchField, .textField, .popUpButton,
            .comboBox, .slider, .outline, .table, .collectionView, .segmentedControl,
        ]
        let nativeFocus = NSPredicate(
            format: "hasKeyboardFocus == true AND elementType IN %@", nativeTypes.map { NSNumber(value: $0.rawValue) })
        filter.click()
        XCTAssertTrue(waitUntil(timeout: 3) { focused.evaluate(with: filter) })
        var focusTrace = ["Start: native Links search field has keyboard focus."]
        for step in 1...24 {
            // WebKit can retain its DOM/AX focus while AppKit's search field
            // owns the keyboard. Send the first Tab from that verified field;
            // thereafter require positive native control focus before another.
            app.typeKey(.tab, modifierFlags: [])
            // Bind this query's results to AX identity, then read immutable
            // snapshots. Focus may move while attributes are collected; live
            // index-bound queries would re-evaluate a shrinking result set.
            let nativeOwners = try workspace.descendants(matching: .any).matching(nativeFocus)
                .allElementsBoundByAccessibilityElement.prefix(16).map { try $0.snapshot() }
            let identities = nativeOwners.prefix(6).map {
                "\($0.elementType): \($0.identifier), \(String($0.label.prefix(100)))"
            }
            let targetFocused = focused.evaluate(with: kept)
            focusTrace.append(
                "After Tab \(step): native=[\(identities.joined(separator: " | "))], target=\(targetFocused), editorDOMFocus=\(focused.evaluate(with: editor))")
            if targetFocused { break }
            if nativeOwners.isEmpty {
                focusTrace.append("No unambiguous native control focus; stopped before sending another Tab.")
                break
            }
        }
        let diagnostic = XCTAttachment(string: focusTrace.joined(separator: "\n") + "\nTarget: \(keptID), hittable: \(kept.isHittable)")
        diagnostic.name = "Bounded native keyboard focus traversal"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        if !focused.evaluate(with: kept) {
            let blocked = XCTAttachment(screenshot: workspace.screenshot())
            blocked.name = "Kept passage keyboard reachability failure"
            blocked.lifetime = .keepAlways
            add(blocked)
        }
        XCTAssertTrue(focused.evaluate(with: kept), "Native Tab traversal must reach the kept passage while focus remains in native controls.")
        app.typeKey(.return, modifierFlags: .control)
        let keyboardOpen = app.menuItems["Open Source"].firstMatch
        let keyboardMenuAppeared = keyboardOpen.waitForExistence(timeout: 5)
        if !keyboardMenuAppeared {
            let diagnostic = XCTAttachment(
                string:
                    "Control-Return produced no Open Source menu. Kept passage remains focused: \(focused.evaluate(with: kept)); target: \(keptID)"
            )
            diagnostic.name = "Native context-menu invocation diagnostic"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            let blocked = XCTAttachment(screenshot: workspace.screenshot())
            blocked.name = "Focused kept passage context-menu failure"
            blocked.lifetime = .keepAlways
            add(blocked)
        }
        XCTAssertTrue(keyboardMenuAppeared, "Control-Return must open the focused passage's native context menu.")
        XCTAssertTrue(app.menuItems["Remove Kept Passage"].firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !keyboardOpen.exists && focused.evaluate(with: kept) })
        XCTAssertEqual(documentTitle(in: workspace), "QA Work")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, workSource)
        XCTAssertEqual(keptControls.count, 1)
        XCTAssertEqual(kept.identifier, keptID)
        XCTAssertEqual(kept.label, keptText)

        // The existing document command reads the retained editor selection
        // without a pointer click that would replace that selection.
        app.typeKey("e", modifierFlags: .command)
        let selectedFind = workspace.descendants(matching: .any)["scholium.documentFind.query"].firstMatch
        XCTAssertTrue(selectedFind.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { selectedFind.value as? String == selection })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !selectedFind.exists })
        XCTAssertEqual(documentTitle(in: workspace), "QA Work")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, workSource)
        for (url, bytes) in originalBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
    }
}
