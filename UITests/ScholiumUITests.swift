@preconcurrency import XCTest

/// Commits marked text without changing the user's active input source.
/// `typeText` alone can leave Latin test queries inside a CJK IME
/// composition, so SwiftUI has not yet received the bound value. Return
/// commits that composition; Tab can be consumed by the IME instead.
private func typeCommittedText(
    _ text: String,
    into field: XCUIElement,
    in application: XCUIApplication
) {
    field.click()
    field.typeText(text)
    application.typeKey(.return, modifierFlags: [])
}

final class ScholiumUITests: XCTestCase {
    private enum QAAppearance: String, CaseIterable {
        case light
        case dark

        var displayName: String { rawValue.capitalized }
    }

    private var app: XCUIApplication!
    private var sessionID: UUID!
    private var testDirectory: URL!
    private var homeDirectory: URL!
    private var triptychDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        sessionID = UUID()
        try createIsolatedTriptych()
        app = configuredApplication(sessionID: sessionID, windowWidth: 1380)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "The isolated QA window did not appear")
    }

    override func tearDownWithError() throws {
        if testRun?.failureCount ?? 0 > 0 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Scholium UI failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Scholium accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        try? FileManager.default.removeItem(at: testDirectory)
        app = nil
        sessionID = nil
        testDirectory = nil
        homeDirectory = nil
        triptychDirectory = nil
    }

    /// The default final QA route. It keeps one isolated application process
    /// alive for the complete journey so the researcher does not see a new QA
    /// app open for every assertion group.
    @MainActor
    func testCanonicalAcceptanceJourney() throws {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let nativeDocument = app.descendants(matching: .any)["Markdown reader"]
        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]

        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists || nativeDocument.exists })
        XCTAssertTrue(
            documentTabs.waitForExistence(timeout: 5),
            "The document-first toolbar must keep the active note identity visible with one open note."
        )
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertTrue(inspectorButton.exists)
        XCTAssertFalse(inspector.exists)

        XCTContext.runActivity(named: "Search, properties, and inspector") { _ in
            app.typeKey("f", modifierFlags: [.command])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            let field = app.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            typeCommittedText("analysis", into: field, in: app)
            let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })

            metadata.click()
            XCTAssertTrue(waitUntil(timeout: 3) { metadata.label == "Hide note properties" })
            metadata.click()

            inspectorButton.click()
            XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            inspectorButton.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
        }

        XCTContext.runActivity(named: "Review requires a written judgment and verdict") { _ in
            let review = app.descendants(matching: .any)[
                "scholium.researchFunction.review"
            ]
            XCTAssertTrue(waitUntil(timeout: 5) {
                review.exists && review.isEnabled && review.isHittable
            })
            review.click()

            let complete = app.buttons["Complete Review"]
            let noteField = app.textViews["Review Note"]
            XCTAssertTrue(complete.waitForExistence(timeout: 5))
            XCTAssertFalse(complete.isEnabled)
            noteField.click()
            noteField.typeText("A bounded acceptance-test judgment.")
            XCTAssertFalse(complete.isEnabled)
            app.buttons["Cancel"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !complete.exists })
        }

        XCTContext.runActivity(named: "Peer vaults preserve context and Back/Forward cross vaults") { _ in
            let analyses = app.radioButtons["Analyses"]
            let topics = app.radioButtons["Topics"]
            XCTAssertTrue(analyses.exists)
            XCTAssertTrue(topics.exists)

            topics.click()
            let topicRow = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
            XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
            topicRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (metadata.value as? String) == "QA Topic"
            })

            app.typeKey("[", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 8) {
                (metadata.value as? String) == "QA Autosave A"
            })
            XCTAssertTrue((analyses.value as? NSNumber)?.boolValue == true)

            app.typeKey("]", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 8) {
                (metadata.value as? String) == "QA Topic"
            })
            XCTAssertTrue((topics.value as? NSNumber)?.boolValue == true)

            analyses.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (metadata.value as? String) == "QA Autosave A"
            })
        }

        XCTContext.runActivity(named: "Zotero reports a precise unavailable state") { _ in
            if !inspector.exists {
                inspectorButton.click()
                XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            }
            let research = app.radioButtons["Research"]
            XCTAssertTrue(research.exists)
            research.click()
            XCTAssertTrue(app.staticTexts["Zotero Source"].waitForExistence(timeout: 5))

            let missing = app.staticTexts[
                "The Zotero item identified by this Analysis was not found."
            ]
            let unavailable = app.staticTexts.matching(
                NSPredicate(format: "value CONTAINS[c] %@", "Zotero is not responding")
            ).firstMatch
            let disabled = app.staticTexts.matching(
                NSPredicate(format: "value CONTAINS[c] %@", "Zotero local API access is disabled")
            ).firstMatch
            XCTAssertTrue(waitUntil(timeout: 8) { missing.exists || unavailable.exists || disabled.exists })
            XCTAssertFalse(app.buttons["Open PDF in Preview"].exists)
            XCTAssertFalse(app.buttons["Open Attachment"].exists)
        }

        XCTContext.runActivity(named: "Live Preview projects the document and commits before navigation") { _ in
            XCTAssertTrue(mode.exists)
            mode.click()
            let livePreview = app.menuItems
                .matching(identifier: "text.page.badge.magnifyingglass")
                .firstMatch
            XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
            livePreview.click()

            let editor = app.descendants(matching: .any)["Markdown live preview editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 8))
            // WebKit exposes CodeMirror's lossless source buffer through
            // AXValue even when the live-preview decorations hide frontmatter
            // from the rendered surface. The projection itself is covered by
            // the editor bundle/style contract; this journey verifies that the
            // projected editor remains interactive and commits its source.
            XCTAssertFalse((editor.value as? String ?? "").isEmpty)

            let token = " ACCEPTANCE-\(UUID().uuidString)"
            let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
            editor.click()
            editor.typeKey(.end, modifierFlags: [.command])
            editor.typeText(token)
            XCTAssertFalse((try? source(at: noteURL).contains(token)) ?? true)

            app.typeKey("f", modifierFlags: [.command, .shift])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            XCTAssertTrue(search.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: noteURL).contains(token)) == true })
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        }

        XCTContext.runActivity(named: "An independent second window remains reachable") { _ in
            app.typeKey("n", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count >= 2 })
            closeFrontmostWindow()
            XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
        }
    }

    @MainActor
    func testQuickOpenMatchesAnAliasAcrossTheTriptych() throws {
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))

        app.typeKey("p", modifierFlags: [.command])
        let quickOpen = app.descendants(matching: .any)["scholium.quickOpen"]
        XCTAssertTrue(quickOpen.waitForExistence(timeout: 5))

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        typeCommittedText("Normative QA Nexus", into: field, in: app)

        let result = app.descendants(matching: .any)[
            "scholium.quickOpenResult.topic_knowledge.QA Topic.md"
        ]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()

        XCTAssertTrue(waitUntil(timeout: 8) {
            (metadata.value as? String) == "QA Topic"
        })
        XCTAssertTrue((app.radioButtons["Topics"].value as? NSNumber)?.boolValue == true)
        XCTAssertFalse(quickOpen.exists)
    }

    @MainActor
    func testNewAnalysisRequiresAndPersistsResearchStatus() throws {
        let newNote = app.descendants(matching: .any)["scholium.newNote"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 10))
        newNote.click()

        let scope = app.descendants(matching: .any)["scholium.newNote.researchUnitScope"]
        let limitations = app.descendants(matching: .any)["scholium.newNote.researchUnitLimitations"]
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertTrue(limitations.exists)
        XCTAssertTrue(create.exists)
        XCTAssertFalse(create.isEnabled)

        scope.click()
        scope.typeText("Introduction and Chapter 1")
        limitations.click()
        limitations.typeText("Chapters 2-5 remain unread.")
        XCTAssertTrue(create.isEnabled)
        create.click()

        let createdURL = triptychDirectory.appendingPathComponent("01-analyses/Untitled.md")
        XCTAssertTrue(waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: createdURL.path) })
        let source = try source(at: createdURL)
        XCTAssertTrue(source.contains("research_unit:"))
        XCTAssertTrue(source.contains("scope: \"Introduction and Chapter 1\""))
        XCTAssertTrue(source.contains("- \"Chapters 2-5 remain unread.\""))
    }

    @MainActor
    func testRecentNotesReturnsToCrossVaultWorkWithoutSearch() throws {
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))

        app.radioButtons["Topics"].click()
        let topicRow = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
        XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
        topicRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            metadata.value as? String == "QA Topic"
        })

        // Back/Forward is chronological, while Recent Notes is actual MRU.
        app.typeKey("[", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) {
            metadata.value as? String == "QA Autosave A"
        })

        app.menuBars.menuBarItems["Navigate"].click()
        let recentNotes = app.menuItems["Recent Notes"]
        XCTAssertTrue(recentNotes.waitForExistence(timeout: 3))
        recentNotes.hover()

        let topicRecentItem = app.menuItems["QA Topic — Topics"]
        XCTAssertTrue(topicRecentItem.waitForExistence(timeout: 3))
        XCTAssertTrue(topicRecentItem.isEnabled)
        topicRecentItem.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            metadata.value as? String == "QA Topic"
        })

        app.menuBars.menuBarItems["Navigate"].click()
        XCTAssertTrue(recentNotes.waitForExistence(timeout: 3))
        recentNotes.hover()
        let clear = app.menuItems["Clear Recent Notes"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.click()

        app.menuBars.menuBarItems["Navigate"].click()
        XCTAssertTrue(recentNotes.waitForExistence(timeout: 3))
        recentNotes.hover()
        let empty = app.menuItems["No Recent Notes"]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        XCTAssertFalse(empty.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testCleanAccountConfiguresAndRestoresACompleteTriptych() throws {
        app.terminate()

        let cleanHome = testDirectory.appendingPathComponent("clean-home", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanHome, withIntermediateDirectories: true)

        app = XCUIApplication(bundleIdentifier: "com.kbmanager.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = triptychDirectory.path
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let setupSurfaces = app.descendants(matching: .any)
            .matching(identifier: "scholium.triptychSetup")
        let setup = setupSurfaces.firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertEqual(
            setupSurfaces.count,
            1,
            "First launch must present one setup surface, not root setup plus a duplicate sheet."
        )
        XCTAssertTrue(app.staticTexts["Set Up Scholium"].exists)
        XCTAssertEqual(
            app.windows.firstMatch.frame.width,
            360,
            accuracy: 18,
            "First-run setup should use the same narrow measure as the Triptych Interface."
        )
        XCTAssertFalse(app.scrollViews.firstMatch.exists)

        let getStarted = app.buttons["Get Started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5))
        getStarted.click()
        XCTAssertTrue(app.staticTexts["Choose Analyses"].waitForExistence(timeout: 3))

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        chooseSetupFolder(analyses, role: "Analyses")
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Choose Topics"].waitForExistence(timeout: 3))
        chooseSetupFolder(topics, role: "Topics")
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Choose Works"].waitForExistence(timeout: 3))
        chooseSetupFolder(works, role: "Works")
        app.buttons["Continue"].click()

        let complete = app.buttons["Use This Triptych"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        XCTAssertFalse(complete.isEnabled)
        authorizePortableFolder(triptychDirectory)
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        XCTAssertTrue(app.radioButtons["Analyses"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["scholium.triptychInterface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.firstMatch.frame.width <= 390 })
        RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychSetup"].exists,
            "Completing first-run setup must not re-present the same guide over the Triptych Interface."
        )
        let analysisRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(analysisRow.waitForExistence(timeout: 15))
        analysisRow.click()
        waitForDocumentSurface()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.firstMatch.frame.width >= 760 })

        let manifest = triptychDirectory.appendingPathComponent(".scholium/manifest.json")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: manifest.path),
            "Expected setup to create only its portable control manifest beside Works."
        )

        app.terminate()
        app = XCUIApplication(bundleIdentifier: "com.kbmanager.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.radioButtons["Analyses"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["scholium.triptychSetup"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
                .waitForExistence(timeout: 15)
        )

        app.typeKey(",", modifierFlags: [.command])
        let nameField = app.descendants(matching: .any)["scholium.triptychName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.click()
        nameField.typeKey("a", modifierFlags: [.command])
        nameField.typeText("QA Renamed Triptych")
        let saveTriptych = app.buttons["Save Triptych"]
        XCTAssertTrue(saveTriptych.waitForExistence(timeout: 5))
        XCTAssertTrue(saveTriptych.isEnabled)
        saveTriptych.click()
        XCTAssertTrue(waitUntil(timeout: 10) {
            !self.app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "manifest.json")
            ).firstMatch.exists
        })
        let registryURL = cleanHome
            .appendingPathComponent("ApplicationSupport/Workspace/workspace-registry-v2.json")
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? String(contentsOf: registryURL, encoding: .utf8))?
                .contains("QA Renamed Triptych") == true
        })
    }

    @MainActor
    func testResearchGuidanceSkillsAreReachableInSettings() throws {
        let collisionPackage = triptychDirectory.appendingPathComponent(
            ".scholium/skills/scholium-development",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: collisionPackage,
            withIntermediateDirectories: true
        )
        try write(
            """
            ---
            name: Conflicting Development
            description: Disposable package used to verify collision recovery.
            ---
            Remain explicit-only and researcher-owned.
            """ + "\n",
            to: collisionPackage.appendingPathComponent("SKILL.md")
        )

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()

        let collection = app.descendants(matching: .any)["scholium.researchGuidance.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        let skillsSegment = app.radioButtons["Skills"]
        XCTAssertTrue(skillsSegment.waitForExistence(timeout: 5))
        skillsSegment.click()

        let bundled = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.bundled.scholium-development"
        ].firstMatch
        XCTAssertTrue(bundled.waitForExistence(timeout: 10))
        let skillSidebar = app.windows["Research Guidance"].outlines["Sidebar"].firstMatch
        XCTAssertTrue(skillSidebar.waitForExistence(timeout: 5))
        scrollUntilHittable(bundled, in: skillSidebar)
        bundled.click()

        let editor = app.descendants(matching: .any)["scholium.researchGuidance.skillEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.skillRouting"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Duplicate into Triptych"].exists)
        XCTAssertTrue(app.buttons["Reveal Skills Folder"].exists)
        XCTAssertFalse(app.buttons["Save Skill"].exists)

        let collision = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.triptych.scholium-development"
        ].firstMatch
        XCTAssertTrue(collision.waitForExistence(timeout: 5))
        collision.click()
        let validation = app.descendants(matching: .any)[
            "scholium.researchGuidance.skillValidation"
        ]
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        XCTAssertTrue((validation.label + " " + (validation.value as? String ?? ""))
            .contains("protected Scholium package"))

        app.buttons["Delete Triptych Skill"].click()
        app.buttons["Delete Skill"].click()
        XCTAssertTrue(waitUntil(timeout: 8) { !collision.exists })
        bundled.click()
        app.buttons["Duplicate into Triptych"].click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.triptych.development-copy"
        ].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    func testDialoguePreservesResearcherFollowUpAndAgentResponseChronology() throws {
        waitForDocumentSurface()
        let initialComment = "Clarify the distinction without overstating the source."
        let followUpComment = "Keep the unresolved interpretive question visible."
        let agentResponse = "The distinction is clarified, and the unresolved scope question remains marked for review."

        let prepare = app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.click()
        let instruction = app.descendants(matching: .any)[
            "scholium.researchFunctionInstruction"
        ]
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        scrollUntilHittable(instruction, in: app.sheets.firstMatch.scrollViews.firstMatch)
        instruction.click()
        instruction.typeText(initialComment)
        let prepareRun = app.descendants(matching: .any)[
            "scholium.prepareResearchFunction"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled })
        prepareRun.click()
        let copy = app.descendants(matching: .any)[
            "scholium.copyResearchFunctionInstructions"
        ]
        XCTAssertTrue(copy.waitForExistence(timeout: 8))
        copy.click()
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !instruction.exists })

        let historyButton = app.buttons["scholium.noteHistoryButton"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.click()
        let history = app.descendants(matching: .any)["scholium.noteHistoryPanel"]
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        let dialogueSection = history.descendants(matching: .any)["scholium.noteHistory.dialogueSection"]
        XCTAssertTrue(dialogueSection.waitForExistence(timeout: 8))
        let disclosure = dialogueSection.descendants(matching: .any)["scholium.dialogue.entryDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()

        let addFollowUp = history.descendants(matching: .any)["scholium.dialogue.addFollowUp"]
        XCTAssertTrue(addFollowUp.waitForExistence(timeout: 5))
        addFollowUp.click()
        let followUpField = app.descendants(matching: .any)["scholium.dialogue.followUpText"]
        XCTAssertTrue(followUpField.waitForExistence(timeout: 5))
        followUpField.click()
        followUpField.typeText(followUpComment)
        app.descendants(matching: .any)["scholium.dialogue.saveFollowUp"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !followUpField.exists })

        let recordResponse = history.descendants(matching: .any)["scholium.dialogue.recordResponse"]
        XCTAssertTrue(recordResponse.waitForExistence(timeout: 5))
        let historyScrollView = app.scrollViews["scholium.noteHistoryPanel"].firstMatch
        XCTAssertTrue(historyScrollView.exists)
        scrollUntilHittable(recordResponse, in: historyScrollView)
        recordResponse.click()
        let agentName = app.descendants(matching: .any)["scholium.dialogue.agentName"]
        let responseField = app.descendants(matching: .any)["scholium.dialogue.responseText"]
        XCTAssertTrue(agentName.waitForExistence(timeout: 5))
        agentName.click()
        agentName.typeKey("a", modifierFlags: [.command])
        agentName.typeText("Codex")
        responseField.click()
        responseField.typeText(agentResponse)
        app.descendants(matching: .any)["scholium.dialogue.saveResponse"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !responseField.exists })

        assertDialogueTurns(
            in: history,
            containInOrder: [initialComment, followUpComment, agentResponse]
        )

        historyButton.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !history.exists })
        historyButton.click()
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        let reopenedSection = history.descendants(matching: .any)["scholium.noteHistory.dialogueSection"]
        let reopenedDisclosure = reopenedSection.descendants(matching: .any)["scholium.dialogue.entryDisclosure"]
        XCTAssertTrue(reopenedDisclosure.waitForExistence(timeout: 5))
        reopenedDisclosure.click()
        assertDialogueTurns(
            in: history,
            containInOrder: [initialComment, followUpComment, agentResponse]
        )
    }

    @MainActor
    func testDialogueFunctionCopiesPreparedRequest() throws {
        waitForDocumentSurface()

        let dialogue = app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ]
        XCTAssertTrue(dialogue.waitForExistence(timeout: 5))
        dialogue.click()

        var sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))

        var target = sheet.descendants(matching: .any)[
            "scholium.researchFunctionTarget"
        ]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.staticTexts["QA Autosave A"].exists)
        XCTAssertTrue(target.staticTexts["QA Autosave A.md"].exists)

        let targetMaterialIdentifier =
            "scholium.researchFunctionMaterial.analysis.QA Autosave A.md"
        var selectedMaterial = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.analysis.QA Autosave B.md"
        ]
        var unselectedMaterial = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.topic.QA Topic.md"
        ]
        XCTAssertFalse(sheet.descendants(matching: .any)[targetMaterialIdentifier].exists)
        XCTAssertTrue(selectedMaterial.waitForExistence(timeout: 8))
        XCTAssertTrue(unselectedMaterial.waitForExistence(timeout: 5))
        XCTAssertFalse(checkboxIsSelected(selectedMaterial))
        XCTAssertFalse(checkboxIsSelected(unselectedMaterial))

        selectedMaterial.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.checkboxIsSelected(selectedMaterial) })

        var instruction = sheet.descendants(matching: .any)[
            "scholium.researchFunctionInstruction"
        ]
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        scrollUntilHittable(instruction, in: sheet.scrollViews.firstMatch)
        instruction.click()
        instruction.typeText("Discard this draft after Cancel.")

        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })

        dialogue.click()
        sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        target = sheet.descendants(matching: .any)["scholium.researchFunctionTarget"]
        selectedMaterial = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.analysis.QA Autosave B.md"
        ]
        unselectedMaterial = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.topic.QA Topic.md"
        ]
        instruction = sheet.descendants(matching: .any)[
            "scholium.researchFunctionInstruction"
        ]
        XCTAssertTrue(selectedMaterial.waitForExistence(timeout: 8))
        XCTAssertTrue(unselectedMaterial.waitForExistence(timeout: 5))
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        XCTAssertFalse(checkboxIsSelected(selectedMaterial))
        XCTAssertFalse(checkboxIsSelected(unselectedMaterial))
        XCTAssertFalse((instruction.value as? String ?? "").contains("Discard this draft"))

        selectedMaterial.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.checkboxIsSelected(selectedMaterial) })
        XCTAssertTrue(target.staticTexts["QA Autosave A"].exists)
        XCTAssertTrue(target.staticTexts["QA Autosave A.md"].exists)
        XCTAssertFalse(sheet.descendants(matching: .any)[targetMaterialIdentifier].exists)

        scrollUntilHittable(instruction, in: sheet.scrollViews.firstMatch)
        instruction.click()
        instruction.typeText("Assess the bounded philosophical result with the selected Analysis only.")

        let prepareRun = sheet.descendants(matching: .any)[
            "scholium.prepareResearchFunction"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled && prepareRun.isHittable })
        prepareRun.click()
        let copy = sheet.descendants(matching: .any)[
            "scholium.copyResearchFunctionInstructions"
        ]
        XCTAssertTrue(copy.waitForExistence(timeout: 8))
        XCTAssertEqual(copy.label, "Copy Instructions for Agent")
        copy.click()

        let copiedInstructions = try pasteboardText()
        XCTAssertTrue(copiedInstructions.contains(
            "Assess the bounded philosophical result with the selected Analysis only."
        ))
        XCTAssertTrue(copiedInstructions.contains("Dialogue"))
        XCTAssertTrue(copiedInstructions.contains(
            "Target: QA Autosave A [QA Autosave A.md]"
        ))
        XCTAssertTrue(copiedInstructions.contains("Materials:"))
        XCTAssertTrue(copiedInstructions.contains("QA Autosave B.md"))
        XCTAssertFalse(copiedInstructions.contains("QA Topic.md"))
        XCTAssertFalse(copiedInstructions.contains(
            "- QA Autosave A [QA Autosave A.md] —"
        ))
        XCTAssertTrue(copiedInstructions.contains(
            "The Target and Materials are read-only."
        ))

        sheet.buttons["Done"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !sheet.exists })
    }

    @MainActor
    func testResearchStripAccessibilityOrderAndReviewPanelSemantics() {
        waitForDocumentSurface()

        let strip = app.descendants(matching: .any)["scholium.researchStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertEqual(strip.label, "Research functions")

        let functions = ["Dialogue", "Develop", "Review", "Fidelity"].map { title in
            app.buttons[title].firstMatch
        }
        for function in functions {
            XCTAssertTrue(function.exists)
            XCTAssertTrue(function.isEnabled)
        }
        for pair in zip(functions, functions.dropFirst()) {
            XCTAssertLessThan(pair.0.frame.minX, pair.1.frame.minX)
        }

        let dialogue = app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ]
        dialogue.click()

        let sheet = app.sheets.firstMatch
        let panel = sheet.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.label, "Dialogue function")
        XCTAssertTrue(sheet.staticTexts["Dialogue"].exists)
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchFunctionTarget"
        ].exists)
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterials"
        ].exists)
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchFunctionScope"
        ].exists)
        XCTAssertTrue(sheet.radioButtons["Whole"].exists)
        XCTAssertTrue(sheet.radioButtons["Passage"].exists)
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.analysis.QA Autosave B.md"
        ].waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })

        let review = app.descendants(matching: .any)[
            "scholium.researchFunction.review"
        ]
        XCTAssertTrue(waitUntil(timeout: 3) {
            review.exists && review.isEnabled && review.isHittable
        })
        review.click()
        let reviewPanel = app.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ]
        XCTAssertTrue(reviewPanel.waitForExistence(timeout: 8))
        XCTAssertEqual(reviewPanel.label, "Review function")
        let reviewTarget = app.descendants(matching: .any)[
            "scholium.researchFunctionTarget"
        ]
        let reviewComments = app.descendants(matching: .any)[
            "scholium.researchFunctionComments"
        ]
        XCTAssertTrue(reviewTarget.exists)
        XCTAssertTrue(reviewComments.exists)
        XCTAssertLessThan(
            reviewTarget.frame.minY,
            reviewComments.frame.minY,
            "Review must present its immutable Target before Comments."
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !reviewPanel.exists })
    }

    @MainActor
    func testResearchStripVoiceOverSpeechOrder() throws {
        guard #available(macOS 27.0, *) else {
            throw XCTSkip("The VoiceOver UI-test service requires macOS 27 or newer.")
        }
        waitForDocumentSurface()
        let strip = app.descendants(matching: .any)["scholium.researchStrip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))

        let voiceOver = XCUIDevice.shared.voiceOverService
        let wasEnabled = voiceOver.isEnabled
        defer {
            do {
                if wasEnabled && !voiceOver.isEnabled {
                    try voiceOver.enable()
                } else if !wasEnabled && voiceOver.isEnabled {
                    try voiceOver.disable()
                }
            } catch {
                XCTFail(
                    "The VoiceOver test could not restore the researcher's prior VoiceOver state: \(error.localizedDescription)"
                )
            }
        }
        if !wasEnabled {
            try voiceOver.enable()
        }

        XCTAssertTrue(voiceOver.isEnabled)
        app.activate()

        let dialogueControl = app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ]
        dialogueControl.click()
        let panel = app.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
        app.typeKey(.F4, modifierFlags: [.control, .option, .shift])
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let expectedFunctions = ["Dialogue", "Develop", "Review", "Fidelity"]
        var spoken: [String] = []
        func attachTranscript(_ error: Error? = nil) {
            var lines = spoken.enumerated().map { index, spokenItem in
                "\(index + 1). \(spokenItem)"
            }
            if let error {
                lines.append("Navigation error: \(error.localizedDescription)")
            }
            let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
            attachment.name = "Research Strip VoiceOver transcript"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func currentUtterance() throws -> String {
            var lastError: Error?
            for _ in 0..<3 {
                do {
                    return try voiceOver.currentSpeech().utterance
                } catch {
                    lastError = error
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
            }
            throw lastError ?? NSError(
                domain: "ScholiumVoiceOverUITest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "VoiceOver produced no speech."]
            )
        }

        let functionUtterances: [String]
        do {
            spoken.append("VoiceOver service: \(voiceOver.debugDescription)")
            let focusedDialogue = try currentUtterance()
            spoken.append("Focused Dialogue: \(focusedDialogue)")
            guard focusedDialogue.localizedCaseInsensitiveContains("Dialogue") else {
                attachTranscript()
                XCTFail("VoiceOver did not follow accessibility focus to Dialogue.")
                return
            }

            var traversed = [focusedDialogue]
            var nextExpectedIndex = 1
            for step in 1...16 where nextExpectedIndex < expectedFunctions.count {
                app.typeKey(.tab, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let utterance = try currentUtterance()
                spoken.append("Tab \(step): \(utterance)")
                let mentionedIndices = expectedFunctions.indices.filter { index in
                    utterance.localizedCaseInsensitiveContains(expectedFunctions[index])
                }
                if mentionedIndices.contains(nextExpectedIndex) {
                    traversed.append(utterance)
                    nextExpectedIndex += 1
                } else if mentionedIndices.contains(where: { $0 > nextExpectedIndex }) {
                    attachTranscript()
                    XCTFail("VoiceOver announced a Research function out of order.")
                    return
                }
            }
            guard nextExpectedIndex == expectedFunctions.count else {
                attachTranscript()
                XCTFail("VoiceOver did not announce every Research function in order.")
                return
            }
            functionUtterances = traversed
        } catch {
            attachTranscript(error)
            throw error
        }

        let transcript = spoken.enumerated().map { index, spokenItem in
            "\(index + 1). \(spokenItem)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "Research Strip VoiceOver transcript"
        attachment.lifetime = .keepAlways
        add(attachment)

        for (expected, actual) in zip(expectedFunctions, functionUtterances) {
            XCTAssertTrue(
                actual.localizedCaseInsensitiveContains(expected),
                "Expected VoiceOver to announce \(expected), but heard \(actual).\n\(transcript)"
            )
        }
    }

    @MainActor
    func testResearchStripAndPanelRemainUsableInLightAndDarkAppearances() {
        for appearance in QAAppearance.allCases {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID,
                windowWidth: 1380,
                appearance: appearance
            )
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 15),
                "The \(appearance.displayName) QA window did not appear."
            )
            waitForDocumentSurface()

            let window = app.windows.firstMatch
            let strip = app.descendants(matching: .any)["scholium.researchStrip"]
            XCTAssertTrue(strip.waitForExistence(timeout: 5))
            let functions = ["Dialogue", "Develop", "Review", "Fidelity"].map { title in
                app.buttons[title].firstMatch
            }
            for function in functions {
                XCTAssertTrue(function.exists)
                XCTAssertTrue(function.isHittable)
                XCTAssertGreaterThanOrEqual(function.frame.minX, window.frame.minX)
                XCTAssertLessThanOrEqual(function.frame.maxX, window.frame.maxX)
            }
            for pair in zip(functions, functions.dropFirst()) {
                XCTAssertLessThan(pair.0.frame.minX, pair.1.frame.minX)
            }

            app.descendants(matching: .any)["scholium.researchFunction.dialogue"].click()
            let sheet = app.sheets.firstMatch
            let panel = sheet.descendants(matching: .any)["scholium.researchFunctionPanel"]
            XCTAssertTrue(panel.waitForExistence(timeout: 8))
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFunctionTarget"
            ].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFunctionMaterials"
            ].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFunctionScope"
            ].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFunctionInstruction"
            ].exists)
            XCTAssertTrue(sheet.buttons["Cancel"].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.prepareResearchFunction"
            ].exists)

            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Research Strip and Dialogue — \(appearance.displayName)"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
        }
    }

    @MainActor
    func testCritiqueRequestUsesTriptychResearchGuidanceWithoutAdHocPrompting() throws {
        waitForDocumentSurface()
        app.radioButtons["Works"].click()

        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()

        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(waitUntil(timeout: 8) { metadata.value as? String == "QA Work" })

        let critique = app.descendants(matching: .any)[
            "scholium.researchFunction.critique"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) {
            critique.exists && critique.isEnabled && critique.isHittable
        })
        critique.click()

        let panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionTarget"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionMaterials"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionScope"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionComments"].exists)
        XCTAssertTrue(app.radioButtons["Whole"].exists)
        XCTAssertTrue(app.radioButtons["Passage"].exists)

        let prepareRun = app.descendants(matching: .any)["scholium.prepareResearchFunction"]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled && prepareRun.isHittable })
        prepareRun.click()
        let copy = app.descendants(matching: .any)[
            "scholium.copyResearchFunctionInstructions"
        ]
        XCTAssertTrue(copy.waitForExistence(timeout: 8))
        copy.click()
        let copiedInstructions = try pasteboardText()
        XCTAssertTrue(copiedInstructions.contains("scholium-critique"))
        XCTAssertTrue(copiedInstructions.contains("QA Work.md"))
        XCTAssertTrue(panel.exists)
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
    }

    @MainActor
    func testCritiqueFindingOpensExactWorkPassageInSource() throws {
        waitForDocumentSurface()
        app.radioButtons["Works"].click()

        let critiquesFolder = app.buttons["Critiques"].firstMatch
        XCTAssertTrue(critiquesFolder.waitForExistence(timeout: 8))
        critiquesFolder.click()

        let critiqueRow = app.descendants(matching: .any)[
            "scholium.noteRow.Critiques/QA Critique.md"
        ]
        XCTAssertTrue(critiqueRow.waitForExistence(timeout: 8))
        critiqueRow.click()

        let provenance = app.descendants(matching: .any)["scholium.critiqueProvenance"]
        XCTAssertTrue(provenance.waitForExistence(timeout: 8))
        let agentAttribution = provenance.staticTexts
            .matching(NSPredicate(format: "value CONTAINS %@", "Agent-authored Critique"))
            .firstMatch
        XCTAssertTrue(agentAttribution.waitForExistence(timeout: 3))

        let findings = provenance.descendants(matching: .any)["scholium.critiqueFindings"]
        XCTAssertTrue(findings.waitForExistence(timeout: 5))
        findings.click()

        let finding = app.buttons["Traced: Topic connection"].firstMatch
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        XCTAssertTrue(finding.isEnabled)
        finding.click()

        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(waitUntil(timeout: 8) { metadata.value as? String == "QA Work" })
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        XCTAssertTrue((sourceEditor.value as? String ?? "").contains("[[QA Topic]]"))
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testDocumentModesInspectorAndSearchAreKeyboardReachable() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        XCTAssertTrue(app.menuItems["Live Preview"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])

        let inspector = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        XCTAssertTrue(inspector.exists)

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditorCommandsAreReachableFromNativeAndContextMenus() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.click()

        let format = app.menuBars.menuBarItems["Format"]
        XCTAssertTrue(format.waitForExistence(timeout: 3))
        format.click()
        let bold = app.menuItems["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 3))
        XCTAssertTrue(bold.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        let insert = app.menuBars.menuBarItems["Insert"]
        XCTAssertTrue(insert.waitForExistence(timeout: 3))
        insert.click()
        XCTAssertTrue(app.menuItems["Footnote"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Table"].firstMatch.exists)
        XCTAssertTrue(app.menuItems["Add Comment…"].firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])

        editor.rightClick()
        XCTAssertTrue(app.menuItems["Bold"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Add Comment…"].firstMatch.exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testSearchThisNoteReportsMatchesNoResultsAndCloses() throws {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let nativeDocument = app.descendants(matching: .any)["Markdown reader"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists || nativeDocument.exists })

        app.typeKey("f", modifierFlags: [.command])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let searchMode = app.descendants(matching: .any)["scholium.searchMode"]
        XCTAssertFalse(searchMode.exists)

        typeCommittedText("analysis", into: field, in: app)
        XCTAssertTrue(searchMode.waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["This Note"].exists)
        XCTAssertTrue(app.radioButtons["This Vault"].exists)
        XCTAssertTrue(app.radioButtons["Triptych"].exists)
        app.radioButtons["This Note"].click()
        XCTAssertTrue(result.waitForExistence(timeout: 8))

        field.click()
        field.typeKey("a", modifierFlags: [.command])
        typeCommittedText("not in this rendered note", into: field, in: app)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !result.exists
        })

        app.buttons["Close"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        XCTAssertTrue(renderedDocument.exists || nativeDocument.exists)
    }

    @MainActor
    func testSearchOpensTheSelectedResultFromTheKeyboard() throws {
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        typeCommittedText("analysis", into: field, in: app)
        let thisNote = app.radioButtons["This Note"]
        XCTAssertTrue(thisNote.waitForExistence(timeout: 5))
        thisNote.click()
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        field.click()
        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(waitUntil(timeout: 5) { !search.exists })
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.renderedDocument.QA Autosave A.md"
            ].waitForExistence(timeout: 10),
            "The selected Search result did not finish rendering in Read mode."
        )
    }

    @MainActor
    func testSearchKeepsDirectResultsSeparateFromRelatedConnections() throws {
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        typeCommittedText("QA Topic", into: field, in: app)
        XCTAssertTrue(app.radioButtons["Triptych"].waitForExistence(timeout: 5))

        let directTopic = app.descendants(matching: .any)["scholium.searchResult.QA Topic.md"]
        let relatedAnalysis = app.descendants(matching: .any)[
            "scholium.relatedSearchResult.QA Autosave A.md"
        ]
        let directWork = app.descendants(matching: .any)[
            "scholium.searchResult.QA Work.md"
        ]
        XCTAssertTrue(directTopic.waitForExistence(timeout: 10))
        XCTAssertTrue(relatedAnalysis.waitForExistence(timeout: 10))
        XCTAssertTrue(directWork.exists)
        XCTAssertTrue(app.staticTexts["Related"].exists)
        XCTAssertTrue(app.staticTexts[
            "Direct Topic connections. Related items do not affect search ranking."
        ].exists)

        relatedAnalysis.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !search.exists })
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
    }

    @MainActor
    func testSearchExplainsTitleAliasHeadingAndBodyRanking() throws {
        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        try write(
            "---\ntitle: Deliberative Autonomy\n---\nA concise account.\n",
            to: analyses.appendingPathComponent("Ranking Title.md")
        )
        try write(
            "---\ntitle: Agency Structure\naliases: [Deliberative Autonomy]\n---\nA concise account.\n",
            to: analyses.appendingPathComponent("Ranking Alias.md")
        )
        try write(
            "---\ntitle: Normative Architecture\n---\n# Deliberative Autonomy\nA concise account.\n",
            to: analyses.appendingPathComponent("Ranking Heading.md")
        )
        try write(
            "---\ntitle: Practical Reason\n---\nThis account develops deliberative autonomy in ordinary prose.\n",
            to: analyses.appendingPathComponent("Ranking Body.md")
        )
        // Relaunching makes the four synthetic notes part of one deterministic
        // initial scan instead of relying on watcher timing during the query.
        relaunchApplication(windowWidth: 1380)
        waitForDocumentSurface()

        app.typeKey("f", modifierFlags: [.command, .shift])
        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        typeCommittedText("deliberative autonomy", into: field, in: app)
        let thisVault = app.radioButtons["This Vault"]
        XCTAssertTrue(thisVault.waitForExistence(timeout: 5))
        thisVault.click()

        let title = app.descendants(matching: .any)["scholium.searchResult.Ranking Title.md"]
        let alias = app.descendants(matching: .any)["scholium.searchResult.Ranking Alias.md"]
        let heading = app.descendants(matching: .any)["scholium.searchResult.Ranking Heading.md"]
        let body = app.descendants(matching: .any)["scholium.searchResult.Ranking Body.md"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(alias.waitForExistence(timeout: 10))
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        XCTAssertTrue(body.waitForExistence(timeout: 10))

        XCTAssertTrue(title.label.contains(", Title,"))
        XCTAssertTrue(alias.label.contains(", Alias,"))
        XCTAssertTrue(heading.label.contains(", Heading,"))
        XCTAssertTrue(body.label.contains(", Body,"))
        XCTAssertLessThan(title.frame.minY, alias.frame.minY)
        XCTAssertLessThan(alias.frame.minY, heading.frame.minY)
        XCTAssertLessThan(heading.frame.minY, body.frame.minY)
    }

    @MainActor
    func testResponsiveDocumentLayoutPreservesNavigationAndContextRoutes() throws {
        waitForDocumentSurface()
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 1200)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.researchInspector"].exists)
        let wideInspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        XCTAssertTrue(wideInspectorButton.waitForExistence(timeout: 5))
        wideInspectorButton.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchInspector"].waitForExistence(timeout: 10))

        relaunchApplication(windowWidth: 1080)
        waitForDocumentSurface()
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 980)
        XCTAssertLessThan(app.windows.firstMatch.frame.width, 1200)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.researchInspector"].exists)
        openAndCloseAdaptiveInspector()

        relaunchApplication(windowWidth: 900)
        waitForDocumentSurface()
        XCTAssertLessThan(app.windows.firstMatch.frame.width, 980)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.researchInspector"].exists)
        openAndCloseAdaptiveInspector()

        app.menuBars.menuBarItems["View"].click()
        let collapseNote = app.menuItems["Collapse Note"]
        XCTAssertTrue(collapseNote.waitForExistence(timeout: 3))
        XCTAssertTrue(collapseNote.isEnabled)
        collapseNote.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.triptychInterface"].waitForExistence(timeout: 5))
        let note = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.click()
        waitForDocumentSurface()
    }

    @MainActor
    func testResearchFunctionPanelFitsWideAndCompactEditors() throws {
        waitForDocumentSurface()

        let wideWindow = app.windows.firstMatch
        XCTAssertGreaterThanOrEqual(wideWindow.frame.width, 1200)
        openResearchFunctionAndVerifyPanel(
            minimumWidth: 540,
            maximumWidth: 720,
            window: wideWindow
        )

        app.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.app.sheets.firstMatch.exists })

        relaunchApplication(windowWidth: 900)
        waitForDocumentSurface()

        let compactWindow = app.windows.firstMatch
        XCTAssertLessThan(compactWindow.frame.width, 980)
        openResearchFunctionAndVerifyPanel(
            minimumWidth: 540,
            maximumWidth: 720,
            window: compactWindow
        )
    }

    @MainActor
    func testColdCompactLaunchStartsWithTheDocumentUnobscured() throws {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, windowWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let adaptiveInspector = app.descendants(matching: .any)["scholium.adaptiveContextPanel"]
        XCTAssertFalse(
            adaptiveInspector.waitForExistence(timeout: 1.5),
            "A cold compact window must not flash a blocking Research Inspector sheet."
        )
        waitForDocumentSurface()
        XCTAssertFalse(adaptiveInspector.exists)

        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.isEnabled)
    }

    @MainActor
    func testClosingLastNoteContractsToLibraryAndSelectionExpandsDocument() throws {
        waitForDocumentSurface()
        let window = app.windows.firstMatch
        XCTAssertGreaterThanOrEqual(window.frame.width, 760)

        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(app.descendants(matching: .any)["scholium.triptychInterface"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { window.frame.width <= 390 })
        XCTAssertFalse(app.buttons["Triptych Home"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.researchStrip"].exists)
        let triptychManagement = app.menuButtons["Triptych management"]
        XCTAssertTrue(triptychManagement.exists)
        let collapsedManagementFrame = triptychManagement.frame
        let libraryFilters = app.menuButtons["Library filters"]
        XCTAssertTrue(libraryFilters.waitForExistence(timeout: 5))
        XCTAssertFalse(app.menuButtons["Research filters"].exists)
        XCTAssertFalse(app.menuButtons["Tag filter"].exists)
        XCTAssertFalse(app.menuButtons["Metadata filters"].exists)
        XCTAssertFalse(app.menuButtons["Sort notes"].exists)
        libraryFilters.click()
        XCTAssertTrue(app.menuItems["Research State"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Tag"].exists)
        XCTAssertTrue(app.menuItems["Status"].exists)
        XCTAssertTrue(app.menuItems["Sort"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(app.buttons["Collapse Note"].exists)

        let note = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.click()
        waitForDocumentSurface()
        XCTAssertTrue(waitUntil(timeout: 5) { window.frame.width >= 760 })
        let collapseNote = app.buttons["Collapse Note"]
        XCTAssertTrue(collapseNote.waitForExistence(timeout: 5))
        let expandedTriptychManagement = app.menuButtons["Triptych management"]
        XCTAssertTrue(expandedTriptychManagement.exists)
        XCTAssertEqual(
            expandedTriptychManagement.frame.size,
            collapsedManagementFrame.size,
            "Triptych management must not resize when Collapse Note joins its control group."
        )
        XCTAssertFalse(
            app.buttons["Hide Sidebar"].exists,
            "Triptych Interface owns retraction; the duplicate system sidebar toggle must stay absent."
        )
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")

        collapseNote.click()
        XCTAssertTrue(waitUntil(timeout: 5) { window.frame.width <= 390 })
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Collapse Note"].exists)
    }

    @MainActor
    func testTwoHundredPercentDocumentTextPersistsAcrossEveryMode() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, windowWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.documentTextSizeMenu"].exists,
            "Text size belongs in the View menu rather than permanent document chrome."
        )

        app.menuBars.menuBarItems["View"].click()
        let documentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(documentTextSizeMenu.waitForExistence(timeout: 3))
        documentTextSizeMenu.hover()
        let twoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(twoHundredPercent.waitForExistence(timeout: 3))
        twoHundredPercent.click()

        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        mode.click()
        let livePreview = app.menuItems["Live Preview"].firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()
        XCTAssertTrue(app.descendants(matching: .any)["Markdown live preview editor"].waitForExistence(timeout: 8))

        mode.click()
        let source = app.menuItems["Source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.click()
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))

        mode.click()
        let read = app.menuItems["Read"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 3))
        read.click()
        waitForDocumentSurface()

        let sessionFile = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let data = try? Data(contentsOf: sessionFile),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let scale = snapshot["documentTextScale"] as? NSNumber else { return false }
            return scale.doubleValue == 2.0
        })

        app.terminate()
        app = configuredApplication(sessionID: sessionID, windowWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        app.menuBars.menuBarItems["View"].click()
        let restoredDocumentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(restoredDocumentTextSizeMenu.waitForExistence(timeout: 3))
        restoredDocumentTextSizeMenu.hover()
        let restoredTwoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(restoredTwoHundredPercent.waitForExistence(timeout: 3))
        XCTAssertFalse(
            restoredTwoHundredPercent.isEnabled,
            "The restored window session must reapply 200% after asynchronous workspace restoration."
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testPrototypeTrailingContextUsesOneSharedRegion() throws {
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let historyButton = app.buttons["scholium.noteHistoryButton"]
        let history = app.descendants(matching: .any)["scholium.noteHistoryPanel"]

        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        XCTAssertTrue(historyButton.exists)
        historyButton.click()
        XCTAssertTrue(history.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })

        let inspectorButton = app.buttons["scholium.researchInspectorButton"]
        inspectorButton.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 5) { !history.exists })
    }

    @MainActor
    func testLivePreviewHidesYAMLAndSourceShortcutIsUnavailable() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)

        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertEqual(mode.value as? String, "Live Preview", "Source must be entered through the document-mode menu")

        mode.click()
        let source = app.menuItems
            .matching(identifier: "chevron.left.forwardslash.chevron.right")
            .firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        source.click()
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertEqual(mode.value as? String, "Source")
    }

    @MainActor
    func testNewWindowCreatesIndependentDocumentSurface() throws {
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count >= 2 })
        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
    }

    @MainActor
    func testCommittedEditConvergesAcrossIndependentWindows() throws {
        // A fixed session override is appropriate for deterministic relaunch
        // tests, but two live windows must own distinct session identities.
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            windowWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let editingWindow = app.windows.firstMatch
        let editingMetadata = editingWindow.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(waitUntil(timeout: 10) { editingMetadata.value as? String == "QA Autosave A" })

        let token = " SHARED-\(UUID().uuidString)"
        let firstURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(token, in: editingWindow)
        XCTAssertFalse(try source(at: firstURL).contains(token))

        let secondRow = editingWindow.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        secondRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) { editingMetadata.value as? String == "QA Autosave B" })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })

        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
        let observingWindow = app.windows.firstMatch
        let observingMetadata = observingWindow.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(
            waitUntil(timeout: 8) { observingMetadata.value as? String == "QA Autosave A" },
            "The observing window must retain its own selection after the peer window navigates."
        )

        let mode = observingWindow.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.click()
        let sourceMode = app.menuItems
            .matching(identifier: "chevron.left.forwardslash.chevron.right")
            .firstMatch
        XCTAssertTrue(sourceMode.waitForExistence(timeout: 3))
        sourceMode.click()
        let sourceEditor = observingWindow.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        XCTAssertTrue(
            waitUntil(timeout: 8) { (sourceEditor.value as? String ?? "").contains(token) },
            "A clean peer window must converge to the committed shared-runtime revision."
        )
        XCTAssertFalse(observingWindow.buttons["Compare Changes"].exists)
    }

    @MainActor
    func testExternalRenameConvergesAcrossIndependentWindows() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            windowWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let windows = app.windows.allElementsBoundByIndex
        XCTAssertEqual(windows.count, 2)
        for window in windows {
            let metadata = window.descendants(matching: .any)["scholium.metadataDisclosure"]
            XCTAssertTrue(waitUntil(timeout: 10) { metadata.value as? String == "QA Autosave A" })
        }

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let originalURL = analyses.appendingPathComponent("QA Autosave A.md")
        let renamedPath = "QA Shared Rename.md"
        let renamedURL = analyses.appendingPathComponent(renamedPath)
        let originalSource = try source(at: originalURL)
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)

        for window in windows {
            let renamedRow = window.descendants(matching: .any)["scholium.noteRow.\(renamedPath)"]
            let originalRow = window.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
            let metadata = window.descendants(matching: .any)["scholium.metadataDisclosure"]
            XCTAssertTrue(
                renamedRow.waitForExistence(timeout: 12),
                "Every independent window must receive the shared runtime rename."
            )
            XCTAssertTrue(waitUntil(timeout: 12) { !originalRow.exists })
            XCTAssertTrue(
                waitUntil(timeout: 12) { metadata.value as? String == "QA Autosave A" },
                "Each window must migrate its own selected document session to the rebound path."
            )
            XCTAssertFalse(window.staticTexts["Confirm Note Identity"].exists)
        }
        XCTAssertEqual(try source(at: renamedURL), originalSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
    }

    @MainActor
    func testDirtyWindowRejectsAPeerCommitAndPreservesItsOwnBuffer() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            windowWidth: 1380,
            usesFixedSessionID: false,
            autosaveDelayMS: 20_000
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let openedWindows = app.windows.allElementsBoundByIndex
        let dirtyWindowID = openedWindows[0].identifier
        let peerWindowID = openedWindows[1].identifier
        XCTAssertNotEqual(dirtyWindowID, peerWindowID)
        let dirtyWindow = app.windows[dirtyWindowID]
        let peerWindow = app.windows[peerWindowID]

        let localToken = " LOCAL-WINDOW-\(UUID().uuidString)"
        let peerToken = " PEER-WINDOW-\(UUID().uuidString)"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(localToken, in: dirtyWindow)
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        peerWindow.click()
        try enterLivePreviewAndAppend(peerToken, in: peerWindow)
        let peerSecondRow = peerWindow.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(peerSecondRow.waitForExistence(timeout: 5))
        peerSecondRow.click()
        XCTAssertTrue(waitUntil(timeout: 10) { (try? self.source(at: noteURL).contains(peerToken)) == true })
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        let compare = dirtyWindow.buttons["Compare Changes"]
        XCTAssertTrue(
            compare.waitForExistence(timeout: 12),
            "A peer commit must become a persistent conflict in a dirty independent window."
        )
        let dirtyEditor = dirtyWindow.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(dirtyEditor.waitForExistence(timeout: 5))
        XCTAssertTrue((dirtyEditor.value as? String ?? "").contains(localToken))
        XCTAssertFalse((dirtyEditor.value as? String ?? "").contains(peerToken))

        compare.click()
        XCTAssertTrue(
            dirtyWindow.descendants(matching: .any)["scholium.conflictComparison"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(dirtyWindow.buttons["Return to Editing"].exists)
        XCTAssertTrue(dirtyWindow.buttons["Reload from Disk"].exists)
        XCTAssertTrue(try source(at: noteURL).contains(peerToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))
    }

    @MainActor
    func testFocusedCommandsStayInTheActiveIndependentWindow() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            windowWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let openedWindows = app.windows.allElementsBoundByIndex
        let firstWindow = app.windows[openedWindows[0].identifier]
        let secondWindow = app.windows[openedWindows[1].identifier]
        let firstMode = firstWindow.descendants(matching: .any)["scholium.documentModeMenu"]
        let secondMode = secondWindow.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(firstMode.waitForExistence(timeout: 8))
        XCTAssertTrue(secondMode.waitForExistence(timeout: 8))
        XCTAssertEqual(firstMode.value as? String, "Read")
        XCTAssertEqual(secondMode.value as? String, "Read")

        firstWindow.click()
        app.typeKey("e", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { firstMode.value as? String == "Live Preview" })
        XCTAssertEqual(
            secondMode.value as? String,
            "Read",
            "The document-mode command must be routed only to the focused scene."
        )

        secondWindow.click()
        app.typeKey("f", modifierFlags: [.command])
        let firstSearch = firstWindow.descendants(matching: .any)["scholium.searchWorkspace"]
        let secondSearch = secondWindow.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(secondSearch.waitForExistence(timeout: 5))
        XCTAssertFalse(firstSearch.exists)
        secondWindow.buttons["Close"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !secondSearch.exists })
        XCTAssertEqual(firstMode.value as? String, "Live Preview")
        XCTAssertEqual(secondMode.value as? String, "Read")
    }

    @MainActor
    func testIndependentWindowSessionsRestoreTogetherAfterRelaunch() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            windowWidth: 1380,
            usesFixedSessionID: false,
            ignoresSystemWindowRestoration: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        while app.windows.count > 1 {
            closeFrontmostWindow()
            XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count >= 1 })
        }

        let originalWindow = app.windows.firstMatch
        let originalMetadata = originalWindow.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(waitUntil(timeout: 10) { originalMetadata.value as? String == "QA Autosave A" })
        let originalWindowID = originalWindow.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let openedWindows = app.windows.allElementsBoundByIndex
        let secondWindow = try XCTUnwrap(
            openedWindows.first(where: { $0.identifier != originalWindowID })
        )
        let secondRow = secondWindow.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 8))
        secondRow.click()
        let secondMetadata = secondWindow.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(waitUntil(timeout: 8) { secondMetadata.value as? String == "QA Autosave B" })

        let secondMode = secondWindow.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(secondMode.waitForExistence(timeout: 5))
        secondMode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()
        XCTAssertTrue(waitUntil(timeout: 8) { secondMode.value as? String == "Live Preview" })

        let sessionsDirectory = homeDirectory
            .appendingPathComponent("ApplicationSupport/Window Sessions", isDirectory: true)
        XCTAssertTrue(waitUntil(timeout: 8) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil
            ) else { return false }
            let snapshots = files.compactMap { try? Data(contentsOf: $0) }
            let sources = snapshots.compactMap { String(data: $0, encoding: .utf8) }
            return sources.contains { $0.contains("QA Autosave A.md") }
                && sources.contains { $0.contains("QA Autosave B.md") && $0.contains("livePreview") }
        })

        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.state == .notRunning })

        app.launch()
        XCTAssertTrue(waitUntil(timeout: 20) { self.app.windows.count == 2 })
        XCTAssertTrue(waitUntil(timeout: 15) {
            let titles = self.app.windows.allElementsBoundByIndex.compactMap { window in
                window.descendants(matching: .any)["scholium.metadataDisclosure"].value as? String
            }
            return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
        })

        let restoredWindows = app.windows.allElementsBoundByIndex
        let restoredA = try XCTUnwrap(restoredWindows.first { window in
            window.descendants(matching: .any)["scholium.metadataDisclosure"].value as? String
                == "QA Autosave A"
        })
        let restoredB = try XCTUnwrap(restoredWindows.first { window in
            window.descendants(matching: .any)["scholium.metadataDisclosure"].value as? String
                == "QA Autosave B"
        })
        XCTAssertEqual(
            restoredA.descendants(matching: .any)["scholium.documentModeMenu"].value as? String,
            "Read"
        )
        let restoredBMode = restoredB.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(waitUntil(timeout: 10) { restoredBMode.value as? String == "Live Preview" })

        restoredB.click()
        app.menuBars.menuBarItems["Window"].click()
        let mergeWindows = app.menuItems["Merge Scholium Windows"]
        XCTAssertTrue(mergeWindows.waitForExistence(timeout: 3))
        XCTAssertTrue(mergeWindows.isEnabled)
        mergeWindows.click()

        app.menuBars.menuBarItems["Window"].click()
        let moveTabToNewWindow = app.menuItems["Move Scholium Tab to New Window"]
        XCTAssertTrue(
            moveTabToNewWindow.waitForExistence(timeout: 5),
            "The restored windows must participate in the native macOS window tab group."
        )
        XCTAssertTrue(
            app.menuItems["Show Previous Tab"].isEnabled,
            "AppKit must expose navigation for the native tab group after merging."
        )
        XCTAssertTrue(moveTabToNewWindow.isEnabled)
        moveTabToNewWindow.click()
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        XCTAssertTrue(waitUntil(timeout: 8) {
            let titles = self.app.windows.allElementsBoundByIndex.compactMap { window in
                window.descendants(matching: .any)["scholium.metadataDisclosure"].value as? String
            }
            return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
        })
    }

    @MainActor
    func testLifecycleCardsPreserveTheOpenDocumentAndLibraryGeometry() throws {
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        let library = app.buttons["Library"]
        let setAside = app.buttons["Set Aside"]
        let trash = app.buttons["Trash"]
        let sourceRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 5))

        let documentTitle = metadata.value as? String
        let libraryFrame = library.frame
        let setAsideFrame = setAside.frame
        let trashFrame = trash.frame

        setAside.click()
        let collapseSetAside = app.buttons["Collapse Set Aside"]
        XCTAssertTrue(collapseSetAside.waitForExistence(timeout: 8))
        XCTAssertEqual(metadata.value as? String, documentTitle)
        XCTAssertTrue(library.isSelected)
        XCTAssertTrue(sourceRow.exists)
        XCTAssertEqual(library.frame, libraryFrame)
        XCTAssertEqual(setAside.frame, setAsideFrame)
        XCTAssertEqual(trash.frame, trashFrame)

        trash.click()
        let collapseTrash = app.buttons["Collapse Trash"]
        XCTAssertTrue(collapseTrash.waitForExistence(timeout: 8))
        XCTAssertFalse(collapseSetAside.exists)
        XCTAssertEqual(metadata.value as? String, documentTitle)
        XCTAssertTrue(library.isSelected)
        XCTAssertTrue(sourceRow.exists)
        XCTAssertEqual(library.frame, libraryFrame)
        XCTAssertEqual(setAside.frame, setAsideFrame)
        XCTAssertEqual(trash.frame, trashFrame)

        collapseTrash.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !collapseTrash.exists })
        XCTAssertEqual(metadata.value as? String, documentTitle)
    }

    @MainActor
    func testTrashAndPutBackPreserveExactSourceThroughTheLifecycleUI() throws {
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let trashURL = triptychDirectory.appendingPathComponent("01-analyses/Trash/QA Autosave A.md")
        let originalSource = try source(at: sourceURL)

        let sourceRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        sourceRow.rightClick()
        let moveToTrash = app.menuItems["Move to Trash…"]
        XCTAssertTrue(moveToTrash.waitForExistence(timeout: 3))
        moveToTrash.click()

        let confirmMove = app.windows.firstMatch.buttons["Move to Trash"]
        XCTAssertTrue(confirmMove.waitForExistence(timeout: 3))
        confirmMove.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                FileManager.default.fileExists(atPath: trashURL.path)
                    && !FileManager.default.fileExists(atPath: sourceURL.path)
            },
            "Move to Trash must relocate the exact note instead of copying or deleting it."
        )
        XCTAssertEqual(try source(at: trashURL), originalSource)

        // SwiftUI currently propagates the sidebar container identifier to
        // these native buttons. Their visible VoiceOver names are the stable
        // user contract and exercise the same route as Full Keyboard Access.
        let trashLocation = app.buttons["Trash"]
        XCTAssertTrue(trashLocation.waitForExistence(timeout: 5))
        trashLocation.click()
        let collapseTrash = app.buttons["Collapse Trash"]
        XCTAssertTrue(collapseTrash.waitForExistence(timeout: 8))
        let trashedNote = app.buttons["QA Autosave A"]
        XCTAssertTrue(trashedNote.waitForExistence(timeout: 5))
        trashedNote.rightClick()
        let putBackMenuItem = app.menuItems["Put Back…"]
        XCTAssertTrue(putBackMenuItem.waitForExistence(timeout: 3))
        putBackMenuItem.click()

        XCTAssertTrue(app.staticTexts["Put Back Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["QA Autosave A.md"].waitForExistence(timeout: 5))
        let putBack = app.windows.firstMatch.buttons["Put Back"]
        XCTAssertTrue(putBack.waitForExistence(timeout: 5))
        XCTAssertTrue(putBack.isEnabled)
        putBack.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                FileManager.default.fileExists(atPath: sourceURL.path)
                    && !FileManager.default.fileExists(atPath: trashURL.path)
            },
            "Put Back must return the trashed note to its exact original vault-relative path."
        )
        XCTAssertEqual(try source(at: sourceURL), originalSource)

        XCTAssertTrue(collapseTrash.waitForExistence(timeout: 5))
        collapseTrash.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
                .waitForExistence(timeout: 8)
        )
    }

    @MainActor
    func testPermanentDeletionPurgesTrashedSourceAndContainingCheckpoint() throws {
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let trashURL = triptychDirectory.appendingPathComponent("01-analyses/Trash/QA Autosave A.md")
        let checkpointName = "QA Permanent Deletion \(UUID().uuidString.prefix(8))"

        app.menuBars.menuBarItems["Research"].click()
        let createCheckpoint = app.menuItems["Create Checkpoint…"]
        XCTAssertTrue(createCheckpoint.waitForExistence(timeout: 3))
        createCheckpoint.click()

        let nameField = app.textFields["Checkpoint name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText(checkpointName)
        let create = app.windows.firstMatch.buttons["Create Checkpoint"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(
            waitUntil(timeout: 15) { !nameField.exists },
            "The containing checkpoint must be durable before permanent deletion begins."
        )

        let sourceRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 10))
        sourceRow.rightClick()
        let moveToTrash = app.menuItems["Move to Trash…"]
        XCTAssertTrue(moveToTrash.waitForExistence(timeout: 3))
        moveToTrash.click()
        let confirmMove = app.windows.firstMatch.buttons["Move to Trash"]
        XCTAssertTrue(confirmMove.waitForExistence(timeout: 3))
        confirmMove.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                FileManager.default.fileExists(atPath: trashURL.path)
                    && !FileManager.default.fileExists(atPath: sourceURL.path)
                    && !sourceRow.exists
            },
            "The note must enter Trash and leave the live library before the irreversible action is offered."
        )

        let trashLocation = app.buttons["Trash"]
        XCTAssertTrue(trashLocation.waitForExistence(timeout: 5))
        trashLocation.click()
        let collapseTrash = app.buttons["Collapse Trash"]
        XCTAssertTrue(collapseTrash.waitForExistence(timeout: 8))
        let trashedNote = app.buttons["QA Autosave A"]
        XCTAssertTrue(trashedNote.waitForExistence(timeout: 5))
        trashedNote.rightClick()
        let deletePermanently = app.menuItems["Delete Permanently…"]
        XCTAssertTrue(deletePermanently.waitForExistence(timeout: 3))
        deletePermanently.click()

        XCTAssertTrue(app.staticTexts["Delete Permanently?"].waitForExistence(timeout: 5))
        let confirmationSheet = app.sheets
            .matching(NSPredicate(format: "label == %@", "alert"))
            .firstMatch
        XCTAssertTrue(confirmationSheet.waitForExistence(timeout: 5))
        let confirmation = confirmationSheet.buttons["Delete Permanently"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                !FileManager.default.fileExists(atPath: sourceURL.path)
                    && !FileManager.default.fileExists(atPath: trashURL.path)
                    && !trashedNote.exists
            },
            "Permanent deletion must remove both the live and trashed source with no note left in Trash."
        )

        app.menuBars.menuBarItems["Research"].click()
        let restoreFromCheckpoint = app.menuItems["Restore from Checkpoint…"]
        XCTAssertTrue(restoreFromCheckpoint.waitForExistence(timeout: 3))
        restoreFromCheckpoint.click()
        XCTAssertTrue(
            app.staticTexts["No Checkpoints"].waitForExistence(timeout: 10),
            "A checkpoint containing a permanently deleted note must be invalidated instead of retaining recoverable bytes."
        )
        XCTAssertFalse(app.staticTexts[checkpointName].exists)
    }

    @MainActor
    func testInterruptedTransactionRecoveryRequiresInspectionBeforeResolution() throws {
        waitForDocumentSurface()

        let manifestURL = triptychDirectory.appendingPathComponent(".scholium/manifest.json")
        XCTAssertTrue(
            waitUntil(timeout: 10) { FileManager.default.fileExists(atPath: manifestURL.path) },
            "The disposable Triptych must publish its portable identity before a recovery record can be bound to it."
        )
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let triptychID = try XCTUnwrap(manifest["id"] as? String)

        let interruptedSource = "# QA Interrupted Import\n\nExact disposable source that resolution must not modify.\n"
        let unclassifiedDirectory = triptychDirectory
            .appendingPathComponent(".scholium/unclassified", isDirectory: true)
        try FileManager.default.createDirectory(
            at: unclassifiedDirectory,
            withIntermediateDirectories: true
        )
        let interruptedSourceURL = unclassifiedDirectory
            .appendingPathComponent("QA Interrupted Import.md")
        try write(interruptedSource, to: interruptedSourceURL)

        let recoveryDirectory = homeDirectory
            .appendingPathComponent("ApplicationSupport/Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID, isDirectory: true)
            .appendingPathComponent("transactions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recoveryDirectory,
            withIntermediateDirectories: true
        )
        let recoveryFile = recoveryDirectory.appendingPathComponent("transaction-recovery.json")
        let failure = "Synthetic interrupted classification requires explicit file inspection."
        let payload: [String: Any] = [
            "records": [[
                "id": UUID().uuidString,
                "triptychID": triptychID,
                "operation": "unclassifiedClassification",
                "createdAt": Date().timeIntervalSinceReferenceDate,
                "failure": failure,
                "files": [[
                    "path": "QA Interrupted Import.md",
                    "alternatePath": "01-analyses/QA Interrupted Import.md",
                    "role": "classifiedSource",
                    "state": "externallyChanged",
                    "detail": "Inspect both locations before marking this recovery record complete.",
                ]],
            ]],
        ]
        let recoveryData = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try recoveryData.write(to: recoveryFile, options: .atomic)

        relaunchApplication(windowWidth: 1380)
        let notice = app.descendants(matching: .any)["scholium.transactionRecovery.notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Transaction Recovery Required"].exists)
        let inspect = app.buttons["Inspect Recovery…"]
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        inspect.click()

        XCTAssertTrue(app.staticTexts["Transaction Recovery"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Classify Imported Note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[failure].waitForExistence(timeout: 5))
        let recoveryFileRow = app.descendants(matching: .any)[
            "Externally changed, Unclassified source, Unclassified, QA Interrupted Import.md"
        ]
        XCTAssertTrue(recoveryFileRow.waitForExistence(timeout: 5))
        XCTAssertEqual(try source(at: interruptedSourceURL), interruptedSource)

        let markComplete = app.buttons["Mark Recovery Complete…"]
        XCTAssertTrue(markComplete.waitForExistence(timeout: 5))
        markComplete.click()
        XCTAssertTrue(app.staticTexts["Mark Recovery Complete?"].waitForExistence(timeout: 5))
        let confirmationSheet = app.sheets
            .matching(NSPredicate(format: "label == %@", "alert"))
            .firstMatch
        XCTAssertTrue(confirmationSheet.waitForExistence(timeout: 5))
        let confirm = confirmationSheet.buttons["Mark Recovery Complete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()

        XCTAssertTrue(app.staticTexts["No Pending Recovery"].waitForExistence(timeout: 10))
        XCTAssertEqual(
            try source(at: interruptedSourceURL),
            interruptedSource,
            "Resolving a recovery record must not mutate the file it asked the researcher to inspect."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                guard let data = try? Data(contentsOf: recoveryFile),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dictionary = object as? [String: Any],
                      let records = dictionary["records"] as? [Any] else { return false }
                return records.isEmpty
            },
            "Mark Recovery Complete must remove only the inspected durable record."
        )

        app.buttons["Close"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !notice.exists })
    }

    @MainActor
    func testSelectiveCheckpointRestorePreservesTheExactCheckpointSource() throws {
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalSource = try source(at: sourceURL)
        let checkpointName = "QA Selective Restore \(UUID().uuidString.prefix(8))"

        app.menuBars.menuBarItems["Research"].click()
        let createCheckpoint = app.menuItems["Create Checkpoint…"]
        XCTAssertTrue(createCheckpoint.waitForExistence(timeout: 3))
        createCheckpoint.click()

        let nameField = app.textFields["Checkpoint name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText(checkpointName)
        let create = app.windows.firstMatch.buttons["Create Checkpoint"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertTrue(create.isEnabled)
        create.click()
        XCTAssertTrue(
            waitUntil(timeout: 15) { !nameField.exists },
            "The checkpoint sheet must close only after the self-contained checkpoint is committed."
        )

        let token = "\n\nSelective checkpoint restore token \(UUID().uuidString)"
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: sourceURL).contains(token))

        let secondRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        secondRow.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) { (try? self.source(at: sourceURL).contains(token)) == true },
            "Navigating away must flush the edited source before checkpoint comparison begins."
        )

        app.menuBars.menuBarItems["Research"].click()
        let restoreFromCheckpoint = app.menuItems["Restore from Checkpoint…"]
        XCTAssertTrue(restoreFromCheckpoint.waitForExistence(timeout: 3))
        restoreFromCheckpoint.click()

        XCTAssertTrue(app.staticTexts["Restore from Checkpoint"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[checkpointName].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Changed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["QA Autosave A.md"].waitForExistence(timeout: 8))

        // A native SwiftUI List can briefly expose both its current row and
        // the outgoing accessibility snapshot during an asynchronous reload.
        // They represent the same checked control, so address the actionable
        // first match instead of requiring XCTest to synthesize uniqueness.
        let selection = app.checkBoxes
            .matching(identifier: "Restore QA Autosave A.md")
            .firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        let restoreSelected = app.windows.firstMatch.buttons["Restore Selected Notes"]
        XCTAssertTrue(restoreSelected.waitForExistence(timeout: 5))
        XCTAssertTrue(
            restoreSelected.isEnabled,
            "The default selection must make the selective restore action available."
        )
        restoreSelected.click()

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                !restoreSelected.exists && (try? self.source(at: sourceURL)) == originalSource
            },
            "Selective restore must write the exact checkpoint source through the repository path."
        )
        XCTAssertFalse(try source(at: sourceURL).contains(token))

        // Reopen the browser to prove that restoration also created the
        // durable recovery checkpoint promised by the confirmation copy.
        app.menuBars.menuBarItems["Research"].click()
        XCTAssertTrue(restoreFromCheckpoint.waitForExistence(timeout: 3))
        restoreFromCheckpoint.click()
        XCTAssertTrue(app.staticTexts["Before Restore"].waitForExistence(timeout: 8))
        app.windows.firstMatch.buttons["Cancel"].click()
    }

    @MainActor
    func testCompleteCheckpointRestoreMovesLaterFilesToTrash() throws {
        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let sourceURL = analyses.appendingPathComponent("QA Autosave A.md")
        let originalSource = try source(at: sourceURL)
        let checkpointName = "QA Full Restore \(UUID().uuidString.prefix(8))"

        app.menuBars.menuBarItems["Research"].click()
        let createCheckpoint = app.menuItems["Create Checkpoint…"]
        XCTAssertTrue(createCheckpoint.waitForExistence(timeout: 3))
        createCheckpoint.click()
        let nameField = app.textFields["Checkpoint name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeText(checkpointName)
        let create = app.windows.firstMatch.buttons["Create Checkpoint"]
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        create.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !nameField.exists })

        let editToken = "\n\nComplete checkpoint restore token \(UUID().uuidString)"
        try enterLivePreviewAndAppend(editToken)
        let secondRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        secondRow.click()
        XCTAssertTrue(waitUntil(timeout: 10) { (try? self.source(at: sourceURL).contains(editToken)) == true })

        let laterName = "QA Post Checkpoint.md"
        let laterSource = "# QA Post Checkpoint\n\nThis file must remain recoverable after a complete restore.\n"
        let laterURL = analyses.appendingPathComponent(laterName)
        try write(laterSource, to: laterURL)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.\(laterName)"]
                .waitForExistence(timeout: 10),
            "The shared watcher must publish the externally created post-checkpoint note."
        )

        app.menuBars.menuBarItems["Research"].click()
        let restoreFromCheckpoint = app.menuItems["Restore from Checkpoint…"]
        XCTAssertTrue(restoreFromCheckpoint.waitForExistence(timeout: 3))
        restoreFromCheckpoint.click()
        XCTAssertTrue(app.staticTexts[checkpointName].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Changed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Created Since Checkpoint"].waitForExistence(timeout: 8))

        let completeRestoreButtons = app.buttons.matching(identifier: "Restore Complete Triptych")
        let openConfirmation = completeRestoreButtons.firstMatch
        XCTAssertTrue(openConfirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(openConfirmation.isEnabled)
        openConfirmation.click()
        XCTAssertTrue(app.staticTexts["Restore the Complete Triptych?"].waitForExistence(timeout: 5))

        let confirmationSheet = app.sheets
            .matching(NSPredicate(format: "label == %@", "alert"))
            .firstMatch
        XCTAssertTrue(confirmationSheet.waitForExistence(timeout: 5))
        let confirmation = confirmationSheet.buttons["Restore Complete Triptych"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.click()

        let trashedLaterURL = analyses
            .appendingPathComponent("Trash/After \(checkpointName)", isDirectory: true)
            .appendingPathComponent(laterName)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                !FileManager.default.fileExists(atPath: laterURL.path)
                    && FileManager.default.fileExists(atPath: trashedLaterURL.path)
                    && (try? self.source(at: sourceURL)) == originalSource
            },
            "Complete restore must recover checkpoint bytes and move later files to Trash."
        )
        XCTAssertEqual(try source(at: trashedLaterURL), laterSource)
        XCTAssertFalse(try source(at: sourceURL).contains(editToken))
    }

    @MainActor
    func testCommittedWindowModeRestoresAfterRelaunch() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()
        XCTAssertTrue(waitUntil(timeout: 5) { mode.value as? String == "Live Preview" })

        let sessionFile = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let data = try? Data(contentsOf: sessionFile),
                  let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains("livePreview")
        })

        app.terminate()
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let restoredMode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(restoredMode.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                restoredMode.value as? String == "Live Preview"
            },
            "The restored window session must reapply Live Preview after asynchronous workspace restoration."
        )
    }

    @MainActor
    func testMetadataAndInspectorCanBeToggled() throws {
        let contextCluster = app.descendants(matching: .any)["scholium.documentContextCluster"]
        XCTAssertTrue(contextCluster.waitForExistence(timeout: 10))
        let contextControls = app.descendants(matching: .any)["scholium.documentContextControls"]
        XCTAssertTrue(contextControls.waitForExistence(timeout: 10))
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertTrue(metadata.isHittable)

        let controlsFrame = contextControls.frame
        let collapsedMetadataFrame = metadata.frame
        let renderedDocument = app.descendants(matching: .any)[
            "scholium.renderedDocument.QA Autosave A.md"
        ]
        XCTAssertTrue(renderedDocument.waitForExistence(timeout: 10))
        XCTAssertEqual(controlsFrame.height, collapsedMetadataFrame.height, accuracy: 1.5)
        XCTAssertEqual(controlsFrame.midY, collapsedMetadataFrame.midY, accuracy: 1.5)
        XCTAssertEqual(contextCluster.frame.width, 920, accuracy: 2)
        XCTAssertEqual(
            collapsedMetadataFrame.maxX - controlsFrame.minX,
            920,
            accuracy: 2,
            "The controls and Properties strip must jointly occupy the document measure."
        )
        XCTAssertEqual(
            contextCluster.frame.midX,
            renderedDocument.frame.midX,
            accuracy: 10,
            "The complete controls-and-Properties cluster must share the document measure."
        )

        metadata.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).click()
        XCTAssertTrue(waitUntil(timeout: 3) { metadata.label == "Hide note properties" })
        let metadataPanel = app.descendants(matching: .any)["scholium.metadataPanel"]
        XCTAssertTrue(metadataPanel.waitForExistence(timeout: 3))

        let expandedPanelFrame = metadataPanel.frame
        XCTAssertEqual(expandedPanelFrame.minX, contextCluster.frame.minX, accuracy: 2)
        XCTAssertEqual(expandedPanelFrame.maxX, contextCluster.frame.maxX, accuracy: 2)
        XCTAssertEqual(expandedPanelFrame.width, 920, accuracy: 2)

        metadata.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5)).click()
        XCTAssertTrue(waitUntil(timeout: 3) { metadata.label == "Show note properties" })
        XCTAssertTrue(waitUntil(timeout: 3) { !metadataPanel.exists })

        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        XCTAssertTrue(inspectorButton.exists)
        let inspectorWasVisible = inspector.exists
        inspectorButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { inspector.exists != inspectorWasVisible })
        inspectorButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { inspector.exists == inspectorWasVisible })
    }

    @MainActor
    func testHumanReviewCannotCompleteWithoutRequiredJudgment() throws {
        let review = app.descendants(matching: .any)[
            "scholium.researchFunction.review"
        ]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.click()

        let complete = app.buttons["Complete Review"]
        let noteField = app.textViews["Review Note"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(noteField.exists)
        XCTAssertFalse(complete.isEnabled)

        noteField.click()
        noteField.typeText("A bounded test judgment.")
        XCTAssertFalse(complete.isEnabled, "A note without a Qualified or Unqualified verdict must not complete Review")

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.exists)
        cancel.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !complete.exists })
    }

    @MainActor
    func testZoteroSourceSurfacesUnavailableWithoutAttachmentActions() throws {
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))

        let research = app.radioButtons["Research"]
        XCTAssertTrue(research.exists)
        research.click()

        XCTAssertTrue(app.staticTexts["Zotero Source"].waitForExistence(timeout: 5))
        let missing = app.staticTexts[
            "The Zotero item identified by this Analysis was not found."
        ]
        let unavailable = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Zotero is not responding")
        ).firstMatch
        let disabled = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Zotero local API access is disabled")
        ).firstMatch
        XCTAssertTrue(
            waitUntil(timeout: 8) { missing.exists || unavailable.exists || disabled.exists },
            "The inspector must name the exact Zotero-unavailable condition."
        )
        XCTAssertFalse(app.buttons["Open in Zotero"].exists)
        XCTAssertFalse(app.buttons["Open PDF in Preview"].exists)
        XCTAssertFalse(app.buttons["Open Attachment"].exists)
        XCTAssertFalse(app.buttons["Reveal in Finder"].exists)
    }

    @MainActor
    func testDirtyLivePreviewCommitsBeforeOpeningSearch() throws {
        let token = " SEARCH-\(UUID().uuidString)"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.descendants(matching: .any)["scholium.searchWorkspace"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: noteURL).contains(token)) == true })
    }

    @MainActor
    func testPendingAutosaveSurvivesInspectorViewReconstruction() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            autosaveDelayMS: 1_200
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let token = " RECONSTRUCT-\(UUID().uuidString)"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: noteURL).contains(token))

        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        XCTAssertTrue(
            waitUntil(timeout: 8) { (try? self.source(at: noteURL).contains(token)) == true },
            "A retained document session must complete its pending autosave after layout reconstruction."
        )
    }

    @MainActor
    func testDirtyLivePreviewCommitsBeforeSwitchingNotes() throws {
        let token = " SWITCH-\(UUID().uuidString)"
        let firstURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let secondURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave B.md")
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: firstURL).contains(token))

        let secondRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        secondRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            (self.app.descendants(matching: .any)["scholium.metadataDisclosure"].value as? String) == "QA Autosave B"
        })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })
        XCTAssertFalse(try source(at: secondURL).contains(token))
    }

    @MainActor
    func testCleanExternalEditRefreshesTheOpenNote() throws {
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let title = "QA External \(UUID().uuidString.prefix(8))"
        let current = try source(at: noteURL)
        let changed = current.replacingOccurrences(of: "title: QA Autosave A", with: "title: \(title)")
        try write(changed, to: noteURL)

        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 12) { metadata.value as? String == title },
            "A clean open document must refresh after an external filesystem edit."
        )
        XCTAssertEqual(try source(at: noteURL), changed)
    }

    @MainActor
    func testCleanExternalRenamePreservesTheOpenDocumentSession() throws {
        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let originalURL = analyses.appendingPathComponent("QA Autosave A.md")
        let renamedPath = "QA Externally Renamed.md"
        let renamedURL = analyses.appendingPathComponent(renamedPath)
        let originalSource = try source(at: originalURL)

        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        let originalRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
        XCTAssertTrue(originalRow.waitForExistence(timeout: 5))

        try FileManager.default.moveItem(at: originalURL, to: renamedURL)

        let renamedRow = app.descendants(matching: .any)["scholium.noteRow.\(renamedPath)"]
        XCTAssertTrue(
            renamedRow.waitForExistence(timeout: 12),
            "The watcher must publish the externally renamed path."
        )
        XCTAssertTrue(
            waitUntil(timeout: 12) { !originalRow.exists },
            "The old path must leave the note list after identity recovery."
        )
        XCTAssertTrue(
            waitUntil(timeout: 12) { metadata.value as? String == "QA Autosave A" },
            "A clean active document must remain selected after its path is rebound."
        )
        XCTAssertEqual(try source(at: renamedURL), originalSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(app.staticTexts["Confirm Note Identity"].exists)
    }

    @MainActor
    func testAmbiguousExternalRenameRequiresExplicitIdentityConfirmation() throws {
        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let firstPath = "QA Identity A.md"
        let secondPath = "QA Identity B.md"
        let movedPath = "QA Identity Moved.md"
        let firstURL = analyses.appendingPathComponent(firstPath)
        let secondURL = analyses.appendingPathComponent(secondPath)
        let movedURL = analyses.appendingPathComponent(movedPath)
        let ambiguousSource = "---\ntitle: QA Ambiguous Identity\n---\n# QA Ambiguous Identity\n\nExact shared bytes.\n"

        try write(ambiguousSource, to: firstURL)
        try write(ambiguousSource, to: secondURL)

        let firstRow = app.descendants(matching: .any)["scholium.noteRow.\(firstPath)"]
        let secondRow = app.descendants(matching: .any)["scholium.noteRow.\(secondPath)"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 12))
        XCTAssertTrue(secondRow.waitForExistence(timeout: 12))

        // Visiting both notes after the shared-runtime refresh also proves
        // their stable identities were published before the external move.
        firstRow.click()
        let researchStrip = app.descendants(matching: .any)["scholium.researchStrip"]
        XCTAssertTrue(researchStrip.waitForExistence(timeout: 8))
        secondRow.click()
        XCTAssertTrue(researchStrip.waitForExistence(timeout: 8))

        // Remove the peer first, then move the selected file immediately. On
        // the resulting inventory both prior identities are absent and both
        // have the exact fingerprint of the new path.
        try FileManager.default.removeItem(at: secondURL)
        try FileManager.default.moveItem(at: firstURL, to: movedURL)

        let movedRow = app.descendants(matching: .any)["scholium.noteRow.\(movedPath)"]
        XCTAssertTrue(movedRow.waitForExistence(timeout: 12))
        movedRow.click()

        let chooseIdentity = app.buttons["Choose Identity…"]
        XCTAssertTrue(
            chooseIdentity.waitForExistence(timeout: 12),
            "Equal fingerprints from two missing notes must remain blocked for researcher confirmation."
        )
        XCTAssertEqual(try source(at: movedURL), ambiguousSource)

        // Functions require a resolved stable Target, so the entire Strip is
        // absent while identity confirmation is pending.
        XCTAssertFalse(researchStrip.exists)

        chooseIdentity.click()
        let firstCandidate = app.radioButtons["Use the note identity previously at \(firstPath)"]
        let secondCandidate = app.radioButtons["Use the note identity previously at \(secondPath)"]
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCandidate.exists)
        firstCandidate.click()
        app.buttons["Confirm Identity"].click()

        XCTAssertTrue(waitUntil(timeout: 12) { !chooseIdentity.exists })
        XCTAssertTrue(researchStrip.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunction.review"
        ].isEnabled)
        XCTAssertEqual(try source(at: movedURL), ambiguousSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @MainActor
    func testDirtyExternalRenamePreservesTheUncommittedEditorBuffer() throws {
        let localToken = " DIRTY-RENAME-\(UUID().uuidString)"
        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let originalURL = analyses.appendingPathComponent("QA Autosave A.md")
        let renamedPath = "QA Dirty External Rename.md"
        let renamedURL = analyses.appendingPathComponent(renamedPath)
        let originalSource = try source(at: originalURL)

        try enterLivePreviewAndAppend(localToken)
        XCTAssertFalse(try source(at: originalURL).contains(localToken))

        try FileManager.default.moveItem(at: originalURL, to: renamedURL)

        let renamedRow = app.descendants(matching: .any)["scholium.noteRow.\(renamedPath)"]
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 12))
        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil(timeout: 8) { (editor.value as? String ?? "").contains(localToken) },
            "An external path change must never replace the dirty in-memory buffer."
        )

        // Autosave cannot authoritatively commit to a path that disappeared.
        // The document-local failure keeps the editor and buffer visible.
        let alert = app.windows.firstMatch.sheets.firstMatch
        let keepEditing = alert.buttons["Keep Editing"]
        XCTAssertTrue(keepEditing.waitForExistence(timeout: 12))
        XCTAssertFalse(alert.buttons["Reload from Disk"].exists)
        XCTAssertEqual(try source(at: renamedURL), originalSource)
        XCTAssertFalse(try source(at: renamedURL).contains(localToken))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))

        keepEditing.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(localToken))
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].exists,
            "The deleted-path document session must remain reachable for manual recovery while dirty."
        )
    }

    @MainActor
    func testDirtyExternalEditPreservesTheBufferAndPresentsConflictRecovery() throws {
        let localToken = " LOCAL-\(UUID().uuidString)"
        let diskToken = "\n\n## External Disk Revision\n"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(localToken)

        let originalDisk = try source(at: noteURL)
        try write(originalDisk + diskToken, to: noteURL)

        let conflictWindow = app.windows.firstMatch
        let compare = conflictWindow.buttons["Compare Changes"]
        let reload = conflictWindow.buttons["Reload from Disk"]
        let keepEditing = conflictWindow.buttons["Keep Editing"]
        XCTAssertTrue(
            compare.waitForExistence(timeout: 12),
            "A dirty buffer and external edit must produce a persistent conflict decision."
        )
        XCTAssertTrue(reload.exists)
        XCTAssertTrue(keepEditing.exists)
        XCTAssertTrue(try source(at: noteURL).contains(diskToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        compare.click()
        let comparison = app.descendants(matching: .any)["scholium.conflictComparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))
        let currentRevision = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Current Editor, SHA-256")
        ).firstMatch
        let diskRevision = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Disk Version, SHA-256")
        ).firstMatch
        XCTAssertTrue(currentRevision.exists)
        XCTAssertTrue(diskRevision.exists)
        let returnToEditing = conflictWindow.buttons["Return to Editing"]
        XCTAssertTrue(returnToEditing.exists)
        XCTAssertTrue(conflictWindow.buttons["Reload from Disk"].exists)
        returnToEditing.click()

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(localToken))
    }

    @MainActor
    func testDirtyEditorBufferSurvivesTheQAFaultRoute() throws {
        app.terminate()
        let markerURL = testDirectory.appendingPathComponent("editor-fault-invoked.txt")
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 30_000)
        app.launchArguments.append("--scholium-editor-qa-faults")
        app.launchEnvironment["SCHOLIUM_UI_TEST_EDITOR_FAULT_MARKER"] = markerURL.path
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let token = " QA-FAULT-\(UUID().uuidString)"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalSource = try source(at: noteURL)
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("w", modifierFlags: [.command, .option, .control])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (try? String(contentsOf: markerURL, encoding: .utf8)) == "QA Autosave A.md"
            },
            "The QA-only distributed fault route must reach the focused document session."
        )

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        XCTAssertTrue(
            waitUntil(timeout: 12) { (editor.value as? String ?? "").contains(token) },
            "Recovery must restore the accepted dirty buffer rather than rereading disk."
        )
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("e", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                guard let committed = try? Data(contentsOf: noteURL) else { return false }
                return committed == Data((originalSource + token).utf8)
            },
            "The recovered dirty buffer must remain eligible for the normal fingerprint-gated flush."
        )
    }

    @MainActor
    func testDocumentTabsExposeEditedAndConflictState() throws {
        let secondPath = "QA Autosave B.md"
        let firstPath = "QA Autosave A.md"
        let secondRow = app.descendants(matching: .any)["scholium.noteRow.\(secondPath)"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10))
        secondRow.rightClick()
        let openInNewTab = app.menuItems["Open in New Tab"]
        XCTAssertTrue(openInNewTab.waitForExistence(timeout: 3))
        openInNewTab.click()

        let activeTab = app.descendants(matching: .any)["scholium.documentTab.\(secondPath)"]
        let firstTab = app.descendants(matching: .any)["scholium.documentTab.\(firstPath)"]
        XCTAssertTrue(activeTab.waitForExistence(timeout: 5))
        XCTAssertTrue(firstTab.exists)

        let localToken = " TAB-STATE-\(UUID().uuidString)"
        try enterLivePreviewAndAppend(localToken)
        XCTAssertTrue(
            waitUntil(timeout: 3) { self.accessibilityText(of: activeTab).contains("Edited") },
            "The active document tab must expose its uncommitted editor state."
        )

        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/\(secondPath)")
        let originalDisk = try source(at: noteURL)
        try write(originalDisk + "\n\n## External Tab Revision\n", to: noteURL)

        firstTab.click()
        let compare = app.windows.firstMatch.buttons["Compare Changes"]
        XCTAssertTrue(compare.waitForExistence(timeout: 12))
        XCTAssertTrue(
            waitUntil(timeout: 3) { self.accessibilityText(of: activeTab).contains("Conflict") },
            "A rejected tab transition must replace Edited with the exact Conflict state."
        )
        XCTAssertTrue((try source(at: noteURL)).contains("External Tab Revision"))
        XCTAssertFalse((try source(at: noteURL)).contains(localToken))

        app.windows.firstMatch.buttons["Keep Editing"].click()
        XCTAssertTrue(activeTab.waitForExistence(timeout: 3))
        XCTAssertTrue(accessibilityText(of: activeTab).contains("Conflict"))
    }

    @MainActor
    func testConflictReloadRejectsADiskRevisionThatChangedAfterComparison() throws {
        let localToken = " LOCAL-\(UUID().uuidString)"
        let firstDiskToken = "\n\n## First External Revision\n"
        let secondDiskToken = "\n## Second External Revision\n"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(localToken)

        let originalDisk = try source(at: noteURL)
        try write(originalDisk + firstDiskToken, to: noteURL)

        let conflictWindow = app.windows.firstMatch
        let compare = conflictWindow.buttons["Compare Changes"]
        XCTAssertTrue(compare.waitForExistence(timeout: 12))
        compare.click()
        let comparison = app.descendants(matching: .any)["scholium.conflictComparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))

        try write(originalDisk + firstDiskToken + secondDiskToken, to: noteURL)
        conflictWindow.buttons["Reload from Disk"].click()

        XCTAssertTrue(
            conflictWindow.buttons["Compare Changes"].waitForExistence(timeout: 5),
            "Reload must not accept bytes that weren't shown in the comparison."
        )
        conflictWindow.buttons["Keep Editing"].click()
        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(localToken))
        XCTAssertTrue(try source(at: noteURL).contains(secondDiskToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))
    }

    @MainActor
    private func accessibilityText(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    private func assertDialogueTurns(
        in history: XCUIElement,
        containInOrder expectedTexts: [String]
    ) {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "scholium.dialogue.turn.")
        XCTAssertTrue(waitUntil(timeout: 5) {
            history.descendants(matching: .any).matching(predicate).count == expectedTexts.count
        })
        let turns = history.descendants(matching: .any)
            .matching(predicate)
            .allElementsBoundByIndex
        XCTAssertEqual(turns.count, expectedTexts.count)
        for (turn, expected) in zip(turns, expectedTexts) {
            XCTAssertTrue(
                accessibilityText(of: turn).contains(expected),
                "Dialogue turn did not preserve the expected chronological scholarly text."
            )
        }
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement
    ) {
        // macOS can report a control as reachable before its containing list
        // or scroll view has exposed an interactive frame. Move once before
        // trusting hit testing, then keep the retries bounded.
        scrollView.swipeUp()
        for _ in 0..<3 where !element.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected the control to become visible after scrolling.")
    }

    @MainActor
    private func closeFrontmostWindow() {
        let closeButton = app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func configuredApplication(
        sessionID: UUID,
        windowWidth: Int? = 1380,
        usesFixedSessionID: Bool = true,
        autosaveDelayMS: Int = 5_000,
        ignoresSystemWindowRestoration: Bool = true,
        appearance: QAAppearance? = nil
    ) -> XCUIApplication {
        let application = XCUIApplication(bundleIdentifier: "com.kbmanager.qa")
        // Keep macOS scene restoration from reopening windows left by an
        // earlier isolated run. Scholium's own WindowSession snapshot tests
        // still verify application-level restoration explicitly below.
        application.launchArguments += [
            "-ApplePersistenceIgnoreState", ignoresSystemWindowRestoration ? "YES" : "NO",
        ]
        if !ignoresSystemWindowRestoration {
            application.launchArguments += ["-NSQuitAlwaysKeepsWindows", "YES"]
        }
        application.launchArguments += [
            "-scholium.settings.selectedPane", "research-guidance",
            "-scholium.settings.researchGuidanceCollection", "skills",
        ]
        if let appearance {
            application.launchArguments += ["-colorScheme", appearance.rawValue]
        }
        application.launchEnvironment["SCHOLIUM_HOME"] = homeDirectory.path
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = triptychDirectory.path
        // Keep navigation assertions independent of the user's persisted note
        // sort preference. The journey deliberately starts from A, then
        // crosses to the peer Topics vault and back again.
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "QA Autosave A.md"
        if usesFixedSessionID {
            application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = sessionID.uuidString
        }
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = String(autosaveDelayMS)
        if let windowWidth {
            application.launchEnvironment["SCHOLIUM_UI_TEST_WINDOW_WIDTH"] = String(windowWidth)
        }
        return application
    }

    @MainActor
    private func relaunchApplication(windowWidth: Int) {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, windowWidth: windowWidth)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    private func openAndCloseAdaptiveInspector() {
        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.isEnabled)
        inspectorButton.click()

        let panel = app.descendants(matching: .any)["scholium.adaptiveContextPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.buttons["Done"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
    }

    @MainActor
    private func openResearchFunctionAndVerifyPanel(
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
        window: XCUIElement
    ) {
        let dialogue = app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ]
        XCTAssertTrue(dialogue.waitForExistence(timeout: 5))
        dialogue.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(sheet.frame.width, minimumWidth)
        XCTAssertLessThanOrEqual(sheet.frame.width, maximumWidth)
        XCTAssertLessThan(sheet.frame.width, window.frame.width)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunctionTarget"
        ].exists)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunctionMaterials"
        ].exists)
        XCTAssertFalse(app.staticTexts["Supported modes"].exists)
        XCTAssertFalse(app.staticTexts["Required packages"].exists)
    }

    @MainActor
    private func waitForDocumentSurface() {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let nativeDocument = app.descendants(matching: .any)["Markdown reader"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists || nativeDocument.exists })
    }

    @MainActor
    private func checkboxIsSelected(_ checkbox: XCUIElement) -> Bool {
        if let value = checkbox.value as? NSNumber {
            return value.boolValue
        }
        guard let value = checkbox.value as? String else { return false }
        return ["1", "true", "selected", "checked"].contains(value.lowercased())
    }

    @MainActor
    private func enterLivePreviewAndAppend(_ token: String, in root: XCUIElement? = nil) throws {
        let mode = root?.descendants(matching: .any)["scholium.documentModeMenu"]
            ?? app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.click()
        let livePreview = app.menuItems
            .matching(identifier: "text.page.badge.magnifyingglass")
            .firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 3))
        livePreview.click()

        let editor = root?.descendants(matching: .any)["Markdown live preview editor"]
            ?? app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        editor.click()
        editor.typeKey(.end, modifierFlags: [.command])
        editor.typeText(token)
    }

    @MainActor
    private func chooseSetupFolder(_ folder: URL, role: String) {
        let openPanelButton = app.buttons["Choose \(role) folder"]
        XCTAssertTrue(openPanelButton.waitForExistence(timeout: 5))
        openPanelButton.click()

        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path)
        app.typeKey(.enter, modifierFlags: [])

        let choose = app.dialogs["open-panel"].buttons["OKButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertTrue(choose.isEnabled)
        choose.click()

        XCTAssertTrue(
            waitUntil(timeout: 5) { !choose.exists },
            "Expected the standard Open panel to close after choosing the \(role) folder."
        )
    }

    @MainActor
    private func authorizePortableFolder(_ folder: URL) {
        let authorizeButton = app.buttons["Authorize folder containing Works"]
        XCTAssertTrue(authorizeButton.waitForExistence(timeout: 5))
        authorizeButton.click()

        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(folder.path)
        app.typeKey(.enter, modifierFlags: [])

        let authorize = app.dialogs["open-panel"].buttons["OKButton"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        XCTAssertTrue(authorize.isEnabled)
        authorize.click()

        XCTAssertTrue(waitUntil(timeout: 5) { !authorize.exists })
    }

    private func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func pasteboardText() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }

    private func createIsolatedTriptych() throws {
        // The Xcode 26.6 runner can deny a sandboxed test bundle direct writes
        // to the literal /tmp root. Its process-specific temporary directory
        // remains test-owned and is also reachable by the unsandboxed QA app.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-XCUITests", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        testDirectory = root
        homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        triptychDirectory = root.appendingPathComponent("Triptych", isDirectory: true)

        // `run-ui-tests.sh` first makes one disposable copy of the researcher-
        // approved TestVaults root. Every journey clones that test-owned copy
        // into its process-specific container, then adds deterministic QA notes.
        // No UI test opens or mutates Desktop/TestVaults itself.
        let stagedFixtures = URL(
            fileURLWithPath: "/tmp/scholium-workbench-qa",
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: stagedFixtures.path) else {
            throw XCTSkip("The disposable TestVaults copy was not staged by build-qa-app.sh.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: stagedFixtures, to: triptychDirectory)

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        let critiques = works.appendingPathComponent("Critiques", isDirectory: true)
        for directory in [homeDirectory!, analyses, topics, works, critiques] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try write(
            """
            ---
            title: QA Autosave A
            authors:
              - Ada Tester
            year: 2026
            zotero_item_key: QA123
            ---
            # QA Autosave A

            Initial analysis body.
            """ + "\n",
            to: analyses.appendingPathComponent("QA Autosave A.md")
        )
        try write(
            """
            ---
            title: QA Autosave B
            authors:
              - Blaise Tester
            year: 2025
            ---
            # QA Autosave B

            Second analysis body.
            """ + "\n",
            to: analyses.appendingPathComponent("QA Autosave B.md")
        )
        try write(
            "---\ntitle: QA Topic\naliases: [Normative QA Nexus]\n---\n# QA Topic\n\n+[[QA Autosave A]]\n",
            to: topics.appendingPathComponent("QA Topic.md")
        )
        try write("# QA Work\n\n[[QA Topic]]\n", to: works.appendingPathComponent("QA Work.md"))
        try write(
            """
            ---
            critique_authorship: agent
            critique_target_path: QA Work.md
            critique_requested_at: "2026-07-14T00:00:00Z"
            critique_request_scope: "Both"
            ---
            # Critique: QA Work

            ## Specific Findings

            ### Traced — Topic connection
            - Target Work: QA Work.md
            - Target line: 3
            - Target quotation: "[[QA Topic]]"

            ## Materials Consulted and Limitations

            Synthetic QA fixture only.
            """ + "\n",
            to: critiques.appendingPathComponent("QA Critique.md")
        )
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }
}

/// External driver for the frozen RDF-1 performance protocol. This class does
/// not create fixtures, package Scholium, or decide whether a run is a release
/// gate. `run-performance-benchmarks.sh` owns those fail-closed checks and
/// invokes this single method against an explicitly registered app bundle.
final class ScholiumPerformanceUITests: XCTestCase {
    private enum Metric: String {
        case warmLibraryLaunch = "warm_library_launch"
        case indexedSearch = "indexed_search"
        case warmReadActivation = "warm_read_activation"
        case coldReadActivation = "cold_read_activation"

        var usesBatchedWarmProcess: Bool {
            self == .indexedSearch || self == .warmReadActivation
        }
    }

    @MainActor
    func testRDF1PerformanceSamples() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH"] != nil else {
            throw XCTSkip("The external RDF-1 performance driver is not configured.")
        }
        let applicationPath = try required("SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH", in: environment)
        let metric = try XCTUnwrap(
            Metric(rawValue: try required("SCHOLIUM_PERFORMANCE_DRIVER_METRIC", in: environment))
        )
        let fixtureRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT", in: environment)
        let homeRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT", in: environment)
        let resultsPath = try required("SCHOLIUM_PERFORMANCE_DRIVER_RESULTS_PATH", in: environment)
        let runID = try required("SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID", in: environment)
        let warmups = try positiveOrZero("SCHOLIUM_PERFORMANCE_DRIVER_WARMUPS", in: environment)
        let samples = try positive("SCHOLIUM_PERFORMANCE_DRIVER_SAMPLES", in: environment)
        let relaunchCooldownMilliseconds = try optionalPositiveOrZero(
            "SCHOLIUM_PERFORMANCE_DRIVER_RELAUNCH_COOLDOWN_MS",
            in: environment
        )
        let total = warmups + samples

        if metric.usesBatchedWarmProcess {
            let application = configuredApplication(
                applicationPath: applicationPath,
                metric: metric,
                fixtureRoot: fixtureRoot,
                homeRoot: homeRoot,
                resultsPath: resultsPath,
                runID: runID,
                sample: 0,
                sampleCount: total
            )
            defer { application.terminate() }
            application.launch()
            XCTAssertTrue(
                application.windows.firstMatch.waitForExistence(timeout: 30),
                "The batched warm performance app window did not appear."
            )
            try prepareBatchedWarmMetric(metric, in: application)
            for sample in 0..<total {
                try performBatchedWarmAction(
                    for: metric,
                    in: application,
                    environment: environment,
                    resultsPath: resultsPath,
                    sample: sample,
                    total: total
                )
            }
            return
        }

        for sample in 0..<total {
            let application = configuredApplication(
                applicationPath: applicationPath,
                metric: metric,
                fixtureRoot: fixtureRoot,
                homeRoot: homeRoot,
                resultsPath: resultsPath,
                runID: runID,
                sample: sample,
                sampleCount: 1
            )

            application.launchEnvironment["SCHOLIUM_PERFORMANCE_STARTED_NS"] = String(
                DispatchTime.now().uptimeNanoseconds
            )
            application.launch()
            XCTAssertTrue(
                application.windows.firstMatch.waitForExistence(timeout: 30),
                "Sample \(sample): the performance app window did not appear."
            )
            XCTAssertTrue(
                waitUntil(timeout: 60) { self.lineCount(at: resultsPath) == sample + 1 },
                "Sample \(sample): the app did not publish exactly one performance record."
            )
            application.terminate()
            if sample + 1 < total, relaunchCooldownMilliseconds > 0 {
                Thread.sleep(forTimeInterval: Double(relaunchCooldownMilliseconds) / 1_000)
            }
        }
    }

    @MainActor
    private func configuredApplication(
        applicationPath: String,
        metric: Metric,
        fixtureRoot: String,
        homeRoot: String,
        resultsPath: String,
        runID: String,
        sample: Int,
        sampleCount: Int
    ) -> XCUIApplication {
        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = "performance-\(runID)-\(sample)"
        application.launchEnvironment["SCHOLIUM_UI_TEST_WINDOW_WIDTH"] = "1380"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = resultsPath
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] = metric.rawValue
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = String(sample)
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = String(sampleCount)

        switch metric {
        case .warmLibraryLaunch:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "paper_analysis"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_COUNT"] = "267"
        case .indexedSearch:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "paper_analysis"
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Cluster-00/analysis-note-001.md"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_QUERY"] = "RDF1WarmAnalysis"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_COUNT"] = "1"
        case .warmReadActivation:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "paper_analysis"
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Cluster-01/analysis-note-002.md"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "Cluster-00/analysis-note-001.md"
        case .coldReadActivation:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Long/Canonical-5000-Word-Work.md"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "Long/Canonical-5000-Word-Work.md"
        }
        return application
    }

    @MainActor
    private func prepareBatchedWarmMetric(
        _ metric: Metric,
        in application: XCUIApplication
    ) throws {
        let setupDocument: String
        switch metric {
        case .indexedSearch:
            setupDocument = "Cluster-00/analysis-note-001.md"
        case .warmReadActivation:
            setupDocument = "Cluster-01/analysis-note-002.md"
        case .warmLibraryLaunch, .coldReadActivation:
            return
        }
        XCTAssertTrue(
            waitForRenderedDocument(setupDocument, in: application, timeout: 30),
            "The warm metric setup document did not finish rendering."
        )
        application.typeKey("f", modifierFlags: [.command])
        let field = application.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        replaceCommittedText("scope setup", in: field, application: application)
        let thisVault = application.radioButtons["This Vault"]
        XCTAssertTrue(thisVault.waitForExistence(timeout: 5))
        thisVault.click()
        clearSearchField(field, application: application)
        if metric == .warmReadActivation {
            let close = application.buttons["scholium.closeSearchButton"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.click()
            XCTAssertTrue(waitUntil(timeout: 5) { !field.exists })
        }
    }

    @MainActor
    private func performBatchedWarmAction(
        for metric: Metric,
        in application: XCUIApplication,
        environment: [String: String],
        resultsPath: String,
        sample: Int,
        total: Int
    ) throws {
        switch metric {
        case .warmLibraryLaunch, .coldReadActivation:
            return
        case .indexedSearch:
            let field = application.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            replaceCommittedText(
                environment["SCHOLIUM_PERFORMANCE_DRIVER_QUERY"] ?? "RDF1WarmAnalysis",
                in: field,
                application: application
            )
            XCTAssertTrue(
                waitUntil(timeout: 30) { self.lineCount(at: resultsPath) == sample + 1 },
                "Sample \(sample): Search did not publish exactly one performance record."
            )
            clearSearchField(field, application: application)
            if sample + 1 == total {
                let close = application.buttons["scholium.closeSearchButton"]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                close.click()
            }
        case .warmReadActivation:
            application.typeKey("f", modifierFlags: [.command])
            let field = application.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            replaceCommittedText("RDF1WarmAnalysis", in: field, application: application)
            let thisVault = application.radioButtons["This Vault"]
            XCTAssertTrue(thisVault.waitForExistence(timeout: 5))
            thisVault.click()
            let target = application.descendants(matching: .any)[
                "scholium.searchResult.Cluster-00/analysis-note-001.md"
            ]
            XCTAssertTrue(target.waitForExistence(timeout: 15))
            XCTAssertTrue(target.isHittable, "Sample \(sample): the warm Read Search result is not hittable.")
            target.click()
            XCTAssertTrue(
                waitForRenderedDocument(
                    "Cluster-00/analysis-note-001.md",
                    in: application,
                    timeout: 30
                ),
                "Sample \(sample): the selected warm Read document did not finish rendering."
            )
            XCTAssertTrue(
                waitUntil(timeout: 30) { self.lineCount(at: resultsPath) == sample + 1 },
                "Sample \(sample): Read did not publish exactly one performance record."
            )
            if sample + 1 < total {
                application.typeKey("[", modifierFlags: [.command])
                XCTAssertTrue(
                    waitForRenderedDocument(
                        "Cluster-01/analysis-note-002.md",
                        in: application,
                        timeout: 30
                    ),
                    "Sample \(sample): navigation did not restore the alternate warm document."
                )
            }
        }
    }

    @MainActor
    private func waitForRenderedDocument(
        _ documentID: String,
        in application: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        application.descendants(matching: .any)[
            "scholium.renderedDocument.\(documentID)"
        ].waitForExistence(timeout: timeout)
    }

    private func replaceCommittedText(
        _ text: String,
        in field: XCUIElement,
        application: XCUIApplication
    ) {
        clearSearchField(field, application: application)
        typeCommittedText(text, into: field, in: application)
    }

    private func clearSearchField(_ field: XCUIElement, application: XCUIApplication) {
        field.click()
        field.typeKey("a", modifierFlags: [.command])
        field.typeKey(.delete, modifierFlags: [])
        application.typeKey(.tab, modifierFlags: [])
    }

    private func required(_ key: String, in environment: [String: String]) throws -> String {
        let value = try XCTUnwrap(environment[key], "Missing \(key).")
        return try XCTUnwrap(value.isEmpty ? nil : value, "Empty \(key).")
    }

    private func positive(_ key: String, in environment: [String: String]) throws -> Int {
        let value = try XCTUnwrap(Int(try required(key, in: environment)))
        return try XCTUnwrap(value > 0 ? value : nil, "\(key) must be positive.")
    }

    private func positiveOrZero(_ key: String, in environment: [String: String]) throws -> Int {
        let value = try XCTUnwrap(Int(try required(key, in: environment)))
        return try XCTUnwrap(value >= 0 ? value : nil, "\(key) must not be negative.")
    }

    private func optionalPositiveOrZero(_ key: String, in environment: [String: String]) throws -> Int {
        guard let rawValue = environment[key], !rawValue.isEmpty else { return 0 }
        let value = try XCTUnwrap(Int(rawValue), "\(key) must be an integer.")
        return try XCTUnwrap(value >= 0 ? value : nil, "\(key) must not be negative.")
    }

    private func lineCount(at path: String) -> Int {
        guard let data = FileManager.default.contents(atPath: path) else { return 0 }
        return data.reduce(into: 0) { count, byte in
            if byte == 0x0A { count += 1 }
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
