@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

/// Commits marked text without changing the user's active input source.
/// `typeText` alone can leave Latin test queries inside a CJK IME
/// composition, so SwiftUI has not yet received the bound value. Return
/// commits that composition; Tab can be consumed by the IME instead.
@MainActor
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
    /// Mirrors `ScholiumMetrics.Workspace` in the app target. The standalone
    /// UI-test bundle cannot import that executable module, so keep this named
    /// acceptance contract synchronized with the source design tokens.
    private enum QAWorkspaceMetricContract {
        static let preferredWidth: CGFloat = 1_180
        static let frameTolerance: CGFloat = 18
    }

    /// Mirrors the separate first-run Bootstrap scene. Bootstrap is not a
    /// compact workspace shell: it never owns the three-region split or its
    /// toolbar, and it is replaced by the configured workspace on success.
    private enum QABootstrapMetricContract {
        static let preferredWidth: CGFloat = 720
    }

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

    /// `defaultSize` is a first-presentation input. Tests that need a specific
    /// starting width must request it before their first scene appears; a
    /// relaunch is intentionally not a frame-reset API.
    private var initialWorkspaceWidthForCurrentTest: Int {
        if name.contains("testResearchFunctionPanelFitsCompactEditor")
            || name.contains("testTwoHundredPercentDocumentTextPersistsAcrossEveryMode") {
            return 900
        }
        if name.contains("testWorkspaceInitialDefaultPreservesNativeReachability")
            || name.contains("testNativeToolbarVisualProofAtDefaultWindowSize")
            || name.contains("testNoDocumentKeepsTrailingToolbarControlsVisibleAndDisabled")
            || name.contains("testSystemInspectorToolbarItemOpensAndClosesInspector") {
            return Int(QAWorkspaceMetricContract.preferredWidth)
        }
        return 1_380
    }

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        sessionID = UUID()
        try createIsolatedTriptych()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: initialWorkspaceWidthForCurrentTest
        )
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "The isolated QA window did not appear"
        )
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(
            waitUntil(timeout: 30) { renderedDocument.exists },
            "The isolated QA window appeared without reaching a usable document surface."
        )
    }

    @MainActor
    override func tearDown() async throws {
        if testRun?.failureCount ?? 0 > 0, let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Scholium UI failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Scholium accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app?.terminate()
        if ProcessInfo.processInfo.environment["SCHOLIUM_QA_KEEP_ARTIFACTS"] != "1",
           let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
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
        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        let documentTitle = app.staticTexts["scholium.documentNoteName"].firstMatch
        let inspectorButton = app.descendants(matching: .any)["scholium.toggleInspector"]
        let inspector = app.scrollViews["scholium.researchInspector"]
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]

        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })
        XCTAssertFalse(documentTabs.exists)
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 10))
        XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
        XCTAssertTrue(inspectorButton.exists)
        if inspector.exists {
            inspectorButton.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
        }

        XCTContext.runActivity(named: "Search, properties, and inspector") { _ in
            app.typeKey("f", modifierFlags: [.command])
            let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
            let field = app.descendants(matching: .any)["scholium.searchField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            typeCommittedText("Autosave", into: field, in: app)
            let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
            XCTAssertTrue(result.waitForExistence(timeout: 8))
            app.buttons["Close"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })

            app.menuBars.menuBarItems["Edit"].click()
            let editProperties = app.menuItems["Edit Properties…"].firstMatch
            XCTAssertTrue(editProperties.waitForExistence(timeout: 3))
            editProperties.click()
            let properties = app.descendants(matching: .any)["scholium.propertiesEditor"]
            XCTAssertTrue(properties.waitForExistence(timeout: 5))
            app.buttons["Cancel"].click()
            XCTAssertTrue(waitUntil(timeout: 3) { !properties.exists })

            inspectorButton.click()
            XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            inspectorButton.click()
            XCTAssertTrue(waitUntil(timeout: 3) { !inspector.exists })
        }

        XCTContext.runActivity(named: "Review requires a written judgment and verdict") { _ in
            app.typeKey("r", modifierFlags: [.command])

            let complete = app.buttons["Complete Review"]
            let noteField = app.textViews["Review Note"]
            XCTAssertTrue(complete.waitForExistence(timeout: 5))
            XCTAssertFalse(complete.isEnabled)
            noteField.click()
            noteField.typeText("A bounded acceptance-test judgment.")
            XCTAssertFalse(complete.isEnabled)
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !complete.exists })
        }

        XCTContext.runActivity(named: "Peer vaults keep explicit Library selection") { _ in
            let analyses = app.buttons["scholium.vault.paper_analysis"].firstMatch
            let topics = app.buttons["scholium.vault.topic_knowledge"].firstMatch
            XCTAssertTrue(analyses.exists)
            XCTAssertTrue(topics.exists)

            topics.click()
            let topicRow = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
            XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
            topicRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Topic"
            })

            analyses.click()
            let analysisRow = app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ]
            XCTAssertTrue(analysisRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Topic")
            analysisRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Autosave A"
            })

            topics.click()
            XCTAssertTrue(topicRow.waitForExistence(timeout: 8))
            XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
            topicRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Topic"
            })
        }

        XCTContext.runActivity(named: "Zotero reports a precise unavailable state") { _ in
            let analyses = app.buttons["scholium.vault.paper_analysis"].firstMatch
            analyses.click()
            let analysisRow = app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ]
            XCTAssertTrue(analysisRow.waitForExistence(timeout: 8))
            analysisRow.click()
            XCTAssertTrue(waitUntil(timeout: 8) {
                (documentTitle.value as? String) == "QA Autosave A"
            })

            if !inspector.exists {
                inspectorButton.click()
                XCTAssertTrue(inspector.waitForExistence(timeout: 3))
            }
            selectResearchInspectorMode("overview")
            let zoteroSource = app.descendants(matching: .any)["scholium.zoteroSourceSection"]
            XCTAssertTrue(zoteroSource.waitForExistence(timeout: 5))

            let openInZotero = app.buttons["Open in Zotero"].firstMatch
            let unavailableSource = app.images["Zotero source unavailable"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 8) {
                openInZotero.exists || unavailableSource.exists
            })
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
    func testSharedSearchMatchesAnAliasAcrossTheTriptych() throws {
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))

        app.typeKey("f", modifierFlags: [.command, .shift])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        let field = app.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        typeCommittedText("Normative QA Nexus", into: field, in: app)

        let result = app.descendants(matching: .any)["scholium.searchResult.QA Topic.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.click()

        XCTAssertTrue(waitUntil(timeout: 8) {
            (metadata.value as? String) == "QA Topic"
        })
        XCTAssertTrue(app.buttons["scholium.vault.topic_knowledge"].exists)
        XCTAssertFalse(search.exists)
    }

    @MainActor
    func testNewAnalysisCanDeclareAndPersistsResearchStatus() throws {
        let newNote = app.descendants(matching: .any)["scholium.newNote"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 10))
        newNote.click()

        let declareNow = app.buttons["Declare Now"].firstMatch
        let declareNowRadio = app.radioButtons["Declare Now"].firstMatch
        XCTAssertTrue(declareNow.waitForExistence(timeout: 3) || declareNowRadio.exists)
        (declareNow.exists ? declareNow : declareNowRadio).click()

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
    func testNewAnalysisNotYetPreservesYAMLFreeSourceAndGatesReview() throws {
        let newNote = app.descendants(matching: .any)["scholium.newNote"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 10))
        newNote.click()

        let notYet = app.radioButtons["Not Yet"]
        XCTAssertTrue(notYet.waitForExistence(timeout: 3))
        XCTAssertEqual((notYet.value as? NSNumber)?.boolValue, true)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.newNote.researchUnitScope"
        ].exists)
        let create = app.buttons["Create"].firstMatch
        XCTAssertTrue(create.isEnabled)
        create.click()

        let createdURL = triptychDirectory.appendingPathComponent(
            "01-analyses/Untitled.md"
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: createdURL.path)
        })
        let createdSource = try source(at: createdURL)
        XCTAssertEqual(createdSource, "")
        XCTAssertFalse(createdSource.contains("research_unit"))

        let review = app.descendants(matching: .any)[
            "scholium.researchFunction.review"
        ]
        XCTAssertTrue(waitUntil(timeout: 8) {
            review.exists && review.isEnabled && review.isHittable
        })
        review.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.reviewResearchStatusGate"
        ].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Complete Review"].isEnabled)
        XCTAssertTrue(app.buttons["Declare Research Status…"].exists)
    }

    @MainActor
    func testRetiredNavigationMenuIsAbsent() {
        XCTAssertFalse(app.menuBars.menuBarItems["Navigate"].exists)
        XCTAssertFalse(app.menuItems["Back"].exists)
        XCTAssertFalse(app.menuItems["Forward"].exists)
        XCTAssertFalse(app.menuItems["Recent Notes"].exists)
    }

    @MainActor
    func testCleanAccountConfiguresAndRestoresACompleteTriptych() throws {
        app.terminate()

        let cleanHome = testDirectory.appendingPathComponent("clean-home", isDirectory: true)
        try FileManager.default.createDirectory(at: cleanHome, withIntermediateDirectories: true)

        app = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["SCHOLIUM_HOME"] = cleanHome.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"] = triptychDirectory.path
        app.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = String(
            Int(QAWorkspaceMetricContract.preferredWidth)
        )
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
        let setupFrame = app.windows.firstMatch.frame
        XCTAssertEqual(
            setupFrame.width,
            QABootstrapMetricContract.preferredWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance,
            "Bootstrap's 720pt contract is an initial size, not a minimum."
        )
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertFalse(app.splitGroups["scholium.workspaceSplitView"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.toggleSidebar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.toggleInspector"].exists)

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

        let analysesControl = app.buttons["Analyses"]
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        let loadingOverlay = app.descendants(matching: .any)["scholium.loadingOverlay"]
        XCTAssertTrue(waitUntil(timeout: 45) {
            analysesControl.exists && librarySurface.exists && !loadingOverlay.exists
        }, "Completing first-run setup must finish opening the Triptych and dismiss loading.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.app.windows.count == 1
                && !self.app.descendants(matching: .any)["scholium.triptychSetup"].exists
                && self.app.splitGroups["scholium.workspaceSplitView"].exists
        }, "Successful setup must replace Bootstrap with one configured workspace window.")
        let workspaceWindow = app.windows.firstMatch
        if let visibleScreenWidth = NSScreen.main?.visibleFrame.width,
           visibleScreenWidth >= QAWorkspaceMetricContract.preferredWidth {
            XCTAssertTrue(waitUntil(timeout: 5) {
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
        let analysisRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(analysisRow.waitForExistence(timeout: 15))
        analysisRow.click()
        waitForDocumentSurface()
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
        app.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = UUID().uuidString
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Analyses"].waitForExistence(timeout: 15))
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
        let vaultsPane = app.descendants(matching: .any)["Vaults"].firstMatch
        XCTAssertTrue(vaultsPane.waitForExistence(timeout: 10))
        vaultsPane.click()
        let nameField = app.descendants(matching: .any)["scholium.triptychName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        try paste("QA Renamed Triptych", into: nameField)
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
        let promptTemplatesSegment = app.radioButtons["Prompt Templates"]
        let skillsSegment = app.radioButtons["Skills"]
        let advancedSegment = app.radioButtons["Advanced"]
        XCTAssertTrue(promptTemplatesSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(skillsSegment.waitForExistence(timeout: 5))
        XCTAssertTrue(advancedSegment.waitForExistence(timeout: 5))
        XCTAssertLessThan(promptTemplatesSegment.frame.midX, skillsSegment.frame.midX)
        XCTAssertLessThan(skillsSegment.frame.midX, advancedSegment.frame.midX)
        let settingsWindow = app.windows["Research Guidance"]
        XCTAssertFalse(settingsWindow.buttons["Toggle Sidebar"].exists)
        XCTAssertFalse(settingsWindow.buttons["Show Sidebar"].exists)
        XCTAssertFalse(settingsWindow.buttons["Hide Sidebar"].exists)
        skillsSegment.click()

        let skillList = app.descendants(matching: .any)[
            "scholium.researchGuidance.skillList"
        ].firstMatch
        XCTAssertTrue(skillList.waitForExistence(timeout: 10))
        let bundled = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.bundled.scholium-development"
        ].firstMatch
        XCTAssertTrue(bundled.waitForExistence(timeout: 10))
        scrollUntilHittable(bundled, in: skillList)
        bundled.click()

        let editor = app.descendants(matching: .any)["scholium.researchGuidance.skillEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Duplicate"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.skillRouting"].exists
        )
        XCTAssertTrue(app.buttons["Reveal Skills Folder"].exists)

        advancedSegment.click()
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [expectation(
                    for: NSPredicate(format: "value == 1"),
                    evaluatedWith: advancedSegment
                )],
                timeout: 5
            ) == .completed,
            "Advanced must become the selected Research Guidance page before its controls are checked."
        )
        XCTAssertTrue(app.radioButtons["Skills"].exists)
        XCTAssertTrue(app.radioButtons["Prompt Templates"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.advancedPage"]
                .waitForExistence(timeout: 5),
            "Advanced must own an independent page."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.agentCLI.section"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.researchMethods"].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchGuidance.skillList"].exists
        )
        XCTAssertFalse(app.buttons["Reveal Skills Folder"].exists)

        skillsSegment.click()
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [expectation(
                    for: NSPredicate(format: "value == 1"),
                    evaluatedWith: skillsSegment
                )],
                timeout: 5
            ) == .completed,
            "Skills must become selected before its package editor is checked."
        )
        XCTAssertTrue(bundled.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reveal Skills Folder"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.skillTitle"]
                .waitForExistence(timeout: 5),
            "Returning to Skills must preserve its selection and stable list."
        )

        let collision = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.triptych.scholium-development"
        ].firstMatch
        XCTAssertTrue(collision.waitForExistence(timeout: 5))
        scrollUntilHittable(collision, in: skillList)
        collision.click()
        let validation = app.descendants(matching: .any)[
            "scholium.researchGuidance.skillValidation"
        ]
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        XCTAssertTrue((validation.label + " " + (validation.value as? String ?? ""))
            .contains("protected Scholium package"))

        app.buttons["Delete Triptych Skill"].click()
        let confirmDeletion = app.sheets.firstMatch.buttons["Delete Skill"]
        XCTAssertTrue(confirmDeletion.waitForExistence(timeout: 3))
        confirmDeletion.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !collision.exists })
        let duplicateBundled = app.buttons["Duplicate"]
        XCTAssertTrue(duplicateBundled.waitForExistence(timeout: 5))
        duplicateBundled.click()
        let duplicatedSkill = triptychDirectory.appendingPathComponent(
            ".scholium/skills/development-copy/SKILL.md"
        )
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                FileManager.default.fileExists(atPath: duplicatedSkill.path)
            },
            "Duplicate must create the independent Triptych-owned skill even when its lazy sidebar row is offscreen."
        )
    }

    @MainActor
    func testScholiumCLIInstallsFromSettings() throws {
        openResearchGuidanceSkills(openAdvanced: true)

        let section = app.descendants(matching: .any)["scholium.agentCLI.section"]
        let status = app.descendants(matching: .any)["scholium.agentCLI.status"]
        let install = app.descendants(matching: .any)["scholium.agentCLI.install"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Scholium CLI status")
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        XCTAssertTrue(install.isEnabled)
        install.click()

        let installedTool = testDirectory.appendingPathComponent("cli-bin/scholium")
        let installedCatalog = testDirectory.appendingPathComponent(
            "cli-bin/Scholium_ScholiumCore.bundle/Contents/Resources/Skills/catalog.yaml"
        )
        XCTAssertTrue(waitUntil(timeout: 15) {
            FileManager.default.isExecutableFile(atPath: installedTool.path)
                && FileManager.default.fileExists(atPath: installedCatalog.path)
        })
        XCTAssertTrue(waitUntil(timeout: 10) {
            (status.value as? String) == "Installed"
                || (status.value as? String) == "Installed and discoverable"
        })
        XCTAssertFalse(install.exists)
    }

    @MainActor
    func testGuidedEvolutionAppliesAndRestoresACompleteResearcherSkill() throws {
        XCTAssertTrue(app.buttons["scholium.vault.output"].waitForExistence(timeout: 15))
        waitForDocumentSurface()
        app.terminate()
        let package = triptychDirectory.appendingPathComponent(
            ".scholium/skills/guided-evolution-fixture",
            isDirectory: true
        )
        let evals = package.appendingPathComponent("evals", isDirectory: true)
        try FileManager.default.createDirectory(at: evals, withIntermediateDirectories: true)
        let originalSkill = """
        ---
        name: Guided Evolution Fixture
        description: Disposable Researcher Skill for transport and gating verification.
        scholium:
          role: specialist
          supported_functions: [fidelity]
          capabilities: []
          citation_styles: []
          allow_evolution: true
          supported_modes: [audit]
          required_skills: [scholium-core-protocol]
        ---
        Preserve the researcher's explicit boundaries in this disposable fixture.
        """ + "\n"
        let originalEvaluation = "# Synthetic fixture cases\n\nNo philosophical judgment is claimed.\n"
        try write(originalSkill, to: package.appendingPathComponent("SKILL.md"))
        try write(originalEvaluation, to: evals.appendingPathComponent("cases.md"))
        relaunchApplication(initialWorkspaceWidth: 1380)

        openResearchGuidanceSkills()
        let settingsWindow = app.windows["Research Guidance"]
        let bundled = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.bundled.scholium-development"
        ].firstMatch
        XCTAssertTrue(bundled.waitForExistence(timeout: 10))
        bundled.click()
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchGuidance.maintenance"].exists,
            "Bundled Workflow Skills must expose no evolution action."
        )

        let skill = app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.triptych.guided-evolution-fixture"
        ].firstMatch
        XCTAssertTrue(skill.waitForExistence(timeout: 10))
        let sidebar = settingsWindow.outlines["Sidebar"].firstMatch
        let skillRow = sidebar.cells.containing(
            .any,
            identifier: "scholium.researchGuidance.skill.triptych.guided-evolution-fixture"
        ).firstMatch
        scrollUntilHittable(skillRow, in: sidebar)
        skillRow.click()
        let selectedSkillTitle = app.descendants(matching: .any)[
            "scholium.researchGuidance.skillTitle"
        ]
        XCTAssertTrue(waitUntil(timeout: 10) {
            selectedSkillTitle.exists
                && (selectedSkillTitle.value as? String) == "Guided Evolution Fixture"
        })
        let maintenance = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenance"
        ]
        let skillEditor = app.descendants(matching: .any)[
            "scholium.researchGuidance.skillEditor"
        ]
        XCTAssertTrue(skillEditor.waitForExistence(timeout: 10))
        let detailScroll = skillEditor
        let openMaintenance = app.descendants(matching: .any)[
            "scholium.researchGuidance.openMaintenance"
        ]
        XCTAssertTrue(openMaintenance.waitForExistence(timeout: 5))
        openMaintenance.click()
        let instruction = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceInstruction"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { instruction.exists && instruction.isHittable })
        XCTAssertTrue(maintenance.exists)
        instruction.click()
        instruction.typeText("Refine the synthetic workflow without expanding its authority.")

        let proposedSkill = originalSkill.replacingOccurrences(
            of: "Preserve the researcher's explicit boundaries in this disposable fixture.",
            with: "Preserve explicit boundaries and report uncertainty in this disposable fixture."
        )
        let proposedEvaluation = "# Synthetic fixture cases\n\nTransport, boundary, and rollback gates only.\n"
        let files = [
            ("SKILL.md", proposedSkill),
            ("evals/cases.md", proposedEvaluation),
        ]
        let proposal = try JSONSerialization.data(withJSONObject: [
            "files": files.map { ["relativePath": $0.0, "source": $0.1] },
        ], options: [.prettyPrinted, .sortedKeys])
        let proposalEditor = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceProposalJSON"
        ]
        if !proposalEditor.isHittable {
            scrollUntilHittable(proposalEditor, in: detailScroll)
        }
        try paste(String(decoding: proposal, as: UTF8.self), into: proposalEditor)
        let importProposal = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceImportProposal"
        ]
        if !importProposal.isHittable {
            scrollUntilHittable(importProposal, in: detailScroll)
        }
        importProposal.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceDiff"
        ].waitForExistence(timeout: 8))

        let validate = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceEvaluate"
        ]
        if !validate.isHittable { scrollUntilHittable(validate, in: detailScroll) }
        validate.click()
        let evaluation = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceEvaluation"
        ]
        XCTAssertTrue(evaluation.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceApply"
        ].exists)

        let evidenceEditor = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceEvidence"
        ]
        if !evidenceEditor.isHittable {
            scrollUntilHittable(evidenceEditor, in: detailScroll)
        }
        let mismatchedEvidence = try maintenanceEvidence(
            revision: (String(repeating: "0", count: 64), 0)
        )
        try paste(mismatchedEvidence, into: evidenceEditor)
        if !validate.isHittable { scrollUntilHittable(validate, in: detailScroll) }
        validate.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            !self.app.descendants(matching: .any)[
                "scholium.researchGuidance.maintenanceApply"
            ].exists
        })

        let proposedRevision = packageRevision(files)
        if !evidenceEditor.isHittable {
            scrollUntilHittable(evidenceEditor, in: detailScroll)
        }
        try paste(try maintenanceEvidence(revision: proposedRevision), into: evidenceEditor)
        if !validate.isHittable { scrollUntilHittable(validate, in: detailScroll) }
        validate.click()
        let apply = app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceApply"
        ]
        XCTAssertTrue(apply.waitForExistence(timeout: 10))
        if !apply.isHittable { scrollUntilHittable(apply, in: detailScroll) }
        apply.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.maintenanceApplied"
        ].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? self.source(at: package.appendingPathComponent("SKILL.md"))) == proposedSkill
                && (try? self.source(at: evals.appendingPathComponent("cases.md")))
                    == proposedEvaluation
        })

        closeFrontmostWindow()
        relaunchApplication(initialWorkspaceWidth: 1380)
        openResearchGuidanceSkills()
        let recovery = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.researchGuidance.recovery."
            )
        ).firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        let relaunchedSidebar = app.windows["Research Guidance"].outlines["Sidebar"].firstMatch
        scrollUntilHittable(recovery, in: relaunchedSidebar)
        recovery.click()
        let restore = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.researchGuidance.recoveryRestore."
            )
        ).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        restore.click()
        let confirm = app.sheets.firstMatch.buttons["Restore Complete Package"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? self.source(at: package.appendingPathComponent("SKILL.md"))) == originalSkill
                && (try? self.source(at: evals.appendingPathComponent("cases.md")))
                    == originalEvaluation
        })
        XCTAssertGreaterThanOrEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "scholium.researchGuidance.recovery."
                )
            ).count,
            2,
            "Restore must leave the original snapshot and a new undo snapshot."
        )
    }

    @MainActor
    func testResearchGuidanceWaitsForTriptychActivationWithoutIncompleteAlert() throws {
        openResearchGuidanceSkills()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.bundled.scholium-development"
        ].firstMatch.waitForExistence(timeout: 12))
        XCTAssertFalse(app.alerts["Could Not Manage Skills"].exists)
        XCTAssertFalse(app.staticTexts[
            "The Triptych is incomplete. Choose Analyses, Topics, and Works again."
        ].exists)

        closeFrontmostWindow()
        relaunchApplication(initialWorkspaceWidth: 1380)
        XCTAssertTrue(app.buttons["scholium.vault.output"].waitForExistence(timeout: 15))
        waitForDocumentSurface()
        openResearchGuidanceSkills()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchGuidance.skill.bundled.scholium-development"
        ].firstMatch.waitForExistence(timeout: 12))
        XCTAssertFalse(app.alerts["Could Not Manage Skills"].exists)
        XCTAssertFalse(app.staticTexts[
            "The Triptych is incomplete. Choose Analyses, Topics, and Works again."
        ].exists)
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
        scrollUntilHittable(
            instruction,
            in: app.descendants(matching: .any)["scholium.researchFunctionPanel.scroll"]
        )
        instruction.click()
        instruction.typeText(initialComment)
        let prepareRun = app.descendants(matching: .any)[
            "scholium.prepareResearchFunction"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled })
        prepareRun.click()
        copyPreparedResearchFunctionInstructions()
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !instruction.exists })

        let recordButton = app.buttons["scholium.showResearchRecord"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.click()
        let record = app.descendants(matching: .any)["scholium.researchRecord"]
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        let dialogueSection = record.descendants(matching: .any)["scholium.researchRecord.dialogueSection"]
        XCTAssertTrue(dialogueSection.waitForExistence(timeout: 8))
        let disclosure = dialogueSection.descendants(matching: .any)["scholium.dialogue.entryDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.click()

        let addFollowUp = record.descendants(matching: .any)["scholium.dialogue.addFollowUp"]
        XCTAssertTrue(addFollowUp.waitForExistence(timeout: 5))
        addFollowUp.click()
        let followUpField = app.descendants(matching: .any)["scholium.dialogue.followUpText"]
        XCTAssertTrue(followUpField.waitForExistence(timeout: 5))
        followUpField.click()
        followUpField.typeText(followUpComment)
        app.descendants(matching: .any)["scholium.dialogue.saveFollowUp"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !followUpField.exists })

        let recordResponse = record.descendants(matching: .any)["scholium.dialogue.recordResponse"]
        XCTAssertTrue(recordResponse.waitForExistence(timeout: 5))
        let recordScrollView = record.scrollViews.firstMatch
        XCTAssertTrue(recordScrollView.exists)
        scrollUntilHittable(recordResponse, in: recordScrollView)
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
            in: record,
            containInOrder: [initialComment, followUpComment, agentResponse]
        )

        let recordWindow = app.windows["Research Record"].firstMatch
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !record.exists })
        recordButton.click()
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        let reopenedSection = record.descendants(matching: .any)["scholium.researchRecord.dialogueSection"]
        let reopenedDisclosure = reopenedSection.descendants(matching: .any)["scholium.dialogue.entryDisclosure"]
        XCTAssertTrue(reopenedDisclosure.waitForExistence(timeout: 5))
        reopenedDisclosure.click()
        assertDialogueTurns(
            in: record,
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
        XCTAssertFalse(sheet.descendants(matching: .any)[targetMaterialIdentifier].exists)
        let materialsSearch = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterials.search"
        ]
        XCTAssertTrue(materialsSearch.waitForExistence(timeout: 5))
        materialsSearch.click()
        materialsSearch.typeText("QA Autosave B")
        XCTAssertTrue(selectedMaterial.waitForExistence(timeout: 8))
        XCTAssertTrue(selectedMaterial.isHittable)
        XCTAssertFalse(checkboxIsSelected(selectedMaterial))

        selectedMaterial.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.checkboxIsSelected(selectedMaterial) })

        materialsSearch.click()
        materialsSearch.typeKey("a", modifierFlags: [.command])
        materialsSearch.typeKey(.delete, modifierFlags: [])
        materialsSearch.typeText("QA Topic")
        let unselectedMaterial = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterial.topic.QA Topic.md"
        ]
        XCTAssertTrue(unselectedMaterial.waitForExistence(timeout: 5))
        XCTAssertFalse(checkboxIsSelected(unselectedMaterial))
        materialsSearch.typeKey("a", modifierFlags: [.command])
        materialsSearch.typeKey(.delete, modifierFlags: [])

        var instruction = sheet.descendants(matching: .any)[
            "scholium.researchFunctionInstruction"
        ]
        XCTAssertTrue(instruction.waitForExistence(timeout: 8))
        scrollUntilHittable(
            instruction,
            in: sheet.descendants(matching: .any)["scholium.researchFunctionPanel.scroll"]
        )
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
        instruction = sheet.descendants(matching: .any)[
            "scholium.researchFunctionInstruction"
        ]
        XCTAssertTrue(instruction.waitForExistence(timeout: 5))
        let reopenedMaterialsSearch = sheet.descendants(matching: .any)[
            "scholium.researchFunctionMaterials.search"
        ]
        XCTAssertTrue(reopenedMaterialsSearch.waitForExistence(timeout: 5))
        reopenedMaterialsSearch.click()
        reopenedMaterialsSearch.typeText("QA Autosave B")
        XCTAssertTrue(selectedMaterial.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedMaterial.isHittable)
        XCTAssertFalse(checkboxIsSelected(selectedMaterial))
        XCTAssertFalse((instruction.value as? String ?? "").contains("Discard this draft"))

        selectedMaterial.click()
        XCTAssertTrue(waitUntil(timeout: 3) { self.checkboxIsSelected(selectedMaterial) })
        XCTAssertTrue(target.staticTexts["QA Autosave A"].exists)
        XCTAssertTrue(target.staticTexts["QA Autosave A.md"].exists)
        XCTAssertFalse(sheet.descendants(matching: .any)[targetMaterialIdentifier].exists)

        scrollUntilHittable(
            instruction,
            in: sheet.descendants(matching: .any)["scholium.researchFunctionPanel.scroll"]
        )
        instruction.click()
        instruction.typeText("Assess the bounded philosophical result with the selected Analysis only.")

        let prepareRun = sheet.descendants(matching: .any)[
            "scholium.prepareResearchFunction"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled && prepareRun.isHittable })
        prepareRun.click()
        let handoff = sheet.descendants(matching: .any)[
            "scholium.copyAndOpenAgentApplication"
        ]
        XCTAssertTrue(handoff.waitForExistence(timeout: 8))
        XCTAssertEqual(handoff.label, "Copy and Choose Agent App…")
        copyPreparedResearchFunctionInstructions()

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
    func testFunctionsInspectorAccessibilityOrderAndDialogueReviewSemantics() {
        waitForDocumentSurface()

        selectResearchInspectorMode("functions")
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchStrip"].exists
        )

        let functions = ["dialogue", "develop", "fidelity"].map { identifier in
            app.descendants(matching: .any)[
                "scholium.researchFunction.\(identifier)"
            ].firstMatch
        }
        for function in functions {
            XCTAssertTrue(function.exists)
            XCTAssertTrue(function.isEnabled)
        }
        for pair in zip(functions, functions.dropFirst()) {
            XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
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
        let humanReview = sheet.descendants(matching: .any)[
            "scholium.humanReviewSheet"
        ]
        XCTAssertTrue(humanReview.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchFunction.review"
        ].exists)
        let reviewCommentComposer = app.descendants(matching: .any)[
            "scholium.newResearcherComment"
        ]
        let selectionRequired = app.descendants(matching: .any)[
            "scholium.commentSelectionRequired"
        ]
        XCTAssertFalse(
            reviewCommentComposer.exists,
            "Human Review must not expose a whole-note Comment textbox."
        )
        XCTAssertTrue(selectionRequired.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
    }

    @MainActor
    func testResearchInspectorModePersistsAcrossNotesAndRelaunch() throws {
        waitForDocumentSurface()
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchStrip"].exists
        )

        selectResearchInspectorMode("overview")
        selectResearchInspectorMode("connections")
        selectResearchInspectorMode("functions")

        let secondRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave B.md"
        ]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 8))
        secondRow.click()
        let documentTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ]
        XCTAssertTrue(waitUntil(timeout: 8) {
            documentTitle.value as? String == "QA Autosave B"
        })
        let functionsMode = app.buttons[
            "scholium.inspectorMode.functions"
        ].firstMatch
        XCTAssertTrue(functionsMode.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ].exists)

        let sessionFile = homeDirectory
            .appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(waitUntil(timeout: 8) {
            guard let data = try? Data(contentsOf: sessionFile),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            return snapshot["inspectorMode"] as? String == "functions"
                && snapshot["inspectorVisible"] as? Bool == true
        })

        app.terminate()
        app = configuredApplication(sessionID: sessionID)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        XCTAssertTrue(app.buttons[
            "scholium.inspectorMode.functions"
        ].firstMatch.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.researchStrip"].exists
        )
    }

    @MainActor
    func testFunctionsInspectorVoiceOverSpeechOrder() throws {
        guard #available(macOS 27.0, *) else {
            throw XCTSkip("The VoiceOver UI-test service requires macOS 27 or newer.")
        }
        waitForDocumentSurface()
        selectResearchInspectorMode("functions")

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

        let expectedFunctions = ["Dialogue", "Develop", "Fidelity"]
        var spoken: [String] = []
        func attachTranscript(_ error: Error? = nil) {
            var lines = spoken.enumerated().map { index, spokenItem in
                "\(index + 1). \(spokenItem)"
            }
            if let error {
                lines.append("Navigation error: \(error.localizedDescription)")
            }
            let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
            attachment.name = "Functions Inspector VoiceOver transcript"
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
        let workFunctionUtterances: [String]
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

            app.buttons["scholium.vault.output"].click()
            let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
            XCTAssertTrue(workRow.waitForExistence(timeout: 8))
            workRow.click()
            waitForDocumentSurface()

            let critiqueControl = app.descendants(matching: .any)[
                "scholium.researchFunction.critique"
            ]
            XCTAssertTrue(critiqueControl.waitForExistence(timeout: 8))
            critiqueControl.click()
            XCTAssertTrue(panel.waitForExistence(timeout: 8))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
            app.typeKey(.F4, modifierFlags: [.control, .option, .shift])
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            let expectedWorkFunctions = [
                "Critique", "Revise", "Dialogue", "Fidelity", "Manuscript",
            ]
            let focusedCritique = try currentUtterance()
            spoken.append("Focused Critique: \(focusedCritique)")
            guard focusedCritique.localizedCaseInsensitiveContains("Critique") else {
                attachTranscript()
                XCTFail("VoiceOver did not follow accessibility focus to Critique.")
                return
            }

            var traversedWork = [focusedCritique]
            var nextWorkIndex = 1
            for step in 1...20 where nextWorkIndex < expectedWorkFunctions.count {
                app.typeKey(.tab, modifierFlags: [])
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                let utterance = try currentUtterance()
                spoken.append("Work Tab \(step): \(utterance)")
                let mentionedIndices = expectedWorkFunctions.indices.filter { index in
                    utterance.localizedCaseInsensitiveContains(expectedWorkFunctions[index])
                }
                if mentionedIndices.contains(nextWorkIndex) {
                    traversedWork.append(utterance)
                    nextWorkIndex += 1
                } else if mentionedIndices.contains(where: { $0 > nextWorkIndex }) {
                    attachTranscript()
                    XCTFail("VoiceOver announced a Work function out of order.")
                    return
                }
            }
            guard nextWorkIndex == expectedWorkFunctions.count else {
                attachTranscript()
                XCTFail("VoiceOver did not announce every Work function in order.")
                return
            }
            workFunctionUtterances = traversedWork
        } catch {
            attachTranscript(error)
            throw error
        }

        let transcript = spoken.enumerated().map { index, spokenItem in
            "\(index + 1). \(spokenItem)"
        }.joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "Functions Inspector VoiceOver transcript"
        attachment.lifetime = .keepAlways
        add(attachment)

        for (expected, actual) in zip(expectedFunctions, functionUtterances) {
            XCTAssertTrue(
                actual.localizedCaseInsensitiveContains(expected),
                "Expected VoiceOver to announce \(expected), but heard \(actual).\n\(transcript)"
            )
        }
        for (expected, actual) in zip(
            ["Critique", "Revise", "Dialogue", "Fidelity", "Manuscript"],
            workFunctionUtterances
        ) {
            XCTAssertTrue(
                actual.localizedCaseInsensitiveContains(expected),
                "Expected VoiceOver to announce \(expected), but heard \(actual).\n\(transcript)"
            )
        }
    }

    @MainActor
    func testFunctionsInspectorAndPanelRemainUsableInLightAndDarkAppearances() {
        for appearance in QAAppearance.allCases {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID,
                initialWorkspaceWidth: 1380,
                appearance: appearance
            )
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 15),
                "The \(appearance.displayName) QA window did not appear."
            )
            waitForDocumentSurface()

            let window = app.windows.firstMatch
            selectResearchInspectorMode("functions")
            let functions = ["dialogue", "develop", "fidelity"].map { identifier in
                app.descendants(matching: .any)[
                    "scholium.researchFunction.\(identifier)"
                ].firstMatch
            }
            for function in functions {
                XCTAssertTrue(function.exists)
                XCTAssertTrue(function.isHittable)
                XCTAssertGreaterThanOrEqual(function.frame.minX, window.frame.minX)
                XCTAssertLessThanOrEqual(function.frame.maxX, window.frame.maxX)
            }
            for pair in zip(functions, functions.dropFirst()) {
                XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
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
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFunctionResponseModules"
            ].exists)
            XCTAssertTrue(sheet.buttons["Cancel"].exists)
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.prepareResearchFunction"
            ].exists)

            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "Functions Inspector and Dialogue — \(appearance.displayName)"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
        }
    }

    @MainActor
    func testCritiqueRequestUsesTriptychResearchGuidanceWithoutAdHocPrompting() throws {
        waitForDocumentSurface()
        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.noteRow.QA Work.md"
        )

        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researcherCommentsPanel"].exists)
        XCTAssertTrue(app.radioButtons["Whole"].exists)
        XCTAssertTrue(app.radioButtons["Passage"].exists)

        let prepareRun = app.descendants(matching: .any)["scholium.prepareResearchFunction"]
        XCTAssertTrue(waitUntil(timeout: 5) { prepareRun.isEnabled && prepareRun.isHittable })
        prepareRun.click()
        copyPreparedResearchFunctionInstructions()
        let copiedInstructions = try pasteboardText()
        XCTAssertTrue(copiedInstructions.contains("scholium-critique"))
        XCTAssertTrue(copiedInstructions.contains("QA Work.md"))
        XCTAssertTrue(panel.exists)
        app.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !panel.exists })
    }

    @MainActor
    func testWorkFunctionsInspectorMaterialsCommentsModulesAndShortcuts() throws {
        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.noteRow.QA Work.md"
        )
        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()
        waitForDocumentSurface()
        selectResearchInspectorMode("functions")

        let orderedIDs = ["critique", "revise", "dialogue", "fidelity", "manuscript"]
        let controls = orderedIDs.map {
            app.descendants(matching: .any)["scholium.researchFunction.\($0)"]
        }
        for control in controls {
            XCTAssertTrue(waitUntil(timeout: 8) {
                control.exists && control.isEnabled && control.isHittable
            })
        }
        for pair in zip(controls, controls.dropFirst()) {
            XCTAssertLessThan(
                pair.0.frame.minY,
                pair.1.frame.minY,
                "The Work Functions mode must expose Critique, Revise, Dialogue, Fidelity, Manuscript in VoiceOver and visual order."
            )
        }

        app.menuBars.menuBarItems["Research"].click()
        for title in ["Critique", "Revise", "Dialogue", "Fidelity", "Manuscript"] {
            XCTAssertTrue(app.menuItems[title].firstMatch.exists)
        }
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("r", modifierFlags: [.command])
        var panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.label, "Critique function")
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionScope"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researcherCommentsPanel"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })

        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        mode.click()
        let sourceMode = app.menuItems
            .matching(identifier: "chevron.left.forwardslash.chevron.right")
            .firstMatch
        XCTAssertTrue(sourceMode.waitForExistence(timeout: 3))
        sourceMode.click()
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        sourceEditor.click()
        app.menuBars.menuBarItems["Insert"].click()
        var addComment = app.menuItems["Add Comment…"].firstMatch
        XCTAssertTrue(addComment.waitForExistence(timeout: 5))
        XCTAssertFalse(addComment.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        sourceEditor.typeKey(.end, modifierFlags: [.command])
        sourceEditor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.menuBars.menuBarItems["Insert"].click()
        addComment = app.menuItems["Add Comment…"].firstMatch
        XCTAssertTrue(addComment.waitForExistence(timeout: 5))
        XCTAssertTrue(addComment.isEnabled)
        addComment.click()
        let commentJudgmentPanel = app.descendants(matching: .any)[
            "scholium.researchFunctionPanel"
        ]
        XCTAssertTrue(commentJudgmentPanel.waitForExistence(timeout: 8))
        XCTAssertEqual(commentJudgmentPanel.label, "Critique function")
        let commentsPanel = app.descendants(matching: .any)[
            "scholium.researcherCommentsPanel"
        ]
        XCTAssertTrue(commentsPanel.waitForExistence(timeout: 8))
        let newComment = app.descendants(matching: .any)["scholium.newResearcherComment"]
        newComment.click()
        newComment.typeText("Synthetic Work boundary Comment.")
        let addCommentButton = app.descendants(matching: .any)[
            "scholium.addResearcherComment"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) { addCommentButton.isHittable })
        addCommentButton.click()
        XCTAssertTrue(commentsPanel.staticTexts[
            "Synthetic Work boundary Comment."
        ].waitForExistence(timeout: 8))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !commentJudgmentPanel.exists })

        app.typeKey("d", modifierFlags: [.command, .shift])
        panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.label, "Dialogue function")
        let target = panel.descendants(matching: .any)["scholium.researchFunctionTarget"]
        XCTAssertTrue(target.exists)
        XCTAssertTrue(target.staticTexts["QA Work"].exists)
        XCTAssertTrue(target.staticTexts["QA Work.md"].exists)

        let material = panel.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.researchFunctionMaterial."
            )
        ).firstMatch
        XCTAssertTrue(material.waitForExistence(timeout: 8))
        let panelScroll = app.descendants(matching: .any)[
            "scholium.researchFunctionPanel.scroll"
        ]
        if !material.isHittable { scrollUntilHittable(material, in: panelScroll) }
        material.click()
        XCTAssertTrue(checkboxIsSelected(material))
        let selectedTray = panel.descendants(matching: .any)[
            "scholium.researchFunctionMaterials.selectedTray"
        ]
        XCTAssertTrue(selectedTray.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.descendants(matching: .any)[
            "scholium.researchFunctionMaterials.search"
        ].exists)
        XCTAssertTrue(panel.descendants(matching: .any)[
            "scholium.researchFunctionMaterials.suggestedOnly"
        ].exists)
        selectedTray.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Remove ")
        ).firstMatch.click()
        XCTAssertFalse(checkboxIsSelected(material))
        XCTAssertTrue(waitUntil(timeout: 3) { !selectedTray.exists })

        let modules = panel.descendants(matching: .any)[
            "scholium.researchFunctionResponseModules"
        ]
        XCTAssertTrue(modules.exists)
        for module in [
            "critical-reflection",
            "remaining-questions",
            "philosophical-significance",
            "debate-context",
            "research-directions",
        ] {
            XCTAssertTrue(panel.descendants(matching: .any)[
                "scholium.researchFunctionResponseModule.\(module)"
            ].exists)
        }
        XCTAssertTrue(panel.descendants(matching: .any)[
            "scholium.researchFunctionAcademicOutcome"
        ].exists)

        let selectableComment = panel.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.researchFunctionComment."
            )
        ).firstMatch
        XCTAssertTrue(selectableComment.waitForExistence(timeout: 8))
        if !selectableComment.isHittable {
            scrollUntilHittable(selectableComment, in: panelScroll)
        }
        selectableComment.click()
        XCTAssertTrue(checkboxIsSelected(selectableComment))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })

        controls[1].click()
        panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.label, "Revise function")
        XCTAssertTrue(app.descendants(matching: .any)["scholium.prepareResearchFunction"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        controls[3].click()
        panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["scholium.researchFunctionFidelity"].exists)
        XCTAssertTrue(panel.checkBoxes["Content"].exists)
        XCTAssertTrue(panel.checkBoxes.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Citations")
        ).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunction.repairCitationMethod"
        ].exists)
        app.typeKey(.escape, modifierFlags: [])

        controls[4].click()
        panel = app.descendants(matching: .any)["scholium.researchFunctionPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertEqual(panel.label, "Manuscript function")
        XCTAssertFalse(panel.staticTexts["Phases"].exists)
        XCTAssertFalse(panel.staticTexts["Packages"].exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
        XCTAssertTrue(
            controls[4].isHittable,
            "Escape must restore focus to the initiating Functions button."
        )
    }

    @MainActor
    func testCritiqueFindingOpensExactWorkPassageInSource() throws {
        waitForDocumentSurface()
        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.folderRow.Critiques"
        )

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

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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

        let inspector = app.descendants(matching: .any)["scholium.toggleInspector"]
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
        let addComment = app.menuItems["Add Comment…"].firstMatch
        XCTAssertTrue(addComment.exists)
        XCTAssertFalse(addComment.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        // Collapse any selection retained by the persistent editor session so
        // this first context-menu assertion is deterministic. The second half
        // of the test creates an explicit selection and verifies Comment then.
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.rightClick()
        let editorContextMenu = app.menus["scholium.editor.contextMenu"]
        XCTAssertTrue(editorContextMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(editorContextMenu.menuItems["Bold"].waitForExistence(timeout: 3))
        XCTAssertFalse(editorContextMenu.menuItems["Add Comment…"].exists)
        app.typeKey(.escape, modifierFlags: [])

        editor.typeKey(.rightArrow, modifierFlags: [.shift])
        insert.click()
        XCTAssertTrue(app.menuItems["Add Comment…"].firstMatch.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testSearchThisNoteReportsMatchesNoResultsAndCloses() throws {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })

        app.typeKey("f", modifierFlags: [.command])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let searchMode = app.descendants(matching: .any)["scholium.searchMode"]
        let closeSearch = app.descendants(matching: .any)["scholium.closeSearchButton"]
        XCTAssertTrue(searchMode.waitForExistence(timeout: 5))
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.radioButtons["This Note"].exists)
        XCTAssertTrue(app.radioButtons["This Vault"].exists)
        XCTAssertTrue(app.radioButtons["Triptych"].exists)
        let collapsedControls = field.frame
            .union(searchMode.frame)
            .union(closeSearch.frame)
        XCTAssertLessThanOrEqual(collapsedControls.width, 644)
        XCTAssertLessThanOrEqual(collapsedControls.height, 80)

        typeCommittedText("analysis", into: field, in: app)
        app.radioButtons["This Note"].click()
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let expandedContentHeight = result.frame.maxY - field.frame.minY
        XCTAssertGreaterThan(expandedContentHeight, collapsedControls.height)
        XCTAssertLessThanOrEqual(expandedContentHeight, 524)

        field.click()
        field.typeKey("a", modifierFlags: [.command])
        typeCommittedText("not in this rendered note", into: field, in: app)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !result.exists
        })
        XCTAssertTrue(
            waitUntil(timeout: 5) { closeSearch.exists },
            "A new query must not dismiss Search by opening a stale result."
        )

        closeSearch.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        XCTAssertTrue(renderedDocument.exists)
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
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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
        relaunchApplication(initialWorkspaceWidth: 1380)
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
    func testResearchFunctionPanelFitsWideEditor() throws {
        waitForDocumentSurface()

        let wideWindow = app.windows.firstMatch
        guard wideWindow.frame.width >= 1_200 else {
            throw XCTSkip(
                "AppKit restored a narrower test-owned frame; rerun this journey from a clean QA preference domain."
            )
        }
        openResearchFunctionAndVerifyPanel(
            minimumWidth: 540,
            maximumWidth: 720,
            window: wideWindow
        )

        app.buttons["scholium.dismissResearchFunction"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.app.sheets.firstMatch.exists })
    }

    @MainActor
    func testResearchFunctionPanelFitsCompactEditor() throws {
        waitForDocumentSurface()

        let compactWindow = app.windows.firstMatch
        guard compactWindow.frame.width < 980 else {
            throw XCTSkip(
                "AppKit restored a wider test-owned frame; rerun this journey from a clean QA preference domain."
            )
        }
        openResearchFunctionAndVerifyPanel(
            minimumWidth: 540,
            maximumWidth: 720,
            window: compactWindow
        )
        app.buttons["scholium.dismissResearchFunction"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !self.app.sheets.firstMatch.exists })

        let compactWorks = app.buttons["scholium.vault.output"]
        if !compactWorks.exists {
            let sidebarToggle = app.buttons["Show Sidebar"].exists
                ? app.buttons["Show Sidebar"]
                : app.buttons["Hide Sidebar"]
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))
            sidebarToggle.click()
            XCTAssertTrue(app.descendants(matching: .any)[
                "scholium.librarySurface"
            ].waitForExistence(timeout: 5))
        }
        XCTAssertTrue(compactWorks.waitForExistence(timeout: 5))
        compactWorks.click()
        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 8))
        workRow.click()
        waitForDocumentSurface()
        openResearchFunctionAndVerifyPanel(
            minimumWidth: 540,
            maximumWidth: 720,
            window: compactWindow
        )
    }

    @MainActor
    func testWorkspaceInitialDefaultPreservesNativeReachability() throws {
        waitForDocumentSurface()
        let window = app.windows.firstMatch
        guard abs(window.frame.width - QAWorkspaceMetricContract.preferredWidth)
            <= QAWorkspaceMetricContract.frameTolerance else {
            throw XCTSkip(
                "AppKit restored a test-owned frame; rerun this first-presentation journey from a clean QA preference domain."
            )
        }
        XCTAssertTrue(app.descendants(matching: .any)["Rendered Markdown"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.toggleSidebar"]
                .waitForExistence(timeout: 5)
        )
        let inspectorButton = app.descendants(matching: .any)["scholium.toggleInspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.isEnabled)
    }

    @MainActor
    func testNativeSidebarToggleAndLibraryTriptychIdentityRemainAvailable() throws {
        waitForDocumentSurface()
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let triptychManagement = app.menuButtons["Triptych management"]
        XCTAssertTrue(triptychManagement.waitForExistence(timeout: 5))
        let hideSidebar = app.buttons["Hide Sidebar"]
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(librarySurface.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(triptychManagement.frame.minX, librarySurface.frame.minX)
        XCTAssertLessThan(triptychManagement.frame.maxX, librarySurface.frame.maxX)
        let folderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Level 1 - Philosophy of Emotion"
        ]
        let noteRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            noteRow.frame.minX,
            folderRow.frame.minX + 30,
            "Top-level note rows must remain aligned with the Library outline."
        )
        XCTAssertFalse(app.buttons["Collapse Note"].exists)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Collapse Note"].exists)
        app.typeKey(.escape, modifierFlags: [])

        hideSidebar.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.app.descendants(matching: .any)["scholium.librarySurface"].exists
        })
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
        hideSidebar.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 1)

        let shellScreenshot = XCTAttachment(screenshot: window.screenshot())
        shellScreenshot.name = "Full-height editorial Library with native sidebar controls"
        shellScreenshot.lifetime = .keepAlways
        add(shellScreenshot)
    }

    /// A retained visual checkpoint for the native-toolbar migration. This is
    /// intentionally a narrow proof rather than a claim that the complete UI
    /// acceptance matrix has passed.
    @MainActor
    func testNativeToolbarVisualProofAtDefaultWindowSize() throws {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: 1_180,
            appearance: .light
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()

        let window = app.windows.firstMatch
        guard abs(window.frame.width - QAWorkspaceMetricContract.preferredWidth)
            <= QAWorkspaceMetricContract.frameTolerance else {
            throw XCTSkip(
                "AppKit restored a test-owned frame; rerun this visual checkpoint from a clean QA preference domain."
            )
        }

        let sidebarToggle = app.descendants(matching: .any)["scholium.toggleSidebar"]
        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        let search = app.descendants(matching: .any)["scholium.documentSearch"]
        let history = app.descendants(matching: .any)["scholium.showResearchRecord"]
        let inspectorToggle = app.descendants(matching: .any)["scholium.toggleInspector"]
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))

        XCTAssertLessThan(sidebarToggle.frame.midX, window.frame.midX)
        XCTAssertGreaterThan(search.frame.midX, mode.frame.midX)
        XCTAssertGreaterThan(history.frame.midX, search.frame.midX)
        XCTAssertGreaterThan(inspectorToggle.frame.midX, window.frame.midX)

        let close = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(close.exists)
        XCTAssertLessThanOrEqual(abs(close.frame.midY - sidebarToggle.frame.midY), 12)

        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        if !library.exists { sidebarToggle.click() }
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let triptych = app.descendants(matching: .any)["scholium.triptychManagement"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))

        let documentIdentity = app.descendants(matching: .any)[
            "scholium.documentToolbarIdentity"
        ]
        let documentActions = app.descendants(matching: .any)[
            "scholium.documentToolbarActions"
        ]
        XCTAssertTrue(documentIdentity.waitForExistence(timeout: 5))
        XCTAssertTrue(documentActions.waitForExistence(timeout: 5))
        XCTAssertLessThan(documentIdentity.frame.maxX, mode.frame.minX)
        // AppKit may report a grouped toolbar item's accessibility frame one
        // physical pixel inside its hosted control. Compare with a two-point
        // tolerance; this is not visual spacing owned by Scholium.
        XCTAssertGreaterThanOrEqual(mode.frame.minX, documentActions.frame.minX - 2)
        XCTAssertEqual(mode.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertEqual(search.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertEqual(history.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertLessThan(
            history.frame.maxX,
            inspectorToggle.frame.minX,
            "Research Record must remain immediately left of the Inspector control."
        )

        let inspector = app.scrollViews["scholium.researchInspector"]
        if !inspector.exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            history.frame.maxX,
            inspector.frame.minX,
            "Document commands must end before the Apparatus begins."
        )

        // Move the pointer off the toolbar control so its transient help tag
        // cannot obscure the retained visual proof.
        let proofFocus = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
        )
        proofFocus.hover()
        proofFocus.click()

        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Transparent native titlebar — default 1180pt workspace"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let untabbedHeaderTop = documentIdentity.frame.minY - window.frame.minY
        app.menuBars.menuBarItems["File"].click()
        let openInNewTab = app.menuItems["Open in New Tab"]
        XCTAssertTrue(openInNewTab.waitForExistence(timeout: 3))
        openInNewTab.click()
        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(documentTabs.waitForExistence(timeout: 8))

        // Document tabs retain independent documents while borrowing the one
        // window-owned Library and Apparatus presentation.
        let tabbedInspector = app.scrollViews["scholium.researchInspector"]
        XCTAssertTrue(tabbedInspector.waitForExistence(timeout: 5))
        let tabbedLibrary = app.descendants(matching: .any)[
            "scholium.librarySurface"
        ].firstMatch
        XCTAssertTrue(tabbedLibrary.waitForExistence(timeout: 5))

        let tabbedIdentity = app.descendants(matching: .any)[
            "scholium.documentToolbarIdentity"
        ].firstMatch
        XCTAssertTrue(tabbedIdentity.waitForExistence(timeout: 5))
        let tabbedWindow = app.windows.firstMatch
        let tabbedHeaderTop = tabbedIdentity.frame.minY - tabbedWindow.frame.minY
        XCTAssertEqual(
            tabbedHeaderTop,
            untabbedHeaderTop,
            accuracy: 2,
            "Opening document tabs must not push the document title and commands below the top toolbar."
        )
        XCTAssertGreaterThanOrEqual(
            documentTabs.frame.minX,
            tabbedLibrary.frame.maxX - 3,
            "The visible native-tab presentation must begin at the Library/Document divider."
        )
        XCTAssertLessThanOrEqual(
            documentTabs.frame.maxX,
            tabbedInspector.frame.minX + 3,
            "The visible native-tab presentation must end at the Document/Apparatus divider."
        )
        XCTAssertFalse(
            app.tabGroups.firstMatch.exists,
            "The full-window AppKit tab bar must stay hidden when the Document split accessory is visible."
        )

        let tabbedScreenshot = XCTAttachment(screenshot: tabbedWindow.screenshot())
        tabbedScreenshot.name = "Document-scoped native window tabs below persistent toolbar"
        tabbedScreenshot.lifetime = .keepAlways
        add(tabbedScreenshot)
    }

    @MainActor
    func testNoDocumentKeepsTrailingToolbarControlsVisibleAndDisabled() throws {
        app.terminate()
        if let enumerator = FileManager.default.enumerator(
            at: triptychDirectory,
            includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                try FileManager.default.removeItem(at: url)
            }
        }
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: 1_180,
            openNote: nil
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let history = app.descendants(matching: .any)["scholium.showResearchRecord"]
        let inspector = app.descendants(matching: .any)["scholium.toggleInspector"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.documentToolbarIdentity"].exists,
            "An empty Triptych must not expose a stale document identity."
        )
        XCTAssertFalse(history.isEnabled)
        XCTAssertFalse(inspector.isEnabled)
        XCTAssertLessThan(history.frame.maxX, inspector.frame.minX)
    }

    @MainActor
    func testSystemInspectorToolbarItemOpensAndClosesInspector() throws {
        // Keep the trailing toolbar item inside the active display. The
        // default 1380-point acceptance window can extend beyond smaller test
        // displays even though the application window itself is valid.
        relaunchApplication(initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth))
        waitForDocumentSurface()

        let inspectorToggle = app.descendants(matching: .any)["scholium.toggleInspector"]
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorToggle.isEnabled)

        let inspector = app.scrollViews["scholium.researchInspector"].firstMatch
        if inspector.exists {
            inspectorToggle.click()
            XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        }

        inspectorToggle.click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        inspectorToggle.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
    }

    @MainActor
    func testTwoHundredPercentDocumentTextPersistsAcrossEveryMode() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
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
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
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
    func testResearchRecordIsIndependentFromInspector() throws {
        waitForDocumentSurface()
        let originalWorkspaceID = app.windows.firstMatch.identifier
        let originalWorkspace = app.windows[originalWorkspaceID]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let recordButton = app.buttons["scholium.showResearchRecord"]
        let record = app.descendants(matching: .any)["scholium.researchRecord"]

        if !inspector.exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        XCTAssertTrue(recordButton.exists)
        recordButton.click()

        let recordWindow = app.windows["Research Record"].firstMatch
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        XCTAssertFalse(recordWindow.staticTexts["No Active Document"].exists)
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        XCTAssertTrue(inspector.exists)
        XCTAssertTrue(recordWindow.staticTexts["QA Autosave A"].waitForExistence(timeout: 5))

        focusWorkspaceWindow(originalWorkspace)
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 3 })
        let newWorkspace = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first(where: { window in
                window.identifier != originalWorkspaceID
                    && window.identifier != recordWindow.identifier
            })
        )
        focusWorkspaceWindow(newWorkspace)
        openNote("QA Autosave B.md", expectedTitle: "QA Autosave B", in: newWorkspace)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                recordWindow.staticTexts["QA Autosave B"].exists
            },
            "Research Record must follow the focused workspace without retaining a manual window model."
        )

        focusWorkspaceWindow(originalWorkspace)
        XCTAssertTrue(waitUntil(timeout: 8) {
            recordWindow.staticTexts["QA Autosave A"].exists
        })
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !record.exists })
        XCTAssertTrue(inspector.exists)
        focusWorkspaceWindow(newWorkspace)
        closeFrontmostWindow()
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
            initialWorkspaceWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        let observingWindowID = app.windows.firstMatch.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let editingWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first(where: {
                $0.identifier != observingWindowID
            })
        )
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: editingWindow)
        let editingMetadata = editingWindow.descendants(matching: .any)["scholium.documentNoteName"]
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
        let observingWindow = app.windows[observingWindowID]
        let observingMetadata = observingWindow.descendants(matching: .any)["scholium.documentNoteName"]
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
            initialWorkspaceWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        let originalWindowID = app.windows.firstMatch.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let windows = app.windows.allElementsBoundByIndex
        XCTAssertEqual(windows.count, 2)
        if let newWindow = windows.first(where: { $0.identifier != originalWindowID }) {
            openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: newWindow)
        } else {
            XCTFail("New Window must create a distinct window identity.")
        }
        for window in windows {
            let metadata = window.descendants(matching: .any)["scholium.documentNoteName"]
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
            let metadata = window.descendants(matching: .any)["scholium.documentNoteName"]
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
            initialWorkspaceWidth: 1380,
            usesFixedSessionID: false,
            autosaveDelayMS: 20_000
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        let dirtyWindowID = app.windows.firstMatch.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let openedWindows = app.windows.allElementsBoundByIndex
        let peerWindowID = try XCTUnwrap(
            openedWindows.first(where: { $0.identifier != dirtyWindowID })?.identifier
        )
        XCTAssertNotEqual(dirtyWindowID, peerWindowID)
        let dirtyWindow = app.windows[dirtyWindowID]
        let peerWindow = app.windows[peerWindowID]
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: peerWindow)

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
            initialWorkspaceWidth: 1380,
            usesFixedSessionID: false
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        let firstWindowID = app.windows.firstMatch.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let openedWindows = app.windows.allElementsBoundByIndex
        let secondWindowID = try XCTUnwrap(
            openedWindows.first(where: { $0.identifier != firstWindowID })?.identifier
        )
        let firstWindow = app.windows[firstWindowID]
        let secondWindow = app.windows[secondWindowID]
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: secondWindow)
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
            initialWorkspaceWidth: 1380,
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
        let originalMetadata = originalWindow.descendants(matching: .any)["scholium.documentNoteName"]
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
        let secondMetadata = secondWindow.descendants(matching: .any)["scholium.documentNoteName"]
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
                window.descendants(matching: .any)["scholium.documentNoteName"].value as? String
            }
            return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
        })

        let restoredWindows = app.windows.allElementsBoundByIndex
        let restoredA = try XCTUnwrap(restoredWindows.first { window in
            window.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Autosave A"
        })
        let restoredB = try XCTUnwrap(restoredWindows.first { window in
            window.descendants(matching: .any)["scholium.documentNoteName"].value as? String
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
        let mergeWindows = app.menuItems["Merge All Windows"]
        XCTAssertTrue(mergeWindows.waitForExistence(timeout: 3))
        XCTAssertTrue(mergeWindows.isEnabled)
        mergeWindows.click()

        app.menuBars.menuBarItems["Window"].click()
        let moveTabToNewWindow = app.menuItems["Move Tab to New Window"]
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
                window.descendants(matching: .any)["scholium.documentNoteName"].value as? String
            }
            return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
        })
    }

    @MainActor
    func testLifecycleCardsPreserveTheOpenDocumentAndLibraryGeometry() throws {
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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

        app.menuBars.menuBarItems["File"].click()
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

        app.menuBars.menuBarItems["File"].click()
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

        relaunchApplication(initialWorkspaceWidth: 1380)
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

        app.menuBars.menuBarItems["File"].click()
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

        app.menuBars.menuBarItems["File"].click()
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
        app.menuBars.menuBarItems["File"].click()
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

        app.menuBars.menuBarItems["File"].click()
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

        app.menuBars.menuBarItems["File"].click()
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
    func testDocumentHasNoFloatingMetadataSurfaceAndInspectorRemainsIndependent() throws {
        let renderedDocument = app.descendants(matching: .any)[
            "scholium.renderedDocument.QA Autosave A.md"
        ]
        XCTAssertTrue(renderedDocument.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["scholium.documentContextCluster"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.documentContextControls"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.metadataPanel"].exists)

        let documentIdentity = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(documentIdentity.waitForExistence(timeout: 10))
        XCTAssertEqual(documentIdentity.value as? String, "QA Autosave A")

        let inspectorButton = app.descendants(matching: .any)["scholium.toggleInspector"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        let inspectorWasVisible = inspector.exists
        inspectorButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { inspector.exists != inspectorWasVisible })
        XCTAssertTrue(renderedDocument.exists)
        inspectorButton.click()
        XCTAssertTrue(waitUntil(timeout: 3) { inspector.exists == inspectorWasVisible })
        XCTAssertTrue(renderedDocument.exists)
    }

    @MainActor
    func testHumanReviewCannotCompleteWithoutRequiredJudgment() throws {
        selectResearchInspectorMode("overview")
        let review = app.descendants(matching: .any)[
            "scholium.openReview"
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
        selectResearchInspectorMode("overview")

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
    func testRecommendedBibliographyStaysAtLibraryBottomAcrossScopes() throws {
        let librarySection = app.descendants(matching: .any)[
            "scholium.recommendedBibliography.library"
        ]
        XCTAssertTrue(librarySection.waitForExistence(timeout: 8))

        let openDetails = app.descendants(matching: .any)[
            "scholium.recommendedBibliography.open"
        ]
        XCTAssertTrue(openDetails.waitForExistence(timeout: 5))
        openDetails.click()
        let details = app.descendants(matching: .any)[
            "scholium.recommendedBibliography"
        ]
        XCTAssertTrue(details.waitForExistence(timeout: 5))

        let goals = app.descendants(matching: .any)[
            "scholium.recommendedBibliography.goals"
        ]
        let purpose = app.descendants(matching: .any)[
            "scholium.recommendedBibliography.purpose"
        ]
        let prepare = app.descendants(matching: .any)[
            "scholium.recommendedBibliography.prepare"
        ]
        XCTAssertTrue(goals.exists)
        XCTAssertEqual(goals.value as? String, "Goals: Neutral")
        XCTAssertTrue(purpose.exists)
        XCTAssertTrue(prepare.isEnabled)

        goals.click()
        let objections = app.menuItems["Objections"]
        XCTAssertTrue(objections.waitForExistence(timeout: 3))
        objections.click()
        XCTAssertTrue(waitUntil(timeout: 3) {
            (goals.value as? String) == "Goals: 1"
        })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !details.exists })

        app.descendants(matching: .any)["scholium.vault.topic_knowledge"].click()
        let topic = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
        XCTAssertTrue(topic.waitForExistence(timeout: 8))
        topic.click()
        XCTAssertTrue(librarySection.waitForExistence(timeout: 8))
        openDetails.click()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.recommendedBibliography.prepare"
        ].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        app.descendants(matching: .any)["scholium.vault.output"].click()
        let work = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        XCTAssertTrue(work.waitForExistence(timeout: 8))
        work.click()
        XCTAssertTrue(librarySection.waitForExistence(timeout: 8))
        openDetails.click()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.recommendedBibliography.prepare"
        ].isEnabled)
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

        let inspectorButton = app.descendants(matching: .any)["scholium.toggleInspector"]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let inspectorWasVisible = inspector.exists
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { inspector.exists != inspectorWasVisible },
            "The native Inspector toggle must change the trailing split presentation."
        )

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
            (self.app.descendants(matching: .any)["scholium.documentNoteName"].value as? String) == "QA Autosave B"
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

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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

        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
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
        selectResearchInspectorMode("functions")
        let functionsMode = app.buttons[
            "scholium.inspectorMode.functions"
        ].firstMatch
        XCTAssertTrue(functionsMode.isSelected)
        secondRow.click()
        XCTAssertTrue(functionsMode.isSelected)

        // Remove the peer first, then move the selected file immediately. On
        // the resulting inventory both prior identities are absent and both
        // have the exact fingerprint of the new path.
        try FileManager.default.removeItem(at: secondURL)
        try FileManager.default.moveItem(at: firstURL, to: movedURL)

        let movedRow = app.descendants(matching: .any)["scholium.noteRow.\(movedPath)"]
        XCTAssertTrue(movedRow.waitForExistence(timeout: 12))
        movedRow.click()

        let chooseIdentity = app.buttons["Choose Identity…"]
        let identityChoiceAppeared = chooseIdentity.waitForExistence(timeout: 12)
        if !identityChoiceAppeared,
           let identityState = try? String(
               contentsOf: triptychDirectory.appendingPathComponent(".scholium/identities.json"),
               encoding: .utf8
           ) {
            let attachment = XCTAttachment(string: identityState)
            attachment.name = "Portable identity state after ambiguous external rename"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(
            identityChoiceAppeared,
            "Equal fingerprints from two missing notes must remain blocked for researcher confirmation."
        )
        XCTAssertEqual(try source(at: movedURL), ambiguousSource)

        // Functions require a resolved stable Target. Keep the selected
        // Inspector mode, but expose no incorrect launcher while identity
        // confirmation is pending.
        XCTAssertTrue(functionsMode.isSelected)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchFunction.dialogue"
        ].exists)

        chooseIdentity.click()
        let firstCandidate = app.radioButtons["Use the note identity previously at \(firstPath)"]
        let secondCandidate = app.radioButtons["Use the note identity previously at \(secondPath)"]
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCandidate.exists)
        firstCandidate.click()
        app.buttons["Confirm Identity"].click()

        XCTAssertTrue(waitUntil(timeout: 12) { !chooseIdentity.exists })
        XCTAssertTrue(functionsMode.isSelected)
        let dialogue = app.descendants(matching: .any)["scholium.researchFunction.dialogue"]
        let develop = app.descendants(matching: .any)["scholium.researchFunction.develop"]
        let fidelity = app.descendants(matching: .any)["scholium.researchFunction.fidelity"]
        let review = app.descendants(matching: .any)["scholium.researchFunction.review"]
        XCTAssertTrue(dialogue.exists)
        XCTAssertTrue(develop.exists)
        XCTAssertTrue(fidelity.exists)
        XCTAssertFalse(
            review.exists,
            "Human Review is presented within Dialogue, not as a separate agent function."
        )
        XCTAssertEqual(try source(at: movedURL), ambiguousSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    @MainActor
    func testDirtyExternalRenameRebindsAndPreservesTheUncommittedEditorBuffer() throws {
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

        // A unique same-byte rename preserves the stable note identity. The
        // retained session therefore changes location without discarding its
        // exact buffer, and the existing fingerprint gate authorizes autosave
        // only against the unchanged bytes at that new location. The token was
        // absent from disk before the move, so its exact appearance at the new
        // path is the end-to-end proof that the dirty in-memory buffer survived
        // rebinding. Xcode 27 truncates long CodeMirror AX values and cannot be
        // used as a complete-buffer oracle here.
        let renamedBufferWasSaved = waitUntil(timeout: 15) {
            (try? self.source(at: renamedURL).contains(localToken)) == true
        }
        XCTAssertTrue(
            renamedBufferWasSaved,
            "The identity-rebound session must autosave its preserved buffer at the confirmed new path."
        )
        XCTAssertFalse(app.alerts["Save Failed"].exists)
        XCTAssertFalse(app.alerts["This Note Changed on Disk"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].exists)
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(try source(at: renamedURL), originalSource + localToken)
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
    func testVisibleFootnotePreviewClosesBeforeExternalConflictRecovery() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let localToken = " PREVIEW-LOCAL-\(UUID().uuidString)"
        let searchableToken = localToken.trimmingCharacters(in: .whitespaces)
        let diskToken = "\n\n## External Revision While Previewing\n"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let editor = enterLivePreview()
        app.typeKey(.end, modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        try setPasteboardText(localToken)
        app.typeKey("v", modifierFlags: [.command])

        // The fixture's third reference remains in the visible final viewport.
        // Select it first so the native context menu consumes the same exact
        // insertion point that keyboard and menu-command routes use.
        let footnoteReference = app.buttons["Footnote 3"].firstMatch
        XCTAssertTrue(footnoteReference.waitForExistence(timeout: 8))
        XCTAssertTrue(footnoteReference.isHittable)
        footnoteReference.rightClick()

        let editorContextMenu = app.menus["scholium.editor.contextMenu"]
        XCTAssertTrue(editorContextMenu.waitForExistence(timeout: 3))
        let preview = editorContextMenu.menuItems["Preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        preview.click()

        let previewTitle = app.staticTexts["Footnote fixture-three"]
        XCTAssertTrue(
            previewTitle.waitForExistence(timeout: 5),
            "The non-hover route must make the selected single-footnote preview visible."
        )
        let previewContent = app.groups["Preview content"]
        XCTAssertTrue(previewContent.waitForExistence(timeout: 3))
        let dirtyPreviewContent = previewContent.descendants(matching: .any).matching(
            NSPredicate(format: "value CONTAINS %@", searchableToken)
        ).firstMatch
        XCTAssertTrue(
            dirtyPreviewContent.waitForExistence(timeout: 3),
            "The preview must reflect the exact dirty Editor buffer before any disk conflict."
        )

        let originalDisk = try source(at: noteURL)
        XCTAssertFalse(originalDisk.contains(localToken))
        try write(originalDisk + diskToken, to: noteURL)

        let conflictWindow = app.windows.firstMatch
        let keepEditing = conflictWindow.buttons["Keep Editing"]
        XCTAssertTrue(
            keepEditing.waitForExistence(timeout: 12),
            "An external edit must retain conflict ownership while a preview is visible."
        )
        XCTAssertTrue(
            waitUntil(timeout: 3) { !previewTitle.exists },
            "The disposable preview must close when conflict recovery takes focus."
        )
        XCTAssertTrue(try source(at: noteURL).contains(diskToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        keepEditing.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(
            (editor.value as? String ?? "").contains(localToken),
            "Keeping the dirty buffer after previewing must not accept the disk revision."
        )
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

        let qaMenu = app.menuBars.menuBarItems["QA"]
        XCTAssertTrue(qaMenu.waitForExistence(timeout: 5))
        qaMenu.click()
        let terminateEditor = app.menuItems["Simulate Editor Process Termination"]
        XCTAssertTrue(terminateEditor.waitForExistence(timeout: 3))
        XCTAssertTrue(terminateEditor.isEnabled)
        terminateEditor.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (try? Data(contentsOf: markerURL).isEmpty) == false
            },
            "The QA-only distributed fault route must reach the focused bridge document."
        )

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        XCTAssertTrue(
            waitUntil(timeout: 12) { (editor.value as? String ?? "").contains(token) },
            "Recovery must restore the accepted dirty buffer rather than rereading disk."
        )
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                guard let committed = try? Data(contentsOf: noteURL) else { return false }
                return committed == Data((originalSource + token).utf8)
            },
            "The recovered dirty buffer must remain eligible for the normal fingerprint-gated flush."
        )
    }

    @MainActor
    func testHundredThousandCJKEditorStressJourney() throws {
        app.terminate()
        let seed = "研究性能边界输入选择撤销渲染滚动保存恢复"
        let cjkCharacters = String(
            String(repeating: seed, count: 100_000 / seed.count + 1).prefix(100_000)
        )
        XCTAssertEqual(cjkCharacters.count, 100_000)
        var cjkParagraphs: [String] = []
        var paragraphStart = cjkCharacters.startIndex
        while paragraphStart < cjkCharacters.endIndex {
            let paragraphEnd = cjkCharacters.index(
                paragraphStart,
                offsetBy: 1_000,
                limitedBy: cjkCharacters.endIndex
            ) ?? cjkCharacters.endIndex
            cjkParagraphs.append(String(cjkCharacters[paragraphStart..<paragraphEnd]))
            paragraphStart = paragraphEnd
        }
        let cjkBody = cjkParagraphs.joined(separator: "\n\n")
        let source = "---\ntitle: QA 100k CJK\nfixture: true\n---\n# CJK Stress\n\n\(cjkBody)\n"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA 100k CJK.md")
        try write(source, to: noteURL)

        app = configuredApplication(
            sessionID: sessionID,
            autosaveDelayMS: 300_000,
            openNote: "QA 100k CJK.md"
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))

        let mode = app.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        mode.click()
        let livePreview = app.menuItems["Live Preview"].firstMatch
        XCTAssertTrue(livePreview.waitForExistence(timeout: 5))
        livePreview.click()

        let editor = app.descendants(matching: .any)["Markdown live preview editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        let window = app.windows.firstMatch
        let visibleEditorFrame = editor.frame.intersection(window.frame)
        XCTAssertFalse(visibleEditorFrame.isNull)
        XCTAssertGreaterThan(visibleEditorFrame.width, 0)
        XCTAssertGreaterThan(visibleEditorFrame.height, 0)
        window.coordinate(withNormalizedOffset: CGVector(
            dx: (visibleEditorFrame.midX - window.frame.minX) / window.frame.width,
            dy: (visibleEditorFrame.midY - window.frame.minY) / window.frame.height
        )).click()

        let beginningToken = "QA-CJK-BEGIN-\(UUID().uuidString)"
        editor.typeKey(.home, modifierFlags: [.command])
        try setPasteboardText(beginningToken)
        editor.typeKey("v", modifierFlags: [.command])
        editor.typeKey("z", modifierFlags: [.command])

        for _ in 0..<24 { editor.typeKey(.pageDown, modifierFlags: []) }
        let middleToken = "QA-CJK-MIDDLE-\(UUID().uuidString)"
        try setPasteboardText(middleToken)
        editor.typeKey("v", modifierFlags: [.command])
        editor.typeKey("z", modifierFlags: [.command])

        let endToken = "QA-CJK-END-\(UUID().uuidString)"
        editor.typeKey(.end, modifierFlags: [.command])
        try setPasteboardText(endToken)
        editor.typeKey("v", modifierFlags: [.command])
        XCTAssertEqual(try Data(contentsOf: noteURL), Data(source.utf8))

        let saveTransitionStarted = DispatchTime.now().uptimeNanoseconds
        mode.click()
        let readMode = app.menuItems["Read"].firstMatch
        XCTAssertTrue(readMode.waitForExistence(timeout: 5))
        readMode.click()
        XCTAssertTrue(app.descendants(matching: .any)["Rendered Markdown"].waitForExistence(timeout: 180))
        XCTAssertEqual(try Data(contentsOf: noteURL), Data((source + endToken).utf8))
        let saveTransitionMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - saveTransitionStarted
        ) / 1_000_000
        let evidence = XCTAttachment(
            string: "100,000-CJK-character dirty Live Preview reached byte-exact committed Read mode in \(saveTransitionMilliseconds) ms under the QA automation boundary."
        )
        evidence.name = "100k CJK byte-exact save transition observation"
        evidence.lifetime = .keepAlways
        add(evidence)

        mode.click()
        let sourceMode = app.menuItems["Source"].firstMatch
        XCTAssertTrue(sourceMode.waitForExistence(timeout: 5))
        sourceMode.click()
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 15))
        mode.click()
        XCTAssertTrue(livePreview.waitForExistence(timeout: 5))
        livePreview.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        XCTAssertEqual(try Data(contentsOf: noteURL), Data((source + endToken).utf8))
    }

    @MainActor
    func testOpenInNewTabUsesDocumentRegionTabsAndVisibleClose() throws {
        waitForDocumentSurface()
        let secondPath = "QA Autosave B.md"
        let inspectorToggle = app.descendants(matching: .any)["scholium.toggleInspector"]
        let inspector = app.scrollViews["scholium.researchInspector"].firstMatch
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))
        if !inspector.exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        let secondRow = app.descendants(matching: .any)["scholium.noteRow.\(secondPath)"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10))
        secondRow.rightClick()
        let noteContextMenu = app.menus["scholium.noteRow.\(secondPath)"]
        XCTAssertTrue(noteContextMenu.waitForExistence(timeout: 3))
        let openInNewTab = noteContextMenu.menuItems["Open in New Tab"]
        XCTAssertTrue(openInNewTab.waitForExistence(timeout: 3))
        openInNewTab.click()

        // Expand a known collection only after opening the second root note.
        // Expanding a large first folder can move root notes outside the lazy
        // Library viewport, which is not evidence about document tabs.
        let sharedFolder = app.descendants(matching: .any)[
            "scholium.folderRow.Level 1 - Philosophy of Emotion"
        ]
        XCTAssertTrue(sharedFolder.waitForExistence(timeout: 8))
        if sharedFolder.value as? String != "Expanded" {
            sharedFolder.click()
        }
        XCTAssertTrue(waitUntil(timeout: 5) {
            sharedFolder.value as? String == "Expanded"
        })

        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(documentTabs.waitForExistence(timeout: 8))
        let firstTab = documentTabs.buttons["QA Autosave A"]
        let secondTab = documentTabs.buttons["QA Autosave B"]
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTab.waitForExistence(timeout: 5))
        XCTAssertTrue(documentTabs.buttons["Close QA Autosave A"].exists)
        XCTAssertTrue(documentTabs.buttons["Close QA Autosave B"].exists)
        XCTAssertFalse(app.tabGroups.firstMatch.exists)

        let sharedFolderIdentifier = sharedFolder.identifier
        func currentSharedFolder() -> XCUIElement {
            self.app.descendants(matching: .any)[sharedFolderIdentifier]
        }

        func sharedPresentationIsPreserved(expectedNote: String) -> Bool {
            let folder = currentSharedFolder()
            let currentInspector = self.app.scrollViews[
                "scholium.researchInspector"
            ].firstMatch
            let metadata = self.app.descendants(matching: .any)[
                "scholium.documentNoteName"
            ]
            return folder.exists
                && (folder.value as? String) == "Expanded"
                && currentInspector.exists
                && metadata.exists
                && (metadata.value as? String) == expectedNote
        }

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                sharedPresentationIsPreserved(expectedNote: "QA Autosave B")
            },
            "Opening a document tab must preserve Library disclosure and Apparatus presentation."
        )

        firstTab.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            sharedPresentationIsPreserved(expectedNote: "QA Autosave A")
        })

        secondTab.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            sharedPresentationIsPreserved(expectedNote: "QA Autosave B")
        })
        documentTabs.buttons["Close QA Autosave B"].click()
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                self.app.windows.firstMatch.exists
                    && !documentTabs.exists
                    && (self.app.descendants(matching: .any)[
                        "scholium.documentNoteName"
                    ].value as? String) == "QA Autosave A"
            },
            "Closing the selected page must choose its previous neighbor without closing the workspace window."
        )
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    @MainActor
    func testFileMenuOpensTheCurrentDocumentInADocumentTab() throws {
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")

        let fileMenuItem = app.menuBars.menuBarItems["File"]
        fileMenuItem.click()
        let fileMenu = fileMenuItem.menus.firstMatch
        let openInNewTab = fileMenu.menuItems["Open in New Tab"]
        XCTAssertTrue(
            openInNewTab.waitForExistence(timeout: 3),
            "The File menu must expose Open in New Tab."
        )
        XCTAssertTrue(openInNewTab.isEnabled)
        openInNewTab.click()

        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(documentTabs.waitForExistence(timeout: 8))
        let closeButtons = documentTabs.buttons.matching(
            NSPredicate(format: "label == %@", "Close QA Autosave A")
        )
        XCTAssertEqual(closeButtons.count, 2)
        closeButtons.element(boundBy: 1).click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.app.windows.firstMatch.exists
                && !documentTabs.exists
        })
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
    private func copyPreparedResearchFunctionInstructions() {
        let options = app.descendants(matching: .any)[
            "scholium.agentApplicationHandoffOptions"
        ]
        XCTAssertTrue(options.waitForExistence(timeout: 8))
        if !options.isHittable {
            scrollUntilHittable(
                options,
                in: app.descendants(matching: .any)["scholium.researchFunctionPanel.scroll"]
            )
        }
        options.click()

        let copyOnly = app.menuItems["Copy Only"].firstMatch
        XCTAssertTrue(copyOnly.waitForExistence(timeout: 5))
        copyOnly.click()
    }

    @MainActor
    private func scrollUntilHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement
    ) {
        guard !element.isHittable else { return }

        // XCUITest exposes offscreen SwiftUI list rows with their actual frame.
        // Scroll toward that frame rather than always moving down the list;
        // an unconditional upward swipe can move a near-top row offscreen.
        for _ in 0..<6 where !element.isHittable {
            if element.frame.midY < scrollView.frame.midY {
                scrollView.swipeDown()
            } else {
                scrollView.swipeUp()
            }
        }
        XCTAssertTrue(element.isHittable, "Expected the control to become visible after scrolling.")
    }

    @MainActor
    private func closeFrontmostWindow() {
        let closeButton = app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        closeButton.click()
    }

    /// The native AppKit divider exposes a sub-point accessibility frame even
    /// though its pointer target is wider. Probe a few nearby pixels so this
    /// journey exercises the same public divider interaction as a researcher
    /// instead of assuming the AX frame is the complete hit region.
    @MainActor
    private func dragNativeSplitter(
        _ splitter: XCUIElement,
        within splitGroup: XCUIElement,
        horizontalDelta: CGFloat,
        until condition: @escaping () -> Bool
    ) -> Bool {
        let splitFrame = splitGroup.frame
        let dividerFrame = splitter.frame
        guard splitFrame.width > 0, splitFrame.height > 0 else { return false }
        let dividerX = (dividerFrame.midX - splitFrame.minX) / splitFrame.width
        let dividerY = (dividerFrame.midY - splitFrame.minY) / splitFrame.height
        for offset in [CGFloat.zero, -2, 2, -4, 4] {
            // Build the pointer coordinate from the stable split-group frame.
            // XCUI's coordinate relative to a 0.5pt splitter collapses to the
            // element origin on current macOS, while the enclosing split group
            // preserves the real screen coordinate.
            let origin = splitGroup.coordinate(
                withNormalizedOffset: CGVector(dx: dividerX, dy: dividerY)
            ).withOffset(CGVector(dx: offset, dy: 0))
            origin.press(
                forDuration: 0.2,
                thenDragTo: origin.withOffset(CGVector(dx: horizontalDelta, dy: 0))
            )
            if waitUntil(timeout: 1.5, condition: condition) { return true }
        }
        return false
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func configuredApplication(
        sessionID: UUID,
        initialWorkspaceWidth: Int? = 1380,
        usesFixedSessionID: Bool = true,
        autosaveDelayMS: Int = 5_000,
        ignoresSystemWindowRestoration: Bool = true,
        appearance: QAAppearance? = nil,
        openNote: String? = "QA Autosave A.md"
    ) -> XCUIApplication {
        let application = XCUIApplication(bundleIdentifier: "com.scholium.qa")
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
        application.launchEnvironment["SCHOLIUM_CLI_INSTALL_PATH"] = testDirectory
            .appendingPathComponent("cli-bin/scholium")
            .path
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = triptychDirectory.path
        // Keep navigation assertions independent of the user's persisted note
        // sort preference. The journey deliberately starts from A, then
        // crosses to the peer Topics vault and back again.
        if let openNote {
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = openNote
        }
        if usesFixedSessionID {
            application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = sessionID.uuidString
        }
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = String(autosaveDelayMS)
        if let initialWorkspaceWidth {
            application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = String(initialWorkspaceWidth)
        }
        return application
    }

    @MainActor
    private func relaunchApplication(initialWorkspaceWidth: Int) {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: initialWorkspaceWidth)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    private func focusWorkspaceWindow(_ window: XCUIElement) {
        // Utility windows float above the workspace center. The leading title
        // bar remains unobscured and gives the native scene a real key-window
        // transition for FocusedObject propagation.
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.08, dy: 0.025)
        ).click()
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
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchFunctionResponseModules"
        ].exists)
        XCTAssertFalse(app.staticTexts["Supported modes"].exists)
        XCTAssertFalse(app.staticTexts["Required packages"].exists)
    }

    @MainActor
    private func waitForDocumentSurface() {
        let renderedDocument = app.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(waitUntil(timeout: 20) { renderedDocument.exists })
    }

    @MainActor
    @discardableResult
    private func selectResearchInspectorMode(_ mode: String) -> XCUIElement {
        let inspector = app.descendants(matching: .any)[
            "scholium.researchInspector"
        ].firstMatch
        if !inspector.exists {
            let toggle = app.descendants(matching: .any)[
                "scholium.toggleInspector"
            ].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.click()
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        let modeButton = app.buttons[
            "scholium.inspectorMode.\(mode)"
        ].firstMatch
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        modeButton.click()

        let contentIdentifier: String
        switch mode {
        case "overview": contentIdentifier = "scholium.researchStatus"
        case "connections": contentIdentifier = "scholium.connectionGroup.0"
        case "functions": contentIdentifier = "scholium.researchFunction.dialogue"
        default:
            XCTFail("Unknown Inspector mode: \(mode)")
            return inspector
        }
        XCTAssertTrue(
            app.descendants(matching: .any)[contentIdentifier]
                .waitForExistence(timeout: 8)
        )
        return inspector
    }

    @MainActor
    private func openNote(
        _ relativePath: String,
        expectedTitle: String,
        in window: XCUIElement
    ) {
        let row = window.descendants(matching: .any)["scholium.noteRow.\(relativePath)"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "The requested note must be available in the target window."
        )
        row.click()
        let metadata = window.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(
            metadata.waitForExistence(timeout: 10)
                && waitUntil(timeout: 10) { metadata.value as? String == expectedTitle },
            "The target window must finish opening the requested note."
        )
    }

    @MainActor
    private func selectVault(
        _ identifier: String,
        waitingFor rowIdentifier: String
    ) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any)[rowIdentifier]
        let deadline = Date().addingTimeInterval(20)
        repeat {
            button.click()
            if row.waitForExistence(timeout: 5) { return }
        } while Date() < deadline
        XCTFail("The selected vault did not publish its expected Library content.")
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
        _ = enterLivePreview(in: root)
        app.typeKey(.end, modifierFlags: [.command])
        app.typeText(token)
    }

    @MainActor
    private func enterLivePreview(in root: XCUIElement? = nil) -> XCUIElement {
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
        XCTAssertTrue(waitUntil(timeout: 8) { editor.isHittable })
        // The mode transition requests focus, but XCUITest must still prove
        // that the WebKit text surface is the active command target before it
        // sends editing or document-session shortcuts.
        editor.click()
        return editor
    }

    @MainActor
    private func chooseSetupFolder(_ folder: URL, role: String) {
        let openPanelButton = app.buttons["Choose \(role) folder"]
        XCTAssertTrue(openPanelButton.waitForExistence(timeout: 5))
        openPanelButton.click()

        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let folderEntry = panel.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@", folder.lastPathComponent)
        ).firstMatch
        XCTAssertTrue(folderEntry.waitForExistence(timeout: 5))
        folderEntry.click()

        let choose = panel.buttons["OKButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { choose.isEnabled })
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

        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let folderEntry = panel.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@", folder.lastPathComponent)
        ).firstMatch
        XCTAssertTrue(folderEntry.waitForExistence(timeout: 5))
        folderEntry.click()

        let authorize = panel.buttons["OKButton"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { authorize.isEnabled })
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

    private func setPasteboardText(_ text: String) throws {
        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(text.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    @MainActor
    private func paste(_ text: String, into element: XCUIElement) throws {
        try setPasteboardText(text)
        element.click()
        element.typeKey("a", modifierFlags: [.command])
        element.typeKey("v", modifierFlags: [.command])
    }

    @MainActor
    private func openResearchGuidanceSkills(openAdvanced: Bool = false) {
        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let collection = app.descendants(matching: .any)[
            "scholium.researchGuidance.collection"
        ]
        XCTAssertTrue(collection.waitForExistence(timeout: 10))
        let skills = app.radioButtons["Skills"]
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        skills.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.researchGuidance.skillList"]
                .waitForExistence(timeout: 10)
        )
        if openAdvanced {
            let advanced = app.radioButtons["Advanced"]
            XCTAssertTrue(advanced.waitForExistence(timeout: 5))
            advanced.click()
        }
    }

    private func packageRevision(_ files: [(String, String)]) -> (String, Int) {
        var bytes = Data()
        for (path, source) in files.sorted(by: { $0.0 < $1.0 }) {
            let sourceData = Data(source.utf8)
            bytes.append(Data(path.utf8))
            bytes.append(0)
            bytes.append(Data(String(sourceData.count).utf8))
            bytes.append(0)
            bytes.append(sourceData)
            bytes.append(0)
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return (digest, bytes.count)
    }

    private func maintenanceEvidence(revision: (String, Int)) throws -> String {
        let payload: [String: Any] = [
            "proposedPackageRevision": [
                "sha256": revision.0,
                "byteCount": revision.1,
            ],
            "evaluator": "Synthetic UI transport fixture",
            "method": "Structural, boundary, and rollback gating only",
            "status": "passed",
            "cases": [[
                "id": "synthetic-transport-gate",
                "status": "passed",
                "summary": "Fixture evidence exercises transport and gating; it makes no philosophical-quality claim.",
            ]],
            "evaluatedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        return String(
            decoding: try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            ),
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
        // approved static TestVaults root. Every journey clones that test-owned
        // copy and uses its existing QA Autosave A/B, QA Topic, and QA Work
        // anchors. Only state-specific records absent from the static fixture
        // may be added below. No UI test opens or mutates Desktop/TestVaults.
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

        for staticAnchor in [
            analyses.appendingPathComponent("QA Autosave A.md"),
            analyses.appendingPathComponent("QA Autosave B.md"),
            topics.appendingPathComponent("QA Topic.md"),
            works.appendingPathComponent("QA Work.md"),
        ] where !FileManager.default.fileExists(atPath: staticAnchor.path) {
            throw XCTSkip("The static TestVault anchor is missing: \(staticAnchor.lastPathComponent)")
        }
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

    /// Samples only the app and WebKit service PIDs attributed to this exact
    /// process while the retained CodeMirror surface changes presentation.
    /// The shell runner fixes the release journey at 50 transitions; a smaller
    /// count is accepted here only so the focused harness can be exercised
    /// without impersonating retained acceptance evidence.
    @MainActor
    func testRDF1EditorRetainedMemory() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_PERFORMANCE_MEMORY_PROGRESS_PATH"] != nil else {
            throw XCTSkip("The attributed Editor memory driver is not configured.")
        }
        let applicationPath = try required("SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH", in: environment)
        let fixtureRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT", in: environment)
        let homeRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT", in: environment)
        let runID = try required("SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID", in: environment)
        let progressPath = try required("SCHOLIUM_PERFORMANCE_MEMORY_PROGRESS_PATH", in: environment)
        let acknowledgmentPath = try required(
            "SCHOLIUM_PERFORMANCE_MEMORY_ACKNOWLEDGMENT_PATH",
            in: environment
        )
        let transitions = try positive("SCHOLIUM_PERFORMANCE_MEMORY_TRANSITIONS", in: environment)
        XCTAssertLessThanOrEqual(transitions, 50)

        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--scholium-performance-editor-mode-notifications",
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = "memory-\(runID)"
        application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = "1380"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Long/Canonical-5000-Word-Work.md"
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = "300000"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = progressPath
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] = "editor_retained_memory"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = "0"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = String(transitions + 1)
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] =
            "Long/Canonical-5000-Word-Work.md"
        defer { application.terminate() }

        application.launch()
        XCTAssertTrue(
            application.windows.firstMatch.waitForExistence(timeout: 30),
            "The retained-memory app window did not appear."
        )
        let modeMenu = application.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 30))
        selectEditorMode(
            "Live Preview",
            accessibilityLabel: "Markdown live preview editor",
            modeMenu: modeMenu,
            application: application,
            documentID: "Long/Canonical-5000-Word-Work.md"
        )
        Thread.sleep(forTimeInterval: 0.5)
        waitForMemoryAcknowledgment(
            index: 0,
            acknowledgmentPath: acknowledgmentPath
        )

        for transition in 1...transitions {
            let sourceMode = transition.isMultiple(of: 2) == false
            selectEditorMode(
                sourceMode ? "Source" : "Live Preview",
                accessibilityLabel: sourceMode
                    ? "Markdown source editor"
                    : "Markdown live preview editor",
                modeMenu: modeMenu,
                application: application,
                documentID: "Long/Canonical-5000-Word-Work.md"
            )
            _ = XCUIScreen.main.screenshot()
            Thread.sleep(forTimeInterval: 0.1)
            waitForMemoryAcknowledgment(
                index: transition,
                acknowledgmentPath: acknowledgmentPath
            )
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
        application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = "1380"
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
        if metric == .warmReadActivation {
            try prepareWarmReadLibraryTargets(in: application)
            return
        }
        application.typeKey("f", modifierFlags: [.command])
        let field = application.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        replaceCommittedText("scopeSetup", in: field, application: application)
        let thisVault = application.radioButtons["This Vault"]
        XCTAssertTrue(thisVault.waitForExistence(timeout: 5))
        thisVault.click()
        clearSearchField(field, application: application)
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
            let recordPublished = waitUntil(timeout: 30) {
                self.lineCount(at: resultsPath) == sample + 1
            }
            if !recordPublished {
                attachPerformanceFailureState(
                    named: "indexed-search-sample-\(sample)",
                    application: application
                )
            }
            XCTAssertTrue(
                recordPublished,
                "Sample \(sample): Search did not publish exactly one performance record."
            )
            clearSearchField(field, application: application)
            if sample + 1 == total {
                let close = application.buttons["scholium.closeSearchButton"]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                close.click()
            }
        case .warmReadActivation:
            let target = application.descendants(matching: .any)[
                "scholium.noteRow.Cluster-00/analysis-note-001.md"
            ]
            XCTAssertTrue(target.waitForExistence(timeout: 15))
            XCTAssertTrue(target.isHittable, "Sample \(sample): the warm Read Library target is not hittable.")
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
                let alternate = application.descendants(matching: .any)[
                    "scholium.noteRow.Cluster-01/analysis-note-002.md"
                ]
                XCTAssertTrue(alternate.waitForExistence(timeout: 15))
                XCTAssertTrue(
                    alternate.isHittable,
                    "Sample \(sample): the alternate warm Read Library target is not hittable."
                )
                alternate.click()
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
    private func prepareWarmReadLibraryTargets(in application: XCUIApplication) throws {
        for folder in ["Cluster-00", "Cluster-01"] {
            let row = application.descendants(matching: .any)["scholium.folderRow.\(folder)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            if (row.value as? String) != "Expanded" {
                row.click()
            }
        }
        XCTAssertTrue(
            application.descendants(matching: .any)[
                "scholium.noteRow.Cluster-00/analysis-note-001.md"
            ].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            application.descendants(matching: .any)[
                "scholium.noteRow.Cluster-01/analysis-note-002.md"
            ].waitForExistence(timeout: 10)
        )
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

    @MainActor
    private func selectEditorMode(
        _ title: String,
        accessibilityLabel: String,
        modeMenu: XCUIElement,
        application: XCUIApplication,
        documentID: String
    ) {
        let notificationName = title == "Live Preview"
            ? "com.scholium.qa.performance-editor-mode.live-preview"
            : "com.scholium.qa.performance-editor-mode.source"
        let deadline = Date().addingTimeInterval(20)
        repeat {
            XCTAssertEqual(
                notify_post(notificationName),
                UInt32(NOTIFY_STATUS_OK),
                "The QA Editor mode request could not be posted."
            )
            if waitUntil(timeout: 1.5, condition: {
                (modeMenu.value as? String) == title
                    && application.descendants(matching: .any)[accessibilityLabel].exists
            }) {
                return
            }
        } while Date() < deadline
        XCTFail(
            "The \(title) editor surface for \(documentID) did not become accessible."
        )
    }

    private func waitForMemoryAcknowledgment(
        index: Int,
        acknowledgmentPath: String
    ) {
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                self.lineCount(at: acknowledgmentPath) == index + 1
            },
            "The external process-memory sampler did not acknowledge sample \(index)."
        )
    }

    @MainActor
    private func replaceCommittedText(
        _ text: String,
        in field: XCUIElement,
        application: XCUIApplication
    ) {
        clearSearchField(field, application: application)
        field.click()
        var pendingLetters = ""
        for character in text {
            if character.isNumber {
                if !pendingLetters.isEmpty {
                    field.typeText(pendingLetters)
                    application.typeKey(.return, modifierFlags: [])
                    pendingLetters = ""
                    field.click()
                }
                field.typeKey(String(character), modifierFlags: [])
            } else {
                pendingLetters.append(character)
            }
        }
        if !pendingLetters.isEmpty {
            field.typeText(pendingLetters)
        }
        application.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(
            field.value as? String,
            text,
            "The fixed performance query was not committed exactly."
        )
    }

    @MainActor
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

    @MainActor
    private func attachPerformanceFailureState(
        named name: String,
        application: XCUIApplication
    ) {
        let screenshot = XCTAttachment(screenshot: application.screenshot())
        screenshot.name = "\(name)-screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(
            data: Data(application.debugDescription.utf8),
            uniformTypeIdentifier: "public.plain-text"
        )
        hierarchy.name = "\(name)-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return condition()
    }
}

/// External, read-only launch driver for the release-to-release Triptych
/// integrity gate. `verify-qa-upgrade-safety.sh` owns fixture copying, exact
/// manifests, process serialization, and evidence retention.
final class ScholiumUpgradeSafetyUITests: XCTestCase {
    @MainActor
    func testReadOnlyLaunch() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_UPGRADE_DRIVER_APP_PATH"] != nil else {
            throw XCTSkip("The external upgrade-safety driver is not configured.")
        }

        let applicationPath = try required("SCHOLIUM_UPGRADE_DRIVER_APP_PATH", in: environment)
        let fixtureRoot = try required("SCHOLIUM_UPGRADE_DRIVER_FIXTURE_ROOT", in: environment)
        let homeRoot = try required("SCHOLIUM_UPGRADE_DRIVER_HOME_ROOT", in: environment)
        let label = try required("SCHOLIUM_UPGRADE_DRIVER_LABEL", in: environment)
        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = "upgrade-safety-\(label)"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "paper_analysis"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Upgrade Safety/Launch Probe.md"
        application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = "1080"

        defer { application.terminate() }
        application.launch()
        XCTAssertTrue(
            application.windows.firstMatch.waitForExistence(timeout: 30),
            "The \(label) app window did not appear."
        )
        XCTAssertTrue(
            application.descendants(matching: .any)["scholium.librarySurface"]
                .waitForExistence(timeout: 30),
            "The \(label) Library did not become available."
        )
        XCTAssertTrue(
            application.descendants(matching: .any)[
                "scholium.renderedDocument.Upgrade Safety/Launch Probe.md"
            ].waitForExistence(timeout: 30),
            "The \(label) read-only launch probe did not render."
        )

        let screenshot = XCTAttachment(screenshot: application.windows.firstMatch.screenshot())
        screenshot.name = "\(label)-read-only-launch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func required(_ key: String, in environment: [String: String]) throws -> String {
        let value = try XCTUnwrap(environment[key], "Missing \(key).")
        return try XCTUnwrap(value.isEmpty ? nil : value, "Empty \(key).")
    }
}
