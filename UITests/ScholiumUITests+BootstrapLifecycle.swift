import AppKit
import CryptoKit
@preconcurrency import XCTest

extension ScholiumUITests {
    /// A configured launch may spend longer than the former setup deadline
    /// restoring its window. Time cannot turn that pending restoration into
    /// permission to configure a different Triptych.
    @MainActor
    func testConfiguredLaunchWaitsForRestorationWithoutOpeningBootstrap() throws {
        terminateBootstrapLifecycleApplication()
        let registryURL = bootstrapLifecycleRegistryURL
        let registryBefore = try Data(contentsOf: registryURL)
        let notesBefore = try bootstrapLifecycleNoteHashes()
        XCTAssertEqual(notesBefore.count, 500)

        let waiting = homeDirectory.appendingPathComponent("WorkspaceRestore.waiting")
        let release = homeDirectory.appendingPathComponent("WorkspaceRestore.release")
        app = configuredApplication(
            sessionID: sessionID,
            usesFixtureWorkspace: false,
            openNote: nil
        )
        app.launchEnvironment["SCHOLIUM_UI_TEST_HOLD_WORKSPACE_RESTORE"] = "1"
        app.launch()
        XCTAssertTrue(
            waitUntil(timeout: 30) { FileManager.default.fileExists(atPath: waiting.path) },
            "The isolated QA launch did not reach the controlled restoration boundary."
        )
        XCTAssertTrue(bootstrapLifecycleMainWindows.firstMatch.waitForExistence(timeout: 15))
        captureBootstrapLifecycleBoundary("configured-restoration-held")
        assertBootstrapLifecycleStaysConfigured(mainWindowCount: 1, duration: 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: waiting.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: release.path))
        XCTAssertTrue(try Data(contentsOf: registryURL) == registryBefore, "Pending restoration must preserve the exact registry bytes.")

        try Data("Release isolated workspace restoration.\n".utf8).write(to: release)
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 1)
        captureBootstrapLifecycleBoundary("configured-restoration-complete")
        XCTAssertTrue(try Data(contentsOf: registryURL) == registryBefore, "Configured launch must preserve the exact registry bytes.")
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)
    }

    /// A saved registration whose folder is temporarily absent must retain
    /// its identity and offer access recovery, including beyond the former
    /// setup deadline. Only selecting that exact folder renews its bookmark.
    @MainActor
    func testUnavailableSavedFolderKeepsRegistrationAndRestoresAccess() throws {
        terminateBootstrapLifecycleApplication()
        let registryURL = bootstrapLifecycleRegistryURL
        let registryBefore = try Data(contentsOf: registryURL)
        let notesBefore = try bootstrapLifecycleNoteHashes()
        XCTAssertEqual(notesBefore.count, 500)

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let backup = testDirectory.appendingPathComponent("UnavailableAnalyses.backup", isDirectory: true)
        // Both paths are owned by this journey. Preserve every copied byte
        // before making the registered path unavailable; TestVaults is untouched.
        try FileManager.default.copyItem(at: analyses, to: backup)
        try FileManager.default.removeItem(at: analyses)
        let unaffectedNotes = try bootstrapLifecycleNoteHashes()

        app = configuredApplication(
            sessionID: sessionID,
            usesFixtureWorkspace: false,
            openNote: nil
        )
        app.launch()
        let recovery = app.sheets.firstMatch
        XCTAssertTrue(
            recovery.staticTexts["Restore Access"].waitForExistence(timeout: 30),
            "A missing saved vault must offer Restore Access instead of new Triptych setup."
        )
        XCTAssertTrue(recovery.buttons["Choose Folder…"].exists)
        XCTAssertTrue(
            recovery.staticTexts.matching(
                NSPredicate(format: "label == %@ OR value == %@", analyses.path, analyses.path)
            ).firstMatch.exists,
            "Recovery must identify the exact unavailable registered folder."
        )
        captureBootstrapLifecycleBoundary("saved-folder-unavailable")
        assertBootstrapLifecycleStaysConfigured(mainWindowCount: 1, duration: 9)
        XCTAssertTrue(recovery.staticTexts["Restore Access"].exists)
        XCTAssertTrue(try Data(contentsOf: registryURL) == registryBefore, "An unavailable folder must preserve the exact registry bytes.")
        try assertBootstrapLifecycleNotesUnchanged(unaffectedNotes)

        terminateBootstrapLifecycleApplication()
        try FileManager.default.copyItem(at: backup, to: analyses)
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)
        app = configuredApplication(
            sessionID: sessionID,
            usesFixtureWorkspace: false,
            openNote: nil
        )
        app.launch()
        // Copying the directory back may leave a stale bookmark. The live
        // access route decides whether renewed authorization is required.
        XCTAssertTrue(
            waitUntil(timeout: 30) {
                self.app.sheets.firstMatch.staticTexts["Restore Access"].exists
                    || self.bootstrapLifecycleLibraryIsReady(mainWindowCount: 1)
            },
            "The restored folder must yield either usable access or its exact authorization repair."
        )
        if app.sheets.firstMatch.staticTexts["Restore Access"].exists {
            chooseBootstrapLifecycleRecoveryFolder(analyses)
        }
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 1)
        captureBootstrapLifecycleBoundary("saved-folder-access-restored")
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)

        terminateBootstrapLifecycleApplication()
        let renewedRegistry = try Data(contentsOf: registryURL)
        app = configuredApplication(
            sessionID: sessionID,
            usesFixtureWorkspace: false,
            openNote: nil
        )
        app.launch()
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 1)
        assertBootstrapLifecycleStaysConfigured(mainWindowCount: 1, duration: 9)
        captureBootstrapLifecycleBoundary("saved-folder-recovery-persisted-relaunch")
        XCTAssertTrue(try Data(contentsOf: registryURL) == renewedRegistry, "Relaunch must preserve the renewed registry bytes.")
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)
    }

    /// Exercise native scene restoration separately from a fresh default
    /// launch: a bootstrap default must not add another window beside the
    /// two configured workspace routes restored by SwiftUI.
    @MainActor
    func testNativeWindowRestorationDoesNotAddBootstrapOrWorkspace() throws {
        terminateBootstrapLifecycleApplication()
        let registryURL = bootstrapLifecycleRegistryURL
        let registryBefore = try Data(contentsOf: registryURL)
        let notesBefore = try bootstrapLifecycleNoteHashes()
        XCTAssertEqual(notesBefore.count, 500)
        app = configuredApplication(
            sessionID: sessionID,
            usesFixtureWorkspace: false,
            ignoresSystemWindowRestoration: false,
            openNote: nil
        )
        app.launch()
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 1)
        app.menuBars.menuBarItems["File"].click()
        let newWindow = app.menuItems["New Window"].firstMatch
        XCTAssertTrue(newWindow.waitForExistence(timeout: 5) && newWindow.isEnabled)
        newWindow.click()
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 2)
        let windowIdentifiers = Set(
            bootstrapLifecycleMainWindows.allElementsBoundByIndex.map(\.identifier)
        )
        XCTAssertEqual(windowIdentifiers.count, 2)
        captureBootstrapLifecycleBoundary("native-restoration-before-quit")

        // Command-Q permits native scene-state saving. XCUIApplication's
        // terminate transport does not establish that graceful-quit boundary.
        app.typeKey("q", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 15) { self.app.state == .notRunning },
            "The isolated QA application did not finish its native quit."
        )
        app.launch()
        assertBootstrapLifecycleLibraryReady(mainWindowCount: 2)
        assertBootstrapLifecycleStaysConfigured(mainWindowCount: 2, duration: 9)
        XCTAssertEqual(
            Set(bootstrapLifecycleMainWindows.allElementsBoundByIndex.map(\.identifier)),
            windowIdentifiers,
            "Native relaunch must restore the same two configured window routes."
        )
        captureBootstrapLifecycleBoundary("native-restoration-after-relaunch")
        XCTAssertTrue(try Data(contentsOf: registryURL) == registryBefore, "Native scene restoration must preserve the exact registry bytes.")
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)
    }

    private var bootstrapLifecycleRegistryURL: URL {
        homeDirectory.appendingPathComponent("ApplicationSupport/Workspace/workspace-registration-v3.json")
    }

    @MainActor
    private var bootstrapLifecycleMainWindows: XCUIElementQuery {
        app.windows.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-"))
    }

    @MainActor
    private var bootstrapLifecycleShowsSetup: Bool {
        app.descendants(matching: .any)["scholium.bootstrap"].exists
            || app.buttons["scholium.bootstrap.createNew"].exists
            || app.descendants(matching: .any)["scholium.bootstrap.existingFolders"].exists
    }

    @MainActor
    private func terminateBootstrapLifecycleApplication() {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 10) { self.app.state == .notRunning })
        terminateRunningQAApplications()
    }

    @MainActor
    private func assertBootstrapLifecycleStaysConfigured(
        mainWindowCount: Int,
        duration: TimeInterval
    ) {
        XCTAssertEqual(bootstrapLifecycleMainWindows.count, mainWindowCount)
        XCTAssertEqual(app.windows.count, mainWindowCount)
        XCTAssertFalse(bootstrapLifecycleShowsSetup)
        let unexpectedSetup = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                self.bootstrapLifecycleShowsSetup
                    || self.bootstrapLifecycleMainWindows.count != mainWindowCount
                    || self.app.windows.count != mainWindowCount
            },
            object: nil
        )
        unexpectedSetup.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [unexpectedSetup], timeout: duration),
            .completed,
            "A configured restoration or access failure must not open Bootstrap or another workspace window."
        )
    }

    @MainActor
    private func bootstrapLifecycleLibraryIsReady(mainWindowCount: Int) -> Bool {
        let windows = bootstrapLifecycleMainWindows.allElementsBoundByIndex
        return windows.count == mainWindowCount && app.windows.count == mainWindowCount
            && !bootstrapLifecycleShowsSetup
            && windows.allSatisfy {
                $0.descendants(matching: .any)["scholium.librarySurface"].exists
                    && $0.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].exists
                    && !$0.descendants(matching: .any)["scholium.loadingOverlay"].exists
                    && !$0.sheets.firstMatch.exists
            }
    }

    @MainActor
    private func assertBootstrapLifecycleLibraryReady(mainWindowCount: Int) {
        XCTAssertTrue(
            waitUntil(timeout: 45) {
                self.bootstrapLifecycleLibraryIsReady(mainWindowCount: mainWindowCount)
            },
            "Persisted configuration must finish opening the Library in its existing workspace windows."
        )
    }

    @MainActor
    private func captureBootstrapLifecycleBoundary(_ name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name) — accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        for (index, window) in app.windows.allElementsBoundByIndex.enumerated() {
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "\(name) — window \(index + 1)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    private func chooseBootstrapLifecycleRecoveryFolder(_ folder: URL) {
        let recovery = app.sheets.firstMatch
        let choose = recovery.buttons["Choose Folder…"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.click()
        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToFolder = app.sheets.matching(
            NSPredicate(format: "identifier != %@", "open-panel")
        ).firstMatch
        XCTAssertTrue(goToFolder.waitForExistence(timeout: 5))
        let path = goToFolder.textFields.firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        path.click()
        path.typeKey("a", modifierFlags: [.command])
        path.typeText(folder.path)
        path.typeKey(.return, modifierFlags: [])
        if !waitUntil(timeout: 2) { !goToFolder.exists } {
            path.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !goToFolder.exists })
        // Confirming Go to Folder can also activate the Open panel's default
        // action, delivering the selected folder before a second button click.
        guard panel.exists else { return }
        let authorize = panel.buttons["OKButton"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        authorize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
    }

    private func bootstrapLifecycleNoteHashes() throws -> [String: String] {
        var hashes: [String: String] = [:]
        for role in ["01-analyses", "02-topics", "03-works"] {
            let root = triptychDirectory.appendingPathComponent(role, isDirectory: true)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ))
            for case let note as URL in enumerator where note.pathExtension.lowercased() == "md" {
                guard try note.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    continue
                }
                let relativePath = String(note.path.dropFirst(triptychDirectory.path.count + 1))
                hashes[relativePath] = SHA256.hash(data: try Data(contentsOf: note))
                    .map { String(format: "%02x", $0) }.joined()
            }
        }
        return hashes
    }

    private func assertBootstrapLifecycleNotesUnchanged(_ expected: [String: String]) throws {
        let actual = try bootstrapLifecycleNoteHashes()
        let changed = Set(expected.keys).union(actual.keys).filter {
            expected[$0] != actual[$0]
        }.sorted()
        XCTAssertTrue(
            changed.isEmpty,
            "Research bytes changed for \(changed.count) test-owned Notes: \(Array(changed.prefix(12)))."
        )
    }
}
