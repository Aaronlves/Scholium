import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct AgentChatView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject var controller: AgentChatController
    let isVisible: Bool
    let addSelection: () -> Void
    let noteChoices: [WorkspaceCatalogNote]
    let addNote: (WorkspaceCatalogNote, UUID) async throws -> Void
    let openReference: (URL) -> Bool
    let openAttachment: (AgentChatAttachment) -> Void
    let showInLibrary: (URL) -> Void
    let showChanges: (UUID) -> Void
    let showConversationChanges: ([UUID]) -> Void
    var changes: [AgentChange]? = nil
    var changesError: String? = nil
    @AppStorage(AgentChatInputBehavior.key) private var inputBehavior = AgentChatInputBehavior.steer
    @AppStorage(AgentChangeViewedLedger.key) private var viewedChangeData = Data()
    @State private var queueEditTarget: AgentChatQueueEditTarget?
    @State private var showsArchived = false
    @State private var deletionTarget: UUID?
    @State private var readingStore = AgentChatReadingStore()
    @State private var showsTurns = false
    @State private var showsPlan = false
    private var readingSession: AgentChatReadingSession { readingStore.session(for: controller.selectedID) }
    private var readingIsPaused: Bool {
        get { readingSession.isPaused }
        nonmutating set { if newValue { readingSession.pause() } else { readingSession.isPaused = false } }
    }
    @State private var conversationOrder = AgentChatListOrder()
    private var isAwayFromLatest: Bool { readingSession.isAwayFromLatest }
    @State private var transcriptIsScrolling = false
    @State private var arrivalBaseline: Set<String>?
    @State private var showsConversationList = true
    @State private var showsFiles = false
    @State private var showsContext = false
    @State private var showsDiagnostics = false
    @State private var diagnosticMessageID: String?
    @State private var diagnosticError: String?
    private var expandedActivityIDs: Set<String> {
        get { readingSession.expandedActivities }
        nonmutating set { readingSession.expandedActivities = newValue }
    }
    @State private var completion = AgentChatComposerCompletion()
    @State private var notePickerTarget: AgentChatNotePicker.Target?
    @State private var pdfPagesTarget: AgentChatPDFPagesView.Target?
    @State private var comparisonRequest: AgentChatApproval?
    @State private var inspectedAgent: AgentChatChildController?
    @State private var materialTask: Task<Void, Never>?
    @State private var conversationQuery = ""
    @State private var conversationFilter = AgentChatListFilter.all
    @State private var showsFind = false
    @State private var find = AgentChatFindState()
    @State private var findFocusRequest: UUID?
    @State private var renameID: UUID?
    @State private var showsRename = false
    @State private var renameTitle = ""
    @State private var messageIsFocused = false
    @State private var replyNavigation: ReplyNavigation?

    private struct ReplyNavigation: Equatable {
        let id = UUID()
        let conversationID: UUID
        let messageID: String
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            connectionStatus
            if showsConversationList {
                ContextSearchField(
                    text: $conversationQuery, prompt: "Search Conversations",
                    identifier: "scholium.chat.search",
                    options: AgentChatListFilter.allCases.map { filter in
                        .init(title: filter.title, selected: conversationFilter == filter) { conversationFilter = filter }
                    }
                )
                .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
                .padding(.bottom, ScholiumSidebarLayout.itemSpacing)
                if conversationFilter != .all {
                    HStack {
                        Text(ScholiumL10n.dynamicString(conversationFilter.title)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Button("Clear") { conversationFilter = .all }
                    }
                    .font(.caption)
                    .padding(.horizontal, ScholiumSidebarLayout.textInset)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scholium.chat.filterStatus")
                }
                conversationList
            } else {
                conversationDetail
            }
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
        .popover(isPresented: $showsDiagnostics) {
            AgentChatDiagnosticsView(
                messages: controller.selected?.messages ?? [], selectedID: diagnosticMessageID,
                error: diagnosticError ?? controller.error, close: { showsDiagnostics = false })
        }
        .sheet(item: $queueEditTarget) { target in
            AgentChatQueuedMessageEditor(
                message: target.message,
                save: { controller.editQueuedMessage(target.message.id, text: $0, in: target.conversationID) },
                close: { queueEditTarget = nil })
        }
        .sheet(item: $inspectedAgent) { child in
            AgentChatChildInspector(child: child, openReference: openReference)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat")
        .sheet(item: $notePickerTarget) { target in
            AgentChatNotePicker(notes: noteChoices) { note in try await addNote(note, target.id) }
        }
        .sheet(item: $pdfPagesTarget) { target in AgentChatPDFPagesView(controller: controller, target: target) }
        .sheet(item: $comparisonRequest) { request in
            if let preview = request.updatePreview {
                AgentChatUpdateComparisonSheet(controller: controller, requestID: request.id, preview: preview)
            }
        }
        .onDisappear { materialTask?.cancel() }
        .dropDestination(for: URL.self) { urls, _ in
            guard materialTask == nil, let id = controller.selectedID, !urls.isEmpty,
                urls.allSatisfy(\.isFileURL)
            else { return false }
            prepareFiles(urls, to: id)
            return true
        }
        .onChange(of: showsConversationList) { _, _ in markVisibleConversationRead() }
        .onChange(of: isVisible) { _, _ in markVisibleConversationRead() }
        .onChange(of: controller.selectedID) { _, _ in markVisibleConversationRead() }
        .onChange(of: controller.conversations.map(\.id)) { _, ids in readingStore.retain(Set(ids)) }
        .onChange(of: controller.selected?.unreadAt) { _, _ in markVisibleConversationRead() }
        .onAppear { markVisibleConversationRead() }
        .onChange(of: showsArchived) { _, _ in
            conversationFilter = .all
        }
        .onChange(of: controller.selectedID) { _, _ in
            completion.dismiss()
            showsFiles = false
            showsContext = false
            showsDiagnostics = false
            diagnosticError = nil
            showsTurns = false
            showsPlan = false
            transcriptIsScrolling = false
            arrivalBaseline = nil
            showsFind = false
            find = .init()
            renameID = nil
            showsRename = false
        }
        .onChange(of: controller.contextPresentationID, initial: true) { _, request in
            guard request != nil else { return }
            showsConversationList = false
            messageIsFocused = isVisible
        }
        .onChange(of: controller.selected?.attachments.count) { old, new in
            if (new ?? 0) > (old ?? 0) {
                showsConversationList = false
                messageIsFocused = isVisible
            }
        }
        .onChange(of: isVisible) { _, visible in
            if visible, controller.contextPresentationID != nil { messageIsFocused = true }
            if !visible {
                messageIsFocused = false
                showsFiles = false
                showsContext = false
                showsDiagnostics = false
                diagnosticError = nil
            }
        }
        .onChange(of: find.query) { _, _ in refreshFind(reset: true) }
        .onChange(of: controller.selected?.messages) { _, _ in
            if showsFind { refreshFind() }
        }
        .alert("Rename Conversation", isPresented: $showsRename) {
            TextField("Conversation Title", text: $renameTitle)
            Button("Cancel", role: .cancel) { renameID = nil }
            Button("Rename") {
                if let renameID { controller.rename(renameTitle, in: renameID) }
                renameID = nil
            }.disabled(renameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var header: some View {
        ScholiumSidebarHeader {
            if !showsConversationList || showsArchived {
                Button {
                    if !showsConversationList { showsConversationList = true } else { showsArchived = false }
                } label: {
                    ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.back.symbol)
                }
                .scholiumSidebarHeaderControl()
                .help("Conversations").accessibilityLabel("Conversations")
                .accessibilityIdentifier("scholium.chat.back")
            }
            Text(
                showsConversationList
                    ? (showsArchived ? String(localized: "Archived Chats") : String(localized: "Chat"))
                    : controller.selected?.title.isEmpty == false
                        ? controller.selected!.title : String(localized: "New Conversation")
            )
            .font(.headline).lineLimit(1)
            .padding(
                .leading, showsConversationList && !showsArchived ? ScholiumSidebarLayout.rowInset : 0)
            Spacer(minLength: 0)
            ScholiumSidebarHeaderActions {
                Button {
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
                    showsArchived = false
                    showsConversationList = false
                    messageIsFocused = true
                } label: {
                    ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.newConversation.symbol)
                }
                .scholiumSidebarHeaderControl()
                .disabled(!controller.isLoaded)
                .help("New Conversation").accessibilityLabel("New Conversation")
                .accessibilityIdentifier("scholium.chat.newConversation")
                if showsConversationList {
                    archiveMenu
                } else {
                    Menu {
                        Button("Conversation Outline", systemImage: ScholiumSidebarAction.outline.symbol) { showsTurns = true }
                        Button("Find in Conversation") {
                            showsFind = true
                            messageIsFocused = false
                            findFocusRequest = UUID()
                            refreshFind()
                        }
                        Button("Rename Conversation…") {
                            renameTitle = controller.selected?.title ?? ""
                            renameID = controller.selectedID
                            showsRename = renameID != nil
                        }
                        Menu("Branch Conversation") {
                            ForEach(controller.branchPoints) { message in
                                Button(String(message.text.prefix(90))) {
                                    if let turnID = message.turnID { controller.branch(through: turnID) }
                                }
                            }
                        }.disabled(!controller.canBranch || controller.branchPoints.isEmpty)
                        Menu("Edit Earlier Request") {
                            ForEach(controller.editableRequests) { message in
                                Button(String(message.text.prefix(90))) { controller.editInNewBranch(message.id) }
                            }
                        }.disabled(!controller.canBranch || controller.editableRequests.isEmpty)
                        if let origin = controller.selected?.branchOrigin {
                            Button("Open Original Conversation") { controller.select(origin.conversationID) }
                                .disabled(!controller.conversations.contains(where: { $0.id == origin.conversationID }))
                        }
                        Divider()
                        Button("Context and Usage") { showsContext = true }
                        Button("Diagnostics…") {
                            diagnosticMessageID = nil
                            showsDiagnostics = true
                        }
                        Button("Conversation Changes") {
                            showConversationChanges(controller.selected?.messages.compactMap(\.changeID) ?? [])
                        }.accessibilityIdentifier("scholium.chat.changeHistory")
                    } label: {
                        ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.more.symbol)
                    }
                    .scholiumSidebarHeaderControl()
                    .accessibilityLabel("Chat Options")
                    .accessibilityIdentifier("scholium.chat.options")
                    .popover(isPresented: $showsContext, arrowEdge: .leading) {
                        contextPanel
                    }
                }
            }
        }
    }

    private var archiveMenu: some View {
        Menu {
            Button("Conversations") { showsArchived = false }
            Button("Archived Chats") { showsArchived = true }
        } label: {
            ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.archive.symbol)
        }
        .scholiumSidebarHeaderControl()
        .help("Organize Chats").accessibilityLabel("Organize Chats")
        .accessibilityIdentifier("scholium.chat.archived")
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if controller.isRenewingSettings {
            if let error = controller.settingsRenewalError {
                ScholiumSidebarState(Text("Settings Could Not Be Applied"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                    Button("Retry") { controller.renewSettingsWhenIdle() }
                    Button("Diagnostics…") {
                        diagnosticMessageID = nil
                        diagnosticError = error
                        showsDiagnostics = true
                    }
                }
            } else {
                ScholiumSidebarState(Text("Applying Settings…"), indicator: .progress)
            }
        } else if controller.isLoaded {
            if controller.connectionState == .disconnected {
                ScholiumSidebarState(Text("Not Connected"), indicator: .symbol("network")) {
                    Button("Connect Codex") { controller.connectConfigured() }
                }
            } else if controller.connectionState == .connecting {
                ScholiumSidebarState(Text("Connecting…"), indicator: .progress)
            } else if controller.account == nil {
                ScholiumSidebarState(Text("Sign-In Required"), indicator: .symbol("person.crop.circle")) {
                    Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy)
                }
            }
        }
        if let error = controller.capabilities.workspaceError {
            ScholiumSidebarState(Text("Skills Could Not Be Loaded"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                Button("Refresh Skills") {
                    controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
                }.disabled(controller.isBusy || controller.capabilities.isRefreshing)
                Button("Diagnostics…") {
                    diagnosticMessageID = nil
                    diagnosticError = error
                    showsDiagnostics = true
                }
            }
        }
        if controller.historyUnavailable {
            ScholiumSidebarState(
                Text("Conversation Unavailable"),
                detail: Text("This conversation is saved here, but unavailable in the connected runtime."),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            ) {
                Button("Retry") { controller.retryHistory() }.disabled(controller.isBusy)
                Button("New Conversation") { controller.newConversation() }
            }
        }
        if let error = controller.error {
            ScholiumSidebarState(Text("Conversation Needs Attention"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                Button("Diagnostics…") {
                    diagnosticMessageID = nil
                    diagnosticError = error
                    showsDiagnostics = true
                }
                if controller.state == .disconnected {
                    Button("Agent Settings…") {
                        UserDefaults.standard.set("integrations", forKey: "scholium.settings.selectedPane")
                        UserDefaults.standard.set(
                            SettingsIntegrationCategory.agents.rawValue, forKey: "scholium.settings.integrationCategory")
                        openSettings()
                    }
                }
            }
        }
    }

    private var visibleConversations: [AgentChatConversation] {
        controller.conversations.filter { ($0.archivedAt != nil) == showsArchived }
            .filter {
                !$0.messages.isEmpty || AgentChatListFilter.hasDraft($0) || $0.archivedAt != nil
            }
            .filter {
                conversationFilter.includes(
                    $0,
                    needsInput: controller.questionCount(in: $0.id) > 0 || controller.approvalCount(in: $0.id) > 0,
                    inProgress: [.working, .compacting, .branching, .stopping].contains(controller.state(for: $0.id)))
            }
            .filter { AgentChatSearch.contains($0, query: AgentChatSearch.query(conversationQuery)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func openConversation(_ conversation: AgentChatConversation) {
        controller.setUnread(conversation.id, unread: false)
        if controller.selectedID != conversation.id { controller.select(conversation.id) }
        showsConversationList = false
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
        .onChange(of: showsArchived) { _, _ in conversationOrder.reset(visibleConversations.map(\.id)) }
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
            conversation: conversation, query: AgentChatSearch.query(conversationQuery),
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
        let isFiltered = conversationFilter != .all || !AgentChatSearch.query(conversationQuery).isEmpty
        return ScholiumSidebarState(
            isFiltered ? Text("No Matching Conversations") : showsArchived ? Text("No Archived Chats") : Text("No Conversations"),
            detail: isFiltered
                ? Text("Try another search or clear the conversation filter.")
                : showsArchived ? Text("Archived conversations appear here.") : Text("Start a conversation about your research."),
            indicator: .symbol(isFiltered ? "magnifyingglass" : showsArchived ? "archivebox" : "bubble.left.and.bubble.right")
        )
        .accessibilityIdentifier("scholium.chat.empty")
    }

    @ViewBuilder
    private func conversationActions(_ conversation: AgentChatConversation) -> some View {
        Button("Open Conversation") {
            openConversation(conversation)
        }
        Button("Rename Conversation…") {
            renameTitle = conversation.title
            renameID = conversation.id
            showsRename = true
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

    private func markVisibleConversationRead() {
        if isVisible, !showsConversationList, let id = controller.selectedID {
            controller.setUnread(id, unread: false)
        }
    }

    private func refreshFind(reset: Bool = false) {
        find.refresh(messages: controller.selected?.messages ?? [], reset: reset)
    }

    private func dismissFind() {
        showsFind = false
        find = .init()
        messageIsFocused = isVisible && controller.selected?.isAvailable == true
    }

    private var timelineMessages: [AgentChatMessage] {
        let active = Set(
            controller.approvals.flatMap { approval -> [String] in
                var ids: [String] = []
                if !approval.questions.isEmpty { ids.append("question:\(approval.id)") }
                if approval.runtimeApproval != nil { ids.append("approval:\(approval.id)") }
                if let item = approval.runtimeItemID { ids.append("runtime:\(item)") }
                return ids
            })
        return (controller.selected?.messages ?? []).filter {
            !active.contains($0.id) || (showsFind && find.selectedID == $0.id)
        }
    }

    private var timelineItems: [AgentChatTimelineItem] { AgentChatTimelineItem.group(timelineMessages) }
    private var visibleTimelineItems: [AgentChatTimelineItem] {
        let items = timelineItems
        return Array(items[readingSession.history.range(in: items.map(\.id))])
    }

    private func revealMessage(_ id: String) {
        guard let item = timelineItems.first(where: { $0.messages.contains(where: { $0.id == id }) }) else { return }
        if item.isProcess { expandedActivityIDs.insert(id) }
        readingSession.navigate(to: item.id, in: timelineItems.map(\.id))
    }

    @ViewBuilder
    private func historyPagingButton(earlier: Bool) -> some View {
        let ids = timelineItems.map(\.id)
        let range = readingSession.history.range(in: ids)
        if earlier ? range.lowerBound > 0 : range.upperBound < ids.count {
            Button {
                readingSession.viewport?.capture()
                readingSession.pause()
                if earlier { readingSession.history.earlier(in: ids) } else { readingSession.history.later(in: ids) }
            } label: {
                Label(
                    earlier ? "Earlier Messages" : "Later Messages",
                    systemImage: earlier ? ScholiumSidebarAction.earlier.symbol : ScholiumSidebarAction.later.symbol)
            }
            .buttonStyle(.borderless).font(.callout)
            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
            .accessibilityIdentifier(earlier ? "scholium.chat.earlier" : "scholium.chat.later")
        }
    }

    private var currentReadingRequestID: String? {
        guard let anchor = readingSession.anchor,
            let item = timelineItems.first(where: { $0.id == anchor.id }),
            let turnID = item.messages.first?.turnID
        else { return readingSession.anchor?.id }
        return timelineMessages.first(where: { $0.turnID == turnID && $0.role == .user })?.id
    }

    private var turnNavigationButton: some View {
        Button {
            showsTurns = true
        } label: {
            ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.outline.symbol, placement: .action)
        }
        .buttonStyle(.borderless).foregroundStyle(.primary)
        .glassEffect(.clear.interactive(), in: Circle())
        .help("Conversation Outline").accessibilityLabel("Conversation Outline")
        .accessibilityIdentifier("scholium.chat.outlineButton")
        .disabled(!timelineMessages.contains { $0.role == .user })
        .popover(isPresented: $showsTurns, arrowEdge: .leading) {
            AgentChatConversationOutline(messages: timelineMessages, currentMessageID: currentReadingRequestID) { id in
                showsTurns = false
                revealMessage(id)
            }
        }
    }

    private var contextMeterButton: some View {
        Button {
            showsContext = true
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ScholiumSidebarIcon(systemImage: ScholiumSidebarItem.context.symbol)
                if let fraction = AgentChatContextPresentation.fraction(controller.selected?.contextUsage) {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                }
            }.font(.caption)
                .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                .frame(minWidth: ScholiumGrid.Dimension.preferredCustomTarget, minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
        }
        .buttonStyle(.borderless).foregroundStyle(.primary)
        .glassEffect(.clear.interactive(), in: Capsule())
        .help("Context and Usage").accessibilityLabel("Context and Usage")
        .accessibilityValue(
            controller.selected?.contextUsage.flatMap { AgentChatContextPresentation.fraction($0) }
                .map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? String(localized: "Not Available", bundle: .module)
        )
        .accessibilityIdentifier("scholium.chat.contextMeter")
    }

    private var activePlan: AgentChatPlan? {
        guard controller.isBusy else { return nil }
        return controller.selected?.messages.last(where: { $0.turnID == controller.currentTurnID && $0.plan != nil })?.plan
    }

    private func currentPlanButton(_ plan: AgentChatPlan) -> some View {
        Button {
            showsPlan = true
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ScholiumSidebarIcon(systemImage: ScholiumSidebarItem.plan.symbol)
                Text(verbatim: plan.steps.first(where: { $0.status == .inProgress })?.step ?? String(localized: "Plan", bundle: .module))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(plan.steps.filter { $0.status == .completed }.count)/\(plan.steps.count)").monospacedDigit()
            }.font(.callout)
                .padding(ScholiumGrid.Spacing.inlineControlGap)
        }
        .buttonStyle(.borderless).foregroundStyle(.secondary)
        .glassEffect(.clear.interactive(), in: Capsule())
        .padding(.horizontal, ScholiumSidebarLayout.textInset)
        .help("Current Plan")
        .accessibilityLabel(Text("Current Plan") + Text(verbatim: ": " + (plan.steps.first(where: { $0.status == .inProgress })?.step ?? "")))
        .accessibilityValue(Text("\(plan.steps.filter { $0.status == .completed }.count)/\(plan.steps.count)"))
        .accessibilityIdentifier("scholium.chat.currentPlan")
        .popover(isPresented: $showsPlan, arrowEdge: .leading) {
            AgentChatContentScroll { AgentChatPlanView(plan: plan).padding(ScholiumSidebarLayout.textInset) }
                .frame(width: 300)
        }
    }

    private var conversationDetail: some View {
        VStack(spacing: 0) {
            if controller.selected?.pendingMessageID != nil, !controller.isBusy {
                Button("Continue Without Resending") { controller.confirmContinueAfterUncertainDelivery() }
                    .padding(8)
            }
            Group {
                if showsFind {
                    AgentChatFindBar(
                        query: $find.query, focusRequest: findFocusRequest,
                        position: find.position, count: find.messageIDs.count,
                        move: { backwards in find.move(backwards: backwards) }, dismiss: dismissFind)
                }
                ScrollView {
                    // Transcript geometry must describe the loaded messages, rather than
                    // LazyVStack's changing estimates as long replies enter the viewport.
                    VStack(alignment: .leading, spacing: ScholiumChatAppearance.messageSpacing) {
                        if controller.selected?.messages.isEmpty != false {
                            ScholiumContentStateView(
                                title: Text("New Conversation"),
                                detail: Text("Discuss your research here. Add a passage or name a note to begin."),
                                indicator: .symbol("bubble.left.and.bubble.right"),
                                placement: .leading, density: .compact
                            )
                            .accessibilityIdentifier("scholium.chat.emptyConversation")
                        }
                        historyPagingButton(earlier: true)
                        ForEach(visibleTimelineItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                if showsFind, let message = item.messages.first(where: { $0.id == find.selectedID }),
                                    let passage = AgentChatSearch.passage(in: message, query: AgentChatSearch.query(find.query))
                                {
                                    Label("Matching Message", systemImage: ScholiumSidebarAction.search.symbol)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(passage).font(.callout).textSelection(.enabled)
                                }
                                timelineItem(item)
                            }.id(item.id)
                                .background(AgentChatReadingMarker(id: item.id, session: readingSession))
                        }
                        historyPagingButton(earlier: false)
                        if readingSession.history.last == nil { currentActivity }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(.horizontal, ScholiumSidebarLayout.textInset)
                        .padding(.vertical, ScholiumSidebarLayout.edgeInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AgentChatScrollBoundary())
                        .background(AgentChatTranscriptViewport(session: readingSession))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("scholium.chat.transcript.content")
                }
                .accessibilityIdentifier("scholium.chat.transcript")
                .defaultScrollAnchor(.top, for: .alignment)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        if url.scheme == "scholium-chat" {
                            guard let target = AgentChatReplyQuotation.target(url),
                                controller.conversations.contains(where: {
                                    $0.id == target.conversationID
                                        && $0.messages.contains(where: { $0.id == target.messageID })
                                })
                            else { return .discarded }
                            controller.select(target.conversationID)
                            replyNavigation = .init(conversationID: target.conversationID, messageID: target.messageID)
                            return .handled
                        }
                        if url.scheme == "scholium-note" {
                            _ = openReference(url)
                            return .handled
                        }
                        if let destination = AgentChatReplySource.externalURL(url) { return .systemAction(destination) }
                        return .discarded
                    }
                )
                .environment(\.chatReadingInteraction, { readingIsPaused = true })
                .simultaneousGesture(TapGesture().onEnded { completion.dismiss() })
                .scrollEdgeEffectHidden(true, for: .bottom)
                .onScrollPhaseChange { _, phase in
                    transcriptIsScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    readingSession.isScrolling = transcriptIsScrolling
                    if phase == .tracking || phase == .interacting { readingSession.pause() }
                    if phase == .idle { readingSession.viewport?.capture() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                        HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                            filesButton
                            turnNavigationButton
                            contextMeterButton
                            if isAwayFromLatest || readingSession.history.last != nil {
                                Button {
                                    readingSession.latest(in: timelineItems.map(\.id))
                                } label: {
                                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.later.symbol, placement: .action)
                                }
                                .buttonStyle(.borderless).foregroundStyle(.primary)
                                .glassEffect(.clear.interactive(), in: Circle())
                                .help("Latest Reply").accessibilityLabel("Latest Reply")
                            }
                        }
                        if let plan = activePlan { currentPlanButton(plan) }
                        if controller.selected?.isAvailable == false {
                            Button("Restore Chat") {
                                if let id = controller.selectedID {
                                    controller.setArchived(id, archived: false)
                                    showsArchived = false
                                }
                            }.buttonStyle(.glass).padding()
                        } else {
                            inputDock
                        }
                    }
                }
                .task(id: replyNavigation) {
                    guard let target = replyNavigation, target.conversationID == controller.selectedID else { return }
                    revealMessage(target.messageID)
                }
                .onChange(of: find.selectedID) { _, id in
                    if let id { expandedActivityIDs.insert(id) }
                    if let id,
                        let item = AgentChatTimelineItem.group(timelineMessages)
                            .first(where: { $0.messages.contains(where: { $0.id == id }) })
                    {
                        readingSession.navigate(to: item.id, in: timelineItems.map(\.id))
                    }
                }
            }
        }
        .onAppear {
            arrivalBaseline = Set(timelineMessages.map(\.id))
            if !readingIsPaused { readingSession.history.latest(in: timelineItems.map(\.id)) }
        }
        .onChange(of: timelineItems.map(\.id)) { _, ids in
            if !readingIsPaused { readingSession.history.latest(in: ids) }
        }
        .onDisappear { arrivalBaseline = nil }
        .task { if isVisible && pendingRequest == nil && controller.pendingAsyncQuestion == nil { messageIsFocused = true } }
        .id(controller.selectedID)
    }

    @ViewBuilder
    private func timelineItem(_ item: AgentChatTimelineItem) -> some View {
        if item.isProcess {
            AgentChatProcessView(
                messages: item.messages,
                isActive: controller.isBusy && controller.currentTurnID != nil && item.messages.first?.turnID == controller.currentTurnID,
                forceExpanded: showsFind && item.messages.contains { $0.id == find.selectedID },
                status: item.carriesTurnStatus(in: timelineMessages) ? turnPresentation(item.messages.first?.turnID) : nil,
                preservesReading: isAwayFromLatest || readingIsPaused || transcriptIsScrolling,
                hasInspectedActivity: item.messages.contains { expandedActivityIDs.contains($0.id) },
                animates: isVisible && controller.approvals.isEmpty,
                inspect: { readingIsPaused = true },
                userExpansion: Binding(
                    get: { readingSession.processExpansions[item.id] },
                    set: { readingSession.processExpansions[item.id] = $0 })
            ) { message in
                if message.activity != nil {
                    activityRow(message)
                } else if let plan = message.plan {
                    AgentChatPlanView(
                        plan: plan,
                        savedExpansion: Binding(
                            get: { readingSession.planExpansions[message.id] },
                            set: { readingSession.planExpansions[message.id] = $0 }))
                } else {
                    AgentChatMarkdown(
                        text: message.text
                    ).foregroundStyle(.secondary)
                }
            }
        } else if let message = item.messages.first {
            if message.role == .assistant && item.carriesTurnStatus(in: timelineMessages) {
                AgentChatTurnStatus(presentation: turnPresentation(message.turnID), animates: isVisible)
            }
            messageView(message)
            if message.role == .user && item.carriesTurnStatus(in: timelineMessages) {
                AgentChatTurnStatus(presentation: turnPresentation(message.turnID), animates: isVisible)
            }
        }
    }

    private func messageView(_ message: AgentChatMessage) -> some View {
        let conversationID = controller.selectedID
        return VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            AgentChatMessageSurface(isUser: message.role == .user) {
                VStack(alignment: .leading, spacing: ScholiumChatAppearance.contentSpacing) {
                    quoteCards(message.replyQuotes ?? [], editable: false)
                    if let target = message.coordinationTarget {
                        coordinationReference(target)
                    }
                    if let plan = message.plan {
                        AgentChatPlanView(
                            plan: plan,
                            savedExpansion: Binding(
                                get: { readingSession.planExpansions[message.id] },
                                set: { readingSession.planExpansions[message.id] = $0 }))
                    }
                    if let request = message.asyncQuestion {
                        ForEach(request.questions) { question in
                            Text(question.prompt).font(.callout).foregroundStyle(.secondary)
                        }
                    } else if !message.text.isEmpty {
                        AgentChatMarkdown(
                            text: message.text, expandsToFillWidth: message.role != .user,
                            quoteSelection: canQuote(message) ? { selection in quote(message, selection: selection, in: conversationID) } : nil)
                    }
                    if !message.attachments.isEmpty || !message.localMaterials.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(message.attachments) { attachment in
                                    AgentChatMaterialChip(attachment: attachment, remove: nil, open: { openAttachment(attachment) })
                                }
                                ForEach(message.localMaterials) { material in
                                    AgentChatLocalMaterialChip(
                                        material: material, preview: { try await controller.previewLocalMaterial(material) }, remove: nil, replace: nil)
                                }
                            }
                        }
                    }
                    ForEach(message.methods ?? []) { method in
                        Label(method.title, systemImage: ScholiumSidebarItem.skill.symbol).font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Requested Skill: \(method.title)")
                    }
                }
            }
            if message.role == .user || (message.role == .assistant && message.phase != .commentary && message.asyncQuestion == nil) {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    if message.role == .user { Spacer(minLength: 0) }
                    if message.role == .assistant, !message.text.isEmpty, !controller.isBusy || message.turnID != controller.currentTurnID {
                        AgentChatReplyActions(
                            text: message.text, openNote: { _ = openReference($0) },
                            context: .init(reply: message, history: controller.selected?.messages ?? []),
                            openAttachment: openAttachment, previewMaterial: { try await controller.previewLocalMaterial($0) })
                    }
                    messageActions(message, in: conversationID)
                        .labelStyle(ScholiumSidebarActionLabelStyle())
                }.buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .modifier(
            AgentChatMessageArrival(
                enabled: shouldAnimateArrival(message),
                waitsForContent: message.asyncQuestion == nil && !message.text.isEmpty)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.role == .user ? ScholiumL10n.string("You", locale: locale) : "Codex")
        .contextMenu { messageActions(message, in: conversationID) }
    }

    @ViewBuilder
    private func messageActions(_ message: AgentChatMessage, in conversationID: UUID?) -> some View {
        if controller.editableRequests.contains(where: { $0.id == message.id }) {
            Button("Edit in New Branch", systemImage: ScholiumSidebarAction.edit.symbol) { controller.editInNewBranch(message.id) }
                .disabled(!controller.canBranch)
                .help("Edit in New Branch").accessibilityLabel("Edit in New Branch")
        }
        if let turnID = message.turnID {
            Button("Branch from This Turn", systemImage: ScholiumSidebarAction.branch.symbol) { controller.branch(through: turnID) }
                .disabled(!controller.canBranch || !controller.branchPoints.contains(where: { $0.turnID == turnID }))
                .help("Branch from This Turn").accessibilityLabel("Branch from This Turn")
            if controller.canRetryInNewBranch(turnID: turnID) {
                Button("Retry in New Branch", systemImage: ScholiumSidebarAction.retry.symbol) { controller.retryInNewBranch(turnID: turnID) }
                    .help("Retry in New Branch").accessibilityLabel("Retry in New Branch")
            }
        }
        if canQuote(message) {
            Button("Quote in Reply", systemImage: ScholiumSidebarAction.quote.symbol) { quote(message, selection: nil, in: conversationID) }
                .help("Quote in Reply").accessibilityLabel("Quote in Reply")
        }
    }

    private func shouldAnimateArrival(_ message: AgentChatMessage) -> Bool {
        guard let arrivalBaseline else { return false }
        return !arrivalBaseline.contains(message.id) && allowsReplyMotion
    }

    private var allowsReplyMotion: Bool {
        isVisible && !showsConversationList && !isAwayFromLatest && !readingIsPaused && !transcriptIsScrolling && !controller.isRefreshingHistory
    }

    @ViewBuilder private func quoteCards(_ quotes: [AgentChatReplyQuote], editable: Bool) -> some View {
        if !quotes.isEmpty {
            let owner = controller.selectedID
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quotes) { quote in
                        AgentChatReplyQuoteCard(
                            quote: quote,
                            openOriginal: {
                                guard
                                    controller.conversations.contains(where: {
                                        $0.id == quote.conversationID
                                            && $0.messages.contains(where: { $0.id == quote.messageID })
                                    })
                                else {
                                    controller.reportMaterialError(ScholiumL10n.string("The original reply is unavailable."), in: owner ?? quote.conversationID)
                                    return
                                }
                                controller.select(quote.conversationID)
                                replyNavigation = .init(conversationID: quote.conversationID, messageID: quote.messageID)
                            },
                            remove: editable
                                ? {
                                    if let owner { controller.removeReplyQuote(quote.id, in: owner) }
                                } : nil)
                    }
                }.padding(.vertical, 4)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    private func canQuote(_ message: AgentChatMessage) -> Bool {
        message.role == .assistant && message.phase != .commentary && controller.selected?.isAvailable == true
            && (!controller.isBusy || message.turnID != controller.currentTurnID)
    }

    private func quote(_ message: AgentChatMessage, selection: AgentChatReplySelection?, in conversationID: UUID?) {
        guard let id = conversationID,
            controller.quoteReply(message.id, selection: selection, in: id)
        else { return }
        messageIsFocused = true
    }

    private func coordinationReference(_ target: AgentChatCoordinationTarget, editable: Bool = false) -> some View {
        AgentChatCoordinationReferenceView(
            target: target,
            inspect: { inspectedAgent = controller.childController(target: target) },
            openParent: controller.canOpenParent(for: target) ? { controller.openParent(for: target) } : nil,
            remove: editable ? { controller.removeDraftCoordinationTarget() } : nil)
    }

    private func activitySummary(_ activity: AgentChatActivity) -> String {
        if let id = activity.files.first?.noteID,
            let note = noteChoices.first(where: { $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == id })
        {
            return AgentChatActivityProjection.title(activity, locale: locale) + " · " + note.title
        }
        return AgentChatActivityProjection.summary(activity, locale: locale)
    }

    private var currentActivityID: String? {
        guard controller.state == .working, controller.approvals.isEmpty else { return nil }
        return AgentChatTimelineItem.activeActivityID(in: timelineMessages, turnID: controller.currentTurnID)
    }

    private func activitySymbol(_ activity: AgentChatActivity) -> some View {
        ScholiumSidebarIcon(systemImage: activity.status.isActive ? activity.kind.symbol : activity.status.symbol)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func activityRow(_ message: AgentChatMessage) -> some View {
        if let activity = message.activity {
            VStack(alignment: .leading, spacing: 4) {
                if let report = activity.delegation {
                    HStack(alignment: .top, spacing: 6) {
                        activitySymbol(activity)
                        AgentChatDelegationView(
                            report: report, operationStatus: activity.status,
                            openAgent: { target in
                                guard let conversation = controller.selectedID else { return }
                                inspectedAgent = controller.childController(targetID: target, messageID: message.id, in: conversation)
                            })
                    }
                } else {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedActivityIDs.contains(message.id) },
                            set: { expanded in
                                readingIsPaused = true
                                if expanded { expandedActivityIDs.insert(message.id) } else { expandedActivityIDs.remove(message.id) }
                            })
                    ) {
                        AgentChatActivityDetails(activity: activity, isInline: true, openNote: { _ = openReference($0) })
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                AgentChatActivityText(
                                    text: activitySummary(activity),
                                    isCurrent: isVisible && currentActivityID == message.id
                                ).lineLimit(2)
                                if activity.kind == .command && activity.commandAction == nil {
                                    Text(verbatim: activity.subject.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            if activity.status != .running && activity.status != .completed {
                                Text(activity.status.label(locale: locale)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disclosureGroupStyle(
                        AgentChatDisclosureStyle(
                            animates: isVisible,
                            symbol: activity.status.isActive || activity.status == .completed ? activity.kind.symbol : activity.status.symbol
                        ))
                }
            }
            .font(.callout)
            .contextMenu {
                Button("Diagnostics…") {
                    diagnosticError = nil
                    diagnosticMessageID = message.id
                    showsDiagnostics = true
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.chat.activity.\(message.id)")
        } else {
            Text(message.text).textSelection(.enabled)
        }
    }

    private func turnPresentation(_ turnID: String?) -> AgentChatTurnPresentation {
        let record = turnID.flatMap { controller.selected?.turns[$0] }
        let live = controller.isBusy && turnID == controller.currentTurnID
        let messages = timelineMessages.filter { $0.turnID == turnID && $0.role != .user }
        var state: AgentChatTurnPresentation.State = .uncertain
        if live {
            if controller.state == .stopping {
                state = .stopping
            } else if controller.approvals.contains(where: { !$0.questions.isEmpty }) {
                state = .waitingForInput
            } else if !controller.approvals.isEmpty {
                state = .waitingForApproval
            } else if controller.state == .compacting {
                state = .organizing
            } else if controller.state == .working {
                if messages.contains(where: { $0.phase == .finalAnswer && !$0.text.isEmpty }) {
                    state = .responding
                } else if let activity = messages.reversed().compactMap(\.activity).first(where: { $0.status.isActive }) {
                    switch activity.status {
                    case .waitingForInput: state = .waitingForInput
                    case .waitingForApproval: state = .waitingForApproval
                    default:
                        switch activity.kind {
                        case .read, .readAttachment: state = .reading
                        case .search, .webSearch: state = .searching
                        case .create, .update, .files: state = .writing
                        case .command:
                            switch activity.commandAction?.kind {
                            case .read: state = .reading
                            case .search, .listFiles: state = .searching
                            case nil: state = .executing
                            }
                        case .compaction: state = .organizing
                        default: state = .working
                        }
                    }
                } else {
                    state = .working
                }
            }
        } else {
            switch record?.status {
            case .completed: state = .completed
            case .interrupted: state = .interrupted
            case .failed: state = .failed
            default: break
            }
        }
        return .init(
            state: state, timing: record?.timing ?? .init(),
            pendingAnswers: messages.reduce(0) { $0 + ($1.asyncQuestion?.isPending == true ? $1.asyncQuestion?.remaining.count ?? 0 : 0) })
    }

    @ViewBuilder
    private var currentActivity: some View {
        if controller.isBusy {
            if controller.state == .working && controller.approvals.isEmpty && currentActivityID == nil
                && controller.currentTurnID.map({ turn in timelineMessages.contains { $0.turnID == turn } }) != true
            {
                // No pulse is shown until the runtime supplies a concrete public
                // activity. This keeps the turn header calm while preserving the
                // active-row signal for observed work below.
                Text(ScholiumL10n.string("Considering your question…", locale: locale))
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("scholium.chat.currentWork")
            }
            let hasHeader =
                controller.currentTurnID.map { turn in
                    timelineMessages.contains { $0.turnID == turn }
                } ?? false
            if !hasHeader {
                if controller.state == .working || controller.state == .stopping || controller.state == .compacting {
                    AgentChatTurnStatus(presentation: turnPresentation(controller.currentTurnID), animates: isVisible)
                        .accessibilityIdentifier("scholium.chat.currentActivity")
                } else {
                    HStack {
                        Text(
                            controller.state == .branching
                                ? ScholiumL10n.string("Creating Branch…", locale: locale)
                                : controller.isRefreshingHistory
                                    ? ScholiumL10n.string("Loading Conversation…", locale: locale)
                                    : ScholiumL10n.string("Connecting…", locale: locale))
                        if controller.state == .branching {
                            Button("Cancel") { controller.stop() }.accessibilityIdentifier("scholium.chat.cancelBranch")
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conversationChangeIDs: Set<UUID> {
        Set(controller.selected?.messages.compactMap(\.changeID) ?? [])
    }

    private var pendingChanges: [AgentChange] {
        AgentChangeViewedLedger(data: viewedChangeData).pending(changes ?? [], receiptIDs: conversationChangeIDs)
    }

    @ViewBuilder private var filesButton: some View {
        if changes == nil ? !conversationChangeIDs.isEmpty : !pendingChanges.isEmpty {
            Button {
                showsFiles = true
            } label: {
                Label(changes == nil ? String(localized: "Changes") : String(localized: "Changes: \(pendingChanges.count)"), systemImage: "pencil.line")
                    .padding(.horizontal, 10).padding(.vertical, 7)
            }
            .buttonStyle(.borderless).font(.caption).foregroundStyle(.primary)
            .glassEffect(.clear.interactive(), in: Capsule())
            .accessibilityIdentifier("scholium.chat.showFiles")
            .popover(isPresented: $showsFiles, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Changes to Review").font(.headline)
                        Spacer()
                        Button("Close") { showsFiles = false }.keyboardShortcut(.cancelAction)
                    }
                    if let changesError {
                        Text(verbatim: changesError).textSelection(.enabled)
                    } else if changes == nil {
                        ProgressView("Loading Agent Changes…")
                    } else if pendingChanges.isEmpty {
                        Text("No changes awaiting review.").foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(pendingChanges) { change in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            if change.operation != .trash {
                                                Button(AgentChangePresentation.displayName(for: change)) {
                                                    _ = openReference(AgentChatReference.url(noteID: change.noteID))
                                                }.buttonStyle(.link).help("Open Note")
                                                    .contextMenu { AgentChatNoteMenu(url: AgentChatReference.url(noteID: change.noteID)) }
                                            } else {
                                                Text(AgentChangePresentation.displayName(for: change))
                                            }
                                            Text(AgentChangePresentation.operationTitle(for: change.operation))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("View Changes") {
                                            showsFiles = false
                                            showChanges(change.id)
                                        }
                                    }
                                }
                            }
                        }.frame(maxHeight: 280)
                    }
                    Button("All Changes") {
                        showsFiles = false
                        showConversationChanges(Array(conversationChangeIDs))
                    }
                }.padding().frame(width: 360)
            }
        }
    }

    private func chooseFiles(replacing materialID: UUID? = nil) {
        guard materialTask == nil, let conversationID = controller.selectedID else { return }
        controller.reportMaterialError(nil, in: conversationID)
        materialTask = Task { @MainActor in
            defer { materialTask = nil }
            do {
                let urls = try await fileSelectionPresenter.requiredForFileSelection().selectURLs(
                    .init(
                        kind: .files(allowedContentTypes: [.pdf, .plainText, .image], allowsMultipleSelection: materialID == nil)))
                guard let urls, !Task.isCancelled else { return }
                await controller.addLocalFiles(urls, to: conversationID, replacing: materialID)
            } catch { controller.reportMaterialError(error.localizedDescription, in: conversationID) }
        }
    }

    private func prepareFiles(_ urls: [URL], to conversationID: UUID) {
        controller.reportMaterialError(nil, in: conversationID)
        materialTask = Task { @MainActor in
            defer { materialTask = nil }
            await controller.addLocalFiles(urls, to: conversationID)
        }
    }

    private var completionCandidates: [AgentChatComposerCandidate] {
        guard let query = completion.query else { return [] }
        typealias Candidate = AgentChatComposerCandidate
        let needle = AgentChatSearch.query(query.text)
        func matches(_ candidate: Candidate) -> Bool {
            needle.isEmpty || AgentChatSearch.matches(candidate.title + " " + candidate.id + " " + candidate.detail, query: needle)
        }
        switch query.trigger {
        case "$":
            return Array(
                controller.capabilities.methods.filter { !$0.isProtected && $0.enabled }.map { method in
                    Candidate(
                        id: method.id, title: method.selection.title, detail: "", symbol: "square.stack",
                        action: .method(method.selection))
                }.filter(matches).prefix(6))
        case "@":
            let notes = noteChoices.filter {
                $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) != nil
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { note in
                Candidate(
                    id: note.id, title: note.title, detail: note.reference.relativePath,
                    symbol: "doc.text", action: .note(note))
            }.filter(matches)
            return Array(notes.prefix(5)) + [
                Candidate(
                    id: "choose-file", title: ScholiumL10n.string("Choose File…"),
                    detail: "", symbol: "folder", action: .file)
            ]
        default:
            var actions: [Candidate] = [
                .init(id: "file", title: ScholiumL10n.string("Choose File…"), detail: "@", symbol: "folder", action: .file),
                .init(id: "note", title: ScholiumL10n.string("Choose Note…"), detail: "@", symbol: "doc.text", action: .notePicker),
                .init(id: "skills", title: ScholiumL10n.string("Skills"), detail: "$", symbol: "square.stack", action: .methods),
                .init(id: "context", title: ScholiumL10n.string("Context"), detail: "", symbol: "text.alignleft", action: .context),
                .init(id: "selection", title: ScholiumL10n.string("Add Selection to Chat"), detail: "", symbol: "text.badge.plus", action: .selection),
            ]
            if !controller.isBusy {
                actions += AgentChatPreferences.WebSearch.allCases.map { mode in
                    Candidate(
                        id: "web search " + mode.rawValue, title: ScholiumL10n.string("Web Search"),
                        detail: AgentChatControlLabels.webSearch(mode), symbol: "globe", action: .webSearch(mode))
                }
            }
            actions += [
                .init(id: "refresh skills", title: ScholiumL10n.string("Refresh Skills"), detail: "", symbol: "arrow.clockwise", action: .refreshMethods),
                .init(id: "manage skills", title: ScholiumL10n.string("Manage Skills…"), detail: "", symbol: "gearshape", action: .manageMethods),
            ]
            return Array(actions.filter(matches).prefix(6))
        }
    }

    private func chooseCompletion(_ candidate: AgentChatComposerCandidate, in conversationID: UUID?) {
        guard let conversationID, conversationID == controller.selectedID else { return }
        switch candidate.action {
        case .file: chooseFiles()
        case .notePicker: notePickerTarget = .init(id: conversationID)
        case .selection: addSelection()
        case .methods:
            completion.editor?.insertText("$", replacementRange: NSRange(location: NSNotFound, length: 0))
        case .refreshMethods:
            controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
        case .manageMethods:
            UserDefaults.standard.set("integrations", forKey: "scholium.settings.selectedPane")
            UserDefaults.standard.set(SettingsIntegrationCategory.agents.rawValue, forKey: "scholium.settings.integrationCategory")
            openSettings()
        case .context: showsContext = true
        case .webSearch(let mode): controller.setWebSearch(mode)
        case .method(let method): controller.toggleMethod(method)
        case .note(let note):
            guard materialTask == nil else { return }
            materialTask = Task { @MainActor in
                defer { materialTask = nil }
                do { try await addNote(note, conversationID) } catch { controller.reportMaterialError(error.localizedDescription, in: conversationID) }
            }
        }
    }

    private var contextPanel: some View {
        AgentChatContextView(
            usage: controller.selected?.contextUsage,
            ledger: AgentChatContextLedger(
                conversation: controller.selected,
                modelName: controller.selectedModel?.name ?? controller.selected?.preferences.model,
                effort: controller.selectedEffort),
            quotas: controller.quotas, quotaError: controller.quotaError,
            isRefreshing: controller.isRefreshingQuota, canRefresh: controller.account != nil,
            canCompact: controller.canCompact,
            compact: {
                showsContext = false
                controller.compactContext()
            },
            refresh: controller.refreshQuota)
    }

    private var pendingRequest: AgentChatApproval? {
        controller.approvals.first(where: { !$0.isSubmitting }) ?? controller.approvals.first
    }

    private var inputDock: some View {
        let conversationID = controller.selectedID
        let pending = pendingRequest
        let asyncMessage = pending == nil ? controller.pendingAsyncQuestion : nil
        let title =
            pending?.toolQuestionContext != nil
            ? String(localized: "Tool Input Request", bundle: .module)
            : pending?.questions.isEmpty == false || asyncMessage != nil
                ? String(localized: "Answer Agent", bundle: .module)
                : String(localized: "Review Permission", bundle: .module)
        let turnID = controller.currentTurnID
        return VStack(spacing: 0) {
            if !controller.queuedMessages.isEmpty {
                AgentChatQueueView(
                    messages: controller.queuedMessages,
                    canSend: { controller.canSendQueuedMessage($0.id) },
                    send: { _ = controller.sendQueuedMessage($0) },
                    canSteer: { controller.canSteerQueuedMessage($0.id) },
                    steer: { id in if let turnID { _ = controller.steerQueuedMessage(id, expectedTurnID: turnID) } },
                    remove: { controller.removeQueuedMessage($0) },
                    edit: { message in
                        guard let conversationID else { return }
                        queueEditTarget = .init(conversationID: conversationID, message: message)
                    })
            }
            AgentChatInputDock(
                requestID: pending.map { "approval:\($0.id)" } ?? asyncMessage.map { "question:\($0.id)" }, requestTitle: title,
                requestCount: controller.approvals.count + (asyncMessage == nil ? 0 : 1), isActive: isVisible && !showsConversationList,
                isReadingHistory: isAwayFromLatest || readingIsPaused || transcriptIsScrolling,
                isEditingDraft: messageIsFocused
                    && (controller.selected?.draft.isEmpty == false
                        || (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true),
                composerIsFocused: $messageIsFocused
            ) {
                if let pending {
                    approvalView(pending)
                } else if let message = asyncMessage, let request = message.asyncQuestion {
                    AgentChatQuestionForm(
                        questions: request.remaining,
                        answers: Binding(
                            get: { controller.selected?.messages.first { $0.id == message.id }?.asyncQuestion?.answers ?? [:] },
                            set: { controller.editAsyncAnswers(message.id, values: $0) }),
                        isSubmitting: request.pendingMessageID != nil, failure: controller.error,
                        reply: { controller.answerAsyncQuestion(message.id) },
                        skip: { controller.answerAsyncQuestion(message.id, skip: true) }
                    )
                    .id(request.remaining.map(\.id))
                }
            } composer: {
                composer
            }
            .padding(.top, controller.queuedMessages.isEmpty ? 0 : -28)
        }
    }

    private var composer: some View {
        let conversationID = controller.selectedID
        return VStack(alignment: .leading) {
            if let methods = controller.selected?.selectedMethods, !methods.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(methods) { method in
                            Button {
                                controller.toggleMethod(method)
                            } label: {
                                Label(method.title, systemImage: ScholiumSidebarAction.remove.symbol)
                            }
                            .help("Remove Skill").accessibilityLabel("Remove Skill: \(method.title)")
                        }
                    }.font(.caption)
                }
                if controller.capabilities.isRefreshing {
                    ProgressView("Loading Skills…").controlSize(.small)
                } else if !methods.allSatisfy(controller.capabilities.contains) {
                    Text("A selected Skill is unavailable. Refresh Skills or remove it to continue.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if controller.selected?.attachments.isEmpty == false || controller.selected?.localMaterials.isEmpty == false {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(controller.selected?.attachments ?? []) { attachment in
                            AgentChatMaterialChip(
                                attachment: attachment,
                                remove: { controller.removeAttachment(attachment.id) },
                                open: { openAttachment(attachment) })
                        }
                        ForEach(controller.selected?.localMaterials ?? []) { material in
                            AgentChatLocalMaterialChip(
                                material: material, preview: { try await controller.previewLocalMaterial(material) },
                                remove: { if let conversationID { controller.removeLocalMaterial(material.id, from: conversationID) } },
                                replace: { chooseFiles(replacing: material.id) },
                                usePages: {
                                    if let conversationID { pdfPagesTarget = .init(material: material, conversationID: conversationID) }
                                })
                        }
                    }.padding(.vertical, 4)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let conversationID, controller.preparingMaterials.contains(conversationID) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Preparing Material").font(.caption)
                    Spacer()
                    Button("Cancel") { controller.cancelMaterialPreparation(in: conversationID) }
                }
            }
            if let message = controller.materialInputIssue ?? conversationID.flatMap({ controller.materialErrors[$0] }) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            quoteCards(controller.selected?.draftReplyQuotes ?? [], editable: true)
            if let target = controller.selected?.draftCoordinationTarget {
                coordinationReference(target, editable: true)
                if target.parentThreadID != controller.selected?.threadID {
                    Text("This Agent belongs to the original conversation.", bundle: .module)
                        .font(.caption).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                }
            }
            AgentChatComposerInput(
                text: Binding(
                    get: { controller.selected?.draft ?? "" },
                    set: { value in
                        if let conversationID { controller.editDraft(value, in: conversationID) }
                    }),
                isFocused: Binding(get: { messageIsFocused }, set: { messageIsFocused = $0 }),
                conversationID: conversationID,
                isEnabled: controller.isLoaded,
                submit: { controller.submitDraft(whileWorking: inputBehavior) },
                completion: completion, candidates: completionCandidates, candidateQuery: completion.query,
                chooseCompletion: { candidate in chooseCompletion(candidate, in: conversationID) },
                transferMaterials: { materials, origin in
                    guard let conversationID else { return }
                    guard materialTask == nil else {
                        controller.reportMaterialError(ScholiumL10n.string("Finish preparing the current material before adding another."), in: conversationID)
                        return
                    }
                    materialTask = Task { @MainActor in
                        defer { materialTask = nil }
                        await controller.addTransferredMaterials(materials, origin: origin, to: conversationID) { item in
                            let note = try AgentChatPasteboardSnapshot.resolve(item, in: noteChoices)
                            try await addNote(note, conversationID)
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            HStack {
                Menu {
                    Button("Choose File…") { chooseFiles() }.disabled(materialTask != nil)
                    Button("Choose Note…") {
                        if let id = controller.selectedID { notePickerTarget = .init(id: id) }
                    }
                    Button("Add Selection to Chat", action: addSelection)
                    Divider()
                    Menu("Skills") {
                        ForEach(controller.capabilities.methods.filter { !$0.isProtected }) { method in
                            Toggle(
                                method.selection.title,
                                isOn: Binding(
                                    get: { controller.selected?.selectedMethods?.contains(where: { $0.id == method.id }) == true },
                                    set: { _ in controller.toggleMethod(method.selection) })
                            )
                            .disabled(!method.enabled)
                        }
                        Divider()
                        Button("Refresh Skills") { controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true) }
                            .disabled(!controller.capabilities.isConnected || controller.capabilities.isRefreshing)
                        Button("Manage Skills…") {
                            UserDefaults.standard.set("integrations", forKey: "scholium.settings.selectedPane")
                            UserDefaults.standard.set(SettingsIntegrationCategory.agents.rawValue, forKey: "scholium.settings.integrationCategory")
                            openSettings()
                        }
                    }
                    Menu("Web Search") {
                        Picker(
                            "Web Search",
                            selection: Binding(
                                get: { controller.selected?.preferences.webSearch ?? .runtimeDefault },
                                set: controller.setWebSearch)
                        ) {
                            ForEach(AgentChatPreferences.WebSearch.allCases, id: \.self) { mode in
                                Text(AgentChatControlLabels.webSearch(mode)).tag(mode)
                            }
                        }
                    }.disabled(controller.isBusy)
                    AgentChatModelMenu(
                        models: controller.models,
                        preferences: controller.selected?.preferences ?? .init(), selectedModel: controller.selectedModel,
                        isEnabled: !controller.isBusy && controller.account != nil,
                        selectModel: controller.setModel, selectEffort: controller.setEffort)
                    Menu("Permission") {
                        Picker(
                            "Permission",
                            selection: Binding(
                                get: { controller.selected?.permission ?? .ask }, set: controller.setPermission)
                        ) {
                            Text("Ask for Approval").tag(AgentChatPermission.ask)
                            Text("Full Access").tag(AgentChatPermission.fullAccess)
                        }
                    }.disabled(controller.isBusy)
                    Button("Context and Usage") { showsContext = true }
                    if [.working, .compacting, .stopping].contains(controller.state) {
                        Divider()
                        Button("Stop") { controller.stop() }
                            .keyboardShortcut(".", modifiers: .command)
                            .disabled(controller.state == .stopping)
                    }
                } label: {
                    Label("Chat Actions", systemImage: ScholiumSidebarAction.add.symbol).labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                }
                .help("Chat Actions").accessibilityLabel("Chat Actions")
                .accessibilityIdentifier("scholium.chat.addMaterial")
                Spacer(minLength: 0)
                AgentChatComposerActionButton(
                    state: controller.state, canSend: controller.canSend,
                    queuesInput: inputBehavior == .queue,
                    submit: {
                        guard (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return }
                        controller.submitDraft(whileWorking: inputBehavior)
                    }, stop: controller.stop)
            }
            .controlSize(.regular)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            if controller.state == .disconnected && controller.selected?.draft.isEmpty == false {
                Text("Connect an agent before sending.").font(.caption).foregroundStyle(.secondary)
            }
            if !controller.selectionIsAvailable {
                Text("Choose an available model and reasoning level.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
        .overlay(alignment: .top) {
            if completion.query != nil {
                AgentChatComposerCandidates(completion: completion, candidates: completionCandidates)
                    .offset(y: -(CGFloat(max(1, completionCandidates.count)) * 44 + 18))
            }
        }
    }

    @ViewBuilder
    private func approvalView(_ approval: AgentChatApproval) -> some View {
        if let request = approval.runtimeApproval {
            AgentChatRuntimeApprovalView(
                request: request,
                decision: approval.runtimeDecision, failure: approval.failure, stop: controller.stop
            ) {
                controller.answerRuntimeApproval(approval.id, decision: $0)
            }.id(approval.id)
        } else if !approval.questions.isEmpty {
            AgentChatQuestionForm(
                questions: approval.questions,
                answers: Binding(
                    get: { controller.questionAnswers(approval.id) },
                    set: { controller.editQuestionAnswers(approval.id, values: $0) }),
                isSubmitting: approval.submission != nil, failure: approval.failure,
                toolContext: approval.toolQuestionContext, technicalDetail: approval.toolInputDetails,
                stop: controller.stop, reply: { controller.answer(approval.id, allow: true) },
                skip: { controller.answer(approval.id, allow: false) }
            )
            .id(approval.id)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(approval.title).font(.headline).padding(.horizontal, 4)
                if approval.updatePreview != nil {
                    Button("Review Changes") { comparisonRequest = approval }
                        .accessibilityIdentifier("scholium.chat.reviewProposedChanges")
                }
                AgentChatContentScroll {
                    Text(approval.detail).font(.callout).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button("Decline") { controller.answer(approval.id, allow: false) }
                    Spacer(minLength: 8)
                    Button("Allow Once") { controller.answer(approval.id, allow: true) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                }.controlSize(.regular)
            }.buttonStyle(.borderless).id(approval.id)
        }
    }
}
