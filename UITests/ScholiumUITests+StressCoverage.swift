import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    /// Opt-in lifecycle pressure over the standard 500-note fixture. These
    /// XCTest action/AX bounds are distinct from the foreground frame probe.
    @MainActor
    func testRepeatedOpenInNewTabReleasesDocumentOwners() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCHOLIUM_TAB_STRESS_UI"] == "1" else {
            throw XCTSkip("The standard-fixture tab pressure diagnostic is not enabled.")
        }
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath()
        let output = URL(
            fileURLWithPath: environment["SCHOLIUM_TAB_STRESS_OUTPUT"]
                ?? build.appendingPathComponent("tab-opening/stress-results.json").path
        )
        .standardizedFileURL.resolvingSymlinksInPath()
        guard output.path.hasPrefix(build.path + "/"), output.pathExtension == "json",
            !FileManager.default.fileExists(atPath: output.path)
        else { throw XCTSkip("The tab diagnostic requires a new JSON output inside repository .build.") }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent("fixture-manifest.json"))) as? [String: Any])
        let inventory = try XCTUnwrap(manifest["files_sha256"] as? [String: String])
        let roles = ["01-analyses": "Analyses", "02-topics": "Topics", "03-works": "Works"]
        let paths = [
            "02-topics/源码保真.md", "02-topics/QA Topic.md", "02-topics/排版样本.md",
            "02-topics/长文与目录.md", "02-topics/诊断样本.md", "02-topics/空白笔记.md",
            "01-analyses/QA Autosave A.md", "01-analyses/QA Autosave B.md", "01-analyses/示例材料.md",
            "03-works/QA Work.md",
        ]
        let sourcePaths = inventory.keys.filter { path in
            path.hasSuffix(".md") && roles.keys.contains { path.hasPrefix($0 + "/") }
        }.sorted()
        let counts = Dictionary(
            uniqueKeysWithValues: roles.keys.map { role in
                (role, sourcePaths.filter { $0.hasPrefix(role + "/") }.count)
            })
        XCTAssertEqual(counts, ["01-analyses": 160, "02-topics": 220, "03-works": 120])
        var actualPaths = Set<String>()
        for role in roles.keys {
            let entries = try XCTUnwrap(
                FileManager.default.enumerator(
                    at: triptychDirectory.appendingPathComponent(role), includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]))
            for case let file as URL in entries where file.pathExtension.lowercased() == "md" {
                actualPaths.insert(String(file.path.dropFirst(triptychDirectory.path.count + 1)))
            }
        }
        XCTAssertEqual(actualPaths, Set(sourcePaths), "The tab workload must use exactly the standard 500-note fixture.")
        func assertSourceInventory() throws {
            for path in sourcePaths {
                XCTAssertFalse(path.split(separator: "/").contains(".."))
                let data = try Data(contentsOf: triptychDirectory.appendingPathComponent(path))
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(digest, inventory[path], "The tab journey changed exact fixture source: \(path)")
            }
        }
        try assertSourceInventory()
        let fidelityURL = triptychDirectory.appendingPathComponent(paths[0])
        let original = try Data(contentsOf: fidelityURL)
        XCTAssertTrue(original.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(original.contains(0x0D))
        XCTAssertFalse(original.suffix(1) == Data([0x0A]))
        var observations: [[String: Any]] = []
        var memoryOwners: [[String: Any]] = []
        var completedRounds = 0
        var inventoryVerified = false
        var undoRedoVerified = false
        func saveSummary() throws {
            let report: [String: Any] = [
                "schema": "scholium-standard-fixture-tab-pressure-v1",
                "fixture_counts": counts, "notes_per_round": paths.count, "planned_rounds": 2,
                "source_paths": paths, "completed_rounds": completedRounds,
                "conditions":
                    "Isolated Debug QA; the setup-owned standard 500-note Triptych copy; one diagnostic process after enabling the existing memory-owner probe, with both rounds in that process.",
                "timing_boundary":
                    "Immediately before Library context menu Open in New Tab activation through observing the matching Document title, usable document surface and native tab count. Includes XCTest input/idle/AX waits; role browsing and context menu presentation are excluded. No frame or app-only latency claim.",
                "unmeasured": ["first paint", "frame pacing", "process resident memory", "installed Release behavior"],
                "observations": observations, "memory_owner_samples": memoryOwners,
                "cross_tab_edit_undo_redo_exact_bytes_verified": undoRedoVerified,
                "all_500_fixture_sources_verified": inventoryVerified,
            ]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output, options: .atomic)
        }
        try saveSummary()

        // The setup launch did not enable this opt-in owner probe. Relaunch
        // only its disposable home/Triptych, then keep both rounds in one process.
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, autosaveDelayMS: 300_000, openNote: nil)
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["SCHOLIUM_QA_MEMORY_OWNER_DIAGNOSTICS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let window = stableWorkspaceWindow(app.windows.firstMatch)
        let tabs = window.toolbars.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium.documentTab."))
        // Existing toolbar chrome is hidden for a single tab. Its AX count
        // therefore cannot distinguish one logical tab from an empty workspace.
        func visibleTabCount(for logicalCount: Int) -> Int { logicalCount > 1 ? logicalCount : 0 }
        func closeAllTabs(expectedLogicalCount: Int) {
            XCTAssertLessThanOrEqual(expectedLogicalCount, paths.count)
            XCTAssertEqual(tabs.count, visibleTabCount(for: expectedLogicalCount))
            for remaining in stride(from: expectedLogicalCount, through: 1, by: -1) {
                app.menuBars.menuBarItems["File"].click()
                let close = app.menuItems["Close Tab"].firstMatch
                XCTAssertTrue(close.waitForExistence(timeout: 3) && close.isEnabled)
                close.click()
                XCTAssertTrue(
                    waitUntil(timeout: 30) {
                        tabs.count == visibleTabCount(for: remaining - 1) && window.exists
                    })
            }
            XCTAssertEqual(tabs.count, 0)
        }
        func recordOwners(_ phase: String) throws -> [String: Any] {
            let sample = try stressMemoryOwnerSnapshot(phase: phase)
            memoryOwners.append(sample)
            try saveSummary()
            return sample
        }
        let releasedKeys = [
            "retained_sessions", "leased_sessions", "pinned_sessions", "attached_webview_sessions",
            "full_snapshots", "pending_hydrations", "editor_pool_attached", "editor_pool_preparing",
            "editor_pool_abandoned_live", "editor_pool_waiting",
        ]
        func releasedOwners(_ phase: String) throws -> [String: Any] {
            var latest: [String: Any]?
            var nextSample = ContinuousClock.now
            var failure: Error?
            let released = waitUntil(timeout: 20) {
                guard ContinuousClock.now >= nextSample else { return false }
                nextSample = ContinuousClock.now.advanced(by: .seconds(1))
                do {
                    latest = try recordOwners(phase)
                    return releasedKeys.allSatisfy { latest?[$0] as? Int == 0 }
                } catch {
                    failure = error
                    return true
                }
            }
            if let failure { throw failure }
            XCTAssertTrue(released, "Closing every tab must release document sessions, snapshots and pending page acquisitions.")
            let sample = try XCTUnwrap(latest)
            for key in releasedKeys { XCTAssertEqual(sample[key] as? Int, 0, "Unreleased owner: \(key)") }
            // The existing pool deliberately keeps at most one source-neutral runtime.
            XCTAssertLessThanOrEqual(try XCTUnwrap(sample["editor_pool_idle"] as? Int), 1)
            return sample
        }
        closeAllTabs(expectedLogicalCount: 0)
        _ = try releasedOwners("baseline_no_tabs")
        var peaks: [[String: Any]] = []
        var closedRounds: [[String: Any]] = []
        for round in 0..<2 {
            for (index, path) in paths.enumerated() {
                let components = path.split(separator: "/").map(String.init)
                let role = try XCTUnwrap(roles[components[0]])
                let relative = components[1]
                let navigator = window.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
                let control = navigator.descendants(matching: .any)[role].firstMatch
                XCTAssertTrue(control.waitForExistence(timeout: 10))
                XCTAssertTrue(waitUntil(timeout: 45) { control.isEnabled })
                control.click()
                _ = clickLibraryRow(relative, in: window, rightMouseButton: true)
                let menu = app.menus["scholium.noteRow.\(relative)"]
                XCTAssertTrue(menu.waitForExistence(timeout: 5))
                let open = menu.menuItems["Open in New Tab"]
                XCTAssertTrue(open.waitForExistence(timeout: 3) && open.isEnabled)
                let started = DispatchTime.now().uptimeNanoseconds
                open.click()
                let title = (relative as NSString).deletingPathExtension
                XCTAssertTrue(
                    waitUntil(timeout: 45) {
                        self.documentTitle(in: window) == title && tabs.count == visibleTabCount(for: index + 1)
                            && self.documentSurfaceIsUsable(for: relative)
                    })
                let ready = DispatchTime.now().uptimeNanoseconds
                observations.append([
                    "round": round, "index": index, "source_path": path, "tab_count": index + 1,
                    "visible_tab_count": tabs.count,
                    "action": "library_context_open_new_tab_to_ready",
                    "observed_duration_ms": Double(ready - started) / 1_000_000,
                ])
                try saveSummary()
                if index == 0 {
                    let token = " tab-pressure-\(round)"
                    try enterLivePreviewAndAppend(token, in: window)
                    app.typeKey("s", modifierFlags: [.command])
                    XCTAssertTrue(
                        waitUntil(timeout: 15) {
                            (try? Data(contentsOf: fidelityURL)) == original + Data(token.utf8)
                        })
                }
                _ = try recordOwners("round_\(round)_open_\(index + 1)")
            }
            let peak = try recordOwners("round_\(round)_all_tabs")
            peaks.append(peak)
            XCTAssertEqual(peak["retained_sessions"] as? Int, paths.count)
            XCTAssertEqual(peak["leased_sessions"] as? Int, paths.count)
            XCTAssertEqual(peak["full_snapshots"] as? Int, paths.count)
            // The last opened tab advances to the first one through the actual
            // Window menu, including when ten tabs overflow the visible strip.
            app.menuBars.menuBarItems["Window"].click()
            let next = app.menuItems["Next Tab"].firstMatch
            XCTAssertTrue(next.waitForExistence(timeout: 3) && next.isEnabled)
            next.click()
            XCTAssertTrue(waitForDocumentTitle("源码保真", in: window, timeout: 30))
            let token = " tab-pressure-\(round)"
            let editor = window.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
            XCTAssertTrue(waitUntil(timeout: 15) { (editor.value as? String)?.contains(token) == true })
            // Tab navigation can preserve Library focus. Undo must be sent
            // to the actual document editor before checking its saved bytes.
            editor.click()
            for (redo, expected) in [
                (false, original), (true, original + Data(token.utf8)), (false, original),
            ] {
                app.typeKey("z", modifierFlags: redo ? [.command, .shift] : [.command])
                XCTAssertTrue(
                    waitUntil(timeout: 15) { (editor.value as? String)?.contains(token) == redo },
                    "The focused editor must finish cross-tab \(redo ? "Redo" : "Undo") before Save.")
                app.typeKey("s", modifierFlags: [.command])
                XCTAssertTrue(
                    waitUntil(timeout: 15) { (try? Data(contentsOf: fidelityURL)) == expected },
                    "Cross-tab \(redo ? "Redo" : "Undo") must preserve exact BOM, CRLF and final-newline bytes.")
            }
            undoRedoVerified = true
            closeAllTabs(expectedLogicalCount: paths.count)
            closedRounds.append(try releasedOwners("round_\(round)_all_closed"))
            completedRounds += 1
            try saveSummary()
        }
        // Compare held document owners at the same completed workload boundary.
        // A transient preparation or the single idle runtime is not a leak;
        // their settled bounds are checked only after every tab has closed.
        for key in [
            "retained_sessions", "leased_sessions", "attached_webview_sessions", "full_snapshots",
            "editor_pool_attached", "read_projection_entries",
        ] {
            XCTAssertLessThanOrEqual(
                try XCTUnwrap(peaks[1][key] as? Int),
                try XCTUnwrap(peaks[0][key] as? Int), "The second round accumulated held \(key).")
        }
        for key in releasedKeys + ["read_projection_entries"] {
            XCTAssertLessThanOrEqual(
                try XCTUnwrap(closedRounds[1][key] as? Int),
                try XCTUnwrap(closedRounds[0][key] as? Int), "The second round retained closed \(key).")
        }
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        try assertSourceInventory()
        inventoryVerified = true
        try saveSummary()
        print("TAB_PRESSURE_UI rounds=2 notes_per_round=10 cross_tab_undo_redo_exact=true unchanged_sources=500 output=\(output.lastPathComponent)")
    }

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
                if kind == "image_gallery" {
                    let preview = window.buttons["Preview image Synthetic image 0000 (image-0000.png)"]
                    XCTAssertTrue(preview.waitForExistence(timeout: 15), "The admitted Review image must decode and expose its preview action.")
                    XCTAssertTrue(preview.isEnabled)
                }
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
