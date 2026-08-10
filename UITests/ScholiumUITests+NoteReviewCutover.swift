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
        XCTAssertTrue(
            app.staticTexts["Needs Review · 2 Agent activities"]
                .waitForExistence(timeout: 20),
            "The live workspace projection must ingest both newly arrived portable Records."
        )
        XCTAssertTrue(initialInspector.exists)

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
        workspace.buttons["scholium.showResearchRecords"].click()
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
        let pendingTwo = app.staticTexts["Needs Review · 2 Agent activities"]
        XCTAssertTrue(pendingTwo.waitForExistence(timeout: 12))
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
        XCTAssertTrue(app.staticTexts[
            "Needs Review · 1 Agent activities"
        ].waitForExistence(timeout: 12))

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
        XCTAssertTrue(
            app.staticTexts["Needs Review · 1 Agent activities"]
                .waitForExistence(timeout: 20),
            "A later confirmed Agent activity must reopen Review for this Note."
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
    }

    @MainActor
    func testNoChangeActionDeliversOneResultArrivalWithoutNoteReview() throws {
        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        selectResearchInspectorMode("actions")
        let synthesize = app.descendants(matching: .any)[
            "scholium.researchAction.synthesize"
        ].firstMatch
        XCTAssertTrue(synthesize.waitForExistence(timeout: 5))
        synthesize.click()
        let actionSheet = app.sheets.firstMatch
        XCTAssertTrue(actionSheet.waitForExistence(timeout: 8))
        XCTAssertTrue(actionSheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        let copy = actionSheet.buttons["scholium.researchAction.copyHandoff"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.isEnabled)
        copy.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !actionSheet.exists })

        let runID = try latestLocalResearchExecutionRunID()
        let origin = QANoteReviewRecordSeed.Participant(
            relativePath: "QA Topic.md",
            role: "topic",
            title: "QA Topic"
        )
        try seedNoteReviewRecords([
            QANoteReviewRecordSeed(
                recordID: runID,
                title: "No-change Synthesis result",
                primaryRelativePath: origin.relativePath,
                participants: [origin],
                changedRelativePaths: [],
                finishedAt: "2026-08-10T04:10:00Z"
            ),
        ])
        try triggerWorkspaceRefreshForPortableFixture("no-change result")

        let resultNotice = app.descendants(matching: .any)[
            "scholium.researchResultNotification"
        ]
        XCTAssertTrue(resultNotice.waitForExistence(timeout: 20))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                identifier: "scholium.researchResultNotification"
            ).count,
            1
        )
        selectResearchInspectorMode("overview")
        XCTAssertTrue(app.staticTexts[
            "No Agent changes to review"
        ].waitForExistence(timeout: 12))
        resultNotice.buttons["Dismiss"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !resultNotice.exists })

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
            "scholium.researchResultNotification"
        ].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "No Agent changes to review"
        ].exists)
    }

    @MainActor
    private func openCurrentNoteRecords(
        in workspace: XCUIElement
    ) throws -> XCUIElement {
        let recordsButton = workspace.buttons["scholium.showResearchRecords"]
        XCTAssertTrue(recordsButton.waitForExistence(timeout: 5))
        recordsButton.click()
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
