import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
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
        let longPassage =
            "合成界面样本：\(lineWords) 标记这段可回到原文的材料。研究者可以先阅读上下文，再判断它与当前问题的关系；这里不预设支持或反对。The passage remains a source excerpt, with mixed-script wording and enough context to inspect its wrapping in the research pane."
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
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 45))
        waitForCurrentDocumentSurface()
        let workspace = app.windows["scholium-main-\(sessionID.uuidString)"].firstMatch
        XCTAssertTrue(workspace.exists)
        focusWorkspaceWindow(workspace)

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
        let groupedReferences = XCTAttachment(screenshot: workspace.screenshot())
        groupedReferences.name = "Research Inspector grouped references"
        groupedReferences.lifetime = .keepAlways
        add(groupedReferences)

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

    private func callQAMCP(
        tool: String,
        arguments: [String: Any] = [:]
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
        XCTAssertEqual(result["isError"] as? Bool, false)
        return try XCTUnwrap(result["structuredContent"] as? [String: Any])
    }

    @MainActor
    func testInspectorLinksSelectIncomingAndOutgoingDirections() throws {
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalBytes = try Data(contentsOf: noteURL)
        _ = selectResearchInspectorDirection("outgoing")
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
        let group = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.links.group.")
        ).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        group.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !incoming.exists })
        group.click()
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        let field = app.searchFields["scholium.links.search"].firstMatch
        XCTAssertTrue(field.exists)
        typeCommittedText("no-such-fixture-link", into: field, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.connections.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(incoming.exists)
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual(field.value as? String, "")
        XCTAssertTrue(incoming.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        let links = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        links.name = "Research Inspector incoming links"
        links.lifetime = .keepAlways
        add(links)
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
        selectDocumentMode("Review")

        app.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        let field = advanced.searchFields["scholium.searchField"]
        let result = searchResult(named: "QA Autosave A")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        selectResearchSearchScope("This Vault", in: app)
        typeCommittedText("body:Synthetic title:\"QA Autosave A\"", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        field.click()
        field.typeKey(.downArrow, modifierFlags: [])

        let selectionAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        selectionAttachment.name = "Search editorial selection"
        selectionAttachment.lifetime = .keepAlways
        add(selectionAttachment)

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
