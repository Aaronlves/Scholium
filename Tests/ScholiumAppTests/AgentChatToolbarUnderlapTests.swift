import AppKit
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat toolbar underlap in the native workspace", .serialized)
@MainActor
struct AgentChatToolbarUnderlapTests {
    private final class Hydration {
        var states: [String: Bool] = [:]
    }

    @Test("Chat keeps native chrome input and reading ownership while its viewport extends under the toolbar")
    func nativeWorkspaceUnderlapPreservesReading() async throws {
        _ = NSApplication.shared
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/toolbar-underlap-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        var conversation = AgentChatConversation(triptychID: triptychID)
        conversation.title = "Synthetic toolbar underlap"
        conversation.draft = "Retained unsent draft"
        conversation.messages = (0..<3).flatMap { index in
            var question = AgentChatMessage(id: "question-\(index)", role: .user, text: "Synthetic question \(index)")
            question.turnID = "turn-\(index)"
            var reply = AgentChatMessage(
                id: "reply-\(index)", role: .assistant,
                text: "**Synthetic passage \(index)**\n\n"
                    + String(repeating: "Retained research reading with 中文 and English across a native window resize.\n\n", count: 10),
                phase: .finalAnswer)
            reply.turnID = question.turnID
            return [question, reply]
        }
        let ids = AgentChatTimelineProjection(conversation.messages).ids
        let initialLatestID = try #require(ids.last)
        try await AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString)).save([conversation])
        let controller = fixtureChatController(triptychID: triptychID, root: root) { request in
            try! .init(requestID: request.requestID, result: .object([:]))
        }
        try await settle(
            stage: "storage_load",
            diagnostic: {
                "loaded=\(controller.isLoaded) conversations=\(controller.conversations.count) selected=\(controller.selectedID != nil)"
            }
        ) { controller.isLoaded }
        let chat = AgentChatView(
            controller: controller, transcriptReaderID: UUID(), isVisible: true,
            addSelection: { _ in false }, noteChoices: [], prepareNotes: { _ in { _ in } },
            openReference: { _ in false }, openAttachment: { _, _ in }, showInLibrary: { _ in },
            showChanges: { _ in }, showConversationChanges: { _ in })
        let hydration = Hydration()
        let probedChat = AnyView(
            chat.onPreferenceChange(AgentChatReplyHydrationPreference.self) {
                hydration.states = $0
            })
        let split = ScholiumWorkspaceSplitView<EmptyView, AnyView, Color, EmptyView>.Controller(
            initialLibraryVisible: true, initialApparatusVisible: false,
            documentTabs: [], selectedDocumentTabID: nil, selectDocumentTab: { _ in },
            libraryVisibilityDidChange: { _ in }, researchInspectorVisibilityDidChange: { _ in },
            splitControllerDidAttach: { _ in }, splitControllerDidDetach: { _ in },
            library: EmptyView(), chat: probedChat, sidebarContent: .chat,
            document: Color.blue, apparatus: EmptyView())
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "ChatToolbarUnderlapTests")
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.contentViewController = split
        // Installing a controller can apply its preferred size to the window.
        // Establish the fixture's starting geometry after that native handoff.
        window.setContentSize(.init(width: 1200, height: 760))
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentViewController = nil
            window.toolbar = nil
            window.close()
        }
        split.splitView.setPosition(320, ofDividerAt: 0)
        let sidebar = try #require(
            split.splitViewItems.first?.viewController as? ScholiumSidebarViewController<EmptyView, AnyView>)
        let chatHost = sidebar.chatHost.view
        try await settle(
            split.view, stage: "list_safe_area",
            diagnostic: {
                "search_fields=\(descendants(chatHost).filter { $0 is NSSearchField }.count) host=\(chatHost.frame) safe=\(chatHost.safeAreaInsets) layout=\(window.contentLayoutRect)"
            }
        ) {
            descendants(chatHost).contains { $0 is NSSearchField }
                && chatHost.safeAreaInsets.top > 0
        }
        let search = try #require(descendants(chatHost).compactMap { $0 as? NSSearchField }.first)
        // A fixed native top control stays below chrome even though its host
        // owns the complete Sidebar height. The host keeps inherited safe areas.
        #expect(search.convert(search.bounds, to: nil).maxY <= window.contentLayoutRect.maxY + 1)
        #expect(abs(chatHost.frame.maxY - sidebar.view.bounds.maxY) < 1)
        #expect(chatHost.safeAreaInsets.top > 0)
        #expect(sidebar.view.clipsToBounds)

        #expect(
            await controller.selectNotification(
                .init(triptychID: triptychID, conversationID: conversation.id, event: .inputRequired)))
        try await settle(
            split.view, stage: "detail_mount",
            diagnostic: {
                "viewports=\(descendants(chatHost).filter { $0 is AgentChatTranscriptViewport.View }.count) composers=\(descendants(chatHost).filter { $0 is AgentChatComposerHost }.count) context_request=\(controller.contextPresentationID != nil) selected=\(controller.selectedID == conversation.id)"
            }
        ) {
            descendants(chatHost).contains { $0 is AgentChatTranscriptViewport.View }
                && descendants(chatHost).contains { $0 is AgentChatComposerHost }
        }
        let viewport = try #require(descendants(chatHost).compactMap { $0 as? AgentChatTranscriptViewport.View }.first)
        let session = viewport.session
        let scroll = try #require(viewport.enclosingScrollView)
        let document = try #require(scroll.documentView)
        let composer = try #require(descendants(chatHost).compactMap { $0 as? AgentChatComposerHost }.first)
        func atLatest() -> Bool {
            session.initialTranscriptPhase == .visible && session.viewportRequest == nil
                && abs(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) < 2
        }
        func readingDiagnostic() -> String {
            let markerIDs = session.markers.keys.sorted()
            let readyIDs = hydration.states.filter { $0.value }.keys.sorted()
            let currentIDs = AgentChatTimelineProjection(controller.selected?.messages ?? []).ids
            let responder = window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            return "phase=\(session.initialTranscriptPhase) request=\(String(describing: session.viewportRequest)) position=\(session.position) "
                + "markers=\(markerIDs.count):\(markerIDs.prefix(12).joined(separator: ",")) hydrated=\(readyIDs.prefix(12).joined(separator: ",")) projected=\(ids.joined(separator: ",")) history=\(session.history.range(in: currentIDs)) "
                + "document=\(document.frame) clip=\(scroll.contentView.bounds) inset=\(scroll.contentInsets) bottom_distance=\(document.frame.height - scroll.contentView.bounds.maxY + scroll.contentInsets.bottom) "
                + "responder=\(responder) editor_focused=\(window.firstResponder === composer.editor) key=\(window.isKeyWindow) "
                + "composer_window=\(composer.window === window) editable=\(composer.editor.isEditable) focus_value=\(composer.focusValue) requested_focus=\(String(describing: composer.requestedFocus))"
        }
        // Notification presentation explicitly requests composer focus in the
        // retained Chat shell; geometry readiness and focus are separate stages.
        try await settle(split.view, stage: "initial_read_hydration", diagnostic: readingDiagnostic) {
            atLatest() && hydration.states[initialLatestID] == true
                && session.markers[initialLatestID]?.view?.window === window
                && session.markers[initialLatestID]?.view?.enclosingScrollView === scroll
        }
        try await settle(split.view, stage: "notification_composer_focus", diagnostic: readingDiagnostic) {
            window.firstResponder === composer.editor
        }
        let draftSelection = composer.editor.selectedRange()
        let undoManager = composer.editor.undoManager
        func expectNativeBoundaries() {
            let frame = scroll.convert(scroll.bounds, to: nil)
            // This proves native drawing space, not the appearance of the blur.
            #expect(frame.maxY > window.contentLayoutRect.maxY + 1)
            #expect(scroll.contentInsets.top >= chatHost.safeAreaInsets.top + ScholiumSidebarLayout.headerHeight - 1)
            let toolbarLocation = NSPoint(
                x: frame.midX, y: (window.contentLayoutRect.maxY + frame.maxY) / 2)
            let toolbarPoint = sidebar.view.convert(toolbarLocation, from: nil)
            #expect(sidebar.view.hitTest(sidebar.view.convert(toolbarPoint, to: sidebar.view.superview)) == nil)
        }
        expectNativeBoundaries()

        // Latest mounts a bounded history window. Explicit navigation reveals
        // the earlier row before requiring its reader or native marker.
        session.navigate(to: "reply-0", in: ids)
        try await settle(split.view, stage: "earlier_marker_hydration", diagnostic: readingDiagnostic) {
            session.viewportRequest == nil && session.isRetainingPosition
                && hydration.states["reply-0"] == true
                && session.markers["reply-0"]?.view?.window === window
                && session.markers["reply-0"]?.view?.enclosingScrollView === scroll
        }
        let earlier = try #require(session.markers["reply-0"]?.view)
        func offset() -> CGFloat {
            earlier.convert(earlier.bounds, to: document).minY
                - scroll.contentView.bounds.minY - scroll.contentInsets.top
        }
        var previousDocumentFrame = NSRect.zero
        var previousClipBounds = NSRect.zero
        var previousTopInset: CGFloat = 0
        var previousBottomInset: CGFloat = 0
        try await settle(
            split.view, stage: "earlier_navigation",
            diagnostic: {
                readingDiagnostic() + " offset=\(offset()) expected_offset=0"
            }, stablePasses: 3
        ) {
            let unchanged =
                previousDocumentFrame == document.frame
                && previousClipBounds == scroll.contentView.bounds
                && previousTopInset == scroll.contentInsets.top
                && previousBottomInset == scroll.contentInsets.bottom
            previousDocumentFrame = document.frame
            previousClipBounds = scroll.contentView.bounds
            previousTopInset = scroll.contentInsets.top
            previousBottomInset = scroll.contentInsets.bottom
            return unchanged && session.viewportRequest == nil && session.isRetainingPosition
                && abs(offset()) < 1
        }
        let retainedOffset = offset()
        let originalViewportHeight = scroll.contentView.bounds.height
        let originalWindowFrame = window.frame
        let originalContentBounds = try #require(window.contentView).bounds
        // Native presentation can constrain the requested starting size. Apply
        // the original 160-point reduction to the realized content geometry.
        let resizedContentHeight = originalContentBounds.height - 160
        try #require(resizedContentHeight > 0)
        window.setContentSize(.init(width: 1000, height: resizedContentHeight))
        split.splitView.setPosition(280, ofDividerAt: 0)
        try await settle(
            split.view, stage: "retained_resize",
            diagnostic: {
                readingDiagnostic() + " offset=\(offset()) expected_offset=\(retainedOffset) original_height=\(originalViewportHeight) requested_height=\(resizedContentHeight)"
                    + " before_frame=\(originalWindowFrame) before_content=\(originalContentBounds)"
                    + " frame=\(window.frame) content=\(String(describing: window.contentView?.bounds))"
                    + " layout=\(window.contentLayoutRect) screen=\(String(describing: window.screen?.visibleFrame))"
            }
        ) {
            scroll.contentView.bounds.height < originalViewportHeight - 100
                && abs(offset() - retainedOffset) < 2 && session.isRetainingPosition
                && earlier.enclosingScrollView === scroll
        }
        print(
            "CHAT_TOOLBAR_RESIZE original_viewport_height=\(originalViewportHeight) viewport_height=\(scroll.contentView.bounds.height) requested_height=\(resizedContentHeight)"
                + " before_frame=\(originalWindowFrame) before_content=\(originalContentBounds)"
                + " frame=\(window.frame) content=\(String(describing: window.contentView?.bounds))"
                + " layout=\(window.contentLayoutRect) screen=\(String(describing: window.screen?.visibleFrame))")
        expectNativeBoundaries()
        controller.update {
            $0.messages.append(.init(id: "arrival-retaining", role: .user, text: "Synthetic arrival while reading earlier."))
        }
        try await settle(
            split.view, stage: "retained_arrival_hydration",
            diagnostic: {
                readingDiagnostic()
                    + " arrival_hydrated=\(String(describing: hydration.states["arrival-retaining"])) offset=\(offset()) expected_offset=\(retainedOffset)"
            }, stablePasses: 3
        ) {
            let updatedIDs = AgentChatTimelineProjection(controller.selected?.messages ?? []).ids
            guard let arrivalIndex = updatedIDs.firstIndex(of: "arrival-retaining") else { return false }
            let arrivalIsMounted = session.history.range(in: updatedIDs).contains(arrivalIndex)
            let arrivalIsReady =
                !arrivalIsMounted
                || hydration.states["arrival-retaining"] == true
                    && session.markers["arrival-retaining"]?.view?.enclosingScrollView === scroll
            return arrivalIsReady && hydration.states["reply-0"] == true
                && earlier.enclosingScrollView === scroll && session.viewportRequest == nil
                && abs(offset() - retainedOffset) < 2 && session.isRetainingPosition
        }
        session.latest(in: AgentChatTimelineProjection(controller.selected?.messages ?? []).ids)
        try await settle(split.view, stage: "return_to_latest", diagnostic: readingDiagnostic) {
            atLatest() && !session.isRetainingPosition
        }
        controller.update {
            $0.messages.append(
                .init(
                    id: "arrival-following", role: .assistant,
                    text: String(repeating: "Synthetic new reply keeps latest following.\n\n", count: 4),
                    phase: .finalAnswer))
        }
        try await settle(
            split.view, stage: "following_arrival_hydration",
            diagnostic: {
                readingDiagnostic() + " arrival_hydrated=\(String(describing: hydration.states["arrival-following"]))"
            }
        ) {
            hydration.states["arrival-following"] == true
                && session.markers["arrival-following"]?.view != nil && atLatest() && !session.isRetainingPosition
        }
        #expect(sidebar.chatHost.view === chatHost)
        #expect(descendants(chatHost).compactMap { $0 as? AgentChatComposerHost }.first === composer)
        #expect(descendants(chatHost).compactMap { $0 as? AgentChatTranscriptViewport.View }.first === viewport)
        #expect(viewport.enclosingScrollView === scroll)
        #expect(window.firstResponder === composer.editor)
        #expect(composer.editor.string == conversation.draft)
        #expect(composer.editor.selectedRange() == draftSelection)
        #expect(composer.editor.undoManager === undoManager)
        print("CHAT_TOOLBAR_UNDERLAP native_chrome=true retained_resize=true retained_arrival=true latest_arrival=true")
        try await controller.flushPersistence()
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private func settle(
        _ view: NSView? = nil, stage: String, diagnostic: () -> String,
        stablePasses: Int = 1,
        until condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var passingSamples = 0
        while true {
            view?.window?.layoutIfNeeded()
            view?.layoutSubtreeIfNeeded()
            passingSamples = condition() ? passingSamples + 1 : 0
            if passingSamples >= stablePasses { return }
            if ContinuousClock.now >= deadline {
                print("CHAT_TOOLBAR_TIMEOUT stage=\(stage) \(diagnostic())")
            }
            try #require(ContinuousClock.now < deadline, "Chat toolbar fixture did not reach stage: \(stage)")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
