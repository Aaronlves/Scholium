@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
    @MainActor
    func testLivePreviewHidesYAMLAndSourceShortcutIsUnavailable() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)

        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertEqual(mode.value as? String, "Edit", "Source must be entered through the document-mode menu")

        selectDocumentMode("Source")
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
        XCTAssertTrue(waitUntil(timeout: 15) {
            editingWindow.staticTexts["scholium.documentNoteName"].value as? String
                == "QA Autosave B"
        })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                let titles = self.app.windows.allElementsBoundByIndex.compactMap { window -> String? in
                    let metadata = window.descendants(matching: .any)[
                        "scholium.documentNoteName"
                    ].firstMatch
                    guard metadata.exists else { return nil }
                    return metadata.value as? String
                }
                return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
            },
            "The observing window must retain its own selection after the peer window navigates."
        )
        let observingWindow = try XCTUnwrap(app.windows.allElementsBoundByIndex.first { window in
            window.descendants(matching: .any)["scholium.documentNoteName"].value as? String
                == "QA Autosave A"
        })

        let committedToken = token.trimmingCharacters(in: .whitespaces)
        let peerProjection = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@",
                committedToken,
                committedToken
            )
        ).firstMatch
        XCTAssertTrue(
            peerProjection.waitForExistence(timeout: 20),
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
        XCTAssertTrue(waitUntil(timeout: 15) {
            peerWindow.staticTexts["scholium.documentNoteName"].value as? String
                == "QA Autosave B"
        })
        XCTAssertTrue(waitUntil(timeout: 20) {
            (try? self.source(at: noteURL).contains(peerToken)) == true
        })
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        let compare = dirtyWindow.buttons["Compare Changes"]
        XCTAssertTrue(
            compare.waitForExistence(timeout: 12),
            "A peer commit must become a persistent conflict in a dirty independent window."
        )
        let dirtyEditor = dirtyWindow.descendants(matching: .any)["Markdown editor, Edit mode"]
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
        focusWorkspaceWindow(firstWindow)
        app.typeKey("f", modifierFlags: [.command, .shift])
        let firstSearch = firstWindow.descendants(matching: .any)["scholium.searchWorkspace"]
        let secondSearch = secondWindow.descendants(matching: .any)["scholium.searchWorkspace"]
        XCTAssertTrue(firstSearch.waitForExistence(timeout: 5))
        XCTAssertFalse(secondSearch.exists)
        firstWindow.descendants(matching: .any)["scholium.closeSearchButton"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !firstSearch.exists })

        focusWorkspaceWindow(secondWindow)
        app.typeKey("f", modifierFlags: [.command, .shift])
        XCTAssertTrue(secondSearch.waitForExistence(timeout: 5))
        XCTAssertFalse(firstSearch.exists)
        secondWindow.descendants(matching: .any)["scholium.closeSearchButton"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !secondSearch.exists })
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

        let secondMode = secondWindow.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(secondMode.waitForExistence(timeout: 5))
        selectDocumentMode("Edit", in: secondWindow)
        XCTAssertTrue(waitUntil(timeout: 8) { secondMode.value as? String == "Edit" })

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
            let titles = self.app.windows.allElementsBoundByIndex.compactMap { window -> String? in
                let metadata = window.descendants(matching: .any)[
                    "scholium.documentNoteName"
                ].firstMatch
                guard metadata.exists else { return nil }
                return metadata.value as? String
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
            restoredA.descendants(matching: .any)["scholium.documentModeButton"].value as? String,
            "Review"
        )
        let restoredBMode = restoredB.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(waitUntil(timeout: 10) { restoredBMode.value as? String == "Edit" })

        XCTAssertEqual(app.windows.count, 2)
        XCTAssertFalse(restoredA.descendants(matching: .any)["scholium.documentTabs"].exists)
        XCTAssertFalse(restoredB.descendants(matching: .any)["scholium.documentTabs"].exists)
    }

    @MainActor
    func testSidebarWorkspaceLibraryAndTriptychAttentionWindowJourney() throws {
        app.terminate()
        synthesisAttentionFixture = try seedSynthesisAttentionFixture()
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth),
            usesFixtureWorkspace: false,
            appearance: .light
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForDocumentSurface()
        let documentTitle = app.descendants(matching: .any)[
            "scholium.documentNoteName"
        ].firstMatch
        XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")

        let topics = app.buttons["scholium.vault.topic_knowledge"].firstMatch
        let analyses = app.buttons["scholium.vault.paper_analysis"].firstMatch
        XCTAssertTrue(topics.waitForExistence(timeout: 5))
        topics.click()
        XCTAssertFalse(
            NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: topics),
            "Pointer workspace selection must not leave a keyboard-only focus ring."
        )
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.noteRow.QA Topic.md"
        ].waitForExistence(timeout: 8))
        let noDocumentState = app.descendants(matching: .any)[
            "scholium.noDocumentState"
        ]
        XCTAssertTrue(noDocumentState.waitForExistence(timeout: 5))

        analyses.click()
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(documentTitle.value as? String, "QA Autosave A")
        let folder = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ]
        let noteList = app.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        let noteListViewport = app.scrollViews.containing(
            .outline,
            identifier: "scholium.noteList"
        ).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 8))
        XCTAssertTrue(noteList.waitForExistence(timeout: 5))
        XCTAssertTrue(noteListViewport.waitForExistence(timeout: 5))
        XCTAssertEqual(
            noteListViewport.frame.width,
            QAWorkspaceMetricContract.libraryMinimumReadableWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance
        )
        folder.click()
        noteListViewport.swipeUp(velocity: .slow)
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            abs(folder.frame.minY - noteListViewport.frame.minY),
            30,
            "Folder rows must scroll with the native hierarchy rather than becoming sticky sections."
        )

        topics.click()
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.noteRow.QA Topic.md"
        ].waitForExistence(timeout: 8))
        let attentionButton = app.descendants(matching: .any)[
            "scholium.triptychAttention"
        ]
        XCTAssertTrue(attentionButton.waitForExistence(timeout: 5))
        attentionButton.click()

        let attentionPopover = app.popovers.firstMatch
        XCTAssertTrue(attentionPopover.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(attentionPopover.frame.width, 360)
        XCTAssertGreaterThanOrEqual(attentionPopover.frame.height, 320)
        let kindPicker = attentionPopover.descendants(matching: .any)[
            "scholium.attentionKindFilter"
        ].firstMatch
        XCTAssertTrue(kindPicker.waitForExistence(timeout: 5))
        kindPicker.click()
        let materialChanged = app.menuItems["Material Changed Since Use"].firstMatch
        XCTAssertTrue(materialChanged.waitForExistence(timeout: 3))
        materialChanged.click()
        let attentionItem = attentionPopover.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.attentionItem."
            )
        ).firstMatch
        XCTAssertTrue(attentionItem.waitForExistence(timeout: 10))
        attentionItem.click()
        // The native Outline exposes each Section header as the first disabled
        // row; the task itself is the next row and owns selection.
        let selectedRow = attentionPopover.outlineRows.element(boundBy: 1)
        XCTAssertTrue(selectedRow.isSelected)
        let inspect = attentionPopover.buttons["Inspect"].firstMatch
        XCTAssertTrue(inspect.waitForExistence(timeout: 5))
        inspect.click()

        XCTAssertTrue(waitUntil(timeout: 5) { !attentionPopover.exists })
        XCTAssertTrue(waitUntil(timeout: 8) {
            (documentTitle.value as? String) == "QA Autosave A"
        })
        app.menuBars.menuBarItems["Window"].click()
        let attentionMenuItem = app.menuItems["Attention"].firstMatch
        XCTAssertTrue(attentionMenuItem.waitForExistence(timeout: 3))
        attentionMenuItem.click()
        XCTAssertTrue(attentionPopover.waitForExistence(timeout: 5))
        let reopenedItem = attentionPopover.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.attentionItem."
            )
        ).firstMatch
        XCTAssertTrue(reopenedItem.waitForExistence(timeout: 5))

        let evidence = XCTAttachment(screenshot: app.screenshot())
        evidence.name = "Sidebar clean cutover and transient Attention popover"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testCommittedWindowModeRestoresAfterRelaunch() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")
        XCTAssertTrue(waitUntil(timeout: 5) { mode.value as? String == "Edit" })

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

        let restoredMode = app.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(restoredMode.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                restoredMode.value as? String == "Edit"
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
    func testActionsExposeSettleWithoutAReviewModel() throws {
        selectResearchInspectorMode("actions")
        XCTAssertFalse(app.descendants(matching: .any)["scholium.openReview"].exists)
        XCTAssertFalse(app.buttons["Complete Review"].exists)
        XCTAssertFalse(app.textViews["Review Note"].exists)

        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].waitForExistence(timeout: 5))
        let settle = app.descendants(matching: .any)["scholium.researchAction.settle"]
        XCTAssertTrue(settle.exists)
        XCTAssertTrue(settle.isEnabled)
    }

    @MainActor
    func testOverviewRoutesZoteroOnlyFromCurrentAnalysis() throws {
        _ = selectResearchInspectorMode("overview")
        let openInZotero = app.descendants(matching: .any)[
            "scholium.researchOverview.openInZotero"
        ]
        XCTAssertTrue(openInZotero.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["QAITEM01"].exists)
        XCTAssertFalse(app.buttons["Open PDF in Preview"].exists)
        XCTAssertFalse(app.buttons["Open Attachment"].exists)

        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        let topicRow = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"]
        topicRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !openInZotero.exists })

        selectVault(
            "scholium.vault.output",
            waitingFor: "scholium.noteRow.QA Work.md"
        )
        let workRow = app.descendants(matching: .any)["scholium.noteRow.QA Work.md"]
        workRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !openInZotero.exists })

        selectVault(
            "scholium.vault.paper_analysis",
            waitingFor: "scholium.noteRow.QA Autosave A.md"
        )
        let analysisRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave A.md"
        ]
        analysisRow.click()
        XCTAssertTrue(openInZotero.waitForExistence(timeout: 8))
    }

}
