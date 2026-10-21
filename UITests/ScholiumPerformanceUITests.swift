import AppKit
import CryptoKit
import Vision
@preconcurrency import XCTest
import notify

/// External driver for the frozen RDF-1 performance protocol. This class does
/// not create the frozen RDF-1, package Scholium, or decide whether a run is a release
/// gate. `run-performance-benchmarks.sh` owns those fail-closed checks and
/// invokes this single method against an explicitly registered app bundle.
final class ScholiumPerformanceUITests: XCTestCase {
    @MainActor
    func testVisibleStressLongProseDiagnostic() throws {
        try visibleStressEditingDiagnostic("long_prose")
    }

    @MainActor
    func testVisibleStressDenseLinksDiagnostic() throws {
        try visibleStressEditingDiagnostic("dense_links")
    }

    @MainActor
    func testVisibleStressImageGalleryDiagnostic() throws {
        try visibleStressEditingDiagnostic("image_gallery")
    }

    /// Opt-in foreground journey, independent of the frozen RDF-1 gate.
    /// Native readiness and screenshot observation are separate endpoints;
    /// optional WindowServer frames are analyzed offline, outside this driver.
    @MainActor
    func testForegroundNoteOpeningDiagnostic() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let label = environment["SCHOLIUM_FOREGROUND_OPEN_LABEL"] else {
            throw XCTSkip("The isolated foreground note-opening diagnostic is not configured.")
        }
        guard !label.isEmpty, label.utf8.count <= 32,
            label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else {
            throw NSError(
                domain: "ScholiumUITests.ForegroundOpening", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "An ASCII diagnostic label of at most 32 characters is required."])
        }
        let startWithAlternate = environment["SCHOLIUM_FOREGROUND_OPEN_INITIAL_ALTERNATE"] == "1"
        let retainTarget = environment["SCHOLIUM_FOREGROUND_OPEN_RETAIN_TARGET"] == "1"
        let opensNewTab = environment["SCHOLIUM_FOREGROUND_OPEN_NEW_TAB"] == "1"
        let openingMode = environment["SCHOLIUM_FOREGROUND_OPEN_MODE"] ?? "Edit"
        XCTAssertTrue(["Edit", "Review"].contains(openingMode))
        let includesNewTab = environment["SCHOLIUM_FOREGROUND_OPEN_INCLUDE_NEW_TAB"] == "1"
        let includesModes = environment["SCHOLIUM_FOREGROUND_OPEN_INCLUDE_MODES"] == "1"
        XCTAssertFalse(
            includesNewTab && (opensNewTab || startWithAlternate || retainTarget),
            "The combined journey starts without a selected document and finishes with one new-tab opening.")
        let sampleCount = includesNewTab ? 4 : (opensNewTab ? 1 : 3)
        let nativeMetric = "note_open_to_visible"
        if opensNewTab { XCTAssertTrue(startWithAlternate && retainTarget) }
        try requireQAPreferencePreservation()
        continueAfterFailure = false
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixture = repository.appendingPathComponent(".build/qa-runtime/fixtures").standardizedFileURL.resolvingSymlinksInPath()
        for (directory, count) in [("01-analyses", 160), ("02-topics", 220), ("03-works", 120)] {
            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: fixture.appendingPathComponent(directory), includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]))
            XCTAssertEqual(
                enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }.count, count,
                "Use the disposable standard 500-note Triptych, with three separate vaults.")
        }
        let targetID = "QA Autosave A.md"
        let alternateID = "QA Autosave B.md"
        let note = fixture.appendingPathComponent("01-analyses/\(targetID)")
        let alternate = fixture.appendingPathComponent("01-analyses/\(alternateID)")
        let original = try Data(contentsOf: note)
        let alternateOriginal = try Data(contentsOf: alternate)
        let sentinel = "quartz amber lantern fifty seven"
        XCTAssertFalse(String(decoding: original, as: UTF8.self).contains(sentinel), "The fixture must have no sentinel left from an earlier run.")
        // Long-fixture returns restore a body viewport; recognize a unique
        // recurring target paragraph without resetting the user's scroll.
        let recognitionSentinel = original.count > 100_000 ? "Synthetic structure" : sentinel
        let bodyAnchor = try XCTUnwrap(original.range(of: Data("Synthetic nonprivate QA fixture.".utf8)))
        let newline = original.range(of: Data("\r\n".utf8)) == nil ? "\n" : "\r\n"
        let prepared =
            original.prefix(upTo: bodyAnchor.upperBound)
            + Data("\(newline)\(newline)\(sentinel)".utf8) + original.suffix(from: bodyAnchor.upperBound)
        let bundle = repository.appendingPathComponent(".build/qa-runtime/registered/Scholium-Codex-QA-Do-Not-Use.app")
        XCTAssertEqual(Bundle(url: bundle)?.bundleIdentifier, "com.scholium.qa")
        let application = XCUIApplication(url: bundle)
        let cleanup: @MainActor () throws -> Void = {
            application.terminate()
            if application.state == .notRunning {
                try original.write(to: note, options: .atomic)
            } else {
                XCTFail("The disposable target is retained because QA termination was not confirmed.")
            }
        }
        addTeardownBlock { try await cleanup() }
        try prepared.write(to: note, options: .atomic)
        let runID = "foreground-\(label)-\(UUID().uuidString)"
        let run = repository.appendingPathComponent(".build/performance-\(runID)/app-state")
        let raw = run.appendingPathComponent("raw")
        let home = run.appendingPathComponent("home")
        for directory in [raw, home] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let result = raw.appendingPathComponent("note-opening.jsonl")
        let webResult = raw.appendingPathComponent("note-opening.web.jsonl")
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "--scholium-performance-editor-mode-notifications"]
        application.launchEnvironment = [
            "SCHOLIUM_HOME": home.path, "CFFIXED_USER_HOME": home.path,
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixture.path,
            "SCHOLIUM_UI_TEST_OPEN_SLOT": "paper_analysis",
            "SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1380",
            "SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS": "300000",
            "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
            "SCHOLIUM_PERFORMANCE_METRIC": nativeMetric,
            "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
            "SCHOLIUM_PERFORMANCE_SAMPLE": "0", "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": String(sampleCount),
            "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": targetID,
            "SCHOLIUM_PERFORMANCE_INITIAL_REVIEW": openingMode == "Review" ? "1" : "0",
        ]
        application.launch()
        let window = application.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let editor = application.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        let modeControl = documentModeControl(in: application)
        func openingSurfaceIsReady(_ documentID: String) -> Bool {
            guard self.documentModeState(modeControl) == openingMode else { return false }
            return openingMode == "Review"
                ? self.waitForRenderedDocument(documentID, in: application, timeout: 0.1)
                : editor.exists
        }
        let target = nativeLibraryRow("scholium.noteRow.\(targetID)", in: application)
        let other = nativeLibraryRow("scholium.noteRow.\(alternateID)", in: application)
        XCTAssertTrue(target.waitForExistence(timeout: 60))
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        // The explicit probe setup arms Review in the workspace-opening owner
        // before Library readiness. An empty workspace intentionally has no mode
        // toolbar control, so observing that absent control cannot be a barrier.
        XCTAssertTrue(application.descendants(matching: .any)["scholium.noDocumentState"].waitForExistence(timeout: 30))
        XCTAssertFalse(editor.exists, "Setup must start without an editor before the first real Library selection.")
        if startWithAlternate {
            // Warm only B through the ordinary Library route; A must remain
            // unseen until the measured new-tab action.
            other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(
                waitUntil(timeout: 60) {
                    window.title == "QA Autosave B" && other.isSelected && modeControl.exists
                        && openingSurfaceIsReady(alternateID)
                }, "The initial Library selection must finish loading B in the requested mode before measurement.")
            XCTAssertTrue(
                waitUntil(timeout: 60) { !application.descendants(matching: .any)["scholium.refreshStatus"].exists },
                "Untimed setup must finish derived-state refresh before presenting the new-tab menu.")
            if openingMode == "Edit" {
                editor.click()
                XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor))
            }
        }
        XCTAssertEqual(lineCount(at: result.path), 0)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.qa")
        XCTAssertEqual(running.count, 1, "Exactly one isolated QA application may run.")
        let process = try XCTUnwrap(running.first)
        XCTAssertEqual(process.bundleURL?.standardizedFileURL.resolvingSymlinksInPath(), bundle.standardizedFileURL.resolvingSymlinksInPath())
        let requestDirectory = environment["SCHOLIUM_FOREGROUND_FRAME_REQUEST_DIRECTORY"].map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath()
        }
        if let requestDirectory {
            XCTAssertTrue(
                requestDirectory.path.hasPrefix(
                    repository.appendingPathComponent(".build").standardizedFileURL.resolvingSymlinksInPath().path + "/"))
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: requestDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
                "The parent capture supervisor must create its isolated request directory.")
        }
        var observations: [[String: Any]] = []
        func openAlternateInNewTab() {
            other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
            let menu = application.menus["scholium.noteRow.\(alternateID)"]
            XCTAssertTrue(menu.waitForExistence(timeout: 3))
            menu.menuItems["Open in New Tab"].click()
        }
        for sample in 0..<sampleCount {
            let sampleOpensNewTab = opensNewTab || (includesNewTab && sample == sampleCount - 1)
            if sample > 0 {
                if retainTarget && sample == 1 { openAlternateInNewTab() } else { other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click() }
                XCTAssertTrue(
                    waitUntil(timeout: 60) {
                        window.title == "QA Autosave B" && other.isSelected && openingSurfaceIsReady(alternateID)
                    })
                if openingMode == "Edit" {
                    editor.click()
                    XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor))
                }
                XCTAssertEqual(lineCount(at: result.path), sample, "Alternate clicks must not complete target attempts.")
            }
            let directory = raw.appendingPathComponent("sample-\(sample)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let before = window.screenshot()
            try before.pngRepresentation.write(to: directory.appendingPathComponent("before.png"))
            XCTAssertFalse(
                try foregroundScreenshotContains(recognitionSentinel, png: before.pngRepresentation),
                "The outgoing document must not already display the target body sentinel.")
            // Native NSOutlineView row containers do not expose a hittable
            // AX action; use the same row-center mouse route as other journeys.
            XCTAssertTrue(
                target.frame.width > 0 && target.frame.height > 0 && window.frame.intersects(target.frame),
                "The actual Library row must have on-window geometry before capture starts.")
            let point = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let targetMenu = application.menus["scholium.noteRow.\(targetID)"]
            var newTabPoint: XCUICoordinate?
            if sampleOpensNewTab {
                point.rightClick()
                XCTAssertTrue(targetMenu.waitForExistence(timeout: 3))
                let item = targetMenu.menuItems["Open in New Tab"]
                XCTAssertTrue(item.exists && item.frame.width > 0 && item.frame.height > 0)
                // Use the observed menu item's real pointer position, matching
                // the Library row's pointer route.
                newTabPoint = item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            }
            var captureRequest: (stop: URL, finished: URL)?
            func stopRecorder() {
                guard let request = captureRequest else { return }
                captureRequest = nil
                do {
                    try Data().write(to: request.stop, options: .atomic)
                } catch {
                    XCTFail("The capture stop request could not be written: \(error)")
                    return
                }
                let stopped = waitUntil(timeout: 20) { FileManager.default.fileExists(atPath: request.finished.path) }
                XCTAssertTrue(stopped, "The parent capture supervisor must finish before the next attempt.")
                if stopped {
                    do {
                        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: request.finished)) as? [String: Any])
                        XCTAssertEqual(receipt["exit_code"] as? Int, 0, "The parent-owned frame capture must exit successfully.")
                    } catch { XCTFail("The capture completion receipt is invalid: \(error)") }
                }
            }
            defer { stopRecorder() }
            if let requestDirectory {
                let frames = directory.appendingPathComponent("frames")
                let identifier = UUID().uuidString
                let request = requestDirectory.appendingPathComponent("\(identifier).request.json")
                let finished = requestDirectory.appendingPathComponent("\(identifier).finished.json")
                captureRequest = (requestDirectory.appendingPathComponent("\(identifier).stop"), finished)
                try JSONSerialization.data(
                    withJSONObject: [
                        "schema": 1, "pid": process.processIdentifier, "output": frames.path,
                    ], options: [.sortedKeys]
                ).write(to: request, options: .atomic)
                XCTAssertTrue(
                    waitUntil(timeout: 15) {
                        FileManager.default.fileExists(atPath: frames.appendingPathComponent("ready").path)
                            || FileManager.default.fileExists(atPath: finished.path)
                    })
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: finished.path),
                    "The capture supervisor must remain active until the observation finishes.")
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: frames.appendingPathComponent("ready").path),
                    "Window capture must be ready before the real Library click.")
            }
            XCTAssertEqual(application.state, .runningForeground, "Display measurements require the QA application in the foreground.")
            let refreshVisible = application.descendants(matching: .any)["scholium.refreshStatus"].exists
            let actionStarted = DispatchTime.now().uptimeNanoseconds
            if let newTabPoint { newTabPoint.click() } else { point.click() }
            let actionReturned = DispatchTime.now().uptimeNanoseconds
            let nativeCompleted = waitUntil(timeout: 10) { self.lineCount(at: result.path) == sample + 1 }
            if !nativeCompleted {
                _ = notify_post("com.scholium.qa.performance-note-opening-web-samples")
                let pending = result.deletingPathExtension().appendingPathExtension("pending.jsonl")
                _ = waitUntil(timeout: 3) { FileManager.default.fileExists(atPath: pending.path) }
            }
            XCTAssertTrue(
                nativeCompleted,
                "Each target click must complete exactly one current native opening attempt.")
            // Keep screenshot capture and Vision away from the measured render.
            // Offline analysis rejects any match arriving after this quiet period.
            // Reader readiness can precede shared-host publication. Keep the
            // recorder passive through that handoff before taking a screenshot.
            Thread.sleep(forTimeInterval: 1)
            let firstScreenshotStarted = DispatchTime.now().uptimeNanoseconds
            var captures: [[String: Any]] = []
            var recognized = false
            var lastScreenshot = Data()
            var observed: UInt64 = actionReturned
            for capture in 0..<8 {
                let screen = window.screenshot()
                lastScreenshot = screen.pngRepresentation
                observed = DispatchTime.now().uptimeNanoseconds
                recognized = try foregroundScreenshotContains(recognitionSentinel, png: screen.pngRepresentation)
                captures.append(["capture": capture, "capture_return_uptime_ns": observed, "body_recognized": recognized])
                if capture == 0 { try screen.pngRepresentation.write(to: directory.appendingPathComponent("first-after.png")) }
                if recognized {
                    try screen.pngRepresentation.write(to: directory.appendingPathComponent("after.png"))
                    break
                }
            }
            if !recognized {
                try lastScreenshot.write(to: directory.appendingPathComponent("last-after.png"))
                stopRecorder()
            }
            XCTAssertTrue(recognized, "The target's unique body must appear in actual screenshot pixels.")
            let native = try foregroundLastRecord(at: result)
            XCTAssertEqual(native["run_id"] as? String, runID)
            XCTAssertEqual(native["sample"] as? Int, sample)
            XCTAssertEqual(native["metric"] as? String, nativeMetric)
            let surfaceIsAccessible = waitUntil(timeout: 10) { openingSurfaceIsReady(targetID) }
            if !surfaceIsAccessible {
                let labels = application.textViews.allElementsBoundByIndex.prefix(8).map(\.label)
                print("FOREGROUND_OPEN_AX_FAILURE mode=\(openingMode) reported_mode=\(modeControl.label) text_views=\(labels)")
            }
            XCTAssertTrue(surfaceIsAccessible, "The mode-specific document surface must become accessible after native readiness.")
            let nativeEnd = try XCTUnwrap((native["completed_uptime_ns"] as? NSNumber)?.uint64Value)
            XCTAssertGreaterThanOrEqual(nativeEnd, actionStarted)
            XCTAssertNotNil(native["duration_ms"] as? Double)
            do {
                XCTAssertEqual(notify_post("com.scholium.qa.performance-note-opening-web-samples"), UInt32(NOTIFY_STATUS_OK))
                XCTAssertTrue(
                    waitUntil(timeout: 30) { self.lineCount(at: webResult.path) == sample + 1 },
                    "Collect Web phases before the alternate click invalidates this completed attempt.")
                let web = try foregroundLastRecord(at: webResult)
                XCTAssertEqual(web["run_id"] as? String, runID)
                XCTAssertEqual(web["sample"] as? Int, sample)
                XCTAssertFalse(try XCTUnwrap(web["samples"] as? [[String: Any]]).isEmpty)
            }
            if let captureRequest {
                XCTAssertFalse(
                    FileManager.default.fileExists(atPath: captureRequest.finished.path),
                    "The recorder must cover the complete observation interval.")
            }
            stopRecorder()
            if requestDirectory != nil {
                let capture = try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: Data(
                            contentsOf:
                                directory.appendingPathComponent("frames/capture-summary.json"))) as? [String: Any])
                XCTAssertGreaterThan(try XCTUnwrap(capture["captured_frames"] as? Int), 0)
                XCTAssertEqual(capture["overflow_frames"] as? Int, 0, "Capture overflow invalidates this display sample.")
                XCTAssertEqual(capture["errors"] as? Int, 0, "Capture errors invalidate this display sample.")
            }
            let observation: [String: Any] = [
                "sample": sample,
                "mode": openingMode,
                "kind": sampleOpensNewTab
                    ? "new_tab_first_open"
                    : (sample == 0 ? (startWithAlternate ? "first_switch" : "cold_first_open") : (retainTarget ? "retained_tab_return" : "replace_return")),
                "driver_action_start_uptime_ns": actionStarted, "driver_action_return_uptime_ns": actionReturned,
                "screenshot_observation_upper_bound_ms": Double(observed - actionStarted) / 1_000_000,
                "target_body_recognized": recognized, "captures": captures, "native": native,
                "native_boundary": sampleOpensNewTab
                    ? "Native Open in New Tab handler to validated native stable-visible layout."
                    : "AppKit Library mouseDown handler to validated native stable-visible layout.",
                "first_screenshot_start_uptime_ns": firstScreenshotStarted,
                "passive_frame_interval_before_screenshot": true,
                "window_server_frames_enabled": requestDirectory != nil,
                "background_refresh_visible_before_click": refreshVisible,
            ]
            observations.append(observation)
            try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("observations.json"), options: .atomic)
            XCTAssertEqual(try Data(contentsOf: note), prepared)
            XCTAssertEqual(try Data(contentsOf: alternate), alternateOriginal)
        }
        var modeObservations: [[String: Any]] = []
        if includesModes {
            modeObservations = try foregroundModeSwitches(
                in: application, window: window, documentID: targetID,
                raw: raw, requestDirectory: requestDirectory, pid: process.processIdentifier,
                modeControl: modeControl, originalSource: prepared, sourceURL: note)
        }
        // This correctness phase is deliberately outside every timed sample.
        if documentModeState(modeControl) != "Edit" {
            requestPerformanceEditorAction("activation")
            XCTAssertTrue(waitUntil(timeout: 60) { self.documentModeState(modeControl) == "Edit" && editor.exists })
        }
        editor.click()
        XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor))
        let beforeEditValue = try XCTUnwrap(editor.value as? String)
        application.typeKey(.end, modifierFlags: .command)
        let edit = "9"
        application.typeKey(edit, modifierFlags: [])
        application.typeKey("s", modifierFlags: .command)
        let edited = prepared + Data(edit.utf8)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == edited })
        let afterEditValue = try XCTUnwrap(editor.value as? String)
        XCTAssertNotEqual(afterEditValue, beforeEditValue)
        if includesModes {
            // Review must flush the exact current source without ending history.
            requestPerformanceEditorAction("review")
            XCTAssertTrue(
                waitUntil(timeout: 60) {
                    self.documentModeState(modeControl) == "Review"
                        && self.waitForRenderedDocument(targetID, in: application, timeout: 0.1)
                })
            XCTAssertEqual(try Data(contentsOf: note), edited)
            requestPerformanceEditorAction("activation")
            XCTAssertTrue(waitUntil(timeout: 60) { self.documentModeState(modeControl) == "Edit" && editor.exists })
        }
        if retainTarget { openAlternateInNewTab() } else { other.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click() }
        XCTAssertTrue(waitUntil(timeout: 60) { window.title == "QA Autosave B" && other.isSelected })
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                window.title == "QA Autosave A" && editor.exists
            })
        editor.click()
        let beforeUndoValue = editor.value as? String
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String != beforeUndoValue })
        application.typeKey("s", modifierFlags: .command)
        let undone = waitUntil(timeout: 10) { (try? Data(contentsOf: note)) == prepared }
        if !undone { try Data(contentsOf: note).write(to: raw.appendingPathComponent("undo-observed.md")) }
        XCTAssertTrue(undone, "A single-key Undo must survive ordinary replacement as well as retained tabs.")
        let beforeRedoValue = editor.value as? String
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String != beforeRedoValue })
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == edited }, "Redo must preserve exact source after returning.")
        let beforeFinalUndoValue = editor.value as? String
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String != beforeFinalUndoValue })
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == prepared })
        XCTAssertEqual(try Data(contentsOf: alternate), alternateOriginal)
        XCTAssertEqual(lineCount(at: result.path), sampleCount)
        let report: [String: Any] = [
            "label": label, "run_id": runID, "fixture_notes": 500, "target": targetID, "alternate": alternateID,
            "body_sentinel": recognitionSentinel, "initial_alternate": startWithAlternate, "retain_target": retainTarget,
            "opens_new_tab": opensNewTab, "includes_new_tab": includesNewTab,
            "mode": openingMode, "samples": observations, "mode_samples": modeObservations,
            "source_sha256": SHA256.hash(data: prepared).map { String(format: "%02x", $0) }.joined(),
            "qa_binary_sha256": SHA256.hash(data: try Data(contentsOf: bundle.appendingPathComponent("Contents/MacOS/Scholium"))).map {
                String(format: "%02x", $0)
            }.joined(),
            "post_measurement_exact_save_navigation_undo_redo": true,
            "post_measurement_review_preserves_undo": includesModes,
            "native_boundary": opensNewTab
                ? "Native Open in New Tab handler to validated native stable-visible layout; excludes prior event/menu transport, does not require keyboard focus and does not acknowledge pixels."
                : "AppKit Library mouseDown handler to validated native stable-visible layout; excludes prior OS event queue, does not require keyboard focus and does not acknowledge pixels.",
            "screenshot_boundary":
                "Before XCTest Library click to recognized screenshot return; includes XCTest transport/idling, capture and earlier OCR/write work. Conservative upper bound only.",
            "frame_boundary":
                "Optional QA-window-only SCStream frames retain WindowServer displayTime converted to uptime nanoseconds. Offline body recognition is required; this is not physical panel scanout.",
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: raw.appendingPathComponent("observations.json"), options: .atomic)
        print("FOREGROUND_OPEN_DIAGNOSTIC label=\(label) mode=\(openingMode) samples=\(sampleCount) mode_samples=\(modeObservations.count) raw=\(raw.path)")
    }

    /// Shares the opening recorder but measures mode requests independently.
    /// Pixel timing is established offline from both the mode-control crop and
    /// a settled body reference; a persistent body phrase alone cannot prove a mode change.
    @MainActor
    private func foregroundModeSwitches(
        in application: XCUIApplication, window: XCUIElement, documentID: String,
        raw: URL, requestDirectory: URL?, pid: pid_t, modeControl: XCUIElement,
        originalSource: Data, sourceURL: URL
    ) throws -> [[String: Any]] {
        var observations: [[String: Any]] = []
        for destination in ["Review", "Edit", "Source", "Edit", "Review", "Edit"] {
            let origin = try XCTUnwrap(documentModeState(modeControl))
            if origin == destination { continue }
            let directory = raw.appendingPathComponent("mode-\(observations.count)-\(origin.lowercased())-\(destination.lowercased())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var request: (stop: URL, finished: URL)?
            func stopCapture() throws {
                guard let active = request else { return }
                request = nil
                try Data().write(to: active.stop, options: .atomic)
                XCTAssertTrue(waitUntil(timeout: 20) { FileManager.default.fileExists(atPath: active.finished.path) })
                let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: active.finished)) as? [String: Any])
                XCTAssertEqual(receipt["exit_code"] as? Int, 0)
                let summaryURL = directory.appendingPathComponent("frames/capture-summary.json")
                let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: summaryURL)) as? [String: Any])
                XCTAssertGreaterThan(try XCTUnwrap(summary["captured_frames"] as? Int), 0)
                XCTAssertEqual(summary["errors"] as? Int, 0)
                XCTAssertEqual(summary["overflow_frames"] as? Int, 0)
            }
            defer {
                if request != nil {
                    do { try stopCapture() } catch { XCTFail("Mode frame capture cleanup failed: \(error)") }
                }
            }
            if let requestDirectory {
                let identifier = UUID().uuidString
                let frames = directory.appendingPathComponent("frames")
                let finished = requestDirectory.appendingPathComponent("\(identifier).finished.json")
                request = (requestDirectory.appendingPathComponent("\(identifier).stop"), finished)
                try JSONSerialization.data(withJSONObject: ["schema": 1, "pid": pid, "output": frames.path], options: [.sortedKeys])
                    .write(to: requestDirectory.appendingPathComponent("\(identifier).request.json"), options: .atomic)
                XCTAssertTrue(
                    waitUntil(timeout: 15) {
                        FileManager.default.fileExists(atPath: frames.appendingPathComponent("ready").path)
                            || FileManager.default.fileExists(atPath: finished.path)
                    })
                XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: frames.appendingPathComponent("ready").path))
            }
            XCTAssertEqual(application.state, .runningForeground)
            let controlFrame = modeControl.frame
            let windowFrame = window.frame
            let modeCrop: [String: Double] = [
                "x": (controlFrame.minX - windowFrame.minX) / windowFrame.width,
                "y": (controlFrame.minY - windowFrame.minY) / windowFrame.height,
                "width": controlFrame.width / windowFrame.width,
                "height": controlFrame.height / windowFrame.height,
            ]
            let actionStarted = DispatchTime.now().uptimeNanoseconds
            switch destination {
            case "Review": requestPerformanceEditorAction("review")
            case "Edit": requestMeasuredEditorMode("Edit")
            default: requestMeasuredEditorMode("Source")
            }
            let actionReturned = DispatchTime.now().uptimeNanoseconds
            let accessible = waitUntil(timeout: 60) {
                guard self.documentModeState(modeControl) == destination else { return false }
                switch destination {
                case "Review": return self.waitForRenderedDocument(documentID, in: application, timeout: 0.1)
                case "Edit": return application.descendants(matching: .any)["Markdown editor, Edit mode"].exists
                default: return application.descendants(matching: .any)["Markdown source editor"].exists
                }
            }
            let accessibleObserved = DispatchTime.now().uptimeNanoseconds
            if !accessible {
                let hierarchy = String(application.debugDescription.prefix(30_000))
                let failure = XCTAttachment(string: hierarchy)
                failure.name = "Unavailable mode surface — \(origin) to \(destination)"
                failure.lifetime = .keepAlways
                add(failure)
                print("FOREGROUND_MODE_AX_FAILURE \(hierarchy)")
            }
            XCTAssertTrue(accessible, "The requested mode and its real document surface must become accessible.")
            // Capture only passive frames through this quiet interval. Screenshot
            // and offline comparison start after the recorder has released its stream.
            Thread.sleep(forTimeInterval: 1)
            let passiveIntervalEnded = DispatchTime.now().uptimeNanoseconds
            try stopCapture()
            let firstScreenshotStarted = DispatchTime.now().uptimeNanoseconds
            try window.screenshot().pngRepresentation.write(to: directory.appendingPathComponent("settled.png"))
            XCTAssertEqual(try Data(contentsOf: sourceURL), originalSource, "A display-mode change must preserve exact source.")
            let observation: [String: Any] = [
                "sample": observations.count, "origin": origin, "mode": destination,
                "kind": "mode_switch", "driver_action_start_uptime_ns": actionStarted,
                "driver_action_return_uptime_ns": actionReturned,
                "ax_ready_observed_uptime_ns": accessibleObserved,
                "ax_ready_upper_bound_ms": Double(accessibleObserved - actionStarted) / 1_000_000,
                "passive_interval_end_uptime_ns": passiveIntervalEnded,
                "first_screenshot_start_uptime_ns": firstScreenshotStarted,
                "window_server_frames_enabled": requestDirectory != nil,
                "mode_control_crop_top_left_normalized": modeCrop,
                "body_crop_top_left_normalized": ["x": 0.27, "y": 0.14, "width": 0.72, "height": 0.85],
                "pixel_endpoint_requires_offline_mode_and_body_validation": true,
                "source_preserved": true, "raw_directory": directory.path,
            ]
            try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("observations.json"), options: .atomic)
            observations.append(observation)
        }
        return observations
    }

    private func foregroundScreenshotContains(_ sentinel: String, png: Data) throws -> Bool {
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLanguages = ["en-US"]
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(data: png).perform([recognition])
        let text = recognition.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
        let normalize: (String) -> String = { String($0.lowercased().filter { $0.isLetter || $0.isNumber }) }
        return normalize(text).contains(normalize(sentinel))
    }

    private func foregroundLastRecord(at url: URL) throws -> [String: Any] {
        let line = try XCTUnwrap(String(contentsOf: url, encoding: .utf8).split(separator: "\n").last)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    /// Opt-in native diagnostic. System hitch metrics, screenshot-confirmed
    /// observation bounds, and WebKit event/post-frame-task samples are distinct.
    @MainActor
    private func visibleStressEditingDiagnostic(_ scenario: String) throws {
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Native hitch diagnostics require macOS 26 or later.")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let label = ProcessInfo.processInfo.environment["SCHOLIUM_VISIBLE_EDITOR_LABEL"] else {
            throw XCTSkip("The opt-in isolated visible Stress Notes diagnostic is not configured.")
        }
        guard ["baseline", "profile", "candidate"].contains(label) else {
            throw NSError(
                domain: "ScholiumUITests.VisibleEditor", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "An explicit baseline, profile, or candidate label is required."])
        }
        try requireQAPreferencePreservation()
        continueAfterFailure = false
        let fixture = repository.appendingPathComponent(".build/qa-runtime/fixtures")
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json"))) as? [String: Any])
        XCTAssertEqual(manifest["synthetic_nonprivate"] as? Bool, true)
        let paths = try XCTUnwrap(manifest["scenarios"] as? [String: String])
        let path = try XCTUnwrap(paths[scenario])
        let note = fixture.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard note.path.hasPrefix(fixture.standardizedFileURL.resolvingSymlinksInPath().path + "/") else {
            throw CocoaError(.fileReadNoPermission)
        }
        let original = try Data(contentsOf: note)
        let bundle = repository.appendingPathComponent(".build/qa-runtime/registered/Scholium-Codex-QA-Do-Not-Use.app")
        XCTAssertEqual(Bundle(url: bundle)?.bundleIdentifier, "com.scholium.qa")
        let application = XCUIApplication(url: bundle)
        defer {
            application.terminate()
            if application.state == .notRunning {
                XCTAssertNoThrow(try original.write(to: note, options: .atomic))
            } else {
                XCTFail("The disposable fixture is retained because QA termination was not confirmed.")
            }
        }
        let sentinel = "\n\nsampletest9"
        let prepared = original + Data(sentinel.utf8)
        try prepared.write(to: note, options: .atomic)
        let runID = "visible-\(label)-\(scenario)-\(UUID().uuidString)"
        let run = repository.appendingPathComponent(".build/performance-\(runID)/app-state")
        let raw = run.appendingPathComponent("raw")
        let home = run.appendingPathComponent("home")
        for directory in [raw, home] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let result = raw.appendingPathComponent("event-post-frame-proxy.jsonl")
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.path))
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        application.launchEnvironment = [
            "SCHOLIUM_HOME": home.path, "CFFIXED_USER_HOME": home.path,
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixture.path,
            "SCHOLIUM_UI_TEST_OPEN_SLOT": scenario == "long_prose" ? "paper_analysis" : "topic_knowledge",
            "SCHOLIUM_UI_TEST_OPEN_NOTE": path.split(separator: "/").dropFirst().joined(separator: "/"),
            "SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1380",
            "SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS": "300000",
            "SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS": "1",
            "SCHOLIUM_PERFORMANCE_RESULTS_PATH": result.path,
            "SCHOLIUM_PERFORMANCE_METRIC": "editor_key_to_paint",
            "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
            "SCHOLIUM_PERFORMANCE_SAMPLE": "0", "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "128",
            "SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT": path.split(separator: "/").dropFirst().joined(separator: "/"),
        ]
        application.launch()
        let window = application.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        let editor = application.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 600), "The generated Stress Note must expose its actual Edit surface.")
        XCTAssertTrue(waitUntil(timeout: 60) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: editor) })
        application.typeKey(.end, modifierFlags: .command)
        application.typeKey("x", modifierFlags: [])
        application.typeKey(.delete, modifierFlags: [])
        let before = window.screenshot()
        try before.pngRepresentation.write(to: raw.appendingPathComponent("before.png"))
        let started = DispatchTime.now().uptimeNanoseconds
        application.typeKey("9", modifierFlags: [])
        var observed = 0.0
        var recognized = false
        var observations: [[String: Any]] = []
        for attempt in 0..<8 {
            let screen = window.screenshot()
            observed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLanguages = ["en-US"]
            recognition.recognitionLevel = .accurate
            try VNImageRequestHandler(data: screen.pngRepresentation).perform([recognition])
            let text = recognition.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            recognized = text.lowercased().replacingOccurrences(of: " ", with: "").contains("sampletest99")
            observations.append(["capture": attempt, "capture_return_ms": observed, "typed_pixels_recognized": recognized])
            if attempt == 0 { try screen.pngRepresentation.write(to: raw.appendingPathComponent("first-after.png")) }
            if recognized {
                try screen.pngRepresentation.write(to: raw.appendingPathComponent("after.png"))
                break
            }
        }
        try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
            .write(to: raw.appendingPathComponent("screen-observations.json"), options: .atomic)
        XCTAssertTrue(recognized, "Screen pixels must show the typed result within eight native captures; AX state alone is insufficient.")
        application.typeKey(.delete, modifierFlags: [])
        editor.swipeDown(velocity: .slow)
        editor.swipeDown(velocity: .slow)
        try window.screenshot().pngRepresentation.write(to: raw.appendingPathComponent("scroll-content.png"))
        application.typeKey(.end, modifierFlags: .command)
        var gesture = 0
        let options = XCTMeasureOptions()
        options.iterationCount = label == "profile" ? 1 : 3
        measure(metrics: [XCTHitchMetric(application: application), XCTClockMetric()], options: options) {
            for _ in 0..<4 {
                application.typeKey("x", modifierFlags: [])
                application.typeKey(.delete, modifierFlags: [])
            }
            application.typeKey(.upArrow, modifierFlags: .shift)
            application.typeKey(.rightArrow, modifierFlags: [])
            for _ in 0..<3 { application.typeKey(.upArrow, modifierFlags: []) }
            for _ in 0..<3 { application.typeKey(.downArrow, modifierFlags: []) }
            editor.swipeDown(velocity: .slow)
            editor.swipeDown(velocity: .slow)
            editor.swipeUp(velocity: .slow)
            editor.swipeUp(velocity: .slow)
            application.typeKey(.end, modifierFlags: .command)
            gesture += 1
        }
        XCTAssertEqual(notify_post("com.scholium.qa.performance-memory-owner-snapshot"), UInt32(NOTIFY_STATUS_OK))
        let work = home.appendingPathComponent("qa-editor-work.jsonl")
        XCTAssertTrue(waitUntil(timeout: 15) { FileManager.default.fileExists(atPath: work.path) })
        try Data(contentsOf: work).write(to: raw.appendingPathComponent("editor-work.jsonl"))
        application.typeKey("9", modifierFlags: [])
        let edited = prepared + Data("9".utf8)
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(
            waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == edited },
            "A nonzero edit must reach the revision-checked save path with every other byte unchanged.")
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == prepared }, "Undo must restore every prepared byte.")
        application.typeKey("z", modifierFlags: [.command, .shift])
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == edited }, "Redo must restore the exact saved edit.")
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 60) { (try? Data(contentsOf: note)) == prepared })
        let proxyLines = try String(contentsOf: result, encoding: .utf8).split(separator: "\n")
        XCTAssertGreaterThanOrEqual(
            proxyLines.count, options.iterationCount * 8 + 4,
            "The current run must capture its actual native key events, rather than silently omitting WebKit proxy evidence.")
        let proxies = try proxyLines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertTrue(proxies.allSatisfy { ($0["run_id"] as? String) == runID && ($0["metric"] as? String) == "editor_key_to_paint" })
        let report: [String: Any] = [
            "scenario": scenario, "label": label, "source_bytes": original.count,
            "source_sha256": SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined(),
            "screen_observation_upper_bound_ms": observed, "typed_pixels_recognized": true,
            "screen_capture_count": observations.count,
            "screen_timing_boundary":
                "Before XCTest key action to recognized screenshot return, including event transport, XCTest idle waits, capture and any earlier OCR/write work. Upper bound only; not physical key-to-display latency.",
            "web_timing_boundary": "DOM event to animation frame followed by timer task; browser service proxy without display acknowledgement.",
            "system_metric":
                "XCTHitchMetric targeted at the isolated QA application; retained in xcresult and test log. WebContent process coverage must be checked before attributing WebKit stalls.",
            "measured_iterations": gesture, "nonzero_save_undo_redo_exact": true,
            "key_post_frame_proxy_count": proxies.count,
            "typing_location":
                "Ordinary appended prose at the end of the unchanged Stress Note; caret traversal and native wheel input also cross preceding content. Screen coverage is limited to retained viewports.",
            "qa_binary_sha256": SHA256.hash(data: try Data(contentsOf: bundle.appendingPathComponent("Contents/MacOS/Scholium"))).map {
                String(format: "%02x", $0)
            }.joined(),
            "unverified": ["physical typing latency", "installed Chinese IME", "human accessibility acceptance"],
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: raw.appendingPathComponent("observations.json"), options: .atomic)
        print("VISIBLE_STRESS_DIAGNOSTIC scenario=\(scenario) label=\(label) screen_bound_ms=\(observed) exact_source=true")
    }

    override func setUpWithError() throws {
        if let path = ProcessInfo.processInfo.environment["SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH"],
            Bundle(path: path)?.bundleIdentifier == "com.scholium.qa"
        {
            try requireQAPreferencePreservation()
        }
    }

    private let packagedIsolationArgument =
        "--scholium-performance-driver-isolation"

    /// Opt-in diagnostic for one packaged Release process at a time. The caller
    /// owns the disposable fixture/home, production-preference preservation and
    /// continuous process-memory sampler. ACKs retain each ready surface while
    /// that sampler settles; they are outside every reported action duration.
    @MainActor
    func testReleaseAppLifecycleDiagnostic() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_APP_LIFECYCLE_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("The isolated packaged App lifecycle diagnostic is not configured.")
        }
        continueAfterFailure = false
        let manager = FileManager.default
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let buildRoot = repository.appendingPathComponent(".build").resolvingSymlinksInPath().path + "/"
        func isolatedURL(_ key: String) throws -> URL {
            let url = URL(fileURLWithPath: try required(key, in: environment)).standardizedFileURL.resolvingSymlinksInPath()
            _ = try XCTUnwrap(url.path.hasPrefix(buildRoot) ? true : nil, "\(key) must stay in the disposable repository .build tree.")
            return url
        }
        let bundle = try isolatedURL("SCHOLIUM_PERFORMANCE_DRIVER_APP_PATH")
        let output = try isolatedURL("SCHOLIUM_APP_LIFECYCLE_OUTPUT")
        let acknowledgment = try isolatedURL("SCHOLIUM_APP_LIFECYCLE_ACK_PATH")
        let runID = try required("SCHOLIUM_PERFORMANCE_DRIVER_RUN_ID", in: environment)
        let runPrefix = "release-lifecycle-"
        _ = try XCTUnwrap(runID.hasPrefix(runPrefix) ? true : nil)
        _ = try XCTUnwrap(UUID(uuidString: String(runID.dropFirst(runPrefix.count))))
        // Reuse the existing packaged Release protocol: the sandbox can access
        // this App-owned Application Support root, unlike an arbitrary .build
        // home. Only this precreated, uniquely named disposable run is admitted.
        let runRoot = manager.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("Library/Application Support/Scholium/Performance Runs")
            .appendingPathComponent(runID).standardizedFileURL
        _ = try XCTUnwrap(runRoot.resolvingSymlinksInPath().path == runRoot.path ? true : nil, "The packaged run root must not redirect through a symlink.")
        let rootValues = try runRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        _ = try XCTUnwrap(rootValues.isDirectory == true && rootValues.isSymbolicLink == false ? true : nil)
        func packagedRunDirectory(_ key: String, component: String) throws -> URL {
            let expected = runRoot.appendingPathComponent(component).standardizedFileURL
            let supplied = URL(fileURLWithPath: try required(key, in: environment)).standardizedFileURL
            _ = try XCTUnwrap(
                supplied.path == expected.path && supplied.resolvingSymlinksInPath().path == expected.path ? true : nil,
                "\(key) must be exactly the precreated packaged run's \(component) directory.")
            let values = try supplied.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            _ = try XCTUnwrap(values.isDirectory == true && values.isSymbolicLink == false ? true : nil)
            return supplied
        }
        let fixture = try packagedRunDirectory("SCHOLIUM_PERFORMANCE_DRIVER_FIXTURE_ROOT", component: "fixtures")
        let home = try packagedRunDirectory("SCHOLIUM_PERFORMANCE_DRIVER_HOME_ROOT", component: "home")
        let longTurns =
            try environment["SCHOLIUM_APP_LIFECYCLE_CHAT_TURNS"].map { raw in
                let count = try XCTUnwrap(Int(raw), "The diagnostic Chat turn count must be an integer.")
                return try XCTUnwrap((36...2_000).contains(count) ? count : nil, "The diagnostic Chat turn count must be within 36...2000.")
            } ?? 36
        XCTAssertEqual(Bundle(url: bundle)?.bundleIdentifier, "com.scholium.app")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app").isEmpty)
        XCTAssertTrue(try manager.contentsOfDirectory(atPath: home.path).isEmpty, "Cold launch requires a new isolated home.")
        XCTAssertFalse(manager.fileExists(atPath: output.path))
        XCTAssertFalse(manager.fileExists(atPath: acknowledgment.path))
        try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = home.deletingLastPathComponent().appendingPathComponent("raw")
        try manager.createDirectory(at: raw, withIntermediateDirectories: true)

        func sourceDigests() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for (role, expectedCount) in [("01-analyses", 160), ("02-topics", 220), ("03-works", 120)] {
                let directory = fixture.appendingPathComponent(role)
                let enumerator = try XCTUnwrap(manager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
                let notes = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
                XCTAssertEqual(notes.count, expectedCount, "Use the complete standard 500-note Triptych in three separate vaults.")
                for note in notes {
                    result[String(note.path.dropFirst(fixture.path.count))] = Data(SHA256.hash(data: try Data(contentsOf: note)))
                }
            }
            return result
        }
        let originalDigests = try sourceDigests()
        let note = fixture.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalBytes = try Data(contentsOf: note)
        let originalSource = try XCTUnwrap(String(data: originalBytes, encoding: .utf8))
        let application = XCUIApplication(url: bundle)
        defer { application.terminate() }
        application.launchArguments = ["-ApplePersistenceIgnoreState", "YES", packagedIsolationArgument]
        application.launchEnvironment = [
            "SCHOLIUM_HOME": home.path, "CFFIXED_USER_HOME": home.path,
            "SCHOLIUM_UI_TEST_WORKSPACE_ROOT": fixture.path,
            "SCHOLIUM_UI_TEST_OPEN_SLOT": "paper_analysis",
            "SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH": "1380",
            "SCHOLIUM_PERFORMANCE_RUN_ID": runID,
            "SCHOLIUM_PERFORMANCE_METRIC": "warm_library_launch",
            "SCHOLIUM_PERFORMANCE_EXPECTED_COUNT": "160",
            "SCHOLIUM_PERFORMANCE_SAMPLE": "0", "SCHOLIUM_PERFORMANCE_SAMPLE_COUNT": "1",
        ]
        var sequence = 0
        var windowEntry = "automatic"
        var startupSampleExcluded = false
        var warmAutomaticWindowPresent: Bool?
        func mark(_ phase: String, ready: Bool = false, started: UInt64? = nil, fields: [String: Any] = [:]) throws {
            let now = DispatchTime.now().uptimeNanoseconds
            let index = sequence
            sequence += 1
            let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app")
                .filter { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == bundle }
            XCTAssertLessThanOrEqual(processes.count, 1, "Only one process may own this diagnostic bundle.")
            var record: [String: Any] = [
                "schema_version": 1, "run_id": runID, "sequence": index,
                "phase": phase, "ready": ready, "awaiting_ack": ready,
                "event": ready ? "ready" : (phase.hasSuffix("started") ? "started" : "completed"),
                "wall_time_unix_s": Date().timeIntervalSince1970, "uptime_ns": now,
                "app_pid": processes.first?.processIdentifier ?? 0,
                "bundle_path": bundle.path,
                "source_accessibility_oracle": environment["SCHOLIUM_APP_LIFECYCLE_EXPANDED_FIXTURE"] == "1"
                    ? "exact_viewport_prefix_and_file_bytes" : "full_accessibility_value_and_file_bytes",
                "window_entry": windowEntry, "startup_sample_excluded": startupSampleExcluded,
            ]
            if let warmAutomaticWindowPresent { record["warm_auto_window_present"] = warmAutomaticWindowPresent }
            if let started {
                record["action_begin_uptime_ns"] = started
                record["driver_observed_upper_bound_ms"] = Double(now - started) / 1_000_000
                record["timing_boundary"] =
                    "Before driver action to complete asserted readiness; includes LaunchServices/XCTest transport and idle waits, excludes sampler ACK. Not paint latency."
            }
            for (key, value) in fields { record[key] = value }
            let line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([0x0A])
            if !manager.fileExists(atPath: output.path) { XCTAssertTrue(manager.createFile(atPath: output.path, contents: nil)) }
            let handle = try FileHandle(forWritingTo: output)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
            print("APP_LIFECYCLE_DIAGNOSTIC sequence=\(index) phase=\(phase) ready=\(ready)")
            if ready {
                XCTAssertTrue(
                    waitUntil(timeout: 45) {
                        guard let bytes = try? Data(contentsOf: acknowledgment),
                            let line = String(data: bytes, encoding: .utf8)?.split(separator: "\n").last
                        else { return false }
                        return Int(line) == index
                    }, "The memory sampler must append \(index) and a newline after sampling \(phase).")
            }
        }
        @MainActor
        func launch(_ phase: String) async throws {
            let probe = raw.appendingPathComponent("\(phase)-library.jsonl")
            XCTAssertFalse(manager.fileExists(atPath: probe.path))
            _ = try XCTUnwrap(
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app").isEmpty ? true : nil,
                "LaunchServices must start the sole diagnostic App from a fully stopped state.")
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = probe.path
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = application.launchArguments
            configuration.activates = true
            configuration.addsToRecentItems = false
            configuration.allowsRunningApplicationSubstitution = false
            try mark("\(phase)_launch_started")
            let started = DispatchTime.now().uptimeNanoseconds
            application.launchEnvironment["SCHOLIUM_PERFORMANCE_STARTED_NS"] = String(started)
            configuration.environment = application.launchEnvironment
            let running = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
            _ = try XCTUnwrap(running.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == bundle ? true : nil)
            let executable = try XCTUnwrap(Bundle(url: bundle)?.executableURL?.standardizedFileURL.resolvingSymlinksInPath())
            _ = try XCTUnwrap(running.executableURL?.standardizedFileURL.resolvingSymlinksInPath() == executable ? true : nil)
            _ = try XCTUnwrap(running.processIdentifier > 0 && !running.isTerminated ? true : nil)
            try mark(
                "\(phase)_launch_returned",
                fields: [
                    "launch_transport": "launchservices", "launched_pid": running.processIdentifier,
                    "launch_action_begin_uptime_ns": started,
                ])
            var measurementStarted = started
            if phase == "warm" {
                let automaticWindowPresent = application.windows.firstMatch.waitForExistence(timeout: 3)
                warmAutomaticWindowPresent = automaticWindowPresent
                if !automaticWindowPresent {
                    startupSampleExcluded = true
                    windowEntry = "explicit_reopen"
                    try mark("warm_automatic_window_absent", fields: ["explicit_recovery": true])
                    measurementStarted = DispatchTime.now().uptimeNanoseconds
                    try mark(
                        "warm_explicit_reopen_started",
                        fields: [
                            "action_begin_uptime_ns": measurementStarted, "launch_action_begin_uptime_ns": started,
                            "explicit_recovery": true,
                        ])
                    let reopen = NSWorkspace.OpenConfiguration()
                    reopen.activates = true
                    reopen.addsToRecentItems = false
                    reopen.allowsRunningApplicationSubstitution = false
                    let reopened = try await NSWorkspace.shared.openApplication(at: bundle, configuration: reopen)
                    _ = try XCTUnwrap(
                        reopened.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == bundle
                            && reopened.processIdentifier == running.processIdentifier && !reopened.isTerminated ? true : nil,
                        "Explicit reopening must reuse the original diagnostic process.")
                    let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app")
                    _ = try XCTUnwrap(
                        processes.count == 1 && processes.first?.processIdentifier == running.processIdentifier ? true : nil,
                        "Explicit reopening must leave exactly the original App process running.")
                    try mark(
                        "warm_explicit_reopen_returned", fields: ["first_launch_pid": running.processIdentifier, "reopened_pid": reopened.processIdentifier])
                }
            }
            _ = try XCTUnwrap(
                application.windows.firstMatch.waitForExistence(timeout: 45) ? true : nil,
                "The launch must present a window before any later readiness can be measured.")
            declinePackagedAutomaticUpdateChecksIfOffered(in: application)
            _ = try XCTUnwrap(
                packagedNoteRow(in: application).waitForExistence(timeout: 90) ? true : nil,
                "The launch must present its fixture Library before reading a readiness sample.")
            _ = try XCTUnwrap(
                waitUntil(timeout: 30) { self.lineCount(at: probe.path) == 1 } ? true : nil,
                "The App must independently publish Library readiness for all 160 Analyses.")
            let data = try Data(contentsOf: probe)
            let sample = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(data.dropLast())) as? [String: Any])
            XCTAssertEqual(sample["metric"] as? String, "warm_library_launch")
            XCTAssertEqual(sample["run_id"] as? String, runID)
            XCTAssertEqual(sample["observed_count"] as? Int, 160)
            try mark(
                "\(phase)_library_ready", ready: true, started: measurementStarted,
                fields: [
                    "native_library_probe": probe.path, "expected_analysis_count": 160,
                    "launch_action_begin_uptime_ns": started,
                ])
        }
        func verifyIndex(_ phase: String) throws {
            try mark("\(phase)_index_started")
            let started = DispatchTime.now().uptimeNanoseconds
            let field = application.searchFields["scholium.searchField"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            replaceCommittedText("scopeSetup", in: field, application: application)
            selectResearchSearchScope("Triptych", in: application)
            replaceCommittedText("title:\"QA Autosave A\" OR title:\"QA Topic\" OR title:\"QA Work\"", in: field, application: application)
            for title in ["QA Autosave A", "QA Topic", "QA Work"] {
                let result = application.descendants(matching: .any).matching(
                    NSPredicate(
                        format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "scholium.searchResult.", "\(title),"
                    )
                ).firstMatch
                XCTAssertTrue(result.waitForExistence(timeout: 90), "The full Triptych query must resolve a current Note in each role.")
            }
            XCTAssertTrue(
                waitUntil(timeout: 90) {
                    application.descendants(matching: .any)["scholium.searchResults"].exists
                        && !application.descendants(matching: .any)["scholium.searchLoading"].exists
                        && !application.descendants(matching: .any)["scholium.searchUnavailable"].exists
                        && !application.descendants(matching: .any)["scholium.refreshStatus"].exists
                }, "Index readiness requires a completed Triptych query and completed Library refresh.")
            try mark("\(phase)_index_ready", ready: true, started: started, fields: ["query_roles": 3, "refresh_finished": true])
            clearSearchField(field, application: application)
            XCTAssertTrue(packagedNoteRow(in: application).waitForExistence(timeout: 10))
        }
        func verifySource() throws {
            packagedNoteRow(in: application).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            let mode = documentModeControl(in: application)
            XCTAssertTrue(mode.waitForExistence(timeout: 20))
            selectPackagedMode("Source", in: application, control: mode)
            let editor = application.descendants(matching: .any)["Markdown source editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 20))
            let expandedFixture = environment["SCHOLIUM_APP_LIFECYCLE_EXPANDED_FIXTURE"] == "1"
            if expandedFixture {
                // CodeMirror virtualizes long Source documents. Accessibility
                // exposes its current viewport; it is not a full-buffer oracle.
                // No editing occurs here, and every fixture file is checked by
                // exact digest before and after the complete journey.
                _ = try XCTUnwrap(
                    waitUntil(timeout: 20) {
                        guard let visible = editor.value as? String,
                            visible.contains("# QA Autosave A"), visible.utf8.count >= 128
                        else { return false }
                        return originalSource.hasPrefix(visible)
                            || (visible.hasSuffix("\n") && originalSource.hasPrefix(String(visible.dropLast())))
                    } ? true : nil, "The long Source viewport must be an exact prefix of this copied fixture.")
            } else {
                _ = try XCTUnwrap(waitUntil(timeout: 20) { self.packagedSourceAccessibilityMatches(originalSource, in: editor) } ? true : nil)
            }
            XCTAssertEqual(try Data(contentsOf: note), originalBytes)
        }
        func stop(_ phase: String) async throws {
            try mark("\(phase)_stop_started")
            let appMenu = application.menuBars.menuBarItems["Scholium"].firstMatch
            _ = try XCTUnwrap(appMenu.waitForExistence(timeout: 5) ? true : nil)
            appMenu.click()
            let quit = application.menuItems["Quit Scholium"].firstMatch
            _ = try XCTUnwrap(quit.waitForExistence(timeout: 5) && quit.isEnabled ? true : nil)
            try mark("\(phase)_beforeQuit", fields: ["quit_transport": "app_menu"])
            quit.click()
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            var stopped = false
            repeat {
                stopped =
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app")
                    .filter { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == bundle }.isEmpty
                    && application.state == .notRunning
                if stopped { break }
                // NSWorkspace's application cache also needs the main run loop
                // to receive termination notifications; do not block it while
                // checking whether the external Release process has exited.
                try await Task.sleep(for: .milliseconds(100))
            } while ContinuousClock.now < deadline
            _ = try XCTUnwrap(
                stopped ? true : nil, "Quit Scholium must finish the App's termination owner within 20 seconds; otherwise this diagnostic run is invalid.")
            try mark("\(phase)_stopped", ready: true)
        }

        try mark("driver_started", fields: ["markdown_count": originalDigests.count, "artifact_kind": "packaged_release", "long_chat_turns": longTurns])
        try await launch("cold")
        try verifyIndex("cold")
        try verifySource()
        try await stop("cold")

        // Current v12 local archive, identical to seedChatEntryFixture's format:
        // no runtime thread, connection, account, outgoing request or source edit.
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent(".scholium/manifest.json"))) as? [String: Any])
        let triptychID = try XCTUnwrap(manifest["id"] as? String)
        let seeds = [
            (id: UUID().uuidString, turns: 1, draft: "Short unsent draft — 尚未发送。"),
            (id: UUID().uuidString, turns: longTurns, draft: "Long unsent draft — 保留输入、历史和选择。"),
        ]
        let conversations: [[String: Any]] = seeds.map { item in
            let messages = (0..<item.turns).flatMap { index -> [[String: Any]] in
                let turn = "synthetic-turn-\(index)"
                return [
                    [
                        "id": "question-\(index)", "role": "user", "turnID": turn,
                        "text": "Synthetic question \(index + 1). 请核对来源和解释边界。", "attachments": [], "localMaterials": [],
                    ],
                    [
                        "id": "reply-\(index)", "role": "assistant", "phase": "final_answer", "turnID": turn,
                        "text": "## Synthetic reply \(index + 1)\n\n"
                            + String(repeating: "A disposable source-faithful paragraph. 中文与 English 合成材料，保留研究者控制。\n\n", count: 4)
                            + "| Claim | Status |\n|---|---|\n| Synthetic | Reported |\n\nFinal retained passage \(index + 1).",
                        "attachments": [], "localMaterials": [],
                    ],
                ]
            }
            return [
                "id": item.id, "triptychID": triptychID, "title": "QA \(item.turns)-exchange conversation", "permission": "ask",
                "preferences": ["webSearch": "runtimeDefault"], "turns": [:], "childDrafts": [:], "draft": item.draft,
                "attachments": [], "localMaterials": [], "messages": messages, "queuedMessages": [], "updatedAt": Date().timeIntervalSinceReferenceDate,
            ]
        }
        let archive = home.appendingPathComponent("ApplicationSupport/Chat/\(triptychID)/conversations.json")
        _ = try XCTUnwrap(
            application.state == .notRunning
                && NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app").isEmpty ? true : nil,
            "Only a fully stopped App may have its disposable Chat archive seeded.")
        try manager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: archive.path) || (try? manager.destinationOfSymbolicLink(atPath: archive.path)) != nil {
            let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            _ = try XCTUnwrap(
                values.isRegularFile == true && values.isSymbolicLink == false ? true : nil,
                "The initial empty archive must be a regular file, never a symlink.")
            let initial = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as? [String: Any])
            _ = try XCTUnwrap(Set(initial.keys) == ["version", "conversations"] ? true : nil)
            _ = try XCTUnwrap(initial["version"] as? Int == 12 ? true : nil)
            let records = try XCTUnwrap(initial["conversations"] as? [[String: Any]])
            _ = try XCTUnwrap(records.count == 1 ? true : nil, "Only the automatically created initial empty conversation may be replaced.")
            let record = try XCTUnwrap(records.first)
            // AgentChatConversation.init(triptychID:) encodes these nonoptional
            // defaults. All optional execution, delivery and material context
            // fields are absent; unknown fields must not acquire seed authority.
            let initialKeys: Set<String> = [
                "id", "triptychID", "title", "permission", "preferences", "turns", "childDrafts",
                "draft", "attachments", "localMaterials", "messages", "queuedMessages", "updatedAt",
            ]
            _ = try XCTUnwrap(Set(record.keys) == initialKeys ? true : nil, "An initial conversation must contain only its ordinary encoded defaults.")
            _ = try XCTUnwrap((record["id"] as? String).flatMap(UUID.init(uuidString:)))
            _ = try XCTUnwrap(record["triptychID"] as? String == triptychID ? true : nil)
            _ = try XCTUnwrap(record["title"] as? String == "" && record["draft"] as? String == "" && record["permission"] as? String == "ask" ? true : nil)
            for key in ["attachments", "localMaterials", "messages", "queuedMessages"] {
                _ = try XCTUnwrap((record[key] as? [Any])?.isEmpty == true ? true : nil, "The initial \(key) must be empty.")
            }
            for key in ["turns", "childDrafts"] {
                _ = try XCTUnwrap((record[key] as? [String: Any])?.isEmpty == true ? true : nil, "The initial \(key) must be empty.")
            }
            let preferences = try XCTUnwrap(record["preferences"] as? [String: String])
            _ = try XCTUnwrap(preferences == ["webSearch": "runtimeDefault"] ? true : nil)
            _ = try XCTUnwrap(record["updatedAt"] as? NSNumber)
        }
        try JSONSerialization.data(withJSONObject: ["version": 12, "conversations": conversations]).write(to: archive, options: .atomic)
        application.launchArguments += ["-agent.codex.connected.\(triptychID)", "NO"]
        try await launch("warm")
        try verifyIndex("warm")
        try verifySource()
        try mark("warm_document_ready", ready: true, fields: ["exact_source": true])

        let chat = application.toolbars.firstMatch.descendants(matching: .any).matching(identifier: "Chat").firstMatch
        XCTAssertTrue(
            chat.waitForExistence(timeout: 10),
            "The caller must enable the real Boolean Chat preference inside its preserved production-preference transaction.")
        chat.click()
        let list = application.descendants(matching: .any)["scholium.chat.conversations"].firstMatch
        let composer = application.textViews["scholium.chat.message"].firstMatch
        let transcript = application.descendants(matching: .any)["scholium.chat.transcript.content"].firstMatch
        func question(_ number: Int) -> XCUIElement {
            let text = "Synthetic question \(number). 请核对来源和解释边界。"
            // Rich WebKit text and native read-only text retain their accurate
            // accessibility roles. Use one query for both compared artifacts.
            return application.descendants(matching: .any).matching(
                NSPredicate(
                    format: "label == %@ OR value == %@", text, text)
            ).firstMatch
        }
        func listReady() -> Bool {
            list.exists && !application.descendants(matching: .any)["scholium.chat.loading"].exists
                && !composer.exists && !transcript.exists
                && seeds.allSatisfy { application.descendants(matching: .any)["scholium.chat.conversation.\($0.id)"].exists }
        }
        XCTAssertTrue(waitUntil(timeout: 30) { listReady() })
        try mark("chat_list_ready", ready: true, fields: ["conversation_count": 2])
        let repeatedChatCycles = environment["SCHOLIUM_APP_LIFECYCLE_UNDO_PROBE"] == "1" ? 0 : 6
        for iteration in 0...repeatedChatCycles {
            for item in seeds {
                let label = "chat_\(item.turns == 1 ? "short" : "long")_\(iteration)"
                try mark("\(label)_open_started")
                let started = DispatchTime.now().uptimeNanoseconds
                application.descendants(matching: .any)["scholium.chat.conversation.\(item.id)"].firstMatch.click()
                XCTAssertTrue(composer.waitForExistence(timeout: 20))
                XCTAssertTrue(
                    waitUntil(timeout: 30) {
                        transcript.exists && !application.descendants(matching: .any)["scholium.chat.transcript.hydrating"].exists
                            && composer.value as? String == item.draft
                            && question(item.turns).exists
                    }, "A mounted transcript must finish hydrating the correct history and exact draft before sampling.")
                XCTAssertFalse(application.descendants(matching: .any)["scholium.chat.queue"].exists)
                try mark(
                    "\(label)_detail_ready", ready: true, started: started,
                    fields: ["turns": item.turns, "iteration": iteration, "draft_exact": true, "first_open": iteration == 0])
                if iteration == 6 && item.turns > 1 {
                    let screenshot = application.windows.firstMatch.screenshot()
                    try screenshot.pngRepresentation.write(to: output.deletingPathExtension().appendingPathExtension("chat.png"))
                    let attachment = XCTAttachment(screenshot: screenshot)
                    attachment.name = "Packaged Release long Chat after six returns"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                let back = application.buttons["scholium.chat.back"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5))
                let returnStarted = DispatchTime.now().uptimeNanoseconds
                back.click()
                XCTAssertTrue(waitUntil(timeout: 15) { listReady() })
                try mark("\(label)_list_ready", ready: true, started: returnStarted, fields: ["iteration": iteration, "hidden_detail_inert": true])
            }
        }
        if environment["SCHOLIUM_APP_LIFECYCLE_UNDO_PROBE"] == "1" {
            // This optional round proves Release correctness only. None of its
            // timings or memory samples belong to a retained performance series.
            let long = try XCTUnwrap(seeds.first { $0.turns == longTurns })
            let suffix = " UndoProbeASCII"
            let editedDraft = long.draft + suffix
            let excluded: [String: Any] = [
                "correctness_only": true, "performance_sample_excluded": true, "undo_probe": true,
            ]
            let hydrating = application.descendants(matching: .any)["scholium.chat.transcript.hydrating"].firstMatch
            let queue = application.descendants(matching: .any)["scholium.chat.queue"].firstMatch
            let back = application.buttons["scholium.chat.back"].firstMatch
            let longRow = application.descendants(matching: .any)["scholium.chat.conversation.\(long.id)"].firstMatch
            func undoDraftMatches(_ expected: String) -> Bool {
                guard let actual = composer.value as? String else { return false }
                return Data(actual.utf8) == Data(expected.utf8)
            }
            func requireUndoDetail(_ expected: String, _ reason: String) throws {
                let ready = waitUntil(timeout: 30) {
                        composer.exists
                            && transcript.exists && !hydrating.exists && !queue.exists
                            && question(long.turns).exists && undoDraftMatches(expected)
                    }
                if !ready {
                    let flags: [String: Any] = [
                        "composer_exists": composer.exists, "composer_enabled": composer.isEnabled,
                        "composer_hittable": composer.isHittable, "transcript": transcript.exists,
                        "hydrating": hydrating.exists, "queue": queue.exists,
                        "question": question(long.turns).exists, "draft_exact": undoDraftMatches(expected),
                    ]
                    print("CHAT_UNDO_PRECONDITION \(flags)")
                    try application.debugDescription.write(
                        to: output.deletingPathExtension().appendingPathExtension("undo-failure-ax.txt"),
                        atomically: true, encoding: .utf8)
                    try application.windows.firstMatch.screenshot().pngRepresentation.write(
                        to: output.deletingPathExtension().appendingPathExtension("undo-failure.png"))
                }
                _ = try XCTUnwrap(ready ? true : nil, reason)
            }
            func focusUndoComposer() throws {
                let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.app")
                let process = try XCTUnwrap(processes.count == 1 ? processes.first : nil)
                _ = try XCTUnwrap(process.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == bundle ? true : nil)
                application.activate()
                _ = try XCTUnwrap(
                    waitUntil(timeout: 5) { NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier } ? true : nil)
                let frame = composer.frame
                let center = CGPoint(x: frame.midX, y: frame.midY)
                let chatFrame = application.descendants(matching: .any)["scholium.chatSurface"].firstMatch.frame
                _ = try XCTUnwrap(
                    !frame.isEmpty && !frame.isInfinite && !frame.isNull
                        && application.windows.firstMatch.frame.contains(center) && chatFrame.contains(center) ? true : nil,
                    "Only the finite visible composer inside this exact diagnostic window may receive keyboard input.")
                // Reuse the repository's native input route. An AX hittable
                // proxy does not replace an actual click and keyboard-focus proof.
                composer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
                let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: composer)
                _ = try XCTUnwrap(XCTWaiter.wait(for: [focused], timeout: 5) == .completed ? true : nil,
                    "The identified native composer must acquire keyboard focus before typing or Undo.")
            }
            func undoBackToList() throws {
                _ = try XCTUnwrap(back.waitForExistence(timeout: 5) && back.isHittable ? true : nil)
                back.click()
                _ = try XCTUnwrap(waitUntil(timeout: 15) { listReady() } ? true : nil,
                    "Undo navigation must reach the inert conversation list.")
            }
            func openUndoLong() throws {
                _ = try XCTUnwrap(longRow.waitForExistence(timeout: 5) && longRow.isHittable ? true : nil)
                longRow.click()
            }

            _ = try XCTUnwrap(listReady() ? true : nil, "The optional Undo probe must start at the conversation list.")
            try mark("chat_undo_probe_started", fields: excluded)
            try openUndoLong()
            try requireUndoDetail(long.draft, "Undo must start with the exact seeded long-conversation draft and completed history.")
            try mark("chat_undo_input_precondition", fields: excluded.merging([
                "xcui_textview_enabled": composer.isEnabled, "hittable": composer.isHittable,
            ]) { _, current in current })
            // Use the native text input route; never set the accessibility value
            // or replace the draft through an App/fixture-only hook.
            try focusUndoComposer()
            composer.typeKey(.downArrow, modifierFlags: .command)
            composer.typeText(suffix)
            try requireUndoDetail(editedDraft, "Native typing must append the complete ASCII suffix to the seeded draft.")
            try mark("chat_undo_typed", fields: excluded)
            try undoBackToList()
            try openUndoLong()
            try requireUndoDetail(editedDraft, "Back and reopen must retain the exact typed draft before Undo is attempted.")
            try mark("chat_undo_reopened", fields: excluded)

            try focusUndoComposer()
            application.typeKey("z", modifierFlags: .command)
            try requireUndoDetail(long.draft, "One real Command-Z must restore the seeded draft after Back and reopen.")
            try mark("chat_undo_restored", fields: excluded)
            application.typeKey("z", modifierFlags: [.command, .shift])
            try requireUndoDetail(editedDraft, "Real Command-Shift-Z must restore the exact typed suffix.")
            try mark("chat_undo_redone", fields: excluded)

            let libraryControl = application.toolbars.firstMatch.descendants(matching: .any).matching(identifier: "Library").firstMatch
            _ = try XCTUnwrap(libraryControl.exists && libraryControl.isHittable ? true : nil)
            libraryControl.click()
            _ = try XCTUnwrap(
                waitUntil(timeout: 15) {
                    self.packagedNoteRow(in: application).exists && !composer.exists && !transcript.exists
                } ? true : nil, "Library must hide the native Chat composer before its Undo lifetime is tested.")
            try mark("chat_undo_hidden", fields: excluded)
            _ = try XCTUnwrap(chat.exists && chat.isHittable ? true : nil)
            chat.click()
            try requireUndoDetail(editedDraft, "Returning from Library must retain the redone draft and the current long detail.")
            try focusUndoComposer()
            application.typeKey("z", modifierFlags: .command)
            try requireUndoDetail(long.draft, "Undo after Library/Chat hiding must restore the exact seeded draft.")
            try mark("chat_undo_probe_passed", fields: excluded.merging([
                "draft_exact": true, "native_input": true, "undo_after_back": true,
                "redo_exact": true, "undo_after_hide": true, "queue_absent": true,
            ]) { _, current in current })
            // Leave the draft byte-identical to its seed, then restore the list
            // expected by the existing expanded-reader probe. The original
            // source/history/drafts archive oracle remains authoritative below.
            try undoBackToList()
            try mark("chat_undo_list_restored", fields: excluded)
        }
        if environment["SCHOLIUM_APP_LIFECYCLE_CHAT_RELEASE_PROBE"] == "1" {
            let long = try XCTUnwrap(seeds.first { $0.turns == longTurns })
            let short = try XCTUnwrap(seeds.first { $0.turns == 1 })
            let scrollView = application.scrollViews["scholium.chat.transcript"].firstMatch
            let hydrating = application.descendants(matching: .any)["scholium.chat.transcript.hydrating"].firstMatch
            let earlier = application.buttons["scholium.chat.earlier"].firstMatch
            let back = application.buttons["scholium.chat.back"].firstMatch
            func exactDraft(_ expected: String) -> Bool {
                guard let actual = composer.value as? String else { return false }
                return Data(actual.utf8) == Data(expected.utf8)
            }
            func detailReady(draft: String) -> Bool {
                transcript.exists && scrollView.exists && !hydrating.exists && exactDraft(draft)
            }
            func visiblyHittable(_ element: XCUIElement) -> Bool {
                guard element.isHittable else { return false }
                let intersection = element.frame.intersection(scrollView.frame)
                return !intersection.isNull && intersection.width >= 8 && intersection.height >= 8
            }
            // Reuse the QA paging journey's bounded native-swipe/hit-test
            // policy locally; its helper belongs to the other XCTestCase.
            // Wait for observed movement instead of adding a settling sleep.
            func scrollUntilHittable(_ element: XCUIElement) {
                for _ in 0..<24 where !visiblyHittable(element) {
                    let previousFrame = element.frame
                    if previousFrame.midY < scrollView.frame.midY {
                        scrollView.swipeDown(velocity: .slow)
                    } else {
                        scrollView.swipeUp(velocity: .slow)
                    }
                    XCTAssertTrue(
                        waitUntil(timeout: 5) { visiblyHittable(element) || element.frame != previousFrame },
                        "A native history swipe must visibly advance toward its mounted control.")
                }
                XCTAssertTrue(visiblyHittable(element), "The mounted history control must become visibly reachable.")
            }
            let sameDetailStarted = DispatchTime.now().uptimeNanoseconds
            application.descendants(matching: .any)["scholium.chat.conversation.\(long.id)"].firstMatch.click()
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    detailReady(draft: long.draft)
                        && question(longTurns).exists
                }, "Reopening the same long detail must preserve its exact latest history and draft.")
            try mark(
                "chat_same_detail_ready", ready: true, started: sameDetailStarted,
                fields: ["turns": longTurns, "draft_exact": true])

            // Each seeded turn has exactly two timeline items (question/reply).
            // Four initial items plus one 24-item page expose the last 14 turns.
            let olderNumber = longTurns - 13
            let olderQuestion = question(olderNumber)
            XCTAssertFalse(olderQuestion.exists, "The probe must expand beyond the initial four-item history window.")
            XCTAssertTrue(earlier.waitForExistence(timeout: 5))
            scrollUntilHittable(earlier)
            let expandedStarted = DispatchTime.now().uptimeNanoseconds
            earlier.click()
            XCTAssertTrue(
                waitUntil(timeout: 45) {
                    detailReady(draft: long.draft) && earlier.exists && earlier.isEnabled && olderQuestion.exists
                }, "Earlier Messages must finish its pending page before the expanded detail is sampled.")
            scrollUntilHittable(olderQuestion)
            var observedAnchorY: CGFloat?
            var stableAnchorObservations = 0
            XCTAssertTrue(
                waitUntil(timeout: 10) {
                    guard detailReady(draft: long.draft), earlier.isEnabled, visiblyHittable(olderQuestion) else { return false }
                    let y = olderQuestion.frame.minY
                    if observedAnchorY == y {
                        stableAnchorObservations += 1
                    } else {
                        observedAnchorY = y
                        stableAnchorObservations = 0
                    }
                    return stableAnchorObservations >= 3
                }, "The expanded reading anchor must stop moving before its retained position is recorded.")
            let olderY = try XCTUnwrap(observedAnchorY)
            XCTAssertTrue(olderY.isFinite)
            try mark(
                "chat_expanded_detail_ready", ready: true, started: expandedStarted,
                fields: [
                    "initial_items": 4, "expanded_items": 28, "older_question": olderNumber,
                    "anchor_y": Double(olderY), "draft_exact": true,
                ])
            if environment["SCHOLIUM_APP_LIFECYCLE_UNDO_PROBE"] == "1" {
                let chatSurface = application.descendants(matching: .any)["scholium.chatSurface"].firstMatch
                _ = try XCTUnwrap(
                    chatSurface.exists && chatSurface.frame.width > 0 && chatSurface.frame.height > 0 ? true : nil,
                    "The expanded native/WebKit Chat surface must have actual on-screen geometry before capture.")
                try application.windows.firstMatch.screenshot().pngRepresentation.write(
                    to: output.deletingPathExtension().appendingPathExtension("native-webkit.png"))
            }

            let expandedListStarted = DispatchTime.now().uptimeNanoseconds
            back.click()
            XCTAssertTrue(waitUntil(timeout: 15) { listReady() })
            try mark(
                "chat_expanded_list_ready", ready: true, started: expandedListStarted,
                fields: ["older_question": olderNumber, "hidden_detail_inert": true])

            let anchorTolerance: CGFloat = 24
            func expandedDetailRestored() -> Bool {
                detailReady(draft: long.draft) && earlier.exists && earlier.isEnabled
                    && olderQuestion.exists && visiblyHittable(olderQuestion)
                    && abs(olderQuestion.frame.minY - olderY) <= anchorTolerance
            }
            let reopenedStarted = DispatchTime.now().uptimeNanoseconds
            application.descendants(matching: .any)["scholium.chat.conversation.\(long.id)"].firstMatch.click()
            XCTAssertTrue(
                waitUntil(timeout: 30) { expandedDetailRestored() },
                "The same detail must restore its loaded older question, reading position and exact draft without another page request.")
            try mark(
                "chat_expanded_reopened_ready", ready: true, started: reopenedStarted,
                fields: [
                    "older_question": olderNumber, "anchor_y": Double(olderQuestion.frame.minY),
                    "anchor_delta_y": Double(olderQuestion.frame.minY - olderY), "anchor_tolerance_points": Double(anchorTolerance),
                    "draft_exact": true,
                ])

            let libraryControl = application.toolbars.firstMatch.descendants(matching: .any).matching(identifier: "Library").firstMatch
            XCTAssertTrue(libraryControl.exists)
            let hiddenStarted = DispatchTime.now().uptimeNanoseconds
            libraryControl.click()
            XCTAssertTrue(
                waitUntil(timeout: 15) { self.packagedNoteRow(in: application).exists && !composer.exists && !transcript.exists },
                "Library must hide the expanded Chat detail before its retained memory is sampled.")
            try mark(
                "chat_expanded_hidden_ready", ready: true, started: hiddenStarted,
                fields: ["older_question": olderNumber, "hidden_detail_inert": true])

            let unhiddenStarted = DispatchTime.now().uptimeNanoseconds
            chat.click()
            XCTAssertTrue(
                waitUntil(timeout: 30) { !list.exists && expandedDetailRestored() },
                "Showing Chat must preserve the expanded detail, its original anchor and exact draft.")
            try mark(
                "chat_expanded_unhidden_ready", ready: true, started: unhiddenStarted,
                fields: [
                    "older_question": olderNumber, "anchor_y": Double(olderQuestion.frame.minY),
                    "anchor_delta_y": Double(olderQuestion.frame.minY - olderY), "anchor_tolerance_points": Double(anchorTolerance),
                    "draft_exact": true,
                ])

            back.click()
            XCTAssertTrue(waitUntil(timeout: 15) { listReady() })
            let replacedStarted = DispatchTime.now().uptimeNanoseconds
            application.descendants(matching: .any)["scholium.chat.conversation.\(short.id)"].firstMatch.click()
            XCTAssertTrue(
                waitUntil(timeout: 30) {
                    detailReady(draft: short.draft)
                        && question(1).exists
                        && !olderQuestion.exists
                }, "Replacing the visible detail must show only the short conversation and its exact draft.")
            try mark(
                "chat_replaced_short_ready", ready: true, started: replacedStarted,
                fields: ["turns": short.turns, "draft_exact": true, "replaced_visible_detail": true])
            back.click()
            XCTAssertTrue(waitUntil(timeout: 15) { listReady() })
        }
        let library = application.toolbars.firstMatch.descendants(matching: .any).matching(identifier: "Library").firstMatch
        XCTAssertTrue(library.exists)
        library.click()
        XCTAssertTrue(packagedNoteRow(in: application).waitForExistence(timeout: 10))
        try verifySource()
        try mark("final_document_ready", ready: true, fields: ["exact_source": true, "chat_returns": repeatedChatCycles])
        try application.windows.firstMatch.screenshot().pngRepresentation.write(to: output.deletingPathExtension().appendingPathExtension("library.png"))
        try await stop("final")
        let retained = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as? [String: Any])
        XCTAssertEqual(retained["version"] as? Int, 12)
        let records = try XCTUnwrap(retained["conversations"] as? [[String: Any]])
        XCTAssertEqual(records.count, conversations.count)
        for expected in conversations {
            let record = try XCTUnwrap(records.first { $0["id"] as? String == expected["id"] as? String })
            XCTAssertEqual(record["triptychID"] as? String, triptychID)
            XCTAssertEqual(Data(try XCTUnwrap(record["draft"] as? String).utf8), Data(try XCTUnwrap(expected["draft"] as? String).utf8))
            XCTAssertEqual(
                try JSONSerialization.data(withJSONObject: try XCTUnwrap(record["messages"]), options: [.sortedKeys]),
                try JSONSerialization.data(withJSONObject: try XCTUnwrap(expected["messages"]), options: [.sortedKeys]))
            XCTAssertTrue(try XCTUnwrap(record["queuedMessages"] as? [Any]).isEmpty)
        }
        XCTAssertEqual(try sourceDigests(), originalDigests, "All 500 authoritative Markdown byte streams must remain unchanged.")
        try mark(
            "oracles_passed",
            fields: [
                "markdown_count": 500, "exact_markdown": true, "exact_history": true, "exact_drafts": true,
                "timing_scope": "Library uses the App probe; Chat uses driver observation upper bounds. Limited repeated returns do not prove absence of leaks.",
            ])
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
        let imageAlt = "Packaged image fixture"
        let imageURL = triptych.appendingPathComponent("01-analyses/Attachments/packaged-smoke.png")
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 90, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        for y in 12..<78 {
            for x in 12..<108 {
                bitmap.setColor(NSColor(calibratedRed: 0.18, green: 0.35, blue: 0.72, alpha: 1), atX: x, y: y)
            }
        }
        let imageBytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try imageBytes.write(to: imageURL)
        // The driver receives a disposable copy, never the standard fixture.
        var smokeBytes = try Data(contentsOf: noteURL)
        smokeBytes.append(Data("\n![\(imageAlt)](Attachments/packaged-smoke.png)\n".utf8))
        try smokeBytes.write(to: noteURL)
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
        application.activate()
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
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                !application.descendants(matching: .any)["scholium.bootstrap"].exists
            },
            "Bootstrap must close before responding to Sparkle's permission window."
        )
        declinePackagedAutomaticUpdateChecksIfOffered(in: application)
        let noteRow = packagedNoteRow(in: application)
        XCTAssertTrue(noteRow.waitForExistence(timeout: 45))
        noteRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let mode = documentModeControl(in: application)
        XCTAssertTrue(mode.waitForExistence(timeout: 20))
        XCTAssertEqual(documentModeState(mode), "Edit")
        XCTAssertTrue(application.images[imageAlt].firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(application.images[imageAlt].firstMatch.frame.width, 0)
        XCTAssertGreaterThan(application.images[imageAlt].firstMatch.frame.height, 0)
        selectPackagedMode("Source", in: application, control: mode)
        let editor = application.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 20))
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.packagedSourceAccessibilityMatches(originalSource, in: editor)
            })
        selectPackagedMode("Review", in: application, control: mode)
        let reviewImage = application.buttons["Preview image \(imageAlt) (\(imageURL.lastPathComponent))"]
        XCTAssertTrue(reviewImage.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(reviewImage.frame.width, 0)
        XCTAssertGreaterThan(reviewImage.frame.height, 0)
        selectPackagedMode("Source", in: application, control: mode)
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
        application.activate()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 30))
        declinePackagedAutomaticUpdateChecksIfOffered(in: application)
        XCTAssertFalse(
            application.descendants(matching: .any)["scholium.bootstrap"].exists,
            "The saved Triptych must restore without repeating Bootstrap."
        )
        let restoredRow = packagedNoteRow(in: application)
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 30))
        restoredRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let restoredMode = documentModeControl(in: application)
        XCTAssertTrue(restoredMode.waitForExistence(timeout: 20))
        selectPackagedMode("Edit", in: application, control: restoredMode)
        XCTAssertTrue(application.images[imageAlt].firstMatch.waitForExistence(timeout: 10))
        selectPackagedMode("Source", in: application, control: restoredMode)
        let restoredEditor = application.descendants(matching: .any)["Markdown source editor"]
        XCTAssertTrue(restoredEditor.waitForExistence(timeout: 20))
        XCTAssertTrue(
            waitUntil(timeout: 20) {
                self.packagedSourceAccessibilityMatches(expectedSource, in: restoredEditor)
            },
            "Reopening after relaunch must display the exact saved source."
        )
        XCTAssertEqual(try Data(contentsOf: noteURL), expectedBytes)
        XCTAssertEqual(try Data(contentsOf: imageURL), imageBytes)
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
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: pathField)
        guard XCTWaiter.wait(for: [focused], timeout: 5) == .completed else {
            XCTFail("The identified native path field did not acquire keyboard focus.")
            return
        }
        application.typeKey("a", modifierFlags: [.command])
        application.typeKey(.delete, modifierFlags: [])
        guard waitUntil(timeout: 5, condition: { pathField.value as? String == "" }) else {
            XCTFail("The native path field did not clear; observed \(String(describing: pathField.value)).")
            return
        }
        application.typeText(folder.path)
        guard waitUntil(timeout: 5, condition: { pathField.value as? String == folder.path }) else {
            XCTFail(
                "Native path input must settle the exact folder \(folder.path.debugDescription); observed \(String(describing: pathField.value))."
            )
            return
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
        let selectedPath = application.descendants(matching: .any)[
            "scholium.bootstrap.existingFolders"
        ].staticTexts.matching(
            NSPredicate(
                format: "value IN %@",
                [folder.path, folder.path.hasSuffix("/") ? folder.path : folder.path + "/"]
            )
        ).firstMatch
        let selectionReturned = {
            !panel.exists && selectedPath.exists
                && (button != "scholium.bootstrap.authorizeParent" || !chooseButton.exists)
        }
        let choose = panel.buttons["OKButton"]
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                selectionReturned() || (panel.exists && choose.exists)
            })
        if !selectionReturned(), panel.exists, choose.exists {
            choose.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { selectionReturned() })
        XCTAssertTrue(
            selectedPath.waitForExistence(timeout: 10),
            "The packaged picker must return the exact disposable folder before continuing."
        )
    }

    @MainActor
    private func declinePackagedAutomaticUpdateChecksIfOffered(
        in application: XCUIApplication
    ) {
        let consent = application.windows.containing(
            .button, identifier: "Check Automatically"
        ).firstMatch
        guard consent.waitForExistence(timeout: 5) else { return }
        let decline = consent.buttons["Don’t Check"]
        XCTAssertTrue(decline.waitForExistence(timeout: 5))
        // Sparkle may keep its permission panel loaded while it is hidden.
        // Only a visible choice belongs to this journey.
        guard waitUntil(timeout: 5, condition: { decline.isHittable }) else { return }
        decline.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { !consent.exists },
            "Declining automatic checks must dismiss Sparkle's permission prompt."
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
    private func selectPackagedMode(
        _ requestedMode: String,
        in application: XCUIApplication,
        control: XCUIElement
    ) {
        if documentModeState(control) == requestedMode { return }
        application.menuBars.menuBarItems["View"].click()
        let documentModeMenu = application.menuItems["Document Mode"].firstMatch
        XCTAssertTrue(documentModeMenu.waitForExistence(timeout: 5))
        documentModeMenu.hover()
        let requested = application.menuItems[requestedMode].firstMatch
        XCTAssertTrue(requested.waitForExistence(timeout: 5))
        requested.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                self.documentModeState(control) == requestedMode
            }, "The packaged Document must report the requested \(requestedMode) mode.")
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
