import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Chat sidebar presentation lifecycle", .serialized)
@MainActor
struct AgentChatSidebarLifecycleTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("The mounted Chat shell changes native draft ownership and clears the previous conversation's Find", arguments: [false, true])
    func conversationSwitchKeepsDraftsAndResetsFind(reduceMotion: Bool) async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/sidebar-switch-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let firstID = try #require(controller.selectedID)
        let firstDraft = "First unsent draft "
        controller.editDraft(firstDraft)
        controller.newConversation()
        let secondID = try #require(controller.selectedID)
        controller.editDraft("第二个未发送草稿")

        let readerID = UUID()
        let host = NSHostingView(
            rootView: AgentChatView(
                controller: controller, transcriptReaderID: readerID, isVisible: true, addSelection: { _ in false },
                noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
                openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
                showConversationChanges: { _ in }
            )
            .environment(\.scholiumVisualEnvironmentOverride, .init(reduceMotion: reduceMotion)))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        #expect(controller.transcriptReaders[readerID] == nil, "The conversation list is not an active conversation")
        #expect(await controller.selectNotification(.init(triptychID: controller.triptychID, conversationID: firstID, event: .inputRequired)))
        try await settle(host) { composer(in: host)?.conversationID == firstID }
        #expect(controller.transcriptReaders[readerID] == firstID)
        let first = try #require(composer(in: host))
        #expect(first.editor.string == firstDraft)

        // Exercise the real composer command route instead of reaching into
        // the shell's private presentation state to display Find.
        first.editor.setSelectedRange(NSRange(location: firstDraft.utf16.count, length: 0))
        first.editor.insertText("/find", replacementRange: first.editor.selectedRange())
        try await settle(host) {
            first.completion?.candidates.contains {
                if case .find = $0.action { return true }
                return false
            } == true
                && first.completion?.candidateQuery == first.completion?.query
        }
        let completion = try #require(first.completion)
        let candidate = try #require(
            completion.candidates.first {
                if case .find = $0.action { return true }
                return false
            })
        completion.accept(candidate)
        try await settle(host) { findField(in: host) != nil }
        let query = try #require(findField(in: host))
        query.stringValue = "first-only query"
        try #require(query.target as? ContextSearchField.Coordinator).searchChanged(query)
        try await settle(host) { controller.selected?.draft == firstDraft }
        let firstSelection = first.editor.selectedRange()
        let firstUndo = try #require(first.editor.undoManager)

        #expect(await controller.selectNotification(.init(triptychID: controller.triptychID, conversationID: secondID, event: .inputRequired)))
        try await settle(host) {
            composer(in: host)?.conversationID == secondID && findField(in: host) == nil
        }
        let second = try #require(composer(in: host))
        #expect(second.editor.string == "第二个未发送草稿")
        #expect(second !== first && first.completion == nil)
        second.editor.setSelectedRange(NSRange(location: second.editor.string.utf16.count, length: 0))
        second.editor.insertText("，补充", replacementRange: second.editor.selectedRange())
        try await settle(host) { controller.selected?.draft == "第二个未发送草稿，补充" }

        #expect(await controller.selectNotification(.init(triptychID: controller.triptychID, conversationID: firstID, event: .inputRequired)))
        try await settle(host) {
            composer(in: host)?.conversationID == firstID && findField(in: host) == nil
        }
        #expect(composer(in: host)?.editor.string == firstDraft)
        #expect(composer(in: host)?.editor === first.editor)
        #expect(composer(in: host)?.editor.selectedRange() == firstSelection)
        #expect(composer(in: host)?.editor.undoManager === firstUndo)
        #expect(controller.conversations.first { $0.id == secondID }?.draft == "第二个未发送草稿，补充")
        #expect(controller.conversations.allSatisfy { $0.messages.isEmpty })
        #expect(controller.connectionState == .disconnected)
        try await controller.flushPersistence()
    }

    @Test("An outgoing or hidden detail relinquishes Find focus without retargeting its native draft or Undo")
    func outgoingDetailKeepsItsConversationIdentity() async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/outgoing-identity-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let firstID = try #require(controller.selectedID)
        controller.editDraft("First native draft")
        controller.newConversation()
        let secondID = try #require(controller.selectedID)
        controller.editDraft("Second independent draft")
        controller.select(firstID)
        let nativeSession = AgentChatComposerSession(conversationID: firstID)
        let presentation = AgentChatDetailPresentation()
        let readingSession = AgentChatReadingSession()
        func detail(visible: Bool) -> some View {
            AgentChatConversationDetailView(
                controller: controller, isVisible: visible, addSelection: { _ in false },
                noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
                openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
                showConversationChanges: { _ in }, presentation: presentation,
                readingSession: readingSession, nativeSession: nativeSession,
                focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in }, showList: {},
                newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
                showAccountUsage: {}, diagnosticsPresentation: .constant(nil))
        }
        let host = NSHostingView(rootView: AnyView(detail(visible: true)))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { nativeSession.host.window === window && nativeSession.host.editor.isEditable }
        let editor = nativeSession.host.editor
        let undo = try #require(editor.undoManager)
        undo.beginUndoGrouping()
        editor.insertText(" edited", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
        undo.endUndoGrouping()
        editor.breakUndoCoalescing()
        editor.setSelectedRange(NSRange(location: 2, length: 4))
        let retained = editor.string
        let selection = editor.selectedRange()
        try #require(undo.canUndo)
        presentation.showsFind = true
        presentation.findFocusRequest = UUID()
        try await settle(host) {
            guard let field = findField(in: host), let fieldEditor = field.currentEditor() else { return false }
            return field.isEnabled && window.firstResponder === fieldEditor
        }
        let find = try #require(findField(in: host))
        let findEditor = try #require(find.currentEditor())

        // Keep A's actual detail mounted while its observed controller selects B,
        // as happens during the outgoing page's navigation transition.
        controller.select(secondID)
        try await settle(host) { !editor.isEditable && !find.isEnabled && window.firstResponder !== findEditor }
        #expect(nativeSession.conversationID == firstID && nativeSession.host.conversationID == firstID)
        #expect(editor.string == retained && editor.selectedRange() == selection)
        #expect(editor.undoManager === undo && undo.canUndo)
        #expect(controller.conversations.first { $0.id == firstID }?.draft == retained)
        #expect(controller.conversations.first { $0.id == secondID }?.draft == "Second independent draft")
        controller.select(firstID)
        try await settle(host) { editor.isEditable && find.isEnabled }

        // The same native field also relinquishes focus when its current detail
        // becomes hidden, independently of the selected-conversation guard.
        try #require(window.makeFirstResponder(find))
        let resumedFindEditor = try #require(find.currentEditor())
        try #require(window.firstResponder === resumedFindEditor)
        host.rootView = AnyView(detail(visible: false))
        try await settle(host) { !find.isEnabled && window.firstResponder !== resumedFindEditor }
        #expect(findField(in: host) === find)
        #expect(editor.string == retained && editor.selectedRange() == selection)
        #expect(editor.undoManager === undo && undo.canUndo)
        #expect(controller.conversations.first { $0.id == firstID }?.draft == retained)
        #expect(controller.conversations.first { $0.id == secondID }?.draft == "Second independent draft")
        host.rootView = AnyView(detail(visible: true))
        try await settle(host) { editor.isEditable && find.isEnabled }
        #expect(window.firstResponder === find.currentEditor())
        undo.undo()
        #expect(editor.string == "First native draft" && controller.selected?.draft == "First native draft")
        try await controller.flushPersistence()
    }

    @Test("A hidden explicit focus intent is consumed once and a historical handoff never refocuses on visibility")
    func visibilityUsesOnlyPendingFocusIntent() async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/focus-intent-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let nativeSession = AgentChatComposerSession(conversationID: controller.selectedID)
        let presentation = AgentChatDetailPresentation()
        let readingSession = AgentChatReadingSession()
        var pendingFocus: UUID? = UUID()
        var consumed = 0
        func detail(visible: Bool) -> some View {
            AgentChatConversationDetailView(
                controller: controller, isVisible: visible, addSelection: { _ in false },
                noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
                openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
                showConversationChanges: { _ in }, presentation: presentation,
                readingSession: readingSession, nativeSession: nativeSession,
                focusRequest: pendingFocus,
                consumeFocusRequest: { id in
                    if pendingFocus == id {
                        pendingFocus = nil
                        consumed += 1
                    }
                }, replyNavigation: nil, openReply: { _ in }, showList: {}, newConversation: {},
                didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {}, diagnosticsPresentation: .constant(nil))
        }
        let host = NSHostingView(rootView: AnyView(detail(visible: false)))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        try await settle(host) { nativeSession.host.window === window }
        #expect(consumed == 0 && pendingFocus != nil && !presentation.messageIsFocused)
        host.rootView = AnyView(detail(visible: true))
        try await settle(host) { consumed == 1 && pendingFocus == nil && window.firstResponder === nativeSession.host.editor }
        host.rootView = AnyView(detail(visible: false))
        try await settle(host) { !presentation.messageIsFocused && window.firstResponder !== nativeSession.host.editor }
        controller.contextPresentationID = UUID()
        host.rootView = AnyView(detail(visible: true))
        host.layoutSubtreeIfNeeded()
        #expect(consumed == 1 && !presentation.messageIsFocused)
        #expect(window.firstResponder !== nativeSession.host.editor)
        try await controller.flushPersistence()
    }

    @Test("Remounting the same conversation restores its native reading anchor and refreshes retained Find results")
    func detailRemountKeepsReadingAndRefreshesFind() async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/sidebar-remount-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
        controller.connect(executable: fixture, home: controller.runtimeHome, helper: fixture)
        do {
            try await settle { controller.canSend || (controller.account != nil && controller.state == .ready) }
            controller.editDraft(String(repeating: "Synthetic retained passage for native reading continuity. 中文合成测试文字。\n\n", count: 24))
            controller.send()
            try await settle { !controller.isBusy && controller.selected?.messages.contains { $0.role == .assistant } == true }
            let conversationID = try #require(controller.selectedID)
            let firstMessage = try #require(controller.selected?.messages.first { $0.role == .user })
            let presentation = AgentChatDetailPresentation()
            presentation.showsFind = true
            presentation.find.query = "retained"
            presentation.findFocusRequest = UUID()
            presentation.find.refresh(messages: controller.selected?.messages ?? [], reset: true)
            let originalMatches = presentation.find.messageIDs.count
            #expect(originalMatches == 1)
            let session = AgentChatReadingSession()
            let nativeSession = AgentChatComposerSession(conversationID: conversationID)

            func detail() -> some View {
                AgentChatConversationDetailView(
                    controller: controller, isVisible: true, addSelection: { _ in false },
                    noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
                    openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
                    showConversationChanges: { _ in }, presentation: presentation, readingSession: session, nativeSession: nativeSession,
                    focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in }, showList: {},
                    newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
                    showAccountUsage: {}, diagnosticsPresentation: .constant(nil))
            }
            let host = NSHostingView(rootView: AnyView(detail()))
            let window = mount(host)
            defer {
                window.contentView = nil
                window.close()
            }
            try await settle(host) {
                guard let marker = session.markers[firstMessage.id]?.view,
                    let scroll = marker.enclosingScrollView, let document = scroll.documentView
                else { return false }
                return document.frame.height > scroll.contentView.bounds.height + 300
                    && abs(scroll.contentView.bounds.maxY - document.frame.height - scroll.contentInsets.bottom) < 1
                    && findField(in: host) != nil
            }
            #expect(!session.isRetainingPosition)
            #expect(session.viewportRequest == nil)
            #expect(window.firstResponder === findField(in: host)?.currentEditor())
            session.pause()
            session.anchor = .init(id: firstMessage.id, offset: -120)
            session.viewport?.reconcile()
            let retainedAnchor = try #require(session.anchor)

            // This is the real detail's unmount/remount boundary, not an
            // assertion that the shell's Back button was exercised.
            host.rootView = AnyView(Color.clear)
            try await settle(host) { session.viewport == nil && composer(in: host) == nil }
            controller.editDraft("Another retained question while the detail is absent")
            controller.send()
            try await settle {
                !controller.isBusy && controller.selected?.messages.filter { $0.role == .user }.count == 2
            }
            #expect(presentation.find.messageIDs.count == originalMatches)
            controller.editDraft("Unsent draft after background completion")
            host.rootView = AnyView(detail())
            try await settle(host) {
                presentation.find.messageIDs.count == originalMatches + 1
                    && composer(in: host)?.conversationID == conversationID
                    && session.markers[firstMessage.id]?.view != nil
            }
            try await settle(host) {
                session.viewport?.reconcile()
                guard let marker = session.markers[retainedAnchor.id]?.view,
                    let scroll = marker.enclosingScrollView, let document = scroll.documentView
                else { return false }
                let offset =
                    marker.convert(marker.bounds, to: document).minY
                    - scroll.contentView.bounds.minY - scroll.contentInsets.top
                return abs(offset - retainedAnchor.offset) < 2
            }
            #expect(session.isRetainingPosition)
            #expect(findField(in: host)?.stringValue == "retained")
            #expect(window.firstResponder === findField(in: host)?.currentEditor())
            #expect(composer(in: host)?.editor.string == "Unsent draft after background completion")
            try await controller.flushPersistence()
        } catch {
            await controller.disconnect()
            throw error
        }
        await controller.disconnect()
    }

    @Test("Retained readers keep their native identity and reading anchor through hidden resizing")
    func retainedTranscriptSurvivesHiddenResize() async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/retained-resize-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.messages = (0..<2).flatMap { index in
            [
                AgentChatMessage(id: "question-\(index)", role: .user, text: "Synthetic question \(index). 中文。"),
                AgentChatMessage(
                    id: "reply-\(index)", role: .assistant,
                    text: String(repeating: "A retained synthetic passage with **中文 and English**.\n\n", count: 12),
                    phase: .finalAnswer),
            ]
        }
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }
        let presentation = AgentChatDetailPresentation()
        let session = AgentChatReadingSession()
        let native = AgentChatComposerSession(conversationID: conversation.id)
        func detail(visible: Bool) -> some View {
            AgentChatConversationDetailView(
                controller: controller, isVisible: visible, addSelection: { _ in false }, noteChoices: [], addNote: { _, _ in },
                openReference: { _ in false }, openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
                showConversationChanges: { _ in }, presentation: presentation, readingSession: session, nativeSession: native,
                focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in }, showList: {},
                newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in }, showAccountUsage: {},
                diagnosticsPresentation: .constant(nil)
            )
            .environment(\.scholiumDocumentSurfaceVisibility, visible ? .active : .retained)
        }
        func readers(_ view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(readers)
        }
        let host = NSHostingView(rootView: AnyView(detail(visible: true)))
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }
        window.makeKeyAndOrderFront(nil)
        func verify(_ phase: String, _ predicate: () -> Bool) async throws {
            do { try await settle(host, until: predicate) } catch {
                print(
                    "CHAT_RETAINED_RESIZE phase=\(phase) readers=\(readers(host).count) initial=\(session.initialTranscriptPhase) request=\(session.viewportRequest != nil) input=\(native.host.editor.isEditable)"
                )
                throw error
            }
        }
        try await verify("initial") { session.initialTranscriptPhase == .visible && session.viewportRequest == nil && readers(host).count == 4 }
        let identities = Set(readers(host).map(ObjectIdentifier.init))
        let anchor = AgentChatReadingSession.Anchor(id: "reply-1", offset: -80)
        session.pause()
        session.anchor = anchor
        func anchorIsPositioned() -> Bool {
            guard let marker = session.markers[anchor.id]?.view, let scroll = marker.enclosingScrollView, let document = scroll.documentView else {
                return false
            }
            session.viewport?.reconcile()
            let offset = marker.convert(marker.bounds, to: document).minY - scroll.contentView.bounds.minY - scroll.contentInsets.top
            return abs(offset - anchor.offset) < 2
        }
        try await verify("anchor", anchorIsPositioned)
        host.rootView = AnyView(detail(visible: false))
        try await verify("hidden") { readers(host).allSatisfy(\.isHiddenOrHasHiddenAncestor) && native.host.isHidden }
        window.setContentSize(NSSize(width: 280, height: 640))
        host.layoutSubtreeIfNeeded()
        #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
        host.rootView = AnyView(detail(visible: true))
        try await verify("resumed") { readers(host).allSatisfy { !$0.isHiddenOrHasHiddenAncestor } && anchorIsPositioned() }
        #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
        #expect(session.anchor == anchor && session.viewportRequest == nil)
        #expect(controller.selected?.messages == conversation.messages)
        // Selection can change before the outgoing detail is dismantled. Its
        // transcript must never rebuild readers for the next conversation.
        controller.newConversation()
        let nextID = try #require(controller.selectedID)
        try await verify("outgoing") { !native.host.editor.isEditable }
        #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
        controller.select(conversation.id)
        controller.select(nextID)
        controller.select(conversation.id)
        try await verify("rapid-return") { native.host.editor.isEditable && anchorIsPositioned() }
        #expect(Set(readers(host).map(ObjectIdentifier.init)) == identities)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_CHAT_LONG_FIXTURE"] == "1"))
    func firstEntryOfLongConversationRecordsNativeViewportStability() async throws {
        _ = NSApplication.shared
        let root = repository.appendingPathComponent(".build/agent-chat-tests/long-entry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }

        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic long conversation"
        conversation.threadID = "synthetic-long-conversation"
        conversation.messages = (0..<36).flatMap { index in
            let turnID = "synthetic-turn-\(index)"
            var question = AgentChatMessage(
                id: "synthetic-question-\(index)", role: .user,
                text: "请继续核对第 \(index + 1) 组材料中的主张、依据与解释边界。")
            question.turnID = turnID
            var reply = AgentChatMessage(
                id: "synthetic-reply-\(index)", role: .assistant,
                text: "## 第 \(index + 1) 组核对\n\n"
                    + String(repeating: "这是一段用于测试首次进入聊天时 WebKit 阅读器逐步测量高度的合成回复。它包含中文、English、列表和表格，以便暴露布局稳定性问题。\n\n", count: 4)
                    + "- 保留来源文本。\n- 单独标出分析。\n\n"
                    + "| 项目 | 状态 |\n|---|---|\n| 原文 | 已保留 |\n| 解释 | 待核对 |\n",
                phase: .finalAnswer)
            reply.turnID = turnID
            return [question, reply]
        }
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        try await storage.save([conversation])

        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle { controller.isLoaded }

        let presentation = AgentChatDetailPresentation()
        let session = AgentChatReadingSession()
        let nativeSession = AgentChatComposerSession(conversationID: conversation.id)
        let projection = AgentChatTimelineProjection(conversation.messages)
        let detail = AgentChatConversationDetailView(
            controller: controller, isVisible: true, addSelection: { _ in false },
            noteChoices: [], addNote: { _, _ in }, openReference: { _ in false },
            openAttachment: { _ in }, showInLibrary: { _ in }, showChanges: { _ in },
            showConversationChanges: { _ in }, presentation: presentation, readingSession: session, nativeSession: nativeSession,
            focusRequest: nil, consumeFocusRequest: { _ in }, replyNavigation: nil, openReply: { _ in }, showList: {},
            newConversation: {}, didRestoreConversation: {}, renameConversation: { _ in },
            showAccountUsage: {}, diagnosticsPresentation: .constant(nil))
        let host = NSHostingView(rootView: AnyView(detail))
        let entryStart = ContinuousClock.now
        let window = mount(host)
        defer {
            window.contentView = nil
            window.close()
        }

        let latestID = try #require(projection.ids.last)
        var samples: [CGFloat] = []
        var visibleSamples: [CGFloat] = []
        var firstVisible: Duration?
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while ContinuousClock.now < deadline {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            if let marker = session.markers[latestID]?.view,
                let scroll = marker.enclosingScrollView, let document = scroll.documentView
            {
                samples.append(scroll.contentView.bounds.minY)
                if session.isInitialTranscriptReady {
                    visibleSamples.append(scroll.contentView.bounds.minY)
                    if firstVisible == nil { firstVisible = entryStart.duration(to: .now) }
                }
                if samples.count > 1, document.frame.height > scroll.contentView.bounds.height + 300,
                    session.viewportRequest == nil, abs(scroll.contentView.bounds.maxY - document.frame.height - scroll.contentInsets.bottom) < 2
                {
                    // Keep sampling after the first valid bottom position so a later
                    // reader measurement cannot hide a second jump.
                    if samples.count > 80 { break }
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let scroll = try #require(session.markers[latestID]?.view?.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let jumps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        let maximumJump = jumps.max() ?? 0
        let visibleJumps = zip(visibleSamples, visibleSamples.dropFirst()).map { abs($1 - $0) }
        let maximumVisibleJump = visibleJumps.max() ?? 0
        let bottomDistance = max(0, document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom)
        let changedSamples = samples.enumerated().filter { index, value in
            index == 0 || abs(value - samples[index - 1]) > 1
        }.map { "\($0.offset):\($0.element)" }.joined(separator: ",")
        print(
            "CHAT_LONG_ENTRY messages=\(conversation.messages.count) samples=\(samples.count) "
                + "max_jump=\(maximumJump) visible_samples=\(visibleSamples.count) "
                + "max_visible_jump=\(maximumVisibleJump) bottom_distance=\(bottomDistance) "
                + "first_visible=\(String(describing: firstVisible)) changed=\(changedSamples)"
        )
        #expect(!samples.isEmpty)
        #expect(!visibleSamples.isEmpty)
        #expect(maximumVisibleJump < 2)
        #expect(session.viewportRequest == nil)
        #expect(bottomDistance < 2)
    }

    private func mount<Content: View>(_ host: NSHostingView<Content>) -> NSWindow {
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }

    private func settle(_ host: NSView? = nil, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while true {
            host?.window?.layoutIfNeeded()
            host?.layoutSubtreeIfNeeded()
            if condition() { return }
            try #require(ContinuousClock.now < deadline, "Chat sidebar fixture did not reach its expected native state")
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func composer(in view: NSView) -> AgentChatComposerHost? {
        (view as? AgentChatComposerHost) ?? view.subviews.lazy.compactMap { composer(in: $0) }.first
    }

    private func findField(in view: NSView) -> NSSearchField? {
        if let field = view as? NSSearchField, field.accessibilityIdentifier() == "scholium.chat.find.query" { return field }
        return view.subviews.lazy.compactMap { findField(in: $0) }.first
    }
}
