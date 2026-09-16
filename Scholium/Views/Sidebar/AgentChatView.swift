import ScholiumContracts
import SwiftUI

struct AgentChatReplyNavigation: Equatable {
    let id = UUID()
    let conversationID: UUID
    let messageID: String
}

/// Window-local routing and retained page presentation; runtime state stays in the controller.
struct AgentChatView: View {
    @ObservedObject var controller: AgentChatController
    let isVisible: Bool
    let addSelection: (UUID) async -> Bool
    let noteChoices: [WorkspaceCatalogNote]
    let addNote: (WorkspaceCatalogNote, UUID) async throws -> Void
    let openReference: (URL) -> Bool
    let openAttachment: (AgentChatAttachment) -> Void
    let showInLibrary: (URL) -> Void
    let showChanges: (UUID) -> Void
    let showConversationChanges: ([UUID]) -> Void
    var changes: [AgentChange]? = nil
    var changesError: String? = nil
    @State private var showsConversationList = true
    @State private var listState = AgentChatConversationListState()
    @State private var detailStore = AgentChatDetailPresentationStore()
    private var detailPresentation: AgentChatDetailPresentation {
        detailStore.presentation(for: controller.selectedID)
    }
    @State private var readingStore = AgentChatReadingStore()
    @State private var focusRequest: UUID?
    @State private var replyNavigation: AgentChatReplyNavigation?
    @State private var showsAccountUsage = false
    @State private var showsDiagnostics = false
    @State private var diagnosticMessageID: String?
    @State private var diagnosticError: String?
    @State private var renameID: UUID?
    @State private var showsRename = false
    @State private var renameTitle = ""

    var body: some View {
        Group {
            if showsConversationList {
                AgentChatConversationListView(
                    controller: controller, state: listState,
                    showConversation: { showsConversationList = false },
                    newConversation: newConversation, renameConversation: renameConversation,
                    showConversationChanges: showConversationChanges,
                    showAccountUsage: { showsAccountUsage = true },
                    showDiagnostics: { presentDiagnostics(error: $0) }
                )
            } else {
                AgentChatConversationDetailView(
                    controller: controller, isVisible: isVisible,
                    addSelection: addSelection, noteChoices: noteChoices, addNote: addNote,
                    openReference: openReference, openAttachment: openAttachment,
                    showInLibrary: showInLibrary, showChanges: showChanges,
                    showConversationChanges: showConversationChanges,
                    changes: changes, changesError: changesError,
                    presentation: detailPresentation,
                    readingSession: readingStore.session(for: controller.selectedID),
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
                        showsConversationList = true
                    },
                    newConversation: newConversation,
                    didRestoreConversation: { listState.showsArchived = false },
                    renameConversation: renameConversation,
                    showAccountUsage: { showsAccountUsage = true },
                    showDiagnostics: { presentDiagnostics(messageID: $0, error: $1) }
                )
                .id(controller.selectedID)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat")
        .popover(isPresented: $showsDiagnostics) {
            AgentChatDiagnosticsView(
                messages: controller.selected?.messages ?? [], selectedID: diagnosticMessageID,
                error: diagnosticError ?? controller.error, close: { showsDiagnostics = false })
        }
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
        .onChange(of: showsConversationList) { _, _ in markVisibleConversationRead() }
        .onChange(of: controller.selectedID) { _, id in
            _ = detailStore.presentation(for: id)
            showsDiagnostics = false
            diagnosticError = nil
            renameID = nil
            showsRename = false
            markVisibleConversationRead()
        }
        .onChange(of: controller.conversations.map(\.id)) { _, ids in readingStore.retain(Set(ids)) }
        .onChange(of: controller.selected?.unreadAt) { _, _ in markVisibleConversationRead() }
        .onChange(of: isVisible) { _, visible in
            if !visible {
                showsDiagnostics = false
                diagnosticError = nil
            }
            markVisibleConversationRead()
        }
        .onAppear { markVisibleConversationRead() }
        .onChange(of: controller.contextPresentationID, initial: true) { _, request in
            guard request != nil else { return }
            showsConversationList = false
            focusRequest = UUID()
        }
        .onChange(of: controller.selected?.attachments.count) { old, new in
            if (new ?? 0) > (old ?? 0) {
                showsConversationList = false
                focusRequest = UUID()
            }
        }
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
        showsConversationList = false
        focusRequest = UUID()
    }

    private func renameConversation(_ conversation: AgentChatConversation) {
        renameTitle = conversation.title
        renameID = conversation.id
        showsRename = true
    }

    private func presentDiagnostics(messageID: String? = nil, error: String? = nil) {
        diagnosticMessageID = messageID
        diagnosticError = error
        showsDiagnostics = true
    }

    private func markVisibleConversationRead() {
        if isVisible, !showsConversationList, let id = controller.selectedID {
            controller.setUnread(id, unread: false)
        }
    }
}
