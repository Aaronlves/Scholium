import AppKit
import CryptoKit
@preconcurrency import XCTest
import notify

extension ScholiumUITests {
    /// One offline Chat journey covers page lifetime without dispatching any message.
    @MainActor
    func testChatSidebarPageTransitionsRetainDraftAndFind() throws {
        waitForCurrentDocumentSurface()
        sidebarModeControl("Chat").click()
        let create = app.buttons["scholium.chat.newConversation"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        let composer = app.textViews["scholium.chat.message"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        typeCommittedText("First sidebar draft", into: composer, in: app, clickWithinVisibleFrame: true)

        app.descendants(matching: .any)["scholium.chat.options"].firstMatch.click()
        app.menuItems["Find in Conversation"].click()
        let find = app.descendants(matching: .any)["scholium.chat.find.query"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        typeCommittedText("retained query", into: find, in: app)
        app.buttons["scholium.chat.back"].click()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "scholium.chat.conversation."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let originalRowID = rows.firstMatch.identifier
        app.buttons[originalRowID].click()
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertEqual(find.value as? String, "retained query")
        XCTAssertEqual(composer.value as? String, "First sidebar draft")

        create.click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(find.exists)
        XCTAssertEqual(composer.value as? String, "")
        typeCommittedText("Second sidebar draft", into: composer, in: app, clickWithinVisibleFrame: true)
        sidebarModeControl("Library").click()
        XCTAssertFalse(composer.exists)
        sidebarModeControl("Chat").click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "Second sidebar draft")
        app.buttons["scholium.chat.back"].click()
        XCTAssertTrue(app.buttons[originalRowID].waitForExistence(timeout: 5))
        app.buttons[originalRowID].click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "First sidebar draft")
        XCTAssertFalse(find.exists)
    }

    /// One settings journey covers stable geometry, draft lifetime, search and
    /// hidden-page input isolation. It writes only the disposable QA profile.
    @MainActor
    func testSettingsNavigationRetainsDraftsAndWindowGeometry() throws {
        waitForCurrentDocumentSurface()
        app.menuBars.menuBarItems["Scholium QA"].click()
        app.menuItems["Settings…"].click()
        let window = app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let originalFrame = window.frame
        func category(_ key: String) -> XCUIElement {
            window.descendants(matching: .any)["scholium.settings.category.\(key)"].firstMatch
        }
        func select(_ key: String) {
            let item = category(key)
            XCTAssertTrue(item.waitForExistence(timeout: 5))
            item.click()
            XCTAssertEqual(window.frame.width, originalFrame.width, accuracy: 1)
            XCTAssertEqual(window.frame.height, originalFrame.height, accuracy: 1)
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        select("document")
        let size = window.textFields["Body font size"]
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        typeCommittedText("17", into: size, in: app)
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(window.buttons["Save Appearance"].isEnabled)
        capture("settings-appearance-draft")
        select("notifications")
        app.typeKey(.return, modifierFlags: [])
        select("document")
        XCTAssertEqual(size.value as? String, "17")
        XCTAssertTrue(window.buttons["Save Appearance"].isEnabled, "Return saved a hidden Appearance draft")
        window.descendants(matching: .any)["scholium.appearance.manage"].firstMatch.click()
        app.menuItems["Rename Appearance…"].click()
        let cancelRename = window.sheets.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelRename.waitForExistence(timeout: 5))
        cancelRename.click()
        XCTAssertEqual(size.value as? String, "17", "Cancelling a child presentation discarded the draft")
        window.descendants(matching: .any)["scholium.appearance.manage"].firstMatch.click()
        app.menuItems["Rename Appearance…"].click()
        let profileName = window.sheets.textFields.firstMatch
        XCTAssertTrue(profileName.waitForExistence(timeout: 5))
        typeCommittedText("QA Settings Profile", into: profileName, in: app)
        window.sheets.buttons["Rename"].firstMatch.click()
        let profilePicker = window.popUpButtons.matching(NSPredicate(format: "label BEGINSWITH %@", "Configuration")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 5) { profilePicker.exists && profilePicker.value as? String == "QA Settings Profile" })
        XCTAssertEqual(size.value as? String, "17", "Renaming the profile discarded unsaved formatting")
        select("notifications")
        XCTAssertFalse(window.buttons["Save Appearance"].exists, "Inactive pane must leave the accessibility tree")
        capture("settings-notifications")
        select("writing")
        capture("settings-writing")
        select("agents")
        capture("settings-agents")
        let taskSearch = window.searchFields["scholium.settings.search"]
        typeCommittedText("Core Protocol", into: taskSearch, in: app)
        let protectedSkill = window.staticTexts["Protected Skill"]
        XCTAssertTrue(protectedSkill.waitForExistence(timeout: 5))
        window.radioButtons["External Access"].click()
        let protocolResult = window.buttons["scholium.settings.result.agents.protocol"]
        XCTAssertTrue(protocolResult.waitForExistence(timeout: 5))
        protocolResult.click()
        XCTAssertTrue(waitUntil(timeout: 5) { protectedSkill.isHittable }, "Repeating a result must reveal its owning Agent segment")
        capture("settings-agent-skills")
        taskSearch.buttons["cancel"].click()
        window.radioButtons["External Access"].click()
        capture("settings-external-access")
        XCTAssertFalse(window.buttons["Show Core Protocol in Finder…"].exists,
            "External access must lead to the sole protocol viewing location")
        let skillsLink = window.buttons["Open Skills and Tools"]
        scrollUntilHittable(skillsLink, in: settingsContentScrollView(in: window))
        skillsLink.click()
        XCTAssertTrue(protectedSkill.waitForExistence(timeout: 5))
        XCTAssertEqual(window.buttons.matching(identifier: "Show Core Protocol in Finder…").count, 1)
        window.radioButtons["Connection and Chat"].click()
        select("zotero")
        typeCommittedText("Connected Tools", into: taskSearch, in: app)
        let zoteroLink = window.buttons["Open Zotero Settings"]
        XCTAssertTrue(zoteroLink.waitForExistence(timeout: 5))
        scrollUntilHittable(zoteroLink, in: settingsContentScrollView(in: window))
        zoteroLink.click()
        XCTAssertTrue(
            waitUntil(timeout: 5) { window.title == "Zotero" && taskSearch.value as? String == "" },
            "An explicit settings link must work when its remembered category is already equal")
        select("shortcuts")
        capture("settings-shortcuts")
        select("zotero")
        capture("settings-zotero")
        select("document")
        XCTAssertEqual(size.value as? String, "17", "Category navigation discarded an unsaved appearance draft")
        XCTAssertTrue(window.buttons["Save Appearance"].isEnabled)

        let search = window.searchFields["scholium.settings.search"]
        typeCommittedText("no-such-setting-qa", into: search, in: app)
        XCTAssertEqual(search.value as? String, "no-such-setting-qa")
        XCTAssertFalse(window.buttons["Save Appearance"].exists)
        capture("settings-empty-search")
        search.buttons["cancel"].click()
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        XCTAssertEqual(size.value as? String, "17")
        window.buttons["Revert to Saved"].click()
        XCTAssertFalse(window.buttons["Save Appearance"].isEnabled)

        select("workspace")
        let name = window.textFields["scholium.triptychName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let savedName = name.value as? String
        typeCommittedText("Unsaved QA name", into: name, in: app)
        select("notifications")
        select("workspace")
        XCTAssertEqual(name.value as? String, "Unsaved QA name")
        if let savedName { typeCommittedText(savedName, into: name, in: app) }
        capture("settings-workspace")

        // Native sidebar selection keeps keyboard focus across successive moves.
        category("workspace").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(size.waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(window.descendants(matching: .any)["scholium.settings.writing"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(window.frame.size, originalFrame.size)

        select("document")
        // Resize from the straight edge; the rounded corner falls outside the
        // Settings window's pointer region on this macOS version.
        let rightEdge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -1, dy: 0))
        rightEdge.click(forDuration: 0.15, thenDragTo: rightEdge.withOffset(CGVector(dx: 780 - window.frame.width, dy: 0)))
        XCTAssertTrue(waitUntil(timeout: 5) { abs(window.frame.width - 780) < 2 })
        XCTAssertTrue(window.buttons["Save Appearance"].isHittable)
        XCTAssertTrue(window.popUpButtons["scholium.appearance.bodyFont"].isHittable)
        capture("settings-appearance-minimum-width")
        let searchForDetails = window.searchFields["scholium.settings.search"]
        typeCommittedText("H6 spacing", into: searchForDetails, in: app)
        let h6Spacing = window.textFields["H6 space after"]
        XCTAssertTrue(h6Spacing.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 5) { h6Spacing.isHittable }, "Search must reveal the specific heading controls without manual scrolling")
        XCTAssertEqual(window.sheets.count, 0, "Heading details are edited in the appearance page")
        searchForDetails.buttons["cancel"].click()

        app.terminate()
        app = configuredApplication(sessionID: sessionID, appearance: .light)
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["scholium.librarySurface"].waitForExistence(timeout: 20))
        app.menuBars.menuBarItems["Scholium QA"].click()
        app.menuItems["设置…"].click()
        let localizedWindow = app.windows.matching(identifier: "com_apple_SwiftUI_Settings_window").firstMatch
        XCTAssertTrue(localizedWindow.waitForExistence(timeout: 5))
        let appearance = localizedWindow.descendants(matching: .any)["scholium.settings.category.document"].firstMatch
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.click()
        XCTAssertTrue(localizedWindow.textFields["正文字号"].waitForExistence(timeout: 5))
        let localizedAttachment = XCTAttachment(screenshot: localizedWindow.screenshot())
        localizedAttachment.name = "settings-appearance-chinese-light"
        localizedAttachment.lifetime = .keepAlways
        add(localizedAttachment)
        localizedWindow.descendants(matching: .any)["scholium.settings.category.agents"].firstMatch.click()
        XCTAssertTrue(localizedWindow.radioButtons["连接与聊天"].waitForExistence(timeout: 5))
        let agentAttachment = XCTAttachment(screenshot: localizedWindow.screenshot())
        agentAttachment.name = "settings-agents-chinese-light-normalized"
        agentAttachment.lifetime = .keepAlways
        add(agentAttachment)
    }

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
        let originalTitle = documentTitle()
        let originalNavigatorFrame = navigator.frame
        for (role, note) in [("Topics", "QA Topic.md"), ("Works", "QA Work.md"), ("Analyses", "QA Autosave A.md")] {
            navigator.descendants(matching: .any)[role].firstMatch.click()
            let destination = app.descendants(matching: .any)["scholium.noteRow.\(note)"].firstMatch
            XCTAssertTrue(destination.waitForExistence(timeout: 5))
            XCTAssertEqual(documentTitle(), originalTitle, "Browsing a Library role must retain the Document.")
            XCTAssertEqual(navigator.frame, originalNavigatorFrame)
            let list = app.descendants(matching: .any)["scholium.noteList"].firstMatch
            XCTAssertGreaterThan(list.frame.height, 200, "The transition host must fill the source region.")
        }
        let topics = navigator.descendants(matching: .any)["Topics"].firstMatch
        XCTAssertTrue(topics.waitForExistence(timeout: 5))
        topics.click()
        _ = clickLibraryRow("QA Topic.md")
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
    func testNativeCommandButtonsPreserveDefaultDisabledAndCancelActions() throws {
        waitForCurrentDocumentSurface()
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let movedURL = triptychDirectory.appendingPathComponent("01-analyses/QA Button Move.md")
        let originalBytes = try Data(contentsOf: sourceURL)
        let row = clickLibraryRow("QA Autosave A.md", rightMouseButton: true)
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
        let movedRow = clickLibraryRow("QA Button Move.md", rightMouseButton: true)
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
