import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testSearchParagraphLocationHasAccessibleNameAndOpensItsNote() throws {
        waitForCurrentDocumentSurface()
        selectDocumentMode("Source")
        let sourceURL = triptychDirectory.appendingPathComponent("02-topics/QA Topic.md")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let line =
            try XCTUnwrap(source.components(separatedBy: "\n").firstIndex { $0.contains("中文检索标记") }) + 1
        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        selectResearchSearchScope("Triptych", in: app)
        let field = advanced.searchFields["scholium.searchField"]
        typeCommittedText("paragraph:(晨光样本 OR aurora-fixture)", into: field, in: app)
        XCTAssertTrue(searchResult(named: "QA Topic").waitForExistence(timeout: 15))
        advanced.buttons["Matching Paragraphs"].click()
        let paragraph = app.buttons["Paragraph at line \(line)"].firstMatch
        XCTAssertTrue(
            paragraph.waitForExistence(timeout: 5),
            "Every paragraph destination must name its source line.")
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "named-search-paragraph-location"
        capture.lifetime = .keepAlways
        add(capture)
        paragraph.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", timeout: 10))
        XCTAssertEqual(documentModeState(documentModeControl()), "Source")
        XCTAssertEqual(try String(contentsOf: sourceURL, encoding: .utf8), source)
        XCTAssertTrue(advanced.exists)
    }

    @MainActor
    func testRelatedMaterialCurrentLineSelectionAndNoteDeparture() throws {
        // setUp clones the staged standard 500-Note Triptych into this journey's
        // UUID directory. Modify existing anchors only, while its QA app is down;
        // never change TestVaults, the staged copy, or the fixture's Note count.
        app.terminate()
        let firstURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let secondURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave B.md")
        let topicURL = triptychDirectory.appendingPathComponent("02-topics/QA Topic.md")
        let workURL = triptychDirectory.appendingPathComponent("03-works/QA Work.md")
        let lineWords = "linequartz linezephyr"
        let adjacentWords = "adjacentcobalt adjacenttundra"
        let destinationWords = "newmonsoon newvelvet"
        let alternative = "词群专用"
        let termGroupName = "QA bilingual terms"
        let termGroupsURL = homeDirectory.appendingPathComponent("ApplicationSupport/Workspace/search-term-groups.json")
        let termGroupsData = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "groups": [["id": UUID().uuidString, "name": termGroupName, "terms": ["unmatchinglexeme", alternative]]],
        ])
        try FileManager.default.createDirectory(at: termGroupsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try termGroupsData.write(to: termGroupsURL)
        let mixedLine = lineWords + " " + adjacentWords
        let lateQualification = "Late qualification: this synthetic material does not establish agreement or evidence. 最后的限定仍须完整可读。"
        let longPassage =
            "合成界面样本：\(lineWords) 标记这段可回到原文的材料。研究者可以先阅读上下文，再判断它与当前问题的关系；这里不预设支持或反对。The passage remains a source excerpt, with mixed-script wording and enough context to inspect its wrapping in the research pane. "
            + "A compact preview cannot replace the complete paragraph when its final sentence limits the apparent claim. "
            + lateQualification
        let additions = [
            (firstURL, "\n\n" + mixedLine + "\n" + lineWords + "\n" + mixedLine),
            (secondURL, "\n\n" + longPassage + "\n\n" + destinationWords),
            (topicURL, "\n\n" + adjacentWords + ".\n\n此处出现" + alternative + "，用于检查研究者选择的双语词群。"),
            (workURL, "\n\n" + lineWords + "：另一篇笔记的合成段落，用于观察分组留白。\n\n" + destinationWords + "."),
        ]
        for (url, suffix) in additions {
            try write(source(at: url) + suffix, to: url)
        }
        let firstSource = try source(at: firstURL)
        let secondSource = try source(at: secondURL)
        let expectedBytes = try additions.map { ($0.0, try Data(contentsOf: $0.0)) }
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_INCREASE_CONTRAST"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_TRANSPARENCY"] = "1"
        app.launchArguments += ["-colorScheme", "light"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 45))
        waitForCurrentDocumentSurface()
        let workspace = app.windows["scholium-main-\(sessionID.uuidString)"].firstMatch
        XCTAssertTrue(workspace.exists)
        focusWorkspaceWindow(workspace)

        // This journey owns Chat-enabled menu parity. Set the real Bool through
        // Settings before establishing any editor selection or Inspector state.
        app.menuBars.menuBarItems["Scholium QA"].click()
        app.menuItems["Settings…"].click()
        let settings = app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        selectSettingsCategory("agents", in: settings)
        let chatEnabled = settings.checkBoxes["scholium.settings.chatSidebarEnabled"].firstMatch
        XCTAssertTrue(chatEnabled.waitForExistence(timeout: 5))
        if !selectionControlIsSelected(chatEnabled) { chatEnabled.click() }
        XCTAssertTrue(waitUntil(timeout: 3) { self.selectionControlIsSelected(chatEnabled) })
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { !settings.exists })
        focusWorkspaceWindow(workspace)
        XCTAssertTrue(sidebarModeControl("Chat", in: workspace).exists)

        let inspector = app.descendants(matching: .any)["scholium.researchInspector"].firstMatch
        let inspectorMode = app.descendants(matching: .any)["scholium.inspectorMode"].firstMatch
        // Native List exposes the enclosing Inspector identifier, not the
        // inner SwiftUI `scholium.related` identifier. Use the real selector.
        XCTAssertFalse(
            inspector.exists && inspectorMode.exists && inspectorMode.value as? String == "Related Material",
            "Opening a Note must not open Related Material by itself.")
        if inspector.exists {
            clickInspectorVisibilityControl()
            XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        }
        selectDocumentMode("Source", in: workspace)
        let editor = app.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == firstSource })
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: .command)
        editor.typeKey(.upArrow, modifierFlags: [])

        // Sample at the completed Source/caret action boundary, outside a waiter:
        // an inverted wait's deadline can interrupt AX snapshot resolution.
        // No native AX receipt proves background completion or continuous absence.
        XCTAssertFalse(inspector.exists, "Caret navigation must not open the Inspector.")
        XCTAssertFalse(
            inspectorMode.exists && inspectorMode.value as? String == "Related Material",
            "Preparation must not select Related Material by itself.")
        XCTAssertEqual(editor.value as? String, firstSource)
        XCTAssertEqual(try Data(contentsOf: firstURL), Data(firstSource.utf8))

        func card(containing wording: String) -> XCUIElement {
            app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                    "scholium.related.card.", wording)
            ).firstMatch
        }
        func waitForMaterial(_ expected: String, excluding unexpected: String) {
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    let match = card(containing: expected)
                    return inspector.exists && inspectorMode.exists && inspectorMode.value as? String == "Related Material"
                        && match.exists && match.isEnabled && !card(containing: unexpected).exists
                }, "Expected only the active writing focus, not adjacent or departed context.")
            XCTAssertFalse(app.descendants(matching: .any)["scholium.related.issue"].firstMatch.exists)
        }

        // Menu entry captures the middle source line. Both adjacent lines are
        // nonempty and include the Topic's distinct vocabulary, so paragraph
        // expansion would visibly admit the unwanted Topic passage as well.
        app.menuBars.menuBarItems["Research"].click()
        let find = app.menuItems["Find Writing References"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(find.isEnabled)
        find.click()
        waitForMaterial(lineWords, excluding: adjacentWords)
        XCTAssertEqual(editor.value as? String, firstSource)
        let longCard = card(containing: "合成界面样本")
        XCTAssertTrue(longCard.waitForExistence(timeout: 5))
        let contextID = "scholium.research.context." + String(longCard.identifier.dropFirst("scholium.related.card.".count))
        let context = app.buttons.matching(NSPredicate(format: "identifier == %@", contextID)).firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.value as? String, "Collapsed")
        XCTAssertTrue(context.label.contains("Show Context"))
        let compactHeight = longCard.frame.height
        XCTAssertGreaterThan(compactHeight, 20)
        XCTAssertLessThanOrEqual(compactHeight, 100, "An ordinary passage preview must stay within a few readable lines.")
        let groupHeader = workspace.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND value == %@", "QA Autosave B,", "Expanded")
        ).firstMatch
        XCTAssertTrue(groupHeader.exists && groupHeader.isHittable)
        let groupHeaderFrame = groupHeader.frame
        let groupedReferences = XCTAttachment(screenshot: workspace.screenshot())
        groupedReferences.name = "Research Inspector compact references — Light"
        groupedReferences.lifetime = .keepAlways
        add(groupedReferences)
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: .command)
        editor.typeKey(.upArrow, modifierFlags: [])

        for expansion in 0..<2 {
            context.click()
            XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
            XCTAssertTrue(context.label.contains("Hide Context"))
            XCTAssertTrue(longCard.label.contains(lateQualification), "Expanded context must retain the paragraph's late qualification.")
            XCTAssertGreaterThan(longCard.frame.height, compactHeight + 20)
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
            XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
            XCTAssertEqual(editor.value as? String, firstSource)
            XCTAssertEqual(try Data(contentsOf: firstURL), Data(firstSource.utf8))
            if expansion == 0 {
                let expanded = XCTAttachment(screenshot: workspace.screenshot())
                expanded.name = "Research Inspector full paragraph context — Light"
                expanded.lifetime = .keepAlways
                add(expanded)
            }
            context.click()
            XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })
            XCTAssertLessThanOrEqual(longCard.frame.height, 100)
        }
        groupHeader.rightClick()
        let openSource = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Open Source")).firstMatch
        XCTAssertTrue(openSource.waitForExistence(timeout: 5))
        for title in ["Link to This Note", "Insert Paragraph Link", "Add to Chat", "Keep Passage"] {
            XCTAssertTrue(
                app.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", title)).firstMatch.exists,
                "The native group context menu must retain \(title).")
        }
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !openSource.exists })
        XCTAssertEqual(groupHeader.frame, groupHeaderFrame, "A cancelled context menu must not reflow the group header.")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        XCTAssertEqual(editor.value as? String, firstSource)

        // The initial caret was at the beginning of the middle source line.
        // Typing after inspecting context and cancelling its menu must still reach
        // that caret; Undo must remain a single native editor transaction.
        let caretProbe = "q"
        app.typeKey(caretProbe, modifierFlags: [])
        let probedSource = firstSource.replacingOccurrences(of: "\n" + lineWords + "\n", with: "\n" + caretProbe + lineWords + "\n")
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == probedSource })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == firstSource })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 8) { (try? Data(contentsOf: firstURL)) == Data(firstSource.utf8) })

        let ordinaryFrame = workspace.frame
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].firstMatch.click()
        resizeProofWindow(workspace, toWidth: 780, height: 640)
        XCTAssertTrue(context.isHittable && groupHeader.isHittable)
        XCTAssertLessThanOrEqual(longCard.frame.height, 100)
        let narrow = XCTAttachment(screenshot: workspace.screenshot())
        narrow.name = "Research Inspector compact references — Dark narrow adapted"
        narrow.lifetime = .keepAlways
        add(narrow)
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
        XCTAssertTrue(longCard.label.contains(lateQualification))
        let narrowExpanded = XCTAttachment(screenshot: workspace.screenshot())
        narrowExpanded.name = "Research Inspector full paragraph context — Dark narrow adapted"
        narrowExpanded.lifetime = .keepAlways
        add(narrowExpanded)
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })
        resizeProofWindow(workspace, toWidth: ordinaryFrame.width, height: ordinaryFrame.height)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Light"].firstMatch.click()
        XCTAssertEqual(editor.value as? String, firstSource)

        // The collection is loaded before Search is ever opened. Choosing a
        // group admits one complete authored alternative, then explicitly
        // clearing it returns to the current writing passage alone.
        XCTAssertFalse(card(containing: alternative).exists)
        let termGroupMenu = app.descendants(matching: .any)["scholium.related.termGroup"].firstMatch
        XCTAssertTrue(termGroupMenu.waitForExistence(timeout: 5))
        func chooseTermGroup(_ name: String) {
            termGroupMenu.click()
            let item = app.menuItems[name].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.click()
        }
        chooseTermGroup(termGroupName)
        XCTAssertTrue(waitUntil(timeout: 30) { card(containing: alternative).exists && card(containing: alternative).isEnabled })
        XCTAssertTrue(card(containing: alternative).label.contains("Matched alternative: " + alternative))
        let termGroupProvenance = app.descendants(matching: .any)["scholium.related.termGroupProvenance"].firstMatch
        XCTAssertTrue(termGroupProvenance.exists)
        let provenanceText = (termGroupProvenance.value as? String) ?? termGroupProvenance.label
        XCTAssertTrue(provenanceText.contains("Original terms: unmatchinglexeme, " + alternative), "Accessible provenance: \(provenanceText)")
        chooseTermGroup("No term group")
        XCTAssertTrue(
            waitUntil(timeout: 30) { card(containing: lineWords).exists && card(containing: lineWords).isEnabled && !card(containing: alternative).exists })
        chooseTermGroup(termGroupName)
        XCTAssertTrue(waitUntil(timeout: 30) { card(containing: alternative).exists && card(containing: alternative).isEnabled })

        // Library browsing retains the active Note's references. Do not use
        // Find or reselect the Inspector to repair context after a role change.
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
        let relatedCards = workspace.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.related.card."))
        let retainedCardIDs = relatedCards.allElementsBoundByIndex.map(\.identifier)
        XCTAssertGreaterThan(retainedCardIDs.count, 1)
        let navigator = workspace.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let roles = [("Topics", "QA Topic.md"), ("Works", "QA Work.md"), ("Analyses", "QA Autosave A.md")]
        func assertRelatedBrowseContext() throws {
            XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
            XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
            XCTAssertEqual(editor.value as? String, firstSource)
            XCTAssertEqual(inspectorMode.value as? String, "Related Material")
            XCTAssertEqual(relatedCards.allElementsBoundByIndex.map(\.identifier), retainedCardIDs)
            XCTAssertTrue(relatedCards.allElementsBoundByIndex.allSatisfy(\.isEnabled))
            XCTAssertEqual(context.value as? String, "Expanded")
            XCTAssertTrue(longCard.label.contains(lateQualification))
            XCTAssertEqual((termGroupProvenance.value as? String) ?? termGroupProvenance.label, provenanceText)
            XCTAssertTrue(card(containing: alternative).exists)
            XCTAssertFalse(app.descendants(matching: .any)["scholium.related.issue"].firstMatch.exists)
            for (url, bytes) in expectedBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        }
        for (role, path) in roles {
            navigator.descendants(matching: .any)[role].firstMatch.click()
            XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.\(path)"].firstMatch.waitForExistence(timeout: 8))
            try assertRelatedBrowseContext()
        }
        // No intermediate waits; owner tests separately force overlapping
        // requests. This journey checks the final native Library destination.
        for (role, _) in roles { navigator.descendants(matching: .any)[role].firstMatch.click() }
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch.waitForExistence(timeout: 8))
        try assertRelatedBrowseContext()
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        navigator.descendants(matching: .any)["Topics"].firstMatch.click()
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(inspector.exists, "Browsing a role must not reopen the hidden Inspector.")
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        try assertRelatedBrowseContext()
        navigator.descendants(matching: .any)["Analyses"].firstMatch.click()
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch.waitForExistence(timeout: 8))
        try assertRelatedBrowseContext()
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })

        // The final line contains BOTH vocabularies; select only its last two
        // words. Ignoring that selection would also retrieve the Analysis.
        // Close first so the keyboard route must also reveal the pane itself.
        clickInspectorVisibilityControl()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.typeKey("j", modifierFlags: [.command, .shift])
        waitForMaterial(adjacentWords, excluding: lineWords)
        XCTAssertTrue(card(containing: alternative).exists, "The chosen group must survive a same-Note writing refresh.")
        XCTAssertEqual(editor.value as? String, firstSource)

        // Request again and leave without waiting for completion. Native timing
        // cannot force an in-flight worker, so this asserts departure isolation,
        // not a deterministic cancellation race or an internal task/cache state.
        app.typeKey("j", modifierFlags: [.command, .shift])
        openNote("QA Autosave B.md", expectedTitle: "QA Autosave B", in: workspace)
        XCTAssertFalse(
            card(containing: adjacentWords).exists,
            "Departing the seed Note must clear its previous material.")
        selectDocumentMode("Source", in: workspace)
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == secondSource })
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        app.typeKey("j", modifierFlags: [.command, .shift])
        waitForMaterial(destinationWords, excluding: adjacentWords)
        XCTAssertFalse(card(containing: lineWords).exists)
        XCTAssertFalse(card(containing: alternative).exists, "Note departure must clear the explicit term-group choice.")

        // The positive result wait above establishes the new Note's foreground
        // action boundary. Check its visible state directly, without an inverted
        // AX polling window or a claim that a late worker was forced to complete.
        XCTAssertFalse(card(containing: adjacentWords).exists)
        XCTAssertTrue(card(containing: destinationWords).exists)
        XCTAssertEqual(editor.value as? String, secondSource)
        XCTAssertEqual(try Data(contentsOf: termGroupsURL), termGroupsData)
        for (url, bytes) in expectedBytes {
            XCTAssertEqual(
                try Data(contentsOf: url), bytes,
                "Retrieval and silent preparation must not rewrite any fixture source.")
        }

        // A retained result can outlive its source. Opening it must explain
        // the failure without claiming navigation or replacing the draft.
        let workBytes = try Data(contentsOf: workURL)
        try FileManager.default.removeItem(at: workURL)
        defer { try? workBytes.write(to: workURL) }
        let unavailableMessage = "This source could not be opened. Use Find Writing References again to refresh the results."
        let unavailableCard = card(containing: destinationWords)
        XCTAssertTrue(unavailableCard.exists && unavailableCard.isEnabled)
        XCTAssertTrue(workspace.frame.contains(unavailableCard.frame))
        // XCTest's automatic scroll-to-visible path cannot find this visible
        // SwiftUI List card after Source focus. Exercise its native hit area.
        unavailableCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let issue = app.descendants(matching: .any)["scholium.operationIssue"].firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[unavailableMessage].exists)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 5))
        XCTAssertEqual(editor.value as? String, secondSource)
        XCTAssertEqual(try Data(contentsOf: secondURL), Data(secondSource.utf8))
        app.buttons["Dismiss"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !issue.exists })
        unavailableCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(issue.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[unavailableMessage].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "scholium.operationIssue").count, 1)
        let unavailableReference = XCTAttachment(screenshot: workspace.screenshot())
        unavailableReference.name = "Unavailable reference retains the writing document"
        unavailableReference.lifetime = .keepAlways
        add(unavailableReference)
        app.buttons["Dismiss"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !issue.exists })
        try workBytes.write(to: workURL)
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        app.typeKey("j", modifierFlags: [.command, .shift])
        waitForMaterial(destinationWords, excluding: adjacentWords)
        XCTAssertEqual(editor.value as? String, secondSource)
        XCTAssertEqual(try Data(contentsOf: workURL), workBytes)
        // The suite's existing tearDown terminates the one QA process and removes
        // only this journey-owned directory, retaining normal failure artifacts.
    }

    /// Changes is the cumulative saved-source UI. Exact receipt identity and
    /// guarded Undo are verified through the real MCP route, not inferred from
    /// the Notifications row or the cumulative comparison.
    @MainActor
    func testAgentChangesShowsExactUpdateAndRestoresOriginalBytes() throws {
        waitForCurrentDocumentSurface()
        let noteURL =
            triptychDirectory
            .appendingPathComponent("02-topics", isDirectory: true)
            .appendingPathComponent("Agent Review.md")
        let originalBytes = try Data(contentsOf: noteURL)
        // WebKit's accessible reading text includes DOM line boundaries. Keep
        // its own exact baseline separate from the authoritative file bytes.
        selectDocumentMode("Source")
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 10))
        let originalAccessibleSource = try XCTUnwrap(sourceEditor.value as? String)
        XCTAssertFalse(originalAccessibleSource.isEmpty)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        selectDocumentMode("Review")
        let status = try callQAMCP(tool: "scholium_workspace_status")
        let triptychID = try XCTUnwrap(status["triptych_id"] as? String)
        let search = try callQAMCP(
            tool: "scholium_search",
            arguments: [
                "triptych_id": triptychID,
                "query": "Reasons",
                "roles": ["topics"],
            ]
        )
        let notes = try XCTUnwrap(search["notes"] as? [String: Any])
        let results = try XCTUnwrap(notes["results"] as? [[String: Any]])
        let result = try XCTUnwrap(
            results.first(where: {
                $0["relative_path"] as? String == "Agent Review.md"
            }))
        let noteID = try XCTUnwrap(result["note_id"] as? String)
        let fingerprint = try XCTUnwrap(result["fingerprint"] as? [String: Any])
        let insertedSentence = "An external Agent added this synthetic sentence for exact comparison. 中文 e\u{301} 👩🏽‍🔬."
        let updatedBody = """
            # Agent Review

            Reasons can guide action without settling every question about value.

            \(insertedSentence)
            """
        let updatedSource = "\u{FEFF}" + updatedBody.replacingOccurrences(of: "\n", with: "\r\n")
        let update = try callQAMCP(
            tool: "scholium_update_note",
            arguments: [
                "triptych_id": triptychID,
                "note_id": noteID,
                "expected_fingerprint": fingerprint,
                "mode": "source",
                "content": updatedSource,
            ]
        )
        let changeID = try XCTUnwrap(update["change_id"] as? String)
        let afterFingerprint = try XCTUnwrap(update["after_fingerprint"] as? [String: Any])
        XCTAssertEqual(update["readback_verified"] as? Bool, true)
        let updatedBytes = try Data(contentsOf: noteURL)
        XCTAssertNotEqual(updatedBytes, originalBytes)
        XCTAssertEqual(updatedBytes, Data(updatedSource.utf8))
        XCTAssertEqual(afterFingerprint["byte_count"] as? Int, updatedBytes.count)
        XCTAssertEqual(
            afterFingerprint["sha256"] as? String,
            SHA256.hash(data: updatedBytes).map { String(format: "%02x", $0) }.joined()
        )

        let documentMode = documentModeControl()
        XCTAssertTrue(documentMode.waitForExistence(timeout: 5))
        let modeBeforeChanges = try XCTUnwrap(documentModeState(documentMode))
        let notifications = app.toolbars.buttons["Open Triptych Notifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.click()
        let notificationPopover = app.popovers.firstMatch
        XCTAssertTrue(notificationPopover.waitForExistence(timeout: 5))
        let pendingChange = notificationPopover.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "scholium.notification.change.", "Agent Review"
            )
        ).firstMatch
        XCTAssertTrue(
            pendingChange.waitForExistence(timeout: 10),
            "The saved external update must appear in the cumulative Changes queue."
        )
        pendingChange.click()
        let comparison = app.descendants(matching: .any)["scholium.changes"].firstMatch
        XCTAssertTrue(comparison.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.documentModeState(self.documentModeControl()) == modeBeforeChanges
            },
            "Opening saved-source Changes must preserve the current Document mode."
        )
        for text in ["Before", "After"] {
            XCTAssertTrue(
                comparison.staticTexts[text].firstMatch.waitForExistence(timeout: 5),
                "Changes did not expose \(text)."
            )
        }
        let inserted = comparison.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@",
                "scholium.changes.row.", "Inserted"
            )
        ).allElementsBoundByIndex
        XCTAssertTrue(
            inserted.contains {
                guard let value = $0.value as? String else { return false }
                return value.utf8.suffix(insertedSentence.utf8.count).elementsEqual(insertedSentence.utf8)
            },
            "The comparison must expose the exact added sentence."
        )
        XCTAssertTrue(inserted.allSatisfy { $0.elementType == .staticText }, "Comparison lines must expose their text semantics.")
        XCTAssertTrue(inserted.allSatisfy { ($0.value as? String)?.hasPrefix("After ") == true }, "Inserted line positions must name the saved revision.")
        let revisionDetails = comparison.disclosureTriangles["Revision Details"].firstMatch
        XCTAssertTrue(revisionDetails.waitForExistence(timeout: 5) && revisionDetails.isHittable)
        XCTAssertEqual(String(describing: revisionDetails.value ?? ""), "0")
        // Target the visible native arrow within AXFrame and verify expansion;
        // XCTest's automatic center click can miss this sheet's disclosure.
        let revisionHeading = comparison.staticTexts["Before"].firstMatch
        let arrow = revisionDetails.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: revisionHeading.frame.minX - revisionDetails.frame.minX + 3, dy: 0))
        arrow.click()
        XCTAssertTrue(waitUntil(timeout: 5) { String(describing: revisionDetails.value ?? "") == "1" })
        for detail in ["No UTF-8 BOM", "UTF-8 BOM present", "Line ending: LF", "Line ending: CRLF"] {
            let format = comparison.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", detail, detail)
            ).firstMatch
            XCTAssertTrue(format.waitForExistence(timeout: 5), "Revision Details must expose \(detail) alongside text changes.")
        }
        XCTAssertTrue(comparison.buttons["scholium.changes.markReviewed"].firstMatch.isEnabled)
        XCTAssertFalse(
            comparison.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium.agentChanges.undo.")
            ).firstMatch.exists,
            "Cumulative Changes must not offer an exact-receipt Undo."
        )
        let beforeUndo = XCTAttachment(screenshot: app.screenshot())
        beforeUndo.name = "Saved-source Changes exact Before and After"
        beforeUndo.lifetime = .keepAlways
        add(beforeUndo)
        comparison.buttons["Close"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !comparison.exists })

        let receiptArguments: [String: Any] = [
            "triptych_id": triptychID, "change_id": changeID, "note_id": noteID,
        ]
        let receipt = try callQAMCP(tool: "scholium_read_change", arguments: receiptArguments)
        let change = try XCTUnwrap(receipt["change"] as? [String: Any])
        XCTAssertEqual(change["change_id"] as? String, changeID)
        XCTAssertEqual(change["note_id"] as? String, noteID)
        XCTAssertEqual(change["operation"] as? String, "update")
        XCTAssertEqual(change["state"] as? String, "confirmed")
        XCTAssertEqual(receipt["ending_revision_state"] as? String, "current")
        XCTAssertEqual(receipt["can_undo"] as? Bool, true)
        let exactComparison = try XCTUnwrap(receipt["comparison"] as? [String: Any])
        XCTAssertEqual(exactComparison["before_fingerprint"] as? NSDictionary, fingerprint as NSDictionary)
        XCTAssertEqual(exactComparison["after_fingerprint"] as? NSDictionary, afterFingerprint as NSDictionary)
        let rows = try XCTUnwrap(exactComparison["rows"] as? [[String: Any]])
        XCTAssertEqual(exactComparison["has_more"] as? Bool, false)
        XCTAssertTrue(rows.contains { $0["kind"] as? String == "added" && $0["text"] as? String == insertedSentence })

        let undo = try callQAMCP(
            tool: "scholium_undo_change",
            arguments: [
                "triptych_id": triptychID, "note_id": noteID,
                "change_id": changeID, "expected_fingerprint": afterFingerprint,
            ]
        )
        XCTAssertEqual(undo["change_id"] as? String, changeID)
        XCTAssertEqual(undo["undone"] as? Bool, true)
        XCTAssertEqual(undo["readback_verified"] as? Bool, true)
        XCTAssertEqual(undo["after_fingerprint"] as? NSDictionary, fingerprint as NSDictionary)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        let undoneReceipt = try callQAMCP(tool: "scholium_read_change", arguments: receiptArguments)
        let undoneChange = try XCTUnwrap(undoneReceipt["change"] as? [String: Any])
        XCTAssertEqual(undoneChange["state"] as? String, "undone")
        XCTAssertEqual(undoneReceipt["can_undo"] as? Bool, false)

        selectDocumentMode("Source")
        let editor = app.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 10) { editor.value as? String == originalAccessibleSource },
            "The Document must converge to the exact restored source after guarded MCP Undo."
        )
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
    }

    /// One native Settings journey verifies per-caller read grants through the
    /// bundled helper while the research window remains behind Settings.
    @MainActor
    func testAgentContextAccessSettingsControlObservationWithoutChangingNotes() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        waitForCurrentDocumentSurface()
        let initialMode = documentModeState(documentModeControl())

        func noteSources() throws -> [String: Data] {
            var sources: [String: Data] = [:]
            for role in ["01-analyses", "02-topics", "03-works"] {
                let root = triptychDirectory.appendingPathComponent(role, isDirectory: true)
                let files = try XCTUnwrap(
                    FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
                for case let file as URL in files {
                    guard file.pathExtension.lowercased() == "md" else { continue }
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    sources[String(file.path.dropFirst(triptychDirectory.path.count + 1))] = try Data(contentsOf: file)
                }
            }
            return sources
        }
        let original = try noteSources()
        XCTAssertEqual(original.count, 500, "This journey uses the complete standard disposable Triptych.")
        let status = try callQAMCP(tool: "scholium_workspace_status")
        let triptychID = try XCTUnwrap(status["triptych_id"] as? String)
        let windows = try XCTUnwrap(status["windows"] as? [[String: Any]])
        XCTAssertEqual(windows.count, 1)
        let windowID = try XCTUnwrap(windows.first?["window_id"] as? String)
        let scope: [String: Any] = ["triptych_id": triptychID, "window_id": windowID]

        let settings = openSettingsForTransactionTest()
        resizeProofWindow(settings, toWidth: 780, height: 640)
        let search = settings.searchFields["scholium.settings.search"]
        func reveal(_ caller: String, _ kind: String, query: String) -> XCUIElement {
            typeCommittedText(query, into: search, in: app)
            selectSettingsSearchResult("agents.context.\(caller).\(kind)", in: settings)
            let control = settings.checkBoxes["scholium.settings.agentContext.\(caller).\(kind)"]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil(timeout: 5) { control.isHittable }, "Search must reveal the sole native access checkbox.")
            return control
        }
        func set(_ control: XCUIElement, to selected: Bool) {
            if selectionControlIsSelected(control) != selected { control.click() }
            XCTAssertTrue(waitUntil(timeout: 3) { self.selectionControlIsSelected(control) == selected })
        }
        func focusSettingsSearch() {
            search.click()
            app.typeKey(.escape, modifierFlags: [])
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: search)
            XCTAssertEqual(
                XCTWaiter.wait(for: [focused], timeout: 5), .completed,
                "The metadata request must run while Settings owns keyboard focus.")
        }

        let chatState = reveal("chat", "state", query: "Chat state access")
        XCTAssertEqual(chatState.label, "Allow Chat agents to inspect Scholium state")
        XCTAssertTrue(selectionControlIsSelected(chatState), "Chat metadata access preserves its existing default.")
        if NSApplication.shared.isFullKeyboardAccessEnabled {
            focusSettingsSearch()
            let focused = NSPredicate(format: "hasKeyboardFocus == true")
            for _ in 0..<16 {
                if focused.evaluate(with: chatState) { break }
                app.typeKey(.tab, modifierFlags: [])
                _ = waitUntil(timeout: 0.2) { focused.evaluate(with: chatState) }
            }
            XCTAssertTrue(
                waitUntil(timeout: 3) { focused.evaluate(with: chatState) },
                "Keyboard navigation must reach the named context-access checkbox.")
            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !self.selectionControlIsSelected(chatState) })
            app.typeKey(" ", modifierFlags: [])
            XCTAssertTrue(
                waitUntil(timeout: 3) { self.selectionControlIsSelected(chatState) },
                "The Space round trip must restore its initial grant.")
        } else {
            let diagnostic = "Context-access checkbox keyboard activation was not verified: host Keyboard navigation is disabled. No host setting was changed."
            print(diagnostic)
            let evidence = XCTAttachment(string: diagnostic)
            evidence.name = "agent-context-keyboard-prerequisite-unavailable"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        set(chatState, to: false)
        let chatText = reveal("chat", "workingText", query: "Chat working text")
        XCTAssertEqual(chatText.label, "Allow Chat agents to read working text")
        XCTAssertFalse(selectionControlIsSelected(chatText), "Working text is opt-in independently of metadata.")
        set(chatText, to: true)
        XCTAssertFalse(selectionControlIsSelected(chatState))

        let externalState = reveal("external", "state", query: "MCP state")
        XCTAssertEqual(externalState.label, "Allow external agents to inspect Scholium state")
        XCTAssertFalse(selectionControlIsSelected(externalState), "External metadata access starts disabled.")
        let externalText = settings.checkBoxes["scholium.settings.agentContext.external.workingText"]
        XCTAssertTrue(externalText.waitForExistence(timeout: 5))
        XCTAssertEqual(externalText.label, "Allow external agents to read working text")
        XCTAssertFalse(selectionControlIsSelected(externalText), "External working text starts disabled.")
        let denied = try callQAMCP(tool: "scholium_observe_workspace", arguments: scope, expectsToolFailure: true)
        XCTAssertEqual(denied["code"] as? String, "permission_denied")

        set(externalState, to: true)
        focusSettingsSearch()
        let snapshot = try callQAMCP(tool: "scholium_observe_workspace", arguments: scope)
        XCTAssertEqual(snapshot["status"] as? String, "ok")
        XCTAssertEqual(snapshot["triptych_id"] as? String, triptychID)
        XCTAssertEqual(snapshot["window_id"] as? String, windowID)
        let tabs = try XCTUnwrap(snapshot["tabs"] as? [String: Any])
        let items = try XCTUnwrap(tabs["items"] as? [[String: Any]])
        let selected = try XCTUnwrap(items.first { $0["selected"] as? Bool == true })
        let note = try XCTUnwrap(selected["note"] as? [String: Any])
        let noteID = try XCTUnwrap(note["note_id"] as? String)
        let revision = try XCTUnwrap(note["revision"] as? [String: Any])
        let fingerprint = try XCTUnwrap(revision["fingerprint"] as? [String: Any])
        let path = try XCTUnwrap(note["relative_path"] as? String)
        XCTAssertEqual(path, "QA Autosave A.md")
        XCTAssertNil(snapshot["text"], "Metadata does not supply Note text.")
        var readScope = scope
        readScope["kind"] = "active_note"
        readScope["note_id"] = noteID
        readScope["expected_fingerprint"] = fingerprint
        readScope["max_utf8"] = 65_536
        let textDenied = try callQAMCP(tool: "scholium_read_context", arguments: readScope, expectsToolFailure: true)
        XCTAssertEqual(textDenied["code"] as? String, "permission_denied")

        set(externalState, to: false)
        let workingText = reveal("external", "workingText", query: "MCP working text")
        set(workingText, to: true)
        XCTAssertFalse(selectionControlIsSelected(externalState))
        focusSettingsSearch()
        let stateDenied = try callQAMCP(tool: "scholium_observe_workspace", arguments: scope, expectsToolFailure: true)
        XCTAssertEqual(stateDenied["code"] as? String, "permission_denied")
        let read = try callQAMCP(tool: "scholium_read_context", arguments: readScope)
        let expectedSource = try XCTUnwrap(original["01-analyses/QA Autosave A.md"])
        XCTAssertEqual(read["text"] as? String, String(decoding: expectedSource, as: UTF8.self))
        let coverage = try XCTUnwrap(read["coverage"] as? [String: Any])
        XCTAssertEqual(coverage["has_more"] as? Bool, false)
        XCTAssertEqual(coverage["end_utf8"] as? Int, expectedSource.count)

        settings.radioButtons["Connection and Chat"].click()
        XCTAssertTrue(chatText.waitForExistence(timeout: 5))
        XCTAssertFalse(selectionControlIsSelected(chatState))
        XCTAssertTrue(selectionControlIsSelected(chatText), "External grants cannot change Chat grants.")
        settings.radioButtons["External Access"].click()
        XCTAssertTrue(workingText.waitForExistence(timeout: 5))
        XCTAssertFalse(selectionControlIsSelected(externalState))
        XCTAssertTrue(selectionControlIsSelected(workingText), "Segment changes retain independent choices.")
        let attachment = XCTAttachment(screenshot: settings.screenshot())
        attachment.name = "agent-context-access-independent-grants-minimum-width"
        attachment.lifetime = .keepAlways
        add(attachment)

        set(workingText, to: false)
        set(reveal("chat", "workingText", query: "Chat working text"), to: false)
        set(reveal("chat", "state", query: "Chat state access"), to: true)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { !settings.exists })
        waitForCurrentDocumentSurface()
        XCTAssertEqual(documentModeState(documentModeControl()), initialMode)
        let after = try noteSources()
        XCTAssertEqual(after.count, original.count)
        let changed = Set(original.keys).union(after.keys).filter { original[$0] != after[$0] }.sorted()
        XCTAssertTrue(changed.isEmpty, "Context access must preserve every Note byte: \(Array(changed.prefix(10)))")

        // One additional appearance capture reuses this journey's restored
        // grants. QA overrides exercise app-owned consumers, not the native
        // system accessibility settings recorded alongside the screenshot.
        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .dark)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["SCHOLIUM_UI_TEST_INCREASE_CONTRAST"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_TRANSPARENCY"] = "1"
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launch()
        waitForCurrentDocumentSurface()
        let darkSettings = openSettingsForTransactionTest()
        resizeProofWindow(darkSettings, toWidth: 780, height: 640)
        let darkSearch = darkSettings.searchFields["scholium.settings.search"]
        let controls: [(caller: String, kind: String, query: String, label: String, selected: Bool)] = [
            ("chat", "state", "Chat state access", "Allow Chat agents to inspect Scholium state", true),
            ("chat", "workingText", "Chat working text", "Allow Chat agents to read working text", false),
            ("external", "state", "MCP state", "Allow external agents to inspect Scholium state", false),
            ("external", "workingText", "MCP working text", "Allow external agents to read working text", false),
        ]
        for expected in controls {
            typeCommittedText(expected.query, into: darkSearch, in: app)
            selectSettingsSearchResult("agents.context.\(expected.caller).\(expected.kind)", in: darkSettings)
            let control = darkSettings.checkBoxes["scholium.settings.agentContext.\(expected.caller).\(expected.kind)"]
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertEqual(control.label, expected.label)
            XCTAssertTrue(waitUntil(timeout: 5) { control.isHittable })
            XCTAssertEqual(selectionControlIsSelected(control), expected.selected)
        }
        typeCommittedText("MCP state", into: darkSearch, in: app)
        selectSettingsSearchResult("agents.context.external.state", in: darkSettings)
        let native = NSWorkspace.shared
        let adaptationDiagnostic =
            "Dark QA capture; app-owned Increase Contrast, Reduce Transparency and Reduce Motion overrides enabled. "
            + "Native host flags: increaseContrast=\(native.accessibilityDisplayShouldIncreaseContrast), "
            + "reduceTransparency=\(native.accessibilityDisplayShouldReduceTransparency), reduceMotion=\(native.accessibilityDisplayShouldReduceMotion). "
            + "Overrides do not prove native checkbox adaptation."
        print(adaptationDiagnostic)
        let nativeEvidence = XCTAttachment(string: adaptationDiagnostic)
        nativeEvidence.name = "agent-context-native-adaptation-observations"
        nativeEvidence.lifetime = .keepAlways
        add(nativeEvidence)
        let darkAttachment = XCTAttachment(screenshot: darkSettings.screenshot())
        darkAttachment.name = "agent-context-access-dark-minimum-width"
        darkAttachment.lifetime = .keepAlways
        add(darkAttachment)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { !darkSettings.exists })
    }

    private func callQAMCP(
        tool: String,
        arguments: [String: Any] = [:],
        expectsToolFailure: Bool = false
    ) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable =
            repositoryRoot
            .appendingPathComponent(".build/qa-swiftpm/debug/ScholiumAgentHelper")
        let process = Process()
        process.executableURL = executable
        process.arguments = ["mcp", "serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["SCHOLIUM_HOME"] = homeDirectory.path
        environment["CFFIXED_USER_HOME"] = homeDirectory.path
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": tool, "arguments": arguments],
        ]
        var requestData = try JSONSerialization.data(withJSONObject: request)
        requestData.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: requestData)
        try input.fileHandleForWriting.close()
        let responseData = try output.fileHandleForReading.readToEnd() ?? Data()
        let errorData = try error.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: errorData, as: UTF8.self)
        )
        let responseLine = try XCTUnwrap(
            responseData.split(separator: 0x0A).first
        )
        let response = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseLine) as? [String: Any]
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, expectsToolFailure)
        return try XCTUnwrap(result["structuredContent"] as? [String: Any])
    }

    @MainActor
    func testInspectorLinksSelectIncomingAndOutgoingDirections() throws {
        app.terminate()
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let topicURL = triptychDirectory.appendingPathComponent("02-topics/QA Topic.md")
        let selectionProbe = "retainedselectionprobe"
        let lateQualification = "Late qualification: this authored connection is not evidence of agreement. 最后的限定仍须完整可读。"
        let longPassage =
            "链接上下文合成样本。A reader should be able to inspect the complete argument before treating the late link as a useful connection. "
            + "The opening establishes a question, the middle describes a possible comparison, and the source keeps both without inferring support or opposition. "
            + "Only after that context does [[QA Autosave A|contextlinkprobe]] appear. The final sentence matters even when a compact preview cannot display it. "
            + lateQualification
        // Enrich only this journey's existing Notes, while its QA app is down.
        // Preserve the original annotated occurrences and the 500-Note count.
        try write(source(at: noteURL) + "\n\n" + selectionProbe, to: noteURL)
        try write(source(at: topicURL) + "\n\n" + longPassage, to: topicURL)
        let originalBytes = try Data(contentsOf: noteURL)
        let originalSource = try source(at: noteURL)
        let topicBytes = try Data(contentsOf: topicURL)
        app.launchArguments += ["-colorScheme", "light"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 45))
        waitForCurrentDocumentSurface()
        let workspace = app.windows["scholium-main-\(sessionID.uuidString)"].firstMatch
        focusWorkspaceWindow(workspace)
        selectDocumentMode("Source", in: workspace)
        let editor = app.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == originalSource })
        _ = selectResearchInspectorDirection("outgoing")
        let orderedModeControl = workspace.descendants(matching: .any)["scholium.inspectorMode"].firstMatch
        let relatedMode = orderedModeControl.descendants(matching: .any)["Related Material"].firstMatch
        let linksMode = orderedModeControl.descendants(matching: .any)["Links"].firstMatch
        XCTAssertTrue(relatedMode.exists && linksMode.exists)
        XCTAssertLessThan(relatedMode.frame.minX, linksMode.frame.minX)
        _ = selectResearchInspectorMode("related")
        XCTAssertEqual(orderedModeControl.value as? String, "Related Material")
        _ = selectResearchInspectorMode("links")
        XCTAssertEqual(orderedModeControl.value as? String, "Links")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, originalSource)
        let outgoing = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.links.occurrence."
            )
        ).firstMatch
        XCTAssertTrue(outgoing.waitForExistence(timeout: 8))

        for retiredHeading in [
            "LINKED ANALYSES", "LINKED SOURCES", "LINKED TOPICS", "LINKED WORKS",
        ] {
            XCTAssertFalse(app.staticTexts[retiredHeading].exists)
        }

        _ = selectResearchInspectorDirection("incoming")
        let incoming = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.links.occurrence."
            )
        ).firstMatch
        XCTAssertTrue(incoming.waitForExistence(timeout: 8))
        let longIncoming = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "scholium.links.occurrence.", "contextlinkprobe")
        ).firstMatch
        XCTAssertTrue(longIncoming.waitForExistence(timeout: 5))
        let contextID = "scholium.research.context." + String(longIncoming.identifier.dropFirst("scholium.links.occurrence.".count))
        let context = app.buttons.matching(NSPredicate(format: "identifier == %@", contextID)).firstMatch
        XCTAssertTrue(context.waitForExistence(timeout: 5))
        XCTAssertEqual(context.value as? String, "Collapsed")
        XCTAssertTrue(context.label.contains("Show Context"))
        let compactHeight = longIncoming.frame.height
        XCTAssertGreaterThan(compactHeight, 20)
        XCTAssertLessThanOrEqual(compactHeight, 100, "Links must share the compact three-line passage presentation.")
        let compactLinks = XCTAttachment(screenshot: workspace.screenshot())
        compactLinks.name = "Research Inspector compact incoming links — Light"
        compactLinks.lifetime = .keepAlways
        add(compactLinks)
        editor.click()
        editor.typeKey(.end, modifierFlags: .command)
        editor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        for expansion in 0..<2 {
            context.click()
            XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
            XCTAssertTrue(context.label.contains("Hide Context"))
            XCTAssertTrue(longIncoming.label.contains(lateQualification), "The full paragraph must retain the qualification after the late link.")
            XCTAssertGreaterThan(longIncoming.frame.height, compactHeight + 20)
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
            XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
            XCTAssertEqual(editor.value as? String, originalSource)
            XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
            XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
            if expansion == 0 {
                let expandedLinks = XCTAttachment(screenshot: workspace.screenshot())
                expandedLinks.name = "Research Inspector full incoming link context — Light"
                expandedLinks.lifetime = .keepAlways
                add(expandedLinks)
            }
            context.click()
            XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })
            XCTAssertLessThanOrEqual(longIncoming.frame.height, 100)
        }
        let group = workspace.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.links.group.")
        ).firstMatch
        XCTAssertTrue(group.exists && group.isHittable)
        let groupFrame = group.frame
        group.rightClick()
        let openLinkedNote = app.menuItems["Open Linked Note"].firstMatch
        XCTAssertTrue(openLinkedNote.waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["Keep Passage"].firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !openLinkedNote.exists })
        XCTAssertEqual(group.frame, groupFrame)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        XCTAssertEqual(editor.value as? String, originalSource)
        // Context and its cancelled menu must preserve the editor's selection.
        // Native replacement and Undo prove it without a private editor hook.
        let replacement = "q"
        app.typeKey(replacement, modifierFlags: [])
        let replacedSource = String(originalSource.dropLast(selectionProbe.count)) + replacement
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == replacedSource })
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 5) { editor.value as? String == originalSource })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 8) { (try? Data(contentsOf: noteURL)) == originalBytes })
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !incoming.exists })
        group.click()
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        let field = app.searchFields["scholium.links.search"].firstMatch
        XCTAssertTrue(field.exists)
        field.click()
        field.typeText("QA Topic")
        XCTAssertEqual(field.value as? String, "QA Topic")
        XCTAssertTrue(longIncoming.waitForExistence(timeout: 5))
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
        let occurrences = workspace.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.links.occurrence."))
        let retainedOccurrenceIDs = occurrences.allElementsBoundByIndex.map(\.identifier)
        let retainedGroupID = group.identifier
        let inspector = workspace.descendants(matching: .any)["scholium.researchInspector"].firstMatch
        let inspectorMode = workspace.descendants(matching: .any)["scholium.inspectorMode"].firstMatch
        let navigator = workspace.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let roles = [("Topics", "QA Topic.md"), ("Works", "QA Work.md"), ("Analyses", "QA Autosave A.md")]
        XCTAssertGreaterThan(retainedOccurrenceIDs.count, 1)
        func assertLinksBrowseContext(collapsed: Bool) throws {
            XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
            XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
            XCTAssertEqual(editor.value as? String, originalSource)
            XCTAssertEqual(inspectorMode.value as? String, "Links")
            XCTAssertEqual(field.value as? String, "QA Topic")
            XCTAssertFalse(workspace.descendants(matching: .any)["scholium.researchProjectionFreshness"].firstMatch.exists)
            XCTAssertTrue(group.exists)
            XCTAssertEqual(group.identifier, retainedGroupID)
            if collapsed {
                XCTAssertFalse(incoming.exists, "Role browsing must not reopen the collapsed link group.")
            } else {
                XCTAssertEqual(occurrences.allElementsBoundByIndex.map(\.identifier), retainedOccurrenceIDs)
                XCTAssertEqual(context.value as? String, "Expanded")
                XCTAssertTrue(longIncoming.label.contains(lateQualification))
            }
            XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
            XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
        }
        for (role, path) in roles {
            navigator.descendants(matching: .any)[role].firstMatch.click()
            XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.\(path)"].firstMatch.waitForExistence(timeout: 8))
            try assertLinksBrowseContext(collapsed: false)
        }
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })
        group.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !incoming.exists })
        for (role, _) in roles { navigator.descendants(matching: .any)[role].firstMatch.click() }
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch.waitForExistence(timeout: 8))
        try assertLinksBrowseContext(collapsed: true)
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        navigator.descendants(matching: .any)["Topics"].firstMatch.click()
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(inspector.exists, "Browsing a role must not reopen the hidden Inspector.")
        clickInspectorVisibilityControl(in: workspace)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        try assertLinksBrowseContext(collapsed: true)
        navigator.descendants(matching: .any)["Analyses"].firstMatch.click()
        XCTAssertTrue(workspace.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch.waitForExistence(timeout: 8))
        try assertLinksBrowseContext(collapsed: true)
        group.click()
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertEqual(occurrences.allElementsBoundByIndex.map(\.identifier), retainedOccurrenceIDs)
        typeCommittedText("no-such-fixture-link", into: field, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.connections.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(incoming.exists)
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "")
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        // A filter hit after the authored link must be readable without
        // changing the occurrence identity or its source-opening action.
        let filteredOccurrenceID = longIncoming.identifier
        let filteredOccurrence = workspace.buttons.matching(NSPredicate(format: "identifier == %@", filteredOccurrenceID)).firstMatch
        let linkCenteredPreview = filteredOccurrence.label
        XCTAssertTrue(linkCenteredPreview.contains("contextlinkprobe"))
        field.click()
        field.typeText("Late qualification")
        XCTAssertEqual(field.value as? String, "Late qualification")
        XCTAssertTrue(waitUntil(timeout: 5) { filteredOccurrence.exists && filteredOccurrence.label.contains("Late qualification") })
        XCTAssertEqual(filteredOccurrence.identifier, filteredOccurrenceID)
        XCTAssertEqual(context.value as? String, "Collapsed")
        XCTAssertLessThanOrEqual(filteredOccurrence.frame.height, 100)
        XCTAssertTrue(filteredOccurrence.isHittable, "The filter-relevant passage must be visibly reachable in its compact row.")
        let filteredLinks = XCTAttachment(screenshot: workspace.screenshot())
        filteredLinks.name = "Research Inspector compact link context follows Find in Links"
        filteredLinks.lifetime = .keepAlways
        add(filteredLinks)
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Expanded" })
        XCTAssertTrue(filteredOccurrence.label.contains("contextlinkprobe"))
        XCTAssertTrue(filteredOccurrence.label.contains(lateQualification))
        XCTAssertEqual(documentTitle(in: workspace), "QA Autosave A")
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, originalSource)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
        context.click()
        XCTAssertTrue(waitUntil(timeout: 5) { context.value as? String == "Collapsed" })
        XCTAssertTrue(filteredOccurrence.label.contains("Late qualification"))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "")
        XCTAssertTrue(waitUntil(timeout: 5) { filteredOccurrence.label == linkCenteredPreview })
        XCTAssertEqual(filteredOccurrence.identifier, filteredOccurrenceID)
        XCTAssertEqual(context.value as? String, "Collapsed")
        XCTAssertLessThanOrEqual(filteredOccurrence.frame.height, 100)
        let links = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        links.name = "Research Inspector incoming links"
        links.lifetime = .keepAlways
        add(links)
        XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
        // Passage activation remains separate from showing context and still
        // opens its source Note in the retained Document mode.
        field.click()
        field.typeText("QA Topic")
        XCTAssertEqual(field.value as? String, "QA Topic")
        longIncoming.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", timeout: 10))
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
        XCTAssertTrue(waitUntil(timeout: 5) { field.value as? String == "" }, "A different Note must not inherit A's Links query.")
        let back = workspace.toolbars.buttons["Back"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { back.exists && back.isEnabled })
        back.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: workspace, timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == originalSource })
        XCTAssertEqual(field.value as? String, "QA Topic", "Back must restore the original Note's Links location.")
        XCTAssertEqual(occurrences.allElementsBoundByIndex.map(\.identifier), retainedOccurrenceIDs)
        XCTAssertEqual(documentModeState(documentModeControl(in: workspace)), "Source")
        XCTAssertEqual(editor.value as? String, originalSource)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        XCTAssertEqual(try Data(contentsOf: topicURL), topicBytes)
    }

    /// The default final QA route. It keeps one isolated application process
    /// alive for the complete journey so the researcher does not see a new QA
    /// app open for every assertion group.
    @MainActor
    func testStorageUnavailableRetriesWithoutConstructingWorkspace() throws {
        let unavailable = app.descendants(matching: .any)[
            "scholium.storageUnavailable"
        ]
        let retry = app.buttons["Retry"]
        let details = app.buttons["Details"].firstMatch
        let detailsContent = app.descendants(matching: .any)[
            "scholium.storageUnavailable.details"
        ]
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let window = app.windows.firstMatch

        XCTAssertTrue(unavailable.exists)
        XCTAssertTrue(app.staticTexts["Storage Unavailable"].exists)
        XCTAssertTrue(retry.exists)
        XCTAssertTrue(retry.isEnabled)
        XCTAssertTrue(app.buttons["Quit"].exists)
        XCTAssertFalse(renderedDocument.exists)
        XCTAssertFalse(detailsContent.exists)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height >= 190
                    && window.frame.height <= 320
            },
            "The collapsed storage-recovery window must fit its compact content."
        )
        let collapsedFrame = window.frame

        XCTAssertTrue(details.exists)
        XCTAssertEqual(details.value as? String, "Collapsed")
        details.click()
        XCTAssertEqual(details.value as? String, "Expanded")
        XCTAssertTrue(detailsContent.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height > collapsedFrame.height
                    && window.frame.height <= 380
            },
            "Expanding storage details must grow only the compact recovery window."
        )

        app.menuBars.menuBarItems["File"].click()
        let newNote = app.menuItems["New Note"].firstMatch
        if newNote.exists {
            XCTAssertFalse(newNote.isEnabled)
        }
        app.typeKey(.escape, modifierFlags: [])

        app.staticTexts["Storage Unavailable"].click()
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                unavailable.exists
                    && retry.isEnabled
                    && !detailsContent.exists
                    && window.frame.width >= 480
                    && window.frame.width <= 560
                    && window.frame.height >= 190
                    && window.frame.height <= 320
            },
            "A failed Retry must remount the same compact recovery state."
        )

        let blocker = homeDirectory.appendingPathComponent("ApplicationSupport")
        try FileManager.default.removeItem(at: blocker)
        app.staticTexts["Storage Unavailable"].click()
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(
            waitUntil(timeout: 90) { self.documentSurfaceIsUsable() },
            "The default Retry action did not enter the Workspace after storage was repaired."
        )
        XCTAssertFalse(unavailable.exists)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                window.frame.width >= 1_200
                    && window.frame.height >= 650
            },
            "Successful Retry must restore the workspace frame after compact recovery."
        )
    }

    @MainActor
    func testSharedSearchMatchesAnAliasAcrossTheTriptych() throws {
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Advanced Search…"].click()
        let emptyAdvanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(emptyAdvanced.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyAdvanced.descendants(matching: .any)["scholium.searchReady"].waitForExistence(timeout: 5))
        XCTAssertFalse(emptyAdvanced.staticTexts["Search Index Unavailable"].exists)
        emptyAdvanced.buttons[XCUIIdentifierCloseWindow].click()
        let field = app.searchFields["scholium.searchField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("Triptych", in: app)
        field.click()
        field.typeText("Normative QA Nexus")
        XCTAssertEqual(field.value as? String, "Normative QA Nexus")
        XCTAssertTrue(searchResult(named: "QA Topic").waitForExistence(timeout: 8))
        field.buttons.firstMatch.click()
        field.menuItems["Advanced Search…"].click()
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let advancedField = advanced.searchFields["scholium.searchField"]
        XCTAssertEqual(advancedField.value as? String, "Normative QA Nexus")
        advancedField.buttons.firstMatch.click()
        XCTAssertFalse(advancedField.menuItems["Advanced Search…"].exists)
        app.typeKey(.escape, modifierFlags: [])
        let result = advanced.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "QA Topic,")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", timeout: 8))
        XCTAssertTrue(advanced.exists)
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Advanced Search…"].click()
        advanced.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !advanced.exists })
        XCTAssertTrue(app.descendants(matching: .any)["scholium.noteList"].exists)
    }

    @MainActor
    func testPortableFolderPanelRejectsWrongExactFolderAndRecovers() throws {
        let wrongFolder = testDirectory.appendingPathComponent(
            "Wrong Portable Folder",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: wrongFolder,
            withIntermediateDirectories: true
        )

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.settings.root"]
                .waitForExistence(timeout: 10)
        )
        let settingsWindow = app.windows.matching(
            identifier: "com_apple_SwiftUI_Settings_window"
        ).firstMatch
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        selectSettingsCategory("workspace", in: settingsWindow)
        XCTAssertTrue(
            settingsWindow.descendants(matching: .any)[
                "scholium.portableControlAccess"
            ].waitForExistence(timeout: 5))

        authorizePortableFolder(wrongFolder, in: settingsWindow)
        let selectionError = settingsWindow.staticTexts[
            "Choose the folder containing Works shown above."
        ]
        XCTAssertTrue(selectionError.waitForExistence(timeout: 5))

        authorizePortableFolder(triptychDirectory, in: settingsWindow)
        XCTAssertTrue(waitUntil(timeout: 5) { !selectionError.exists })
    }

    @MainActor
    func testRestoreAccessFolderSelectionUsesScenePresenter() {
        let restoreSheet = app.sheets.firstMatch
        XCTAssertTrue(
            restoreSheet.staticTexts["Restore Access"].waitForExistence(timeout: 8),
            "The isolated recovery route must present the real Restore Access sheet."
        )

        let chooseFolder = restoreSheet.buttons["Choose Folder…"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 5))
        chooseFolder.click()

        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Restore Access must present the shared native Open panel from its owning sheet."
        )
        XCTAssertFalse(
            restoreSheet.staticTexts[
                "File selection is unavailable in this window."
            ].exists
        )

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            restoreSheet.staticTexts["Restore Access"].exists,
            "Cancelling folder selection must leave Restore Access available for retry."
        )
    }

    @MainActor
    func testBootstrapCreatePreservesDraftAfterDestinationConflictAndOpensWorkspace() throws {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.state == .notRunning })

        let cleanHome = testDirectory.appendingPathComponent("create-home", isDirectory: true)
        let parent = testDirectory.appendingPathComponent("New Triptychs", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let existingName = "Existing Triptych"
        let existingRoot = parent.appendingPathComponent(existingName, isDirectory: true)
        try FileManager.default.createDirectory(at: cleanHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingRoot, withIntermediateDirectories: true)
        let sentinel = existingRoot.appendingPathComponent("Preserve.md")
        let sentinelBytes = Data("# Existing research\nDo not replace this folder.\n".utf8)
        try sentinelBytes.write(to: sentinel)

        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = ""
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = parent.path
        app.launch()

        let createNew = app.buttons["scholium.bootstrap.createNew"]
        XCTAssertTrue(createNew.waitForExistence(timeout: 15))
        let welcomeShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        welcomeShot.name = "Bootstrap welcome"
        welcomeShot.lifetime = .keepAlways
        add(welcomeShot)
        createNew.click()
        let createPage = app.descendants(matching: .any)["scholium.bootstrap.createStructure"]
        XCTAssertTrue(createPage.waitForExistence(timeout: 5))
        let complete = app.buttons["Create and Open"]
        XCTAssertTrue(complete.exists)
        XCTAssertFalse(complete.isEnabled)
        let name = app.textFields["scholium.triptychName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try paste(existingName, into: name)
        chooseSetupFolder(parent, role: "Location")
        XCTAssertTrue(app.staticTexts["Proposed Structure"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "value == %@ OR label == %@", existingRoot.path(percentEncoded: false), existingRoot.path(percentEncoded: false))
            ).firstMatch.exists)
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        let error = app.descendants(matching: .any)["scholium.bootstrap.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(createPage.exists, "A destination conflict must retain the setup form.")
        XCTAssertEqual(name.value as? String, existingName)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", parent.path(percentEncoded: false), parent.path(percentEncoded: false)))
                .firstMatch.exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "value == %@ OR label == %@", existingRoot.path(percentEncoded: false), existingRoot.path(percentEncoded: false))
            ).firstMatch.exists)
        XCTAssertTrue(complete.isEnabled, "A failed creation must permit correction and retry.")
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existingRoot.path), ["Preserve.md"])
        XCTAssertFalse(app.splitGroups["scholium.workspaceSplitView"].exists)
        let errorShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        errorShot.name = "Bootstrap create with retained error"
        errorShot.lifetime = .keepAlways
        add(errorShot)

        let newName = "Created Triptych"
        let newRoot = parent.appendingPathComponent(newName, isDirectory: true)
        try paste(newName, into: name)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "value == %@ OR label == %@", newRoot.path(percentEncoded: false), newRoot.path(percentEncoded: false))
            ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value == %@ OR label == %@", parent.path(percentEncoded: false), parent.path(percentEncoded: false)))
                .firstMatch.exists, "Renaming must retain the selected parent.")
        complete.click()
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                self.app.windows.count == 1
                    && self.app.splitGroups["scholium.workspaceSplitView"].exists
                    && self.app.descendants(matching: .any)["scholium.librarySurface"].exists
                    && !self.app.descendants(matching: .any)["scholium.loadingOverlay"].exists
                    && !self.app.descendants(matching: .any)["scholium.bootstrap"].exists
            }, "Create and Open must directly replace Bootstrap with the new workspace."
        )
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: newRoot.path)),
            Set(["Analyses", "Topics", "Works", ".scholium"])
        )
        for directory in ["Analyses", "Topics", "Works", ".scholium"] {
            let values = try newRoot.appendingPathComponent(directory)
                .resourceValues(forKeys: [.isDirectoryKey])
            XCTAssertEqual(values.isDirectory, true)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: newRoot.appendingPathComponent(".scholium/manifest.json").path
            ))
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelBytes)
    }

    @MainActor
    func testCleanAccountConfiguresAndRestoresACompleteTriptych() throws {
        app.terminate()
        XCTAssertTrue(
            waitUntil(timeout: 10) { self.app.state == .notRunning },
            "The fixture workspace must terminate before the clean-account launch."
        )

        let cleanHome = testDirectory.appendingPathComponent("clean-home", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanHome, withIntermediateDirectories: true)

        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = ""
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = triptychDirectory.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = String(
            Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let setupSurfaces = app.descendants(matching: .any)
            .matching(identifier: "scholium.bootstrap")
        let setup = setupSurfaces.firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertEqual(
            app.windows.count,
            1,
            "First launch must present one setup surface, not root setup plus a duplicate sheet."
        )
        XCTAssertTrue(app.staticTexts["Welcome to Scholium"].exists)
        let setupFrame = app.windows.firstMatch.frame
        XCTAssertEqual(
            setupFrame.width,
            QABootstrapMetricContract.preferredWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "Bootstrap's preferred width is an initial size, not a minimum."
        )
        XCTAssertFalse(app.splitGroups["scholium.workspaceSplitView"].exists)
        XCTAssertFalse(app.buttons["Show Sidebar"].exists)
        XCTAssertFalse(app.buttons["Hide Sidebar"].exists)
        XCTAssertFalse(app.buttons["Show Research Inspector"].exists)
        XCTAssertFalse(app.buttons["Hide Research Inspector"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.bootstrap.welcome"].exists
        )
        let connectExisting = app.buttons["scholium.bootstrap.connectExisting"]
        XCTAssertTrue(connectExisting.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["scholium.bootstrap.createNew"].exists)
        connectExisting.click()
        let existingFolders = app.descendants(matching: .any)["scholium.bootstrap.existingFolders"]
        XCTAssertTrue(existingFolders.waitForExistence(timeout: 5))
        let complete = app.buttons["Connect and Open"]
        XCTAssertTrue(complete.exists)
        XCTAssertFalse(complete.isEnabled)

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        chooseSetupFolder(analyses, role: "Analyses")
        chooseSetupFolder(topics, role: "Topics")
        chooseSetupFolder(works, role: "Works")
        XCTAssertTrue(existingFolders.exists)

        // Reopening and cancelling one picker must retain all three selections.
        app.buttons["scholium.bootstrap.chooseAnalyses"].click()
        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
        XCTAssertTrue(existingFolders.exists)

        // Back revisits the two direct choices without resetting the draft.
        app.buttons["Back"].click()
        XCTAssertTrue(connectExisting.waitForExistence(timeout: 5))
        connectExisting.click()
        XCTAssertTrue(existingFolders.waitForExistence(timeout: 5))
        authorizePortableFolder(triptychDirectory)
        resizeProofWindow(app.windows.firstMatch, toWidth: 480)
        let connectShot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        connectShot.name = "Bootstrap connected folders at minimum width"
        connectShot.lifetime = .keepAlways
        add(connectShot)
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(complete.isEnabled, "Cancelled selection and Back must retain the complete draft.")
        complete.click()

        let analysesControl = app.descendants(matching: .any)[
            "Analyses"
        ]
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        let loadingOverlay = app.descendants(matching: .any)["scholium.loadingOverlay"]
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                analysesControl.exists && librarySurface.exists && !loadingOverlay.exists
            }, "Completing first-run setup must finish opening the Triptych and dismiss loading.")
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.app.windows.count == 1
                    && !self.app.descendants(matching: .any)["scholium.bootstrap"].exists
                    && self.app.splitGroups["scholium.workspaceSplitView"].exists
            }, "Successful setup must replace Bootstrap with one configured workspace window.")
        let workspaceWindow = app.windows.firstMatch
        if let visibleScreenWidth = NSScreen.main?.visibleFrame.width,
            visibleScreenWidth >= QAWorkspaceMetricContract.preferredWidth
        {
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    abs(
                        workspaceWindow.frame.width
                            - QAWorkspaceMetricContract.preferredWidth
                    ) <= QAWorkspaceMetricContract.frameTolerance
                })
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        let workspaceFrame = workspaceWindow.frame
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychSetup"].exists,
            "Completing first-run setup must close Bootstrap instead of presenting it over the workspace."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
                .waitForExistence(timeout: 15)
        )
        clickLibraryRow("QA Autosave A.md")
        waitForCurrentDocumentSurface()
        XCTAssertEqual(workspaceWindow.frame, workspaceFrame)

        XCTAssertEqual(workspaceWindow.frame, workspaceFrame)

        let manifest = triptychDirectory.appendingPathComponent(".scholium/manifest.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifest.path),
            "Expected setup to create only its portable control manifest beside Works."
        )

        app.terminate()
        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = ""
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.descendants(matching: .any)["Analyses"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertFalse(app.descendants(matching: .any)["scholium.triptychSetup"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
                .waitForExistence(timeout: 15)
        )

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.settings.root"]
                .waitForExistence(timeout: 10)
        )
        let nameField = app.descendants(matching: .any)["scholium.triptychName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        try paste("QA Renamed Triptych", into: nameField)
        let saveTriptych = app.buttons["Save Triptych"]
        XCTAssertTrue(saveTriptych.waitForExistence(timeout: 5))
        XCTAssertTrue(saveTriptych.isEnabled)
        saveTriptych.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                !self.app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "manifest.json")
                ).firstMatch.exists
            })
        let registryURL =
            cleanHome
            .appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                (try? String(contentsOf: registryURL, encoding: .utf8))?
                    .contains("QA Renamed Triptych") == true
            })
    }

    @MainActor
    func testDocumentModesInspectorAndSearchAreKeyboardReachable() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["View"].click()
        let documentModeMenu = app.menuItems["Document Mode"].firstMatch
        XCTAssertTrue(documentModeMenu.waitForExistence(timeout: 3))
        documentModeMenu.hover()
        XCTAssertTrue(app.menuItems["Edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Source"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let editor = enterLivePreview()
        editor.typeKey(.end, modifierFlags: [.command])
        try setPasteboardText("\nshortcut-probe")
        editor.typeKey("v", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (editor.value as? String ?? "").contains("shortcut-probe")
            })
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        app.typeKey("i", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (editor.value as? String ?? "").contains("*shortcut-probe*")
            }, "Command-I must apply Markdown emphasis exactly once from the focused editor.")
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let value = editor.value as? String ?? ""
                return value.contains("shortcut-probe") && !value.contains("*shortcut-probe*")
            }, "One Undo must undo exactly one shortcut transaction.")
        selectDocumentMode("Review")
        selectDocumentMode("Edit")
        selectDocumentMode("Review")

        let inspector = inspectorVisibilityControl()
        XCTAssertTrue(inspector.exists)

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.windows["scholium.advancedSearchWindow"].waitForExistence(timeout: 5))
        // Advanced Search directly focuses its field.
        // Paste without clicking to prove the shortcut actually moved focus.
        try setPasteboardText("shortcut-probe")
        app.typeKey("v", modifierFlags: [.command])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSearchOpensTheSelectedResultFromTheKeyboard() throws {
        waitForCurrentDocumentSurface()
        openNote("QA Autosave B.md", expectedTitle: "QA Autosave B", in: app.windows.firstMatch)
        selectDocumentMode("Review")

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        let result = searchResult(named: "QA Autosave A")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("This Vault", in: app)
        typeCommittedText("title:\"QA Autosave A\" body:synthetic", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        field.click()
        let completion = advanced.buttons["body:synthetic, Search term"].firstMatch
        XCTAssertTrue(completion.waitForExistence(timeout: 8))
        field.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(completion.isSelected)
        field.typeKey(.downArrow, modifierFlags: [])
        XCTAssertFalse(completion.isSelected)
        field.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(completion.isSelected, "Up from the first result returns to query suggestions.")
        field.typeKey(.downArrow, modifierFlags: [])

        let selectionAttachment = XCTAttachment(screenshot: advanced.screenshot())
        selectionAttachment.name = "Search editorial selection"
        selectionAttachment.lifetime = .keepAlways
        add(selectionAttachment)

        // An external change in this disposable Triptych adds another match.
        // The replacement response must retain the existing keyboard target.
        try write(
            "---\ntitle: QA Autosave A companion\n---\n\nSynthetic refresh fixture.\n",
            to: triptychDirectory.appendingPathComponent("01-analyses/QA Autosave B.md"))
        XCTAssertTrue(searchResult(named: "QA Autosave B").waitForExistence(timeout: 15))
        field.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(advanced.exists, "Opening a result retains the advanced search window.")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        let renderedDocument = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.renderedDocument.")
        ).firstMatch
        XCTAssertTrue(
            renderedDocument.waitForExistence(timeout: 10),
            "The selected Search result did not finish revealing its rendered match."
        )
        let mode = documentModeControl()
        XCTAssertEqual(documentModeState(mode), "Review")
        XCTAssertFalse(app.descendants(matching: .any)["Markdown source editor"].exists)
    }

    @MainActor
    func testSearchOffersAnIndexBackedLexicalCompletionWhileTyping() throws {
        waitForCurrentDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        typeCommittedText("syn", into: field, in: app)
        let suggestion = advanced.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "synthetic,")
        ).firstMatch
        XCTAssertTrue(
            suggestion.waitForExistence(timeout: 20),
            "Search completion must use the committed index vocabulary while typing a partial term."
        )
        suggestion.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (field.value as? String) == "synthetic"
            },
            "Accepting a lexical completion must replace only the active query token."
        )

        typeCommittedText("paragraph:(syn", into: field, in: app)
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "paragraph:(synthetic" })
        field.typeText(") AND title:\"QA Autosave A\"")
        XCTAssertTrue(searchResult(named: "QA Autosave A").waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "paragraph:(synthetic) AND title:\"QA Autosave A\"")

        typeCommittedText("\"syn", into: field, in: app)
        let quotedSuggestion = advanced.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "\"synthetic\",")
        )
        .firstMatch
        XCTAssertTrue(quotedSuggestion.waitForExistence(timeout: 10))
        quotedSuggestion.click()
        XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "\"synthetic\"" })
    }

    @MainActor
    func testSearchQueriesOneDirectAuthoredLinkWithoutParallelResults() throws {
        waitForCurrentDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("Triptych", in: app)
        typeCommittedText("from-note:\"QA Autosave B\"", into: field, in: app)

        let relatedAnalysis = searchResult(named: "QA Autosave A")
        XCTAssertTrue(relatedAnalysis.waitForExistence(timeout: 20))
        XCTAssertFalse(searchResult(named: "QA Autosave B").exists)
        XCTAssertTrue(
            relatedAnalysis.label.localizedCaseInsensitiveContains(
                "from-note:qa autosave b"
            ),
            "The result must expose its occurrence-local direct-link origin."
        )

        let resultScroll = app.outlines["scholium.searchResults"].firstMatch
        XCTAssertTrue(resultScroll.waitForExistence(timeout: 5))
        relatedAnalysis.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(advanced.exists, "Opening a result retains the advanced search window.")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
    }
}
