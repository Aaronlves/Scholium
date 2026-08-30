import XCTest

extension ScholiumUITests {
    @MainActor
    func testNoteReviewCutoverAcrossRecordsAndNotes() throws {
        try seedNoteReviewCutoverFixture()
        try triggerWorkspaceRefreshForPortableFixture("initial note review")
        let firstRecordID = UUID(
            uuidString: "8A410000-0000-4000-8000-000000000001"
        )!
        let secondRecordID = UUID(
            uuidString: "8A410000-0000-4000-8000-000000000002"
        )!
        let laterRecordID = UUID(
            uuidString: "8A410000-0000-4000-8000-000000000003"
        )!
        let topic = QANoteReviewRecordSeed.Participant(
            relativePath: "QA Topic.md",
            role: "topic",
            title: "QA Topic"
        )
        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        let initialInspector = selectResearchInspectorMode("overview")
        let initialReviewRow = app.buttons["scholium.researchOverview.review.open"]
        XCTAssertTrue(
            initialReviewRow.waitForExistence(timeout: 20),
            "The live workspace projection must ingest both newly arrived portable Records."
        )
        XCTAssertEqual(
            initialReviewRow.value as? String,
            "Needs Review, 2 Agent activities"
        )
        XCTAssertTrue(initialInspector.exists)
        let autoReviewTask = workspace.descendants(matching: .any)[
            "scholium.noteReview.task"
        ]
        XCTAssertTrue(
            autoReviewTask.waitForExistence(timeout: 5),
            "The first pending activity set must present the attached Document task."
        )
        autoReviewTask.buttons["Close Note Review"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !autoReviewTask.exists })
        scrollUntilHittable(initialReviewRow, in: initialInspector)
        initialReviewRow.click()
        XCTAssertTrue(autoReviewTask.waitForExistence(timeout: 5))
        autoReviewTask.buttons["Close Note Review"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !autoReviewTask.exists })

        selectVault(
            "scholium.vault.paper_analysis",
            waitingFor: "scholium.noteRow.QA Autosave A.md"
        )
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordsWindow = try openCurrentNoteRecords(in: workspace)
        let firstRow = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(firstRecordID.uuidString)"
        ]
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 10),
            "The origin Note must project the one durable multi-Note Record."
        )

        focusWorkspaceWindow(workspace)
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        clickResearchRecordsControl(in: workspace)
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(secondRecordID.uuidString)"
        ].waitForExistence(timeout: 10))

        let listFrame = recordsWindow.frame
        firstRow.click()
        let detail = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        assertStableRecordsFrame(recordsWindow.frame, equals: listFrame)

        let comparison = recordsWindow.buttons[
            "scholium.researchRecord.changes.compare"
        ]
        let evidence = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.evidence"
        ]
        XCTAssertTrue(evidence.waitForExistence(timeout: 5))
        scrollUntilHittable(comparison, in: evidence)
        comparison.click()
        let returnToRecord = recordsWindow.buttons["Return to Record"]
        XCTAssertTrue(returnToRecord.waitForExistence(timeout: 8))
        XCTAssertTrue(recordsWindow.staticTexts["Multi-Note Agent revision"].exists)
        returnToRecord.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !returnToRecord.exists })
        XCTAssertFalse(
            NSPredicate(format: "hasKeyboardFocus == true").evaluate(
                with: comparison
            ),
            "Pointer return from comparison must not synthesize keyboard focus."
        )
        assertStableRecordsFrame(recordsWindow.frame, equals: listFrame)

        let back = recordsWindow.buttons["scholium.researchRecords.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.click()
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        assertStableRecordsFrame(recordsWindow.frame, equals: listFrame)
        recordsWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordsWindow.exists })

        focusWorkspaceWindow(workspace)
        let inspector = selectResearchInspectorMode("overview")
        let pendingTwo = app.buttons["scholium.researchOverview.review.open"]
        XCTAssertTrue(pendingTwo.waitForExistence(timeout: 12))
        XCTAssertEqual(
            pendingTwo.value as? String,
            "Needs Review, 2 Agent activities"
        )
        let openReview = app.buttons["scholium.researchOverview.review.open"]
        scrollUntilHittable(openReview, in: inspector)
        openReview.click()

        let reviewTask = workspace.descendants(matching: .any)[
            "scholium.noteReview.task"
        ]
        XCTAssertTrue(reviewTask.waitForExistence(timeout: 5))
        XCTAssertTrue(reviewTask.buttons["scholium.noteReview.viewChanges"].exists)
        let markReviewed = reviewTask.buttons["scholium.noteReview.mark"]
        XCTAssertTrue(markReviewed.exists)
        reviewTask.buttons["scholium.noteReview.viewChanges"].click()
        XCTAssertTrue(recordsWindow.waitForExistence(timeout: 8))
        XCTAssertTrue(firstRow.waitForExistence(timeout: 8))
        focusAuxiliaryWindow(recordsWindow, menuItemTitle: "Research Records")
        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordsWindow.exists })
        XCTAssertTrue(reviewTask.exists)
        XCTAssertTrue(markReviewed.isEnabled)
        markReviewed.click()
        XCTAssertTrue(app.staticTexts[
            "No Agent changes awaiting Review"
        ].waitForExistence(timeout: 12))

        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.noteRow.QA Work.md"
        )
        openNote("QA Work.md", expectedTitle: "QA Work", in: workspace)
        let workReview = app.buttons["scholium.researchOverview.review.open"]
        XCTAssertTrue(workReview.waitForExistence(timeout: 12))
        XCTAssertEqual(
            workReview.value as? String,
            "Needs Review, 1 Agent activities"
        )

        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        XCTAssertTrue(app.staticTexts[
            "No Agent changes awaiting Review"
        ].waitForExistence(timeout: 10))
        try seedNoteReviewRecords([
            QANoteReviewRecordSeed(
                recordID: laterRecordID,
                title: "New Agent activity after Review",
                primaryRelativePath: topic.relativePath,
                participants: [topic],
                changedRelativePaths: [topic.relativePath],
                finishedAt: "2026-08-09T03:03:00Z"
            ),
        ])
        try triggerWorkspaceRefreshForPortableFixture("later note review")
        let laterReview = app.buttons["scholium.researchOverview.review.open"]
        XCTAssertTrue(
            laterReview.waitForExistence(timeout: 20),
            "A later confirmed Agent activity must reopen Review for this Note."
        )
        XCTAssertEqual(
            laterReview.value as? String,
            "Needs Review, 1 Agent activities"
        )
        XCTAssertTrue(
            reviewTask.waitForExistence(timeout: 5),
            "A new pending activity set must present the attached task again."
        )
    }

    @MainActor
    func testResearcherResponseProgressiveEditingAndStaleDraft() throws {
        let fixture = try seedResearchRecordFixture()
        try triggerWorkspaceRefreshForPortableFixture("response fixture")

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordsWindow = try openCurrentNoteRecords(in: workspace)
        let row = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.click()
        let detail = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let addResponse = recordsWindow.buttons[
            "scholium.researchRecord.response.add"
        ]
        scrollUntilHittable(addResponse, in: detail)
        addResponse.click()

        let sheet = recordsWindow.descendants(matching: .any)[
            "scholium.researchResponse.sheet"
        ]
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let evaluation = recordsWindow.textViews[
            "scholium.researchResponse.evaluationNote"
        ]
        XCTAssertTrue(evaluation.waitForExistence(timeout: 5))
        XCTAssertFalse(recordsWindow.textViews[
            "scholium.researchResponse.methodFeedback"
        ].exists)
        try paste(
            "The result helps distinguish salience from practical authority.",
            into: evaluation
        )
        let addFeedback = recordsWindow.buttons[
            "scholium.researchResponse.addMethodFeedback"
        ]
        XCTAssertTrue(addFeedback.waitForExistence(timeout: 5))
        addFeedback.click()
        let feedback = recordsWindow.textViews[
            "scholium.researchResponse.methodFeedback"
        ]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        let responseScroll = recordsWindow.sheets.scrollViews.firstMatch
        XCTAssertTrue(responseScroll.waitForExistence(timeout: 5))
        scrollUntilHittable(feedback, in: responseScroll)
        try paste(
            "Ask the Agent to identify the exact inferential bridge earlier.",
            into: feedback
        )

        recordsWindow.sheets.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(app.staticTexts[
            "Discard the Unsaved Response?"
        ].waitForExistence(timeout: 5))
        recordsWindow.buttons["action-button-2"].click()
        XCTAssertTrue(sheet.exists)
        let save = recordsWindow.buttons["scholium.researchResponse.save"]
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertTrue(waitUntil(timeout: 12) { !sheet.exists })

        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.response.evaluation"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.response.methodFeedback"
        ].exists)
        XCTAssertTrue(recordsWindow.buttons[
            "scholium.researchRecord.response.improveMethod"
        ].exists)
        let storedResponse = try portableResearchRecordSource(fixture.recordID)
        XCTAssertTrue(storedResponse.contains(
            "The result helps distinguish salience from practical authority."
        ))
        XCTAssertTrue(storedResponse.contains(
            "Ask the Agent to identify the exact inferential bridge earlier."
        ))

        let edit = recordsWindow.buttons[
            "scholium.researchRecord.response.edit"
        ]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        let reopenedEvaluation = recordsWindow.textViews[
            "scholium.researchResponse.evaluationNote"
        ]
        try paste(
            "This local draft must survive an external response revision.",
            into: reopenedEvaluation
        )
        try externallyReplaceResearcherResponse(
            recordID: fixture.recordID,
            evaluationText: "A second window saved a different evaluation."
        )
        try triggerWorkspaceRefreshForPortableFixture("stale response")
        let status = recordsWindow.descendants(matching: .any)[
            "scholium.researchResponse.status"
        ]
        XCTAssertTrue(waitUntil(timeout: 20) {
            status.label.contains("Out of Date")
                || (status.value as? String)?.contains("Out of Date") == true
        })
        XCTAssertEqual(
            reopenedEvaluation.value as? String,
            "This local draft must survive an external response revision."
        )
        XCTAssertFalse(recordsWindow.buttons[
            "scholium.researchResponse.save"
        ].isEnabled)
        recordsWindow.sheets.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(app.staticTexts[
            "Discard the Unsaved Response?"
        ].waitForExistence(timeout: 5))
        recordsWindow.buttons["action-button-1"].click()
        XCTAssertTrue(waitUntil(timeout: 8) { !sheet.exists })
        XCTAssertFalse(
            NSPredicate(format: "hasKeyboardFocus == true").evaluate(
                with: edit
            ),
            "Pointer dismissal must not synthesize keyboard focus on Edit Response."
        )
    }

    @MainActor
    func testNoChangeActionResultsFormOneCountedNotificationStackWithoutNoteReview() throws {
        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        let firstRunID = try completeNoChangeSynthesizeAction(
            request: "Synthesize this fixture without changing source.",
            recordTitle: "First no-change Synthesis result"
        )

        let notificationStack = app.descendants(matching: .any)[
            "scholium.researchActivityNotificationStack"
        ]
        let permissionNotice = app.descendants(matching: .any)[
            "scholium.researchNotificationPermission"
        ]
        XCTAssertTrue(notificationStack.waitForExistence(timeout: 20))
        XCTAssertFalse(permissionNotice.exists)
        XCTAssertTrue(
            String(describing: notificationStack.value)
                .contains("1 Action notification")
        )

        let secondRunID = try completeNoChangeSynthesizeAction(
            request: "Synthesize this fixture again without changing source.",
            recordTitle: "Second no-change Synthesis result"
        )

        XCTAssertTrue(waitUntil(timeout: 20) {
            String(describing: notificationStack.value)
                .contains("2 Action notifications")
        })
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                identifier: "scholium.researchActivityNotificationStack"
            ).count,
            1
        )
        selectResearchInspectorMode("overview")
        XCTAssertTrue(app.staticTexts[
            "No Agent changes to review"
        ].waitForExistence(timeout: 12))

        retainNoteReviewScreenshot(
            of: workspace,
            named: "Activity notification stack collapsed"
        )
        notificationStack.hover()
        XCTAssertTrue(notificationStack.isHittable)
        retainNoteReviewScreenshot(
            of: workspace,
            named: "Activity notification stack hover preview"
        )
        notificationStack.click()
        let firstActivity = app.descendants(matching: .any)[
            "scholium.notification.action.\(firstRunID.uuidString)"
        ]
        let secondActivity = app.descendants(matching: .any)[
            "scholium.notification.action.\(secondRunID.uuidString)"
        ]
        XCTAssertTrue(firstActivity.waitForExistence(timeout: 8))
        XCTAssertTrue(secondActivity.waitForExistence(timeout: 8))

        app.buttons[
            "scholium.notification.action.dismiss.\(firstRunID.uuidString)"
        ].click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            String(describing: notificationStack.value)
                .contains("1 Action notification")
        })
        app.buttons[
            "scholium.notification.action.dismiss.\(secondRunID.uuidString)"
        ].click()
        XCTAssertTrue(waitUntil(timeout: 8) { !notificationStack.exists })
        XCTAssertTrue(permissionNotice.waitForExistence(timeout: 8))

        selectVault(
            "scholium.vault.paper_analysis",
            waitingFor: "scholium.noteRow.QA Autosave A.md"
        )
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchActivityNotificationStack"
        ].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "No Agent changes to review"
        ].exists)
    }

    @MainActor
    private func completeNoChangeSynthesizeAction(
        request: String,
        recordTitle: String
    ) throws -> UUID {
        selectResearchInspectorMode("actions")
        let synthesize = app.descendants(matching: .any)[
            "scholium.researchAction.synthesize"
        ].firstMatch
        XCTAssertTrue(synthesize.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { synthesize.isEnabled })
        synthesize.click()
        let actionSheet = app.sheets.firstMatch
        XCTAssertTrue(actionSheet.waitForExistence(timeout: 8))
        XCTAssertTrue(actionSheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        let copy = actionSheet.buttons["scholium.researchAction.copyHandoff"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        let researchRequest = actionSheet.textViews[
            "scholium.researchAction.academicText.research-request"
        ]
        XCTAssertTrue(researchRequest.waitForExistence(timeout: 5))
        researchRequest.click()
        researchRequest.typeText(request)
        XCTAssertTrue(waitUntil(timeout: 5) { copy.isEnabled })
        copy.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !actionSheet.exists })

        let runID = try latestLocalResearchExecutionRunID()
        let copiedInstructions = try pasteboardText()
        let handoffLines = copiedInstructions.components(separatedBy: .newlines)
        let runLocator = try XCTUnwrap(
            handoffLines.first { $0.hasPrefix("Scholium Run: ") }.map {
                String($0.dropFirst("Scholium Run: ".count))
            }
        )
        let pairingCode = try XCTUnwrap(
            handoffLines.first { $0.hasPrefix("Pairing Code: ") }.map {
                String($0.dropFirst("Pairing Code: ".count))
            }
        )
        let pairingOutput = try runScholiumCLI(
            ["agent", "pair", "--run", runLocator],
            stdin: Data("\(pairingCode)\n".utf8)
        )
        XCTAssertTrue(pairingOutput.contains(runLocator))

        let resultSubmission = try JSONSerialization.data(withJSONObject: [
            "schema_version": 3,
            "record_title": recordTitle,
            "disposition": "completed",
            "academic_results": [
                "values": [
                    "synthesis-outcome": [
                        "kind": "freeText",
                        "text": "A disposable synthesis with no source changes.",
                    ],
                    "contribution": [
                        "kind": "multipleChoice",
                        "choices": ["adds"],
                    ],
                ],
            ],
            "fidelity_outcomes": [],
        ])
        let resultOutput = try runScholiumCLI(
            ["agent", "submit-result", "--run", runLocator, "--from", "-"],
            stdin: resultSubmission
        )
        let resultReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultOutput.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(resultReceipt["state"] as? String, "finalized")
        XCTAssertEqual(resultReceipt["record_formed"] as? Bool, true)
        return runID
    }

    @MainActor
    private func retainNoteReviewScreenshot(
        of element: XCUIElement,
        named name: String
    ) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openCurrentNoteRecords(
        in workspace: XCUIElement
    ) throws -> XCUIElement {
        let recordsButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordsButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)
        let triptych = try triptychID(at: triptychDirectory)
        let window = app.windows[
            "scholium-research-records-\(triptych.uuidString.lowercased())"
        ]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        XCTAssertEqual(
            window.descendants(matching: .any)[
                "scholium.researchRecords.scope"
            ].value as? String,
            "This Note"
        )
        return window
    }

    private func assertStableRecordsFrame(
        _ frame: CGRect,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frame.minX, expected.minX, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.maxY, expected.maxY, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.width, expected.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(frame.height, expected.height, accuracy: 1, file: file, line: line)
    }
}
