@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

/// External driver for the frozen RDF-1 performance protocol. This class does
/// not create fixtures, package Scholium, or decide whether a run is a release
/// gate. `run-performance-benchmarks.sh` owns those fail-closed checks and
/// invokes this single method against an explicitly registered app bundle.
final class ScholiumPerformanceUITests: XCTestCase {
    private enum WarmReadScrollDirection {
        case towardEarlierRows
        case towardLaterRows
    }

    private enum Metric: String {
        case warmLibraryLaunch = "warm_library_launch"
        case indexedSearch = "indexed_search"
        case warmReadActivation = "warm_read_activation"
        case firstReadActivation = "first_read_activation"
        case editorKeyToPaint = "editor_key_to_paint"
        case editorModeTransition = "editor_mode_transition"
        case editorCachedPreview = "editor_cached_preview"
        case warmEditActivation = "warm_edit_activation"
        case coldEditActivation = "cold_edit_activation"
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

            if metric != .firstReadActivation {
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
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
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
        let modeMenu = application.descendants(matching: .any)["scholium.documentModeButton"]
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
                (modeMenu.value as? String) == (finalModeIsSource ? "Source" : "Edit")
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
            "--scholium-performance-editor-mode-notifications",
        ]
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = fixtureRoot
        application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = "cjk-\(runID)"
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
        let modeMenu = application.descendants(matching: .any)["scholium.documentModeButton"]
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
        try paste(beginningToken, into: application)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (editor.value as? String)?.contains(beginningToken) == true
            }
        )
        application.typeKey("z", modifierFlags: [.command])

        for _ in 0..<24 { application.typeKey(.pageDown, modifierFlags: []) }
        let middleToken = "QA-CJK-MIDDLE-\(UUID().uuidString)"
        try paste(middleToken, into: application)
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                (editor.value as? String)?.contains(middleToken) == true
            }
        )
        application.typeKey("z", modifierFlags: [.command])

        let endToken = "QA-CJK-END-\(UUID().uuidString)"
        application.typeKey(.end, modifierFlags: [.command])
        try paste(endToken, into: application)
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
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        if metric == .editorModeTransition
            || metric == .editorCachedPreview
            || metric == .warmEditActivation
            || metric == .editorVisibleProjection {
            application.launchArguments.append(
                "--scholium-performance-editor-mode-notifications"
            )
        }
        application.launchEnvironment["SCHOLIUM_HOME"] = homeRoot
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeRoot
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
        case .firstReadActivation:
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "output"
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "Long/Canonical-5000-Word-Work.md"
        case .editorKeyToPaint, .editorModeTransition, .editorCachedPreview,
             .warmEditActivation, .coldEditActivation, .editorVisibleProjection:
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
        case .warmLibraryLaunch, .firstReadActivation, .coldEditActivation:
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
        if metric == .editorModeTransition || metric == .editorKeyToPaint
            || metric == .editorCachedPreview
            || metric == .warmEditActivation
            || metric == .editorVisibleProjection {
            application.typeKey("r", modifierFlags: [.command])
            let modeMenu = application.descendants(matching: .any)[
                "scholium.documentModeButton"
            ]
            XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    (modeMenu.value as? String) == "Edit"
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
                        (modeMenu.value as? String) == "Review"
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
                Thread.sleep(forTimeInterval: 0.5)
            }
            return
        }
        application.typeKey("f", modifierFlags: [.command, .shift])
        let field = application.descendants(matching: .any)["scholium.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        replaceCommittedText("scopeSetup", in: field, application: application)
        let thisVault = application.buttons["scholium.searchScope.currentVault"]
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
        case .warmLibraryLaunch, .firstReadActivation, .coldEditActivation:
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
            scrollReadTargetIntoView(
                target,
                in: application,
                sample: sample,
                role: "measured",
                direction: .towardEarlierRows
            )
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
                scrollReadTargetIntoView(
                    alternate,
                    in: application,
                    sample: sample,
                    role: "alternate",
                    direction: .towardLaterRows
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
            let modeMenu = application.descendants(matching: .any)[
                "scholium.documentModeButton"
            ]
            let accessibilityLabel = sourceMode
                ? "Markdown source editor"
                : "Markdown editor, Edit mode"
            XCTAssertTrue(modeMenu.waitForExistence(timeout: 10))
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    (modeMenu.value as? String) == (sourceMode ? "Source" : "Edit")
                        && application.descendants(matching: .any)[accessibilityLabel].exists
                },
                "Sample \(sample): the measured Editor mode was not accessible after publication."
            )
        case .editorCachedPreview:
            requestPerformanceEditorAction("cached-preview")
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    self.lineCount(at: resultsPath) == sample + 1
                },
                "Sample \(sample): cached preview did not publish exactly one performance record."
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
            let modeMenu = application.descendants(matching: .any)[
                "scholium.documentModeButton"
            ]
            XCTAssertTrue(
                waitUntil(timeout: 20) {
                    (modeMenu.value as? String) == "Edit"
                        && application.descendants(matching: .any)[
                            "Markdown editor, Edit mode"
                        ].exists
                }
            )
            if sample + 1 < total {
                requestPerformanceEditorAction("review")
                XCTAssertTrue(
                    waitUntil(timeout: 20) {
                        (modeMenu.value as? String) == "Review"
                    }
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
    private func performFirstReadActivation(
        in application: XCUIApplication,
        resultsPath: String,
        sample: Int
    ) {
        let noDocumentState = application.descendants(matching: .any)[
            "scholium.noDocumentState"
        ]
        XCTAssertTrue(
            noDocumentState.waitForExistence(timeout: 30),
            "Sample \(sample): cold launch did not settle on an empty Workspace."
        )

        let folder = application.descendants(matching: .any)[
            "scholium.folderRow.Long"
        ]
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        scrollReadTargetIntoView(
            folder,
            in: application,
            sample: sample,
            role: "first-use folder",
            direction: .towardLaterRows
        )
        if (folder.value as? String) != "Expanded" {
            folder.click()
        }

        let documentID = "Long/Canonical-5000-Word-Work.md"
        let target = application.descendants(matching: .any)[
            "scholium.noteRow.\(documentID)"
        ]
        XCTAssertTrue(target.waitForExistence(timeout: 15))
        scrollReadTargetIntoView(
            target,
            in: application,
            sample: sample,
            role: "first-use document",
            direction: .towardLaterRows
        )
        XCTAssertTrue(
            noDocumentState.exists,
            "Sample \(sample): setup selected a document before the measured action."
        )

        target.click()
        XCTAssertTrue(
            waitForRenderedDocument(documentID, in: application, timeout: 60),
            "Sample \(sample): the first selected Review document did not render."
        )
        XCTAssertTrue(
            waitUntil(timeout: 60) { self.lineCount(at: resultsPath) == sample + 1 },
            "Sample \(sample): first Review did not publish exactly one performance record."
        )
    }

    /// Reconciles the native Sidebar viewport before a measured Note click.
    /// `PerformanceProbe.beginReadActivation` starts inside the click action,
    /// so these setup swipes never enter the Read duration. Offscreen
    /// NSOutlineView rows expose document rather than viewport coordinates;
    /// the caller therefore supplies the frozen RDF-1 row-order direction.
    @MainActor
    private func scrollReadTargetIntoView(
        _ target: XCUIElement,
        in application: XCUIApplication,
        sample: Int,
        role: String,
        direction: WarmReadScrollDirection
    ) {
        let noteList = application.descendants(matching: .any)[
            "scholium.noteList"
        ].firstMatch
        XCTAssertTrue(
            noteList.waitForExistence(timeout: 10),
            "Sample \(sample): the native Note list did not remain accessible."
        )

        func isVisiblyHittable() -> Bool {
            guard target.isHittable else { return false }
            let intersection = target.frame.intersection(noteList.frame)
            return !intersection.isNull
                && intersection.width >= 8
                && intersection.height >= 8
        }

        for _ in 0..<12 where !isVisiblyHittable() {
            switch direction {
            case .towardEarlierRows:
                noteList.swipeDown(velocity: .slow)
            case .towardLaterRows:
                noteList.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(
            isVisiblyHittable(),
            "Sample \(sample): the \(role) Read target did not become visibly hittable."
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
        let notificationName = title == "Edit"
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

    @MainActor
    private func requestMeasuredEditorMode(
        _ title: String
    ) {
        let notificationName = title == "Edit"
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
    private func paste(_ text: String, into application: XCUIApplication) throws {
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
        application.typeKey("v", modifierFlags: [.command])
    }

    @MainActor
    private func selectCJKDocumentMode(
        _ title: String,
        accessibilityLabel: String,
        modeMenu: XCUIElement,
        application: XCUIApplication,
        documentID: String
    ) {
        if (modeMenu.value as? String) != title {
            let notificationName = title == "Edit"
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
                (modeMenu.value as? String) == title
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

/// External, read-only launch driver for the release-to-release Triptych
/// integrity gate. `verify-qa-upgrade-safety.sh` owns fixture copying, exact
/// manifests, process serialization, and evidence retention.
