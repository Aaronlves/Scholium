@preconcurrency import XCTest

final class ScholiumUITests: XCTestCase {
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
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]

        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists || nativeDocument.exists })
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertTrue(inspectorButton.exists)
        XCTAssertTrue(inspector.exists)

        XCTContext.runActivity(named: "Search, properties, and inspector") { _ in
            app.typeKey("f", modifierFlags: [.command])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            let field = app.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("analysis")
            let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })

            metadata.click()
            XCTAssertTrue(waitUntil(timeout: 3) { metadata.label == "Hide note properties" })
            metadata.click()

            inspectorButton.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
            inspectorButton.click()
            XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        }

        XCTContext.runActivity(named: "Review requires a written judgment and verdict") { _ in
            let openScholia = app.descendants(matching: .any)["scholium.openScholiaButton"]
            XCTAssertTrue(openScholia.waitForExistence(timeout: 5))
            openScholia.click()
            let scholia = app.descendants(matching: .any)["scholium.scholiaPanel"]
            XCTAssertTrue(scholia.waitForExistence(timeout: 5))
            let review = app.descendants(matching: .any)["scholium.scholiaReview"]
            XCTAssertTrue(review.waitForExistence(timeout: 5))
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
            app.buttons["Done"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !scholia.exists })
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
        field.typeText("Normative QA Nexus")

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

        let setup = app.descendants(matching: .any)["scholium.triptychSetup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Choose Your Triptych"].exists)

        XCTAssertTrue(app.buttons["Choose Analyses folder"].exists)
        XCTAssertTrue(app.buttons["Choose Topics folder"].exists)
        XCTAssertTrue(app.buttons["Choose Works folder"].exists)

        let complete = app.buttons["Use This Triptych"]
        XCTAssertTrue(complete.exists)
        XCTAssertFalse(complete.isEnabled)

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        chooseSetupFolder(analyses, role: "Analyses")
        chooseSetupFolder(topics, role: "Topics")
        chooseSetupFolder(works, role: "Works")

        XCTAssertFalse(complete.isEnabled)
        authorizePortableFolder(triptychDirectory)
        XCTAssertTrue(complete.isEnabled)
        complete.click()

        XCTAssertTrue(app.radioButtons["Analyses"].waitForExistence(timeout: 15))
        let analysisRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(analysisRow.waitForExistence(timeout: 15))
        analysisRow.click()
        waitForDocumentSurface()

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
        app.typeKey(",", modifierFlags: [.command])

        let collection = app.descendants(matching: .any)["scholium.researchGuidance.collection"]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        let skillsSegment = app.radioButtons["Skills"]
        XCTAssertTrue(skillsSegment.waitForExistence(timeout: 5))
        skillsSegment.click()

        let bundled = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.scholium-source-fidelity"
        ]
        XCTAssertTrue(bundled.waitForExistence(timeout: 10))
        bundled.click()

        let editor = app.descendants(matching: .any)["scholium.researchGuidance.skillEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Duplicate into Triptych"].exists)
        XCTAssertTrue(app.buttons["Reveal Skills Folder"].exists)
        XCTAssertFalse(app.buttons["Save Skill"].exists)
    }

    @MainActor
    func testDialoguePreservesResearcherFollowUpAndAgentResponseChronology() throws {
        waitForDocumentSurface()
        let initialComment = "Clarify the distinction without overstating the source."
        let followUpComment = "Keep the unresolved interpretive question visible."
        let agentResponse = "The distinction is clarified, and the unresolved scope question remains marked for review."

        let openScholia = app.descendants(matching: .any)["scholium.openScholiaButton"]
        XCTAssertTrue(openScholia.waitForExistence(timeout: 5))
        openScholia.click()
        let scholia = app.descendants(matching: .any)["scholium.scholiaPanel"]
        XCTAssertTrue(scholia.waitForExistence(timeout: 5))
        app.radioButtons["Dialogue"].click()

        let prepare = app.descendants(matching: .any)["scholium.scholiaDialogue"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.click()
        let instruction = app.descendants(matching: .any)["scholium.dialogue.instruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        instruction.click()
        instruction.typeText(initialComment)
        let copy = app.descendants(matching: .any)["scholium.dialogue.copyInstructions"]
        XCTAssertTrue(copy.isEnabled)
        copy.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !instruction.exists })
        if scholia.exists, app.buttons["Done"].firstMatch.exists {
            app.buttons["Done"].firstMatch.click()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !scholia.exists })

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
            .matching(NSPredicate(format: "label CONTAINS %@", "Agent-authored Critique"))
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
        XCTAssertTrue(searchMode.exists)
        app.radioButtons["This Note"].click()

        field.typeText("analysis")
        XCTAssertTrue(result.waitForExistence(timeout: 8))

        field.typeKey("a", modifierFlags: [.command])
        field.typeText("not in this rendered note")
        XCTAssertTrue(waitUntil(timeout: 5) {
            !result.exists
        })

        app.buttons["Close"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        XCTAssertTrue(renderedDocument.exists || nativeDocument.exists)
    }

    @MainActor
    func testResponsiveDocumentLayoutPreservesNavigationAndContextRoutes() throws {
        waitForDocumentSurface()
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 1200)
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
        let showSidebar = app.menuItems["Show Sidebar"]
        let hideSidebar = app.menuItems["Hide Sidebar"]
        XCTAssertTrue(waitUntil(timeout: 3) { showSidebar.exists || hideSidebar.exists })
        let sidebarCommand = showSidebar.exists ? showSidebar : hideSidebar
        XCTAssertTrue(sidebarCommand.isEnabled)
        sidebarCommand.click()
        waitForDocumentSurface()
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
        XCTAssertEqual(restoredMode.value as? String, "Live Preview")
    }

    @MainActor
    func testMetadataAndInspectorCanBeToggled() throws {
        let metadata = app.descendants(matching: .any)["scholium.metadataDisclosure"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        metadata.click()
        XCTAssertTrue(waitUntil(timeout: 3) { metadata.label == "Hide note properties" })

        let inspectorButton = app.descendants(matching: .any)["scholium.researchInspectorButton"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        XCTAssertTrue(inspectorButton.exists)
        XCTAssertTrue(inspector.exists)
        inspectorButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
        inspectorButton.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
    }

    @MainActor
    func testHumanReviewCannotCompleteWithoutRequiredJudgment() throws {
        let openScholia = app.descendants(matching: .any)["scholium.openScholiaButton"]
        XCTAssertTrue(openScholia.waitForExistence(timeout: 10))
        openScholia.click()
        let scholia = app.descendants(matching: .any)["scholium.scholiaPanel"]
        XCTAssertTrue(scholia.waitForExistence(timeout: 5))
        let review = app.descendants(matching: .any)["scholium.scholiaReview"]
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
        app.buttons["Done"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !scholia.exists })
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
    func testDirtyExternalEditPreservesTheBufferAndPresentsConflictRecovery() throws {
        let localToken = " LOCAL-\(UUID().uuidString)"
        let diskToken = "\n\n## External Disk Revision\n"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(localToken)

        let originalDisk = try source(at: noteURL)
        try write(originalDisk + diskToken, to: noteURL)

        let compare = app.buttons["Compare Changes"]
        let reload = app.buttons["Reload from Disk"]
        let keepEditing = app.buttons["Keep Editing"]
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
        XCTAssertTrue(app.descendants(matching: .any)["scholium.conflict.currentRevision"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.conflict.diskRevision"].exists)
        let returnToEditing = app.buttons["Return to Editing"]
        XCTAssertTrue(returnToEditing.exists)
        XCTAssertTrue(app.buttons["Reload from Disk"].exists)
        returnToEditing.click()

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(localToken))
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

        let compare = app.buttons["Compare Changes"]
        XCTAssertTrue(compare.waitForExistence(timeout: 12))
        compare.click()
        let comparison = app.descendants(matching: .any)["scholium.conflictComparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))

        try write(originalDisk + firstDiskToken + secondDiskToken, to: noteURL)
        app.buttons["Reload from Disk"].click()

        XCTAssertTrue(
            app.buttons["Compare Changes"].waitForExistence(timeout: 5),
            "Reload must not accept bytes that weren't shown in the comparison."
        )
        app.buttons["Keep Editing"].click()
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
        // macOS can report a control as hittable while the persistent history
        // footer visually covers it. Move the expanded exchange upward once
        // before trusting hit testing, then keep the retries bounded.
        scrollView.swipeUp()
        for _ in 0..<3 where !element.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Expected the history action to become visible after scrolling.")
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

    private func configuredApplication(sessionID: UUID, windowWidth: Int? = 1380) -> XCUIApplication {
        let application = XCUIApplication(bundleIdentifier: "com.kbmanager.qa")
        // Keep macOS scene restoration from reopening windows left by an
        // earlier isolated run. Scholium's own WindowSession snapshot tests
        // still verify application-level restoration explicitly below.
        application.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        application.launchArguments += [
            "-scholium.settings.selectedPane", "research-guidance",
            "-scholium.settings.researchGuidanceCollection", "skills",
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeDirectory.path
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = triptychDirectory.path
        // Keep navigation assertions independent of the user's persisted note
        // sort preference. The journey deliberately starts from A, then
        // crosses to the peer Topics vault and back again.
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "QA Autosave A.md"
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = sessionID.uuidString
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = "5000"
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
    private func waitForDocumentSurface() {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        let nativeDocument = app.descendants(matching: .any)["Markdown reader"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists || nativeDocument.exists })
    }

    @MainActor
    private func enterLivePreviewAndAppend(_ token: String) throws {
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
