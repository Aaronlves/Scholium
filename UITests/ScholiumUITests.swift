@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

/// Enters an exact query without changing the user's active input source.
/// XCTest typing can leave Latin text marked under a CJK input source and can
/// route quotes or spaces through its candidate window. A short-lived paste is
/// deterministic; the prior clipboard is restored unless somebody else changes
/// it while the test owns the temporary value.
@MainActor
func typeCommittedText(
    _ text: String,
    into field: XCUIElement,
    in application: XCUIApplication
) {
    let pasteboard = NSPasteboard.general
    let savedItems = pasteboard.pasteboardItems?.map { source in
        source.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { item, type in
            item[type] = source.data(forType: type)
        }
    }

    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString(text, forType: .string))
    let temporaryChangeCount = pasteboard.changeCount
    defer {
        if pasteboard.changeCount == temporaryChangeCount {
            pasteboard.clearContents()
            if let savedItems {
                let restoredItems = savedItems.map { representations in
                    let item = NSPasteboardItem()
                    for (type, data) in representations {
                        item.setData(data, forType: type)
                    }
                    return item
                }
                pasteboard.writeObjects(restoredItems)
            }
        }
    }

    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeKey("v", modifierFlags: .command)
    XCTAssertEqual(
        field.value as? String,
        text,
        "The Search query was not committed exactly under the active input source."
    )
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
        static let preferredWidth: CGFloat = 760
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
        if name.contains("testWorkspaceInitialDefaultPreservesNativeReachability")
            || name.contains("testInspectorToolbarItemOpensAndClosesInspector")
            || name.contains("testInspectorDividerResizesWithoutInteractiveCollapse")
            || name.contains("testPeripheralToolbarVisibilityControlsToggleWithPointerCoordinates")
            || name.contains("testAppearanceLineWidthVisualMatrixAndKeyboardControl")
            || name.contains("testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm")
            || name.contains("testLibraryRemainsReadableAtItsNativeMinimum") {
            return Int(QAWorkspaceMetricContract.preferredWidth)
        }
        return 1_380
    }

    private var initialOpenNoteForCurrentTest: String? {
        if name.contains("testRestoreAccessQuitScholiumTerminatesApplication")
            || name.contains(
                "testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession"
            ) {
            return nil
        }
        if name.contains("testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm") {
            return "QA Document Heading Study.md"
        }
        if name.contains("testAgentChangesShowsExactUpdateAndRestoresSettledBytes") {
            return "Agent Review.md"
        }
        return "QA Autosave A.md"
    }

    private var initialWorkspaceReadyTimeout: TimeInterval {
        if name.contains("testManagedNewNoteKeepsFixedYAMLAfterAddingCustomMetadataField") {
            return 90
        }
        return 45
    }

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        sessionID = UUID()
        try createIsolatedTriptych()
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
            autosaveDelayMS: name.contains(
                "testDirtyLivePreviewSearchesThisNoteWithoutSaving"
            ) ? 300_000 : 5_000,
            appearance: nil,
            openNote: initialOpenNoteForCurrentTest
        )
        if name.contains("testAgentChangesShowsExactUpdateAndRestoresSettledBytes") {
            app.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_SLOT"] = "topic_knowledge"
        }
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
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Scholium UI failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Scholium accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            if let homeDirectory,
               let recoveryURL = FileManager.default.enumerator(
                   at: homeDirectory,
                   includingPropertiesForKeys: nil
               )?.compactMap({ $0 as? URL }).first(where: {
                   $0.lastPathComponent == "transaction-recovery.json"
               }),
               let recoveryData = try? Data(contentsOf: recoveryURL),
               let recoveryText = String(data: recoveryData, encoding: .utf8) {
                let recovery = XCTAttachment(string: recoveryText)
                recovery.name = "Scholium transaction recovery record"
                recovery.lifetime = .keepAlways
                add(recovery)
            }
        }
        app?.terminate()
        if ProcessInfo.processInfo.environment["SCHOLIUM_QA_KEEP_ARTIFACTS"] != "1",
           let testDirectory {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        app = nil
        sessionID = nil
        testDirectory = nil
        homeDirectory = nil
        triptychDirectory = nil
    }

}
