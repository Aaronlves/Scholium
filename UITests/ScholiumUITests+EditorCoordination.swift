import AppKit
import Carbon
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testSelectionActionFailureStaysBesideBarAndPreservesPassage() throws {
        try enterLivePreviewAndAppend("\n\nSelection action fixture")
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        let before = editor.value as? String
        // Select only the final synthetic paragraph, leaving the native editor focused.
        editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
        let polish = app.buttons["Polish"].firstMatch
        XCTAssertTrue(polish.waitForExistence(timeout: 8))
        let barFrame = polish.frame
        polish.hover()
        let hover = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        hover.name = "Selection actions — system accent hover"
        hover.lifetime = .keepAlways
        add(hover)
        polish.click()
        let result = app.descendants(matching: .any)["scholium.selectionResult"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Connect in Chat to send this instruction."].firstMatch.exists)
        let resultFrame = result.frame
        XCTAssertLessThan(min(abs(resultFrame.minY - barFrame.maxY), abs(barFrame.minY - resultFrame.maxY)), 45)
        XCTAssertEqual(editor.value as? String, before)
        let failure = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        failure.name = "Selection actions — anchored unavailable connection"
        failure.lifetime = .keepAlways
        add(failure)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !result.exists })
        XCTAssertEqual(editor.value as? String, before)
    }

    @MainActor
    func testCalloutModesPreserveSemanticOrderAndExactSource() throws {
        func attachWindowScreenshot(_ label: String) {
            let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
            screenshot.name = label
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let roles = ["orient", "cite", "connect", "state", "illustrate", "quote", "flag", "neutral"]
        let content =
            "Callout presentation fixture\n\n"
            + roles.map {
                "> [!\($0)] \($0) · 语义标题\n> Synthetic passage · 可编辑正文。"
            }.joined(separator: "\n\n") + "\n\n> [!cite]\n> Untitled source.\n\n> [!flag]- Folded limitation\n> Hidden fixture body.\n"
        try write(content, to: noteURL)
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 12) { (editor.value as? String)?.contains("Untitled source.") == true })
        attachWindowScreenshot("Callouts — Edit — authored order")
        selectDocumentMode("Review")
        waitForCurrentDocumentSurface()
        attachWindowScreenshot("Callouts — Review — matching structure")
        selectDocumentMode("Edit")
        waitForCurrentDocumentSurface()
        XCTAssertTrue(waitUntil(timeout: 5) { (editor.value as? String)?.contains("Untitled source.") == true })
        XCTAssertEqual(try source(at: noteURL), content)
        selectDocumentMode("Source")
        waitForCurrentDocumentSurface()
        XCTAssertEqual(try source(at: noteURL), content)
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900, appearance: .dark)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        selectDocumentMode("Review")
        waitForCurrentDocumentSurface()
        attachWindowScreenshot("Callouts — Dark Review — narrow width")
        selectDocumentMode("Edit")
        waitForCurrentDocumentSurface()
        attachWindowScreenshot("Callouts — Dark Edit — narrow width")
        XCTAssertEqual(try source(at: noteURL), content)
    }

    @MainActor
    func testNativeCompletionPreservesFocusAndUndo() throws {
        try enterLivePreviewAndAppend("\n\ncompletionprobe\n\n")
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        let viewport = app.webViews.firstMatch
        let frame = viewport.frame
        let inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let isASCII =
            TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsASCIICapable)
            .map { Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue() }
            .map(CFBooleanGetValue) ?? true
        func typeAndCommit(_ text: String) {
            app.typeText(text)
            // Commit marked Latin input without changing the user's input source.
            if !isASCII { app.typeKey(.return, modifierFlags: []) }
        }
        typeAndCommit("/date")
        let suggestions = app.descendants(matching: .any)["scholium.documentSuggestions"].firstMatch
        XCTAssertTrue(suggestions.waitForExistence(timeout: 8))
        XCTAssertLessThan(suggestions.frame.width, 100, "A single short candidate fits its content.")
        XCTAssertGreaterThan(suggestions.frame.width, 44)
        XCTAssertEqual(viewport.frame, frame)
        XCTAssertTrue((editor.value as? String ?? "").contains("/date"))
        XCTAssertEqual(suggestions.frame.height, 40, accuracy: 1)
        let savedNote = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                (try? String(contentsOf: savedNote, encoding: .utf8))?.contains("/date") == true
            }, "Wait for the real autosave before activating the retained completion.")
        XCTAssertTrue(suggestions.exists, "Autosave must preserve the open candidate list.")
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Native Liquid Glass completion"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // The native container exposes geometry; CodeMirror owns the single AX list.
        suggestions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !suggestions.exists })
        XCTAssertFalse((editor.value as? String ?? "").contains("/date"))
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 5) { (editor.value as? String ?? "").contains("/date") })
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: 5) { !(editor.value as? String ?? "").contains("/date") })
        typeAndCommit("focusprobe")
        app.typeKey(.return, modifierFlags: [])
        typeAndCommit("/date")
        XCTAssertTrue(waitUntil(timeout: 5) { (editor.value as? String ?? "").contains("focusprobe") })
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !suggestions.exists })
        XCTAssertFalse((editor.value as? String ?? "").contains("/date"))
        app.typeKey(.return, modifierFlags: [])
        app.typeText("/")
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        let listFrame = suggestions.frame
        suggestions.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).hover()
        let hover = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        hover.name = "Unified native candidate selection"
        hover.lifetime = .keepAlways
        add(hover)
        for _ in 0..<8 {
            app.typeKey(.downArrow, modifierFlags: [])
            XCTAssertTrue(suggestions.exists)
            XCTAssertEqual(suggestions.frame, listFrame)
        }
        let listScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        listScreenshot.name = "Compact stable completion list"
        listScreenshot.lifetime = .keepAlways
        add(listScreenshot)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !suggestions.exists })
        XCTAssertEqual(viewport.frame, frame)

    }

    @MainActor
    func testDocumentFindDisclosesReplacementAndReturnsToExactSelection() throws {
        try enterLivePreviewAndAppend("\n\nfindprobe findprobe.")
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        let viewport = app.webViews.firstMatch
        let documentFrame = viewport.frame
        app.typeKey("f", modifierFlags: [.command])
        let query = app.descendants(matching: .any)["scholium.documentFind.query"].firstMatch
        let replacement = app.textFields["scholium.documentFind.replacement"]
        let count = app.staticTexts["scholium.documentFind.matches"]
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        XCTAssertFalse(replacement.exists)
        XCTAssertFalse(count.exists)
        let panel = app.descendants(matching: .any)["scholium.documentFind"].firstMatch
        XCTAssertLessThan(panel.frame.width, documentFrame.width)
        XCTAssertEqual(viewport.frame.minY, documentFrame.minY, accuracy: 1)
        XCTAssertEqual(viewport.frame.height, documentFrame.height, accuracy: 1)
        // macOS can briefly show its input-source indicator beside a newly
        // focused field. Wait for that system overlay before the pointer action.
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.dialogs.firstMatch.exists })
        viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.7)).click()
        XCTAssertTrue(query.exists, "Document interaction must not dismiss the floating panel.")
        app.typeKey("f", modifierFlags: [.command])
        typeCommittedText("findprobe", into: query, in: app)
        XCTAssertTrue(waitUntil(timeout: 5) { (count.value as? String) == "Match 1 of 2" })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { (count.value as? String) == "Match 2 of 2" })
        app.typeKey(.return, modifierFlags: [.shift])
        XCTAssertTrue(waitUntil(timeout: 5) { (count.value as? String) == "Match 1 of 2" })

        let compact = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        compact.name = "Document Find — compact native query"
        compact.lifetime = .keepAlways
        add(compact)

        app.buttons["scholium.documentFind.disclosure"].click()
        XCTAssertTrue(replacement.waitForExistence(timeout: 3))
        XCTAssertEqual(query.frame.minX, replacement.frame.minX, accuracy: 3)
        XCTAssertEqual(viewport.frame.minY, documentFrame.minY, accuracy: 1)
        XCTAssertEqual(viewport.frame.height, documentFrame.height, accuracy: 1)
        typeCommittedText("changedprobe", into: replacement, in: app)
        app.buttons["scholium.documentFind.replace"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { (count.value as? String) == "Match 1 of 1" })
        XCTAssertTrue((editor.value as? String ?? "").contains("changedprobe"))

        let expanded = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        expanded.name = "Document Find — explicit replacement"
        expanded.lifetime = .keepAlways
        add(expanded)

        app.typeKey("f", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 3) { !replacement.exists })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !query.exists })
        // Send paste to the app's actual responder, without clicking the editor.
        try setPasteboardText("focusreturned")
        app.typeKey("v", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                let value = editor.value as? String ?? ""
                return value.contains("changedprobe focusreturned.")
            })

        app.menuBars.menuBarItems["Edit"].click()
        app.menuItems["Find"].firstMatch.hover()
        let replaceMenu = app.menuItems["Find and Replace…"].firstMatch
        XCTAssertTrue(replaceMenu.waitForExistence(timeout: 3))
        replaceMenu.click()
        XCTAssertTrue(replacement.waitForExistence(timeout: 5))
        XCTAssertEqual(replacement.value as? String, "changedprobe")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !query.exists })

        selectDocumentMode("Review")
        app.typeKey("f", modifierFlags: [.command])
        XCTAssertTrue(query.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["scholium.documentFind.disclosure"].exists)
        XCTAssertFalse(replacement.exists)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !query.exists })
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

        let inspectorButton = inspectorVisibilityControl()
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        let inspectorWasVisible = inspector.exists
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
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

        _ = clickLibraryRow("QA Autosave B.md")
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                self.documentTitle() == "QA Autosave B"
            })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })
        XCTAssertFalse(try source(at: secondURL).contains(token))
    }

    @MainActor
    func testDocumentModeAndLibrarySwitchHandoffsStayBoundedWithoutSourceExposure() throws {
        let mode = documentModeControl()
        let rendered = app.descendants(matching: .any)["Rendered Markdown"]
        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        let sourceEditor = app.descendants(matching: .any)["Markdown source editor"]
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
        let reviewToEditMilliseconds =
            Double(
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
        let editToReviewMilliseconds =
            Double(
                DispatchTime.now().uptimeNanoseconds - editToReviewStart
            ) / 1_000_000

        selectMode("Edit")
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let firstToSecondStart = DispatchTime.now().uptimeNanoseconds
        _ = clickLibraryRow("QA Autosave B.md")
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                self.documentTitle() == "QA Autosave B"
                    && self.app.descendants(matching: .any)[
                        "Markdown editor, Edit mode"
                    ].exists
            })
        let firstToSecondMilliseconds =
            Double(
                DispatchTime.now().uptimeNanoseconds - firstToSecondStart
            ) / 1_000_000

        let secondToFirstStart = DispatchTime.now().uptimeNanoseconds
        _ = clickLibraryRow("QA Autosave A.md")
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                self.documentTitle() == "QA Autosave A"
                    && editor.exists
            })
        let secondToFirstMilliseconds =
            Double(
                DispatchTime.now().uptimeNanoseconds - secondToFirstStart
            ) / 1_000_000

        XCTAssertEqual(try Data(contentsOf: firstURL), firstSource)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondSource)
        let evidence = XCTAttachment(
            string: """
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
        let heading = "QA External \(UUID().uuidString)"
        let current = try source(at: noteURL)
        let changed = current.replacingOccurrences(
            of: "# QA Autosave A",
            with: "# \(heading)"
        )
        XCTAssertNotEqual(changed, current)
        try write(changed, to: noteURL)

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(
            waitUntil(timeout: 12) {
                (editor.value as? String)?.contains(heading) == true
            },
            "A clean open document must refresh after an external filesystem edit."
        )
        XCTAssertEqual(try source(at: noteURL), changed)
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
        let diskToken =
            "## External Disk Revision — "
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
        XCTAssertGreaterThanOrEqual(compare.frame.minX, conflictStatus.frame.minX)
        XCTAssertLessThanOrEqual(compare.frame.maxX, conflictStatus.frame.maxX)
        XCTAssertGreaterThanOrEqual(compare.frame.minY, conflictStatus.frame.minY)
        XCTAssertLessThanOrEqual(
            compare.frame.maxY, conflictStatus.frame.maxY,
            "Conflict recovery must remain within the notice when actions reflow below its message."
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
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.conflict.diff"
            ].waitForExistence(timeout: 3))
        let diffRows = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium.conflict.row."
            )
        ).allElementsBoundByIndex
        let readableDiffLine = try XCTUnwrap(
            diffRows.min(by: { $0.frame.height < $1.frame.height }),
            "The comparison must expose an intact representative source row."
        )
        XCTAssertGreaterThan(
            readableDiffLine.frame.width,
            100,
            "A source line must not collapse into a character-wide column."
        )
        let wrappedDiffLine = try XCTUnwrap(
            diffRows.max(by: { $0.frame.height < $1.frame.height }),
            "The comparison must expose the synthetic long source row."
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
            NSPredicate(format: "label == %@ OR value == %@", "Current Editor", "Current Editor")
        ).firstMatch
        let diskRevision = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR value == %@", "Disk Version", "Disk Version")
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
    func testOpenInNewTabUsesNativeContentTabsAndSharedLibrary() throws {
        waitForCurrentDocumentSurface()
        let secondPath = "QA Autosave B.md"
        let inspectorToggle = inspectorVisibilityControl()
        let inspector = app.descendants(matching: .any)[
            "scholium.researchInspector"
        ].firstMatch
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))
        if !inspector.exists {
            inspectorToggle.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        _ = clickLibraryRow(secondPath, rightMouseButton: true)
        let noteContextMenu = app.menus["scholium.noteRow.\(secondPath)"]
        XCTAssertTrue(noteContextMenu.waitForExistence(timeout: 3))
        let openInNewTab = noteContextMenu.menuItems["Open in New Tab"]
        XCTAssertTrue(openInNewTab.waitForExistence(timeout: 3))
        openInNewTab.click()

        // Expand a known collection only after opening the second root note.
        // Expanding a large first folder can move root notes outside the lazy
        // Library viewport, which is not evidence about document tabs.
        let noteList = app.outlines["scholium.noteList"].firstMatch
        let sharedFolder = noteList.descendants(matching: .outlineRow).containing(
            .any,
            identifier: "scholium.folderRow.格式与检索"
        ).firstMatch
        XCTAssertTrue(sharedFolder.waitForExistence(timeout: 8))
        if sharedFolder.value as? String != "Expanded" {
            let disclosure = sharedFolder.descendants(
                matching: .disclosureTriangle
            ).firstMatch
            XCTAssertTrue(
                disclosure.waitForExistence(timeout: 3),
                "The shared Library folder must expose its native disclosure control."
            )
            disclosure.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
            if !waitUntil(
                timeout: 2,
                condition: { sharedFolder.value as? String == "Expanded" }
            ) {
                // If the triangle itself is not exposed as a hit target at
                // the viewport edge, select the row and use NSOutlineView's
                // native Right Arrow expansion command.
                sharedFolder.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).click()
                app.typeKey(.rightArrow, modifierFlags: [])
            }
        }
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                sharedFolder.value as? String == "Expanded"
            })

        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(documentTabs.waitForExistence(timeout: 8))
        let firstTab = documentTabs.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "QA Autosave A")).firstMatch
        let secondTab = documentTabs.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "QA Autosave B")).firstMatch
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        XCTAssertTrue(secondTab.waitForExistence(timeout: 5))

        let nativeTabsScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        nativeTabsScreenshot.name = "Native content tabs with shared Library and Inspector"
        nativeTabsScreenshot.lifetime = .keepAlways
        add(nativeTabsScreenshot)

        let sharedFolderIdentifier = sharedFolder.identifier
        func currentSharedFolder() -> XCUIElement {
            self.app.descendants(matching: .any)[sharedFolderIdentifier]
        }

        func sharedPresentationIsPreserved(expectedNote: String) -> Bool {
            let folder = currentSharedFolder()
            let currentInspector = self.app.descendants(matching: .any)[
                "scholium.researchInspector"
            ].firstMatch
            return folder.exists
                && (folder.value as? String) == "Expanded"
                && currentInspector.exists
                && self.documentTitle() == expectedNote
        }

        XCTAssertTrue(
            waitUntil(timeout: 10) {
                sharedPresentationIsPreserved(expectedNote: "QA Autosave B")
            },
            "Opening a document tab must preserve Library disclosure and Apparatus presentation."
        )

        let navigator = app.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        navigator.descendants(matching: .any)["Topics"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].waitForExistence(timeout: 8))
        XCTAssertEqual(documentTitle(), "QA Autosave B")
        XCTAssertTrue(firstTab.exists && secondTab.exists)
        navigator.descendants(matching: .any)["Analyses"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 8) { currentSharedFolder().exists })

        firstTab.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                sharedPresentationIsPreserved(expectedNote: "QA Autosave A")
            })

        secondTab.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                sharedPresentationIsPreserved(expectedNote: "QA Autosave B")
            })
        app.menuBars.menuBarItems["File"].click()
        let closeTab = app.menuItems["Close Tab"].firstMatch
        XCTAssertTrue(closeTab.waitForExistence(timeout: 3))
        closeTab.click()
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                self.app.windows.firstMatch.exists
                    && !documentTabs.exists
                    && self.documentTitle() == "QA Autosave A"
            },
            "Closing the selected page must choose its previous neighbor without closing the workspace window."
        )
        XCTAssertTrue(app.windows.firstMatch.exists)
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
