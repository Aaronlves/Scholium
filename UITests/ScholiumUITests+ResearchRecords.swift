import XCTest

extension ScholiumUITests {
    @MainActor
    func testSettlementReminderPersistsUntilSettle() throws {
        try seedSettlementReminderFixture()
        try triggerWorkspaceRefreshForPortableFixture("Settlement reminder")

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)

        let reminder = workspace.descendants(matching: .any)[
            "scholium.researchActivityNotificationStack"
        ]
        XCTAssertTrue(reminder.waitForExistence(timeout: 20))
        let reviewChanges = workspace.buttons["Review Changes"]
        if !reviewChanges.exists {
            reminder.click()
        }
        XCTAssertTrue(reviewChanges.waitForExistence(timeout: 8))
        reviewChanges.click()

        let recordsWindow = app.windows["Research Records"]
        XCTAssertTrue(recordsWindow.waitForExistence(timeout: 8))
        recordsWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordsWindow.exists })

        focusWorkspaceWindow(workspace)
        XCTAssertTrue(reminder.waitForExistence(timeout: 8))
        XCTAssertTrue(reviewChanges.waitForExistence(timeout: 8))
        let settle = workspace.buttons["scholium.researchAction.settle"]
        XCTAssertTrue(settle.waitForExistence(timeout: 8))
        settle.click()
        let settlementPopover = app.popovers.firstMatch
        XCTAssertTrue(settlementPopover.waitForExistence(timeout: 5))
        let confirmSettlement = settlementPopover.buttons["Settle"]
        XCTAssertTrue(confirmSettlement.waitForExistence(timeout: 5))
        confirmSettlement.click()
        XCTAssertTrue(waitUntil(timeout: 20) { !reviewChanges.exists })
        XCTAssertTrue(reminder.exists)
        XCTAssertTrue(accessibilityText(of: reminder).contains("2 Notifications"))
    }

    @MainActor
    func testPartialResearchRecordCorpusKeepsReadableRows() throws {
        try seedSettlementReminderFixture()
        try seedUnreadableResearchRecordFixture()
        try triggerWorkspaceRefreshForPortableFixture("partial Record corpus")

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        let recordsWindow = try openCurrentNoteRecords(in: workspace)
        let readableRow = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.8A410000-0000-4000-8000-000000000001"
        ]

        XCTAssertTrue(readableRow.waitForExistence(timeout: 10))
        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "Some Research Records Could Not Be Loaded"
        ].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Research Records Unavailable"].exists)
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
}
