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

    /// Opt-in diagnostic, not an installed-release cold-launch or first-frame gate.
    /// setUp owns fixture/pref isolation; selected-document restoration is the
    /// fixture-only route over its actual saved session, not ordinary launch.
    @MainActor
    func testRuntimeReadinessDiagnostic() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["SCHOLIUM_RUNTIME_DIAGNOSTIC_OUTPUT"] else {
            throw XCTSkip("Set SCHOLIUM_RUNTIME_DIAGNOSTIC_OUTPUT to a JSON file under repository .build.")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(build.path + "/"), output.pathExtension == "json",
            !FileManager.default.fileExists(atPath: output.path)
        else { throw XCTSkip("Diagnostic output must be a new JSON file under repository .build.") }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let runID = "runtime-readiness-\(UUID().uuidString)"
        let raw = build.appendingPathComponent("performance-\(runID)/app-state/raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try Data(contentsOf: note)
        let notesBefore = try bootstrapLifecycleNoteHashes()
        XCTAssertEqual(notesBefore.count, 500)
        // WorkspaceWindowCoordinator owns this exact native AX identifier.
        XCTAssertEqual(bootstrapLifecycleMainWindows.firstMatch.identifier, "scholium-main-\(sessionID.uuidString)")
        let session = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions/\(sessionID.uuidString).json")
        var launches: [[String: Any]] = []
        var switches: [[String: Any]] = []
        var vaults: [[String: Any]] = []

        func records(_ url: URL) -> [[String: Any]] {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
        func savedSession() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: session)) as? [String: Any])
        }
        func selectedAIsPersisted(in mode: String) -> Bool {
            guard let snapshot = try? savedSession() else { return false }
            return (snapshot["id"] as? String).flatMap(UUID.init(uuidString:)) == sessionID
                && (snapshot["selectedDocument"] as? [String: Any])?["relativePath"] as? String == "QA Autosave A.md"
                && snapshot["documentMode"] as? String == mode
        }
        func configureProbe(_ metric: String, results: URL, sample: Int, count: Int) {
            app = configuredApplication(sessionID: sessionID, usesFixtureWorkspace: true, openNote: nil)
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = results.path
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] = metric
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = String(sample)
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = String(count)
            app.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "QA Autosave A.md"
        }
        func quit() {
            app.typeKey("q", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 15) { self.app.state == .notRunning })
        }
        func persistReviewSelection() {
            selectDocumentMode("Review")
            XCTAssertTrue(waitUntil(timeout: 15) { self.documentSurfaceIsUsable(for: "QA Autosave A.md") })
            XCTAssertTrue(waitUntil(timeout: 10) { selectedAIsPersisted(in: "read") })
        }
        // This is an observation bound: it includes XCTest focus/key transport
        // and polling. The exact saved bytes and Undo provide the input oracle.
        func acceptEditAndRestore() throws -> UInt64 {
            let editor = enterLivePreview()
            XCTAssertTrue(waitUntil(timeout: 5) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor) })
            app.typeKey(.end, modifierFlags: [.command])
            let before = try XCTUnwrap(editor.value as? String)
            app.typeKey("x", modifierFlags: [])
            XCTAssertTrue(
                waitUntil(timeout: 8) {
                    (editor.value as? String).map { $0 != before && $0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("x") } ?? false
                })
            let accepted = DispatchTime.now().uptimeNanoseconds
            app.typeKey("s", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: note)) == original + Data("x".utf8) })
            app.typeKey("z", modifierFlags: [.command])
            // The long editor's AX text reflects its rendered viewport. Exact
            // saved Markdown is the stable Undo oracle across scroll changes.
            app.typeKey("s", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: note)) == original })
            return accepted
        }
        func writeSummary() throws {
            let summary: [String: Any] = [
                "schema": "scholium-runtime-readiness-diagnostic-v1", "run_id": runID,
                "fixture_note_count": notesBefore.count, "session_id": sessionID.uuidString,
                "raw_directory": raw.path,
                "conditions":
                    "Isolated QA build; setup already opened the 500-note fixture. Fixture-selected restoration of the genuinely persisted A selection with openNote nil; ordinary product launch intentionally restores no selected document. Same retained home, session, indexes and OS caches. Three new app processes; no cache purge. Not installed-release cold launch.",
                "origins": [
                    "launch_to_read_ready_ms":
                        "Driver DispatchTime immediately before XCUIApplication.launch through native first_read_activation completed_uptime_ns; includes XCTest launch transport, excludes later AX observation.",
                    "launch_to_accepted_edit_observed_ms":
                        "Same launch origin through XCTest observing accepted x after a native key; exact saved bytes are verified afterward; includes read checks, Review-to-Edit transition, focus/caret transport and polling. Conservative driver bound, not app-only latency.",
                    "note_switch_read_ready_ms":
                        "Native opening action through existing warm_read_activation rendered-document readiness. Actual native edit/save/undo verified separately.",
                    "vault_selection_observed_ms":
                        "Driver DispatchTime before one native segment click through XCTest observing selected destination and expected Library row; includes click/idle/polling overhead.",
                ],
                "unmeasured": ["first frame", "Search/index readiness", "installed-release cold launch"],
                "launches": launches, "note_switches": switches, "vault_switches": vaults,
            ]
            try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }

        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        let setupField = app.searchFields["scholium.searchField"].firstMatch
        XCTAssertTrue(setupField.waitForExistence(timeout: 10))
        setupField.click()
        typeCommittedText("runtimefreshuniqueneedle", into: setupField, in: app)
        selectResearchSearchScope("Triptych", in: app)
        XCTAssertTrue(
            waitUntil(timeout: 180) {
                self.searchResult(named: "QA Work", in: self.app.windows.firstMatch).exists
                    && !self.app.descendants(matching: .any)["scholium.searchLoading"].exists
                    && !self.app.descendants(matching: .any)["scholium.refreshStatus"].exists
            }, "The untimed setup must finish initial indexing before warm measurements.")
        setupField.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        persistReviewSelection()
        quit()
        XCTAssertTrue(selectedAIsPersisted(in: "read"))
        for sample in 0..<3 {
            let results = raw.appendingPathComponent("relaunch-\(sample).jsonl")
            try Data(contentsOf: session).write(to: raw.appendingPathComponent("session-before-relaunch-\(sample).json"))
            configureProbe("first_read_activation", results: results, sample: sample, count: 1)
            let started = DispatchTime.now().uptimeNanoseconds
            app.launch()
            try verifyRuntimeDiagnosticApplicationIdentity()
            XCTAssertTrue(waitUntil(timeout: 45) { records(results).count == 1 }, "Restored Review must reach native read readiness.")
            let record = try XCTUnwrap(records(results).first)
            XCTAssertEqual(record["metric"] as? String, "first_read_activation")
            XCTAssertEqual(record["sample"] as? Int, sample)
            let completed = try XCTUnwrap(record["completed_uptime_ns"] as? NSNumber).uint64Value
            XCTAssertGreaterThanOrEqual(completed, started)
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
            XCTAssertTrue(documentSurfaceIsUsable(for: "QA Autosave A.md"))
            XCTAssertEqual(documentModeState(documentModeControl()), "Review")
            XCTAssertTrue(selectedAIsPersisted(in: "read"))
            let accepted = try acceptEditAndRestore()
            launches.append([
                "sample": sample, "driver_launch_uptime_ns": started, "native_read_completed_uptime_ns": completed,
                "launch_to_read_ready_ms": Double(completed - started) / 1_000_000,
                "accepted_edit_observed_uptime_ns": accepted,
                "launch_to_accepted_edit_observed_ms": Double(accepted - started) / 1_000_000,
                "probe_file": results.path, "fixture_selected_a_restored_in_review": true, "edit_save_undo_exact": true,
            ])
            try writeSummary()
            persistReviewSelection()
            quit()
            XCTAssertTrue(selectedAIsPersisted(in: "read"))
        }

        let results = raw.appendingPathComponent("note-opening.jsonl")
        configureProbe("warm_read_activation", results: results, sample: 0, count: 4)
        app.launch()
        try verifyRuntimeDiagnosticApplicationIdentity()
        XCTAssertTrue(waitUntil(timeout: 45) { self.documentSurfaceIsUsable(for: "QA Autosave A.md") })
        XCTAssertTrue(waitUntil(timeout: 30) { records(results).count == 1 }, "The restored A visit is one declared unmeasured warmup.")
        selectDocumentMode("Review")
        for sample in 0..<3 {
            selectDocumentMode("Review")
            clickLibraryRow("QA Autosave B.md")
            XCTAssertTrue(waitForDocumentTitle("QA Autosave B"))
            XCTAssertTrue(waitUntil(timeout: 15) { self.documentSurfaceIsUsable(for: "QA Autosave B.md") })
            XCTAssertEqual(records(results).count, sample + 1, "The unmeasured B opening must not consume an A sample.")
            clickLibraryRow("QA Autosave A.md")
            XCTAssertTrue(waitUntil(timeout: 30) { records(results).count == sample + 2 })
            let record = try XCTUnwrap(records(results).last)
            XCTAssertEqual(record["metric"] as? String, "warm_read_activation")
            XCTAssertEqual(record["sample"] as? Int, sample + 1)
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
            XCTAssertTrue(documentSurfaceIsUsable(for: "QA Autosave A.md"))
            XCTAssertEqual(documentModeState(documentModeControl()), "Review")
            let accepted = try acceptEditAndRestore()
            switches.append([
                "sample": sample, "note_switch_read_ready_ms": try XCTUnwrap(record["duration_ms"] as? Double),
                "accepted_edit_observed_uptime_ns": accepted, "probe_file": results.path,
                "edit_save_undo_exact": true,
            ])
            try writeSummary()
        }

        let navigator = app.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        for sample in 0..<3 {
            for (destination, rowName) in [("Topics", "QA Topic.md"), ("Analyses", "QA Autosave A.md")] {
                let control = navigator.descendants(matching: .any)[destination].firstMatch
                let row = app.descendants(matching: .any)["scholium.noteRow.\(rowName)"].firstMatch
                XCTAssertTrue(control.waitForExistence(timeout: 5))
                let started = DispatchTime.now().uptimeNanoseconds
                control.click()
                XCTAssertTrue(
                    waitUntil(timeout: 15) {
                        row.exists && (control.isSelected || self.selectionControlIsSelected(control))
                    })
                let completed = DispatchTime.now().uptimeNanoseconds
                XCTAssertEqual(documentTitle(), "QA Autosave A", "Vault browsing must retain the selected document.")
                vaults.append([
                    "sample": sample, "destination": destination, "driver_click_uptime_ns": started,
                    "library_ready_observed_uptime_ns": completed,
                    "vault_selection_observed_ms": Double(completed - started) / 1_000_000,
                ])
                try writeSummary()
            }
        }
        try assertBootstrapLifecycleNotesUnchanged(notesBefore)
        persistReviewSelection()
        quit()
        XCTAssertTrue(selectedAIsPersisted(in: "read"))
        try writeSummary()
        print("RUNTIME_READINESS diagnostic=\(output.path) raw=\(raw.path)")
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
