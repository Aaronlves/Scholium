import AppKit
import CryptoKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    private func toolbarDocumentTab(_ title: String, in window: XCUIElement) -> XCUIElement {
        window.toolbars.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "scholium.documentTab.", title)
        ).firstMatch
    }

    @MainActor
    func testToolbarTabsRetainNativeRoutesAtNarrowWidth() throws {
        let english = "QA A Reading Lifecycle and Reliable Toolbar Tabs"
        let chinese = "QA B 阅读与浏览生命周期的完整验证笔记"
        for title in [english, chinese] {
            let note = triptychDirectory.appendingPathComponent("01-analyses/\(title).md")
            try "---\nsummary: Synthetic nonprivate toolbar QA fixture.\n---\n\n# \(title)\n\nVisible passage for \(title).\n"
                .write(to: note, atomically: true, encoding: .utf8)
        }

        func openThreeTabs(appearance: QAAppearance) {
            app.terminate()
            sessionID = UUID()
            app = configuredApplication(
                sessionID: sessionID, initialWorkspaceWidth: 1_380,
                appearance: appearance
            )
            app.launch()
            let main = app.windows.firstMatch
            XCTAssertTrue(main.waitForExistence(timeout: 15))
            for title in [english, chinese] {
                let filename = "\(title).md"
                _ = clickLibraryRow(filename, in: main, rightMouseButton: true)
                let menu = app.menus["scholium.noteRow.\(filename)"]
                XCTAssertTrue(menu.waitForExistence(timeout: 3))
                menu.menuItems["Open in New Tab"].click()
                XCTAssertTrue(waitForDocumentTitle(title, in: main, timeout: 8))
            }
            XCTAssertTrue(toolbarDocumentTab("QA Autosave A", in: main).waitForExistence(timeout: 5))
            XCTAssertTrue(toolbarDocumentTab(english, in: main).waitForExistence(timeout: 5))
            XCTAssertTrue(toolbarDocumentTab(chinese, in: main).waitForExistence(timeout: 5))
            let passage = main.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@ OR value CONTAINS %@",
                    "Visible passage for \(chinese).", "Visible passage for \(chinese)."
                )
            ).firstMatch
            XCTAssertTrue(
                waitUntil(timeout: 8) {
                    passage.exists && passage.isHittable && passage.frame.intersects(main.frame)
                }, "The selected Document body must occupy the visible native page before screenshots.")
        }

        func capture(_ name: String) {
            let main = app.windows.firstMatch
            let windowShot = XCTAttachment(screenshot: main.screenshot())
            windowShot.name = "\(name) — workspace"
            windowShot.lifetime = .keepAlways
            add(windowShot)
            let toolbarShot = XCTAttachment(screenshot: main.toolbars.firstMatch.screenshot())
            toolbarShot.name = "\(name) — toolbar"
            toolbarShot.lifetime = .keepAlways
            add(toolbarShot)
        }

        func assertThreeTabLayout(in window: XCUIElement) {
            let toolbar = window.toolbars.firstMatch
            let tabs = ["QA Autosave A", english, chinese].map { toolbarDocumentTab($0, in: window) }
            XCTAssertTrue(tabs.allSatisfy { $0.exists && $0.frame.width > 0 })
            let widths = tabs.map { $0.frame.width }
            XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 2)

            let strip = toolbar.scrollViews.firstMatch
            let forward = toolbar.buttons["Forward"].firstMatch
            XCTAssertTrue(strip.exists && forward.exists)
            let trailingActions = toolbar.descendants(matching: .any).matching(
                NSPredicate(
                    format: "label BEGINSWITH %@ OR label == %@ OR label CONTAINS[c] %@",
                    "Document Mode,", "Note Actions", "More"
                )
            ).allElementsBoundByIndex
            guard
                let right = trailingActions.filter({ $0.exists && $0.frame.minX > strip.frame.maxX })
                    .map(\.frame.minX).min()
            else {
                XCTFail("A visible trailing Document command must bound the Tab interval.")
                return
            }
            let left = forward.frame.maxX
            let leftGap = strip.frame.minX - left
            let rightGap = right - strip.frame.maxX
            XCTAssertGreaterThanOrEqual(leftGap, 0)
            XCTAssertLessThanOrEqual(leftGap, 20)
            XCTAssertGreaterThanOrEqual(rightGap, 0)
            XCTAssertLessThanOrEqual(rightGap, 20)
            XCTAssertLessThanOrEqual(abs(strip.frame.midX - (left + right) / 2), 12)
        }

        func visibleMenuAction(_ title: String) -> XCUIElement? {
            app.menuItems.matching(NSPredicate(format: "title == %@ OR label == %@", title, title))
                .allElementsBoundByIndex.first { $0.isHittable }
        }

        openThreeTabs(appearance: .light)
        let main = app.windows.firstMatch
        let englishTab = toolbarDocumentTab(english, in: main)
        let chineseTab = toolbarDocumentTab(chinese, in: main)
        assertThreeTabLayout(in: main)
        capture("Light, three tabs with long titles")

        let autosaveTab = toolbarDocumentTab("QA Autosave A", in: main)
        autosaveTab.rightClick()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                visibleMenuAction("Move to Separate Window") != nil && visibleMenuAction("Close Tab") != nil
            })
        XCTAssertFalse(app.menuItems["Icon and Text"].firstMatch.isHittable)
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 3))
        XCTAssertEqual(String(describing: chineseTab.value ?? ""), "1")
        let closeInactive = try XCTUnwrap(visibleMenuAction("Close Tab"))
        closeInactive.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !autosaveTab.exists && englishTab.exists && chineseTab.exists })
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 3))
        _ = clickLibraryRow("QA Autosave A.md", in: main, rightMouseButton: true)
        let reopenMenu = app.menus["scholium.noteRow.QA Autosave A.md"]
        XCTAssertTrue(reopenMenu.waitForExistence(timeout: 3))
        reopenMenu.menuItems["Open in New Tab"].click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 8))
        chineseTab.click()
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 8))
        chineseTab.rightClick()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                visibleMenuAction("Move to Separate Window") != nil && visibleMenuAction("Close Tab") != nil
            })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 3))
        XCTAssertEqual(String(describing: chineseTab.value ?? ""), "1")

        XCUIElement.perform(withKeyModifiers: [.control]) {
            englishTab.click()
        }
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                visibleMenuAction("Move to Separate Window") != nil
                    && visibleMenuAction("Close Tab") != nil
            })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 3))
        XCTAssertEqual(String(describing: chineseTab.value ?? ""), "1")

        chineseTab.hover()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                main.toolbars.firstMatch.buttons.matching(
                    NSPredicate(format: "label == %@", "Close Tab")
                ).allElementsBoundByIndex.contains { $0.isHittable }
            }, "Hover must reveal the native Close Tab button without changing selection.")
        let visibleClose = try XCTUnwrap(
            main.toolbars.firstMatch.buttons.matching(
                NSPredicate(format: "label == %@", "Close Tab")
            ).allElementsBoundByIndex.first { $0.isHittable })
        XCTAssertGreaterThanOrEqual(visibleClose.frame.width, 20)
        XCTAssertGreaterThanOrEqual(visibleClose.frame.height, 20)
        XCTAssertTrue(chineseTab.isHittable && englishTab.isHittable)
        let dropBeforeEnglish = englishTab.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        chineseTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.8, thenDragTo: dropBeforeEnglish)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                chineseTab.exists && englishTab.exists && chineseTab.frame.minX < englishTab.frame.minX
            }, "Dropping on a toolbar tab's leading edge must reorder the window-owned collection.")

        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 5) { !chineseTab.isHittable })
        app.menuBars.menuBarItems["Window"].click()
        XCTAssertTrue(app.menuItems["Document Tabs"].firstMatch.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 5) { chineseTab.isHittable })

        resizeProofWindow(main, toWidth: 720)
        capture("Light, narrow toolbar overflow")
        app.menuBars.menuBarItems["Window"].click()
        let tabMenu = app.menuItems["Document Tabs"].firstMatch
        XCTAssertTrue(tabMenu.waitForExistence(timeout: 3))
        tabMenu.hover()
        XCTAssertTrue(
            app.menuItems[chinese].firstMatch.waitForExistence(timeout: 3),
            "A narrow toolbar must retain the selected Note through the native Window menu.")
        app.typeKey(.escape, modifierFlags: [])

        resizeProofWindow(main, toWidth: 820)
        let tabScrollView = main.toolbars.firstMatch.scrollViews.firstMatch
        XCTAssertTrue(tabScrollView.waitForExistence(timeout: 3), "The medium-narrow toolbar must retain its Tab strip.")
        XCTAssertTrue(chineseTab.isHittable, "The selected Tab must be a visible wheel target inside the strip.")
        XCTAssertTrue(
            [englishTab, autosaveTab].contains {
                $0.frame.minX < tabScrollView.frame.minX - 1
                    || $0.frame.maxX > tabScrollView.frame.maxX + 1
            },
            "The wheel fixture must actually overflow its native Tab viewport."
        )
        app.activate()
        let wheelTarget = chineseTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        wheelTarget.hover()
        let englishX = englishTab.frame.minX
        wheelTarget.scroll(byDeltaX: 120, deltaY: 0)
        var didScroll = waitUntil(timeout: 3) { abs(englishTab.frame.minX - englishX) > 1 }
        if !didScroll {
            wheelTarget.scroll(byDeltaX: -120, deltaY: 0)
            didScroll = waitUntil(timeout: 3) { abs(englishTab.frame.minX - englishX) > 1 }
        }
        XCTAssertTrue(didScroll, "A real horizontal wheel event must move a nonselected Tab within the strip.")
        XCTAssertTrue(waitForDocumentTitle(chinese, in: main, timeout: 3))
        XCTAssertEqual(String(describing: chineseTab.value ?? ""), "1")
        capture("Light, horizontally scrolled Tab strip")

        resizeProofWindow(main, toWidth: 1_100)
        let mediumToolbar = main.toolbars.firstMatch
        let back = mediumToolbar.buttons["Back"].firstMatch
        let forward = mediumToolbar.buttons["Forward"].firstMatch
        let mode = documentModeControl(in: main)
        XCTAssertTrue(back.exists && back.frame.intersects(mediumToolbar.frame))
        XCTAssertTrue(forward.exists && forward.frame.intersects(mediumToolbar.frame))
        XCTAssertTrue(mode.isHittable)
        for title in ["QA Autosave A", english, chinese] {
            let tab = toolbarDocumentTab(title, in: main)
            XCTAssertTrue(tab.isHittable, "Each Document tab must remain reachable beside core commands at medium width.")
            tab.click()
            XCTAssertTrue(waitForDocumentTitle(title, in: main, timeout: 8))
        }
        assertThreeTabLayout(in: main)
        capture("Light, medium toolbar with core commands and three tabs")
        XCTAssertTrue(chineseTab.isHittable)
        let originalMainID = main.identifier
        let outside = main.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 60, dy: 0))
        chineseTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.8, thenDragTo: outside)
        XCTAssertTrue(
            waitUntil(timeout: 10) { self.app.windows.count == 2 },
            "Dragging a toolbar tab outside the window must transfer its session.")
        let originalMain = app.windows[originalMainID]
        for title in ["QA Autosave A", english] {
            let tab = toolbarDocumentTab(title, in: originalMain)
            XCTAssertTrue(
                tab.exists && tab.frame.width > 0,
                "The source window must keep its remaining Toolbar tabs after detachment.")
        }

        openThreeTabs(appearance: .dark)
        assertThreeTabLayout(in: app.windows.firstMatch)
        capture("Dark, three tabs with long titles")
        resizeProofWindow(app.windows.firstMatch, toWidth: 720)
        capture("Dark, narrow toolbar overflow")
    }

    @MainActor
    func testLivePreviewUsesDocumentModeMenuForSourceTransition() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        selectDocumentMode("Edit")

        let editor = app.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty)

        app.typeKey("e", modifierFlags: [.command, .shift])
        XCTAssertEqual(documentModeState(mode), "Edit", "Source must be entered through the document-mode menu")

        selectDocumentMode("Source")
        XCTAssertTrue(app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))
        XCTAssertEqual(documentModeState(mode), "Source")
    }

    @MainActor
    func testNewWindowCreatesIndependentDocumentSurface() throws {
        app.typeKey("n", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 8) { self.app.windows.count >= 2 })
        closeFrontmostWindow()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.windows.count == 1 })
    }

    @MainActor
    func testDocumentTabTransfersThroughSeparateWindowWithSearchAndFind() throws {
        let mainID = app.windows.firstMatch.identifier
        let main = app.windows[mainID]
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalSource = try self.source(at: noteURL)

        // Menu routes remain usable when Focus Layout hides every toolbar
        // item. Notifications stays transient and restores the editor's focus.
        selectDocumentMode("Edit", in: main)
        let mainEditor = main.descendants(matching: .any)["Markdown editor, Edit mode"].firstMatch
        XCTAssertTrue(mainEditor.waitForExistence(timeout: 8))
        mainEditor.click()
        let keyboardFocus = NSPredicate(format: "hasKeyboardFocus == true")
        XCTAssertTrue(waitUntil(timeout: 5) { keyboardFocus.evaluate(with: mainEditor) })
        let originalAccessibleEditor = try XCTUnwrap(mainEditor.value as? String)
        let originalBytes = try Data(contentsOf: noteURL)
        app.typeKey("l", modifierFlags: [.control, .command])
        XCTAssertTrue(waitUntil(timeout: 5) { !self.documentModeControl(in: main).isHittable })
        XCTAssertTrue(keyboardFocus.evaluate(with: mainEditor))
        app.menuBars.menuBarItems["Window"].click()
        let notificationsCommand = app.menuItems["Notifications"].firstMatch
        XCTAssertTrue(notificationsCommand.waitForExistence(timeout: 3) && notificationsCommand.isEnabled)
        notificationsCommand.click()
        let notificationPopover = main.popovers.firstMatch
        // The AppKit root NSView is not an accessibility element. Observe its
        // actual native search control, scoped to this window's popover.
        let notificationSearch = notificationPopover.searchFields["scholium.attentionSearch"].firstMatch
        XCTAssertTrue(notificationSearch.waitForExistence(timeout: 8), "Notifications must open without a visible toolbar anchor.")
        XCTAssertFalse(documentModeControl(in: main).isHittable)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                !notificationPopover.exists && !notificationSearch.exists
                    && keyboardFocus.evaluate(with: mainEditor)
            },
            "Dismissing Notifications must restore the originating editor's focus."
        )
        XCTAssertFalse(documentModeControl(in: main).isHittable, "Notifications must preserve Focus Layout.")
        XCTAssertEqual(mainEditor.value as? String, originalAccessibleEditor)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
        for (menu, title) in [("Edit", "Copy Note Link"), ("File", "Reveal Note in Finder")] {
            app.menuBars.menuBarItems[menu].click()
            let command = app.menuItems[title].firstMatch
            XCTAssertTrue(command.waitForExistence(timeout: 3) && command.isEnabled, "\(title) must address the current Note in Focus Layout.")
            app.typeKey(.escape, modifierFlags: [])
        }
        // Whole-Note material handoff opens Chat but sends no message. Finder
        // availability is checked above without opening another application.
        app.menuBars.menuBarItems["Research"].click()
        let addNote = app.menuItems["Add Note to Chat"].firstMatch
        XCTAssertTrue(addNote.waitForExistence(timeout: 3) && addNote.isEnabled)
        addNote.click()
        let noteMaterial = main.buttons["Open Note: QA Autosave A"].firstMatch
        XCTAssertTrue(noteMaterial.waitForExistence(timeout: 10))
        XCTAssertTrue((noteMaterial.value as? String)?.contains("Whole Note") == true)
        XCTAssertTrue(documentModeControl(in: main).isHittable, "Explicitly opening Chat must exit windowed Focus Layout.")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 5))
        XCTAssertEqual(try self.source(at: noteURL), originalSource)
        sidebarModeControl("Library", in: main).click()
        XCTAssertTrue(main.descendants(matching: .any)["scholium.librarySurface"].firstMatch.waitForExistence(timeout: 5))

        _ = clickLibraryRow("QA Autosave B.md", in: main, rightMouseButton: true)
        let noteMenu = app.menus["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(noteMenu.waitForExistence(timeout: 3))
        noteMenu.menuItems["Open in New Tab"].click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 8))
        let firstTab = toolbarDocumentTab("QA Autosave A", in: main)
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        let normalWindow = XCTAttachment(screenshot: main.screenshot())
        normalWindow.name = "Document tabs in native toolbar"
        normalWindow.lifetime = .keepAlways
        add(normalWindow)
        let normalToolbar = XCTAttachment(screenshot: main.toolbars.firstMatch.screenshot())
        normalToolbar.name = "Native toolbar with two Document tabs"
        normalToolbar.lifetime = .keepAlways
        add(normalToolbar)
        XCTAssertTrue(firstTab.waitForExistence(timeout: 5))
        firstTab.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 8))

        let token = " WINDOW-TRANSFER-\(UUID().uuidString)"
        try enterLivePreviewAndAppend(token, in: main)
        focusWorkspaceWindow(main)
        app.typeKey("f", modifierFlags: [.command])
        let mainFind = main.descendants(matching: .any)["scholium.documentFind.query"]
        XCTAssertTrue(mainFind.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !mainFind.exists })
        app.menuBars.menuBarItems["Window"].click()
        let moveOut = app.menuItems["Move to Separate Window"].firstMatch
        XCTAssertTrue(moveOut.waitForExistence(timeout: 3) && moveOut.isEnabled)
        moveOut.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 12) { self.app.windows.count == 2 })
        guard
            let detachedID = app.windows.allElementsBoundByIndex.first(where: {
                $0.identifier != mainID && $0.title == "QA Autosave A"
            })?.identifier
        else {
            XCTFail("The transferred Note must appear in its own Document window.")
            return
        }
        let detached = app.windows[detachedID]
        XCTAssertFalse(detached.descendants(matching: .any)["scholium.librarySurface"].exists)
        XCTAssertFalse(detached.descendants(matching: .any)["scholium.researchInspector"].exists)
        XCTAssertFalse(
            detached.toolbars.firstMatch.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "scholium.documentTab.")
            ).firstMatch.exists)
        let detachedEditor = detached.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(
            waitUntil(timeout: 10) { (detachedEditor.value as? String)?.contains(token) == true },
            "The separate window must receive the live source session."
        )

        focusWorkspaceWindow(detached)
        XCTAssertTrue(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: detachedEditor))
        // Commands whose presenter belongs to a main Workspace must not remain
        // enabled in a separate Document window. Document commands still work.
        app.menuBars.menuBarItems["View"].click()
        let sidebarCommand = app.menuItems.matching(
            NSPredicate(
                format: "title IN %@ OR label IN %@",
                ["Show Sidebar", "Hide Sidebar"], ["Show Sidebar", "Hide Sidebar"]
            )
        ).firstMatch
        XCTAssertTrue(sidebarCommand.waitForExistence(timeout: 3))
        XCTAssertFalse(sidebarCommand.isEnabled)
        for title in ["Library", "Chat"] {
            let command = app.menuItems[title].firstMatch
            XCTAssertTrue(command.waitForExistence(timeout: 3))
            XCTAssertFalse(command.isEnabled, "\(title) must not silently target another window.")
        }
        let modeMenu = app.menuItems["Document Mode"].firstMatch
        XCTAssertTrue(modeMenu.waitForExistence(timeout: 3) && modeMenu.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["Window"].click()
        let unavailableNotifications = app.menuItems["Notifications"].firstMatch
        XCTAssertTrue(unavailableNotifications.waitForExistence(timeout: 3))
        XCTAssertFalse(unavailableNotifications.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        let detachedMode = documentModeControl(in: detached)
        XCTAssertTrue(detachedMode.waitForExistence(timeout: 5) && detachedMode.isEnabled)
        detachedMode.click()
        XCTAssertTrue(waitUntil(timeout: 8) { self.documentModeState(detachedMode) == "Review" })
        detachedMode.click()
        XCTAssertTrue(
            waitUntil(timeout: 8) {
                self.documentModeState(detachedMode) == "Edit"
                    && (detachedEditor.value as? String)?.contains(token) == true
            }, "Separate-window mode controls must retain the live source."
        )
        let noteActions = detached.toolbars.firstMatch.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Note Actions")
        ).firstMatch
        XCTAssertTrue(noteActions.waitForExistence(timeout: 5) && noteActions.isEnabled)
        noteActions.click()
        let copyNoteLink = app.menuItems["Copy Note Link"].firstMatch
        XCTAssertTrue(copyNoteLink.waitForExistence(timeout: 3) && copyNoteLink.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        detachedEditor.click()
        detachedEditor.typeKey("f", modifierFlags: [.command])
        let find = detached.descendants(matching: .any)["scholium.documentFind.query"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        typeCommittedText(token.trimmingCharacters(in: .whitespaces), into: find, in: app)
        let matches = detached.staticTexts["scholium.documentFind.matches"]
        XCTAssertTrue(waitUntil(timeout: 8) { (matches.value as? String) == "Match 1 of 1" })
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !find.exists })

        let sourceBeforeFormat = try XCTUnwrap(detachedEditor.value as? String)
        detachedEditor.click()
        detachedEditor.typeKey(.end, modifierFlags: .command)
        detachedEditor.typeKey(.leftArrow, modifierFlags: [.option, .shift])
        app.menuBars.menuBarItems["Format"].click()
        let bold = app.menuItems["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 3) && bold.isEnabled)
        bold.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (detachedEditor.value as? String) != sourceBeforeFormat
            })
        detachedEditor.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                (detachedEditor.value as? String) == sourceBeforeFormat
            })

        app.menuBars.menuBarItems["View"].click()
        let advancedAction = app.menuItems["Advanced Search…"].firstMatch
        XCTAssertTrue(advancedAction.waitForExistence(timeout: 3) && advancedAction.isEnabled)
        advancedAction.click()
        let advanced = app.windows["scholium.advancedSearchWindow"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 8))
        XCTAssertTrue(advanced.searchFields["scholium.searchField"].waitForExistence(timeout: 5))
        // The auxiliary window is still foreground here; native close returns
        // focus to the detached Document that owns this Search session.
        advanced.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !advanced.exists })
        XCTAssertTrue(detached.exists)

        app.menuBars.menuBarItems["Window"].click()
        let moveBack = app.menuItems["Move to Main Window"].firstMatch
        XCTAssertTrue(moveBack.waitForExistence(timeout: 3) && moveBack.isEnabled)
        moveBack.click()
        XCTAssertTrue(waitUntil(timeout: 12) { !detached.exists && self.app.windows.count == 1 })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", in: main, timeout: 10))
        let returnedEditor = main.descendants(matching: .any)["Markdown editor, Edit mode"]
        XCTAssertTrue(
            waitUntil(timeout: 8) { (returnedEditor.value as? String)?.contains(token) == true },
            "Moving back must retain the same editable source and mode."
        )
        XCTAssertTrue(toolbarDocumentTab("QA Autosave A", in: main).waitForExistence(timeout: 5))
        XCTAssertEqual(
            main.toolbars.firstMatch.descendants(matching: .any).matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@",
                    "scholium.documentTab.", "QA Autosave B"
                )
            ).count, 1)

        returnedEditor.typeKey("s", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                (try? self.source(at: noteURL).contains(token)) == true
            })
        XCTAssertEqual(try self.source(at: noteURL).replacingOccurrences(of: token, with: ""), originalSource)
        app.menuBars.menuBarItems["File"].click()
        let closeTab = app.menuItems["Close Tab"].firstMatch
        XCTAssertTrue(closeTab.waitForExistence(timeout: 3))
        closeTab.click()
        XCTAssertTrue(waitForDocumentTitle("QA Autosave B", in: main, timeout: 8))
    }

}
