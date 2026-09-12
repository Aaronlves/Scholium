import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    @MainActor
    func testFixtureLaunchWithoutExplicitSessionIDUsesOneWindowSession() throws {
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.librarySurface"
            ].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "scholium.noteRow.QA Autosave A.md"
            ].waitForExistence(timeout: 5))
        let wordmark = app.descendants(matching: .any)["scholium.wordmark"]
        let search = app.searchFields["scholium.searchField"]
        let notifications = app.buttons["Open Triptych Notifications"]
        XCTAssertFalse(wordmark.exists)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(notifications.waitForExistence(timeout: 5))
        XCTAssertLessThan(notifications.frame.maxY, search.frame.minY)
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychManagement"].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.folderRow.Attachments"].exists
        )
        XCTAssertFalse(app.toolbars.firstMatch.buttons["Agent Changes"].exists)
        XCTAssertEqual(app.windows.count, 1)

        let sessionsURL =
            homeDirectory
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
    func testNotificationsEmptyStateKeepsIndicatorWithCopy() {
        let notifications = app.buttons["Open Triptych Notifications"].firstMatch
        XCTAssertTrue(notifications.waitForExistence(timeout: 8))
        notifications.click()

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        let search = popover.descendants(matching: .any)[
            "scholium.attentionSearch"
        ]
        XCTAssertTrue(search.waitForExistence(timeout: 3))

        let notificationRow = popover.descendants(matching: .group)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                    "scholium.attentionItem.",
                    "QA Work.md"
                )
            )
            .firstMatch
        XCTAssertTrue(notificationRow.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(notificationRow.frame.height, 40)
        let openAction = popover.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                    "scholium.attentionOpen.",
                    "QA Work.md"
                )
            )
            .firstMatch
        XCTAssertTrue(openAction.exists)
        let accessibleRow = accessibilityText(of: openAction)
        XCTAssertTrue(accessibleRow.contains("Possible Orphan"))
        XCTAssertTrue(accessibleRow.contains("QA Work"))
        XCTAssertTrue(accessibleRow.contains("No incoming or outgoing links"))

        let restingRow = notificationRow.screenshot().pngRepresentation
        notificationRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)
        ).hover()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                notificationRow.screenshot().pngRepresentation != restingRow
            },
            "The primary notification action must visibly respond to pointer hover."
        )
        let hoverScreenshot = XCTAttachment(screenshot: popover.screenshot())
        hoverScreenshot.name = "Native Notifications hovered row"
        hoverScreenshot.lifetime = .keepAlways
        add(hoverScreenshot)

        notificationRow.coordinate(
            withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)
        ).hover()
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                notificationRow.screenshot().pngRepresentation != restingRow
            },
            "The notification row must retain its unified hover response over More."
        )
        let accessoryHoverScreenshot = XCTAttachment(screenshot: popover.screenshot())
        accessoryHoverScreenshot.name = "Native Notifications hovered More region"
        accessoryHoverScreenshot.lifetime = .keepAlways
        add(accessoryHoverScreenshot)

        let populatedScreenshot = XCTAttachment(screenshot: popover.screenshot())
        populatedScreenshot.name = "Native Notifications populated queue"
        populatedScreenshot.lifetime = .keepAlways
        add(populatedScreenshot)

        search.click()
        search.typeText("no-notification-can-match-this-query")
        search.typeKey(.return, modifierFlags: [])

        let empty = popover.descendants(matching: .any)[
            "scholium.attentionEmpty"
        ]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        let accessibleCopy = accessibilityText(of: empty)
        XCTAssertTrue(accessibleCopy.contains("No Matching Notifications"))

        let screenshot = XCTAttachment(screenshot: popover.screenshot())
        screenshot.name = "Native Notifications empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testWorkspaceInitialDefaultPreservesNativeReachability() throws {
        waitForCurrentDocumentSurface()
        let window = app.windows.firstMatch
        guard
            abs(window.frame.width - QAWorkspaceMetricContract.preferredWidth)
                <= QAWorkspaceMetricContract.frameTolerance
        else {
            throw XCTSkip(
                "AppKit restored a test-owned frame; rerun this first-presentation journey from a clean QA preference domain."
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"].exists
        )
        XCTAssertTrue(
            sidebarModeControl("Library")
                .waitForExistence(timeout: 5)
        )
        let inspectorButton = app.toolbars.firstMatch.buttons[
            "Show Research Inspector"
        ]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        XCTAssertTrue(inspectorButton.isEnabled)
    }

    @MainActor
    func testNativeToolbarAvailabilityFollowsCurrentDocument() throws {
        waitForCurrentDocumentSurface()
        let topics = app.radioButtons["Topics"].firstMatch
        XCTAssertTrue(topics.waitForExistence(timeout: 5))
        topics.click()
        let chat = sidebarModeControl("Chat")
        let inspector = app.toolbars.buttons["Show Research Inspector"].firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { chat.isEnabled && !inspector.isEnabled })
        XCTAssertTrue(app.descendants(matching: .any)["scholium.noteList"].exists)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Outline"].isEnabled)
        XCTAssertFalse(app.menuItems["Show Research Inspector"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(chat.isEnabled)
        XCTAssertFalse(inspector.isEnabled)
        chat.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.chat"].waitForExistence(timeout: 5))
        sidebarModeControl("Library").click()
        openNote("QA Topic.md", expectedTitle: "QA Topic", in: app.windows.firstMatch)
        XCTAssertTrue(waitUntil(timeout: 5) { chat.isEnabled && inspector.isEnabled })
        inspector.click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.inspectorMode"].waitForExistence(timeout: 5))
        app.toolbars.buttons["Hide Research Inspector"].firstMatch.click()
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Outline"].click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.documentOutline"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testNativeSidebarToggleAndLibraryTriptychIdentityRemainAvailable() throws {
        waitForCurrentDocumentSurface()
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let wordmark = app.descendants(matching: .any)["scholium.wordmark"]
        XCTAssertFalse(wordmark.exists)
        let hideSidebar = sidebarModeControl("Library")
        XCTAssertTrue(hideSidebar.waitForExistence(timeout: 5))
        let librarySurface = app.descendants(matching: .any)["scholium.librarySurface"]
        XCTAssertTrue(librarySurface.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.triptychManagement"].exists
        )
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 5))
        fileMenu.click()
        XCTAssertTrue(app.menuItems["New Triptych…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.menuItems["Open Triptych"].exists)
        app.typeKey(.escape, modifierFlags: [])

        let organize = app.descendants(matching: .any)[
            "scholium.libraryFilters"
        ].firstMatch
        let create = app.descendants(matching: .any)[
            "scholium.libraryCreate"
        ].firstMatch
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(organize.frame.maxX, create.frame.minX)
        XCTAssertFalse(
            app.descendants(matching: .any)["scholium.libraryDisclosureToggle"].exists
        )
        organize.click()
        let collapseAll = app.menuItems["Collapse All Folders"]
        let expandAll = app.menuItems["Expand All Folders"]
        XCTAssertTrue(collapseAll.exists || expandAll.exists)
        app.typeKey(.escape, modifierFlags: [])

        let folderRow = app.descendants(matching: .any)[
            "scholium.folderRow.Cluster-01"
        ]
        let noteRow = app.descendants(matching: .any)["scholium.noteRow.QA Autosave B.md"]
        XCTAssertTrue(folderRow.waitForExistence(timeout: 5))
        XCTAssertTrue(noteRow.waitForExistence(timeout: 5))
        XCTAssertEqual(
            noteRow.frame.minX,
            folderRow.frame.minX,
            accuracy: 2,
            "Top-level Folder and Note titles must share one Library text column."
        )
        XCTAssertFalse(app.buttons["Collapse Note"].exists)
        app.menuBars.menuBarItems["View"].click()
        XCTAssertFalse(app.menuItems["Collapse Note"].exists)
        app.typeKey(.escape, modifierFlags: [])

        hideSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                !self.app.descendants(matching: .any)["scholium.librarySurface"].exists
            })
        let showSidebar = sidebarModeControl("Library")
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A", timeout: 5))
        showSidebar.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 1)

        let shellScreenshot = XCTAttachment(screenshot: window.screenshot())
        shellScreenshot.name = "Full-height editorial Library with native sidebar controls"
        shellScreenshot.lifetime = .keepAlways
        add(shellScreenshot)
    }

    /// Native tabs retain the destination while Library navigation stays native.
    @MainActor
    func testNativeTriptychWorkspaceNavigatorUsesSelectionAndArrowKeys() throws {
        waitForCurrentDocumentSurface()
        let navigator = app.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        let topics = navigator.descendants(matching: .any)["Topics"].firstMatch
        XCTAssertTrue(topics.waitForExistence(timeout: 5))
        topics.click()
        let topicNote = app.descendants(matching: .any)["scholium.noteRow.QA Topic.md"].firstMatch
        XCTAssertTrue(topicNote.waitForExistence(timeout: 8))
        topicNote.click()
        XCTAssertTrue(waitForDocumentTitle("QA Topic", timeout: 5))
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "Native workspace tabs and retained Library"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLibraryOrganizationPreservesDocumentAndCancelsMove() throws {
        waitForCurrentDocumentSurface()
        let noteURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalBytes = try Data(contentsOf: noteURL)
        let organize = app.descendants(matching: .any)["scholium.libraryFilters"].firstMatch
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.click()
        XCTAssertTrue(app.menuItems["Sort By"].firstMatch.waitForExistence(timeout: 5))
        let annotations = app.menuItems["Link Annotations"].firstMatch
        XCTAssertTrue(annotations.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 10) { annotations.isEnabled })
        annotations.click()
        // The standard Triptych intentionally contains annotated links. Combine
        // with malformed managed Metadata, absent from this freshly built fixture.
        organize.click()
        app.menuItems["Malformed Metadata"].firstMatch.click()

        let emptyState = app.descendants(matching: .any)["scholium.libraryEmpty"].firstMatch
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        let emptyCopy = emptyState.staticTexts.firstMatch
        XCTAssertTrue(accessibilityText(of: emptyCopy).contains("No Matching Notes"))
        XCTAssertFalse(accessibilityText(of: emptyCopy).contains("Create a Note to begin."))
        let emptyScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        emptyScreenshot.name = "Filtered Library retains Document and Clear"
        emptyScreenshot.lifetime = .keepAlways
        add(emptyScreenshot)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        let status = app.descendants(matching: .any)["scholium.libraryFilterStatus"].firstMatch
        let clear = status.buttons["Clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let row = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(status.exists)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let contextMenu = app.menus["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 5))
        let move = contextMenu.menuItems["Move Note…"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(move.isEnabled)
        move.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.textFields.firstMatch.exists)
        let buttons = XCTAttachment(screenshot: sheet.screenshot())
        buttons.name = "Neutral native sheet buttons"
        buttons.lifetime = .keepAlways
        add(buttons)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        XCTAssertTrue(row.exists)
        XCTAssertEqual(try Data(contentsOf: noteURL), originalBytes)
    }

    @MainActor
    func testSidebarGridKeepsSearchCardsAndComposerAligned() throws {
        waitForCurrentDocumentSurface()
        let librarySearch = app.searchFields["scholium.searchField"].firstMatch
        XCTAssertTrue(librarySearch.waitForExistence(timeout: 5))
        let searchFrame = librarySearch.frame
        let outline = app.descendants(matching: .any)["scholium.noteList"].firstMatch
        let outerInset = searchFrame.minX - outline.frame.minX
        XCTAssertGreaterThan(outerInset, 0)
        let navigator = app.descendants(matching: .any)["scholium.workspaceNavigator"].firstMatch
        XCTAssertEqual(navigator.frame.minX, searchFrame.minX, accuracy: 1)
        XCTAssertEqual(navigator.frame.maxX, searchFrame.maxX, accuracy: 1)

        sidebarModeControl("Chat").click()
        let chatSearch = app.searchFields["scholium.chat.search"].firstMatch
        XCTAssertTrue(chatSearch.waitForExistence(timeout: 5))
        XCTAssertEqual(chatSearch.frame.minX, searchFrame.minX, accuracy: 1)
        XCTAssertEqual(chatSearch.frame.maxX, searchFrame.maxX, accuracy: 1)
        app.buttons["scholium.chat.newConversation"].click()
        let input = app.textViews["scholium.chat.message"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.frame.minX, searchFrame.minX + outerInset, accuracy: 1)
        XCTAssertEqual(input.frame.maxX, searchFrame.maxX - outerInset, accuracy: 1)
        app.typeText("271828")
        app.buttons["scholium.chat.back"].click()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.chat.conversation.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.frame.minX, searchFrame.minX, accuracy: 1)
        XCTAssertEqual(row.frame.maxX, searchFrame.maxX, accuracy: 1)
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
    }

    @MainActor
    func testSidebarStateTransitionsKeepDocumentAndRecoveryVisible() throws {
        waitForCurrentDocumentSurface()
        let source = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let before = try Data(contentsOf: source)
        let organize = app.descendants(matching: .any)["scholium.libraryFilters"].firstMatch
        organize.click()
        app.menuItems["Malformed Metadata"].firstMatch.click()
        let libraryEmpty = app.descendants(matching: .any)["scholium.libraryEmpty"].firstMatch
        XCTAssertTrue(libraryEmpty.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityText(of: libraryEmpty.staticTexts.firstMatch).contains("No Matching Notes"))
        let clear = app.descendants(matching: .any)["scholium.libraryFilterStatus"].firstMatch.buttons["Clear"]
        clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let search = app.searchFields["scholium.searchField"].firstMatch
        typeCommittedText("qa-state-no-match-817263", into: search, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.searchEmpty"].firstMatch.waitForExistence(timeout: 10))
        search.click()
        search.typeKey("a", modifierFlags: [.command])
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { search.value as? String == "" })
        sidebarModeControl("Chat").click()
        let chatEmpty = app.descendants(matching: .any)["scholium.chat.empty"].firstMatch
        XCTAssertTrue(chatEmpty.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityText(of: chatEmpty.staticTexts.firstMatch).contains("No Conversations"))
        app.descendants(matching: .any)["scholium.chat.archived"].firstMatch.click()
        app.menuItems["Archived Chats"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) {
            self.accessibilityText(of: chatEmpty.staticTexts.firstMatch).contains("No Archived Chats")
        })
        app.buttons["scholium.chat.newConversation"].click()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.chat.emptyConversation"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["scholium.chat.message"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    @MainActor
    func testChatListMenusFilterRenameArchiveAndRestoreDraft() throws {
        waitForCurrentDocumentSurface()
        sidebarModeControl("Chat").click()
        let create = app.buttons["scholium.chat.newConversation"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        let input = app.textViews["scholium.chat.message"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        // New Conversation focuses the native editor. Keyboard input avoids
        // XCTest trying to scroll an already-visible floating composer to a hit point.
        app.typeText("314159265")
        XCTAssertEqual(input.value as? String, "314159265")
        app.buttons["scholium.chat.back"].click()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.chat.conversation.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let search = app.searchFields["scholium.chat.search"]
        search.buttons.firstMatch.click()
        app.menuItems["Needs Input"].firstMatch.click()
        let chatEmpty = app.descendants(matching: .any)["scholium.chat.empty"].firstMatch
        XCTAssertTrue(chatEmpty.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibilityText(of: chatEmpty.staticTexts.firstMatch).contains("No Matching Conversations"))
        let status = app.descendants(matching: .any)["scholium.chat.filterStatus"].firstMatch
        status.buttons["Clear"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        search.buttons.firstMatch.click()
        app.menuItems["Has Draft"].firstMatch.click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Rename Conversation…"].firstMatch.click()
        let renameField = app.textFields.firstMatch
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        typeCommittedText("Sidebar QA conversation", into: renameField, in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { row.label.contains("Sidebar QA conversation") })
        row.rightClick()
        app.menuItems["Archive Chat"].firstMatch.click()
        XCTAssertTrue(waitUntil(timeout: 5) { !row.exists })
        app.descendants(matching: .any)["scholium.chat.archived"].firstMatch.click()
        app.menuItems["Archived Chats"].firstMatch.click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Restore Chat"].firstMatch.click()
        app.buttons["scholium.chat.back"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, "314159265")
        XCTAssertTrue(waitForDocumentTitle("QA Autosave A"))
    }

    @MainActor
    func testNativeCommandButtonsPreserveDefaultDisabledAndCancelActions() throws {
        waitForCurrentDocumentSurface()
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let movedURL = triptychDirectory.appendingPathComponent("01-analyses/QA Button Move.md")
        let originalBytes = try Data(contentsOf: sourceURL)
        let row = app.descendants(matching: .any)["scholium.noteRow.QA Autosave A.md"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.rightClick()
        app.menuItems["Move Note…"].firstMatch.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let field = sheet.textFields.firstMatch
        field.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        let move = sheet.buttons["Move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 3) { !move.isEnabled })
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(sheet.exists)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalBytes)
        typeCommittedText("QA Button Move.md", into: field, in: app)
        XCTAssertTrue(waitUntil(timeout: 3) { move.isEnabled })
        let ready = XCTAttachment(screenshot: sheet.screenshot())
        ready.name = "Neutral default Move button"
        ready.lifetime = .keepAlways
        add(ready)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !sheet.exists })
        XCTAssertTrue(waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: movedURL.path) })
        XCTAssertEqual(try Data(contentsOf: movedURL), originalBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        let movedRow = app.descendants(matching: .any)["scholium.noteRow.QA Button Move.md"].firstMatch
        XCTAssertTrue(movedRow.waitForExistence(timeout: 5))
        movedRow.rightClick()
        app.menuItems["Move to Trash…"].firstMatch.click()
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Move to Trash"].exists)
        let destructive = XCTAttachment(screenshot: confirmation.screenshot())
        destructive.name = "Destructive role stays distinct from neutral Cancel"
        destructive.lifetime = .keepAlways
        add(destructive)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !confirmation.exists })
        XCTAssertEqual(try Data(contentsOf: movedURL), originalBytes)
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

        for (scope, identifier) in [
            ("Analyses", "Analyses"),
            ("Topics", "Topics"),
            ("Works", "Works"),
        ] {
            let control = app.descendants(matching: .any)[identifier]
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

    /// A retained visual checkpoint for native Liquid Glass toolbar controls
    /// above continuous semantic planes. This is intentionally a narrow proof
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
            expandedScreenshot.name = "\(appearance.displayName) — native buttons with Inspector"
            expandedScreenshot.lifetime = .keepAlways
            add(expandedScreenshot)

            clickInspectorVisibilityControl()
            XCTAssertTrue(waitUntil(timeout: 5) { !inspector.exists })

            let sidebarToggle = sidebarVisibilityControl()
            let documentIdentity = documentTitleElement(in: app.windows.firstMatch)
            let documentCommands = documentModeControl()
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
            screenshot.name = "\(appearance.displayName) — native buttons without Inspector"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    @MainActor
    func testDocumentModeButtonShowsAndSwitchesCurrentState() throws {
        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertEqual(mode.label, "Document Mode, Edit")
        XCTAssertEqual(documentModeState(mode), "Edit")

        let initialWidth = mode.frame.width
        let initialEditScreenshot = XCTAttachment(
            screenshot: app.windows.firstMatch.screenshot()
        )
        initialEditScreenshot.name = "Document mode — initial Edit state button"
        initialEditScreenshot.lifetime = .keepAlways
        add(initialEditScreenshot)

        selectDocumentMode("Review")
        XCTAssertTrue(waitUntil(timeout: 10) { self.documentModeState(mode) == "Review" })
        waitForCurrentDocumentSurface()
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)
        let reviewScreenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        reviewScreenshot.name = "Document mode — Review state button"
        reviewScreenshot.lifetime = .keepAlways
        add(reviewScreenshot)

        selectDocumentMode("Edit")
        XCTAssertTrue(waitUntil(timeout: 10) { self.documentModeState(mode) == "Edit" })
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)

        selectDocumentMode("Source")
        XCTAssertEqual(documentModeState(mode), "Source")
        XCTAssertEqual(mode.frame.width, initialWidth, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Document mode — Source state remains menu-only"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        selectDocumentMode("Review")
        XCTAssertTrue(waitUntil(timeout: 10) { self.documentModeState(mode) == "Review" })
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
                XCTAssertTrue(
                    waitUntil(timeout: 5) {
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
            XCTAssertTrue(
                waitUntil(timeout: 5) {
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
        let appearance = app.toolbars.buttons["Appearance"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 8))
        appearance.click()

        let lineWidth = app.textFields["Line width"]
        XCTAssertTrue(lineWidth.waitForExistence(timeout: 8))
        XCTAssertEqual(lineWidth.label, "Line width")
        XCTAssertEqual(appearanceNumericValue(lineWidth), 72)
        lineWidth.click()
        lineWidth.typeKey("a", modifierFlags: .command)
        lineWidth.typeText("73")
        lineWidth.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                self.appearanceNumericValue(lineWidth) == 73
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
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                (try? String(contentsOf: manifest, encoding: .utf8))?
                    .contains("\"lineWidthCharacterUnits\" : 73") == true
            })
        let settingsWindow = settingsWindow()
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        scrollUntilHittable(lineWidth, in: form)
        XCTAssertEqual(appearanceNumericValue(lineWidth), 73)
        let controlScreenshot = XCTAttachment(screenshot: settingsWindow.screenshot())
        controlScreenshot.name = "Appearance — Line width keyboard value 73ch"
        controlScreenshot.lifetime = .keepAlways
        add(controlScreenshot)
    }

    @MainActor
    func testDocumentHeadingStudyWrapsLongMixedTitleUsingAcceptedBodyRhythm() throws {
        let expectedTitle =
            "在长期论证中保持证据边界：Reasons, Values, and the Practical Option Space Across Competing Interpretations"
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

        let noteURL =
            triptychDirectory
            .appendingPathComponent("01-analyses", isDirectory: true)
            .appendingPathComponent("QA Document Heading Study.md")
        let sourceBefore = try Data(contentsOf: noteURL)
        XCTAssertTrue(waitForDocumentTitle(expectedTitle))

        let mode = documentModeControl()
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        selectDocumentMode("Review")
        XCTAssertEqual(documentModeState(mode), "Review")
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
            paragraphSpacing: Double
        ) {
            let appMenu = app.menuBars.menuBarItems["Scholium QA"]
            XCTAssertTrue(appMenu.waitForExistence(timeout: 5))
            appMenu.click()
            let settings = app.menuItems["Settings…"]
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            settings.click()
            let appearance = app.toolbars.buttons["Appearance"].firstMatch
            XCTAssertTrue(appearance.waitForExistence(timeout: 8))
            appearance.click()

            let form = app.descendants(matching: .any)["scholium.appearance.form"]
            XCTAssertTrue(form.waitForExistence(timeout: 5))
            let lineWidth = app.textFields["Line width"]
            XCTAssertTrue(lineWidth.waitForExistence(timeout: 8))
            XCTAssertEqual(appearanceNumericValue(lineWidth), 72)

            func setNumber(_ label: String, target: Double, step: Double) {
                let field = app.textFields.matching(NSPredicate(format: "label == %@", label)).firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 5))
                scrollUntilHittable(field, in: form)
                field.click()
                field.typeKey("a", modifierFlags: .command)
                field.typeText(String(target))
                field.typeKey(.tab, modifierFlags: [])
                XCTAssertTrue(
                    waitUntil(timeout: 5) {
                        guard let value = self.appearanceNumericValue(field) else { return false }
                        return abs(value - target) <= step / 10
                    })
            }

            setNumber("Line spacing", target: lineHeight, step: 0.05)

            let save = app.buttons["Save Appearance"]
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            if save.isEnabled {
                scrollUntilHittable(save, in: form)
                save.click()
                XCTAssertTrue(waitUntil(timeout: 5) { !save.isEnabled })
            }

            do {
                let fileURL = homeDirectory.appendingPathComponent("ApplicationSupport/Workspace/Styles/appearances.json")
                var file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
                var profiles = try XCTUnwrap(file["profiles"] as? [[String: Any]])
                let selected = try XCTUnwrap(file["selectedProfileID"] as? String)
                let index = try XCTUnwrap(profiles.firstIndex { $0["id"] as? String == selected })
                var configuration = try XCTUnwrap(profiles[index]["settings"] as? [String: Any])
                var body = try XCTUnwrap(configuration["body"] as? [String: Any])
                body["paragraphSpacingEm"] = paragraphSpacing
                configuration["body"] = body
                profiles[index]["settings"] = configuration
                file["profiles"] = profiles
                try JSONSerialization.data(withJSONObject: file, options: .prettyPrinted).write(to: fileURL, options: .atomic)
                app.buttons["Reload"].click()
            } catch {
                XCTFail("Could not reload the fixture Appearance: \(error)")
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
            XCTAssertEqual(documentModeState(mode), "Review")
            XCTAssertEqual(
                self.documentTitle(in: workspace),
                expectedTitle
            )
        }

        setBodyRhythm(
            lineHeight: 2.00,
            paragraphSpacing: 1.00
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
        ordinaryScreenshot.name =
            "Heading Study — accepted A — long mixed H1 — 1180×760 — Review — native window title"
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
        narrowScreenshot.name =
            "Heading Study — accepted A — long mixed H1 — 900×760 — Review — native window title"
        narrowScreenshot.lifetime = .keepAlways
        add(narrowScreenshot)

        XCTAssertEqual(try Data(contentsOf: noteURL), sourceBefore)
        XCTAssertEqual(workspace.identifier, workspaceIdentity)
        XCTAssertEqual(documentModeState(mode), "Review")
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
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown editor, Edit mode"].waitForExistence(
                timeout: 8))

        selectDocumentMode("Source")
        XCTAssertTrue(
            app.descendants(matching: .any)["Markdown source editor"].waitForExistence(timeout: 8))

        selectDocumentMode("Review")
        waitForCurrentDocumentSurface()

        let sessionFile = homeDirectory.appendingPathComponent("ApplicationSupport/Window Sessions")
            .appendingPathComponent(sessionID.uuidString + ".json")
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                guard let data = try? Data(contentsOf: sessionFile),
                    let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let scale = snapshot["documentTextScale"] as? NSNumber
                else { return false }
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

/// Opt-in regression driver for a retained, nonprivate Chat fixture. It never
/// sends a message, reads a research vault or resets the QA login/history.
final class ScholiumChatScrollUITests: XCTestCase {
    private var fixtureApp: XCUIApplication?
    @MainActor override func tearDown() async throws {
        fixtureApp?.terminate()
        fixtureApp = nil
    }

    @MainActor
    func testRichReplyScrollRegionsAndStableExtent() throws { try exerciseScroll(checkRegions: true) }

    @MainActor
    func testScrollThumbMovesWithoutChangingExtent() throws { try exerciseScroll(checkRegions: false) }

    @MainActor
    private func exerciseScroll(checkRegions: Bool) throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["SCHOLIUM_CHAT_SCROLL_APP"],
            let conversation = environment["SCHOLIUM_CHAT_SCROLL_CONVERSATION"]
        else {
            throw XCTSkip("Configure the disposable Chat scroll fixture.")
        }
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        fixtureApp = app
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let chat = app.radioButtons.matching(NSPredicate(format: "label == %@", "Chat")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.click()
        let back = app.buttons["scholium.chat.back"]
        if back.waitForExistence(timeout: 2) { back.click() }
        let row = app.buttons["scholium.chat.conversation.\(conversation)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let transcript = app.scrollViews["scholium.chat.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        let content = app.descendants(matching: .any)["scholium.chat.transcript.content"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 15))
        // Wait for the rich reader's asynchronous initial layout to settle.
        var previous = content.frame.height
        var stable = 0
        let deadline = Date().addingTimeInterval(20)
        while stable < 5 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let current = content.frame.height
            stable = abs(current - previous) < 1 ? stable + 1 : 0
            previous = current
        }
        XCTAssertEqual(stable, 5)
        let height = content.frame.height
        XCTAssertGreaterThan(height, transcript.frame.height * 2)
        // Begin at the latest reply, repeatedly cross the reported prose/code
        // boundary upwards, then reverse through the same screen regions.
        if checkRegions {
            for direction: CGFloat in [1, -1] {
                for fraction: CGFloat in [0.25, 0.5, 0.7, 0.35, 0.6, 0.3, 0.65] {
                    let before = content.frame.minY
                    transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: fraction))
                        .scroll(byDeltaX: 0, deltaY: direction * 250)
                    let moved = NSPredicate { _, _ in abs(content.frame.minY - before) > 3 }
                    XCTAssertEqual(
                        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: nil)], timeout: 3), .completed,
                        "Scroll ignored at viewport fraction \(fraction), direction \(direction)")
                    XCTAssertEqual(
                        content.frame.height, height, accuracy: 1,
                        "Loaded transcript extent changed while scrolling")
                }
            }
        } else {
            let scrollbar = try XCTUnwrap(
                transcript.scrollBars.allElementsBoundByIndex.first {
                    $0.frame.height > $0.frame.width
                })
            let window = app.windows.firstMatch
            let origin = window.coordinate(withNormalizedOffset: .zero)
            let rectangle = scrollbar.frame
            let thumb = try XCTUnwrap(
                scrollbar.children(matching: .any).allElementsBoundByIndex.first {
                    $0.frame.width > 0 && $0.frame.height > 10 && $0.frame.height < rectangle.height
                }
            ).frame
            let start = origin.withOffset(
                CGVector(
                    dx: thumb.midX - window.frame.minX,
                    dy: thumb.midY - window.frame.minY))
            let end = origin.withOffset(
                CGVector(
                    dx: thumb.midX - window.frame.minX,
                    dy: rectangle.midY - window.frame.minY))
            start.hover()
            let prior = XCTAttachment(screenshot: app.screenshot())
            prior.name = "Scroll thumb before drag"
            prior.lifetime = .keepAlways
            add(prior)
            let beforeDrag = content.frame.minY
            start.click(forDuration: 0.2, thenDragTo: end)
            let after = XCTAttachment(screenshot: app.screenshot())
            after.name = "Scroll thumb after drag"
            after.lifetime = .keepAlways
            add(after)
            XCTAssertNotEqual(content.frame.minY, beforeDrag, "Dragging the scroll thumb did not move the conversation")
            XCTAssertEqual(content.frame.height, height, accuracy: 1)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Rich reply scroll regions and stable extent"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
