@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

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
        let modeMenu = application.descendants(matching: .any)["scholium.documentModeMenu"]
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 30))
        selectEditorMode(
            "Edit",
            accessibilityLabel: "Markdown editor, Edit mode",
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
                sourceMode ? "Source" : "Edit",
                accessibilityLabel: sourceMode
                    ? "Markdown source editor"
                    : "Markdown editor, Edit mode",
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
