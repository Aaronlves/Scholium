@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
    @MainActor
    func testDirtyLivePreviewSearchesThisNoteWithoutSaving() throws {
        let token = " searchunsavedtoken"
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(token)
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("f", modifierFlags: [.command])
        let search = app.descendants(matching: .any)["scholium.searchWorkspace"]
        let field = app.descendants(matching: .any)["scholium.searchField"]
        let result = app.descendants(matching: .any)["scholium.searchResult.QA Autosave A.md"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        typeCommittedText("searchunsavedtoken", into: field, in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.descendants(matching: .any)["scholium.closeSearchButton"].click()
        XCTAssertTrue(waitUntil(timeout: 3) { !search.exists })
        XCTAssertFalse(try source(at: noteURL).contains(token))
    }

    @MainActor
    func testPendingAutosaveSurvivesInspectorViewReconstruction() throws {
        app.terminate()
        app = configuredApplication(
            sessionID: sessionID,
            autosaveDelayMS: 4_000
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
        XCTAssertTrue(waitUntil(timeout: 15) {
            (self.app.staticTexts["scholium.documentNoteName"].value as? String) == "QA Autosave B"
        })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })
        XCTAssertFalse(try source(at: secondURL).contains(token))
    }

    @MainActor
    func testDocumentModeAndLibrarySwitchHandoffsStayBoundedWithoutSourceExposure() throws {
        let mode = app.descendants(matching: .any)["scholium.documentModeButton"]
        let rendered = app.descendants(matching: .any)["Rendered Markdown"]
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
        let title = app.staticTexts["scholium.documentNoteName"]
        let firstURL = triptychDirectory.appendingPathComponent(
            "01-analyses/QA Autosave A.md"
        )
        let secondURL = triptychDirectory.appendingPathComponent(
            "01-analyses/QA Autosave B.md"
        )
        let firstSource = try Data(contentsOf: firstURL)
        let secondSource = try Data(contentsOf: secondURL)

        func selectMode(_ title: String) {
            selectDocumentMode(title)
        }

        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectMode("Source")
        XCTAssertTrue(sourceEditor.waitForExistence(timeout: 8))
        selectMode("Review")
        XCTAssertTrue(rendered.waitForExistence(timeout: 8))
        XCTAssertFalse(sourceEditor.exists)

        let reviewToEditStart = DispatchTime.now().uptimeNanoseconds
        selectMode("Edit")
        let editDeadline = Date().addingTimeInterval(8)
        var sourceExposureSamples = 0
        while Date() < editDeadline, !(editor.exists && editor.isHittable) {
            if sourceEditor.exists && sourceEditor.isHittable {
                sourceExposureSamples += 1
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let reviewToEditMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - reviewToEditStart
        ) / 1_000_000
        XCTAssertTrue(editor.exists && editor.isHittable)
        XCTAssertEqual(
            sourceExposureSamples,
            0,
            "Review must remain the visible handoff surface until Edit is bridge-acknowledged."
        )
        XCTAssertFalse(sourceEditor.exists)

        let editToReviewStart = DispatchTime.now().uptimeNanoseconds
        selectMode("Review")
        XCTAssertTrue(rendered.waitForExistence(timeout: 8))
        let editToReviewMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - editToReviewStart
        ) / 1_000_000

        selectMode("Edit")
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let secondRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave B.md"
        ]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        let firstToSecondStart = DispatchTime.now().uptimeNanoseconds
        secondRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            title.value as? String == "QA Autosave B"
                && self.app.descendants(matching: .any)[
                    "scholium.renderedDocument.QA Autosave B.md"
                ].exists
        })
        let firstToSecondMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - firstToSecondStart
        ) / 1_000_000

        let firstRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave A.md"
        ]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        let secondToFirstStart = DispatchTime.now().uptimeNanoseconds
        firstRow.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            title.value as? String == "QA Autosave A"
                && editor.exists
        })
        let secondToFirstMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - secondToFirstStart
        ) / 1_000_000

        XCTAssertEqual(try Data(contentsOf: firstURL), firstSource)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondSource)
        let evidence = XCTAttachment(string: """
        Debug/QA scenario observation (not the packaged Release performance gate):
        Review to Edit: \(reviewToEditMilliseconds) ms
        Edit to Review: \(editToReviewMilliseconds) ms
        Edit A to Review B through Library: \(firstToSecondMilliseconds) ms
        Review B to restored Edit A through Library: \(secondToFirstMilliseconds) ms
        Hittable Source samples during Review to Edit: \(sourceExposureSamples)
        """)
        evidence.name = "Document mode and Library handoff timings"
        evidence.lifetime = .keepAlways
        add(evidence)
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
        selectResearchInspectorMode("actions")
        let actionsMode = app.buttons[
            "scholium.inspectorMode.actions"
        ].firstMatch
        XCTAssertTrue(actionsMode.isSelected)
        secondRow.click()
        XCTAssertTrue(actionsMode.isSelected)

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

        // Actions require a resolved stable Target. Keep the selected
        // Inspector mode, but expose no incorrect launcher while identity
        // confirmation is pending.
        XCTAssertTrue(actionsMode.isSelected)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].exists)

        chooseIdentity.click()
        let firstCandidate = app.radioButtons["Use the note identity previously at \(firstPath)"]
        let secondCandidate = app.radioButtons["Use the note identity previously at \(secondPath)"]
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: 5))
        XCTAssertTrue(secondCandidate.exists)
        firstCandidate.click()
        app.buttons["Confirm Identity"].click()

        XCTAssertTrue(waitUntil(timeout: 12) { !chooseIdentity.exists })
        XCTAssertTrue(actionsMode.isSelected)
        let discuss = app.descendants(matching: .any)["scholium.researchAction.discuss"]
        let fidelity = app.descendants(matching: .any)["scholium.researchAction.check-fidelity"]
        let write = app.descendants(matching: .any)["scholium.researchAction.write"]
        let critique = app.descendants(matching: .any)["scholium.researchAction.critique"]
        XCTAssertTrue(discuss.exists)
        XCTAssertTrue(fidelity.exists)
        XCTAssertFalse(write.exists)
        XCTAssertFalse(critique.exists)
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
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
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
        let savedSource = try source(at: renamedURL)
        XCTAssertEqual(
            savedSource.components(separatedBy: localToken).count,
            2,
            "The dirty token must be committed exactly once after identity rebinding."
        )
        XCTAssertEqual(
            savedSource.replacingOccurrences(of: localToken, with: ""),
            originalSource,
            "Identity rebinding may change the insertion position chosen by Live Preview, but no pre-existing Markdown byte may change."
        )
    }

    @MainActor
    func testDirtyExternalEditPreservesTheBufferAndPresentsConflictRecovery() throws {
        let localToken = " LOCAL-\(UUID().uuidString)"
        let diskToken = "## External Disk Revision — "
            + String(repeating: "synthetic exact-source soft-wrap probe ", count: 18)
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndAppend(localToken)

        var externalDisk = try source(at: noteURL)
        let frontmatterEnd = try XCTUnwrap(externalDisk.range(of: "\n---\n"))
        externalDisk.insert(contentsOf: "\n\(diskToken)\n", at: frontmatterEnd.upperBound)
        try write(externalDisk, to: noteURL)

        let conflictWindow = app.windows.firstMatch
        let compare = conflictWindow.buttons["Compare Changes"]
        let reload = conflictWindow.buttons["Reload from Disk"]
        let keepEditing = conflictWindow.buttons["Keep Editing"]
        XCTAssertTrue(
            compare.waitForExistence(timeout: 12),
            "A dirty buffer and external edit must produce a persistent conflict decision."
        )
        let conflictStatus = conflictWindow.descendants(matching: .any)[
            "scholium.documentStatus.conflict"
        ]
        XCTAssertTrue(conflictStatus.exists)
        XCTAssertTrue(accessibilityText(of: conflictStatus).contains("Autosave Paused"))
        XCTAssertLessThanOrEqual(
            abs(compare.frame.midY - conflictStatus.frame.midY),
            1,
            "The conflict action must be vertically centered in the status toast."
        )
        XCTAssertFalse(reload.exists)
        XCTAssertFalse(keepEditing.exists)
        XCTAssertTrue(try source(at: noteURL).contains(diskToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))

        compare.click()
        let comparison = app.descendants(matching: .any)["scholium.conflictComparison"]
        XCTAssertTrue(comparison.waitForExistence(timeout: 5))
        let comparisonSheet = conflictWindow.sheets.firstMatch
        XCTAssertTrue(comparisonSheet.exists)
        XCTAssertGreaterThanOrEqual(
            comparisonSheet.frame.width,
            760,
            "Conflict comparison must retain a readable text width instead of collapsing to its controls."
        )
        let readableDiffLine = app.staticTexts["title: QA Autosave A"].firstMatch
        XCTAssertTrue(
            readableDiffLine.waitForExistence(timeout: 3),
            "The comparison must expose an intact representative source line."
        )
        XCTAssertGreaterThan(
            readableDiffLine.frame.width,
            100,
            "A source line must not collapse into a character-wide column."
        )
        let diskOnlyRows = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.conflict.row.diskOnly."
            )
        ).allElementsBoundByIndex
        let wrappedDiffLine = try XCTUnwrap(
            diskOnlyRows.max(by: { $0.frame.height < $1.frame.height }),
            "The comparison must expose the synthetic disk-only source row."
        )
        XCTAssertGreaterThan(
            wrappedDiffLine.frame.height,
            readableDiffLine.frame.height * 1.5,
            "A long logical source line must soft-wrap instead of requiring horizontal reading scroll."
        )
        XCTAssertLessThanOrEqual(
            wrappedDiffLine.frame.width,
            comparisonSheet.frame.width,
            "A soft-wrapped diff row must stay within the comparison sheet."
        )
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

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
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

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 12))
        XCTAssertTrue(
            waitUntil(timeout: 12) { (editor.value as? String ?? "").contains(token) },
            "Recovery must restore the accepted dirty buffer rather than rereading disk."
        )
        XCTAssertFalse(try source(at: noteURL).contains(token))

        app.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                (try? self.source(at: noteURL).contains(token)) == true
            },
            "The recovered dirty buffer must remain eligible for the normal fingerprint-gated flush."
        )
        let committedSource = try source(at: noteURL)
        XCTAssertEqual(committedSource.components(separatedBy: token).count, 2)
        XCTAssertEqual(
            committedSource.replacingOccurrences(of: token, with: ""),
            originalSource,
            "Recovery may preserve Live Preview's visual-end insertion before footnote definitions, but no pre-existing Markdown byte may change."
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

        // This relaunch intentionally changes the initial document. A fresh
        // window-session identity prevents the preceding setUp launch's
        // restored QA Autosave A selection from correctly taking precedence
        // over what is only a first-launch test input.
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            autosaveDelayMS: 300_000,
            openNote: "QA 100k CJK.md"
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))

        let mode = app.descendants(matching: .any)["scholium.documentModeButton"]
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        selectDocumentMode("Edit")

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
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
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (editor.value as? String ?? "").contains(endToken)
            },
            "The 100k editor must accept the complete end token before the save transition."
        )
        XCTAssertEqual(try Data(contentsOf: noteURL), Data(source.utf8))

        let saveTransitionStarted = DispatchTime.now().uptimeNanoseconds
        selectDocumentMode("Review")
        XCTAssertTrue(app.descendants(matching: .any)["Rendered Markdown"].waitForExistence(timeout: 180))
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                (try? self.source(at: noteURL).contains(endToken)) == true
            },
            "The Read transition must not complete its acceptance journey before the exact editor buffer reaches disk."
        )
        let committedSource = try self.source(at: noteURL)
        XCTAssertEqual(committedSource.components(separatedBy: endToken).count, 2)
        XCTAssertEqual(
            committedSource.replacingOccurrences(of: endToken, with: ""),
            source,
            "The 100k save may place the visual-end token before footnote definitions, but every pre-existing Markdown byte must remain exact."
        )
        let saveTransitionMilliseconds = Double(
            DispatchTime.now().uptimeNanoseconds - saveTransitionStarted
        ) / 1_000_000
        let evidence = XCTAttachment(
            string: "100,000-CJK-character dirty Live Preview reached byte-exact committed Read mode in \(saveTransitionMilliseconds) ms under the QA automation boundary."
        )
        evidence.name = "100k CJK byte-exact save transition observation"
        evidence.lifetime = .keepAlways
        add(evidence)

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 15))
        selectDocumentMode("Edit")
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        let reopenedSource = try self.source(at: noteURL)
        XCTAssertEqual(reopenedSource.components(separatedBy: endToken).count, 2)
        XCTAssertEqual(reopenedSource.replacingOccurrences(of: endToken, with: ""), source)
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
            "scholium.folderRow.Cluster-01"
        ]
        let noteList = app.scrollViews["scholium.noteList"].firstMatch
        for _ in 0..<8 where !sharedFolder.exists {
            noteList.swipeUp(velocity: .slow)
        }
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
    func testFileMenuDoesNotOfferDuplicateCurrentDocumentTab() throws {
        let metadata = app.descendants(matching: .any)["scholium.documentNoteName"]
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")

        let fileMenuItem = app.menuBars.menuBarItems["File"]
        fileMenuItem.click()
        let fileMenu = fileMenuItem.menus.firstMatch
        let openInNewTab = fileMenu.menuItems["Open in New Tab"]
        XCTAssertFalse(
            openInNewTab.exists,
            "The current document cannot be duplicated through the File menu."
        )
        app.typeKey(.escape, modifierFlags: [])

        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertFalse(documentTabs.exists)
        XCTAssertTrue(app.windows.firstMatch.exists)
        XCTAssertEqual(metadata.value as? String, "QA Autosave A")
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
        let conflictStatus = conflictWindow.descendants(matching: .any)[
            "scholium.documentStatus.conflict"
        ]
        XCTAssertTrue(conflictStatus.exists)
        XCTAssertTrue(accessibilityText(of: conflictStatus).contains("Autosave Paused"))
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains(localToken))
        XCTAssertTrue(try source(at: noteURL).contains(secondDiskToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))
    }

}
