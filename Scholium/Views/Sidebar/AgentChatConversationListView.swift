import Observation
import ScholiumContracts
import SwiftUI

/// Retained by the window shell while the list is not mounted.
/// This is presentation state only; conversations remain controller-owned.
@MainActor @Observable
final class AgentChatConversationListState {
    var query = ""
    var filter = AgentChatListFilter.all
    var showsArchived = false {
        didSet { if oldValue != showsArchived { filter = .all } }
    }
}

struct AgentChatConversationListView: View {
    @ObservedObject var controller: AgentChatController
    @Bindable var state: AgentChatConversationListState
    let showConversation: () -> Void
    let newConversation: () -> Void
    let renameConversation: (AgentChatConversation) -> Void
    let showConversationChanges: ([UUID]) -> Void
    let showAccountUsage: () -> Void
    let showDiagnostics: (String) -> Void
    @State private var conversationOrder = AgentChatListOrder()
    @State private var deletionTarget: UUID?

    var body: some View {
        VStack(spacing: 0) {
            AgentChatHeader(
                title: state.showsArchived ? String(localized: "Archived Chats") : String(localized: "Chat"),
                back: state.showsArchived ? { state.showsArchived = false } : nil,
                canCreate: controller.isLoaded, newConversation: newConversation
            ) { archiveMenu }
            AgentChatConnectionStatus(controller: controller, showDiagnostics: showDiagnostics)
            ContextSearchField(
                text: $state.query, prompt: "Search Conversations",
                identifier: "scholium.chat.search",
                options: AgentChatListFilter.allCases.map { filter in
                    .init(title: filter.title, selected: state.filter == filter) { state.filter = filter }
                }
            )
            .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
            .padding(.bottom, ScholiumSidebarLayout.itemSpacing)
            if state.filter != .all {
                HStack {
                    Text(ScholiumL10n.dynamicString(state.filter.title)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Clear") { state.filter = .all }
                }
                .font(.caption)
                .padding(.horizontal, ScholiumSidebarLayout.textInset)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.chat.filterStatus")
            }
            conversationList
        }
        .alert(
            "Delete Conversation?",
            isPresented: Binding(
                get: { deletionTarget != nil }, set: { if !$0 { deletionTarget = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletionTarget = nil }
            Button("Delete", role: .destructive) {
                if let id = deletionTarget { controller.deleteConversation(id) }
                deletionTarget = nil
            }
        } message: {
            Text("This permanently deletes the local conversation history and drafts. This cannot be undone.")
        }
    }

    private var archiveMenu: some View {
        Menu {
            Button("Conversations") { state.showsArchived = false }
            Button("Archived Chats") { state.showsArchived = true }
            Divider()
            Button("Account Usage") { showAccountUsage() }
        } label: {
            ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.more.symbol)
        }
        .scholiumSidebarHeaderControl()
        .help("Chat Options").accessibilityLabel("Chat Options")
        .accessibilityIdentifier("scholium.chat.archived")
    }

    private var visibleConversations: [AgentChatConversation] {
        controller.conversations.filter { ($0.archivedAt != nil) == state.showsArchived }
            .filter {
                !$0.messages.isEmpty || AgentChatListFilter.hasDraft($0) || $0.archivedAt != nil
            }
            .filter {
                state.filter.includes(
                    $0,
                    needsInput: controller.questionCount(in: $0.id) > 0 || controller.approvalCount(in: $0.id) > 0,
                    inProgress: [.working, .compacting, .branching, .stopping].contains(controller.state(for: $0.id)))
            }
            .filter { AgentChatSearch.contains($0, query: AgentChatSearch.query(state.query)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func openConversation(_ conversation: AgentChatConversation) {
        controller.setUnread(conversation.id, unread: false)
        if controller.selectedID != conversation.id { controller.select(conversation.id) }
        showConversation()
    }

    private var conversationList: some View {
        let conversations = visibleConversations
        return List {
            ForEach(conversationOrder.arrange(conversations)) { conversation in
                conversationRow(conversation)
                    .listRowSeparator(.visible, edges: .bottom)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("scholium.chat.conversations")
        .onAppear { conversationOrder.reset(visibleConversations.map(\.id)) }
        .onChange(of: visibleConversations.map(\.id)) { _, ids in conversationOrder.reconcile(ids) }
        .onChange(of: state.showsArchived) { _, _ in conversationOrder.reset(visibleConversations.map(\.id)) }
        .overlay(alignment: .top) {
            if !controller.isLoaded && controller.error == nil {
                ScholiumSidebarState(Text("Loading Conversations…"), indicator: .progress)
                    .accessibilityIdentifier("scholium.chat.loading")
            } else if conversations.isEmpty && controller.isLoaded {
                conversationEmptyState
            }
        }
    }

    @ViewBuilder
    private func conversationRow(_ conversation: AgentChatConversation) -> some View {
        let row = AgentChatConversationRow(
            conversation: conversation, query: AgentChatSearch.query(state.query),
            status: AgentChatListPresentation.status(
                conversation,
                questions: controller.questionCount(in: conversation.id),
                approvals: controller.approvalCount(in: conversation.id),
                busy: controller.isBusy(in: conversation.id)))
        Button {
            openConversation(conversation)
        } label: {
            row.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scholiumActivationPointer()
        .scholiumContentControlPointerFeedback(
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .accessibilityIdentifier("scholium.chat.conversation.\(conversation.id)")
        .contextMenu { conversationActions(conversation) }
        .accessibilityActions { conversationActions(conversation) }
        .swipeActions(edge: .trailing, allowsFullSwipe: conversation.archivedAt == nil) {
            if conversation.archivedAt != nil {
                Button("Delete", systemImage: ScholiumSidebarAction.delete.symbol, role: .destructive) { deletionTarget = conversation.id }
                    .disabled(!controller.canArchive(conversation.id))
            }
            Button(
                conversation.archivedAt == nil ? "Archive" : "Restore",
                systemImage: conversation.archivedAt == nil ? ScholiumSidebarAction.archive.symbol : ScholiumSidebarAction.restore.symbol
            ) {
                controller.setArchived(conversation.id, archived: conversation.archivedAt == nil)
            }
            .tint(ScholiumNativeColorRole.archiveAction.color)
            .disabled(!controller.canArchive(conversation.id))
        }
        .swipeActions(edge: .leading) {
            Button(
                conversation.unreadAt == nil ? "Unread" : "Read",
                systemImage: AgentChatListPresentation.readActionSymbol(isUnread: conversation.unreadAt != nil)
            ) {
                controller.setUnread(conversation.id, unread: conversation.unreadAt == nil)
            }
            .accessibilityLabel(conversation.unreadAt == nil ? "Mark as Unread" : "Mark as Read")
            .tint(ScholiumNativeColorRole.unreadAction.color)
            Button(
                conversation.importantAt == nil ? "Important" : "Unmark",
                systemImage: AgentChatListPresentation.importanceActionSymbol(isImportant: conversation.importantAt != nil)
            ) {
                controller.setImportant(conversation.id, important: conversation.importantAt == nil)
            }
            .accessibilityLabel(conversation.importantAt == nil ? "Mark as Important" : "Unmark Important")
            .tint(ScholiumNativeColorRole.importantAction.color)
        }
    }

    private var conversationEmptyState: some View {
        let isFiltered = state.filter != .all || !AgentChatSearch.query(state.query).isEmpty
        return ScholiumSidebarState(
            isFiltered ? Text("No Matching Conversations") : state.showsArchived ? Text("No Archived Chats") : Text("No Conversations"),
            detail: isFiltered
                ? Text("Try another search or clear the conversation filter.")
                : state.showsArchived ? Text("Archived conversations appear here.") : Text("Start a conversation about your research."),
            indicator: .symbol(isFiltered ? "magnifyingglass" : state.showsArchived ? "archivebox" : "bubble.left.and.bubble.right")
        )
        .accessibilityIdentifier("scholium.chat.empty")
    }

    @ViewBuilder
    private func conversationActions(_ conversation: AgentChatConversation) -> some View {
        Button("Open Conversation") {
            openConversation(conversation)
        }
        Button("Rename Conversation…") {
            renameConversation(conversation)
        }
        Divider()
        Button("Conversation Changes") {
            showConversationChanges(conversation.messages.compactMap(\.changeID))
        }
        Divider()
        Button(conversation.unreadAt == nil ? "Mark as Unread" : "Mark as Read") {
            controller.setUnread(conversation.id, unread: conversation.unreadAt == nil)
        }
        Button(conversation.importantAt == nil ? "Mark as Important" : "Unmark Important") {
            controller.setImportant(conversation.id, important: conversation.importantAt == nil)
        }
        if conversation.archivedAt != nil {
            Button("Delete", role: .destructive) { deletionTarget = conversation.id }
                .disabled(!controller.canArchive(conversation.id))
        }
        Button(conversation.archivedAt == nil ? "Archive Chat" : "Restore Chat") {
            controller.setArchived(conversation.id, archived: conversation.archivedAt == nil)
        }.disabled(!controller.canArchive(conversation.id))
    }

}
