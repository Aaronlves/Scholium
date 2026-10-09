import AppKit
@preconcurrency import XCTest

extension ScholiumUITests {
    @MainActor
    func ensureChatSidebarIsVisible() {
        guard !sidebarModeControl("Chat").exists else { return }
        // Preference-file seeding can leave Chat hidden in the QA session.
        // Establish this journey's precondition through the native setting.
        let settings = openSettingsForTransactionTest()
        let search = settings.searchFields["scholium.settings.search"]
        typeCommittedText("Chat", into: search, in: app)
        selectSettingsSearchResult("agents.chatSidebar", in: settings)
        let toggle = settings.checkBoxes["scholium.settings.chatSidebarEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if !selectionControlIsSelected(toggle) { toggle.click() }
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitUntil(timeout: 3) { !settings.exists })
        XCTAssertTrue(sidebarModeControl("Chat").waitForExistence(timeout: 5))
    }

    @MainActor
    func testChatEntryWithReducedMotionKeepsHiddenDetailInert() throws {
        waitForCurrentDocumentSurface()
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try Data(contentsOf: note)
        app.terminate()
        let fixture = try seedChatEntryFixture()
        app = configuredApplication(sessionID: UUID(), appearance: .light)
        app.launchEnvironment["SCHOLIUM_UI_TEST_REDUCE_MOTION"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        ensureChatSidebarIsVisible()
        sidebarModeControl("Chat").click()
        let composer = app.textViews["scholium.chat.message"].firstMatch
        for item in [fixture.short, fixture.long, fixture.short] {
            chatDeletionRow(item.id).click()
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            XCTAssertEqual(composer.value as? String, item.draft)
            returnToChatDeletionList()
            XCTAssertTrue(waitUntil(timeout: 3) { !composer.exists })
            XCTAssertTrue(app.descendants(matching: .any)["scholium.chat.conversations"].firstMatch.exists)
        }
        chatDeletionRow(fixture.short.id).click()
        XCTAssertEqual(composer.value as? String, fixture.short.draft)
        app.descendants(matching: .any)["scholium.chat.options"].firstMatch.click()
        app.menuItems["Find in Conversation"].hover()
        app.typeKey(.return, modifierFlags: [])
        let find = app.descendants(matching: .any)["scholium.chat.find.query"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: find) })
        returnToChatDeletionList()
        XCTAssertTrue(waitUntil(timeout: 3) { !find.exists && !composer.exists })
        chatDeletionRow(fixture.short.id).click()
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: find) })
        app.typeKey(.escape, modifierFlags: [])
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "Reduced Motion Chat entry — same retained native draft"
        image.lifetime = .keepAlways
        add(image)
        XCTAssertEqual(try Data(contentsOf: note), original)
        let archive = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.archive)) as? [String: Any])
        let conversations = try XCTUnwrap(archive["conversations"] as? [[String: Any]])
        XCTAssertEqual(conversations.compactMap { ($0["messages"] as? [Any])?.count }.sorted(), [2, 72])
    }

    /// App-owned timings exclude XCTest's click/idle wait. The archive has no
    /// provider threads and keeps the standard disposable Triptych unchanged.
    @MainActor
    func testChatEntryMeasuresShortLongAndRepeatedNativeNavigation() throws {
        waitForCurrentDocumentSurface()
        let note = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let original = try Data(contentsOf: note)
        app.terminate()
        let fixture = try seedChatEntryFixture()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runID = "chat-entry-\(UUID().uuidString)"
        let raw = repository.appendingPathComponent(".build/performance-\(runID)/app-state/raw")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        let results = raw.appendingPathComponent("chat-entry.jsonl")
        app = configuredApplication(sessionID: UUID(), appearance: .light)
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_RESULTS_PATH"] = results.path
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_METRIC"] = "chat_entry"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_RUN_ID"] = runID
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE"] = "0"
        app.launchEnvironment["SCHOLIUM_PERFORMANCE_SAMPLE_COUNT"] = "8"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
        sidebarModeControl("Chat").click()
        let composer = app.textViews["scholium.chat.message"].firstMatch
        var expectedSamples = 0
        func records() -> [[String: Any]] {
            guard let text = try? String(contentsOf: results, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").compactMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
        }
        func awaitEntry(_ item: (id: UUID, turns: Int, draft: String)) throws {
            expectedSamples += 1
            XCTAssertTrue(waitUntil(timeout: 15) { records().count == expectedSamples }, "The native Chat entry did not reach hydrated, positioned readiness.")
            XCTAssertTrue(composer.waitForExistence(timeout: 5))
            XCTAssertEqual(composer.value as? String, item.draft)
            let record = try XCTUnwrap(records().last)
            XCTAssertEqual(record["observed_count"] as? Int, item.turns * 2)
            XCTAssertEqual(record["mounted_reader_count"] as? Double, Double(min(4, item.turns * 2)))
            print("CHAT_ENTRY sample=\(expectedSamples - 1) record=\(record)")
        }
        for item in [fixture.short, fixture.long] {
            for visit in 0..<3 {
                let row = chatDeletionRow(item.id)
                XCTAssertTrue(row.waitForExistence(timeout: 10))
                row.click()
                try awaitEntry(item)
                if visit == 0 {
                    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                    image.name = "Native Chat entry settled — \(item.turns) exchanges"
                    image.lifetime = .keepAlways
                    add(image)
                }
                returnToChatDeletionList()
                XCTAssertTrue(waitUntil(timeout: 3) { !composer.exists }, "The retained detail is inaccessible from the list")
            }
        }
        // Keyboard activation follows the same native menu route as pointer entry.
        let shortRow = chatDeletionRow(fixture.short.id)
        shortRow.rightClick()
        let open = app.menuItems["Open Conversation"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.hover()
        app.typeKey(.return, modifierFlags: [])
        try awaitEntry(fixture.short)
        returnToChatDeletionList()
        chatDeletionRow(fixture.long.id).click()
        try awaitEntry(fixture.long)
        composer.click()
        let editedDraft = fixture.long.draft + " — retained native edit"
        typeCommittedText(editedDraft, into: composer, in: app)
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 5) { composer.value as? String == fixture.long.draft })
        app.descendants(matching: .any)["scholium.chat.options"].firstMatch.click()
        app.menuItems["Find in Conversation"].hover()
        app.typeKey(.return, modifierFlags: [])
        let find = app.descendants(matching: .any)["scholium.chat.find.query"].firstMatch
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 3) { NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: find) })
        app.typeKey(.escape, modifierFlags: [])
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Appearance"].firstMatch.hover()
        app.menuItems["Dark"].click()
        resizeProofWindow(app.windows.firstMatch, toWidth: 780, height: 640)
        let finalImage = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        finalImage.name = "Chat entry retained draft and history — Dark narrow"
        finalImage.lifetime = .keepAlways
        add(finalImage)
        XCTAssertEqual(composer.value as? String, fixture.long.draft)
        XCTAssertEqual(records().count, 8)
        XCTAssertEqual(try Data(contentsOf: note), original)
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.archive)) as? [String: Any])
        let conversations = try XCTUnwrap(archive["conversations"] as? [[String: Any]])
        XCTAssertEqual(conversations.compactMap { ($0["messages"] as? [[String: Any]])?.count }.sorted(), [2, 72])
        print("CHAT_ENTRY_RESULTS \(results.path)")
    }

    @MainActor
    func seedChatEntryFixture() throws -> (
        short: (id: UUID, turns: Int, draft: String), long: (id: UUID, turns: Int, draft: String), archive: URL
    ) {
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: triptychDirectory.appendingPathComponent(".scholium/manifest.json"))) as? [String: Any])
        let triptychID = try XCTUnwrap(manifest["id"] as? String)
        let root = homeDirectory.appendingPathComponent("ApplicationSupport/Chat/\(triptychID)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let short = (id: UUID(), turns: 1, draft: "Short unsent draft — 尚未发送。")
        let long = (id: UUID(), turns: 36, draft: "Long unsent draft — 保留输入、历史和选择。")
        let conversations = [short, long].map { item -> [String: Any] in
            let messages = (0..<item.turns).flatMap { index -> [[String: Any]] in
                let turn = "synthetic-turn-\(index)"
                return [
                    [
                        "id": "question-\(index)", "role": "user", "turnID": turn,
                        "text": "Synthetic question \(index + 1). 请核对来源和解释边界。", "attachments": [], "localMaterials": [],
                    ],
                    [
                        "id": "reply-\(index)", "role": "assistant", "phase": "final_answer", "turnID": turn,
                        "text": "## Synthetic reply \(index + 1)\n\n"
                            + String(repeating: "A disposable source-faithful paragraph. 中文与 English 合成材料，保留研究者控制。\n\n", count: 4)
                            + "| Claim | Status |\n|---|---|\n| Synthetic | Reported |\n\nFinal retained passage \(index + 1).",
                        "attachments": [], "localMaterials": [],
                    ],
                ]
            }
            return [
                "id": item.id.uuidString, "triptychID": triptychID,
                "title": "QA \(item.turns)-exchange conversation", "permission": "ask",
                "preferences": ["webSearch": "runtimeDefault"], "turns": [:], "childDrafts": [:],
                "draft": item.draft, "attachments": [], "localMaterials": [], "messages": messages,
                "queuedMessages": [], "updatedAt": Date().timeIntervalSinceReferenceDate,
            ]
        }
        let archive = root.appendingPathComponent("conversations.json")
        try JSONSerialization.data(withJSONObject: ["version": 12, "conversations": conversations]).write(to: archive, options: .atomic)
        return (short, long, archive)
    }

    /// The shared setup transport must preserve a draft's newlines without
    /// accidentally dispatching Return to the composer's submit action.
    @MainActor
    func testNativeTextSetupKeepsMultilineChatDraftUnsent() throws {
        waitForCurrentDocumentSurface()
        let sourceURL = triptychDirectory.appendingPathComponent("01-analyses/QA Autosave A.md")
        let originalSource = try Data(contentsOf: sourceURL)
        sidebarModeControl("Chat").click()
        let create = app.buttons["scholium.chat.newConversation"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.click()
        let composer = app.textViews["scholium.chat.message"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let draft = "Synthetic unsent draft. 保留原文。\n\nA second paragraph. 尚待核对。\n"
        typeCommittedText(draft, into: composer, in: app, clickWithinVisibleFrame: true)
        XCTAssertEqual(composer.value as? String, draft)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.chat.emptyConversation"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.chat.queue"].firstMatch.exists)
        sidebarModeControl("Library").click()
        XCTAssertFalse(composer.exists)
        sidebarModeControl("Chat").click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, draft)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.chat.emptyConversation"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["scholium.chat.queue"].firstMatch.exists)
        XCTAssertEqual(try Data(contentsOf: sourceURL), originalSource)
    }

    /// Uses the current local archive schema with no runtime thread or account.
    /// All actions after seeding use the ordinary conversation list and alert.
    @MainActor
    func testArchivedChatDeletionPreservesSharedMaterialAndOriginals() throws {
        // setUp registers the disposable Triptych. Stop its sole QA process
        // before adding history bound to that newly registered identity.
        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) { self.app.state == .notRunning })
        let fixture = try seedChatDeletionFixture()
        launchChatDeletionFixture(appearance: .light)
        openChatDeletionList()
        XCTAssertTrue(chatDeletionRow(fixture.sourceID).waitForExistence(timeout: 10))
        XCTAssertTrue(chatDeletionRow(fixture.branchID).exists)

        performChatDeletionAction("Archive Chat", on: fixture.sourceID)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.chatDeletionRecord(fixture.sourceID, in: fixture)?.isArchived == true
            })
        showChatDeletionList(archived: true)
        XCTAssertTrue(chatDeletionRow(fixture.sourceID).waitForExistence(timeout: 5))
        XCTAssertFalse(chatDeletionRow(fixture.branchID).exists)

        performChatDeletionAction("Delete", on: fixture.sourceID)
        let cancelledAlert = try chatDeletionAlert()
        let alertImage = XCTAttachment(screenshot: cancelledAlert.screenshot())
        alertImage.name = "Archived Chat permanent deletion confirmation — Light"
        alertImage.lifetime = .keepAlways
        add(alertImage)
        // Escape exercises the native cancellation route without committing.
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        XCTAssertTrue(waitUntil(timeout: 5) { !cancelledAlert.exists })
        XCTAssertTrue(chatDeletionRow(fixture.sourceID).exists)
        XCTAssertEqual(chatDeletionRecord(fixture.sourceID, in: fixture)?.draft, fixture.sourceDraft)
        XCTAssertEqual(chatDeletionRecord(fixture.sourceID, in: fixture)?.isArchived, true)
        try assertChatDeletionCopies(fixture, retainedIndices: Array(0..<6))

        // Restore must expose the retained native draft before rearchiving it.
        performChatDeletionAction("Restore Chat", on: fixture.sourceID)
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.chatDeletionRecord(fixture.sourceID, in: fixture)?.isArchived == false
            })
        showChatDeletionList(archived: false)
        chatDeletionRow(fixture.sourceID).click()
        let composer = app.textViews["scholium.chat.message"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, fixture.sourceDraft)
        typeCommittedText(fixture.sourceDraft + "24680", into: composer, in: app, clickWithinVisibleFrame: true)
        XCTAssertTrue(
            waitUntil(timeout: 5) { composer.value as? String == fixture.sourceDraft + "24680" },
            "Restored offline drafts must accept ordinary native input at the visible composer.")
        XCTAssertTrue(
            waitUntil(timeout: 5) {
                self.chatDeletionRecord(fixture.sourceID, in: fixture)?.draft == fixture.sourceDraft + "24680"
            }, "The edited draft must persist to its own conversation.")
        app.menuBars.menuBarItems["Edit"].click()
        let editMenu = app.menuBars.menuBarItems["Edit"].menus.firstMatch
        let undo = editMenu.menuItems.matching(
            NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@ OR title BEGINSWITH %@", "undo:", "Undo", "Undo")
        ).firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        print("CHAT_NATIVE_UNDO title=\(undo.title) enabled=\(undo.isEnabled)")
        XCTAssertTrue(undo.isEnabled, "A committed native composer edit must expose Undo through Edit.")
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(
            waitUntil(timeout: 5) { composer.value as? String == fixture.sourceDraft },
            "Native Undo must restore the visible draft; actual synthetic text: \(composer.value as? String ?? "unavailable").")
        XCTAssertTrue(
            waitUntil(timeout: 5) { self.chatDeletionRecord(fixture.sourceID, in: fixture)?.draft == fixture.sourceDraft },
            "Native Undo must persist the restored draft to its conversation.")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(timeout: 5) { composer.value as? String == fixture.sourceDraft + "24680" })
        app.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitUntil(timeout: 5) { composer.value as? String == fixture.sourceDraft })
        returnToChatDeletionList()
        performChatDeletionAction("Archive Chat", on: fixture.sourceID)
        showChatDeletionList(archived: true)
        performChatDeletionAction("Delete", on: fixture.sourceID)
        try chatDeletionAlert().buttons["Delete"].firstMatch.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                guard let records = self.chatDeletionRecords(in: fixture) else { return false }
                return !records.contains { $0.id == fixture.sourceID }
                    && fixture.copies.prefix(3).allSatisfy {
                        !FileManager.default.fileExists(atPath: $0.path)
                    }
            }, "Deletion must commit history and release all unreferenced draft, queue, and message copies.")
        XCTAssertFalse(chatDeletionRow(fixture.sourceID).exists)
        try assertChatDeletionCopies(fixture, retainedIndices: Array(3..<6))
        let branch = try XCTUnwrap(chatDeletionRecord(fixture.branchID, in: fixture))
        XCTAssertEqual(branch.draft, fixture.branchDraft)
        XCTAssertEqual(branch.materialIDs, Set(fixture.materialIDs.suffix(3)))
        XCTAssertEqual(branch.messages.map(\.text), ["Inherited input"])
        XCTAssertEqual(branch.queuedMessages.map(\.text), ["Branch queued input"])

        // The surviving branch still exposes its shared unsent material.
        showChatDeletionList(archived: false)
        chatDeletionRow(fixture.branchID).click()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, fixture.branchDraft)
        XCTAssertTrue(
            app.buttons["Preview material: source-4.txt"].firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Preview material: source-4.txt"].firstMatch.isHittable)
        returnToChatDeletionList()
        performChatDeletionAction("Archive Chat", on: fixture.branchID)
        showChatDeletionList(archived: true)
        performChatDeletionAction("Delete", on: fixture.branchID)
        try chatDeletionAlert().buttons["Delete"].firstMatch.click()
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                guard let records = self.chatDeletionRecords(in: fixture) else { return false }
                return records.isEmpty
                    && fixture.copies.allSatisfy {
                        !FileManager.default.fileExists(atPath: $0.path)
                    }
            }, "Deleting the final owner must release shared material and persist an empty archive.")
        try assertChatDeletionCopies(fixture, retainedIndices: [])
        assertChatDeletionEmptyArchive()

        // Relaunch verifies durable deletion; a fresh empty conversation may
        // be created, but neither removed identity may return to either list.
        app.terminate()
        launchChatDeletionFixture(appearance: .dark)
        openChatDeletionList()
        XCTAssertFalse(chatDeletionRow(fixture.sourceID).exists)
        XCTAssertFalse(chatDeletionRow(fixture.branchID).exists)
        XCTAssertTrue(app.descendants(matching: .any)["scholium.chat.empty"].firstMatch.exists)
        showChatDeletionList(archived: true)
        assertChatDeletionEmptyArchive()
        let emptyImage = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        emptyImage.name = "Deleted Chat history remains absent after relaunch — Dark"
        emptyImage.lifetime = .keepAlways
        add(emptyImage)
        try assertChatDeletionCopies(fixture, retainedIndices: [])
        for (url, bytes) in fixture.noteOriginals {
            XCTAssertEqual(try Data(contentsOf: url), bytes, "Chat organization must preserve fixture Note bytes.")
        }
    }

    @MainActor
    private func launchChatDeletionFixture(appearance: QAAppearance) {
        sessionID = UUID()
        app = configuredApplication(sessionID: sessionID, appearance: appearance)
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        waitForCurrentDocumentSurface()
    }

    @MainActor
    private func openChatDeletionList() {
        let chat = sidebarModeControl("Chat")
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        chat.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.chat.conversations"].firstMatch
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            waitUntil(timeout: 10) {
                !self.app.descendants(matching: .any)["scholium.chat.loading"].firstMatch.exists
            })
    }

    @MainActor
    func chatDeletionRow(_ id: UUID) -> XCUIElement {
        app.descendants(matching: .any)["scholium.chat.conversation.\(id.uuidString)"].firstMatch
    }

    @MainActor
    private func performChatDeletionAction(_ title: String, on id: UUID) {
        let row = chatDeletionRow(id)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let menu = app.menus.containing(.menuItem, identifier: "Open Conversation").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        let action = menu.menuItems[title].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        action.click()
    }

    @MainActor
    private func showChatDeletionList(archived: Bool) {
        let options = app.descendants(matching: .any)["scholium.chat.archived"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.click()
        let destination = app.menuItems[archived ? "Archived Chats" : "Conversations"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.click()
    }

    @MainActor
    private func returnToChatDeletionList() {
        let back = app.buttons["scholium.chat.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["scholium.chat.conversations"].firstMatch
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func chatDeletionAlert() throws -> XCUIElement {
        let message = "This permanently deletes the local conversation history and drafts. This cannot be undone."
        XCTAssertTrue(app.staticTexts[message].firstMatch.waitForExistence(timeout: 5))
        // Bind buttons to the visible native modal exposed by XCTest.
        let candidates = [app.alerts.firstMatch, app.dialogs.firstMatch, app.sheets.firstMatch]
        let alert = try XCTUnwrap(candidates.first { $0.exists && $0.buttons["Delete"].firstMatch.exists })
        XCTAssertTrue(alert.buttons["Cancel"].firstMatch.exists)
        XCTAssertTrue(alert.buttons["Delete"].firstMatch.isEnabled)
        return alert
    }

    @MainActor
    private func assertChatDeletionEmptyArchive() {
        let empty = app.descendants(matching: .any)["scholium.chat.empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.staticTexts.matching(NSPredicate(format: "value BEGINSWITH %@", "No Archived Chats")).firstMatch.exists)
    }

    @MainActor
    private func chatDeletionRecords(in fixture: ChatDeletionFixture) -> [ChatDeletionRecord]? {
        guard let data = try? Data(contentsOf: fixture.archive),
            let archive = try? JSONDecoder().decode(ChatDeletionArchive.self, from: data),
            archive.version == 12
        else { return nil }
        return archive.conversations
    }

    @MainActor
    private func chatDeletionRecord(_ id: UUID, in fixture: ChatDeletionFixture) -> ChatDeletionRecord? {
        chatDeletionRecords(in: fixture)?.first { $0.id == id }
    }

    @MainActor
    private func assertChatDeletionCopies(_ fixture: ChatDeletionFixture, retainedIndices: [Int]) throws {
        for index in fixture.copies.indices {
            if retainedIndices.contains(index) {
                XCTAssertEqual(try Data(contentsOf: fixture.copies[index]), fixture.originalBytes[index])
            } else {
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.copies[index].path))
            }
            XCTAssertEqual(try Data(contentsOf: fixture.originals[index]), fixture.originalBytes[index])
        }
    }

    @MainActor
    private func seedChatDeletionFixture() throws -> ChatDeletionFixture {
        let sourceID = UUID()
        let branchID = UUID()
        let sourceDraft = "Retained source draft. 原始草稿。"
        let branchDraft = "Retained branch draft. 分支草稿。"
        let manifestURL = triptychDirectory.appendingPathComponent(".scholium/manifest.json")
        let manifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        let triptychID = try XCTUnwrap((manifest["id"] as? String).flatMap(UUID.init(uuidString:)))
        let root = homeDirectory.appendingPathComponent("ApplicationSupport/Chat/\(triptychID.uuidString)")
        let materialRoot = root.appendingPathComponent("Materials", isDirectory: true)
        let originalRoot = testDirectory.appendingPathComponent("ChatOriginals", isDirectory: true)
        for directory in [materialRoot, originalRoot] {
            guard
                directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents.starts(
                    with: testDirectory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
                )
            else { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        var materials: [[String: Any]] = []
        var materialIDs: [UUID] = []
        var originals: [URL] = []
        var copies: [URL] = []
        var originalBytes: [Data] = []
        for index in 0..<6 {
            let id = UUID()
            let text = "Synthetic Chat material \(index). 原始材料。\n"
            let bytes = Data(text.utf8)
            let original = originalRoot.appendingPathComponent("source-\(index).txt")
            let name = id.uuidString + ".txt"
            let copy = materialRoot.appendingPathComponent(name)
            try bytes.write(to: original, options: .withoutOverwriting)
            try bytes.write(to: copy, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: copy.path)
            materials.append([
                "id": id.uuidString, "source": ["file": ["_0": original.absoluteString]],
                "storedFileName": name, "fingerprint": qaFingerprint(text), "kind": "text",
                "text": text, "pages": [], "pageImages": [],
            ])
            materialIDs.append(id)
            originals.append(original)
            copies.append(copy)
            originalBytes.append(bytes)
        }
        func message(_ text: String, material: Int) -> [String: Any] {
            [
                "id": UUID().uuidString, "role": "user", "text": text,
                "attachments": [], "localMaterials": [materials[material]],
            ]
        }
        func conversation(_ id: UUID, title: String, draft: String) -> [String: Any] {
            [
                "id": id.uuidString, "triptychID": triptychID.uuidString, "title": title,
                "permission": "ask", "preferences": ["webSearch": "runtimeDefault"],
                "turns": [:], "childDrafts": [:], "draft": draft,
                "attachments": [], "localMaterials": [], "messages": [], "queuedMessages": [],
                "updatedAt": Date().timeIntervalSinceReferenceDate,
            ]
        }
        var source = conversation(sourceID, title: "QA source conversation", draft: sourceDraft)
        source["localMaterials"] = [materials[0], materials[3]]
        source["queuedMessages"] = [message("Source queued input", material: 1), message("Shared queued input", material: 4)]
        source["messages"] = [message("Source sent input", material: 2), message("Shared sent input", material: 5)]
        var branch = conversation(branchID, title: "QA branch conversation", draft: branchDraft)
        branch["branchOrigin"] = ["conversationID": sourceID.uuidString, "turnID": "ended-source-turn", "position": "through"]
        branch["localMaterials"] = [materials[4]]
        branch["queuedMessages"] = [message("Branch queued input", material: 5)]
        branch["messages"] = [message("Inherited input", material: 3)]
        let archive = root.appendingPathComponent("conversations.json")
        try JSONSerialization.data(withJSONObject: ["version": 12, "conversations": [source, branch]])
            .write(to: archive, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        let noteOriginals = try ["01-analyses/QA Autosave A.md", "02-topics/QA Topic.md", "03-works/QA Work.md"].map {
            let url = triptychDirectory.appendingPathComponent($0)
            return (url, try Data(contentsOf: url))
        }
        return ChatDeletionFixture(
            sourceID: sourceID, branchID: branchID, sourceDraft: sourceDraft, branchDraft: branchDraft,
            archive: archive, materialIDs: materialIDs, originals: originals, copies: copies,
            originalBytes: originalBytes, noteOriginals: noteOriginals
        )
    }
}

private struct ChatDeletionFixture {
    let sourceID: UUID
    let branchID: UUID
    let sourceDraft: String
    let branchDraft: String
    let archive: URL
    let materialIDs: [UUID]
    let originals: [URL]
    let copies: [URL]
    let originalBytes: [Data]
    let noteOriginals: [(URL, Data)]
}

/// A narrow decoder reads observable persistence without importing the app
/// executable into the standalone UI-test bundle. Unknown current fields stay
/// owned by AgentChatConversation; this test never reconstructs loaded history.
private struct ChatDeletionArchive: Decodable {
    let version: Int
    let conversations: [ChatDeletionRecord]
}

private struct ChatDeletionRecord: Decodable {
    struct Material: Decodable { let id: UUID }
    struct Message: Decodable {
        let text: String
        let localMaterials: [Material]
    }
    let id: UUID
    let draft: String
    let archivedAt: Date?
    let localMaterials: [Material]
    let messages: [Message]
    let queuedMessages: [Message]
    var isArchived: Bool { archivedAt != nil }
    var materialIDs: Set<UUID> {
        Set((localMaterials + messages.flatMap(\.localMaterials) + queuedMessages.flatMap(\.localMaterials)).map(\.id))
    }
}
