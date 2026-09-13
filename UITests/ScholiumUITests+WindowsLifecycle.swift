import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testLivePreviewUsesDocumentModeMenuForSourceTransition() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)

        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertEqual(documentModeState(mode), "Edit", "Source must be entered through the document-mode menu")

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertEqual(documentModeState(mode), "Source")
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
        waitForCurrentDocumentSurface()
        let observingWindowID = app.windows.firstMatch.identifier

        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count == 2 })
        let editingWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first(where: {
                $0.identifier != observingWindowID
            })
        )
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: editingWindow)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: editingWindow))

        let token = " SHARED-\(UUID().uuidString)"
        let firstURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        try enterLivePreviewAndPrepend(token, in: editingWindow)
        XCTAssertFalse(try source(at: firstURL).contains(token))

        let secondRow = editingWindow.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        secondRow.click()
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                self.documentTitle(in: editingWindow) == "QA Autosave B"
            })
        XCTAssertTrue(waitUntil(timeout: 8) { (try? self.source(at: firstURL).contains(token)) == true })

        XCTAssertTrue(
            waitUntil(timeout: 15) {
                let titles = self.app.windows.allElementsBoundByIndex.compactMap { window -> String? in
                    self.documentTitle(in: window)
                }
                return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
            },
            "The observing window must retain its own selection after the peer window navigates."
        )
        let observingWindow = try XCTUnwrap(
            app.windows.allElementsBoundByIndex.first { window in
                documentTitle(in: window) == "QA Autosave A"
            })

        let committedToken = token.trimmingCharacters(in: .whitespaces)
        let peerProjection = observingWindow.descendants(matching: .any).matching(
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
        waitForCurrentDocumentSurface()
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
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                self.documentTitle(in: peerWindow) == "QA Autosave B"
            })
        XCTAssertTrue(
            waitUntil(timeout: 20) {
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

        XCTAssertTrue(try source(at: noteURL).contains(peerToken))
        XCTAssertFalse(try source(at: noteURL).contains(localToken))
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
        waitForCurrentDocumentSurface()

        while app.windows.count > 1 {
            closeFrontmostWindow()
            XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count >= 1 })
        }

        let originalWindow = app.windows.firstMatch
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: originalWindow))
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
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: secondWindow, timeout: 8))

        let secondMode = documentModeControl(in: secondWindow)
        XCTAssertTrue(secondMode.waitForExistence(timeout: 5))
        selectDocumentMode("Edit", in: secondWindow)
        XCTAssertTrue(waitUntil(timeout: 8) { secondMode.value as? String == "Edit" })

        let sessionsDirectory =
            homeDirectory
            .appendingPathComponent("ApplicationSupport/Window Sessions", isDirectory: true)
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                guard
                    let files = try? FileManager.default.contentsOfDirectory(
                        at: sessionsDirectory,
                        includingPropertiesForKeys: nil
                    )
                else { return false }
                let snapshots = files.compactMap { try? Data(contentsOf: $0) }
                let sources = snapshots.compactMap { String(data: $0, encoding: .utf8) }
                return sources.contains { $0.contains("QA Autosave A.md") }
                    && sources.contains { $0.contains("QA Autosave B.md") && $0.contains("livePreview") }
            })

        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.state == .notRunning })

        app.launch()
        XCTAssertTrue(waitUntil(timeout: 20) { self.app.windows.count == 2 })
        XCTAssertTrue(
            waitUntil(timeout: 15) {
                let titles = self.app.windows.allElementsBoundByIndex.compactMap { window -> String? in
                    self.documentTitle(in: window)
                }
                return Set(titles) == Set(["QA Autosave A", "QA Autosave B"])
            })

        let restoredWindows = app.windows.allElementsBoundByIndex
        let restoredA = try XCTUnwrap(
            restoredWindows.first { window in
                documentTitle(in: window) == "QA Autosave A"
            })
        let restoredB = try XCTUnwrap(
            restoredWindows.first { window in
                documentTitle(in: window) == "QA Autosave B"
            })
        XCTAssertEqual(
            documentModeState(documentModeControl(in: restoredA)),
            "Edit"
        )
        let restoredBMode = documentModeControl(in: restoredB)
        XCTAssertTrue(waitUntil(timeout: 10) { restoredBMode.value as? String == "Edit" })

        XCTAssertEqual(app.windows.count, 2)
        XCTAssertFalse(restoredA.descendants(matching: .any)["scholium.documentTabs"].exists)
        XCTAssertFalse(restoredB.descendants(matching: .any)["scholium.documentTabs"].exists)
    }
}
