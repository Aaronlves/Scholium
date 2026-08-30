@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
    @MainActor
    func terminateRunningQAApplications() {
        let bundleIdentifier = "com.scholium.qa"
        let runningApplications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        runningApplications.forEach { $0.terminate() }
        if !waitUntil(timeout: 5, condition: {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).isEmpty
        }) {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).forEach { $0.forceTerminate() }
        }
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleIdentifier
                ).isEmpty
            },
            "The previous isolated QA process did not terminate before launch."
        )
    }

    func localResearchExecutionDirectoryURL() throws -> URL {
        let triptych = try triptychID(at: triptychDirectory)
        let executionStore = homeDirectory
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptych.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v10", isDirectory: true)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: executionStore.appendingPathComponent(
                    "unsupported-executions",
                    isDirectory: true
                ).path
            ),
            "The QA workspace must expose the current Local Execution store."
        )
        return executionStore
    }

    var unreadableLocalExecutionFixtureBytes: Data {
        Data("{\"schema_version\":16}".utf8)
    }

    func unreadableLocalExecutionFixtureURL() throws -> URL {
        try localResearchExecutionDirectoryURL()
            .appendingPathComponent(
                "a58b5cb6-6db4-66e9-c160-51f70354e3e9.json"
            )
    }

    func archivedUnreadableLocalExecutionFixtureURL() throws -> URL {
        let source = try unreadableLocalExecutionFixtureURL()
        return source.deletingLastPathComponent()
            .appendingPathComponent("unsupported-executions", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent)
    }

    func seedUnreadableLocalExecutionForSystemTrash() throws {
        let url = try unreadableLocalExecutionFixtureURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try unreadableLocalExecutionFixtureBytes.write(to: url)
    }

    @MainActor
    func accessibilityText(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty {
            return value
        }
        return element.label
    }

    @MainActor
    func sliderNumericValue(_ element: XCUIElement) -> Double? {
        if let number = element.value as? NSNumber {
            return number.doubleValue
        }
        if let value = element.value as? String {
            return Double(value)
                ?? value.split(whereSeparator: { $0.isWhitespace }).first.flatMap {
                    Double($0)
                }
        }
        return nil
    }


    @MainActor
    func scrollUntilHittable(
        _ element: XCUIElement,
        in scrollView: XCUIElement
    ) {
        func isVisiblyHittable() -> Bool {
            guard element.isHittable else { return false }
            let intersection = element.frame.intersection(scrollView.frame)
            return !intersection.isNull
                && intersection.width >= 8
                && intersection.height >= 8
        }
        guard !isVisiblyHittable() else { return }

        // XCUITest exposes offscreen SwiftUI rows with their actual frame. A
        // swipe can advance by more than one viewport on macOS and oscillate
        // around a compact target, so use bounded native scroll-wheel deltas.
        for _ in 0..<24 where !isVisiblyHittable() {
            if element.frame.midY < scrollView.frame.midY {
                scrollView.scroll(byDeltaX: 0, deltaY: 120)
            } else {
                scrollView.scroll(byDeltaX: 0, deltaY: -120)
            }
        }
        XCTAssertTrue(
            isVisiblyHittable(),
            "Expected the control to become visibly reachable after scrolling."
        )
    }

    @MainActor
    func closeFrontmostWindow() {
        let initialWindowCount = app.windows.count
        app.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) { self.app.windows.count < initialWindowCount },
            "Command-W must close the key window without depending on AX window ordering."
        )
    }

    @MainActor
    func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in condition() },
            object: nil
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    func resizeProofWindow(
        _ window: XCUIElement,
        toWidth width: CGFloat,
        height: CGFloat? = nil
    ) {
        var currentFrame = window.frame
        guard let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame else {
            XCTFail("The responsive proof requires an attached macOS display.")
            return
        }

        let requiredShift = max(
            0,
            currentFrame.minX + width - (screenFrame.maxX - 16)
        )
        if requiredShift > 0 {
            let titlebar = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.42, dy: 0.025)
            )
            titlebar.click(
                forDuration: 0.15,
                thenDragTo: titlebar.withOffset(CGVector(dx: -requiredShift - 12, dy: 0))
            )
            XCTAssertTrue(waitUntil(timeout: 5) {
                window.frame.minX < currentFrame.minX - requiredShift / 2
            })
            currentFrame = window.frame
        }

        for _ in 0..<3 {
            currentFrame = window.frame
            let widthDelta = width - currentFrame.width
            let heightDelta = height.map { $0 - currentFrame.height } ?? 0
            if abs(widthDelta) <= QAWorkspaceMetricContract.frameTolerance,
               abs(heightDelta) <= QAWorkspaceMetricContract.frameTolerance {
                break
            }
            let resizeCorner = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.996, dy: 0.996)
            )
            resizeCorner.click(
                forDuration: 0.15,
                thenDragTo: resizeCorner.withOffset(
                    CGVector(dx: widthDelta, dy: heightDelta)
                )
            )
            _ = waitUntil(timeout: 2) {
                abs(window.frame.width - width)
                    <= QAWorkspaceMetricContract.frameTolerance
                    && (height.map {
                        abs(window.frame.height - $0)
                            <= QAWorkspaceMetricContract.frameTolerance
                    } ?? true)
            }
        }
        XCTAssertTrue(waitUntil(timeout: 5) {
            abs(window.frame.width - width) <= QAWorkspaceMetricContract.frameTolerance
                && (height.map {
                    abs(window.frame.height - $0) <= QAWorkspaceMetricContract.frameTolerance
                } ?? true)
        })
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    @MainActor

    func configuredApplication(
        sessionID: UUID,
        initialWorkspaceWidth: Int? = 1380,
        usesFixedSessionID: Bool = true,
        usesFixtureWorkspace: Bool = true,
        autosaveDelayMS: Int = 5_000,
        ignoresSystemWindowRestoration: Bool = true,
        appearance: QAAppearance? = nil,
        openNote: String? = "QA Autosave A.md"
    ) -> XCUIApplication {
        let application = XCUIApplication(bundleIdentifier: "com.scholium.qa")
        // Keep macOS scene restoration from reopening windows left by an
        // earlier isolated run. Scholium's own WindowSession snapshot tests
        // still verify application-level restoration explicitly below.
        application.launchArguments += [
            "-ApplePersistenceIgnoreState", ignoresSystemWindowRestoration ? "YES" : "NO",
        ]
        if !ignoresSystemWindowRestoration {
            application.launchArguments += ["-NSQuitAlwaysKeepsWindows", "YES"]
            application.launchEnvironment[
                "SCHOLIUM_UI_TEST_ENABLE_SYSTEM_WINDOW_RESTORATION"
            ] = "1"
        }
        application.launchArguments += [
            "-scholium.settings.selectedPane", "research-guidance",
            "-scholium.settings.researchGuidanceCategory", "Skills",
        ]
        if name.contains("testResearchWorkflowInterfaceProofs") {
            application.launchArguments += ["--scholium-research-workflow-proofs"]
        }
        if name.contains("testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm") {
            application.launchArguments += ["--scholium-document-heading-proof"]
        }
        if name.contains("testResearchWriteSetExtensionSheet") {
            application.launchArguments += ["--scholium-write-set-extension-fixture"]
        }
        if name.contains("testWindowFeedbackPlacesTransientToast")
            || name.contains("testSettingsFeedbackOverlaysTheWindow")
            || name.contains("testActionNotificationProofPresentation") {
            application.launchArguments += ["--scholium-feedback-proofs"]
        }
        if let appearance {
            application.launchArguments += ["-colorScheme", appearance.rawValue]
        }
        application.launchEnvironment["SCHOLIUM_HOME"] = homeDirectory.path
        application.launchEnvironment["CFFIXED_USER_HOME"] = homeDirectory.path
        if usesFixtureWorkspace {
            application.launchEnvironment["SCHOLIUM_UI_TEST_WORKSPACE_ROOT"] = triptychDirectory.path
        }
        if let secondTriptychDirectory {
            application.launchEnvironment[
                "SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"
            ] = secondTriptychDirectory.path
        }
        if name.contains("testRestoreAccess") {
            application.launchEnvironment[
                "SCHOLIUM_UI_TEST_FILE_SELECTION_RECOVERY"
            ] = "1"
        }
        // Keep navigation assertions independent of the user's persisted note
        // sort preference. The journey deliberately starts from A, then
        // crosses to the peer Topics vault and back again.
        if let openNote {
            application.launchEnvironment["SCHOLIUM_UI_TEST_OPEN_NOTE"] = openNote
        }
        if usesFixedSessionID {
            application.launchEnvironment["SCHOLIUM_UI_TEST_SESSION_ID"] = sessionID.uuidString
        }
        application.launchEnvironment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"] = String(autosaveDelayMS)
        if let initialWorkspaceWidth {
            application.launchEnvironment["SCHOLIUM_UI_TEST_INITIAL_WORKSPACE_WIDTH"] = String(initialWorkspaceWidth)
        }
        return application
    }

    @MainActor
    func relaunchApplication(initialWorkspaceWidth: Int) {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: initialWorkspaceWidth)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor
    func focusWorkspaceWindow(_ window: XCUIElement) {
        guard window.exists else {
            XCTFail("The requested workspace must exist before focus routing.")
            return
        }
        let targetIdentifier = window.identifier
        guard !targetIdentifier.isEmpty else {
            XCTFail("The requested workspace must expose a stable window identifier.")
            return
        }
        guard targetIdentifier.hasPrefix("scholium-main-"),
              let windowID = UUID(
                  uuidString: String(targetIdentifier.suffix(36))
              )
        else {
            XCTFail("The requested workspace must expose its native scene identity.")
            return
        }
        XCTAssertEqual(
            notify_post("com.scholium.qa.focus-workspace.\(windowID.uuidString)"),
            UInt32(NOTIFY_STATUS_OK),
            "The QA workspace focus request could not be posted."
        )
        RunLoop.current.run(until: Date().addingTimeInterval(1))
    }

    @MainActor
    func focusAuxiliaryWindow(
        _ window: XCUIElement,
        menuItemTitle: String
    ) {
        guard window.exists else {
            XCTFail("The requested auxiliary window must exist before focus routing.")
            return
        }
        let windowMenu = app.menuBars.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 3))
        windowMenu.click()
        let windowItem = app.menuItems[menuItemTitle].firstMatch
        XCTAssertTrue(windowItem.waitForExistence(timeout: 3))
        windowItem.click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    @MainActor
    func openResearchActionAndVerifyPanel(
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
        window: XCUIElement
    ) {
        selectResearchInspectorMode("actions")
        let sheet = openDiscussFromActions()
        XCTAssertGreaterThanOrEqual(sheet.frame.width, minimumWidth)
        XCTAssertLessThanOrEqual(sheet.frame.width, maximumWidth)
        XCTAssertLessThan(sheet.frame.width, window.frame.width)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.additionalContext"
        ].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchAction.focalNoteSearch"
        ].exists)
        XCTAssertFalse(app.descendants(matching: .any)[
            "scholium.researchAction.additionalInstructions"
        ].exists)
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchAction.academicText.research-request"
        ].exists)
        XCTAssertFalse(app.staticTexts["Supported modes"].exists)
        XCTAssertFalse(app.staticTexts["Required packages"].exists)
    }

    @MainActor
    @discardableResult
    func openDiscussFromActions() -> XCUIElement {
        let discuss = app.descendants(matching: .any)[
            "scholium.researchAction.discuss"
        ].firstMatch
        XCTAssertTrue(discuss.waitForExistence(timeout: 5))
        discuss.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 8))
        XCTAssertTrue(sheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        return sheet
    }

    @MainActor
    func waitForCurrentDocumentSurface() {
        let isUsable = waitUntil(timeout: 20) { self.documentSurfaceIsUsable() }
        XCTAssertTrue(
            isUsable,
            "The current window did not expose an Edit, Source, or rendered document surface."
        )
    }

    @MainActor
    func settingsWindow() -> XCUIElement {
        app.windows.allElementsBoundByIndex.first { window in
            window.descendants(matching: .any)["scholium.settings.root"].exists
        } ?? app.windows.firstMatch
    }

    @MainActor
    func researchRecordsWindow(timeout: TimeInterval = 8) -> XCUIElement {
        let recordsWindow = app.windows.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "scholium-research-records-"
            )
        ).firstMatch
        XCTAssertTrue(
            recordsWindow.waitForExistence(timeout: timeout),
            "Research Records did not expose its keyed native window."
        )
        return recordsWindow
    }

    @MainActor
    func documentSurfaceIsUsable(for relativePath: String? = nil) -> Bool {
        if let relativePath,
           !app.descendants(matching: .any)[
               "scholium.noteRow.\(relativePath)"
           ].isSelected {
            return false
        }
        let usableSurface = app.descendants(matching: .any).matching(
            NSPredicate(
                format:
                    "label IN %@ OR title IN %@ OR "
                    + "(identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@)",
                ["Markdown editor, Edit mode", "Markdown source editor"],
                ["Markdown editor, Edit mode", "Markdown source editor"],
                "scholium.renderedDocument.",
                "scholium.renderedDocument.loading",
                "scholium.renderedDocument.failed"
            )
        ).firstMatch
        return usableSurface.exists
    }

    /// Exercises the stable native-toolbar Sidebar and Inspector visibility
    /// controls through their actual pointer hit-testing paths.
    @MainActor
    func exercisePeripheralVisibilityControls() {
        waitForCurrentDocumentSurface()
        let toolbar = app.toolbars.firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5))

        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        if !library.exists {
            let showSidebar = toolbar.buttons["Show Sidebar"].firstMatch
            XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
            showSidebar.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
            XCTAssertTrue(library.waitForExistence(timeout: 5))
        }

        let hideSidebar = toolbar.buttons["Hide Sidebar"].firstMatch
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(hideSidebar.isHittable)
        XCTAssertEqual(
            toolbar.buttons.matching(
                NSPredicate(format: "label IN %@", ["Show Sidebar", "Hide Sidebar"])
            ).count,
            1
        )
        hideSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !library.exists })

        let showSidebar = toolbar.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(showSidebar.isHittable)
        XCTAssertEqual(
            toolbar.buttons.matching(
                NSPredicate(format: "label IN %@", ["Show Sidebar", "Hide Sidebar"])
            ).count,
            1
        )
        showSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(library.waitForExistence(timeout: 5))

        let inspector = app.scrollViews["scholium.researchInspector"].firstMatch
        if inspector.exists {
            let hideInspector = toolbar.buttons["Hide Research Inspector"].firstMatch
            XCTAssertTrue(hideInspector.waitForExistence(timeout: 5))
            hideInspector.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
            XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        }

        let showInspector = toolbar.buttons["Show Research Inspector"].firstMatch
        XCTAssertTrue(showInspector.waitForExistence(timeout: 5))
        XCTAssertTrue(showInspector.isHittable)
        XCTAssertEqual(
            toolbar.buttons.matching(
                NSPredicate(
                    format: "label IN %@",
                    ["Show Research Inspector", "Hide Research Inspector"]
                )
            ).count,
            1
        )
        showInspector.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        let hideInspector = toolbar.buttons["Hide Research Inspector"].firstMatch
        XCTAssertTrue(hideInspector.waitForExistence(timeout: 5))
        XCTAssertTrue(hideInspector.isHittable)
        XCTAssertEqual(
            toolbar.buttons.matching(
                NSPredicate(
                    format: "label IN %@",
                    ["Show Research Inspector", "Hide Research Inspector"]
                )
            ).count,
            1
        )
        hideInspector.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
    }

    @MainActor
    @discardableResult
    func selectResearchInspectorMode(_ mode: String) -> XCUIElement {
        let inspector = app.descendants(matching: .any)[
            "scholium.researchInspector"
        ].firstMatch
        if !inspector.exists {
            let toggle = inspectorVisibilityControl()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntil(timeout: 3) { toggle.isHittable })
            toggle.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        let modeButton = app.buttons[
            "scholium.inspectorMode.\(mode)"
        ].firstMatch
        XCTAssertTrue(modeButton.waitForExistence(timeout: 5))
        modeButton.click()

        let contentIdentifier: String
        switch mode {
        case "overview": contentIdentifier = "scholium.about"
        case "connect": contentIdentifier = "scholium.connectionGroup.0"
        case "actions": contentIdentifier = "scholium.researchAction.discuss"
        default:
            XCTFail("Unknown Inspector mode: \(mode)")
            return inspector
        }
        XCTAssertTrue(
            app.descendants(matching: .any)[contentIdentifier]
                .waitForExistence(timeout: mode == "actions" ? 45 : 8)
        )
        let scrollableInspector = app.scrollViews[
            "scholium.researchInspector"
        ].firstMatch
        return scrollableInspector.exists ? scrollableInspector : inspector
    }

    @MainActor
    func openNote(
        _ relativePath: String,
        expectedTitle: String,
        in window: XCUIElement
    ) {
        focusWorkspaceWindow(window)
        let row = window.descendants(matching: .any)["scholium.noteRow.\(relativePath)"]
        XCTAssertTrue(
            row.waitForExistence(timeout: 10),
            "The requested note must be available in the target window."
        )
        row.click()
        XCTAssertTrue(
            waitForDocumentTitle(expectedTitle, in: window, timeout: 10),
            "The target window must finish opening the requested note."
        )
    }

    @MainActor
    func selectVault(
        _ identifier: String,
        waitingFor rowIdentifier: String
    ) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any)[rowIdentifier]
        let deadline = Date().addingTimeInterval(20)
        repeat {
            button.click()
            if row.waitForExistence(timeout: 5) { return }
        } while Date() < deadline
        XCTFail("The selected vault did not publish its expected Library content.")
    }

    @MainActor
    func selectionControlIsSelected(_ control: XCUIElement) -> Bool {
        if let value = control.value as? NSNumber {
            return value.boolValue
        }
        guard let value = control.value as? String else { return false }
        return ["1", "true", "selected", "checked"].contains(value.lowercased())
    }

    @MainActor
    func checkboxIsSelected(_ checkbox: XCUIElement) -> Bool {
        selectionControlIsSelected(checkbox)
    }

    @MainActor
    func enterLivePreviewAndAppend(_ token: String, in root: XCUIElement? = nil) throws {
        let editor = enterLivePreview(in: root)
        editor.typeKey(.end, modifierFlags: [.command])
        try setPasteboardText(token)
        editor.typeKey("v", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                (editor.value as? String ?? "").contains(token)
            },
            "The editor must accept the complete synthetic token before the journey tests a save or navigation boundary."
        )
    }

    @MainActor
    func enterLivePreviewAndPrepend(_ token: String, in root: XCUIElement? = nil) throws {
        let editor = enterLivePreview(in: root)
        editor.typeKey(.home, modifierFlags: [.command])
        try setPasteboardText(token + "\n")
        editor.typeKey("v", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                (editor.value as? String ?? "").contains(token)
            },
            "The editor must accept the complete synthetic token before the journey tests a save or navigation boundary."
        )
    }

    @MainActor
    func selectDocumentMode(_ title: String, in root: XCUIElement? = nil) {
        if let root { focusWorkspaceWindow(root) }
        let mode = documentModeControl(in: root)
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if mode.value as? String == title { return }

        switch title {
        case "Review":
            app.typeKey("r", modifierFlags: [.command])
        case "Edit":
            if mode.value as? String == "Source" {
                app.typeKey("r", modifierFlags: [.command])
                XCTAssertTrue(waitUntil(timeout: 8) { mode.value as? String == "Review" })
            }
            app.typeKey("r", modifierFlags: [.command])
        case "Source":
            app.menuBars.menuBarItems["View"].click()
            let documentModeMenu = app.menuItems["Document Mode"].firstMatch
            XCTAssertTrue(documentModeMenu.waitForExistence(timeout: 3))
            documentModeMenu.hover()
            let source = app.menuItems["Source"].firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 3))
            source.click()
        default:
            XCTFail("Unsupported Document mode: \(title)")
            return
        }

        XCTAssertTrue(
            waitUntil(timeout: 10) { mode.value as? String == title },
            "The Document mode did not become \(title)."
        )
    }

    @MainActor
    func documentModeControl(in root: XCUIElement? = nil) -> XCUIElement {
        if let root {
            return root.toolbars.firstMatch.buttons["Document Mode"].firstMatch
        }
        return app.toolbars.firstMatch.buttons["Document Mode"].firstMatch
    }

    @MainActor
    func inspectorVisibilityControl(in root: XCUIElement? = nil) -> XCUIElement {
        let toolbar = root?.toolbars.firstMatch ?? app.toolbars.firstMatch
        let show = toolbar.buttons["Show Research Inspector"].firstMatch
        return show.exists ? show : toolbar.buttons["Hide Research Inspector"].firstMatch
    }

    @MainActor
    func sidebarVisibilityControl(in root: XCUIElement? = nil) -> XCUIElement {
        let toolbar = root?.toolbars.firstMatch ?? app.toolbars.firstMatch
        let show = toolbar.buttons["Show Sidebar"].firstMatch
        return show.exists ? show : toolbar.buttons["Hide Sidebar"].firstMatch
    }

    @MainActor
    func researchRecordsControl(in root: XCUIElement? = nil) -> XCUIElement {
        let toolbar = root?.toolbars.firstMatch ?? app.toolbars.firstMatch
        let noteRecords = toolbar.buttons["This Note Records"].firstMatch
        return noteRecords.exists
            ? noteRecords
            : toolbar.buttons["Triptych Records"].firstMatch
    }

    @MainActor
    func clickInspectorVisibilityControl(in root: XCUIElement? = nil) {
        let control = inspectorVisibilityControl(in: root)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { control.isHittable })
        control.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
    }

    @MainActor
    func clickSidebarVisibilityControl(in root: XCUIElement? = nil) {
        let control = sidebarVisibilityControl(in: root)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { control.isHittable })
        control.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
    }

    @MainActor
    func clickResearchRecordsControl(in root: XCUIElement? = nil) {
        let control = researchRecordsControl(in: root)
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { control.isHittable })
        control.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
    }

    @MainActor
    func documentTitle(in root: XCUIElement? = nil) -> String? {
        let window: XCUIElement
        if let root {
            window = root
        } else {
            window = app.windows.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
            ).firstMatch
        }
        guard window.exists else { return nil }
        return window.title
    }

    @MainActor
    func documentTitleElement(in root: XCUIElement? = nil) -> XCUIElement {
        let window = root ?? app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        guard let title = documentTitle(in: window) else {
            return window.staticTexts.firstMatch
        }
        return window.staticTexts.matching(
            NSPredicate(format: "value == %@ OR label == %@", title, title)
        ).firstMatch
    }

    @MainActor
    func waitForDocumentTitle(
        _ expectedTitle: String,
        in root: XCUIElement? = nil,
        timeout: TimeInterval = 10
    ) -> Bool {
        waitUntil(timeout: timeout) {
            self.documentTitle(in: root) == expectedTitle
        }
    }

    @MainActor
    func enterLivePreview(in root: XCUIElement? = nil) -> XCUIElement {
        selectDocumentMode("Edit", in: root)

        let editor = root?.descendants(matching: .any)["Markdown editor, Edit mode"]
            ?? app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 8) { editor.isHittable })
        // The mode transition requests focus, but XCUITest must still prove
        // that the WebKit text surface is the active command target before it
        // sends editing or document-session shortcuts.
        editor.click()
        return editor
    }

    @MainActor
    func chooseSetupFolder(_ folder: URL, role: String) {
        let openPanelButton = app.buttons["Choose Folder…"]
        XCTAssertTrue(openPanelButton.waitForExistence(timeout: 5))
        openPanelButton.click()

        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let goToFolderSheet = panel.sheets.firstMatch
        XCTAssertTrue(goToFolderSheet.waitForExistence(timeout: 5))
        let pathField = goToFolderSheet.textFields.firstMatch
        XCTAssertTrue(pathField.waitForExistence(timeout: 5))
        pathField.click()
        pathField.typeKey("a", modifierFlags: .command)
        pathField.typeText(folder.path)
        // The system Go to Folder sheet can expose a transiently abbreviated
        // accessibility value while it resolves a long path. The Open panel
        // closing and the configured workspace journeys below prove that the
        // requested folder was actually selected.
        for _ in 0..<2 where goToFolderSheet.exists {
            app.typeKey(.return, modifierFlags: [])
            _ = waitUntil(timeout: 2) { !goToFolderSheet.exists }
        }
        XCTAssertTrue(waitUntil(timeout: 5) { !goToFolderSheet.exists })

        let choose = panel.buttons["OKButton"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { choose.isEnabled })
        choose.click()

        XCTAssertTrue(
            waitUntil(timeout: 5) { !choose.exists },
            "Expected the standard Open panel to close after choosing the \(role) folder."
        )
    }

    @MainActor
    func authorizePortableFolder(_ folder: URL, in owner: XCUIElement? = nil) {
        let authorizeButton = owner == nil
            ? app.buttons["Authorize This Folder"]
            : app.buttons["Authorize folder containing Works"]
        XCTAssertTrue(authorizeButton.waitForExistence(timeout: 5))
        authorizeButton.click()

        let panel = app.descendants(matching: .any)["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        if let owner {
            XCTAssertTrue(owner.exists)
            XCTAssertFalse(authorizeButton.isHittable)
            XCTAssertEqual(
                app.descendants(matching: .any)
                    .matching(identifier: "open-panel").count,
                1,
                "The originating window must present one standard Open panel."
            )
        }
        if owner != nil {
            let folderEntry = panel.descendants(matching: .any).matching(
                NSPredicate(format: "value == %@", folder.lastPathComponent)
            ).firstMatch
            XCTAssertTrue(folderEntry.waitForExistence(timeout: 5))
            folderEntry.click()
        }

        let authorize = panel.buttons["OKButton"]
        XCTAssertTrue(authorize.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { authorize.isEnabled })
        authorize.click()

        XCTAssertTrue(waitUntil(timeout: 5) { !authorize.exists })
    }

    func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func pasteboardText() throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }

    func setPasteboardText(_ text: String) throws {
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
    }

    func runScholiumCLI(
        _ arguments: [String],
        stdin: Data? = nil
    ) throws -> String {
        // The QA app keeps its live registry beneath its isolated Application
        // Support root, while an explicitly isolated CLI resolves a frozen
        // invocation registry at <SCHOLIUM_HOME>/registry. Copy that small
        // registry only after the app has configured this disposable
        // Triptych. The CLI then exercises the real packaged boundary without
        // receiving a synthetic assignment or touching researcher state.
        let appRegistry = homeDirectory
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
        let cliRegistry = homeDirectory
            .appendingPathComponent("registry", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appRegistry.path) else {
            throw NSError(
                domain: "ScholiumUITests.CLI",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The isolated QA registry is unavailable.",
                ]
            )
        }
        if !FileManager.default.fileExists(atPath: cliRegistry.path) {
            try FileManager.default.copyItem(at: appRegistry, to: cliRegistry)
        }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot
            .appendingPathComponent(".build/qa-swiftpm/debug/scholium")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["SCHOLIUM_HOME"] = homeDirectory.path
        environment["CFFIXED_USER_HOME"] = homeDirectory.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = error
        let input = stdin.map { _ in Pipe() }
        if let input {
            process.standardInput = input
        }
        try process.run()
        if let input, let stdin {
            input.fileHandleForWriting.write(stdin)
            try input.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        let stdout = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let stderr = String(
            decoding: error.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ScholiumUITests.CLI",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderr]
            )
        }
        return stdout
    }

    @MainActor
    func paste(_ text: String, into element: XCUIElement) throws {
        try setPasteboardText(text)
        element.click()
        element.typeKey("a", modifierFlags: [.command])
        element.typeKey("v", modifierFlags: [.command])
    }

    @MainActor
    func openResearchGuidance(openAdvanced: Bool = false) {
        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let destination = app.descendants(matching: .any)[
            openAdvanced
                ? "scholium.settings.destination.externalToolsCitations"
                : "scholium.settings.destination.skills"
        ]
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        destination.click()
        if openAdvanced {
            XCTAssertTrue(app.staticTexts[
                "External Tools & Citations"
            ].waitForExistence(timeout: 20))
            let advancedScroll = app.scrollViews[
                "scholium.researchGuidance.detail"
            ].firstMatch
            XCTAssertTrue(advancedScroll.waitForExistence(timeout: 20))
            let copyInstructions = app.buttons[
                "scholium.agentCLI.copyInstructions"
            ]
            for _ in 0..<8 where !copyInstructions.exists {
                advancedScroll.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(
                copyInstructions.waitForExistence(timeout: 10)
                )
        }
    }

    private struct QAStoredNoteIdentity {
        let noteID: UUID
        let vaultID: UUID
        let relativePath: String
        let fingerprint: [String: Any]
    }

    struct QANoteReviewRecordSeed {
        struct Participant {
            let relativePath: String
            let role: String
            let title: String
        }

        let recordID: UUID
        let title: String
        let primaryRelativePath: String
        let participants: [Participant]
        let changedRelativePaths: Set<String>
        let finishedAt: String
    }

    func seedResearchRecordFixture(
        hasUnavailableTopicRevision: Bool = false,
        hasEvidenceOverflow: Bool = false,
        createsSynthesisAttention: Bool = false
    ) throws -> QAResearchRecordFixture {
        let triptychID = try triptychID(at: triptychDirectory)
        let manifestURL = triptychDirectory.appendingPathComponent(
            ".scholium/manifest.json"
        )
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: manifestURL)
            ) as? [String: Any]
        )
        let currentVaultIDs = Set(
            (manifest["vaultIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        )
        let identityURL = triptychDirectory.appendingPathComponent(
            ".scholium/identities.json"
        )
        let identityDocument = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: identityURL)
            ) as? [String: Any]
        )
        let records = identityDocument["records"] as? [[String: Any]] ?? []

        func identity(_ relativePath: String) throws -> QAStoredNoteIdentity {
            let record = try XCTUnwrap(records.first(where: { candidate in
                guard candidate["relativePath"] as? String == relativePath,
                      let vault = candidate["vaultID"] as? String,
                      let vaultID = UUID(uuidString: vault) else { return false }
                return currentVaultIDs.contains(vaultID)
            }))
            return QAStoredNoteIdentity(
                noteID: try XCTUnwrap(
                    (record["id"] as? String).flatMap(UUID.init(uuidString:))
                ),
                vaultID: try XCTUnwrap(
                    (record["vaultID"] as? String).flatMap(UUID.init(uuidString:))
                ),
                relativePath: relativePath,
                fingerprint: try XCTUnwrap(record["fingerprint"] as? [String: Any])
            )
        }

        let analysis = try identity("QA Autosave A.md")
        let secondAnalysis = try identity("QA Autosave B.md")
        let topic = try identity("QA Topic.md")
        let work = try identity("QA Work.md")
        let recordID = UUID(uuidString: "5E551019-0000-4000-8000-000000000001")!
        let agentStatementID = UUID(uuidString: "5E551019-0000-4000-8000-000000000002")!
        let researcherStatementID = UUID(
            uuidString: "5E551019-0000-4000-8000-000000000006"
        )!
        let recommendationID = qaResearchRecommendationID(
            runID: recordID,
            ordinal: 0
        )
        let sourceID = UUID(uuidString: "5E551019-0000-4000-8000-000000000005")!
        let startedAt = "2026-07-27T04:00:00Z"
        let finishedAt = "2026-07-27T04:01:00Z"
        let profileRevision = qaFingerprint("QA bounded Analyze Profile")
        func note(
            _ identity: QAStoredNoteIdentity,
            role: String,
            title: String,
            recordedRelativePath: String? = nil
        ) -> [String: Any] {
            [
                "note_id": identity.noteID.uuidString,
                "note": [
                    "vaultID": identity.vaultID.uuidString,
                    "relativePath": recordedRelativePath ?? identity.relativePath,
                ],
                "role": role,
                "title": title,
                "starting_revision": identity.fingerprint,
                "ending_revision": identity.fingerprint,
            ]
        }

        var topicParticipant = note(
            topic,
            role: "topic",
            title: "QA Topic",
            recordedRelativePath: "Historical/QA Topic Before Rename.md"
        )
        let topicStartingRevision: [String: Any]
        if hasUnavailableTopicRevision {
            topicStartingRevision = [
                "sha256": String(repeating: "0", count: 64),
                "byteCount": 1,
            ]
        } else {
            topicStartingRevision = topic.fingerprint
        }
        topicParticipant["starting_revision"] = topicStartingRevision

        var participatingNotes: [[String: Any]] = [
            note(analysis, role: "analysis", title: "QA Autosave A"),
            topicParticipant,
        ]
        if hasEvidenceOverflow {
            participatingNotes.append(
                note(secondAnalysis, role: "analysis", title: "QA Autosave B")
            )
            participatingNotes.append(
                note(work, role: "work", title: "QA Work")
            )
        }

        var portableRecord: [String: Any] = [
            "schema_version": 17,
            "id": recordID.uuidString,
            "triptych_id": triptychID.uuidString,
            "record_title": createsSynthesisAttention
                ? "The practical consequences of fittingness"
                : "Emotional fittingness and practical attention",
            "kind": "action",
            "action": [
                "schema_version": 2,
                "action_id": createsSynthesisAttention ? "synthesize" : "analyze",
                "material_note_ids": createsSynthesisAttention
                    ? [analysis.noteID.uuidString]
                    : [],
            ],
            "method": [
                "registration_key": createsSynthesisAttention
                    ? "10000000-0000-0000-0000-000000000003"
                    : "10000000-0000-0000-0000-000000000002",
                "display_name": createsSynthesisAttention
                    ? "Synthesize"
                    : "Analyze Note",
                "profile_revision": profileRevision,
            ],
            "participating_notes": participatingNotes,
            "statements": [
                [
                    "id": researcherStatementID.uuidString,
                    "author": "researcher",
                    "kind": "researcher_response",
                    "attribution": "Researcher",
                    "text": "Distinguish the emotion's evaluative target from what it gives me reason to do; do not treat salience as authority.",
                    "created_at": startedAt,
                ],
                [
                    "id": agentStatementID.uuidString,
                    "author": "agent",
                    "kind": "agent_feedback",
                    "attribution": "Synthetic Action Agent",
                    "text": "The available material supports a narrower distinction: fittingness concerns the emotion's normative target, while practical uptake remains a further question in deliberation.",
                    "created_at": finishedAt,
                ],
            ],
            "result_disposition": "completed",
            "academic_results": [],
            "fidelity_completion": "unverified",
            "confirmed_changes": [],
            "discrepancies": [],
            "literature_recommendations": createsSynthesisAttention ? [] : [[
                "id": recommendationID.uuidString,
                "raw_citation": "Ada Rivera, Source-Grounded Inquiry (2024).",
                "title": "Source-Grounded Inquiry",
                "authors": ["Ada Rivera"],
                "year": 2024,
                "publication": "Journal of Source-Grounded Inquiry",
                "doi": "10.1000/qa-reading",
                "zotero_item_key": "QAREAD01",
                "source_locators": ["p. 42"],
                "reason": "The analyzed source identifies this work as a key account of source-grounded inquiry.",
                "uncertainty": "The source gives only a brief characterization.",
                "disposition": [
                    "status": "unprocessed",
                    "updated_at": finishedAt,
                ],
            ]],
            "started_at": startedAt,
            "finished_at": finishedAt,
        ]
        if createsSynthesisAttention {
            portableRecord["primary_note_id"] = topic.noteID.uuidString
        } else {
            portableRecord["primary_note_id"] = analysis.noteID.uuidString
            portableRecord["analysis_source_route"] = "scholium_source"
            portableRecord["source_reference"] = [
                "schemaVersion": 1,
                "identity": [
                    "schemaVersion": 1,
                    "id": sourceID.uuidString,
                    "route": "local_file",
                ],
                "displayName": "QA Source.pdf",
                "fingerprint": qaFingerprint("QA exact analyzed source bytes"),
            ]
        }

        let recordsDirectory = triptychDirectory.appendingPathComponent(
            ".scholium/research-records/v1/records",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recordsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )
        let recordURL = recordsDirectory.appendingPathComponent(
            recordID.uuidString.lowercased() + ".json"
        )
        try JSONSerialization.data(
            withJSONObject: portableRecord,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ).write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: recordURL.path
        )

        if createsSynthesisAttention {
            let analysisURL = triptychDirectory.appendingPathComponent(
                "01-analyses/QA Autosave A.md"
            )
            let source = try String(contentsOf: analysisURL, encoding: .utf8)
            try write(
                source + "\nA changed Analysis revision for bounded Attention QA.\n",
                to: analysisURL
            )
        }

        return QAResearchRecordFixture(
            recordID: recordID,
            researcherStatementID: researcherStatementID,
            agentStatementID: agentStatementID,
            recommendationID: createsSynthesisAttention ? nil : recommendationID,
            analysisNoteID: analysis.noteID,
            topicNoteID: topic.noteID,
            overflowParticipantNoteIDs: hasEvidenceOverflow
                ? [secondAnalysis.noteID, work.noteID]
                : []
        )
    }

    /// Seeds current portable Action Records through the real store boundary.
    /// The pre-Agent revisions are deliberately unavailable synthetic exact
    /// fingerprints: the UI journey verifies association, pending Review, and
    /// read-only comparison ownership without manufacturing recoverable source
    /// bytes or granting Undo authority.
    func seedNoteReviewRecords(
        _ seeds: [QANoteReviewRecordSeed]
    ) throws {
        let triptychID = try triptychID(at: triptychDirectory)
        let identities = try qaStoredNoteIdentities()
        let recordsDirectory = triptychDirectory.appendingPathComponent(
            ".scholium/research-records/v1/records",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recordsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )

        for seed in seeds {
            let participants = try seed.participants.map { participant -> [String: Any] in
                let identity = try XCTUnwrap(identities[participant.relativePath])
                let ending = identity.fingerprint
                let starting = seed.changedRelativePaths.contains(participant.relativePath)
                    ? qaFingerprint(
                        "Before Agent work \(seed.recordID.uuidString.lowercased()) \(participant.relativePath)"
                    )
                    : ending
                return [
                    "note_id": identity.noteID.uuidString,
                    "note": [
                        "vaultID": identity.vaultID.uuidString,
                        "relativePath": identity.relativePath,
                    ],
                    "role": participant.role,
                    "title": participant.title,
                    "starting_revision": starting,
                    "ending_revision": ending,
                ]
            }
            let primary = try XCTUnwrap(identities[seed.primaryRelativePath])
            let confirmedChanges = try seed.changedRelativePaths.sorted().map {
                relativePath -> [String: Any] in
                let identity = try XCTUnwrap(identities[relativePath])
                return [
                    "note_id": identity.noteID.uuidString,
                    "actor": "agent",
                    "kind": "modified",
                    "starting_revision": qaFingerprint(
                        "Before Agent work \(seed.recordID.uuidString.lowercased()) \(relativePath)"
                    ),
                    "ending_revision": identity.fingerprint,
                ]
            }
            let statementID = qaStableUUID(
                "\(seed.recordID.uuidString.lowercased()):agent-result"
            )
            let profileRevision = qaFingerprint("QA bounded Synthesize Profile")
            let materialNoteIDs = try seed.participants.compactMap {
                participant -> String? in
                guard participant.role == "analysis" else { return nil }
                return try XCTUnwrap(
                    identities[participant.relativePath]
                ).noteID.uuidString
            }
            let record: [String: Any] = [
                "schema_version": 17,
                "id": seed.recordID.uuidString,
                "triptych_id": triptychID.uuidString,
                "record_title": seed.title,
                "kind": "action",
                "action": [
                    "schema_version": 2,
                    "action_id": "synthesize",
                    "material_note_ids": materialNoteIDs,
                ],
                "method": [
                    "registration_key": "10000000-0000-0000-0000-000000000003",
                    "display_name": "Synthesize",
                    "profile_revision": profileRevision,
                ],
                "primary_note_id": primary.noteID.uuidString,
                "participating_notes": participants,
                "statements": [[
                    "id": statementID.uuidString,
                    "author": "agent",
                    "kind": "agent_feedback",
                    "attribution": "Synthetic QA Agent",
                    "text": "This disposable Record exists only to verify the current Note Review interface.",
                    "created_at": seed.finishedAt,
                ]],
                "result_disposition": "completed",
                "academic_results": [],
                "fidelity_completion": "unverified",
                "confirmed_changes": confirmedChanges,
                "discrepancies": [],
                "literature_recommendations": [],
                "started_at": "2026-08-09T03:00:00Z",
                "finished_at": seed.finishedAt,
            ]
            try writePortableResearchRecord(record, id: seed.recordID)
        }
    }

    func seedNoteReviewCutoverFixture() throws {
        let origin = QANoteReviewRecordSeed.Participant(
            relativePath: "QA Autosave A.md",
            role: "analysis",
            title: "QA Autosave A"
        )
        let topic = QANoteReviewRecordSeed.Participant(
            relativePath: "QA Topic.md",
            role: "topic",
            title: "QA Topic"
        )
        let work = QANoteReviewRecordSeed.Participant(
            relativePath: "QA Work.md",
            role: "work",
            title: "QA Work"
        )
        try seedNoteReviewRecords([
            QANoteReviewRecordSeed(
                recordID: UUID(
                    uuidString: "8A410000-0000-4000-8000-000000000001"
                )!,
                title: "Multi-Note Agent revision",
                primaryRelativePath: origin.relativePath,
                participants: [origin, topic, work],
                changedRelativePaths: [topic.relativePath, work.relativePath],
                finishedAt: "2026-08-09T03:01:00Z"
            ),
            QANoteReviewRecordSeed(
                recordID: UUID(
                    uuidString: "8A410000-0000-4000-8000-000000000002"
                )!,
                title: "Later Topic revision",
                primaryRelativePath: topic.relativePath,
                participants: [topic],
                changedRelativePaths: [topic.relativePath],
                finishedAt: "2026-08-09T03:02:00Z"
            ),
        ])
    }

    func externallyReplaceResearcherResponse(
        recordID: UUID,
        evaluationText: String
    ) throws {
        let recordURL = portableResearchRecordURL(recordID)
        var record = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: recordURL)
            ) as? [String: Any]
        )
        record["researcher_evaluation"] = [
            "revision": UUID().uuidString,
            "author": "researcher",
            "observed_issues": [],
            "no_issues_observed": true,
            "valuable_discovery": false,
            "note": evaluationText,
            "updated_at": "2026-08-10T04:00:00Z",
        ]
        record["method_feedback_comment"] = nil
        try writePortableResearchRecord(record, id: recordID)
    }

    func portableResearchRecordSource(_ id: UUID) throws -> String {
        try source(at: portableResearchRecordURL(id))
    }

    /// Portable stores live under the hidden Triptych boundary and do not
    /// themselves generate a vault-document inventory event. Pair a synthetic
    /// external Record arrival with a harmless disposable Note edit so the
    /// real workspace watcher rebuilds the complete snapshot exactly as it
    /// would after an Agent commit followed by Result formation.
    func triggerWorkspaceRefreshForPortableFixture(_ marker: String) throws {
        let url = triptychDirectory.appendingPathComponent(
            "01-analyses/QA Autosave B.md"
        )
        let current = try source(at: url)
        try write(
            current + "\n<!-- disposable portable fixture refresh: \(marker) -->\n",
            to: url
        )
    }

    func latestLocalResearchExecutionRunID() throws -> UUID {
        let directory = try localResearchExecutionDirectoryURL()
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { $0.pathExtension == "json" }
        let latest = try XCTUnwrap(candidates.max { lhs, rhs in
            let left = try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            let right = try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            return (left ?? .distantPast) < (right ?? .distantPast)
        })
        return try XCTUnwrap(UUID(uuidString: latest.deletingPathExtension().lastPathComponent))
    }

    private func qaStoredNoteIdentities() throws -> [String: QAStoredNoteIdentity] {
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent(
                    ".scholium/manifest.json"
                ))
            ) as? [String: Any]
        )
        let currentVaultIDs = Set(
            (manifest["vaultIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        )
        let identityDocument = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent(
                    ".scholium/identities.json"
                ))
            ) as? [String: Any]
        )
        let records = identityDocument["records"] as? [[String: Any]] ?? []
        return Dictionary(uniqueKeysWithValues: records.compactMap { record in
            guard let relativePath = record["relativePath"] as? String,
                  let rawNoteID = record["id"] as? String,
                  let noteID = UUID(uuidString: rawNoteID),
                  let rawVaultID = record["vaultID"] as? String,
                  let vaultID = UUID(uuidString: rawVaultID),
                  currentVaultIDs.contains(vaultID),
                  let fingerprint = record["fingerprint"] as? [String: Any] else {
                return nil
            }
            return (
                relativePath,
                QAStoredNoteIdentity(
                    noteID: noteID,
                    vaultID: vaultID,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                )
            )
        })
    }

    private func qaStableUUID(_ source: String) -> UUID {
        let digest = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let value = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }

    private func portableResearchRecordURL(_ id: UUID) -> URL {
        triptychDirectory.appendingPathComponent(
            ".scholium/research-records/v1/records/\(id.uuidString.lowercased()).json"
        )
    }

    private func writePortableResearchRecord(
        _ record: [String: Any],
        id: UUID
    ) throws {
        let recordURL = portableResearchRecordURL(id)
        try FileManager.default.createDirectory(
            at: recordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o755)]
        )
        try JSONSerialization.data(
            withJSONObject: record,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ).write(to: recordURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: recordURL.path
        )
    }

    func seedSynthesisAttentionFixture() throws -> QAResearchRecordFixture {
        try seedResearchRecordFixture(createsSynthesisAttention: true)
    }

    func createSecondTriptychFixture() throws -> URL {
        let destination = testDirectory.appendingPathComponent(
            "Second Triptych",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        for component in ["01-analyses", "02-topics", "03-works"] {
            try FileManager.default.copyItem(
                at: triptychDirectory.appendingPathComponent(component, isDirectory: true),
                to: destination.appendingPathComponent(component, isDirectory: true)
            )
        }
        return destination
    }

    func triptychID(at root: URL) throws -> UUID {
        let document = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent(
                    ".scholium/manifest.json"
                ))
            ) as? [String: Any]
        )
        return try XCTUnwrap(
            (document["id"] as? String).flatMap(UUID.init(uuidString:))
        )
    }

    func qaFingerprint(_ source: String) -> [String: Any] {
        let data = Data(source.utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ["sha256": digest, "byteCount": data.count]
    }

    func qaResearchRecommendationID(runID: UUID, ordinal: Int) -> UUID {
        let source = "\(runID.uuidString.lowercased()):literature-recommendation:\(ordinal)"
        let digest = SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let value = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }

    func createIsolatedTriptych() throws {
        // The Xcode 26.6 runner can deny a sandboxed test bundle direct writes
        // to the literal /tmp root. Its process-specific temporary directory
        // remains test-owned and is also reachable by the unsandboxed QA app.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-XCUITests", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString, isDirectory: true)
        testDirectory = root
        homeDirectory = root.appendingPathComponent("home", isDirectory: true)
        triptychDirectory = root.appendingPathComponent("Triptych", isDirectory: true)

        // `run-ui-tests.sh` first makes one disposable copy of the researcher-
        // approved static TestVaults root. Every journey clones that test-owned
        // copy and uses its existing QA Autosave A/B, QA Topic, and QA Work
        // anchors. Only state-specific records absent from the static fixture
        // may be added below. No UI test opens or mutates Desktop/TestVaults.
        // Xcode's macOS UI-test runner does not consistently inherit arbitrary
        // shell environment variables. Prefer the explicit runner value when
        // available, then fall back to the same repository-local staging path
        // derived from this compiled test source. Neither route can resolve to
        // the researcher's Desktop TestVaults source.
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let stagedFixturePath = ProcessInfo.processInfo.environment["SCHOLIUM_QA_FIXTURES"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? sourceRoot.appendingPathComponent(".build/qa-runtime/fixtures", isDirectory: true).path
        let stagedFixtures = URL(fileURLWithPath: stagedFixturePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: stagedFixtures.path) else {
            throw NSError(
                domain: "ScholiumUITests.Configuration",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The disposable TestVaults copy was not staged by build-qa-app.sh.",
                ]
            )
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: stagedFixtures, to: triptychDirectory)

        if name.contains("testResearchActionsRolePointerKeyboardFocusAccessibilityAndMinimumWidth")
            || name.contains("testResearchActionsVoiceOverSpeechOrder")
            || name.contains("testResearchActionsRemainUsableInLightAndDarkAppearances")
            || name.contains("testLineCommentAgentReplyArchivesRecord")
            || name.contains("testCritiqueActionUsesTriptychWorkingMethodWithoutAdHocPrompting")
            || name.contains(
                "testNoChangeActionResultsShareDocumentTopWithoutCreatingNoteReview"
            )
            || name.contains("testResearchActionPanelFits") {
            try resetResearchActionFixtureState()
        }

        let analyses = triptychDirectory.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = triptychDirectory.appendingPathComponent("02-topics", isDirectory: true)
        let works = triptychDirectory.appendingPathComponent("03-works", isDirectory: true)
        let critiques = works.appendingPathComponent("Critiques", isDirectory: true)
        for directory in [homeDirectory!, analyses, topics, works, critiques] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        for staticAnchor in [
            analyses.appendingPathComponent("QA Autosave A.md"),
            analyses.appendingPathComponent("QA Autosave B.md"),
            topics.appendingPathComponent("QA Topic.md"),
            works.appendingPathComponent("QA Work.md"),
        ] where !FileManager.default.fileExists(atPath: staticAnchor.path) {
            throw NSError(
                domain: "ScholiumUITests.Configuration",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The static TestVault anchor is missing: \(staticAnchor.lastPathComponent)",
                ]
            )
        }
        try seedManagedTopicAliases(
            relativePath: "QA Topic.md",
            aliases: [
                "Synthetic Topic Alias 001",
                "Fixture Concept 001",
                "Normative QA Nexus",
            ]
        )
        if name.contains(
            "testNoChangeActionResultsShareDocumentTopWithoutCreatingNoteReview"
        ) {
            let topicURL = topics.appendingPathComponent("QA Topic.md")
            let source = try source(at: topicURL)
            let opening = (1...18).map { index in
                "Synthetic reading context \(index) precedes the stable Document anchor and contains no private research material."
            }.joined(separator: "\n\n")
            let closing = (19...36).map { index in
                "Synthetic reading context \(index) follows the stable Document anchor and keeps this disposable fixture scrollable."
            }.joined(separator: "\n\n")
            let extendedSource = source
                + "\n\n## Notification priority reading fixture\n\n"
                + opening
                + "\n\nNotification priority reading anchor remains in context.\n\n"
                + closing
                + "\n"
            try write(
                extendedSource,
                to: topicURL
            )
            try updateStoredNoteFingerprint(
                relativePath: "QA Topic.md",
                source: extendedSource
            )
        }
        if name.contains(
            "testSidebarWorkspaceLibraryAndTriptychAttentionWindowJourney"
        ) {
            synthesisAttentionFixture = try seedSynthesisAttentionFixture()
        }
        if name.contains("testCanonicalAcceptanceJourney")
            || name.contains("testOverviewRoutesZoteroOnlyFromCurrentAnalysis") {
            try seedAnalysisZoteroBinding(
                relativePath: "QA Autosave A.md",
                itemKey: "QAITEM01"
            )
        }
        if name.contains("testAppearanceLineWidthVisualMatrixAndKeyboardControl") {
            let visualNoteURL = analyses.appendingPathComponent("QA Autosave A.md")
            let existingVisualFixture = try String(
                contentsOf: visualNoteURL,
                encoding: .utf8
            )
            try write(
                existingVisualFixture + #"""

                ## Mixed-script measure fixture

                A readable scholarly line should hold an argument together without making the eye travel across the entire window. This paragraph repeats enough conceptual structure to expose the selected measure, its centering, and its relation to the surrounding editorial panes.

                中文段落用于检查混合文字在默认正文宽度下的换行。价值、理由、反对意见与回应应当保持清楚的节奏，同时窄窗口必须自然回流，不能产生整页横向阅读滚动。

                $$
                \int_0^1 x^2\,dx = \frac{1}{3}
                $$

                A final long paragraph makes the lower page rhythm visible after tables, code, mathematics, and callouts. It remains synthetic, contains no private research material, and exists only inside this test-owned Triptych copy.
                """# + "\n",
                to: visualNoteURL
            )
        }
        if name.contains("testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm") {
            let studyURL = analyses.appendingPathComponent("QA Document Heading Study.md")
            let revisedURL = analyses.appendingPathComponent(
                "QA Document Heading Study — Revised.md"
            )
            let study = documentHeadingStudySource()
            try write(study, to: studyURL)
            try write(
                study.replacingOccurrences(
                    of: "The comparison revision keeps every other line fixed.",
                    with: "The comparison revision changes only this synthetic sentence."
                ),
                to: revisedURL
            )
        }
        if name.contains("testReviewOwnsFootnoteNavigationAndEditKeepsItPassive") {
            let footnoteNoteURL = analyses.appendingPathComponent("QA Autosave A.md")
            let existingFootnoteFixture = try String(
                contentsOf: footnoteNoteURL,
                encoding: .utf8
            )
            try write(
                existingFootnoteFixture + "\nQA footnote marker[^qa-footnote].\n\n"
                    + "[^qa-footnote]: Synthetic Review-only footnote.\n",
                to: footnoteNoteURL
            )
        }
        if name.contains("testSearchQueriesExplicitDirectRelationsWithoutParallelResults") {
            try write(
                """
                ---
                title: "QA Direct Relation Concept 947"
                aliases: ["QA Direct Relation Alias 947"]
                status: seed
                ---
                # QA Direct Relation Concept 947

                Synthetic navigation fixture: +[[QA Autosave A|A distinct analysis relation]].
                """ + "\n",
                to: topics.appendingPathComponent("QA Direct Relation Topic.md")
            )
        }
        if name.contains("testSearchExplainsTitleAliasHeadingAndBodyRanking") {
            try write(
                "# Deliberative Autonomy\n\nA concise account.\n",
                to: analyses.appendingPathComponent("Ranking Title.md")
            )
            try write(
                "# Agency Structure\n\nA concise account.\n",
                to: topics.appendingPathComponent("QA Topic.md")
            )
            try seedManagedTopicAliases(
                relativePath: "QA Topic.md",
                aliases: ["Deliberative Autonomy"]
            )
            try write(
                "# Normative Architecture\n\n## Deliberative Autonomy\n\nA concise account.\n",
                to: analyses.appendingPathComponent("Ranking Heading.md")
            )
            try write(
                "# Practical Reason\n\nThis account develops deliberative autonomy in ordinary prose.\n",
                to: analyses.appendingPathComponent("Ranking Body.md")
            )
        }
        if name.contains("testLifecycleDestinationKeepsLongTitleOnOneRow") {
            try write(
                """
                ---
                title: "A deliberately long lifecycle title about attention, salience, and the normative structure of reasons"
                ---
                # Long Lifecycle Title

                Synthetic long-title fixture.
                """ + "\n",
                to: analyses.appendingPathComponent("QA Autosave B.md")
            )
        }
        try write(
            """
            ---
            critique_authorship: agent
            critique_target_path: QA Work.md
            critique_requested_at: "2026-07-14T00:00:00Z"
            critique_request_scope: "Both"
            ---
            # Critique: QA Work

            ## Specific Findings

            ### Traced — Topic connection
            - Target Work: QA Work.md
            - Target line: 105
            - Target quotation: "[[QA Topic]]"

            ## Evidence Limits

            Synthetic QA fixture only.
            """ + "\n",
            to: critiques.appendingPathComponent("QA Critique.md")
        )
    }

    func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }

    func ambiguousIdentitySource() -> String {
        "---\ntitle: QA Ambiguous Identity\n---\n# QA Ambiguous Identity\n\nExact shared bytes.\n"
    }

    func seedAmbiguousIdentityFixture() throws {
        let analyses = triptychDirectory.appendingPathComponent(
            "01-analyses",
            isDirectory: true
        )
        let source = ambiguousIdentitySource()
        try write(source, to: analyses.appendingPathComponent("QA Identity A.md"))
        try write(source, to: analyses.appendingPathComponent("QA Identity B.md"))
    }

    func documentHeadingStudySource() -> String {
        #"""
        ---
        title: "Heading Wrap Fixture"
        fixture: synthetic-nonprivate
        ---
        # 在长期论证中保持证据边界：Reasons, Values, and the Practical Option Space Across Competing Interpretations

        A sustained philosophical argument asks the reader to retain one distinction while testing several objections. The line should turn without breaking the conceptual thread.

        A second paragraph asks whether evidence supports a premise or merely motivates further inquiry. Its role should remain visible without decorative emphasis.

        A third paragraph separates an author's claim from the researcher's reconstruction. Spacing should keep that evidential boundary calm and legible.

        A fourth paragraph states an objection before considering any reply. The reader should not mistake visual proximity for argumentative support.

        A fifth paragraph introduces a qualification that narrows the conclusion. The transition should remain easy to recover after moving between lines.

        A sixth paragraph compares two practical options without assigning either one authority. Repeated terms should remain trackable through the page.

        A seventh paragraph distinguishes an apparent reason from its normative force. This fixture makes no philosophical claim about that distinction.

        An eighth paragraph returns to the main inference after a short detour. Paragraph boundaries should guide reading without fragmenting the argument.

        A ninth paragraph records a provisional consequence and leaves its source status explicit. Density should remain suitable for sustained inspection.

        A tenth paragraph closes the sequence without becoming a visual conclusion card. It belongs to the same ordinary body rhythm as every prior paragraph.

        The comparison revision keeps every other line fixed.

        ## Mixed writing systems

        中文长段落用于检验混合文字下的换行与两端对齐。论证、反对意见、回应、限定条件与结论应当保持清楚的层级；窗口变窄或文档文字放大时，普通正文必须自然回流，而不是产生整页横向阅读滚动。

        This mixed paragraph asks whether 理由、价值与可行选项 remain legible beside Latin punctuation, *emphasis*, a [local link](QA%20Autosave%20A.md), a footnote marker[^measure], and inline code such as `sourceUTF16Offset`.

        هذه فقرة عربية اصطناعية لا تنسب رأيا إلى مصدر حقيقي، وهي تختبر اتجاه الفقرة وعلامات الترقيم مع `inline code` والأرقام 12345. זהו טקסט עברי סינתטי לבדיקת כיווניות וסימני פיסוק.

        The unbroken token scholium_document_rhythm_fixture_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 and the URL https://example.invalid/a/very/long/synthetic/path/that/contains/no/research/data test local break and overflow behavior.

        ### Heading Level Three

        #### Heading Level Four

        ##### Heading Level Five

        ###### Heading Level Six

        > [!orient] Reading Route
        > Begin with the ordinary prose, then inspect exact objects without treating this note as a source.

        > [!connect]
        > A neutral connection list can remain untitled and still belong to the same document grammar.

        > [!state] Provisional Claim
        > A displayed distinction should remain visibly subordinate to the surrounding research document.
        >
        > A second paragraph checks internal callout rhythm.

        > [!illustrate] Synthetic Case
        > Imagine two options that differ only in the information available to the researcher.

        > [!flag] Limitation
        > No sentence in this fixture is evidence for a philosophical conclusion.

        > [!quote] Synthetic Wording
        > This is invented wording, not a quotation from any author.

        > [!cite] Fixture Source Boundary
        > Synthetic UI material; no bibliography item is being attributed.

        > [!neutral]- Folded Synthetic Note
        > This neutral fallback tests the source-controlled collapsed state.

        | Claim | Status | Count |
        |:---|:---:|---:|
        | Ordinary prose reflows | Open | 12 |
        | Exact objects stay local | Required | 3 |
        | 超宽表格单元格包含中英混排与一段很长的综合说明 | Synthetic | 987654 |

        Table note: counts are arbitrary fixture values and carry no evidential meaning.

        A named footnote appears here[^measure], and the same reference appears again[^measure]. An inline note follows.^[This inline note is also synthetic.]

        [^measure]: The named footnote tests a long continuation, source return, and hanging rhythm without citing a real work.
          Its continuation includes **emphasis**, mixed text 与中文, and a second sentence.

        ## References

        Synthetic, A. (2026). *A deliberately long un-attributed title used only to test bibliography indentation and continuation rhythm*. Fixture Press.

        Example, B., & Sample, C. (2025). A second invented entry with mixed-script metadata: 排版比较条目. *Nonexistent Journal, 12*(3), 100–128.

        Inline mathematics $r = f(o, c)$ remains part of the sentence.

        $$
        \int_0^1 x^2\,dx = \frac{1}{3}
        $$

        ```swift
        let exactSource = "Synthetic fixture only"
        let retainedIdentity = true
        ```

        > Ordinary quotation syntax remains distinct from semantic Callouts and should preserve selectable prose.

        1. First ordered item with a continuation that wraps across the selected measure.
        2. Second ordered item with **emphasis**, `code`, and mixed text 理由.

        - Unordered evidence placeholder
          - Nested qualification placeholder

        Final ordinary prose returns after every exact object. It should still look like the same document, retain the same source authority, and leave tables, code, mathematics, and the synthetic diff pair inside their own bounded responsibilities.
        """# + "\n"
    }

    @MainActor
    func searchResult(named title: String, in container: XCUIElement? = nil) -> XCUIElement {
        let buttons = if let container {
            container.buttons
        } else {
            app.buttons
        }
        return buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
            "scholium.searchResult.",
            "\(title),"
        )).firstMatch
    }

    /// Preserves the fixture's valid Triptych identity, Note identities, and
    /// editable Working Methods while removing only mutable Research Records
    /// owned by these action journeys. Deleting the manifest while retaining
    /// identity-bound control files would manufacture an unsupported partial
    /// Triptych and correctly route the app back to recovery Bootstrap.
    private func resetResearchActionFixtureState() throws {
        let scholiumDirectory = triptychDirectory.appendingPathComponent(
            ".scholium",
            isDirectory: true
        )
        let mutableComponents = ["research-records"]

        for component in mutableComponents {
            let stateURL = scholiumDirectory.appendingPathComponent(component)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                try FileManager.default.removeItem(at: stateURL)
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: stateURL.path),
                "Research Action fixture retained mutable state: \(component)"
            )
        }
    }

    private func seedManagedTopicAliases(
        relativePath: String,
        aliases: [String]
    ) throws {
        let controlDirectory = triptychDirectory.appendingPathComponent(
            ".scholium",
            isDirectory: true
        )
        let identityDocument = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: controlDirectory.appendingPathComponent(
                    "identities.json"
                ))
            ) as? [String: Any]
        )
        let matchingRecords = (identityDocument["records"] as? [[String: Any]] ?? [])
            .filter { $0["relativePath"] as? String == relativePath }
        let noteID = try XCTUnwrap(
            matchingRecords.count == 1 ? matchingRecords.first?["id"] as? String : nil,
            "The managed Topic alias fixture requires one exact stable Note identity."
        )
        let encodedAliases = aliases.map { alias in
            ["string": ["_0": alias]]
        }
        let record: [String: Any] = [
            "schemaVersion": 1,
            "noteID": noteID,
            "fields": [
                "aliases": [
                    "array": ["_0": encodedAliases],
                ],
            ],
        ]
        let destinationDirectory = controlDirectory.appendingPathComponent(
            "note-metadata/v1",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let destination = destinationDirectory.appendingPathComponent(
            "\(noteID.lowercased()).json"
        )
        try JSONSerialization.data(
            withJSONObject: record,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )
    }

    /// Test-owned source extensions must update the matching identity record
    /// before launch so the app sees an ordinary current Note, not an external
    /// replacement whose old stable ID cannot own the seeded Review Record.
    private func updateStoredNoteFingerprint(
        relativePath: String,
        source: String
    ) throws {
        let identityURL = triptychDirectory.appendingPathComponent(
            ".scholium/identities.json"
        )
        var document = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: identityURL)
            ) as? [String: Any]
        )
        var records = document["records"] as? [[String: Any]] ?? []
        let matches = records.indices.filter {
            records[$0]["relativePath"] as? String == relativePath
        }
        let index = try XCTUnwrap(
            matches.count == 1 ? matches.first : nil,
            "The extended reading fixture requires one exact Note identity."
        )
        records[index]["fingerprint"] = qaFingerprint(source)
        records[index]["updatedAt"] = "2026-08-30T08:00:00Z"
        document["records"] = records
        try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ).write(to: identityURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: identityURL.path
        )
    }

    private func seedAnalysisZoteroBinding(
        relativePath: String,
        itemKey: String
    ) throws {
        let controlDirectory = triptychDirectory.appendingPathComponent(
            ".scholium",
            isDirectory: true
        )
        let identityDocument = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: controlDirectory.appendingPathComponent("identities.json"))
            ) as? [String: Any]
        )
        let matchingRecords = (identityDocument["records"] as? [[String: Any]] ?? [])
            .filter { $0["relativePath"] as? String == relativePath }
        let identity = try XCTUnwrap(
            matchingRecords.count == 1 ? matchingRecords.first : nil,
            "The Zotero UI fixture requires one exact stable Analysis identity."
        )
        let noteID = try XCTUnwrap(identity["id"] as? String)
        let bindings: [String: Any] = [
            "schemaVersion": 1,
            "bindings": [[
                "note_id": noteID,
                "library": ["kind": "user"],
                "item_key": itemKey,
            ]],
        ]
        let destination = controlDirectory.appendingPathComponent(
            "analysis-zotero-bindings.json"
        )
        try JSONSerialization.data(
            withJSONObject: bindings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: destination.path
        )
    }
}
