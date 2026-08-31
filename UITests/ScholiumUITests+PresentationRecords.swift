@preconcurrency import XCTest
import AppKit
import CryptoKit
import notify

extension ScholiumUITests {
    @MainActor
    func testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession() throws {
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.librarySurface"
        ].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave A.md"
        ].waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        let sessionsURL = homeDirectory
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Window Sessions", isDirectory: true)
        let sessions = try FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension == "json" }
        XCTAssertEqual(
            sessions.count,
            1,
            "A fixture launch without an explicit Session ID must reuse one per-process fallback."
        )
        XCTAssertNotNil(UUID(uuidString: sessions[0].deletingPathExtension().lastPathComponent))
    }

    @MainActor
    func testWindowFeedbackPlacesTransientToastBelowAndPersistentWarningAbove() {
        let document = app.webViews.firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        let documentFrameBeforeFeedback = document.frame
        let window = app.windows.firstMatch

        let qaMenu = app.menuBars.menuBarItems["QA"]
        XCTAssertTrue(qaMenu.waitForExistence(timeout: 5))
        qaMenu.click()
        let present = app.menuItems["Present Window Feedback Proof"]
        XCTAssertTrue(present.waitForExistence(timeout: 3))
        present.click()

        let confirmation = app.descendants(matching: .any)[
            "scholium.windowFeedback.confirmation"
        ]
        let warning = app.descendants(matching: .any)[
            "scholium.windowFeedback.warning"
        ]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertEqual(confirmation.label, "Confirmation")
        XCTAssertEqual(warning.label, "Warning")
        XCTAssertTrue(
            accessibilityText(of: confirmation.staticTexts.firstMatch)
                .contains("QA transient confirmation")
        )
        XCTAssertTrue(
            accessibilityText(of: warning.staticTexts.firstMatch)
                .contains("QA persistent warning")
        )

        XCTAssertEqual(document.frame, documentFrameBeforeFeedback)
        XCTAssertTrue(window.frame.contains(warning.frame))
        XCTAssertTrue(
            document.frame.intersects(confirmation.frame),
            "Transient feedback must overlay Document instead of taking layout space."
        )
        XCTAssertEqual(warning.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertEqual(confirmation.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertEqual(
            warning.frame.minY - window.frame.minY,
            16,
            accuracy: 4
        )
        XCTAssertEqual(
            window.frame.maxY - confirmation.frame.maxY,
            16,
            accuracy: 4
        )
        XCTAssertGreaterThan(
            confirmation.frame.midY,
            document.frame.midY,
            "The transient toast must remain in the lower half of the window."
        )
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Window feedback split presentation"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(
            waitUntil(timeout: 8) { !confirmation.exists },
            "A redundant confirmation must leave after the bounded dwell."
        )
        XCTAssertEqual(document.frame, documentFrameBeforeFeedback)
        XCTAssertTrue(warning.exists, "Warnings must remain until explicit dismissal.")
        let dismiss = warning.buttons["Dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<32 where !keyboardFocus.evaluate(with: dismiss) {
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(
            keyboardFocus.evaluate(with: dismiss),
            "Tab must give Dismiss observable native keyboard focus."
        )
        let focusedScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        focusedScreenshot.name = "Persistent feedback keyboard focus"
        focusedScreenshot.lifetime = .keepAlways
        add(focusedScreenshot)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !warning.exists })
        XCTAssertTrue(document.exists)
    }

    @MainActor
    func testActionNotificationProofPresentationKeepsTheStackExact() throws {
        let window = app.windows.firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: window)
        let document = app.webViews.firstMatch
        XCTAssertTrue(document.waitForExistence(timeout: 8))
        let documentFrameBeforeAction = document.frame
        let stack = app.descendants(matching: .any)[
            "scholium.researchActivityNotificationStack"
        ]
        XCTAssertTrue(
            stack.waitForExistence(timeout: 20),
            "The seeded Settlement reminder did not reach the shared stack."
        )
        XCTAssertTrue(accessibilityText(of: stack).contains("3 Notifications"))
        stack.click()
        XCTAssertTrue(
            window.buttons["Review Changes"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            window.descendants(matching: .any)[
                "scholium.researchActivityNotificationRows"
            ].buttons["Settle"].exists
        )
        stack.click()

        let qaMenu = app.menuBars.menuBarItems["QA"]
        XCTAssertTrue(qaMenu.waitForExistence(timeout: 5))
        qaMenu.click()
        let present = app.menuItems["Present Action Notification Proof"]
        XCTAssertTrue(present.waitForExistence(timeout: 3))
        present.click()

        XCTAssertTrue(stack.waitForExistence(timeout: 8))
        XCTAssertTrue(accessibilityText(of: stack).contains("3 Notifications"))
        stack.click()
        let dismiss = window.buttons["Dismiss"].firstMatch
        XCTAssertTrue(
            dismiss.waitForExistence(timeout: 5),
            "The shared stack must expose the Action row when expanded."
        )
        let expandedRows = window.descendants(matching: .any)[
            "scholium.researchActivityNotificationRows"
        ]
        XCTAssertTrue(expandedRows.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["Review Changes"].exists)
        XCTAssertFalse(app.popovers.firstMatch.exists)
        XCTAssertEqual(document.frame, documentFrameBeforeAction)
        XCTAssertTrue(document.frame.intersects(expandedRows.frame))
        XCTAssertEqual(stack.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertEqual(
            stack.frame.minY - window.frame.minY,
            16,
            accuracy: 4
        )
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Shared Settlement and Action notification stack"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(dismiss.isHittable)
        dismiss.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                stack.exists && window.buttons["Review Changes"].exists
            },
            "Dismissing the Action must retain the persistent Settlement reminder."
        )
        XCTAssertTrue(accessibilityText(of: stack).contains("2 Notifications"))
        XCTAssertFalse(app.popovers.firstMatch.exists)
    }

    @MainActor
    func testNotificationsEmptyStateKeepsIndicatorWithCopy() {
        let notifications = app.buttons["scholium.triptychNotifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 8))
        notifications.click()

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        let search = popover.descendants(matching: .any)[
            "scholium.attentionSearch"
        ]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("no-notification-can-match-this-query")

        let empty = popover.descendants(matching: .any)[
            "scholium.attentionEmpty"
        ]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        let copy = empty.staticTexts.firstMatch
        XCTAssertTrue(copy.exists)
        let accessibleCopy = accessibilityText(of: copy)
        XCTAssertTrue(accessibleCopy.contains("No Matching Notifications"))
        XCTAssertTrue(
            accessibleCopy.contains(
                "No Action activity or visible derived issue needs attention in this Scope."
            )
        )

        let screenshot = XCTAttachment(screenshot: popover.screenshot())
        screenshot.name = "Grouped Notifications empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsFeedbackOverlaysTheWindowWithoutReflow() {
        let settingsItem = app.menuItems["Settings…"]
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 3))
        settingsItem.click()
        let settings = settingsWindow()
        XCTAssertTrue(settings.waitForExistence(timeout: 8))

        let confirmation = settings.descendants(matching: .any)[
            "scholium.settings.feedback.confirmation"
        ]
        let error = settings.descendants(matching: .any)[
            "scholium.settings.feedback.error"
        ]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertFalse(error.exists)
        XCTAssertEqual(confirmation.label, "Confirmation")
        XCTAssertTrue(
            accessibilityText(of: confirmation.staticTexts.firstMatch)
                .contains("QA settings confirmation")
        )

        let root = settings.descendants(matching: .any)["scholium.settings.root"]
        let sidebar = settings.descendants(matching: .any)["scholium.settings.sidebar"]
        XCTAssertTrue(root.exists)
        XCTAssertTrue(sidebar.exists)
        let sidebarFrame = sidebar.frame

        XCTAssertTrue(
            waitUntil(timeout: 8) { !confirmation.exists },
            "A Settings confirmation must leave after the bounded dwell."
        )
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Error")
        XCTAssertTrue(
            accessibilityText(of: error.staticTexts.firstMatch)
                .contains("QA settings error")
        )
        XCTAssertTrue(error.exists, "Settings errors must remain until explicit dismissal.")
        XCTAssertTrue(root.frame.contains(error.frame))
        XCTAssertEqual(error.frame.midX, settings.frame.midX, accuracy: 2)
        let settingsFeedbackTopGap = error.frame.minY - settings.frame.minY
        XCTAssertGreaterThanOrEqual(
            settingsFeedbackTopGap,
            12,
            "Settings feedback must begin inside the transparent toolbar band."
        )
        XCTAssertLessThanOrEqual(
            settingsFeedbackTopGap,
            24,
            "Settings feedback must retain only the compact top-edge inset."
        )
        XCTAssertEqual(
            sidebar.frame,
            sidebarFrame,
            "Settings feedback must not move the underlying Settings content."
        )
        let screenshot = XCTAttachment(screenshot: settings.screenshot())
        screenshot.name = "Window-level Settings feedback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let dismiss = error.buttons["Dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        XCTAssertTrue(
            dismiss.isHittable,
            "The transparent toolbar must not intercept the Settings notice action."
        )
        dismiss.click()
        XCTAssertTrue(waitUntil(timeout: 3) { !error.exists })
    }

    @MainActor
    func testWorkspaceInitialDefaultPreservesNativeReachability() throws {
        waitForCurrentDocumentSurface()
        let window = app.windows.firstMatch
        guard abs(window.frame.width - QAWorkspaceMetricContract.preferredWidth)
            <= QAWorkspaceMetricContract.frameTolerance else {
            throw XCTSkip(
                "AppKit restored a test-owned frame; rerun this first-presentation journey from a clean QA preference domain."
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"].exists
        )
        XCTAssertTrue(
            app.toolbars.firstMatch.buttons["Hide Sidebar"]
                .waitForExistence(timeout: 5)
        )
        let inspectorButton = app.toolbars.firstMatch.buttons[
            "Show Research Inspector"
        ]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.isEnabled)
    }

    @MainActor
    func testNativeSidebarToggleAndLibraryTriptychIdentityRemainAvailable() throws {
        waitForCurrentDocumentSurface()
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let triptychManagement = app.menuButtons[
            "scholium.triptychManagement"
        ].firstMatch
        XCTAssertTrue(triptychManagement.waitForExistence(timeout: 5))
        let hideSidebar = app.buttons["Hide Sidebar"]
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(librarySurface.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(triptychManagement.frame.minX, librarySurface.frame.minX)
        XCTAssertLessThan(triptychManagement.frame.maxX, librarySurface.frame.maxX)
        let folderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ]
        let noteRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            noteRow.frame.minX,
            folderRow.frame.minX + 30,
            "Top-level note rows must remain aligned with the Library outline."
        )
        XCTAssertFalse(app.buttons["Collapse Note"].exists)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Collapse Note"].exists)
        app.typeKey(.escape, modifierFlags: [])

        hideSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !self.app.descendants(matching: .any)["scholium.librarySurface"].exists
        })
        let showSidebar = app.buttons["Show Sidebar"]
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        showSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 1)

        let shellScreenshot = XCTAttachment(screenshot: window.screenshot())
        shellScreenshot.name = "Full-height editorial Library with native sidebar controls"
        shellScreenshot.lifetime = .keepAlways
        add(shellScreenshot)
    }

    @MainActor
    func testLibraryRemainsReadableAtItsNativeMinimum() throws {
        waitForCurrentDocumentSurface()

        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            library.frame.width,
            QAWorkspaceMetricContract.libraryMinimumReadableWidth - 1,
            "An expanded Library must not remain below its content-tested readable width."
        )

        for scope in ["Analyses", "Topics", "Works"] {
            let control = app.buttons[scope]
            XCTAssertTrue(control.waitForExistence(timeout: 3))
            XCTAssertLessThanOrEqual(
                control.frame.height,
                32,
                "The \(scope) scope must remain a single-line control at the Library minimum."
            )
        }

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Library at the 300pt native readable minimum"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// A retained visual checkpoint for stable native-toolbar Sidebar and
    /// Inspector visibility controls. This is intentionally a narrow proof
    /// rather than a claim that the complete UI acceptance matrix has passed.
    @MainActor
    func testNativeToolbarVisualProofAtDefaultWindowSize() throws {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: 1_180,
            appearance: .light
        )
        app.launch()
        let loadingWindow = app.windows.firstMatch
        XCTAssertTrue(loadingWindow.waitForExistence(timeout: 15))
        let loadingClose = loadingWindow.buttons[XCUIIdentifierCloseWindow]
        let loadingToolbar = app.toolbars.firstMatch
        XCTAssertTrue(loadingClose.waitForExistence(timeout: 5))
        XCTAssertTrue(loadingToolbar.waitForExistence(timeout: 5))
        let loadingCloseMidY = loadingClose.frame.midY
        let loadingToolbarHeight = loadingToolbar.frame.height

        waitForCurrentDocumentSurface()

        let window = app.windows.firstMatch
        let loadedToolbar = app.toolbars.firstMatch
        let close = window.buttons[XCUIIdentifierCloseWindow]
        XCTAssertTrue(close.exists)
        XCTAssertTrue(loadedToolbar.exists)
        XCTAssertEqual(close.frame.midY, loadingCloseMidY, accuracy: 1)
        XCTAssertEqual(loadedToolbar.frame.height, loadingToolbarHeight, accuracy: 1)
        guard abs(window.frame.width - QAWorkspaceMetricContract.preferredWidth)
            <= QAWorkspaceMetricContract.frameTolerance else {
            throw XCTSkip(
                "AppKit restored a test-owned frame; rerun this visual checkpoint from a clean QA preference domain."
            )
        }

        let sidebarToggle = loadedToolbar.buttons["Hide Sidebar"].firstMatch
        let back = loadedToolbar.buttons["Back"].firstMatch
        let forward = loadedToolbar.buttons["Forward"].firstMatch
        let mode = documentModeControl()
        let search = loadedToolbar.buttons["Search"].firstMatch
        let history = researchRecordsControl()
        let inspectorToggle = loadedToolbar.buttons["Show Research Inspector"].firstMatch
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 5))
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(forward.waitForExistence(timeout: 5))
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))

        XCTAssertLessThan(sidebarToggle.frame.midX, back.frame.midX)
        XCTAssertLessThan(back.frame.midX, forward.frame.midX)
        XCTAssertGreaterThan(mode.frame.midX, search.frame.midX)
        XCTAssertGreaterThan(history.frame.midX, mode.frame.midX)
        // The HStack owns an 8pt layout gap. XCUI reports each native toolbar
        // button's accessibility frame one point beyond its layout frame on
        // both adjacent edges, so the observable frame gap is 6pt.
        XCTAssertGreaterThanOrEqual(mode.frame.minX - search.frame.maxX, 0)
        XCTAssertLessThanOrEqual(mode.frame.minX - search.frame.maxX, 8)
        XCTAssertGreaterThanOrEqual(history.frame.minX - mode.frame.maxX, 0)
        XCTAssertLessThanOrEqual(history.frame.minX - mode.frame.maxX, 8)
        XCTAssertGreaterThan(inspectorToggle.frame.midX, window.frame.midX)

        let library = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarToggle.label, "Hide Sidebar")
        XCTAssertTrue(sidebarToggle.isHittable)
        XCTAssertEqual(sidebarToggle.frame.midY, close.frame.midY, accuracy: 12)
        let stableSidebarMidX = sidebarToggle.frame.midX
        let stableInspectorMidX = inspectorToggle.frame.midX

        sidebarToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !library.exists })
        let sidebarReveal = loadedToolbar.buttons["Show Sidebar"].firstMatch
        XCTAssertTrue(sidebarReveal.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarReveal.label, "Show Sidebar")
        XCTAssertEqual(sidebarReveal.frame.midY, close.frame.midY, accuracy: 12)
        XCTAssertEqual(sidebarReveal.frame.midX, stableSidebarMidX, accuracy: 2)
        XCTAssertEqual(inspectorToggle.frame.midX, stableInspectorMidX, accuracy: 2)
        XCTAssertEqual(
            loadedToolbar.buttons.matching(
                NSPredicate(format: "label IN %@", ["Show Sidebar", "Hide Sidebar"])
            ).count,
            1
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.toolbar.attention"].exists,
            "Collapsing Sidebar must not transfer Attention into the Document toolbar."
        )
        XCTAssertLessThan(sidebarReveal.frame.midX, back.frame.midX)
        XCTAssertLessThan(back.frame.midX, forward.frame.midX)
        XCTAssertLessThan(forward.frame.midX, search.frame.midX)
        XCTAssertLessThan(search.frame.midX, mode.frame.midX)
        XCTAssertLessThan(mode.frame.midX, history.frame.midX)
        XCTAssertLessThan(history.frame.midX, inspectorToggle.frame.midX)
        let collapsedToolbarScreenshot = XCTAttachment(screenshot: window.screenshot())
        collapsedToolbarScreenshot.name = "Native toolbar — both peripheral panes collapsed"
        collapsedToolbarScreenshot.lifetime = .keepAlways
        add(collapsedToolbarScreenshot)
        sidebarReveal.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let sidebarHide = loadedToolbar.buttons["Hide Sidebar"].firstMatch
        XCTAssertTrue(sidebarHide.waitForExistence(timeout: 5))
        XCTAssertEqual(sidebarHide.label, "Hide Sidebar")
        XCTAssertTrue(sidebarHide.isHittable)
        XCTAssertEqual(sidebarHide.frame.midY, close.frame.midY, accuracy: 12)

        let triptych = app.descendants(matching: .any)["scholium.triptychManagement"]
        XCTAssertTrue(triptych.waitForExistence(timeout: 5))

        let documentIdentity = documentTitleElement(in: window)
        XCTAssertTrue(documentIdentity.waitForExistence(timeout: 5))
        XCTAssertLessThan(forward.frame.maxX, documentIdentity.frame.minX)
        XCTAssertLessThan(documentIdentity.frame.maxX, search.frame.minX)
        XCTAssertEqual(mode.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertEqual(search.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertEqual(history.frame.midY, documentIdentity.frame.midY, accuracy: 8)
        XCTAssertLessThan(
            history.frame.maxX,
            inspectorToggle.frame.minX,
            "Research Record must remain immediately left of the Inspector control."
        )

        let inspector = app.scrollViews["scholium.researchInspector"]
        inspectorToggle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        let inspectorHide = loadedToolbar.buttons["Hide Research Inspector"].firstMatch
        XCTAssertTrue(inspectorHide.waitForExistence(timeout: 5))
        XCTAssertEqual(inspectorHide.label, "Hide Research Inspector")
        XCTAssertTrue(inspectorHide.isHittable)
        XCTAssertEqual(inspectorHide.frame.midY, close.frame.midY, accuracy: 12)
        XCTAssertEqual(inspectorHide.frame.midX, stableInspectorMidX, accuracy: 2)
        XCTAssertEqual(
            loadedToolbar.buttons.matching(
                NSPredicate(
                    format: "label IN %@",
                    ["Show Research Inspector", "Hide Research Inspector"]
                )
            ).count,
            1
        )
        inspectorHide.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
        let inspectorReveal = loadedToolbar.buttons["Show Research Inspector"].firstMatch
        XCTAssertTrue(inspectorReveal.waitForExistence(timeout: 5))
        XCTAssertEqual(inspectorReveal.frame.midY, close.frame.midY, accuracy: 12)
        XCTAssertEqual(inspectorReveal.frame.midX, stableInspectorMidX, accuracy: 2)
        inspectorReveal.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            history.frame.maxX,
            inspector.frame.minX,
            "Document commands must end before the Apparatus begins."
        )

        search.hover()
        let toolbarHoverScreenshot = XCTAttachment(screenshot: window.screenshot())
        toolbarHoverScreenshot.name = "Native toolbar — system hover reference"
        toolbarHoverScreenshot.lifetime = .keepAlways
        add(toolbarHoverScreenshot)

        let connectMode = app.descendants(matching: .any)[
            "scholium.inspectorMode.connect"
        ]
        XCTAssertTrue(connectMode.waitForExistence(timeout: 5))
        connectMode.hover()
        let modeHoverScreenshot = XCTAttachment(screenshot: window.screenshot())
        modeHoverScreenshot.name = "Inspector ModeIndex — selected and hover surfaces"
        modeHoverScreenshot.lifetime = .keepAlways
        add(modeHoverScreenshot)

        let libraryFilters = app.descendants(matching: .any)[
            "scholium.libraryFilters"
        ]
        XCTAssertTrue(libraryFilters.waitForExistence(timeout: 5))
        libraryFilters.hover()
        let libraryHoverScreenshot = XCTAttachment(screenshot: window.screenshot())
        libraryHoverScreenshot.name = "Library header — semantic icon hover"
        libraryHoverScreenshot.lifetime = .keepAlways
        add(libraryHoverScreenshot)

        let libraryDisclosure = app.descendants(matching: .any)[
            "scholium.libraryDisclosureToggle"
        ]
        XCTAssertTrue(libraryDisclosure.waitForExistence(timeout: 5))
        libraryDisclosure.hover()
        let disclosureHoverScreenshot = XCTAttachment(screenshot: window.screenshot())
        disclosureHoverScreenshot.name = "Library header — disclosure hover"
        disclosureHoverScreenshot.lifetime = .keepAlways
        add(disclosureHoverScreenshot)

        let libraryCreate = app.descendants(matching: .any)[
            "scholium.libraryCreate"
        ]
        XCTAssertTrue(libraryCreate.waitForExistence(timeout: 5))
        libraryCreate.hover()
        let createHoverScreenshot = XCTAttachment(screenshot: window.screenshot())
        createHoverScreenshot.name = "Library header — create hover"
        createHoverScreenshot.lifetime = .keepAlways
        add(createHoverScreenshot)

        // Move the pointer off the toolbar control so its transient help tag
        // cannot obscure the retained visual proof.
        let proofFocus = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
        )
        proofFocus.hover()
        proofFocus.click()

        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Native-toolbar peripheral controls — default 1180pt workspace"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let initialDocumentTitle = try XCTUnwrap(documentTitle())
        let untabbedHeaderTop = documentIdentity.frame.minY - window.frame.minY
        let secondRow = app.descendants(matching: .any)[
            "scholium.noteRow.QA Autosave B.md"
        ]
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10))
        secondRow.rightClick()
        let noteContextMenu = app.menus["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(noteContextMenu.waitForExistence(timeout: 3))
        let openInNewTab = noteContextMenu.menuItems["Open in New Tab"]
        XCTAssertTrue(openInNewTab.waitForExistence(timeout: 3))
        openInNewTab.click()
        let documentTabs = app.descendants(matching: .any)["scholium.documentTabs"]
        XCTAssertTrue(documentTabs.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 5))
        XCTAssertTrue(back.isEnabled)
        back.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitForDocumentTitle(initialDocumentTitle, timeout: 5))
        XCTAssertTrue(forward.isEnabled)
        forward.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", timeout: 5))

        // Document tabs retain independent documents while borrowing the one
        // window-owned Library and Apparatus presentation.
        let tabbedInspector = app.scrollViews["scholium.researchInspector"]
        XCTAssertTrue(tabbedInspector.waitForExistence(timeout: 5))
        let tabbedLibrary = app.descendants(matching: .any)[
            "scholium.librarySurface"
        ].firstMatch
        XCTAssertTrue(tabbedLibrary.waitForExistence(timeout: 5))

        let tabbedIdentity = documentTitleElement(in: app.windows.firstMatch)
        XCTAssertTrue(tabbedIdentity.waitForExistence(timeout: 5))
        let tabbedWindow = app.windows.firstMatch
        let tabbedHeaderTop = tabbedIdentity.frame.minY - tabbedWindow.frame.minY
        XCTAssertEqual(
            tabbedHeaderTop,
            untabbedHeaderTop,
            accuracy: 2,
            "Opening document tabs must not push the document title and commands below the top toolbar."
        )
        XCTAssertGreaterThanOrEqual(
            documentTabs.frame.minX,
            tabbedLibrary.frame.maxX - 3,
            "The visible native-tab presentation must begin at the Library/Document divider."
        )
        XCTAssertLessThanOrEqual(
            documentTabs.frame.maxX,
            tabbedInspector.frame.minX + 3,
            "The visible native-tab presentation must end at the Document/Apparatus divider."
        )
        XCTAssertFalse(
            app.tabGroups.firstMatch.exists,
            "The full-window AppKit tab bar must stay hidden when the Document split accessory is visible."
        )

        let tabbedScreenshot = XCTAttachment(screenshot: tabbedWindow.screenshot())
        tabbedScreenshot.name = "Document-scoped native window tabs below persistent toolbar"
        tabbedScreenshot.lifetime = .keepAlways
        add(tabbedScreenshot)
    }

    @MainActor
    func testNoDocumentKeepsTriptychRecordsAvailableAndInspectorDisabled() throws {
        app.terminate()
        if let enumerator = FileManager.default.enumerator(
            at: triptychDirectory,
            includingPropertiesForKeys: nil
        ) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                try FileManager.default.removeItem(at: url)
            }
        }
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: 1_180,
            openNote: nil
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        let history = researchRecordsControl()
        let inspector = inspectorVisibilityControl()
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        XCTAssertFalse(
            documentModeControl().exists,
            "An empty Triptych must not expose a stale document identity."
        )
        let emptyState = app.descendants(matching: .any)["scholium.noDocumentState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        XCTAssertTrue(
            history.isEnabled,
            "Triptych Records remains available without a selected Document."
        )
        XCTAssertFalse(inspector.isEnabled)
        XCTAssertLessThan(history.frame.maxX, inspector.frame.minX)

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Restrained no-document empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testInspectorToolbarItemOpensAndClosesInspector() throws {
        // Keep the trailing toolbar item inside the active display. The
        // default 1380-point acceptance window can extend beyond smaller test
        // displays even though the application window itself is valid.
        for appearance in QAAppearance.allCases {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID,
                initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth),
                appearance: appearance
            )
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
            waitForCurrentDocumentSurface()

            let inspectorToggle = inspectorVisibilityControl()
            XCTAssertTrue(inspectorToggle.waitForExistence(timeout: 5))
            XCTAssertTrue(inspectorToggle.isEnabled)

            let inspector = app.scrollViews["scholium.researchInspector"].firstMatch
            if inspector.exists {
                clickInspectorVisibilityControl()
                XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })
            }

            clickInspectorVisibilityControl()
            XCTAssertTrue(inspector.waitForExistence(timeout: 5))

            let expandedWindow = app.windows.firstMatch
            expandedWindow.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
            ).hover()
            let expandedScreenshot = XCTAttachment(screenshot: expandedWindow.screenshot())
            expandedScreenshot.name = "\(appearance.displayName) — continuous Inspector titlebar"
            expandedScreenshot.lifetime = .keepAlways
            add(expandedScreenshot)

            clickInspectorVisibilityControl()
            XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })

            let sidebarToggle = sidebarVisibilityControl()
            let documentIdentity = documentTitleElement(in: app.windows.firstMatch)
            let documentCommands = app.toolbars.firstMatch.buttons["Search"]
            XCTAssertTrue(
                sidebarToggle.isHittable,
                "Hiding Inspector must preserve the fixed leading toolbar zone."
            )
            XCTAssertTrue(
                documentIdentity.isHittable,
                "Hiding Inspector must preserve the Document identity toolbar zone."
            )
            XCTAssertTrue(
                documentCommands.isHittable,
                "Hiding Inspector must preserve the Document command toolbar zone."
            )
            XCTAssertTrue(
                app.descendants(matching: .any)["scholium.noteList"].isHittable,
                "Hiding Inspector must not collapse the independent Library plane."
            )
            XCTAssertLessThan(
                sidebarToggle.frame.maxX,
                documentIdentity.frame.minX,
                "The leading controls must remain before the Document identity."
            )
            XCTAssertLessThan(
                documentIdentity.frame.maxX,
                documentCommands.frame.minX,
                "The Document identity must remain before the command group."
            )
            XCTAssertLessThan(
                documentCommands.frame.maxX,
                inspectorToggle.frame.minX,
                "The command group must remain before the trailing Inspector control."
            )

            let window = app.windows.firstMatch
            window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)
            ).hover()
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = "\(appearance.displayName) — borderless Show Inspector"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testDocumentModeButtonShowsAndSwitchesCurrentState() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.label, "Document Mode")
        XCTAssertEqual(mode.value as? String, "Edit")

        let initialWidth = mode.frame.width
        let initialEditScreenshot = XCTAttachment(
            screenshot: app.windows.firstMatch.screenshot()
        )
        initialEditScreenshot.name = "Document mode — initial Edit state button"
        initialEditScreenshot.lifetime = .keepAlways
        add(initialEditScreenshot)

        selectDocumentMode("Review")
        XCTAssertTrue(waitUntil(timeout: 10) { mode.value as? String == "Review" })
        waitForCurrentDocumentSurface()
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)
        let reviewScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        reviewScreenshot.name = "Document mode — Review state button"
        reviewScreenshot.lifetime = .keepAlways
        add(reviewScreenshot)

        selectDocumentMode("Edit")
        XCTAssertTrue(waitUntil(timeout: 10) { mode.value as? String == "Edit" })
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)

        selectDocumentMode("Source")
        XCTAssertEqual(mode.value as? String, "Source")
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Document mode — Source state remains menu-only"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        selectDocumentMode("Review")
        XCTAssertTrue(waitUntil(timeout: 10) { mode.value as? String == "Review" })
        waitForCurrentDocumentSurface()
    }

    @MainActor
    func testPeripheralToolbarVisibilityControlsToggleWithPointerCoordinates() throws {
        exercisePeripheralVisibilityControls()
    }

    @MainActor
    func testAppearanceLineWidthVisualMatrixAndKeyboardControl() throws {
        func prepareVisualFixture(width: Int) {
            let mode = documentModeControl()
            XCTAssertTrue(mode.waitForExistence(timeout: 10))
            selectDocumentMode("Review")
            waitForCurrentDocumentSurface()
            XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
            XCTAssertEqual(
                app.windows.firstMatch.frame.width,
                CGFloat(width),
                accuracy: QAWorkspaceMetricContract.frameTolerance,
                "The requested first-presentation width must be visible in its retained screenshot."
            )
        }

        func resizeVisualFixture(width: Int) {
            let window = app.windows.firstMatch
            var currentFrame = window.frame
            guard let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame else {
                XCTFail("The visual matrix requires an attached macOS display.")
                return
            }
            let requiredShift = max(
                0,
                currentFrame.minX + CGFloat(width) - (screenFrame.maxX - 16)
            )
            if requiredShift > 0 {
                let titlebar = window.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.42, dy: 0.025)
                )
                titlebar.click(
                    forDuration: 0.15,
                    thenDragTo: titlebar.withOffset(
                        CGVector(dx: -requiredShift - 12, dy: 0)
                    )
                )
                XCTAssertTrue(waitUntil(timeout: 5) {
                    self.app.windows.firstMatch.frame.minX
                        < currentFrame.minX - requiredShift / 2
                })
                currentFrame = window.frame
            }

            let widthDelta = CGFloat(width) - currentFrame.width
            let resizeCorner = window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.996, dy: 0.996)
            )
            resizeCorner.click(
                forDuration: 0.15,
                thenDragTo: resizeCorner.withOffset(CGVector(dx: widthDelta, dy: 0))
            )
            XCTAssertTrue(waitUntil(timeout: 5) {
                abs(self.app.windows.firstMatch.frame.width - CGFloat(width))
                    <= QAWorkspaceMetricContract.frameTolerance
            })
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        func attachWindowScreenshot(_ label: String) {
            let window = app.windows.firstMatch
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).hover()
            let screenshot = XCTAttachment(screenshot: window.screenshot())
            screenshot.name = label
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        func selectMode(_ name: String, surfaceIdentifier: String) {
            let mode = documentModeControl()
            XCTAssertTrue(mode.waitForExistence(timeout: 5))
            selectDocumentMode(name)
            XCTAssertTrue(
                app.descendants(matching: .any)[surfaceIdentifier]
                    .waitForExistence(timeout: 8)
            )
        }

        prepareVisualFixture(width: 1_180)
        attachWindowScreenshot("Default 72ch — 1180×760 — Read — Inspector hidden")
        clickInspectorVisibilityControl()
        let inspector = app.scrollViews["scholium.researchInspector"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        attachWindowScreenshot("Default 72ch — 1180×760 — Read — Inspector visible")
        clickInspectorVisibilityControl()
        XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })

        selectMode("Edit", surfaceIdentifier: "Markdown editor, Edit mode")
        attachWindowScreenshot("Default 72ch — 1180×760 — Live Preview")
        selectMode("Source", surfaceIdentifier: "Markdown source editor")
        attachWindowScreenshot("Default 72ch — 1180×760 — Source")

        prepareVisualFixture(width: 1_180)
        for width in [1_380, 1_080, 900, 720] {
            resizeVisualFixture(width: width)
            attachWindowScreenshot("Default 72ch — \(width)×760 — Read")
        }

        let appMenu = app.menuBars.menuBarItems["Scholium QA"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
        appMenu.click()
        let settings = app.menuItems["Settings…"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let appearance = app.descendants(matching: .any)[
            "scholium.settings.destination.appearance"
        ].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 8))
        appearance.click()

        let lineWidth = app.sliders["Line width"]
        XCTAssertTrue(lineWidth.waitForExistence(timeout: 8))
        XCTAssertEqual(lineWidth.label, "Line width")
        XCTAssertEqual(sliderNumericValue(lineWidth), 72)
        XCTAssertTrue(
            app.staticTexts[
                "Measured in CSS character-width units; the exact measure varies by typeface."
            ].exists
        )
        lineWidth.click()
        lineWidth.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) {
            self.sliderNumericValue(lineWidth) == 73
        })

        let form = app.descendants(matching: .any)["scholium.appearance.form"]
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let save = app.buttons["Save Appearance"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        scrollUntilHittable(save, in: form)
        XCTAssertTrue(save.isEnabled)
        save.click()

        let manifest = homeDirectory.appendingPathComponent(
            "ApplicationSupport/Workspace/Styles/appearances.json"
        )
        XCTAssertTrue(waitUntil(timeout: 10) {
            (try? String(contentsOf: manifest, encoding: .utf8))?
                .contains("\"lineWidthCharacterUnits\" : 73") == true
        })
        let settingsWindow = settingsWindow()
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        scrollUntilHittable(lineWidth, in: form)
        XCTAssertEqual(sliderNumericValue(lineWidth), 73)
        let controlScreenshot = XCTAttachment(screenshot: settingsWindow.screenshot())
        controlScreenshot.name = "Appearance — Line width keyboard value 73ch"
        controlScreenshot.lifetime = .keepAlways
        add(controlScreenshot)
    }

    @MainActor
    func testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm() throws {
        let expectedTitle = "在长期论证中保持证据边界：Reasons, Values, and the Practical Option Space Across Competing Interpretations"
        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        XCTAssertTrue(workspace.waitForExistence(timeout: 10))
        let workspaceIdentity = workspace.identifier
        XCTAssertFalse(workspaceIdentity.isEmpty)
        XCTAssertEqual(
            workspace.frame.width,
            QAWorkspaceMetricContract.preferredWidth,
            accuracy: QAWorkspaceMetricContract.frameTolerance
        )
        XCTAssertGreaterThanOrEqual(
            workspace.frame.height,
            760,
            "XCU includes the native titlebar outside the configured Workspace content height."
        )
        XCTAssertLessThanOrEqual(
            workspace.frame.height,
            800,
            "The native titlebar must not turn the configured 760pt Workspace into a materially taller proof."
        )
        XCTAssertFalse(
            app.scrollViews["scholium.researchInspector"].exists,
            "The first Document-heading proof keeps the Inspector hidden."
        )

        let noteURL = triptychDirectory
            .appendingPathComponent("01-analyses", isDirectory: true)
            .appendingPathComponent("QA Document Heading Study.md")
        let sourceBefore = try Data(contentsOf: noteURL)
        XCTAssertTrue(waitForDocumentTitle(expectedTitle))

        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        selectDocumentMode("Review")
        XCTAssertEqual(mode.value as? String, "Review")
        let renderedDocument = workspace.descendants(matching: .any)["Rendered Markdown"]
        XCTAssertTrue(renderedDocument.waitForExistence(timeout: 10))
        let anchorParagraph = renderedDocument.staticTexts.matching(
            NSPredicate(
                format: "value BEGINSWITH %@",
                "A sustained philosophical argument asks the reader"
            )
        ).firstMatch
        XCTAssertTrue(anchorParagraph.waitForExistence(timeout: 10))

        func setBodyRhythm(
            lineHeight: Double,
            paragraphSpacing: Double,
            letterSpacing: Double
        ) {
            let appMenu = app.menuBars.menuBarItems["Scholium QA"]
            XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
            appMenu.click()
            let settings = app.menuItems["Settings…"]
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            settings.click()
            let appearance = app.descendants(matching: .any)[
                "scholium.settings.destination.appearance"
            ].firstMatch
            XCTAssertTrue(appearance.waitForExistence(timeout: 8))
            appearance.click()

            let form = app.descendants(matching: .any)["scholium.appearance.form"]
            XCTAssertTrue(form.waitForExistence(timeout: 5))
            let lineWidth = app.sliders["Line width"]
            XCTAssertTrue(lineWidth.waitForExistence(timeout: 8))
            XCTAssertEqual(sliderNumericValue(lineWidth), 72)

            func setSlider(_ label: String, target: Double, step: Double) {
                let slider = app.sliders.matching(
                    NSPredicate(format: "label == %@", label)
                ).firstMatch
                for _ in 0..<8 where !slider.exists {
                    form.swipeUp(velocity: .slow)
                }
                XCTAssertTrue(slider.waitForExistence(timeout: 5))
                scrollUntilHittable(slider, in: form)
                let currentValue = sliderNumericValue(slider)
                XCTAssertNotNil(currentValue)
                guard let currentValue else { return }
                if abs(currentValue - target) <= step / 10 {
                    return
                }
                slider.click()
                for _ in 0..<64 {
                    guard let current = sliderNumericValue(slider) else { break }
                    if abs(current - target) <= step / 10 {
                        break
                    }
                    let key: XCUIKeyboardKey = current > target ? .leftArrow : .rightArrow
                    slider.typeKey(key, modifierFlags: [])
                    _ = waitUntil(timeout: 1) {
                        guard let updated = self.sliderNumericValue(slider) else { return false }
                        return abs(updated - current) >= step / 2
                    }
                }
                XCTAssertTrue(waitUntil(timeout: 5) {
                    guard let value = self.sliderNumericValue(slider) else { return false }
                    return abs(value - target) <= step / 10
                })
            }

            setSlider("Line spacing", target: lineHeight, step: 0.05)
            let advancedAppearance = app.buttons[
                "scholium.appearance.advanced"
            ]
            XCTAssertTrue(advancedAppearance.waitForExistence(timeout: 5))
            scrollUntilHittable(advancedAppearance, in: form)
            advancedAppearance.click()
            func advancedAppearanceIsExpanded() -> Bool {
                advancedAppearance.value as? String == "Expanded"
            }
            XCTAssertTrue(waitUntil(timeout: 5, condition: advancedAppearanceIsExpanded))
            setSlider("Paragraph spacing", target: paragraphSpacing, step: 0.05)
            setSlider("Letter spacing", target: letterSpacing, step: 0.005)

            let save = app.buttons["Save Appearance"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            if save.isEnabled {
                scrollUntilHittable(save, in: form)
                save.click()
                XCTAssertTrue(waitUntil(timeout: 5) { !save.isEnabled })
            }

            let settingsWindow = settingsWindow()
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
            let settingsRoot = settingsWindow.descendants(matching: .any)[
                "scholium.settings.root"
            ]
            settingsWindow.buttons[XCUIIdentifierCloseWindow].click()
            XCTAssertTrue(waitUntil(timeout: 5) { !settingsRoot.exists })
            focusWorkspaceWindow(workspace)
            XCTAssertTrue(renderedDocument.waitForExistence(timeout: 8))
            XCTAssertTrue(anchorParagraph.waitForExistence(timeout: 8))
            XCTAssertEqual(mode.value as? String, "Review")
            XCTAssertEqual(
                self.documentTitle(in: workspace),
                expectedTitle
            )
        }

        setBodyRhythm(
            lineHeight: 2.00,
            paragraphSpacing: 1.00,
            letterSpacing: 0.020
        )
        XCTAssertTrue(
            anchorParagraph.isHittable,
            "The accepted ordinary first paragraph must remain visible beneath the long title."
        )
        let documentTitle = renderedDocument.staticTexts.matching(
            NSPredicate(
                format: "value == %@",
                "在长期论证中保持证据边界：Reasons, Values, and the Practical Option Space Across Competing Interpretations"
            )
        ).firstMatch
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            documentTitle.frame.height,
            40,
            "The long mixed-script H1 must wrap instead of truncating to one line."
        )
        let ordinaryScreenshot = XCTAttachment(screenshot: workspace.screenshot())
        ordinaryScreenshot.name = "Heading Study — accepted A — long mixed H1 — 1180×760 — Review — native window title"
        ordinaryScreenshot.lifetime = .keepAlways
        add(ordinaryScreenshot)

        resizeProofWindow(workspace, toWidth: 900)
        XCTAssertTrue(documentTitle.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(
            documentTitle.frame.height,
            40,
            "The long mixed-script H1 must remain wrapped after the Workspace narrows."
        )
        XCTAssertGreaterThanOrEqual(documentTitle.frame.minX, renderedDocument.frame.minX)
        XCTAssertLessThanOrEqual(documentTitle.frame.maxX, renderedDocument.frame.maxX)
        let narrowScreenshot = XCTAttachment(screenshot: workspace.screenshot())
        narrowScreenshot.name = "Heading Study — accepted A — long mixed H1 — 900×760 — Review — native window title"
        narrowScreenshot.lifetime = .keepAlways
        add(narrowScreenshot)

        XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)
        XCTAssertEqual(workspace.identifier, workspaceIdentity)
        XCTAssertEqual(mode.value as? String, "Review")
    }

    @MainActor
    func testTwoHundredPercentDocumentTextPersistsAcrossEveryMode() throws {
        app.terminate()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.documentTextSizeMenu"].exists,
            "Text size belongs in the View menu rather than permanent document chrome."
        )

        app.menuBars.menuBarItems["View"].click()
        let documentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(documentTextSizeMenu.waitForExistence(timeout: 3))
        documentTextSizeMenu.hover()
        let twoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(twoHundredPercent.waitForExistence(timeout: 3))
        twoHundredPercent.click()

        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        selectDocumentMode("Edit")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown editor, Edit mode"].waitForExistence(timeout: 8))

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))

        selectDocumentMode("Review")
        waitForCurrentDocumentSurface()

        let sessionFile = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let data = try? Data(contentsOf: sessionFile),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let scale = snapshot["documentTextScale"] as? NSNumber else { return false }
            return scale.doubleValue == 2.0
        })

        app.terminate()
        app = configuredApplication(sessionID: sessionID, initialWorkspaceWidth: 900)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        app.menuBars.menuBarItems["View"].click()
        let restoredDocumentTextSizeMenu = app.menuItems["Document Text Size"].firstMatch
        XCTAssertTrue(restoredDocumentTextSizeMenu.waitForExistence(timeout: 3))
        restoredDocumentTextSizeMenu.hover()
        let restoredTwoHundredPercent = app.menuItems["200%"].firstMatch
        XCTAssertTrue(restoredTwoHundredPercent.waitForExistence(timeout: 3))
        XCTAssertFalse(
            restoredTwoHundredPercent.isEnabled,
            "The restored window session must reapply 200% after asynchronous workspace restoration."
        )
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testResearchRecordsReusesTriptychWindowIndependentlyFromInspector() throws {
        waitForCurrentDocumentSurface()
        let currentTriptychID = try triptychID(at: triptychDirectory)
        let originalWorkspaceID = app.windows.firstMatch.identifier
        let originalWorkspace = app.windows[originalWorkspaceID]
        let inspector = app.descendants(matching: .any)["scholium.researchInspector"]
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: originalWorkspace)
        let recordButton = researchRecordsControl(in: originalWorkspace)

        if !inspector.exists {
            app.typeKey("b", modifierFlags: [.command, .option])
        }
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        XCTAssertTrue(recordButton.exists)
        clickResearchRecordsControl(in: originalWorkspace)

        let recordWindow = app.windows[
            "scholium-research-records-\(currentTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.exists)
        XCTAssertTrue(inspector.exists)
        XCTAssertTrue(recordWindow.textFields[
            "scholium.researchRecord.search"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.empty"
        ].waitForExistence(timeout: 5))
        let scopeMenu = recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.scope"
        ]
        XCTAssertTrue(scopeMenu.exists)
        XCTAssertEqual(scopeMenu.value as? String, "This Note")
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.view"
        ].exists)

        focusWorkspaceWindow(originalWorkspace)
        app.menuBars.menuBarItems["Research"].click()
        let triptychRecords = app.menuItems["Triptych Records"]
        XCTAssertTrue(triptychRecords.waitForExistence(timeout: 5))
        triptychRecords.click()
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(scopeMenu.value as? String, "Triptych")

        focusWorkspaceWindow(originalWorkspace)
        clickResearchRecordsControl(in: originalWorkspace)
        XCTAssertTrue(waitUntil(timeout: 5) {
            scopeMenu.value as? String == "This Note"
        })

        focusWorkspaceWindow(originalWorkspace)
        app.typeKey("n", modifierFlags: [.command])
        let workspaceWindows = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        )
        XCTAssertTrue(
            waitUntil(timeout: 15) { workspaceWindows.count == 2 },
            "New Window must create a second Workspace without replacing the keyed Records window."
        )
        let newWorkspace = try XCTUnwrap(
            workspaceWindows.allElementsBoundByIndex.first(where: { window in
                window.identifier != originalWorkspaceID
            })
        )
        focusWorkspaceWindow(newWorkspace)
        openNote("QA Autosave B.md", expectedTitle: "QA Autosave B", in: newWorkspace)
        XCTAssertTrue(recordWindow.textFields["scholium.researchRecord.search"].exists)
        let secondRecordButton = researchRecordsControl(in: newWorkspace)
        XCTAssertTrue(secondRecordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: newWorkspace)
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.windows.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium-research-records-")
            ).count,
            1,
            "Two Workspace windows for one Triptych must reuse one Research Records window."
        )

        XCTAssertTrue(recordWindow.textFields["scholium.researchRecord.search"].exists)
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordWindow.exists })
        focusWorkspaceWindow(originalWorkspace)
        XCTAssertTrue(inspector.exists)
        focusWorkspaceWindow(newWorkspace)
        closeFrontmostWindow()
    }

    @MainActor
    func testLiteratureRecommendationHandlingStaysInsideParentRecord() throws {
        app.terminate()
        let fixture = try seedResearchRecordFixture()
        let recommendationID = try XCTUnwrap(fixture.recommendationID)
        let currentTriptychID = try triptychID(at: triptychDirectory)
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordsButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordsButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)

        let recordsWindow = app.windows[
            "scholium-research-records-\(currentTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(recordsWindow.waitForExistence(timeout: 8))
        for nativeSidebarLabel in ["Show Sidebar", "Hide Sidebar", "Toggle Sidebar"] {
            XCTAssertFalse(recordsWindow.buttons[nativeSidebarLabel].exists)
        }
        let recommendations = recordsWindow.buttons["Reading Leads"].firstMatch
        XCTAssertTrue(recommendations.waitForExistence(timeout: 5))
        recommendations.click()

        let recommendationRow = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecommendation.row.\(recommendationID.uuidString)"
        ]
        XCTAssertTrue(recommendationRow.waitForExistence(timeout: 8))
        XCTAssertEqual(recommendationRow.buttons.count, 1)
        XCTAssertTrue(
            recommendationRow.buttons.firstMatch.label.hasPrefix(
                "Source-Grounded Inquiry"
            ),
            "The one destination must begin with the literature identity."
        )
        recommendationRow.buttons.firstMatch.click()
        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "scholium.researchRecommendation.workspace"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordsWindow.staticTexts["WHY IT WAS RECOMMENDED"].exists)
        XCTAssertTrue(recordsWindow.staticTexts["p. 42"].exists)
        let recommendationReading = recordsWindow.scrollViews.firstMatch
        XCTAssertTrue(recommendationReading.waitForExistence(timeout: 5))
        let analyzedSource = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecommendation.source"
        ]
        scrollUntilHittable(analyzedSource, in: recommendationReading)

        focusWorkspaceWindow(workspace)
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        let workspaceCount = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).count
        focusAuxiliaryWindow(recordsWindow, menuItemTitle: "Research Records")
        let openAnalysis = recordsWindow.buttons[
            "scholium.researchRecommendation.openAnalysis"
        ]
        scrollUntilHittable(openAnalysis, in: recommendationReading)
        openAnalysis.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: workspace))
        XCTAssertEqual(
            app.windows.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
            ).count,
            workspaceCount,
            "Open Analysis must reuse the same Triptych Workspace."
        )
        focusAuxiliaryWindow(recordsWindow, menuItemTitle: "Research Records")

        let handled = recordsWindow.buttons[
            "scholium.researchRecommendation.handled.\(recommendationID.uuidString)"
        ]
        scrollUntilHittable(handled, in: recommendationReading)
        handled.click()
        XCTAssertTrue(waitUntil(timeout: 8) {
            handled.value as? String == "Handled" && handled.isEnabled
        })
        let backToRecords = recordsWindow.buttons["scholium.researchRecords.back"]
        XCTAssertTrue(backToRecords.waitForExistence(timeout: 5))
        backToRecords.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !recommendationRow.exists })

        let filterMenu = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecords.filters"
        ]
        XCTAssertTrue(filterMenu.waitForExistence(timeout: 5))
        filterMenu.click()
        XCTAssertTrue(app.menuItems["Handled"].waitForExistence(timeout: 3))
        app.menuItems["Handled"].click()
        XCTAssertTrue(recommendationRow.waitForExistence(timeout: 8))
        recommendationRow.click()

        let editNote = recordsWindow.buttons[
            "scholium.researchRecommendation.noteHeader"
        ]
        scrollUntilHittable(editNote, in: recommendationReading)
        editNote.click()
        let noteSheet = recordsWindow.sheets.firstMatch
        XCTAssertTrue(noteSheet.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(noteSheet.frame.width, 439)
        XCTAssertGreaterThanOrEqual(noteSheet.frame.height, 319)
        XCTAssertTrue(noteSheet.buttons["Cancel"].isHittable)
        XCTAssertTrue(noteSheet.buttons["Save"].isHittable)
        let noteEditor = recordsWindow.textViews[
            "scholium.researchRecommendation.noteEditor"
        ]
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5))
        try paste("Follow up after checking the cited chapter.", into: noteEditor)
        recordsWindow.sheets.buttons["Save"].click()
        XCTAssertTrue(recordsWindow.staticTexts[
            "Follow up after checking the cited chapter."
        ].waitForExistence(timeout: 8))

        let handledAfterNote = recordsWindow.buttons[
            "scholium.researchRecommendation.handled.\(recommendationID.uuidString)"
        ]
        scrollUntilHittable(handledAfterNote, in: recommendationReading)
        handledAfterNote.click()
        backToRecords.click()
        filterMenu.click()
        XCTAssertTrue(app.menuItems["Unprocessed"].waitForExistence(timeout: 3))
        app.menuItems["Unprocessed"].click()
        XCTAssertTrue(recommendationRow.waitForExistence(timeout: 8))
        recommendationRow.click()
        XCTAssertTrue(recordsWindow.staticTexts[
            "Follow up after checking the cited chapter."
        ].exists)

        let openParent = recordsWindow.buttons[
            "scholium.researchRecommendation.openParentRecord"
        ]
        XCTAssertTrue(openParent.exists)
        openParent.click()
        XCTAssertTrue(recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ].waitForExistence(timeout: 8))
        let embeddedRecommendation = recordsWindow.buttons[
            "scholium.researchRecord.recommendation.\(recommendationID.uuidString)"
        ]
        XCTAssertTrue(embeddedRecommendation.waitForExistence(timeout: 5))
        embeddedRecommendation.click()
        XCTAssertTrue(recordsWindow.staticTexts["WHY IT WAS RECOMMENDED"].waitForExistence(
            timeout: 5
        ))

        recordsWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordsWindow.exists })
    }

    @MainActor
    func testResearchSheetLayoutsRemainReachable() throws {
        app.terminate()
        let fixture = try seedResearchRecordFixture()
        let recommendationID = try XCTUnwrap(fixture.recommendationID)
        let currentTriptychID = try triptychID(at: triptychDirectory)
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)

        waitForDocumentActionRail()
        let actionSheet = openDiscussFromActions()
        XCTAssertGreaterThanOrEqual(actionSheet.frame.width, 519)
        XCTAssertGreaterThanOrEqual(actionSheet.frame.height, 279)
        XCTAssertTrue(actionSheet.staticTexts["Discuss"].exists)
        XCTAssertTrue(actionSheet.buttons["Cancel"].isHittable)
        XCTAssertTrue(actionSheet.buttons["Copy Handoff"].isHittable)
        retainScreenshot(of: workspace, named: "Research Action sheet layout")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !actionSheet.exists })

        let recordsButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordsButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)
        let recordsWindow = app.windows[
            "scholium-research-records-\(currentTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(recordsWindow.waitForExistence(timeout: 8))

        let readingLeads = recordsWindow.buttons["Reading Leads"].firstMatch
        XCTAssertTrue(readingLeads.waitForExistence(timeout: 5))
        readingLeads.click()
        let recommendationRow = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecommendation.row.\(recommendationID.uuidString)"
        ]
        XCTAssertTrue(recommendationRow.waitForExistence(timeout: 8))
        recommendationRow.buttons.firstMatch.click()

        let recommendationReading = recordsWindow.scrollViews.firstMatch
        XCTAssertTrue(recommendationReading.waitForExistence(timeout: 5))
        let editNote = recordsWindow.buttons[
            "scholium.researchRecommendation.noteHeader"
        ]
        for _ in 0..<4 where !editNote.exists {
            recommendationReading.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(editNote.waitForExistence(timeout: 5))
        scrollUntilHittable(editNote, in: recommendationReading)
        editNote.click()
        let noteSheet = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecommendation.noteSheet"
        ]
        XCTAssertTrue(noteSheet.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(noteSheet.frame.width, 439)
        XCTAssertGreaterThanOrEqual(noteSheet.frame.height, 319)
        XCTAssertTrue(noteSheet.staticTexts["Researcher Note"].exists)
        XCTAssertTrue(noteSheet.buttons["Cancel"].isHittable)
        XCTAssertTrue(noteSheet.buttons["Save"].isHittable)
        XCTAssertTrue(recordsWindow.textViews[
            "scholium.researchRecommendation.noteEditor"
        ].exists)
        retainScreenshot(of: recordsWindow, named: "Reading Lead note sheet layout")
        noteSheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !noteSheet.exists })

        let back = recordsWindow.buttons["scholium.researchRecords.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.click()
        let records = recordsWindow.buttons["Records"].firstMatch
        XCTAssertTrue(records.waitForExistence(timeout: 5))
        records.click()
        let recordRow = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertTrue(recordRow.waitForExistence(timeout: 8))
        recordRow.click()

        let evidenceScroll = recordsWindow.scrollViews[
            "scholium.researchRecord.evidence"
        ]
        XCTAssertTrue(evidenceScroll.waitForExistence(timeout: 5))
        let responseEditor = recordsWindow.buttons[
            "scholium.researchRecord.response.add"
        ]
        let recordReading = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        scrollUntilHittable(responseEditor, in: recordReading)
        responseEditor.click()
        let responseSheet = recordsWindow.descendants(matching: .any)[
            "scholium.researchResponse.sheet"
        ]
        XCTAssertTrue(responseSheet.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(responseSheet.frame.width, 619)
        XCTAssertGreaterThanOrEqual(responseSheet.frame.height, 599)
        XCTAssertTrue(responseSheet.staticTexts["Researcher Response"].exists)
        let cancelResponse = responseSheet.buttons["Cancel"]
        XCTAssertTrue(cancelResponse.isHittable)
        retainScreenshot(of: recordsWindow, named: "Researcher Response sheet layout")
        cancelResponse.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !responseSheet.exists })

        recordsWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordsWindow.exists })
    }

    @MainActor
    func testResearchRecordFollowUpReopensAccessiblyOnTheMountedRecord() throws {
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        selectVault(
            "scholium.vault.topic_knowledge",
            waitingFor: "scholium.noteRow.QA Topic.md"
        )
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: workspace)
        waitForDocumentActionRail()
        let synthesize = app.descendants(matching: .any)[
            "scholium.researchAction.synthesize"
        ].firstMatch
        XCTAssertTrue(synthesize.waitForExistence(timeout: 8))
        synthesize.click()
        let actionSheet = app.sheets.firstMatch
        XCTAssertTrue(actionSheet.descendants(matching: .any)[
            "scholium.researchAction.sheet"
        ].waitForExistence(timeout: 8))
        let researchRequest = actionSheet.textViews[
            "scholium.researchAction.academicText.research-request"
        ]
        XCTAssertTrue(researchRequest.waitForExistence(timeout: 5))
        researchRequest.click()
        researchRequest.typeText(
            "Create a disposable completed result for mounted Follow-up routing QA."
        )
        let copyHandoff = actionSheet.buttons[
            "scholium.researchAction.copyHandoff"
        ]
        XCTAssertTrue(waitUntil(timeout: 5) {
            copyHandoff.isEnabled && copyHandoff.isHittable
        })
        copyHandoff.click()
        XCTAssertTrue(waitUntil(timeout: 15) { !actionSheet.exists })

        let runID = try latestLocalResearchExecutionRunID()
        let copiedInstructions = try pasteboardText()
        let handoffLines = copiedInstructions.components(separatedBy: .newlines)
        let runLocator = try XCTUnwrap(
            handoffLines.first { $0.hasPrefix("Scholium Run: ") }.map {
                String($0.dropFirst("Scholium Run: ".count))
            }
        )
        let pairingCode = try XCTUnwrap(
            handoffLines.first { $0.hasPrefix("Pairing Code: ") }.map {
                String($0.dropFirst("Pairing Code: ".count))
            }
        )
        let pairingOutput = try runScholiumCLI(
            ["agent", "pair", "--run", runLocator],
            stdin: Data("\(pairingCode)\n".utf8)
        )
        XCTAssertTrue(pairingOutput.contains(runLocator))
        let resultSubmission = try JSONSerialization.data(withJSONObject: [
            "schema_version": 3,
            "record_title": "Mounted Follow-up routing result",
            "disposition": "completed",
            "academic_results": [
                "values": [
                    "synthesis-outcome": [
                        "kind": "freeText",
                        "text": "A disposable synthesis that verifies mounted Follow-up routing.",
                    ],
                    "contribution": [
                        "kind": "multipleChoice",
                        "choices": ["adds"],
                    ],
                ],
            ],
            "fidelity_outcomes": [],
        ])
        let resultOutput = try runScholiumCLI(
            ["agent", "submit-result", "--run", runLocator, "--from", "-"],
            stdin: resultSubmission
        )
        let resultReceipt = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultOutput.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(resultReceipt["state"] as? String, "finalized")
        XCTAssertEqual(resultReceipt["record_formed"] as? Bool, true)

        let notifications = workspace.buttons[
            "scholium.triptychNotifications"
        ]
        XCTAssertTrue(waitUntil(timeout: 20) {
            notifications.exists && notifications.isEnabled
        })
        notifications.click()
        var popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 8))
        let activityID = "scholium.notification.action.\(runID.uuidString)"
        var activity = popover.descendants(matching: .any)[activityID]
        XCTAssertTrue(activity.waitForExistence(timeout: 8))
        let reviewResult = app.buttons[
            "scholium.notification.action.reviewResult.\(runID.uuidString)"
        ].firstMatch
        XCTAssertTrue(
            reviewResult.waitForExistence(timeout: 25),
            "The seeded completed Record did not replace the active Run with Result Ready."
        )
        reviewResult.click()

        let recordsWindow = researchRecordsWindow()
        let reading = recordsWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        XCTAssertTrue(reading.waitForExistence(timeout: 8))
        XCTAssertTrue(
            reading.staticTexts["Mounted Follow-up routing result"]
                .waitForExistence(timeout: 5)
        )

        for attempt in 1...2 {
            if popover.exists {
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitUntil(timeout: 5) { !popover.exists })
            }
            workspace.click()
            XCTAssertTrue(notifications.exists && notifications.isEnabled)
            notifications.click()
            popover = app.popovers.firstMatch
            XCTAssertTrue(popover.waitForExistence(timeout: 8))
            activity = popover.descendants(matching: .any)[activityID]
            XCTAssertTrue(activity.waitForExistence(timeout: 8))
            let notificationFollowUp = app.buttons[
                "scholium.notification.action.followUp.\(runID.uuidString)"
            ].firstMatch
            XCTAssertTrue(notificationFollowUp.waitForExistence(timeout: 5))
            XCTAssertTrue(notificationFollowUp.isHittable)
            notificationFollowUp.click()

            let sheet = recordsWindow.sheets.firstMatch
            let sheetMarker = sheet.descendants(matching: .any)[
                "scholium.researchFollowUp.sheet"
            ]
            XCTAssertTrue(
                sheet.waitForExistence(timeout: 10)
                    && sheetMarker.waitForExistence(timeout: 5),
                "Mounted Record Follow-up attempt \(attempt) did not present."
            )
            XCTAssertTrue(sheet.descendants(matching: .any)[
                "scholium.researchFollowUp.actionPicker"
            ].exists)
            XCTAssertTrue(sheet.buttons["Cancel"].isEnabled)
            XCTAssertTrue(sheet.buttons["Continue"].exists)

            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
            XCTAssertTrue(reading.exists)
        }

        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: recordsWindow
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [focusExpectation], timeout: 3),
            .completed,
            "Dismissing notification-routed Follow-up must keep keyboard focus in the mounted Records window."
        )
    }

    @MainActor
    private func retainScreenshot(of element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testResearchRecordParticipantPreviewPopoverKeyboardAndDismissal() throws {
        app.terminate()
        let fixture = try seedResearchRecordFixture(hasEvidenceOverflow: true)
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)

        let recordWindow = researchRecordsWindow()
        let recordRow = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertTrue(recordRow.waitForExistence(timeout: 8))
        recordRow.click()

        let detailScroll = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        let evidenceScroll = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.evidence"
        ]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(evidenceScroll.waitForExistence(timeout: 5))
        let participantsHeader = recordWindow.buttons[
            "scholium.researchRecord.participantsHeader"
        ]
        scrollUntilHittable(participantsHeader, in: evidenceScroll)

        let overflowWorkID = try XCTUnwrap(fixture.overflowParticipantNoteIDs.last)
        XCTAssertFalse(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.note.\(overflowWorkID.uuidString)"
        ].exists)

        participantsHeader.click()
        let participantPopover = app.descendants(matching: .any)[
            "scholium.researchRecord.participantsPopover"
        ]
        XCTAssertTrue(participantPopover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchRecord.note.\(overflowWorkID.uuidString).all"
        ].exists)
        let firstParticipantRow = app.buttons[
            "scholium.researchRecord.note.\(fixture.analysisNoteID.uuidString).all"
        ]
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(firstParticipantRow.waitForExistence(timeout: 5))
        XCTAssertFalse(keyboardFocus.evaluate(with: firstParticipantRow))
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 2) {
            keyboardFocus.evaluate(with: firstParticipantRow)
        })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !participantPopover.exists })
        XCTAssertTrue(waitUntil(timeout: 3) {
            keyboardFocus.evaluate(with: participantsHeader)
        })

        participantsHeader.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(participantPopover.waitForExistence(timeout: 5))
        detailScroll.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { !participantPopover.exists },
            "A native outside click must dismiss the Participant popover."
        )

    }

    @MainActor
    func testResearchRecordAcademicEvidenceAndConfirmedDeletion() throws {
        app.terminate()
        let fixture = try seedResearchRecordFixture(
            hasUnavailableTopicRevision: true,
            hasEvidenceOverflow: true
        )
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth)
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)

        let recordWindow = researchRecordsWindow()
        XCTAssertFalse(recordWindow.buttons["Record Trash"].exists)
        XCTAssertFalse(recordWindow.descendants(matching: .any)[
            "Record Trash"
        ].exists)
        XCTAssertFalse(recordWindow.buttons["Restore"].exists)
        let row = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.hover()
        let rowHoverAttachment = XCTAttachment(screenshot: recordWindow.screenshot())
        rowHoverAttachment.name = "Research Record collection row hover"
        rowHoverAttachment.lifetime = .keepAlways
        add(rowHoverAttachment)
        row.click()

        let detailScroll = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        let evidenceScroll = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.evidence"
        ]
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(evidenceScroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(detailScroll.frame.width, evidenceScroll.frame.width)
        XCTAssertGreaterThanOrEqual(evidenceScroll.frame.width, 259)
        XCTAssertLessThanOrEqual(evidenceScroll.frame.width, 305)
        let evidenceToggle = recordWindow.buttons[
            "scholium.researchRecord.toggleEvidence"
        ]
        XCTAssertTrue(evidenceToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(evidenceToggle.value as? String, "Shown")
        let splitReadingWidth = detailScroll.frame.width
        evidenceToggle.click()
        XCTAssertTrue(waitUntil(timeout: 2) { !evidenceScroll.exists })
        XCTAssertEqual(evidenceToggle.value as? String, "Hidden")
        let expandedDetailScroll = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        XCTAssertTrue(expandedDetailScroll.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(expandedDetailScroll.frame.width, splitReadingWidth)
        evidenceToggle.click()
        XCTAssertTrue(evidenceScroll.waitForExistence(timeout: 2))
        XCTAssertEqual(evidenceToggle.value as? String, "Shown")
        XCTAssertFalse(recordWindow.staticTexts["COMPLETED"].exists)
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchResult.finalized"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.staticTexts[
            "No academic result fields were configured for this Action."
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.attributedHeading"
        ].exists)
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.statementRole.\(fixture.researcherStatementID.uuidString)"
        ].exists)
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.statementRole.\(fixture.agentStatementID.uuidString)"
        ].exists)
        XCTAssertFalse(recordWindow.staticTexts["Researcher Response"].exists)
        XCTAssertFalse(recordWindow.staticTexts["Agent Feedback"].exists)
        let recordWorkspaceAttachment = XCTAttachment(screenshot: recordWindow.screenshot())
        recordWorkspaceAttachment.name = "Research Record reading and evidence workspace"
        recordWorkspaceAttachment.lifetime = .keepAlways
        add(recordWorkspaceAttachment)
        let participantLink = recordWindow.buttons[
            "scholium.researchRecord.note.\(fixture.analysisNoteID.uuidString)"
        ]
        XCTAssertTrue(participantLink.waitForExistence(timeout: 5))
        participantLink.hover()
        let evidenceHoverAttachment = XCTAttachment(screenshot: recordWindow.screenshot())
        evidenceHoverAttachment.name = "Research Record evidence row rounded hover"
        evidenceHoverAttachment.lifetime = .keepAlways
        add(evidenceHoverAttachment)
        let participantsHeader = recordWindow.buttons[
            "scholium.researchRecord.participantsHeader"
        ]
        let responseEditor = recordWindow.buttons[
            "scholium.researchRecord.response.add"
        ]
        XCTAssertTrue(participantsHeader.exists)
        let effectsHeader = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.effectsHeader"
        ]
        XCTAssertTrue(effectsHeader.exists)
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.effects.result"
        ].exists)
        XCTAssertTrue(responseEditor.exists)
        XCTAssertEqual(participantsHeader.frame.minX, effectsHeader.frame.minX, accuracy: 1)
        XCTAssertEqual(participantsHeader.frame.height, effectsHeader.frame.height, accuracy: 1)

        let overflowWorkID = try XCTUnwrap(fixture.overflowParticipantNoteIDs.last)
        XCTAssertFalse(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.note.\(overflowWorkID.uuidString)"
        ].exists)

        participantsHeader.click()
        let participantPopover = app.descendants(matching: .any)[
            "scholium.researchRecord.participantsPopover"
        ]
        XCTAssertTrue(participantPopover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)[
            "scholium.researchRecord.note.\(overflowWorkID.uuidString).all"
        ].exists)
        let firstParticipantPopoverRow = app.buttons[
            "scholium.researchRecord.note.\(fixture.analysisNoteID.uuidString).all"
        ]
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(firstParticipantPopoverRow.waitForExistence(timeout: 5))
        XCTAssertFalse(
            keyboardFocus.evaluate(with: firstParticipantPopoverRow),
            "Pointer opening must not paint keyboard focus on the first Participant row."
        )
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 2) {
                keyboardFocus.evaluate(with: firstParticipantPopoverRow)
            },
            "Tab must move visible keyboard focus from the popover scroll owner to its first row."
        )
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !participantPopover.exists })

        scrollUntilHittable(responseEditor, in: detailScroll)
        responseEditor.click()
        let responseSheet = recordWindow.descendants(matching: .any)[
            "scholium.researchResponse.sheet"
        ]
        XCTAssertTrue(responseSheet.waitForExistence(timeout: 5))
        let cancelResponse = responseSheet.buttons["Cancel"]
        XCTAssertTrue(cancelResponse.waitForExistence(timeout: 5))
        cancelResponse.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !responseSheet.exists })
        XCTAssertFalse(recordWindow.buttons[
            "scholium.researchRecord.compare.\(fixture.analysisNoteID.uuidString)"
        ].exists)
        XCTAssertFalse(recordWindow.staticTexts["METHOD FEEDBACK"].exists)
        let deletePermanently = recordWindow.buttons[
            "scholium.researchRecord.deletePermanently"
        ]
        XCTAssertTrue(deletePermanently.waitForExistence(timeout: 5))
        deletePermanently.click()
        XCTAssertTrue(app.staticTexts[
            "Delete This Research Record Permanently?"
        ].waitForExistence(timeout: 5))
        let deletionTitle = app.staticTexts[
            "Delete This Research Record Permanently?"
        ]
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !deletionTitle.exists })
        XCTAssertTrue(detailScroll.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) {
            NSPredicate(format: "hasKeyboardFocus == true")
                .evaluate(with: deletePermanently)
        })
        XCTAssertTrue(deletePermanently.isHittable)
        deletePermanently.click()
        XCTAssertTrue(app.staticTexts[
            "Delete This Research Record Permanently?"
        ].waitForExistence(timeout: 5))
        let confirm = recordWindow.sheets.buttons["action-button-1"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Delete Permanently")
        confirm.click()
        XCTAssertTrue(waitUntil(timeout: 8) { !row.exists })
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.empty"
        ].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Research Records Unavailable"].exists)
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordWindow.exists })
        focusWorkspaceWindow(workspace)
        clickResearchRecordsControl(in: workspace)
        let reopenedRecordWindow = researchRecordsWindow()
        let reopenedRow = reopenedRecordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertFalse(
            reopenedRow.exists,
            "A reopened browser must consume the controller's republished deletion."
        )
        reopenedRecordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !reopenedRecordWindow.exists })
    }

    @MainActor
    func testResearchRecordActionDeepLinkAndCrossTriptychFocus() throws {
        let secondTriptychDirectory = try XCTUnwrap(secondTriptychDirectory)

        // The first isolated launch registers the fixture Triptych. Relaunch
        // without the fixture shortcut so File > New Triptych exercises the
        // production Bootstrap route instead of opening another copy of the
        // first QA workspace.
        app.terminate()
        let fixture = try seedResearchRecordFixture()
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth),
            usesFixtureWorkspace: false,
            appearance: .light
        )
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspaceWindows = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        )
        let initialWorkspaceMatch = workspaceWindows.firstMatch
        XCTAssertTrue(initialWorkspaceMatch.waitForExistence(timeout: 10))
        let initialWorkspaceID = initialWorkspaceMatch.identifier
        let initialWorkspace = app.windows[initialWorkspaceID]

        app.menuBars.menuBarItems["File"].click()
        let newTriptych = app.menuItems["New Triptych…"]
        XCTAssertTrue(newTriptych.waitForExistence(timeout: 3))
        newTriptych.click()

        let setup = app.descendants(matching: .any)["scholium.bootstrap"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        app.buttons["Get Started"].click()
        XCTAssertTrue(app.staticTexts["Choose a Starting Point"].waitForExistence(timeout: 5))
        let connectExisting = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Connect Existing Folders")
        ).firstMatch
        XCTAssertTrue(connectExisting.waitForExistence(timeout: 5))
        connectExisting.click()
        app.buttons["Continue"].click()
        chooseSetupFolder(
            secondTriptychDirectory.appendingPathComponent("01-analyses", isDirectory: true),
            role: "Analyses"
        )
        app.buttons["Continue"].click()
        chooseSetupFolder(
            secondTriptychDirectory.appendingPathComponent("02-topics", isDirectory: true),
            role: "Topics"
        )
        app.buttons["Continue"].click()
        chooseSetupFolder(
            secondTriptychDirectory.appendingPathComponent("03-works", isDirectory: true),
            role: "Works"
        )
        app.buttons["Continue"].click()

        XCTAssertTrue(app.staticTexts["Authorize the Detected Folder"].waitForExistence(timeout: 5))
        authorizePortableFolder(secondTriptychDirectory)
        XCTAssertTrue(app.staticTexts["Review the Connected Triptych"].waitForExistence(timeout: 5))
        let useTriptych = app.buttons["Use This Triptych"]
        XCTAssertTrue(useTriptych.isEnabled)
        useTriptych.click()
        XCTAssertTrue(app.staticTexts["Your Triptych Is Ready"].waitForExistence(timeout: 30))
        app.buttons["Open Workspace"].click()

        XCTAssertTrue(waitUntil(timeout: 45) {
            workspaceWindows.count == 2 && !setup.exists
        })
        let secondWorkspace = app.windows.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier != %@",
                "scholium-main-",
                initialWorkspaceID
            )
        ).firstMatch
        XCTAssertTrue(
            secondWorkspace.waitForExistence(timeout: 10),
            "The second Triptych must open in its own native Workspace window."
        )
        let initialTriptychID = try triptychID(at: triptychDirectory)
        let secondTriptychID = try triptychID(at: secondTriptychDirectory)
        XCTAssertNotEqual(
            initialTriptychID,
            secondTriptychID,
            "The focus journey must use two distinct Triptych identities."
        )

        focusWorkspaceWindow(initialWorkspace)
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: initialWorkspace)
        let recordButton = researchRecordsControl(in: initialWorkspace)
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: initialWorkspace)

        let recordWindow = app.windows[
            "scholium-research-records-\(initialTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 8))
        XCTAssertEqual(
            recordWindow.frame.width,
            760,
            accuracy: QAWorkspaceMetricContract.frameTolerance
        )
        XCTAssertEqual(
            recordWindow.frame.height,
            680,
            accuracy: 8,
            "The ordinary Records window must expose the specified 760 by 680 default frame."
        )
        let scopeMenu = recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.scope"
        ]
        let recordsView = recordWindow.buttons["Records"].firstMatch
        let recommendationsView = recordWindow.buttons["Reading Leads"].firstMatch
        XCTAssertTrue(scopeMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(recordsView.waitForExistence(timeout: 5))
        XCTAssertTrue(recommendationsView.waitForExistence(timeout: 5))
        XCTAssertTrue(scopeMenu.isHittable)
        XCTAssertEqual(scopeMenu.value as? String, "This Note")
        XCTAssertTrue(recordsView.isHittable)
        XCTAssertTrue(selectionControlIsSelected(recordsView))

        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        recordsView.click()
        for _ in 0..<24 where !keyboardFocus.evaluate(with: recordsView) {
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(
            keyboardFocus.evaluate(with: recordsView),
            "The View index must be reachable by keyboard."
        )
        scopeMenu.click()
        XCTAssertTrue(
            app.menuItems["Triptych"].waitForExistence(timeout: 3),
            "The Scope control must remain an accessible native menu."
        )
        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecords.collection"
        ].waitForExistence(timeout: 5))
        XCTAssertTrue(scopeMenu.isHittable)
        XCTAssertTrue(recordsView.isHittable)
        for nativeSidebarLabel in ["Show Sidebar", "Hide Sidebar", "Toggle Sidebar"] {
            XCTAssertFalse(recordWindow.buttons[nativeSidebarLabel].exists)
        }
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ].waitForExistence(timeout: 8))
        XCTAssertTrue(recordWindow.buttons["Record, 1 results"].exists)
        let populatedSearchField = recordWindow.textFields[
            "scholium.researchRecord.search"
        ]
        XCTAssertTrue(populatedSearchField.waitForExistence(timeout: 5))
        let populatedSearchFrame = populatedSearchField.frame
        let recordCollection = recordWindow.scrollViews[
            "scholium.researchRecords.collection"
        ]
        XCTAssertTrue(recordCollection.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(
            recordCollection.frame.width,
            640,
            "The collection-first index must use the full Records window width."
        )
        let recordRow = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.row.\(fixture.recordID.uuidString)"
        ]
        XCTAssertLessThanOrEqual(
            recordRow.frame.height,
            120,
            "A scanning row must retain the compact collection rhythm."
        )
        XCTAssertTrue(recordRow.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "QA Autosave A")
        ).firstMatch.exists)

        recordRow.click()
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ].waitForExistence(timeout: 5))
        let readingPlane = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.detail"
        ]
        let evidenceRail = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.evidence"
        ]
        XCTAssertTrue(readingPlane.waitForExistence(timeout: 5))
        XCTAssertTrue(evidenceRail.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(readingPlane.frame.width, evidenceRail.frame.width)
        XCTAssertGreaterThanOrEqual(evidenceRail.frame.width, 259)
        XCTAssertLessThanOrEqual(evidenceRail.frame.width, 305)
        XCTAssertTrue(recordWindow.staticTexts["Synthetic Action Agent"].exists)
        let agentStatement = recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.statement.\(fixture.agentStatementID.uuidString)"
        ]
        XCTAssertTrue(agentStatement.exists)
        XCTAssertTrue(recordWindow.descendants(matching: .any)[
            "scholium.researchRecord.checkFidelity.unverified"
        ].exists)
        let topicLink = recordWindow.buttons[
            "scholium.researchRecord.note.\(fixture.topicNoteID.uuidString)"
        ]
        XCTAssertTrue(topicLink.waitForExistence(timeout: 5))
        topicLink.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", in: initialWorkspace))
        XCTAssertTrue(recordWindow.exists)

        focusWorkspaceWindow(secondWorkspace)
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: secondWorkspace)
        XCTAssertTrue(agentStatement.waitForExistence(timeout: 10))
        XCTAssertFalse(
            recordWindow.descendants(matching: .any)[
                "scholium.researchRecords.empty"
            ].exists,
            "Focusing another Triptych must not retarget the existing Records window."
        )

        let secondRecordButton = researchRecordsControl(in: secondWorkspace)
        XCTAssertTrue(secondRecordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: secondWorkspace)
        let secondRecordWindow = app.windows[
            "scholium-research-records-\(secondTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(secondRecordWindow.waitForExistence(timeout: 8))
        XCTAssertTrue(secondRecordWindow.descendants(matching: .any)[
            "scholium.researchRecords.empty"
        ].waitForExistence(timeout: 10))
        let emptySearchFrame = secondRecordWindow.textFields[
            "scholium.researchRecord.search"
        ].frame
        XCTAssertEqual(
            emptySearchFrame.minY - secondRecordWindow.frame.minY,
            populatedSearchFrame.minY - recordWindow.frame.minY,
            accuracy: 2,
            "An empty result set must not vertically recenter the search and filters."
        )
        XCTAssertEqual(
            emptySearchFrame.height,
            populatedSearchFrame.height,
            accuracy: 1,
            "The compact filter controls must retain their size across content states."
        )

        secondRecordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !secondRecordWindow.exists })

        focusWorkspaceWindow(initialWorkspace)
        XCTAssertTrue(agentStatement.waitForExistence(timeout: 10))
        recordButton.click()
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 5))
        focusAuxiliaryWindow(recordWindow, menuItemTitle: "Research Records")
        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordWindow.exists })
    }

    @MainActor
    func testResearchRecordsViewIndexMirrorsArrowTraversalInRTL() throws {
        app.terminate()
        sessionID = UUID()
        app = configuredApplication(
            sessionID: sessionID,
            initialWorkspaceWidth: Int(QAWorkspaceMetricContract.preferredWidth),
            appearance: .light
        )
        app.launchEnvironment["SCHOLIUM_UI_TEST_LAYOUT_DIRECTION"] = "rtl"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()

        let workspace = app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "scholium-main-")
        ).firstMatch
        openNote("QA Autosave A.md", expectedTitle: "QA Autosave A", in: workspace)
        let recordButton = researchRecordsControl(in: workspace)
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        clickResearchRecordsControl(in: workspace)

        let currentTriptychID = try triptychID(at: triptychDirectory)
        let recordWindow = app.windows[
            "scholium-research-records-\(currentTriptychID.uuidString.lowercased())"
        ]
        XCTAssertTrue(recordWindow.waitForExistence(timeout: 8))
        let recordsView = recordWindow.buttons["Records"].firstMatch
        let recommendationsView = recordWindow.buttons["Reading Leads"].firstMatch
        XCTAssertTrue(recordsView.waitForExistence(timeout: 5))
        XCTAssertTrue(recommendationsView.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            recordsView.frame.minX,
            recommendationsView.frame.minX,
            "The View index must mirror its visual order in a right-to-left interface."
        )

        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        recordsView.click()
        for _ in 0..<24 where !keyboardFocus.evaluate(with: recordsView) {
            app.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(keyboardFocus.evaluate(with: recordsView))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                self.selectionControlIsSelected(recommendationsView)
            },
            "Left Arrow must follow the mirrored visual order in RTL."
        )

        recordWindow.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !recordWindow.exists })
    }

}
