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

/// Enters exact text through XCTest's native keyboard transport in one isolated
/// QA input. A trailing space and ordinary Delete commit through AppKit;
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
    if input.identifier == "scholium.chat.message" {
        // Return submits this native composer. XCTest's typeText discards
        // contextual modifiers, so insert draft newlines explicitly.
        let lines = (text + " ").components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 { input.typeKey(.return, modifierFlags: .shift) }
            if !line.isEmpty { input.typeText(line) }
        }
    } else {
        input.typeText(text + " ")
    }
    input.typeKey(input.elementType == .textView ? .downArrow : .rightArrow, modifierFlags: .command)
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

    private let initialWorkspaceReadyTimeout: TimeInterval = 45

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
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
        app.launch()
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
            XCTAssertTrue(
                waitUntil(timeout: initialWorkspaceReadyTimeout) {
                    self.documentSurfaceIsUsable(for: initialOpenNote)
                },
                "The isolated QA window appeared without exposing the initial document in its current mode."
            )
        }
    }

    @MainActor
    override func tearDown() async throws {
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
    }

}
