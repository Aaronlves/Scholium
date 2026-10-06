import ScholiumContracts
import SwiftUI

struct AgentChatReplyNavigation: Equatable {
    let id = UUID()
    let conversationID: UUID
    let messageID: String
}

private struct AgentChatOutgoingPageInteraction: ViewModifier {
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(!isInteractive)
    }
}

/// Window-local routing and retained page presentation; runtime state stays in the controller.
struct AgentChatView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @ObservedObject var controller: AgentChatController
    let transcriptReaderID: UUID
    let isVisible: Bool
    let addSelection: (UUID) async -> Bool
    let noteChoices: [WorkspaceCatalogNote]
    let prepareNotes: @MainActor (UUID) throws -> (@MainActor (WorkspaceCatalogNote) async throws -> Void)
    let openReference: (URL) -> Bool
    let openAttachment: (AgentChatAttachment) -> Void
    let showInLibrary: (URL) -> Void
    let showChanges: (UUID) -> Void
    let showConversationChanges: ([UUID]) -> Void
    var changes: [AgentChange]? = nil
    var pendingDocuments: [DocumentChangeSummary]? = nil
    var changesError: String? = nil
    @State private var showsConversationList = true
    @State private var hasPresentedDetail = false
    @State private var presentedConversationID: UUID?
    @State private var listState = AgentChatConversationListState()
    @State private var detailStore = AgentChatDetailPresentationStore()
    private var detailPresentation: AgentChatDetailPresentation {
        detailStore.presentation(for: controller.selectedID)
    }
    @State private var readingStore = AgentChatReadingStore()
    @State private var composerStore = AgentChatComposerSessionStore()
    @State private var focusRequest: UUID?
    @State private var replyNavigation: AgentChatReplyNavigation?
    @State private var showsAccountUsage = false
    @State private var diagnosticsPresentation: AgentChatDiagnosticsPresentation?
    @State private var renameID: UUID?
    @State private var showsRename = false
    @State private var renameTitle = ""

    private var navigationAnimation: Animation? {
        isVisible && !reduceMotion && activeState != .inactive ? .smooth(duration: 0.24) : nil
    }

    private func pageTransition(from edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge),
            removal: .move(edge: edge).combined(
                with: .modifier(
                    active: AgentChatOutgoingPageInteraction(isInteractive: false),
                    identity: AgentChatOutgoingPageInteraction(isInteractive: true))))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if showsConversationList { listPage }
                // Retain one visited page, rather than recreating its readers
                // on Back/reopen. A different selection replaces that lifetime.
                if hasPresentedDetail && (!showsConversationList || presentedConversationID == controller.selectedID) {
                    detailPage
                        .offset(x: showsConversationList ? geometry.size.width : 0)
                        .opacity(showsConversationList ? 0 : 1)
                        .environment(\.scholiumDocumentSurfaceVisibility, isVisible && !showsConversationList ? .active : .retained)
                        .id(controller.selectedID)
                        // An already hidden page has no outgoing transition.
                        .transition(showsConversationList ? .identity : pageTransition(from: .trailing))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat")
        .sheet(isPresented: $showsAccountUsage) {
            AgentChatAccountUsageView(
                quotas: controller.quotas, error: controller.quotaError,
                isRefreshing: controller.isRefreshingQuota, canRefresh: controller.account != nil,
                refresh: controller.refreshQuota, close: { showsAccountUsage = false })
        }
        .alert("Rename Conversation", isPresented: $showsRename) {
            TextField("Conversation Title", text: $renameTitle)
            Button("Cancel", role: .cancel) { renameID = nil }
            Button("Rename") {
                if let renameID { controller.rename(renameTitle, in: renameID) }
                renameID = nil
            }.disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let id = controller.selectedID, !controller.preparingMaterials.contains(id), !urls.isEmpty,
                urls.allSatisfy(\.isFileURL)
            else { return false }
            Task { @MainActor in await controller.addLocalFiles(urls, to: id) }
            return true
        }
        .onChange(of: showsConversationList) { _, _ in
            diagnosticsPresentation = nil
            markVisibleConversationRead()
        }
        .onChange(of: controller.selectedID) { _, id in
            if showsConversationList { hasPresentedDetail = false } else { presentedConversationID = id }
            _ = detailStore.presentation(for: id)
            diagnosticsPresentation = nil
            renameID = nil
            showsRename = false
            markVisibleConversationRead()
        }
        .onChange(of: controller.conversations.map(\.id)) { _, ids in
            readingStore.retain(Set(ids))
            composerStore.retain(Set(ids))
        }
        .onChange(of: controller.selected?.unreadAt) { _, _ in markVisibleConversationRead() }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                PerformanceProbe.shared.cancelChatEntry()
                diagnosticsPresentation = nil
                showsAccountUsage = false
                showsRename = false
            }
            markVisibleConversationRead()
        }
        .onAppear { markVisibleConversationRead() }
        .onDisappear {
            PerformanceProbe.shared.cancelChatEntry()
            controller.displayTranscript(nil, readerID: transcriptReaderID)
        }
        .onChange(of: controller.contextPresentationID, initial: true) { _, request in
            guard request != nil else { return }
            showDetail(animated: false)
            focusRequest = UUID()
        }
        .onChange(of: controller.selected?.attachments.count) { old, new in
            if (new ?? 0) > (old ?? 0) {
                showDetail(animated: false)
                focusRequest = UUID()
            }
        }
    }

    private var listPage: some View {
        AgentChatConversationListView(
            controller: controller, state: listState,
            showConversation: { showDetail() },
            newConversation: newConversation, renameConversation: renameConversation,
            showConversationChanges: showConversationChanges,
            showAccountUsage: { showsAccountUsage = true },
            diagnosticsPresentation: $diagnosticsPresentation
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(pageTransition(from: .leading))
    }

    private var detailPage: some View {
        AgentChatConversationDetailView(
            controller: controller, isVisible: isVisible && !showsConversationList,
            addSelection: addSelection, noteChoices: noteChoices, prepareNotes: prepareNotes,
            openReference: openReference, openAttachment: openAttachment,
            showInLibrary: showInLibrary, showChanges: showChanges,
            showConversationChanges: showConversationChanges,
            changes: changes, pendingDocuments: pendingDocuments,
            changesError: changesError,
            presentation: detailPresentation,
            readingSession: readingStore.session(for: controller.selectedID),
            nativeSession: composerStore.session(for: controller.selectedID),
            focusRequest: focusRequest,
            consumeFocusRequest: { if focusRequest == $0 { focusRequest = nil } },
            replyNavigation: replyNavigation,
            openReply: { target in
                controller.select(target.conversationID)
                replyNavigation = target
            },
            showList: {
                detailPresentation.contextAnchor = nil
                detailPresentation.completion.dismiss()
                showList()
            },
            newConversation: newConversation,
            didRestoreConversation: { listState.showsArchived = false },
            renameConversation: renameConversation,
            showAccountUsage: { showsAccountUsage = true },
            diagnosticsPresentation: $diagnosticsPresentation
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newConversation() {
        if controller.selected?.messages.isEmpty != true
            || controller.selected?.draft.isEmpty != true
            || controller.selected?.attachments.isEmpty != true
            || controller.selected?.localMaterials.isEmpty != true
            || controller.selected?.draftReplyQuotes?.isEmpty == false
            || controller.selected?.selectedMethods?.isEmpty == false
            || controller.selected?.queuedMessages.isEmpty == false
            || controller.selected?.isAvailable == false
        {
            controller.newConversation()
        }
        listState.showsArchived = false
        showDetail()
        focusRequest = UUID()
    }

    private func showList() {
        PerformanceProbe.shared.cancelChatEntry()
        detailPresentation.messageIsFocused = false
        withAnimation(navigationAnimation) { showsConversationList = true }
    }

    private func showDetail(animated: Bool = true) {
        withAnimation(animated ? navigationAnimation : nil) {
            presentedConversationID = controller.selectedID
            hasPresentedDetail = true
            showsConversationList = false
        }
    }

    private func renameConversation(_ conversation: AgentChatConversation) {
        renameTitle = conversation.title
        renameID = conversation.id
        showsRename = true
    }

    private func markVisibleConversationRead() {
        controller.displayTranscript(
            isVisible && !showsConversationList ? controller.selectedID : nil,
            readerID: transcriptReaderID)
    }
}
