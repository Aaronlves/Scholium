import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testUndoSaveAfterCrossLibraryEditorHandoff() throws {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        let path = "03-works/Stress/Stress Source Fidelity.md"
        let source =
            "\u{FEFF}---\r\nsummary: Synthetic nonprivate stress fixture; no scholarly claims.\r\nkeywords: [stress-fixture, 压力测试, stress-900000]\r\nstress_sequence: 900000\r\nfixture_only: true\r\n---\r\n\r\n# Stress Source Fidelity\r\n\r\n全部内容为合成测试材料，不是引文、文献分析或研究结论。\r\n\r\n<!-- Source bytes must remain authoritative. -->\r\n\r\n中文 English café e\u{301} 🧭; no final newline."
        let url = triptychDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(source.utf8).write(to: url)
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000)
        app.launchEnvironment["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        for mode in ["Source", "Edit", "Review"] { selectDocumentMode(mode, in: window, timeout: 45) }
        _ = try openStressFixtureNote(path, in: window) { _, _, _ in }
        try exerciseStressSelectionAndUndo(path: path, in: window)
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: url), Data(source.utf8))
    }

    @MainActor
    func testImmediateSaveAfterUndoPreservesExactSource() throws {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        let path = "01-analyses/QA Autosave A.md"
        let source =
            "\u{FEFF}---\r\nsummary: Synthetic nonprivate exact-source fixture.\r\nunknown: 'KEEP: 原始'\r\n---\r\n\r\n# Exact source\r\n\r\n```mermaid\r\nflowchart LR\r\naccTitle: QA Source diagram\r\naccDescr: Synthetic source survives mode changes and Undo.\r\nA[中文 e\u{301} 🧭] --> B[Retain]\r\n```\r\n\r\n中文 English café e\u{301} 🧭; no final newline."
        try Data(source.utf8).write(to: triptychDirectory.appendingPathComponent(path))
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000)
        app.launchEnvironment["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        selectDocumentMode("Review", in: window)
        let diagram = window.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "QA Source diagram")
        ).firstMatch
        XCTAssertTrue(diagram.waitForExistence(timeout: 10))
        // An AX Raise alone cannot supply the key-window context that SwiftUI
        // commands consume. Exercise the real QA focus route from that state.
        let windowIdentifier = window.identifier
        app.typeKey("m", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 5) { !self.app.windows[windowIdentifier].exists })
        focusWorkspaceWindow(identifier: windowIdentifier)
        selectDocumentMode("Source", in: window, timeout: 45)
        let sourceImage = XCTAttachment(screenshot: window.screenshot())
        sourceImage.name = "Source menu after restoring the QA window"
        sourceImage.lifetime = .keepAlways
        add(sourceImage)
        try exerciseStressSelectionAndUndo(
            path: path, in: window)
        XCTAssertTrue(diagram.waitForExistence(timeout: 10))
        let image = XCTAttachment(screenshot: window.screenshot())
        image.name = "Source menu restores Review after exact-source Undo"
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
        XCTAssertEqual(
            try Data(contentsOf: triptychDirectory.appendingPathComponent(path)), Data(source.utf8))
    }

    @MainActor
    func testMermaidSourceChangesRecoverAndRenderLatestTyping() throws {
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        let url = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        func source(_ label: String, malformed: Bool = false) -> String {
            "# Diagram editing\n\n```mermaid\nflowchart LR\naccTitle: Diagram \(label)\naccDescr: Synthetic source editing fixture.\n"
                + (malformed ? "A[\"unterminated" : "A[Start] --> B[\(label)]")
                + "\n```\n\nTail"
        }
        try Data(source("Original").utf8).write(to: url)
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = repository.appendingPathComponent(".build/performance-pele-edit-followup/app-state/raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let measurements = raw.appendingPathComponent("typing-\(sessionID.uuidString).jsonl")
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = measurements.path
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] = "editor_key_to_paint"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = "pele-edit-followup"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = "0"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = "100"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_EXPECTED_DOCUMENT"] = "QA Autosave A.md"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        func diagram(_ label: String) -> XCUIElement {
            window.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Diagram \(label)")
            ).firstMatch
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        selectDocumentMode("Review", in: window)
        XCTAssertTrue(diagram("Original").waitForExistence(timeout: 10))
        for (label, malformed) in [("Updated", false), ("Broken", true), ("Recovered", false)] {
            selectDocumentMode("Source", in: window)
            let editor = window.descendants(matching: .any)["Markdown source editor"].firstMatch
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let expected = source(label, malformed: malformed)
            try paste(expected, into: editor)
            app.typeKey("s", modifierFlags: [.command])
            XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: url)) == Data(expected.utf8) })
            selectDocumentMode("Review", in: window)
            if malformed {
                let diagnostic = window.staticTexts.matching(
                    NSPredicate(
                        format: "label CONTAINS %@ OR value CONTAINS %@",
                        "unsupported or could not be rendered", "unsupported or could not be rendered"
                    )
                ).firstMatch
                XCTAssertTrue(diagnostic.waitForExistence(timeout: 10))
                XCTAssertFalse(diagram("Updated").exists)
                XCTAssertTrue(
                    window.staticTexts.matching(
                        NSPredicate(
                            format: "label CONTAINS %@ OR value CONTAINS %@", "unterminated", "unterminated"
                        )
                    ).firstMatch.exists)
            } else {
                XCTAssertTrue(diagram(label).waitForExistence(timeout: 10))
                XCTAssertFalse(diagram(label == "Updated" ? "Original" : "Updated").exists)
            }
            capture("Mermaid source \(label)")
        }
        selectDocumentMode("Source", in: window)
        let editor = window.descendants(matching: .any)["Markdown source editor"].firstMatch
        let earlierSamples = (try? String(contentsOf: measurements, encoding: .utf8))?.split(separator: "\n").count ?? 0
        window.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).click()
        editor.typeKey(.end, modifierFlags: [.command])
        for _ in 0..<3 { editor.typeKey(.upArrow, modifierFlags: []) }
        editor.typeKey(.rightArrow, modifierFlags: [.command])
        editor.typeKey(.leftArrow, modifierFlags: [])
        let typing = "012345678901234567890123"
        editor.typeText(typing)
        let expected = source("Recovered").replacingOccurrences(of: "B[Recovered]", with: "B[Recovered\(typing)]")
        app.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 10) { (try? Data(contentsOf: url)) == Data(expected.utf8) })
        selectDocumentMode("Review", in: window)
        XCTAssertTrue(diagram("Recovered").waitForExistence(timeout: 10))
        capture("Mermaid latest native continuous typing")
        app.terminate()
        XCTAssertEqual(try Data(contentsOf: url), Data(expected.utf8))
        if let data = try? Data(contentsOf: measurements) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Mermaid native typing paint proxy; exclude first \(earlierSamples) samples"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    /// An opt-in scale diagnostic over a disposable generated Triptych. XCTest
    /// transport/polling durations are observation bounds, never frame timings.
    @MainActor
    func testLargeSyntheticVaultDocumentLifecycleStress() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_STRESS_UI"] == "1" else {
            throw XCTSkip("The generated large-fixture UI diagnostic is not enabled.")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath()
        let output = URL(
            fileURLWithPath: environment["SCHOLIUM_STRESS_UI_OUTPUT"]
                ?? build.appendingPathComponent("stress-audit/ui-lifecycle-\(sessionID.uuidString).json")
                .path
        ).standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(build.path + "/"), output.pathExtension == "json",
            !FileManager.default.fileExists(atPath: output.path)
        else {
            throw XCTSkip("The diagnostic requires a new JSON output inside repository .build.")
        }
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent("stress-manifest.json")))
                as? [String: Any])
        XCTAssertEqual(manifest["schema_version"] as? Int, 1)
        XCTAssertEqual(manifest["synthetic_nonprivate"] as? Bool, true)
        let counts = try XCTUnwrap(manifest["counts"] as? [String: Int])
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(counts["notes"]), 508)
        let scenarios = try XCTUnwrap(manifest["scenarios"] as? [String: String])
        let files = try XCTUnwrap(manifest["files"] as? [String: [String: Any]])
        let supportedKinds = [
            "long_prose", "dense_links", "nested_callouts", "image_gallery", "format_matrix",
        ]
        let kinds: [String]
        if let selection = environment["SCHOLIUM_STRESS_UI_SCENARIOS"] {
            let selected = selection.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !selected.isEmpty, Set(selected).count == selected.count,
                selected.allSatisfy({ supportedKinds.contains($0) })
            else {
                throw NSError(
                    domain: "ScholiumUITests.StressScope", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "SCHOLIUM_STRESS_UI_SCENARIOS requires a nonempty, duplicate-free selection from \(supportedKinds.joined(separator: ", "))."
                    ])
            }
            kinds = selected
        } else {
            kinds = supportedKinds
        }
        let includesFidelityJourney = Set(kinds) == Set(supportedKinds)
        let paths = try kinds.map { try XCTUnwrap(scenarios[$0]) }
        let fidelityPath = try XCTUnwrap(scenarios["source_fidelity"])
        for path in paths + [fidelityPath] {
            try assertStressFixtureFile(path, inventory: files)
        }
        var observations = [try XCTUnwrap(initialWorkspaceReadinessObservation)]
        var memoryOwners: [[String: Any]] = []
        var sourceInventoryVerified = false
        var fidelitySelectionAndUndoVerified = false
        func saveSummary() throws {
            let report: [String: Any] = [
                "schema": "scholium-large-fixture-ui-diagnostic-v1",
                "fixture_counts": counts,
                "scenario_selection": kinds,
                "source_fidelity_journey": includesFidelityJourney
                    ? "included" : "excluded_by_selected_diagnostic_scope",
                "conditions":
                    "Isolated Debug QA, generated nonprivate Triptych copied by the canonical runner. One cold setup launch continues through both repeated passes in the same process; no setup relaunch or OS-cache purge.",
                "timing_boundary":
                    "DispatchTime immediately before the named XCTest action through observing its ready state. Includes native-event transport, XCTest idle waits and AX polling; not app-only latency, frame rate or a release performance gate.",
                "unmeasured": [
                    "physical trackpad feel", "first paint", "frame pacing", "process resident memory",
                    "installed Release behavior",
                    "complete gallery image decode; the retained screenshot proves only its inspected viewport",
                ],
                "observations": observations,
                "memory_owner_samples": memoryOwners,
                "source_inventory_verified": sourceInventoryVerified,
                "fidelity_selection_and_undo_verified": fidelitySelectionAndUndoVerified,
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
        }
        try saveSummary()

        // Diagnostics were enabled on the setup launch. Continue that same
        // cold-open process so the journey never cancels its initial indexing.
        selectDocumentMode("Review", timeout: 45)
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        memoryOwners.append(try stressMemoryOwnerSnapshot(phase: "baseline"))

        for pass in 0..<2 {
            for (kind, path) in zip(kinds, paths) {
                let started = DispatchTime.now().uptimeNanoseconds
                let relative = try openStressFixtureNote(path, in: window) { role, duration, available in
                    observations.append([
                        "pass": pass, "scenario": kind, "source_path": path, "role": role,
                        "action": "destination_role_availability", "available": available,
                        "observed_duration_ms": duration,
                        "waiting_bound_seconds": 600,
                    ])
                    try saveSummary()
                }
                let ready = DispatchTime.now().uptimeNanoseconds
                observations.append([
                    "pass": pass, "scenario": kind, "action": "library_open_review",
                    "observed_duration_ms": Double(ready - started) / 1_000_000,
                    "source_bytes": try XCTUnwrap(files[path]?["bytes"] as? Int),
                ])
                try saveSummary()
                if pass == 0, kind == "image_gallery" || kind == "format_matrix" {
                    let rendered = XCTAttachment(screenshot: window.screenshot())
                    rendered.name = "large-fixture-\(kind)-first-pass-ready"
                    rendered.lifetime = .keepAlways
                    add(rendered)
                }
                let reader = stressReader(relative, in: window)
                let initialFrame = reader.frame
                XCTAssertTrue(initialFrame.width.isFinite && initialFrame.height.isFinite)
                XCTAssertGreaterThan(initialFrame.width, 300)
                XCTAssertGreaterThan(initialFrame.height, 100)
                XCTAssertTrue(
                    waitUntil(timeout: 12) { self.stressPersistedScrollFraction(relative) != nil })
                let before = try XCTUnwrap(stressPersistedScrollFraction(relative))
                let scrollStarted = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<4 { reader.swipeUp(velocity: .slow) }
                XCTAssertTrue(
                    waitUntil(timeout: 12) {
                        self.stressPersistedScrollFraction(relative).map { $0 > before + 0.000_1 } ?? false
                    }, "Forward native scrolling must advance the actual retained document position.")
                let forward = try XCTUnwrap(stressPersistedScrollFraction(relative))
                for _ in 0..<2 { reader.swipeDown(velocity: .slow) }
                XCTAssertTrue(
                    waitUntil(timeout: 12) {
                        self.stressPersistedScrollFraction(relative).map { $0 < forward - 0.000_1 } ?? false
                    }, "Reverse native scrolling must remain responsive after the large projection is ready.")
                let reverse = try XCTUnwrap(stressPersistedScrollFraction(relative))
                XCTAssertGreaterThan(reverse, 0)
                XCTAssertEqual(reader.frame.minY, initialFrame.minY, accuracy: 2)
                XCTAssertEqual(reader.frame.height, initialFrame.height, accuracy: 2)
                observations.append([
                    "pass": pass, "scenario": kind, "action": "four_forward_two_reverse_swipes",
                    "observed_duration_ms": Double(DispatchTime.now().uptimeNanoseconds - scrollStarted)
                        / 1_000_000,
                    "before_fraction": before, "forward_fraction": forward, "reverse_fraction": reverse,
                    "viewport_height": initialFrame.height,
                ])
                try saveSummary()

                for mode in ["Edit", "Source", "Review"] {
                    let modeStarted = DispatchTime.now().uptimeNanoseconds
                    selectDocumentMode(mode, in: window, timeout: 45)
                    XCTAssertTrue(
                        waitUntil(timeout: 45) {
                            self.stressModeIsReady(mode, relativePath: relative, in: window)
                        },
                        "The \(kind) projection must finish its \(mode) lifecycle without an error or stale document."
                    )
                    observations.append([
                        "pass": pass, "scenario": kind, "action": "mode_\(mode.lowercased())",
                        "observed_duration_ms": Double(DispatchTime.now().uptimeNanoseconds - modeStarted)
                            / 1_000_000,
                    ])
                    try saveSummary()
                }
                XCTAssertTrue(
                    waitUntil(timeout: 12) {
                        self.stressPersistedScrollFraction(relative).map { $0 > 0 } ?? false
                    }, "Completed mode changes must retain the noninitial reading context.")
                try assertStressFixtureFile(path, inventory: files)
            }
            memoryOwners.append(try stressMemoryOwnerSnapshot(phase: "pass_\(pass)"))
            try saveSummary()
        }
        let first = try XCTUnwrap(memoryOwners.dropFirst().first)
        let second = try XCTUnwrap(memoryOwners.last)
        for key in [
            "retained_sessions", "full_snapshots", "read_projection_entries", "editor_pool_idle",
            "editor_pool_abandoned_live",
        ] {
            XCTAssertLessThanOrEqual(
                try XCTUnwrap(second[key] as? Int), try XCTUnwrap(first[key] as? Int),
                "Repeating the identical completed workload must not accumulate \(key).")
        }

        if includesFidelityJourney {
            _ = try openStressFixtureNote(fidelityPath, in: window) { role, duration, available in
                observations.append([
                    "pass": 1, "scenario": "source_fidelity", "source_path": fidelityPath, "role": role,
                    "action": "destination_role_availability", "available": available,
                    "observed_duration_ms": duration,
                    "waiting_bound_seconds": 600,
                ])
                try saveSummary()
            }
            try exerciseStressSelectionAndUndo(path: fidelityPath, in: window)
            fidelitySelectionAndUndoVerified = true
            try saveSummary()
        }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "large-fixture-lifecycle-completed"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        for path in files.keys.sorted() {
            try assertStressFixtureFile(path, inventory: files)
        }
        sourceInventoryVerified = true
        try saveSummary()
        print(
            "LARGE_FIXTURE_UI notes=\(counts["notes"] ?? 0) passes=2 scenarios=\(kinds.count) selected_scenarios=\(kinds.joined(separator: ",")) unchanged_files=\(files.count) selection_undo_exact=\(fidelitySelectionAndUndoVerified) output=\(output.lastPathComponent)"
        )
    }

    @MainActor
    private func openStressFixtureNote(
        _ path: String, in window: XCUIElement,
        recordAvailability: (_ role: String, _ observedMilliseconds: Double, _ available: Bool) throws
            -> Void
    ) throws -> String {
        let components = path.split(separator: "/").map(String.init)
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(components[1], "Stress")
        let role = try XCTUnwrap(
            ["01-analyses": "Analyses", "02-topics": "Topics", "03-works": "Works"][components[0]])
        let relative = components.dropFirst().joined(separator: "/")
        let navigator = window.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let roleControl = navigator.descendants(matching: .any)[role].firstMatch
        let availabilityStarted = DispatchTime.now().uptimeNanoseconds
        let roleExists = roleControl.waitForExistence(timeout: 10)
        // Libraries become available as their source preparation finishes,
        // independently of the complete index. Observe that wait separately, after
        // proving the cold initial reader and its native scrolling above.
        // This diagnostic bound is not a responsiveness acceptance threshold.
        let available = roleExists && waitUntil(timeout: 600) { roleControl.isEnabled }
        try recordAvailability(
            role, Double(DispatchTime.now().uptimeNanoseconds - availabilityStarted) / 1_000_000,
            available)
        XCTAssertTrue(
            roleExists,
            "The destination \(role) control must remain discoverable during progressive opening.")
        XCTAssertTrue(
            available,
            "The destination \(role) Vault did not become available within the 600-second diagnostic observation window."
        )
        roleControl.click()
        let outline = window.outlines["scholium.noteList"].firstMatch
        let anchor = try XCTUnwrap(
            [
                "01-analyses": "QA Autosave A.md", "02-topics": "QA Topic.md", "03-works": "QA Work.md",
            ][components[0]])
        // Every role contains a folder named Stress. Await a role-unique row
        // before resolving that folder, so a staged browse cannot disclose
        // the previous role's identically named folder.
        XCTAssertTrue(
            outline.descendants(matching: .outlineRow)
                .containing(.any, identifier: "scholium.noteRow." + anchor).firstMatch.waitForExistence(
                    timeout: 45))
        let row = outline.descendants(matching: .outlineRow).containing(
            .any, identifier: "scholium.noteRow." + relative
        ).firstMatch
        if !row.exists {
            let folder = outline.descendants(matching: .outlineRow).containing(
                .any, identifier: "scholium.folderRow.Stress"
            ).firstMatch
            XCTAssertTrue(folder.waitForExistence(timeout: 30))
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
            app.typeKey(.rightArrow, modifierFlags: [])
        }
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
        let title = (components[2] as NSString).deletingPathExtension
        XCTAssertTrue(waitForDocumentTitle(title, in: window, timeout: 45))
        XCTAssertTrue(
            waitUntil(timeout: 60) {
                self.stressModeIsReady("Review", relativePath: relative, in: window)
            })
        return relative
    }

    @MainActor
    private func stressReader(_ relative: String, in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any)["scholium.renderedDocument." + relative].firstMatch
    }

    @MainActor
    private func stressModeIsReady(_ mode: String, relativePath: String, in window: XCUIElement)
        -> Bool
    {
        guard documentModeState(documentModeControl(in: window)) == mode,
            !window.descendants(matching: .any)["scholium.renderedDocument.failed"].exists
        else { return false }
        switch mode {
        case "Review": return stressReader(relativePath, in: window).exists
        case "Edit": return window.descendants(matching: .any)["Markdown editor, Edit mode"].exists
        case "Source": return window.descendants(matching: .any)["Markdown source editor"].exists
        default: return false
        }
    }

    private func stressPersistedScrollFraction(_ relative: String) -> Double? {
        let session = homeDirectory.appendingPathComponent(
            "ApplicationSupport/Window Sessions/\(sessionID.uuidString).json")
        guard let bytes = try? Data(contentsOf: session),
            let snapshot = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
            let workspaces = snapshot["workspaceSessions"] as? [[String: Any]]
        else { return nil }
        let presentations = workspaces.compactMap {
            $0["documentPresentations"] as? [String: [String: Any]]
        }
        let matching = presentations.compactMap { $0[relative] }
        guard matching.count == 1 else { return nil }
        return matching.first?["scrollFraction"] as? Double
    }

    private func assertStressFixtureFile(_ path: String, inventory: [String: [String: Any]]) throws {
        XCTAssertFalse(path.hasPrefix("/"))
        XCTAssertFalse(path.split(separator: "/").contains(".."))
        let bytes = try Data(contentsOf: triptychDirectory.appendingPathComponent(path))
        let expected = try XCTUnwrap(inventory[path])
        XCTAssertEqual(bytes.count, expected["bytes"] as? Int, "Fixture byte count changed: \(path)")
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            digest, expected["sha256"] as? String,
            "The large-fixture lifecycle changed exact source: \(path)")
    }

    @MainActor
    private func stressMemoryOwnerSnapshot(phase: String) throws -> [String: Any] {
        let url = homeDirectory.appendingPathComponent("qa-memory-owner-diagnostics.jsonl")
        func records() -> [[String: Any]] {
            guard let bytes = try? Data(contentsOf: url) else { return [] }
            return String(decoding: bytes, as: UTF8.self).split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
        let previousCount = records().count
        XCTAssertEqual(
            notify_post("com.scholium.qa.performance-memory-owner-snapshot"), UInt32(NOTIFY_STATUS_OK))
        XCTAssertTrue(waitUntil(timeout: 15) { records().count == previousCount + 1 })
        var snapshot = try XCTUnwrap(records().last)
        snapshot["phase"] = phase
        XCTAssertEqual(snapshot["schema"] as? String, "scholium-qa-memory-owners-v1")
        return snapshot
    }

    @MainActor
    private func exerciseStressSelectionAndUndo(path: String, in window: XCUIElement) throws {
        let url = triptychDirectory.appendingPathComponent(path)
        let original = try Data(contentsOf: url)
        defer {
            let traceURL = homeDirectory.appendingPathComponent("qa-save-stages.jsonl")
            if let data = try? Data(contentsOf: traceURL), data.count <= 524_288 {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "native-save-stage-trace"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCTAssertTrue(original.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(original.contains(0x0D))
        XCTAssertFalse(original.suffix(1) == Data([0x0A]))
        selectDocumentMode("Source", in: window, timeout: 45)
        let editor = window.descendants(matching: .any)["Markdown source editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        func assertSaved(_ expected: Data, stage: String, line: UInt = #line) throws {
            let matches = waitUntil(timeout: 15) { (try? Data(contentsOf: url)) == expected }
            if !matches {
                let actual = try Data(contentsOf: url)
                let diagnostic: [String: Any] = [
                    "stage": stage, "expected_base64": expected.base64EncodedString(),
                    "actual_base64": actual.base64EncodedString(),
                    "mounted_editor_value": editor.value as? String ?? "unavailable",
                ]
                let attachment = XCTAttachment(
                    data: try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
                    uniformTypeIdentifier: "public.json")
                attachment.name = "exact-source-save-\(stage)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertTrue(
                matches, "The \(stage) Save must persist the current exact editor source.", line: line)
        }
        window.webViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).click()
        editor.typeKey(.end, modifierFlags: [.command])
        let first = " stress-selection-first"
        let replacement = " stress-selection-replaced"
        editor.typeText(first)
        XCTAssertTrue(waitUntil(timeout: 10) { (editor.value as? String)?.contains(first) == true })
        for _ in first { editor.typeKey(.leftArrow, modifierFlags: [.shift]) }
        selectDocumentMode("Edit", in: window, timeout: 45)
        selectDocumentMode("Source", in: window, timeout: 45)
        // No click, caret navigation, or reconstructed selection repairs this
        // handoff. The next native insertion must replace the retained range.
        app.typeText(replacement)
        app.typeKey("s", modifierFlags: [.command])
        try assertSaved(original + Data(replacement.utf8), stage: "replacement")
        app.typeKey("z", modifierFlags: [.command])
        app.typeKey("s", modifierFlags: [.command])
        try assertSaved(original + Data(first.utf8), stage: "first-undo")
        app.typeKey("z", modifierFlags: [.command])
        app.typeKey("s", modifierFlags: [.command])
        try assertSaved(original, stage: "second-undo")
        selectDocumentMode("Review", in: window, timeout: 45)
    }
}
