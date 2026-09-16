import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testAgentChangesShowsExactUpdateAndRestoresSettledBytes() throws {
        let noteURL =
            triptychDirectory
            .appendingPathComponent("02-topics", isDirectory: true)
            .appendingPathComponent("Agent Review.md")
        let originalBytes = try Data(contentsOf: noteURL)

        var settle = app.toolbars.buttons["Settle"].firstMatch
        XCTAssertTrue(settle.waitForExistence(timeout: 10))
        XCTAssertEqual(settle.label, "Settle")
        settle.click()
        let settlePopover = app.popovers.firstMatch
        XCTAssertTrue(settlePopover.waitForExistence(timeout: 5))
        let confirmSettle = settlePopover.buttons["Settle"].firstMatch
        XCTAssertTrue(confirmSettle.waitForExistence(timeout: 5))
        confirmSettle.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                settle =
                    self.app.toolbars.buttons.matching(
                        NSPredicate(format: "label CONTAINS %@", "Settle Again")
                    ).firstMatch
                return settle.exists
            })

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
        let updatedBody = """
            # Agent Review

            Reasons can guide action without settling every question about value.

            An external Agent added this synthetic sentence for exact comparison.
            """
        _ = try callQAMCP(
            tool: "scholium_update_note",
            arguments: [
                "triptych_id": triptychID,
                "note_id": noteID,
                "expected_fingerprint": fingerprint,
                "mode": "body",
                "content": updatedBody,
            ]
        )

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                settle.label.contains("Changed since settlement")
            })
        XCTAssertTrue(settle.label.contains("Settle Again"))

        let notifications = app.toolbars.buttons["Open Triptych Notifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        notifications.click()
        let notificationPopover = app.popovers.firstMatch
        XCTAssertTrue(notificationPopover.waitForExistence(timeout: 5))
        let agentChange = notificationPopover.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.notification.agentChange."
            )
        ).firstMatch
        XCTAssertTrue(
            agentChange.waitForExistence(timeout: 10),
            "The confirmed external update must appear in Triptych Notifications."
        )
        agentChange.click()
        let comparison = app.descendants(matching: .any)["scholium.agentChanges"]
            .firstMatch
        XCTAssertTrue(comparison.waitForExistence(timeout: 10))
        for text in [
            "Current Revision",
            "Before",
            "After",
        ] {
            XCTAssertTrue(
                comparison.staticTexts[text].firstMatch.waitForExistence(timeout: 5),
                "Agent Changes did not expose \(text)."
            )
        }
        let changeRows = comparison.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.agentChanges.row.")
        )
        XCTAssertTrue(
            changeRows.matching(
                NSPredicate(format: "label == %@", "Inserted")
            ).firstMatch.exists)
        let beforeUndo = XCTAttachment(screenshot: app.screenshot())
        beforeUndo.name = "Agent Changes exact Before and After"
        beforeUndo.lifetime = .keepAlways
        add(beforeUndo)

        let undo = comparison.buttons["Undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertTrue(undo.isEnabled)
        undo.click()
        let confirmation = app.sheets.matching(
            NSPredicate(format: "label == %@", "alert")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        let restore = confirmation.buttons["Restore Before Version"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.click()
        XCTAssertTrue(
            comparison.staticTexts["Earlier Revision"].firstMatch
                .waitForExistence(timeout: 10))
        XCTAssertTrue(comparison.staticTexts["This update was undone."].firstMatch.exists)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)

        comparison.buttons["Close"].firstMatch.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                settle.label.contains("Settled — Settle Again")
            })
        XCTAssertTrue(settle.label.contains("Settle Again"))
        let afterUndo = XCTAttachment(screenshot: app.screenshot())
        afterUndo.name = "Settlement retained after exact Agent Undo"
        afterUndo.lifetime = .keepAlways
        add(afterUndo)
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
    func testInspectorLinksSelectIncomingAndOutgoingDirections() {
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
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(
            sourceEditor.waitForExistence(timeout: 10),
            "The selected Search result did not finish revealing its source range."
        )
        let mode = documentModeControl()
        XCTAssertEqual(documentModeState(mode), "Source")
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
