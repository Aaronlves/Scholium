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
            confirmation.staticTexts["QA transient confirmation"].exists
        )
        XCTAssertTrue(
            warning.staticTexts["QA persistent warning"].exists
        )

        XCTAssertEqual(document.frame, documentFrameBeforeFeedback)
        XCTAssertTrue(window.frame.contains(warning.frame))
        XCTAssertTrue(
            document.frame.intersects(confirmation.frame),
            "Transient feedback must overlay Document instead of taking layout space."
        )
        XCTAssertFalse(
            confirmation.buttons["Dismiss"].exists,
            "A bounded transient toast must not add a redundant dismissal control."
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
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 3) { !warning.exists })
        XCTAssertTrue(document.exists)
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









}
