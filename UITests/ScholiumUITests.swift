import AppKit
import ApplicationServices
import CryptoKit
@preconcurrency import XCTest
import notify

@MainActor
private func reportXCTestInputTransport() {
    print(
        "XCTest native text input: directAXTrusted=\(AXIsProcessTrusted()), pid \(ProcessInfo.processInfo.processIdentifier), bundle \(Bundle.main.bundleIdentifier ?? "unknown"), executable \(Bundle.main.executableURL?.path ?? "unknown")"
    )
}

/// The outer owner survives an XCTest runner restart and preserves the exact
/// shared QA domain before even fixture-preparation launches. An unresolved
/// snapshot or direct unguarded driver run must not authorize a native launch.
func requireQAPreferencePreservation() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let state = root.appendingPathComponent(".build/qa-preferences-preservation")
    let data = try Data(contentsOf: state.appendingPathComponent("owner.json"))
    let owner = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let pid = try XCTUnwrap(owner["ownerPID"] as? Int32)
    let present = try XCTUnwrap(owner["present"] as? Bool)
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-p", String(pid), "-o", "lstart="]
    process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    let started = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard owner["schema"] as? Int == 1, owner["domain"] as? String == "com.scholium.qa",
        pid > 1, process.terminationStatus == 0, !started.isEmpty,
        owner["ownerStarted"] as? String == started
    else {
        throw NSError(
            domain: "ScholiumUITests.Preservation", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Run through the QA preservation owner; do not reuse a stale preference snapshot."
            ])
    }
    if present {
        let snapshot = try Data(contentsOf: state.appendingPathComponent("original.plist"))
        _ = try XCTUnwrap(PropertyListSerialization.propertyList(from: snapshot, format: nil) as? [String: Any])
    }
}

/// Retains clipboard representations in memory only. A later external write
/// becomes the next baseline; it must never be replaced by an older snapshot.
@MainActor
final class QAClipboardPreservation {
    private typealias Item = [(type: NSPasteboard.PasteboardType, data: Data)]
    private let pasteboard: NSPasteboard
    private var originalItems: [Item]?
    private var ownedChangeCount: Int?

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func setText(_ text: String) throws {
        let changeCount = pasteboard.changeCount
        let items = try snapshot()
        guard pasteboard.changeCount == changeCount else {
            throw CocoaError(.fileReadUnknown)
        }
        if ownedChangeCount != changeCount {
            originalItems = items
        }
        let writeChangeCount = pasteboard.clearContents()
        ownedChangeCount = writeChangeCount
        guard pasteboard.setString(text, forType: .string),
            pasteboard.changeCount == writeChangeCount
        else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func restoreIfOwned() throws {
        defer {
            originalItems = nil
            ownedChangeCount = nil
        }
        guard let originalItems, let ownedChangeCount,
            pasteboard.changeCount == ownedChangeCount
        else { return }
        let items = try originalItems.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                guard item.setData(representation.data, forType: representation.type) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            return item
        }
        guard pasteboard.changeCount == ownedChangeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty, !pasteboard.writeObjects(items) {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func snapshot() throws -> [Item] {
        guard let items = pasteboard.pasteboardItems else {
            throw CocoaError(.fileReadUnknown)
        }
        guard !items.isEmpty || pasteboard.types?.isEmpty != false else {
            throw CocoaError(.fileReadUnknown)
        }
        return try items.map { item in
            try item.types.map { type in
                guard let data = item.data(forType: type) else {
                    throw CocoaError(.fileReadUnknown)
                }
                return (type, data)
            }
        }
    }
}

/// Enters exact text through XCTest's native keyboard transport in one isolated
/// QA input. A trailing commit character and ordinary Delete commit through AppKit;
/// the system clipboard and input-source settings are never accessed.
@MainActor
func typeCommittedText(
    _ text: String,
    into field: XCUIElement,
    in application: XCUIApplication,
    clickWithinVisibleFrame: Bool = false
) {
    let processes = NSRunningApplication.runningApplications(withBundleIdentifier: "com.scholium.qa")
    guard processes.count == 1, let process = processes.first,
        process.executableURL?.path.contains("/.build/qa-runtime/") == true,
        application.state != .notRunning
    else {
        XCTFail(
            "Exact input requires one isolated repository QA process and its XCTest application; processes \(processes.count), paths \(processes.compactMap { $0.executableURL?.path }), state \(application.state.rawValue)."
        )
        return
    }
    let targetFrame = field.frame
    let inputType = field.elementType
    let inputIdentifier = field.identifier
    guard !targetFrame.isEmpty, !targetFrame.isInfinite, !targetFrame.isNull,
        [.textField, .searchField, .textView].contains(inputType)
    else {
        XCTFail("The QA input has no finite, nonempty editable frame: \(targetFrame).")
        return
    }
    // Resolve from the supplied QA application, never mutate an arbitrary
    // caller's element or choose between equal identifiers in different windows.
    var matches: [(window: XCUIElement, input: XCUIElement)] = []
    var remainingNodes = 2_048
    for window in application.windows.allElementsBoundByIndex
    where window.identifier.hasPrefix("scholium") || window.identifier == "com_apple_SwiftUI_Settings_window" {
        let inputs = window.descendants(matching: inputType)
        // Narrow before binding by index: unrelated editor text views can be
        // replaced during an asynchronous render, changing the broad query.
        let candidates = (inputIdentifier.isEmpty ? inputs : inputs.matching(identifier: inputIdentifier))
            .allElementsBoundByIndex
        guard candidates.count <= remainingNodes else {
            XCTFail("The QA input lookup exceeded its bounded candidate budget.")
            return
        }
        remainingNodes -= candidates.count
        for candidate in candidates {
            let frame = candidate.frame
            if abs(frame.minX - targetFrame.minX) < 2, abs(frame.minY - targetFrame.minY) < 2,
                abs(frame.width - targetFrame.width) < 2, abs(frame.height - targetFrame.height) < 2
            {
                matches.append((window, candidate))
            }
        }
    }
    guard matches.count == 1, let match = matches.first else {
        XCTFail("The QA input has no unique XCTest window/input identity: \(field.identifier), \(targetFrame), matches \(matches.count).")
        return
    }
    application.activate()
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process.processIdentifier else {
        XCTFail("The isolated QA process did not become active before text entry.")
        return
    }
    let input = match.input
    if clickWithinVisibleFrame {
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    } else {
        input.click()
    }
    let focused = XCTNSPredicateExpectation(
        predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: input)
    guard XCTWaiter.wait(for: [focused], timeout: 5) == .completed else {
        XCTFail("The identified QA input did not acquire native keyboard focus.")
        return
    }
    input.typeKey("a", modifierFlags: .command)
    // A native search field can consume a trailing space while committing
    // input. Keep a visible sentinel so Delete cannot remove the query itself.
    let sentinel = inputType == .searchField ? "." : " "
    if input.identifier == "scholium.chat.message" {
        // Return submits this native composer. XCTest's typeText discards
        // contextual modifiers, so insert draft newlines explicitly.
        let lines = (text + sentinel).components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 { input.typeKey(.return, modifierFlags: .shift) }
            if !line.isEmpty { input.typeText(line) }
        }
    } else {
        input.typeText(text + sentinel)
    }
    input.typeKey(input.elementType == .textView ? .downArrow : .rightArrow, modifierFlags: .command)
    if inputType == .searchField, input.value as? String != text + sentinel {
        XCTFail("The QA search input did not retain its commit character; Delete was not attempted.")
        return
    }
    input.typeKey(.delete, modifierFlags: [])
    XCTAssertEqual(field.value as? String, text, "The QA input did not commit its exact setup text.")
}

final class ScholiumUITests: XCTestCase {
    /// Mirrors `ScholiumMetrics.Workspace` in the app target. The standalone
    /// UI-test bundle cannot import that executable module, so keep this named
    /// acceptance contract synchronized with the source design tokens.
    enum QAWorkspaceMetricContract {
        static let preferredWidth: CGFloat = 1_180
        static let libraryMinimumReadableWidth: CGFloat = 300
        static let apparatusFirstRevealWidth: CGFloat = 320
        static let frameTolerance: CGFloat = 18
    }

    /// Mirrors the separate first-run Bootstrap scene. Bootstrap is not a
    /// compact workspace shell: it never owns the three-region split or its
    /// toolbar, and it is replaced by the configured workspace on success.
    enum QABootstrapMetricContract {
        static let preferredWidth: CGFloat = 620
    }

    enum QAAppearance: String, CaseIterable {
        case light
        case dark

        var displayName: String { rawValue.capitalized }
    }

    var app: XCUIApplication!
    var sessionID: UUID!
    var testDirectory: URL!
    var homeDirectory: URL!
    var triptychDirectory: URL!
    var clipboardPreservation: QAClipboardPreservation?
    var initialWorkspaceReadinessObservation: [String: Any]?

    var isLargeSyntheticVaultStressTest: Bool {
        name.contains("testLargeSyntheticVaultDocumentLifecycleStress")
    }
    /// `defaultSize` is a first-presentation input. Tests that need a specific
    /// starting width must request it before their first scene appears; a
    /// relaunch is intentionally not a frame-reset API.
    private var initialWorkspaceWidthForCurrentTest: Int {
        if name.contains("testTwoHundredPercentDocumentTextPersistsAcrossEveryMode") {
            return 900
        }
        if name.contains("testLibraryRemainsReadableAtItsNativeMinimum") {
            return Int(QAWorkspaceMetricContract.preferredWidth)
        }
        return 1_380
    }

    private var initialOpenNoteForCurrentTest: String? {
        if name.contains("testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession") {
            return nil
        }
        if name.contains("testAgentChangesShowsExactUpdateAndRestoresOriginalBytes") {
            return "Agent Review.md"
        }
        return "QA Autosave A.md"
    }

    // The large fixture's cold configuration is itself observed diagnostic
    // work. Its bound must not inherit the ordinary 500-note fixture deadline.
    private var initialWorkspaceReadyTimeout: TimeInterval {
        isLargeSyntheticVaultStressTest ? 600 : 45
    }

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        if isLargeSyntheticVaultStressTest,
            ProcessInfo.processInfo.environment["SCHOLIUM_STRESS_UI"] != "1"
        {
            throw XCTSkip("The opt-in synthetic stress fixture is not configured.")
        }
        if name.contains("testRuntimeReadinessDiagnostic") || name.contains("testFreshIndexReadinessDiagnostic") {
            let environment = ProcessInfo.processInfo.environment
            guard environment["SCHOLIUM_RUNTIME_DIAGNOSTIC_OUTPUT"] != nil else {
                throw XCTSkip("The opt-in runtime diagnostic is not configured.")
            }
            _ = try XCTUnwrap(
                environment["SCHOLIUM_RUNTIME_DIAGNOSTIC_APP_PATH"],
                "Runtime measurements require the exact isolated QA bundle path.")
        }
        try requireQAPreferencePreservation()
        sessionID = UUID()
        try createIsolatedTriptych()
        try prepareIdentityBoundFixturesIfNeeded(
            initialWorkspaceWidth: initialWorkspaceWidthForCurrentTest,
            initialOpenNote: initialOpenNoteForCurrentTest,
            readyTimeout: initialWorkspaceReadyTimeout
        )
        if name.contains("testStorageUnavailableRetriesWithoutConstructingWorkspace") {
            try FileManager.default.createDirectory(
                at: homeDirectory,
                withIntermediateDirectories: true
            )
            try Data("Application Support blocker".utf8).write(
                to: homeDirectory.appendingPathComponent("ApplicationSupport")
            )
        }
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: initialWorkspaceWidthForCurrentTest,
            usesFixedSessionID: !name.contains(
                "testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession"
            ),
            autosaveDelayMS: 5_000,
            appearance: name.contains("testSettingsNavigationRetainsDraftsAndWindowGeometry") ? .dark : nil,
            openNote: initialOpenNoteForCurrentTest
        )
        if name.contains("testAgentChangesShowsExactUpdateAndRestoresOriginalBytes") {
            app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "topic_knowledge"
        }
        reportXCTestInputTransport()
        // A runner killed by XCTest cannot execute tearDown, so its QA app can
        // survive into the next test process. A fresh XCUIApplication can
        // report `.notRunning` even while that orphan still owns the bundle.
        // Reclaim every process with the QA-only bundle identifier before the
        // journey asks SwiftUI to create its one default scene.
        terminateRunningQAApplications()
        let launchStarted = DispatchTime.now().uptimeNanoseconds
        app.launch()
        try verifyRuntimeDiagnosticApplicationIdentity()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "The isolated QA window did not appear"
        )
        if name.contains("testStorageUnavailableRetriesWithoutConstructingWorkspace") {
            XCTAssertTrue(
                app.descendants(matching: .any)["scholium.storageUnavailable"]
                    .waitForExistence(timeout: 15),
                "The invalid Application Support root did not produce the recoverable storage page."
            )
            return
        }
        if let initialOpenNote = initialOpenNoteForCurrentTest {
            let usable = waitUntil(timeout: initialWorkspaceReadyTimeout) {
                self.documentSurfaceIsUsable(for: initialOpenNote)
            }
            if isLargeSyntheticVaultStressTest {
                let observation: [String: Any] = [
                    "action": "cold_bootstrap_initial_document_usable",
                    "source_path": initialOpenNote,
                    "usable": usable,
                    "observed_duration_ms": Double(DispatchTime.now().uptimeNanoseconds - launchStarted) / 1_000_000,
                    "waiting_bound_seconds": initialWorkspaceReadyTimeout,
                    "timing_boundary":
                        "Immediately before XCTest app.launch through initial document usability polling. Includes launch transport, XCTest idle waits, window/identity checks and AX polling; not app-only latency or a performance pass threshold.",
                ]
                initialWorkspaceReadinessObservation = observation
                // Keep the setup observation even if readiness fails before
                // the stress body can write its consolidated JSON report.
                let data = try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
                let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
                attachment.name = "large-fixture-cold-bootstrap-observation"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertTrue(
                usable,
                "The isolated QA window appeared without exposing the initial document in its current mode."
            )
        }
    }

    @MainActor
    override func tearDown() async throws {
        if isLargeSyntheticVaultStressTest, let homeDirectory,
            let failures = try? Data(contentsOf: homeDirectory.appendingPathComponent("qa-reader-failures.jsonl")),
            failures.count <= 65_536,
            let metadata = String(data: failures, encoding: .utf8)
        {
            let attachment = XCTAttachment(string: metadata)
            attachment.name = "Scholium QA reader failure metadata"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        if testRun?.failureCount ?? 0 > 0, let app {
            for window in app.windows.allElementsBoundByIndex
            where window.exists
                && window.identifier.hasPrefix("scholium")
            {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.scholium.qa" {
                    let attachment = XCTAttachment(screenshot: window.screenshot())
                    attachment.name = "Scholium UI failure — \(window.identifier)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
                let hierarchy = XCTAttachment(string: window.debugDescription)
                hierarchy.name = "Scholium window accessibility — \(window.identifier)"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            if let homeDirectory,
                let recoveryURL = FileManager.default.enumerator(
                    at: homeDirectory,
                    includingPropertiesForKeys: nil
                )?.compactMap({ $0 as? URL }).first(where: {
                    $0.lastPathComponent == "transaction-recovery.json"
                }),
                let recoveryData = try? Data(contentsOf: recoveryURL),
                let recoveryText = String(data: recoveryData, encoding: .utf8)
            {
                let recovery = XCTAttachment(string: recoveryText)
                recovery.name = "Scholium transaction recovery record"
                recovery.lifetime = .keepAlways
                add(recovery)
            }
        }
        app?.terminate()
        if ProcessInfo.processInfo.environment["SCHOLIUM_QA_KEEP_ARTIFACTS"] != "1",
            let testDirectory
        {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        app = nil
        sessionID = nil
        testDirectory = nil
        homeDirectory = nil
        triptychDirectory = nil
        initialWorkspaceReadinessObservation = nil
        let clipboard = clipboardPreservation
        clipboardPreservation = nil
        // App and fixture cleanup must finish even if clipboard restoration fails.
        try clipboard?.restoreIfOwned()
    }

}

/// Uses only unique named pasteboards; no app, filesystem, or general clipboard.
final class QAClipboardPreservationTests: XCTestCase {
    @MainActor
    func testAllItemRepresentationsSurviveRoundTrip() throws {
        let pasteboard = NSPasteboard(name: .init("com.scholium.qa.clipboard.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("com.scholium.qa.binary")
        let first = NSPasteboardItem()
        let second = NSPasteboardItem()
        XCTAssertTrue(first.setString("Synthetic original", forType: .string))
        XCTAssertTrue(first.setData(Data([0, 1, 127, 255]), forType: binaryType))
        XCTAssertTrue(second.setData(Data("<b>Synthetic second item</b>".utf8), forType: .html))
        XCTAssertTrue(pasteboard.writeObjects([first, second]))
        let originalItems = try XCTUnwrap(pasteboard.pasteboardItems)
        let originalTypes = originalItems.map(\.types)
        let originalText = try XCTUnwrap(originalItems[0].data(forType: .string))
        let originalHTML = try XCTUnwrap(originalItems[1].data(forType: .html))
        let clipboard = QAClipboardPreservation(pasteboard: pasteboard)
        try clipboard.setText("Temporary QA text")
        try clipboard.restoreIfOwned()
        let restored = try XCTUnwrap(pasteboard.pasteboardItems)
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.map(\.types), originalTypes)
        XCTAssertEqual(restored[0].data(forType: .string), originalText)
        XCTAssertEqual(restored[0].data(forType: binaryType), Data([0, 1, 127, 255]))
        XCTAssertEqual(restored[1].data(forType: .html), originalHTML)
    }

    @MainActor
    func testEmptyClipboardIsRestored() throws {
        let pasteboard = NSPasteboard(name: .init("com.scholium.qa.clipboard.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let clipboard = QAClipboardPreservation(pasteboard: pasteboard)
        try clipboard.setText("Temporary QA text")
        try clipboard.restoreIfOwned()
        XCTAssertTrue(pasteboard.pasteboardItems?.isEmpty != false)
        XCTAssertTrue(pasteboard.types?.isEmpty != false)
    }

    @MainActor
    func testRepeatedOwnedWritesRestoreOriginalContents() throws {
        let pasteboard = NSPasteboard(name: .init("com.scholium.qa.clipboard.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.setString("Original", forType: .string))
        let clipboard = QAClipboardPreservation(pasteboard: pasteboard)
        try clipboard.setText("First QA text")
        try clipboard.setText("Second QA text")
        try clipboard.restoreIfOwned()
        XCTAssertEqual(pasteboard.string(forType: .string), "Original")
    }

    @MainActor
    func testExternalChangeIsNotOverwrittenOnRestore() throws {
        let pasteboard = NSPasteboard(name: .init("com.scholium.qa.clipboard.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.setString("Original", forType: .string))
        let clipboard = QAClipboardPreservation(pasteboard: pasteboard)
        try clipboard.setText("Temporary QA text")
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Later external text", forType: .string))
        let externalChangeCount = pasteboard.changeCount
        try clipboard.restoreIfOwned()
        XCTAssertEqual(pasteboard.changeCount, externalChangeCount)
        XCTAssertEqual(pasteboard.string(forType: .string), "Later external text")
    }

    @MainActor
    func testExternalChangeBetweenWritesBecomesRestorationBaseline() throws {
        let pasteboard = NSPasteboard(name: .init("com.scholium.qa.clipboard.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.setString("Original", forType: .string))
        let clipboard = QAClipboardPreservation(pasteboard: pasteboard)
        try clipboard.setText("First QA text")
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Later external text", forType: .string))
        try clipboard.setText("Second QA text")
        try clipboard.restoreIfOwned()
        XCTAssertEqual(pasteboard.string(forType: .string), "Later external text")
    }
}
