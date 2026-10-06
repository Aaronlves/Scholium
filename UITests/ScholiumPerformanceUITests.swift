import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

/// External driver for the frozen RDF-1 performance protocol. This class does
/// not create fixtures, package Scholium, or decide whether a run is a release
/// gate. `run-performance-benchmarks.sh` owns those fail-closed checks and
/// invokes this single method against an explicitly registered app bundle.
final class ScholiumPerformanceUITests: XCTestCase {
    private let packagedIsolationArgument =
        "--scholium-performance-driver-isolation"

    private enum Metric: String {
        case warmLibraryLaunch = "warm_library_launch"
        case indexedSearch = "indexed_search"
        case warmReadActivation = "warm_read_activation"
        case firstReadActivation = "first_read_activation"
        case editorKeyToPaint = "editor_key_to_paint"
        case editorModeTransition = "editor_mode_transition"
        case editorCachedPreview = "editor_cached_preview"
        case warmEditActivation = "warm_edit_activation"
        case firstEditActivation = "first_edit_activation"
        case editorVisibleProjection = "editor_visible_projection"

        var usesBatchedWarmProcess: Bool {
            self == .indexedSearch
                || self == .warmReadActivation
                || self == .editorKeyToPaint
                || self == .editorModeTransition
                || self == .editorCachedPreview
                || self == .warmEditActivation
                || self == .editorVisibleProjection
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

            if metric == .warmLibraryLaunch {
                application.launchEnvironment["SCHOLIUM_PERFORMANCE_STARTED_NS"] = String(
                    DispatchTime.now().uptimeNanoseconds
                )
            }
            application.launch()
            XCTAssertTrue(
                application.windows.firstMatch.waitForExistence(timeout: 30),
                "Sample \(sample): the performance app window did not appear."
            )
            if metric == .firstReadActivation {
                performFirstReadActivation(
                    in: application,
                    resultsPath: resultsPath,
                    sample: sample
                )
            } else if metric == .firstEditActivation {
                performFirstEditActivation(
                    in: application,
                    resultsPath: resultsPath,
                    sample: sample
                )
            } else {
                XCTAssertTrue(
                    waitUntil(timeout: 60) { self.lineCount(at: resultsPath) == sample + 1 },
                    "Sample \(sample): the app did not publish exactly one performance record."
                )
            }
            application.terminate()
            if sample + 1 < total, relaunchCooldownMilliseconds > 0 {
                Thread.sleep(forTimeInterval: Double(relaunchCooldownMilliseconds) / 1_000)
            }
        }
    }

    /// Exercises one clean Core journey on the exact packaged Release App.
    /// The shell driver runs this against both the mounted and copied bundle,
    /// each with its own disposable standard Triptych and empty state root.
    @MainActor
    func testPackagedCoreSmoke() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_PACKAGED_CORE_SMOKE"] == "1" else {
            throw XCTSkip("The packaged Core smoke is not configured.")
        }
        let applicationPath = try required(
            "SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH",
            in: environment
        )
        let fixtureRoot = try required(
            "SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT",
            in: environment
        )
        let homeRoot = try required(
            "SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT",
            in: environment
        )
        let runID = try required("SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID", in: environment)
        let triptych = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
        let noteURL = triptych.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalBytes = try Data(contentsOf: noteURL)
        let originalSource = try XCTUnwrap(String(data: originalBytes, encoding: .utf8))
        let addition = "packaged-core-smoke-\(runID)\n"
        let expectedSource = originalSource + addition
        let expectedBytes = Data(expectedSource.utf8)
        for role in ["01-analyses", "02-topics", "03-works"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: triptych.appendingPathComponent(role, isDirectory: true).path
                ),
                "The packaged smoke needs all three standard fixture folders."
            )
        }
        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            packagedIsolationArgument,
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
        defer { application.terminate() }

        application.launch()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(
            application.descendants(matching: .any)["scholium.bootstrap"]
                .waitForExistence(timeout: 20),
            "A clean packaged Release launch must enter Bootstrap."
        )
        XCTAssertTrue(
            application.buttons["scholium.bootstrap.createNew"].waitForExistence(timeout: 5),
            "Bootstrap must directly expose creation on first launch."
        )
        XCTAssertTrue(
            application.buttons["scholium.bootstrap.connectExisting"].exists,
            "Bootstrap must directly expose connecting existing folders on first launch."
        )
        XCTAssertFalse(
            application.descendants(matching: .any)["scholium.restoreAccess"].exists,
            "Restore Access is valid only for an already configured Triptych."
        )

        application.buttons["scholium.bootstrap.connectExisting"].click()
        XCTAssertTrue(
            application.descendants(matching: .any)["scholium.bootstrap.existingFolders"]
                .waitForExistence(timeout: 5)
        )
        choosePackagedFolder(
            triptych.appendingPathComponent("01-analyses", isDirectory: true),
            button: "scholium.bootstrap.chooseAnalyses",
            in: application
        )
        choosePackagedFolder(
            triptych.appendingPathComponent("02-topics", isDirectory: true),
            button: "scholium.bootstrap.chooseTopics",
            in: application
        )
        choosePackagedFolder(
            triptych.appendingPathComponent("03-works", isDirectory: true),
            button: "scholium.bootstrap.chooseWorks",
            in: application
        )
        choosePackagedFolder(
            triptych,
            button: "scholium.bootstrap.authorizeParent",
            in: application
        )
        let connect = application.buttons["Connect and Open"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertTrue(connect.isEnabled)
        connect.click()
        let noteRow = packagedNoteRow(in: application)
        XCTAssertTrue(noteRow.waitForExistence(timeout: 45))
        noteRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let mode = documentModeControl(in: application)
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        selectPackagedSourceMode(in: application, control: mode)
        let editor = application.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.packagedSourceAccessibilityMatches(originalSource, in: editor)
            })
        editor.click()
        editor.typeKey(.end, modifierFlags: [.command])
        editor.typeText(addition)
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.packagedSourceAccessibilityMatches(expectedSource, in: editor)
            })
        application.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 30) { (try? Data(contentsOf: noteURL)) == expectedBytes },
            "Saving must write the exact edited Markdown bytes to the disposable Note."
        )

        XCTAssertTrue(
            stopPackagedApplication(
                application,
                bundleURL: URL(fileURLWithPath: applicationPath, isDirectory: true)
            ),
            "The packaged App must fully terminate before the restore launch."
        )
        application.launch()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(
            application.descendants(matching: .any)["scholium.bootstrap"].exists,
            "The saved Triptych must restore without repeating Bootstrap."
        )
        let restoredRow = packagedNoteRow(in: application)
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 30))
        restoredRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let restoredMode = documentModeControl(in: application)
        XCTAssertTrue(restoredMode.waitForExistence(timeout: 20))
        selectPackagedSourceMode(in: application, control: restoredMode)
        let restoredEditor = application.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(restoredEditor.waitForExistence(timeout: 20))
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.packagedSourceAccessibilityMatches(expectedSource, in: restoredEditor)
            },
            "Reopening after relaunch must display the exact saved source."
        )
        XCTAssertEqual(try Data(contentsOf: noteURL), expectedBytes)
    }

    @MainActor
    private func packagedSourceAccessibilityMatches(
        _ expected: String,
        in editor: XCUIElement
    ) -> Bool {
        guard let value = editor.value as? String else { return false }
        // WebKit accessibility may expose one terminal blank line; disk bytes are checked exactly.
        return value == expected || value == expected + "\n"
    }

    @MainActor
    private func choosePackagedFolder(
        _ folder: URL,
        button: String,
        in application: XCUIApplication
    ) {
        let chooseButton = application.buttons[button]
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 5))
        chooseButton.click()
        let panel = application.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let goToFolders = application.sheets.matching(identifier: "GoToWindow")
        XCTAssertTrue(goToFolders.element(boundBy: 0).waitForExistence(timeout: 5))
        guard goToFolders.count == 1 else {
            XCTFail("The packaged picker must own exactly one native Go to Folder sheet.")
            return
        }
        let goToFolder = goToFolders.element
        let pathFields = goToFolder.textFields.matching(identifier: "PathTextField")
        XCTAssertTrue(pathFields.element(boundBy: 0).waitForExistence(timeout: 5))
        guard pathFields.count == 1 else {
            XCTFail("The native Go to Folder sheet must own exactly one path field.")
            return
        }
        let pathField = pathFields.element
        guard pathField.isHittable else {
            XCTFail("The native Go to Folder path field must be hittable before entering its exact path.")
            return
        }
        pathField.click()
        application.typeKey("a", modifierFlags: [.command])
        application.typeKey(.delete, modifierFlags: [])
        guard waitUntil(timeout: 5, condition: { pathField.value as? String == "" }) else {
            XCTFail("The native path field did not clear; observed \(String(describing: pathField.value)).")
            return
        }
        var enteredPrefix = ""
        for character in folder.path {
            application.typeText(String(character))
            enteredPrefix.append(character)
            guard waitUntil(timeout: 5, condition: { pathField.value as? String == enteredPrefix }) else {
                XCTFail(
                    "Native path input must settle the exact prefix \(enteredPrefix.debugDescription); observed \(String(describing: pathField.value))."
                )
                return
            }
        }
        let enteredPath = pathField.value as? String
        XCTAssertEqual(
            enteredPath,
            folder.path,
            "The native path field must contain the exact disposable folder before confirmation."
        )
        guard enteredPath == folder.path else { return }
        application.typeKey(.return, modifierFlags: [])
        // Go to Folder can use the first Return to accept a completion. The
        // panel route is ready only after the sheet has actually closed.
        if !waitUntil(timeout: 2) { !goToFolder.exists }, goToFolder.exists {
            application.typeKey(.return, modifierFlags: [])
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !goToFolder.exists })
        if panel.exists {
            let choose = panel.buttons["OKButton"]
            XCTAssertTrue(choose.waitForExistence(timeout: 5))
            choose.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
            XCTAssertTrue(waitUntil(timeout: 5) { !panel.exists })
        }
        let selectedPath = application.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", folder.path)
        ).firstMatch
        XCTAssertTrue(
            selectedPath.waitForExistence(timeout: 10),
            "The packaged picker must return the exact disposable folder before continuing."
        )
    }

    @MainActor
    private func packagedNoteRow(in application: XCUIApplication) -> XCUIElement {
        application.outlines["scholium.noteList"]
            .descendants(matching: .outlineRow)
            .containing(.any, identifier: "scholium.noteRow.QA Autosave A.md")
            .firstMatch
    }

    @MainActor
    private func selectPackagedSourceMode(
        in application: XCUIApplication,
        control: XCUIElement
    ) {
        if documentModeState(control) == "Source" { return }
        application.menuBars.menuBarItems["View"].click()
        let documentModeMenu = application.menuItems["Document Mode"].firstMatch
        XCTAssertTrue(documentModeMenu.waitForExistence(timeout: 5))
        documentModeMenu.hover()
        let source = application.menuItems["Source"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()
    }

    /// Samples only the app and WebKit service PIDs attributed to this exact
    /// process while the retained CodeMirror surface changes presentation.
    /// The shell runner supplies the predeclared scenario or product-gate
    /// transition count; this driver enforces only the protocol's hard cap.
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
        XCTAssertLessThanOrEqual(transitions, 60)

        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            packagedIsolationArgument,
            "--scholium-performance-editor-mode-notifications",
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
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
        let modeMenu = documentModeControl(in: application)
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 30))
        selectEditorMode(
            "Edit",
            accessibilityLabel: "Markdown editor, Edit mode",
            modeMenu: modeMenu,
            application: application,
            documentID: "Long/Canonical-5000-Word-Work.md"
        )
        waitForMemoryAcknowledgment(
            index: 0,
            acknowledgmentPath: acknowledgmentPath
        )

        for transition in 1...transitions {
            let sourceMode = transition.isMultiple(of: 2) == false
            requestMeasuredEditorMode(sourceMode ? "Source" : "Edit")
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.lineCount(at: progressPath) == transition + 1
                },
                "The app did not acknowledge retained-memory transition \(transition)."
            )
            waitForMemoryAcknowledgment(
                index: transition,
                acknowledgmentPath: acknowledgmentPath
            )
        }

        let finalModeIsSource = transitions.isMultiple(of: 2) == false
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.documentModeState(modeMenu) == (finalModeIsSource ? "Source" : "Edit")
                    && application.descendants(matching: .any)[
                        finalModeIsSource
                            ? "Markdown source editor"
                            : "Markdown editor, Edit mode"
                    ].exists
            },
            "The final retained Editor mode was not visibly accessible."
        )
    }

    /// Exercises the frozen packaged RDF-1 CJK document without leaving a
    /// modified fixture behind. Beginning and middle edits are immediately
    /// undone; the end edit is saved across mode switches, then undone and
    /// saved back to the original exact bytes.
    @MainActor
    func testRDF1HundredThousandCJKCorrectness() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_PERFORMANCE_CJK_RESULTS_PATH"] != nil else {
            throw XCTSkip("The packaged RDF-1 CJK correctness driver is not configured.")
        }
        let applicationPath = try required("SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH", in: environment)
        let fixtureRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT", in: environment)
        let homeRoot = try required("SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT", in: environment)
        let runID = try required("SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID", in: environment)
        let resultsPath = try required("SCHOLIUM_PERFORMANCE_CJK_RESULTS_PATH", in: environment)
        let relativePath = "Long/Canonical-100000-CJK-Work.md"
        let noteURL = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
            .appendingPathComponent("03-works", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: false)
        let originalData = try Data(contentsOf: noteURL)
        let originalSource = try XCTUnwrap(String(data: originalData, encoding: .utf8))
        let cjkCharacterCount = originalSource.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x4E00...0x9FFF).contains(scalar.value) { count += 1 }
        }
        XCTAssertEqual(cjkCharacterCount, 100_000)
        let application = XCUIApplication(
            url: URL(fileURLWithPath: applicationPath, isDirectory: true)
        )
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            packagedIsolationArgument,
            "--scholium-performance-editor-mode-notifications",
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = "1380"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
        application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = relativePath
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = "300000"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = resultsPath
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] =
            "editor_large_cjk_correctness"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = "0"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = "1"
        application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = relativePath
        defer {
            let stopped = stopPackagedApplication(
                application,
                bundleURL: URL(fileURLWithPath: applicationPath, isDirectory: true)
            )
            // Never race a live editor buffer with an out-of-process repair.
            // A process that refuses termination leaves the disposable fixture
            // dirty so the runner's final RDF-1 manifest check fails closed.
            if stopped, (try? Data(contentsOf: noteURL)) != originalData {
                try? originalData.write(to: noteURL, options: .atomic)
            }
        }

        application.launch()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 30))
        let modeMenu = documentModeControl(in: application)
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 30))
        selectCJKDocumentMode(
            "Edit",
            accessibilityLabel: "Markdown editor, Edit mode",
            modeMenu: modeMenu,
            application: application,
            documentID: relativePath
        )
        let editor = application.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 60))
        editor.click()

        let beginningToken = "QA-CJK-BEGIN-\(UUID().uuidString)"
        application.typeKey(.home, modifierFlags: [.command])
        typeText(beginningToken, into: application)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (editor.value as? String)?.contains(beginningToken) == true
            }
        )
        application.typeKey("z", modifierFlags: [.command])

        for _ in 0..<24 { application.typeKey(.pageDown, modifierFlags: []) }
        let middleToken = "QA-CJK-MIDDLE-\(UUID().uuidString)"
        typeText(middleToken, into: application)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (editor.value as? String)?.contains(middleToken) == true
            }
        )
        application.typeKey("z", modifierFlags: [.command])

        let endToken = "QA-CJK-END-\(UUID().uuidString)"
        application.typeKey(.end, modifierFlags: [.command])
        typeText(endToken, into: application)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalData)

        application.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                (try? String(contentsOf: noteURL, encoding: .utf8).contains(endToken)) == true
            },
            "The 100,000-CJK end edit did not reach the revision-checked save path."
        )
        let committedSource = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertEqual(committedSource.components(separatedBy: endToken).count, 2)
        XCTAssertEqual(committedSource.replacingOccurrences(of: endToken, with: ""), originalSource)

        selectCJKDocumentMode(
            "Source",
            accessibilityLabel: "Markdown source editor",
            modeMenu: modeMenu,
            application: application,
            documentID: relativePath
        )
        selectCJKDocumentMode(
            "Edit",
            accessibilityLabel: "Markdown editor, Edit mode",
            modeMenu: modeMenu,
            application: application,
            documentID: relativePath
        )
        editor.click()
        application.typeKey("z", modifierFlags: [.command])
        application.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 60) { (try? Data(contentsOf: noteURL)) == originalData },
            "Undo after mode switching did not restore the exact RDF-1 CJK bytes."
        )

        XCTAssertEqual(
            notify_post("com.scholium.qa.performance-editor-cjk-correctness"),
            UInt32(NOTIFY_STATUS_OK),
            "The packaged CJK correctness handshake could not be posted."
        )
        XCTAssertTrue(
            waitUntil(timeout: 20) { self.lineCount(at: resultsPath) == 1 },
            "The packaged app did not publish the CJK correctness record."
        )
        let recorded = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: URL(fileURLWithPath: resultsPath))
            ) as? [String: Any]
        )
        XCTAssertEqual(recorded["run_id"] as? String, runID)
        XCTAssertEqual(recorded["character_count"] as? Int, cjkCharacterCount)
        for key in [
            "beginning_edit_undo", "middle_edit_undo", "end_edit_save",
            "mode_switching", "exact_source_restored",
        ] {
            XCTAssertEqual(recorded[key] as? Bool, true)
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
        application.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            packagedIsolationArgument,
        ]
        if metric == .editorModeTransition
            || metric == .editorCachedPreview
            || metric == .warmEditActivation
            || metric == .firstEditActivation
            || metric == .editorVisibleProjection
        {
            application.launchArguments.append(
                "--scholium-performance-editor-mode-notifications"
            )
        }
        if metric == .warmReadActivation || metric == .firstReadActivation
            || metric == .firstEditActivation
        {
            application.launchArguments.append(
                "--scholium-performance-library-reveal-notifications"
            )
        }
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
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
        case .firstReadActivation, .firstEditActivation:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "Long/Canonical-5000-Word-Work.md"
        case .editorKeyToPaint, .editorModeTransition, .editorCachedPreview,
            .warmEditActivation, .editorVisibleProjection:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = "Long/Canonical-5000-Word-Work.md"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "Long/Canonical-5000-Word-Work.md"
        }
        if metric == .editorKeyToPaint {
            application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = "300000"
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
        case .editorKeyToPaint, .editorModeTransition, .editorCachedPreview,
            .warmEditActivation, .editorVisibleProjection:
            setupDocument = "Long/Canonical-5000-Word-Work.md"
        case .warmLibraryLaunch, .firstReadActivation, .firstEditActivation:
            return
        }
        XCTAssertTrue(
            waitForUsableDocument(setupDocument, in: application, timeout: 30),
            "The warm metric setup document did not expose an accessible surface."
        )
        if metric == .warmReadActivation {
            let modeMenu = documentModeControl(in: application)
            XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
            if documentModeState(modeMenu) != "Review" {
                application.typeKey("r", modifierFlags: [.command])
            }
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.documentModeState(modeMenu) == "Review"
                        && self.waitForRenderedDocument(
                            setupDocument,
                            in: application,
                            timeout: 0.1
                        )
                },
                "The warm Read setup did not reach accessible Review."
            )
            try prepareWarmReadLibraryTargets(in: application)
            return
        }
        if metric == .editorModeTransition || metric == .editorKeyToPaint
            || metric == .editorCachedPreview
            || metric == .warmEditActivation
            || metric == .editorVisibleProjection
        {
            let modeMenu = documentModeControl(in: application)
            XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
            if documentModeState(modeMenu) != "Edit"
                || !application.descendants(matching: .any)[
                    "Markdown editor, Edit mode"
                ].exists
            {
                requestPerformanceEditorAction("activation")
            }
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    self.documentModeState(modeMenu) == "Edit"
                        && application.descendants(matching: .any)[
                            "Markdown editor, Edit mode"
                        ].exists
                },
                "The Editor transition setup did not reach accessible Edit mode."
            )
            if metric == .editorKeyToPaint {
                let editor = application.descendants(matching: .any)[
                    "Markdown editor, Edit mode"
                ]
                XCTAssertTrue(editor.waitForExistence(timeout: 10))
                let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
                XCTAssertTrue(
                    waitUntil(timeout: 10) {
                        keyboardFocus.evaluate(with: editor)
                    },
                    "The key-to-paint setup did not receive the Editor's native focus handoff."
                )
                application.typeKey(.end, modifierFlags: [.command])
            }
            if metric == .warmEditActivation {
                requestPerformanceEditorAction("review")
                XCTAssertTrue(
                    waitUntil(timeout: 20) {
                        self.documentModeState(modeMenu) == "Review"
                            && self.waitForRenderedDocument(
                                setupDocument,
                                in: application,
                                timeout: 0.1
                            )
                    },
                    "The warm Edit setup did not return to accessible Review."
                )
            }
            if metric == .editorCachedPreview {
                let refreshing = application.descendants(matching: .any)[
                    "scholium.refreshStatus"
                ]
                XCTAssertTrue(
                    waitUntil(timeout: 90) { !refreshing.exists },
                    "Cached preview setup did not finish the synthetic Library graph refresh."
                )
            }
            return
        }
        application.typeKey("f", modifierFlags: [.command, .shift])
        let advanced = application.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 10))
        let field = advanced.searchFields["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        replaceCommittedText("scopeSetup", in: field, application: application)
        selectResearchSearchScope("This Vault", in: application)
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
        case .warmLibraryLaunch, .firstReadActivation, .firstEditActivation:
            return
        case .indexedSearch:
            let field = application.windows["scholium.advancedSearchWindow"].searchFields["scholium.searchField"]
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
                let close = application.windows["scholium.advancedSearchWindow"]
                    .buttons[XCUIIdentifierCloseWindow]
                XCTAssertTrue(close.waitForExistence(timeout: 5))
                close.click()
            }
        case .warmReadActivation:
            let target = revealNativeLibraryRow(
                "Cluster-00/analysis-note-001.md",
                in: application,
                sample: sample,
                role: "measured"
            )
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
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
                let alternate = revealNativeLibraryRow(
                    "Cluster-01/analysis-note-002.md",
                    in: application,
                    sample: sample,
                    role: "alternate"
                )
                alternate.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                XCTAssertTrue(
                    waitForRenderedDocument(
                        "Cluster-01/analysis-note-002.md",
                        in: application,
                        timeout: 30
                    ),
                    "Sample \(sample): navigation did not restore the alternate warm document."
                )
            }
        case .editorKeyToPaint:
            let editor = application.descendants(matching: .any)[
                "Markdown editor, Edit mode"
            ]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            if sample.isMultiple(of: 2) {
                application.typeKey("x", modifierFlags: [])
            } else {
                application.typeKey(.delete, modifierFlags: [])
            }
            let recordPublished = waitUntil(timeout: 30) {
                self.lineCount(at: resultsPath) == sample + 1
            }
            if !recordPublished {
                XCTFail(
                    "Sample \(sample): painted key input did not publish exactly one performance record."
                )
                return
            }
        case .editorModeTransition:
            let sourceMode = sample.isMultiple(of: 2)
            requestMeasuredEditorMode(
                sourceMode ? "Source" : "Edit"
            )
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.lineCount(at: resultsPath) == sample + 1
                },
                "Sample \(sample): Editor mode transition did not publish exactly one performance record."
            )
            let modeMenu = documentModeControl(in: application)
            let accessibilityLabel =
                sourceMode
                ? "Markdown source editor"
                : "Markdown editor, Edit mode"
            XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    self.documentModeState(modeMenu) == (sourceMode ? "Source" : "Edit")
                        && application.descendants(matching: .any)[accessibilityLabel].exists
                },
                "Sample \(sample): the measured Editor mode was not accessible after publication."
            )
        case .editorCachedPreview:
            requestPerformanceEditorAction("cached-preview")
            let preview = application.descendants(matching: .any)["scholium.documentPreview"]
            let content = application.descendants(matching: .any)["scholium.documentPreview.content"]
            let accessible =
                preview.waitForExistence(timeout: 30)
                && content.waitForExistence(timeout: 5)
            if !accessible {
                attachPerformanceFailureState(
                    named: "cached-preview-sample-\(sample)",
                    application: application
                )
            }
            XCTAssertTrue(
                accessible,
                "Sample \(sample): the visible native preview and content were not accessible."
            )
            XCTAssertTrue(
                waitUntil(timeout: 5) {
                    self.lineCount(at: resultsPath) == sample + 1
                },
                "Sample \(sample): the native cached preview did not publish a visible performance record."
            )
        case .editorVisibleProjection:
            requestPerformanceEditorAction("visible-projection")
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.lineCount(at: resultsPath) == sample + 1
                },
                "Sample \(sample): visible projection did not publish exactly one performance record."
            )
        case .warmEditActivation:
            requestPerformanceEditorAction("activation")
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.lineCount(at: resultsPath) == sample + 1
                },
                "Sample \(sample): warm Edit activation did not publish exactly one performance record."
            )
            let modeMenu = documentModeControl(in: application)
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    self.documentModeState(modeMenu) == "Edit"
                        && application.descendants(matching: .any)[
                            "Markdown editor, Edit mode"
                        ].exists
                }
            )
            if sample + 1 < total {
                requestPerformanceEditorAction("review")
                XCTAssertTrue(
                    waitUntil(timeout: 20) {
                        self.documentModeState(modeMenu) == "Review"
                    }
                )
            }
        }
    }

    @MainActor
    private func prepareWarmReadLibraryTargets(in application: XCUIApplication) throws {
        _ = revealNativeLibraryRow(
            "Cluster-00/analysis-note-001.md",
            in: application,
            sample: 0,
            role: "warm setup first"
        )
        _ = revealNativeLibraryRow(
            "Cluster-01/analysis-note-002.md",
            in: application,
            sample: 0,
            role: "warm setup alternate"
        )
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
    private func performFirstReadActivation(
        in application: XCUIApplication,
        resultsPath: String,
        sample: Int
    ) {
        _ = selectFirstUseReviewDocument(in: application, sample: sample)
        XCTAssertTrue(
            waitUntil(timeout: 60) { self.lineCount(at: resultsPath) == sample + 1 },
            "Sample \(sample): first Review did not publish exactly one performance record."
        )
    }

    @MainActor
    private func documentModeControl(
        in application: XCUIApplication
    ) -> XCUIElement {
        application.toolbars.firstMatch.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Document Mode,")
        ).firstMatch
    }

    @MainActor
    private func documentModeState(_ control: XCUIElement) -> String? {
        control.label.split(separator: ",", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func performFirstEditActivation(
        in application: XCUIApplication,
        resultsPath: String,
        sample: Int
    ) {
        _ = selectFirstUseReviewDocument(in: application, sample: sample)
        XCTAssertEqual(
            lineCount(at: resultsPath),
            sample,
            "Sample \(sample): first Edit setup published a record before the Edit request."
        )

        requestPerformanceEditorAction("activation")
        XCTAssertTrue(
            waitUntil(timeout: 30) { self.lineCount(at: resultsPath) == sample + 1 },
            "Sample \(sample): first Edit did not publish exactly one performance record."
        )
        let modeMenu = documentModeControl(in: application)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.documentModeState(modeMenu) == "Edit"
                    && application.descendants(matching: .any)[
                        "Markdown editor, Edit mode"
                    ].exists
            },
            "Sample \(sample): the first Editor was not visible and accessible."
        )
    }

    @MainActor
    private func selectFirstUseReviewDocument(
        in application: XCUIApplication,
        sample: Int
    ) -> String {
        let noDocumentState = application.descendants(matching: .any)[
            "scholium.noDocumentState"
        ]
        XCTAssertTrue(
            noDocumentState.waitForExistence(timeout: 30),
            "Sample \(sample): cold launch did not settle on an empty Workspace."
        )

        let documentID = "Long/Canonical-5000-Word-Work.md"
        let target = revealNativeLibraryRow(
            documentID,
            in: application,
            sample: sample,
            role: "first-use document"
        )
        XCTAssertTrue(
            noDocumentState.exists,
            "Sample \(sample): setup selected a document before the measured action."
        )

        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForRenderedDocument(documentID, in: application, timeout: 60),
            "Sample \(sample): the first selected Review document did not render."
        )
        return documentID
    }

    @MainActor
    private func nativeLibraryRow(
        _ identifier: String,
        in application: XCUIApplication
    ) -> XCUIElement {
        application.outlines["scholium.noteList"]
            .descendants(matching: .outlineRow)
            .containing(.any, identifier: identifier)
            .firstMatch
    }

    @MainActor
    private func revealNativeLibraryRow(
        _ documentID: String,
        in application: XCUIApplication,
        sample: Int,
        role: String
    ) -> XCUIElement {
        let notificationName: String
        switch documentID {
        case "Cluster-00/analysis-note-001.md":
            notificationName = "com.scholium.qa.performance-library-reveal-cluster-00"
        case "Cluster-01/analysis-note-002.md":
            notificationName = "com.scholium.qa.performance-library-reveal-cluster-01"
        case "Long/Canonical-5000-Word-Work.md":
            notificationName = "com.scholium.qa.performance-library-reveal-long"
        default:
            XCTFail("Sample \(sample): unsupported RDF-1 Library target \(documentID).")
            return nativeLibraryRow("scholium.noteRow.\(documentID)", in: application)
        }
        var acknowledgmentToken: Int32 = 0
        XCTAssertEqual(
            notify_register_check("\(notificationName).complete", &acknowledgmentToken),
            UInt32(NOTIFY_STATUS_OK),
            "Sample \(sample): native Library reveal acknowledgment could not be registered."
        )
        defer { notify_cancel(acknowledgmentToken) }
        var changed: Int32 = 0
        XCTAssertEqual(notify_check(acknowledgmentToken, &changed), UInt32(NOTIFY_STATUS_OK))
        XCTAssertEqual(
            notify_post(notificationName),
            UInt32(NOTIFY_STATUS_OK),
            "Sample \(sample): native Library reveal request could not be posted."
        )
        XCTAssertTrue(
            waitUntil(timeout: 25) {
                var didChange: Int32 = 0
                return notify_check(acknowledgmentToken, &didChange)
                    == UInt32(NOTIFY_STATUS_OK) && didChange != 0
            },
            "Sample \(sample): the \(role) native Library reveal was not consumed."
        )

        let target = nativeLibraryRow("scholium.noteRow.\(documentID)", in: application)
        let scrollView = application.scrollViews
            .containing(.outline, identifier: "scholium.noteList")
            .firstMatch
        XCTAssertTrue(
            scrollView.waitForExistence(timeout: 10),
            "Sample \(sample): the native Note list scroll viewport did not remain accessible."
        )
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                guard target.exists else { return false }
                let intersection = target.frame.intersection(scrollView.frame)
                return !intersection.isNull
                    && intersection.width >= 8
                    && intersection.height >= 8
            },
            "Sample \(sample): the \(role) Read target was not revealed by native Library navigation."
        )
        return target
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
    private func waitForUsableDocument(
        _ documentID: String,
        in application: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let row = application.outlines["scholium.noteList"]
            .descendants(matching: .outlineRow)
            .containing(.any, identifier: "scholium.noteRow.\(documentID)")
            .firstMatch
        return waitUntil(timeout: timeout) {
            guard row.isSelected else { return false }
            if self.waitForRenderedDocument(
                documentID,
                in: application,
                timeout: 0.1
            ) {
                return true
            }
            return application.descendants(matching: .any)[
                "Markdown editor, Edit mode"
            ].exists
                || application.descendants(matching: .any)[
                    "Markdown source editor"
                ].exists
        }
    }

    @MainActor
    private func selectEditorMode(
        _ title: String,
        accessibilityLabel: String,
        modeMenu: XCUIElement,
        application: XCUIApplication,
        documentID: String
    ) {
        let notificationName =
            title == "Edit"
            ? "com.scholium.qa.performance-editor-mode.live-preview"
            : "com.scholium.qa.performance-editor-mode.source"
        let deadline = Date().addingTimeInterval(20)
        repeat {
            XCTAssertEqual(
                notify_post(notificationName),
                UInt32(NOTIFY_STATUS_OK),
                "The QA Editor mode request could not be posted."
            )
            if waitUntil(
                timeout: 1.5,
                condition: {
                    self.documentModeState(modeMenu) == title
                        && application.descendants(matching: .any)[accessibilityLabel].exists
                })
            {
                return
            }
        } while Date() < deadline
        XCTFail(
            "The \(title) editor surface for \(documentID) did not become accessible."
        )
    }

    @MainActor
    private func requestMeasuredEditorMode(
        _ title: String
    ) {
        let notificationName =
            title == "Edit"
            ? "com.scholium.qa.performance-editor-mode.live-preview"
            : "com.scholium.qa.performance-editor-mode.source"
        XCTAssertEqual(
            notify_post(notificationName),
            UInt32(NOTIFY_STATUS_OK),
            "The measured QA Editor mode request could not be posted."
        )
    }

    private func requestPerformanceEditorAction(_ action: String) {
        XCTAssertEqual(
            notify_post("com.scholium.qa.performance-editor-\(action)"),
            UInt32(NOTIFY_STATUS_OK),
            "The QA Editor performance action could not be posted."
        )
    }

    @MainActor
    private func typeText(_ text: String, into application: XCUIApplication) {
        application.typeText(text)
    }

    @MainActor
    private func selectCJKDocumentMode(
        _ title: String,
        accessibilityLabel: String,
        modeMenu: XCUIElement,
        application: XCUIApplication,
        documentID: String
    ) {
        if documentModeState(modeMenu) != title {
            let notificationName =
                title == "Edit"
                ? "com.scholium.qa.performance-editor-mode.live-preview"
                : "com.scholium.qa.performance-editor-mode.source"
            XCTAssertEqual(
                notify_post(notificationName),
                UInt32(NOTIFY_STATUS_OK),
                "The packaged CJK mode request could not be posted."
            )
        }
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                self.documentModeState(modeMenu) == title
                    && application.descendants(matching: .any)[accessibilityLabel].exists
            },
            "The packaged CJK \(title) surface for \(documentID) did not become accessible."
        )
    }

    private func stopPackagedApplication(
        _ application: XCUIApplication,
        bundleURL: URL
    ) -> Bool {
        let expectedURL = bundleURL.standardizedFileURL
        func matchingApplications() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.scholium.app"
            ).filter { $0.bundleURL?.standardizedFileURL == expectedURL }
        }

        application.terminate()
        if waitUntil(timeout: 10) { matchingApplications().isEmpty } {
            return true
        }
        matchingApplications().forEach { $0.forceTerminate() }
        return waitUntil(timeout: 10) { matchingApplications().isEmpty }
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
