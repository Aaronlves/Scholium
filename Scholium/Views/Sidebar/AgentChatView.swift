import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct AgentChatView: View {
  @Environment(\.locale) private var locale
  @Environment(\.openSettings) private var openSettings
  @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
  @State private var showsArchived = false
  @State private var isSelectingChats = false
  @State private var selectedChatIDs: Set<UUID> = []
  @State private var isAwayFromLatest = false
  @State private var transcriptIsScrolling = false
  @State private var showsConversationList = true
  @State private var showsFiles = false
  @State private var showsContext = false
  @State private var completion = AgentChatComposerCompletion()
  @State private var notePickerTarget: AgentChatNotePicker.Target?
  @State private var pdfPagesTarget: AgentChatPDFPagesView.Target?
  @State private var comparisonRequest: AgentChatApproval?
  @State private var inspectedAgent: AgentChatChildController?
  @State private var materialTask: Task<Void, Never>?
  @State private var conversationQuery = ""
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
        ContextSearchField(text: $conversationQuery, prompt: "Search Conversations",
          identifier: "scholium.chat.search")
          .padding(.horizontal, ScholiumSidebarLayout.textInset).padding(.bottom, 8)
        conversationList
        if isSelectingChats { selectionActions }
      } else {
        conversationDetail
      }
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
        urls.allSatisfy(\.isFileURL) else { return false }
      prepareFiles(urls, to: id)
      return true
    }
    .onChange(of: showsConversationList) { _, _ in endChatSelection() }
    .onChange(of: showsArchived) { _, _ in endChatSelection() }
    .onChange(of: conversationQuery) { _, _ in endChatSelection() }
    .onChange(of: controller.selectedID) { _, _ in
      completion.dismiss()
      showsFiles = false
      showsContext = false
      isAwayFromLatest = false
      showsFind = false
      find = .init()
      renameID = nil
      showsRename = false
    }
    .onChange(of: controller.conversations.map(\.id)) { _, ids in
      selectedChatIDs.formIntersection(ids)
    }
    .onChange(of: controller.contextPresentationID, initial: true) { _, request in
      guard request != nil else { return }
      isSelectingChats = false
      selectedChatIDs.removeAll()
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
          ScholiumSidebarHeaderIcon(systemImage: "chevron.left")
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
            || controller.selected?.archivedAt != nil
          {
            controller.newConversation()
          }
          showsArchived = false
          showsConversationList = false
          messageIsFocused = true
        } label: {
          ScholiumSidebarHeaderIcon(systemImage: "square.and.pencil")
        }
        .scholiumSidebarHeaderControl()
        .disabled(!controller.isLoaded || isSelectingChats)
        .help("New Conversation").accessibilityLabel("New Conversation")
        .accessibilityIdentifier("scholium.chat.newConversation")
        if showsConversationList {
          archiveMenu
        } else {
          Menu {
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
            Button("Conversation Changes") {
              showConversationChanges(controller.selected?.messages.compactMap(\.changeID) ?? [])
            }.accessibilityIdentifier("scholium.chat.changeHistory")
          } label: {
            ScholiumSidebarHeaderIcon(systemImage: "ellipsis")
          }
          .scholiumSidebarHeaderControl()
          .accessibilityLabel("Chat Options")
          .accessibilityIdentifier("scholium.chat.options")
          .popover(isPresented: $showsContext) {
            AgentChatContextView(usage: controller.selected?.contextUsage,
              quotas: controller.quotas, quotaError: controller.quotaError,
              isRefreshing: controller.isRefreshingQuota, canRefresh: controller.account != nil,
              canCompact: controller.canCompact,
              compact: { showsContext = false; controller.compactContext() },
              refresh: controller.refreshQuota)
          }
        }
      }
    }
  }

  private var archiveMenu: some View {
    Menu {
      Button("Archived Chats") { showsArchived = true }
      Button(
        showsArchived
          ? String(localized: "Select Chats to Restore")
          : String(localized: "Select Chats to Archive")
      ) {
        selectedChatIDs.removeAll()
        isSelectingChats = true
      }
      .disabled(visibleConversations.isEmpty)
    } label: {
      ScholiumSidebarHeaderIcon(systemImage: "archivebox")
    }
    .scholiumSidebarHeaderControl()
    .help("Archived Chats").accessibilityLabel("Archived Chats")
    .accessibilityIdentifier("scholium.chat.archived")
  }

  @ViewBuilder
  private var connectionStatus: some View {
    if controller.isRenewingSettings {
      if let error = controller.settingsRenewalError {
        VStack(alignment: .leading, spacing: 6) {
          Text("Settings Could Not Be Applied").font(.caption)
          DisclosureGroup("Operation Details") { Text(verbatim: error).textSelection(.enabled) }.font(.caption)
          Button("Retry") { controller.renewSettingsWhenIdle() }
        }.padding(8)
      } else {
        ProgressView("Applying Settings…").controlSize(.small).padding(8)
      }
    } else if controller.connectionState == .disconnected {
      Button("Connect Codex") { controller.connectConfigured() }
        .disabled(!controller.isLoaded).padding(8)
    } else if controller.connectionState == .connecting {
      ProgressView("Connecting…").controlSize(.small).padding(8)
    } else if controller.account == nil {
      Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy).padding(8)
    }
    if let error = controller.error {
      VStack(alignment: .leading, spacing: 6) {
        Label("Conversation Needs Attention", systemImage: "exclamationmark.triangle").font(.caption)
        DisclosureGroup("Operation Details") { Text(verbatim: error).textSelection(.enabled) }
          .font(.caption).foregroundStyle(.secondary)
        if controller.state == .disconnected {
          Button("Agent Settings…") {
            UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
            UserDefaults.standard.set(
              "Agent Integration", forKey: "scholium.settings.researchGuidanceCategory")
            openSettings()
          }
        }
      }.padding(.horizontal, 14)
    }
  }

  private var visibleConversations: [AgentChatConversation] {
    controller.conversations.filter { ($0.archivedAt != nil) == showsArchived }
      .filter {
        !$0.messages.isEmpty || !$0.draft.isEmpty || !$0.attachments.isEmpty || !$0.localMaterials.isEmpty || $0.draftReplyQuotes?.isEmpty == false || $0.selectedMethods?.isEmpty == false || $0.archivedAt != nil
      }
      .filter { AgentChatSearch.contains($0, query: AgentChatSearch.query(conversationQuery)) }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  private var conversationList: some View {
    let conversations = visibleConversations
    let groups = Dictionary(grouping: conversations) {
      Calendar.current.startOfDay(for: $0.updatedAt)
    }
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: ScholiumSidebarLayout.sectionSpacing) {
        ForEach(groups.keys.sorted(by: >), id: \.self) { day in
          VStack(alignment: .leading, spacing: 8) {
            Group {
              if Calendar.current.isDateInToday(day) {
                Text("Today")
              } else if Calendar.current.isDateInYesterday(day) {
                Text("Yesterday")
              } else {
                Text(day, style: .date)
              }
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, ScholiumSidebarLayout.rowInset)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
              ForEach(groups[day] ?? []) { conversation in
                Button {
                  if isSelectingChats {
                    if !selectedChatIDs.insert(conversation.id).inserted {
                      selectedChatIDs.remove(conversation.id)
                    }
                  } else {
                    if controller.selectedID != conversation.id {
                      controller.select(conversation.id)
                    }
                    showsConversationList = false
                  }
                } label: {
                  HStack(spacing: 10) {
                    if isSelectingChats {
                      Image(
                        systemName: selectedChatIDs.contains(conversation.id)
                          ? "checkmark.circle.fill" : "circle"
                      )
                      .foregroundStyle(.secondary)
                      .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                      HStack {
                        Text(
                          conversation.title.isEmpty
                            ? String(localized: "New Conversation") : conversation.title
                        )
                        .font(.body).lineLimit(1)
                        Spacer(minLength: 4)
                        if controller.questionCount(in: conversation.id) > 0 {
                          Image(systemName: "questionmark.bubble").accessibilityLabel("Input Requested")
                        } else if controller.approvalCount(in: conversation.id) > 0 {
                          Image(systemName: "hand.raised").accessibilityLabel("Waiting for Approval")
                        } else if controller.isBusy(in: conversation.id) {
                          Image(systemName: "ellipsis").accessibilityLabel("In Progress")
                        } else if let status = conversation.lastRunStatus {
                          Image(systemName: status.symbol).foregroundStyle(.secondary)
                            .help(status.label).accessibilityLabel(status.label)
                        } else if !isSelectingChats {
                          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        }
                      }
                      Text(
                        conversationPreview(conversation)
                      )
                      .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                  }
                  .padding(.horizontal, ScholiumSidebarLayout.rowInset).padding(.vertical, 14)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSelectingChats && !controller.canArchive(conversation.id))
                .accessibilityAddTraits(
                  selectedChatIDs.contains(conversation.id) ? .isSelected : []
                )
                .accessibilityIdentifier("scholium.chat.conversation.\(conversation.id)")
                if conversation.id != groups[day]?.last?.id {
                  Divider().padding(.horizontal, ScholiumSidebarLayout.rowInset)
                }
              }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }
        }
        if conversations.isEmpty && controller.isLoaded {
          Text(
            !AgentChatSearch.query(conversationQuery).isEmpty
              ? String(localized: "No Matching Conversations")
              : showsArchived
              ? String(localized: "No Archived Chats")
              : String(localized: "Start a conversation about your research.")
          )
          .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
        }

      }.padding(ScholiumSidebarLayout.edgeInset)
    }
    .overlay {
      if !controller.isLoaded && controller.error == nil { ProgressView("Loading Conversations…") }
    }
    .accessibilityIdentifier("scholium.chat.conversations")
  }

  private var selectionActions: some View {
    HStack {
      Button("Cancel") { endChatSelection() }
        .keyboardShortcut(.cancelAction)
      Spacer(minLength: 4)
      Button {
        guard selectedChatIDs.allSatisfy(controller.canArchive) else { return }
        for conversation in visibleConversations where selectedChatIDs.contains(conversation.id) {
          controller.setArchived(conversation.id, archived: !showsArchived)
        }
        endChatSelection()
      } label: {
        if showsArchived {
          Text("Restore Selected Chats (\(selectedChatIDs.count))")
        } else {
          Text("Archive Selected Chats (\(selectedChatIDs.count))")
        }
      }
      .disabled(selectedChatIDs.isEmpty || !selectedChatIDs.allSatisfy(controller.canArchive))
      .accessibilityIdentifier("scholium.chat.applySelection")
    }
    .padding(12)
  }

  private func endChatSelection() {
    isSelectingChats = false
    selectedChatIDs.removeAll()
  }

  private func conversationPreview(_ conversation: AgentChatConversation) -> String {
    let query = AgentChatSearch.query(conversationQuery)
    if !query.isEmpty {
      return conversation.messages.lazy.compactMap { AgentChatSearch.passage(in: $0, query: query) }.first
        ?? AgentChatSearch.snippet(conversation.title, query: query)
    }
    return !conversation.draft.isEmpty ? conversation.draft
      : conversation.messages.last(where: { $0.role != .operation && !$0.text.isEmpty })
        .map { String($0.text.prefix(120)) } ?? ""
  }

  private func refreshFind(reset: Bool = false) {
    find.refresh(messages: controller.selected?.messages ?? [], reset: reset)
  }

  private func dismissFind() {
    showsFind = false
    find = .init()
    messageIsFocused = isVisible && controller.selected?.archivedAt == nil
  }

  private var timelineMessages: [AgentChatMessage] {
    let active = Set(controller.approvals.flatMap { approval -> [String] in
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

  private var conversationDetail: some View {
    VStack(spacing: 0) {
      if controller.selected?.pendingMessageID != nil, !controller.isBusy {
        Button("Continue Without Resending") { controller.confirmContinueAfterUncertainDelivery() }
          .padding(8)
      }
      ScrollViewReader { proxy in
        if showsFind {
          AgentChatFindBar(query: $find.query, focusRequest: findFocusRequest,
            position: find.position, count: find.messageIDs.count,
            move: { backwards in find.move(backwards: backwards) }, dismiss: dismissFind)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            if controller.selected?.messages.isEmpty != false {
              Text("Discuss your research here. Add a passage or name a note to begin.")
                .foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(AgentChatTimelineItem.group(timelineMessages)) { item in
              VStack(alignment: .leading, spacing: 6) {
                if showsFind, let message = item.messages.first(where: { $0.id == find.selectedID }),
                  let passage = AgentChatSearch.passage(in: message, query: AgentChatSearch.query(find.query)) {
                  Label("Matching Message", systemImage: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                  Text(passage).font(.callout).textSelection(.enabled)
                }
                timelineItem(item)
              }.id(item.id)
            }
            if let approval = controller.approvals.first(where: { !$0.isSubmitting }) ?? controller.approvals.first {
              approvalView(approval)
            }
            currentActivity
            Color.clear.frame(height: 1).id("latest")
          }.padding(.horizontal, ScholiumSidebarLayout.textInset)
            .padding(.vertical, ScholiumSidebarLayout.edgeInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.top, for: .alignment)
        .environment(
          \.openURL,
          OpenURLAction { url in
            if url.scheme == "scholium-chat" {
              guard let target = AgentChatReplyQuotation.target(url),
                controller.conversations.contains(where: { $0.id == target.conversationID
                  && $0.messages.contains(where: { $0.id == target.messageID }) }) else { return .discarded }
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
        .simultaneousGesture(TapGesture().onEnded { completion.dismiss() })
        .scrollEdgeEffectHidden(true, for: .bottom)
        .onScrollPhaseChange { _, phase in transcriptIsScrolling = phase.isScrolling }
        .onScrollGeometryChange(for: AgentChatScrollMetrics.self) { geometry in
          .init(height: geometry.contentSize.height, bottomInset: geometry.contentInsets.bottom,
            bottomDistance: geometry.contentSize.height
              - geometry.contentOffset.y - geometry.containerSize.height)
        } action: { previous, current in
          if transcriptIsScrolling { isAwayFromLatest = current.bottomDistance > 80 }
          else if !isAwayFromLatest && (previous.height != current.height || previous.bottomInset != current.bottomInset) {
            proxy.scrollTo("latest", anchor: .bottom)
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          VStack(spacing: 6) {
            HStack(spacing: 8) {
              filesButton
              if isAwayFromLatest {
                Button {
                  isAwayFromLatest = false
                  proxy.scrollTo("latest", anchor: .bottom)
                } label: {
                  Image(systemName: "arrow.down").padding(7)
                }
                .buttonStyle(.borderless).foregroundStyle(.primary)
                .glassEffect(.clear.interactive(), in: Circle())
                .help("Latest Reply").accessibilityLabel("Latest Reply")
              }
            }
            if controller.selected?.archivedAt != nil {
              Button("Restore Chat") {
                if let id = controller.selectedID {
                  controller.setArchived(id, archived: false)
                  showsArchived = false
                }
              }.buttonStyle(.glass).padding()
            } else { composer }
          }
        }
        .task(id: replyNavigation) {
          guard let target = replyNavigation, target.conversationID == controller.selectedID else { return }
          isAwayFromLatest = true
          proxy.scrollTo(target.messageID, anchor: .top)
        }
        .onChange(of: find.selectedID) { _, id in
          if let id, let item = AgentChatTimelineItem.group(timelineMessages)
            .first(where: { $0.messages.contains(where: { $0.id == id }) }) {
            isAwayFromLatest = true
            proxy.scrollTo(item.id, anchor: .top)
          }
        }
      }
    }
    .task { if isVisible { messageIsFocused = true } }
    .id(controller.selectedID)
  }

  @ViewBuilder
  private func timelineItem(_ item: AgentChatTimelineItem) -> some View {
    if item.isProcess {
      AgentChatProcessView(messages: item.messages,
        isActive: controller.isBusy && controller.currentTurnID != nil && item.messages.first?.turnID == controller.currentTurnID,
        hasFinalAnswer: timelineMessages.contains { $0.phase == .finalAnswer && $0.turnID == item.messages.first?.turnID },
        forceExpanded: showsFind && item.messages.contains { $0.id == find.selectedID }) { message in
          if message.activity != nil { activityRow(message) }
          else if let plan = message.plan { AgentChatPlanView(plan: plan) }
          else { AgentChatMarkdown(text: message.text).foregroundStyle(.secondary) }
      }
      AgentChatOperationFiles(files: AgentChatFileSummary.collect(item.messages).filter { $0.file.effect?.isMutation == true },
        open: { _ = openReference($0) }, showChanges: showChanges, showAll: { showsFiles = true })
    } else if let message = item.messages.first {
      messageView(message, showsSpeaker: item.showsSpeaker)
    }
  }

  private func messageView(_ message: AgentChatMessage, showsSpeaker: Bool) -> some View {
    let conversationID = controller.selectedID
    return VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
      if showsSpeaker {
        Text(message.role == .user ? ScholiumL10n.string("You", locale: locale) : "Codex")
          .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 6) {
        quoteCards(message.replyQuotes ?? [], editable: false)
        if let target = message.coordinationTarget {
          coordinationReference(target)
        }
        if let plan = message.plan { AgentChatPlanView(plan: plan) }
        if !message.text.isEmpty {
          AgentChatMarkdown(text: message.text, expandsToFillWidth: message.role != .user,
            quoteSelection: canQuote(message) ? { selection in quote(message, selection: selection, in: conversationID) } : nil)
        }
        AgentChatResultFiles(files: AgentChatResultFile.collect(message.text),
          open: { _ = openReference($0) }, showInLibrary: showInLibrary,
          showAll: { showsFiles = true })
        if message.role == .assistant, message.phase != .commentary, !message.text.isEmpty,
          (!controller.isBusy || message.turnID != controller.currentTurnID) {
          AgentChatReplyActions(text: message.text, openNote: { _ = openReference($0) },
            context: .init(reply: message, history: controller.selected?.messages ?? []),
            openAttachment: openAttachment, previewMaterial: { try await controller.previewLocalMaterial($0) })
        }
        if !message.attachments.isEmpty || !message.localMaterials.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(message.attachments) { attachment in
                AgentChatMaterialChip(attachment: attachment, remove: nil, open: { openAttachment(attachment) })
              }
              ForEach(message.localMaterials) { material in
                AgentChatLocalMaterialChip(material: material, preview: { try await controller.previewLocalMaterial(material) }, remove: nil, replace: nil)
              }
            }
          }
        }
        ForEach(message.methods ?? []) { method in
          Label(method.title, systemImage: "square.stack").font(.caption).foregroundStyle(.secondary)
            .accessibilityLabel("Requested Method: \(method.title)")
        }
      }
      .padding(message.role == .user ? 12 : 0)
      .background {
        if message.role == .user {
          RoundedRectangle(cornerRadius: 18)
            .fill(ScholiumChatAppearance.userMessageBackground)
        }
      }
    }
    .padding(.leading, message.role == .user ? 24 : 0)
    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(message.role == .user ? ScholiumL10n.string("You", locale: locale) : "Codex")
    .contextMenu {
      if controller.editableRequests.contains(where: { $0.id == message.id }) {
        Button("Edit in New Branch") { controller.editInNewBranch(message.id) }
          .disabled(!controller.canBranch)
      }
      if let turnID = message.turnID {
        Button("Branch from This Turn") { controller.branch(through: turnID) }
          .disabled(!controller.canBranch || !controller.branchPoints.contains(where: { $0.turnID == turnID }))
      }
      if canQuote(message) {
        Button("Quote in Reply") { quote(message, selection: nil, in: conversationID) }
      }
    }
  }

  @ViewBuilder private func quoteCards(_ quotes: [AgentChatReplyQuote], editable: Bool) -> some View {
    if !quotes.isEmpty {
      let owner = controller.selectedID
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(quotes) { quote in
            AgentChatReplyQuoteCard(quote: quote, openOriginal: {
              guard controller.conversations.contains(where: { $0.id == quote.conversationID
                && $0.messages.contains(where: { $0.id == quote.messageID }) }) else {
                controller.reportMaterialError(ScholiumL10n.string("The original reply is unavailable."), in: owner ?? quote.conversationID)
                return
              }
              controller.select(quote.conversationID)
              replyNavigation = .init(conversationID: quote.conversationID, messageID: quote.messageID)
            }, remove: editable ? {
              if let owner { controller.removeReplyQuote(quote.id, in: owner) }
            } : nil)
          }
        }.padding(.vertical, 4)
      }.fixedSize(horizontal: false, vertical: true)
    }
  }

  private func canQuote(_ message: AgentChatMessage) -> Bool {
    message.role == .assistant && message.phase != .commentary && controller.selected?.archivedAt == nil
      && (!controller.isBusy || message.turnID != controller.currentTurnID)
  }

  private func quote(_ message: AgentChatMessage, selection: AgentChatReplySelection?, in conversationID: UUID?) {
    guard let id = conversationID,
      controller.quoteReply(message.id, selection: selection, in: id) else { return }
    messageIsFocused = true
  }

  private func coordinationReference(_ target: AgentChatCoordinationTarget, editable: Bool = false) -> some View {
    AgentChatCoordinationReferenceView(target: target,
      inspect: { inspectedAgent = controller.childController(target: target) },
      openParent: controller.canOpenParent(for: target) ? { controller.openParent(for: target) } : nil,
      remove: editable ? { controller.removeDraftCoordinationTarget() } : nil)
  }

  @ViewBuilder
  private func activityRow(_ message: AgentChatMessage) -> some View {
    if let activity = message.activity, let report = activity.delegation {
      AgentChatDelegationView(report: report, operationStatus: activity.status, openAgent: { target in
        guard let conversation = controller.selectedID else { return }
        inspectedAgent = controller.childController(targetID: target, messageID: message.id, in: conversation)
      })
        .accessibilityIdentifier("scholium.chat.activity.\(message.id)")
    } else if let activity = message.activity {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(
            systemName: activity.status.isActive ? activity.kind.symbol : activity.status.symbol
          )
          .accessibilityHidden(true)
          Text(AgentChatActivityProjection.title(activity, locale: locale))
          Spacer(minLength: 0)
          Text(activity.status.label).foregroundStyle(.secondary)
        }
        if let subject = AgentChatActivityProjection.subject(activity) {
          Text(verbatim: subject).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if !activity.subject.isEmpty || !activity.detail.isEmpty {
          DisclosureGroup("Operation Details") {
            if !activity.subject.isEmpty { Text(verbatim: activity.subject).monospaced().textSelection(.enabled) }
            if !activity.detail.isEmpty { Text(verbatim: activity.detail).monospaced().textSelection(.enabled) }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("scholium.chat.activity.\(message.id)")
    } else {
      Text(message.text).textSelection(.enabled)
    }
  }

  @ViewBuilder
  private var currentActivity: some View {
    if controller.isBusy && controller.approvals.isEmpty {
      let activity = controller.selected?.messages.reversed().compactMap(\.activity)
        .first { $0.status.isActive }
      HStack(alignment: .top, spacing: 8) {
        if reduceMotion || !controller.approvals.isEmpty {
          Image(systemName: controller.approvals.isEmpty ? "ellipsis" : "hand.raised")
            .accessibilityHidden(true)
        } else {
          ProgressView().controlSize(.small).accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(
            controller.state == .stopping
              ? String(localized: "Stopping…")
              : !controller.approvals.isEmpty
                ? String(localized: "Waiting for Approval")
              : controller.state == .connecting
                  ? String(localized: "Connecting…")
                  : controller.isRefreshingHistory
                    ? String(localized: "Loading Conversation…", bundle: .module)
                  : controller.state == .compacting
                    ? String(localized: "Compacting Context…", bundle: .module)
                  : controller.state == .branching
                    ? String(localized: "Creating Branch…", bundle: .module)
                  : activity.map { AgentChatActivityProjection.title($0, locale: locale) } ?? String(localized: "Codex is responding…"))
          if let subject = activity.flatMap(AgentChatActivityProjection.subject) {
            Text(subject).lineLimit(2).help(subject)
          }
        }
        Spacer(minLength: 0)
        if controller.state == .branching {
          Button("Cancel") { controller.stop() }
            .accessibilityIdentifier("scholium.chat.cancelBranch")
        }
      }
      .font(.caption).foregroundStyle(.secondary)
      .padding(.top, 8)
      .accessibilityElement(children: controller.state == .branching ? .contain : .combine)
      .accessibilityIdentifier("scholium.chat.currentActivity")
    } else if controller.selected?.lastRunStatus == .interrupted {
      Label(AgentChatActivity.Status.interrupted.label, systemImage: "stop.circle")
        .font(.caption).foregroundStyle(.secondary)
        .accessibilityIdentifier("scholium.chat.interrupted")
    }
  }

  @ViewBuilder
  private var filesButton: some View {
    let files = AgentChatFileSummary.collect(controller.selected?.messages ?? [])
    let changed = files.filter { $0.file.effect?.isMutation == true }
    if !files.isEmpty || !unrecordedResultFiles.isEmpty {
      Button {
        showsFiles = true
      } label: {
        Label(
          changed.isEmpty
            ? String(localized: "Files: \(files.count + unrecordedResultFiles.count)")
            : String(localized: "Changes: \(changed.count)"), systemImage: "doc.on.doc")
          .padding(.horizontal, 10).padding(.vertical, 7)
      }
      .buttonStyle(.borderless).font(.caption).foregroundStyle(.primary)
      .glassEffect(.clear.interactive(), in: Capsule())
      .accessibilityIdentifier("scholium.chat.showFiles")
      .popover(isPresented: $showsFiles, arrowEdge: .leading) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Files in This Conversation").font(.headline)
            Spacer()
            Button("Close") { showsFiles = false }.keyboardShortcut(.cancelAction)
          }
          ScrollView { fileSummary }
        }.padding().frame(width: 360, height: 360)
      }
    }
  }

  private func chooseFiles(replacing materialID: UUID? = nil) {
    guard materialTask == nil, let conversationID = controller.selectedID else { return }
    controller.reportMaterialError(nil, in: conversationID)
    materialTask = Task { @MainActor in
      defer { materialTask = nil }
      do {
        let urls = try await fileSelectionPresenter.requiredForFileSelection().selectURLs(.init(
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

  private var unrecordedResultFiles: [AgentChatResultFile] {
    let recorded = Set(AgentChatFileSummary.collect(controller.selected?.messages ?? []).compactMap { $0.file.noteID })
    var seen: Set<URL> = []
    return (controller.selected?.messages ?? []).filter { $0.role == .assistant }.flatMap {
      AgentChatResultFile.collect($0.text)
    }.filter { file in
      guard let target = AgentChatReference.parse(file.url) else { return false }
      return !recorded.contains(target.noteID) && seen.insert(file.url).inserted
    }
  }

  @ViewBuilder private var fileSummary: some View {
    let files = AgentChatFileSummary.collect(controller.selected?.messages ?? [])
    if !files.isEmpty || !unrecordedResultFiles.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        let changed = files.filter { $0.file.effect?.isMutation == true }
        let unchanged = files.filter { $0.file.effect?.isMutation != true }
        ForEach(changed) { file in fileRow(file) }
        if !unrecordedResultFiles.isEmpty {
          Text("Referenced Files").font(.caption).foregroundStyle(.secondary)
          ForEach(unrecordedResultFiles) { file in
            AgentChatResultFiles(files: [file], open: { _ = openReference($0) },
              showInLibrary: showInLibrary, showAll: {})
          }
        }
        if !unchanged.isEmpty {
          if !changed.isEmpty {
            Text(String(localized: "Without Recorded Edits: \(unchanged.count)"))
              .font(.caption).foregroundStyle(.secondary)
          }
          ForEach(unchanged) { file in fileRow(file) }
        }
      }.font(.callout)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.files")
    }
  }

  private func fileRow(_ summary: AgentChatFileSummary) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "doc.text").foregroundStyle(.secondary).accessibilityHidden(true)
        if let noteID = summary.file.noteID, summary.file.effect != .trashed {
          Button(summary.file.path) { _ = openReference(AgentChatReference.url(noteID: noteID)) }
            .buttonStyle(.link)
        } else {
          Text(summary.file.path).textSelection(.enabled)
        }
      }
      HStack(alignment: .firstTextBaseline) {
        Text(summary.file.effect?.label ?? "").foregroundStyle(.secondary)
        if summary.source == .runtime {
          Text("Runtime Report").foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if let id = summary.changeIDs.last {
          Button("View Changes") {
            showsFiles = false
            showChanges(id)
          }
        }
      }.font(.caption)
    }.accessibilityElement(children: .contain)
      .accessibilityIdentifier("scholium.chat.file.\(summary.id)")
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
      return Array(controller.capabilities.methods.filter { !$0.isProtected && $0.enabled }.map { method in
        Candidate(id: method.id, title: method.selection.title, detail: "", symbol: "square.stack",
          action: .method(method.selection))
      }.filter(matches).prefix(6))
    case "@":
      let notes = noteChoices.filter {
        $0.reference.stableNoteID.flatMap(UUID.init(uuidString:)) != nil
      }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { note in
        Candidate(id: note.id, title: note.title, detail: note.reference.relativePath,
          symbol: "doc.text", action: .note(note))
      }.filter(matches)
      return Array(notes.prefix(5)) + [Candidate(id: "choose-file", title: ScholiumL10n.string("Choose File…"),
        detail: "", symbol: "folder", action: .file)]
    default:
      var actions: [Candidate] = [
        .init(id: "file", title: ScholiumL10n.string("Choose File…"), detail: "@", symbol: "folder", action: .file),
        .init(id: "note", title: ScholiumL10n.string("Choose Note…"), detail: "@", symbol: "doc.text", action: .notePicker),
        .init(id: "methods skills", title: ScholiumL10n.string("Methods"), detail: "$", symbol: "square.stack", action: .methods),
        .init(id: "context", title: ScholiumL10n.string("Context"), detail: "", symbol: "text.alignleft", action: .context),
        .init(id: "selection", title: ScholiumL10n.string("Add Selection to Chat"), detail: "", symbol: "text.badge.plus", action: .selection)
      ]
      if !controller.isBusy {
        actions += AgentChatPreferences.WebSearch.allCases.map { mode in
          Candidate(id: "web search " + mode.rawValue, title: ScholiumL10n.string("Web Search"),
            detail: AgentChatControlLabels.webSearch(mode), symbol: "globe", action: .webSearch(mode))
        }
      }
      actions += [
        .init(id: "refresh methods", title: ScholiumL10n.string("Refresh Methods"), detail: "", symbol: "arrow.clockwise", action: .refreshMethods),
        .init(id: "manage methods skills", title: ScholiumL10n.string("Manage Methods…"), detail: "", symbol: "gearshape", action: .manageMethods)
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
      controller.capabilities.refresh(threadID: controller.selected?.threadID, applyAssociations: true)
    case .manageMethods:
      UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
      UserDefaults.standard.set("Agent Integration", forKey: "scholium.settings.researchGuidanceCategory")
      openSettings()
    case .context: showsContext = true
    case .webSearch(let mode): controller.setWebSearch(mode)
    case .method(let method): controller.toggleMethod(method)
    case .note(let note):
      guard materialTask == nil else { return }
      materialTask = Task { @MainActor in
        defer { materialTask = nil }
        do { try await addNote(note, conversationID) }
        catch { controller.reportMaterialError(error.localizedDescription, in: conversationID) }
      }
    }
  }

  private var composer: some View {
    let conversationID = controller.selectedID
    return VStack(alignment: .leading) {
      if let methods = controller.selected?.selectedMethods, !methods.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(methods) { method in
              Button { controller.toggleMethod(method) } label: {
                Label(method.title, systemImage: "xmark.circle")
              }
              .help("Remove Method").accessibilityLabel("Remove Method: \(method.title)")
            }
          }.font(.caption)
        }
        if controller.capabilities.isRefreshing {
          ProgressView("Loading Methods…").controlSize(.small)
        } else if !methods.allSatisfy(controller.capabilities.contains) {
          Text("A selected method is unavailable. Refresh Methods or remove it to continue.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if controller.selected?.attachments.isEmpty == false || controller.selected?.localMaterials.isEmpty == false {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(controller.selected?.attachments ?? []) { attachment in
              AgentChatMaterialChip(attachment: attachment,
                remove: { controller.removeAttachment(attachment.id) },
                open: { openAttachment(attachment) })
            }
            ForEach(controller.selected?.localMaterials ?? []) { material in
              AgentChatLocalMaterialChip(material: material, preview: { try await controller.previewLocalMaterial(material) },
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
        text: Binding(get: { controller.selected?.draft ?? "" }, set: { value in
          if let conversationID { controller.editDraft(value, in: conversationID) }
        }),
        isFocused: Binding(get: { messageIsFocused }, set: { messageIsFocused = $0 }),
        conversationID: conversationID,
        isEnabled: controller.isLoaded,
        submit: { if controller.canSend { controller.send() } },
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
      .overlay(alignment: .topLeading) {
        if controller.selected?.draft.isEmpty != false {
          Text("Message", bundle: .module).font(.body)
            .foregroundStyle(Color(nsColor: .placeholderTextColor))
            .padding(.horizontal, 9).padding(.vertical, 6).allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity)
      HStack {
        Menu {
          Button("Choose File…") { chooseFiles() }.disabled(materialTask != nil)
          Button("Choose Note…") {
            if let id = controller.selectedID { notePickerTarget = .init(id: id) }
          }
          Button("Add Selection to Chat", action: addSelection)
          Divider()
          Menu("Methods") {
          ForEach(controller.capabilities.methods.filter { !$0.isProtected }) { method in
            Toggle(method.selection.title, isOn: Binding(
              get: { controller.selected?.selectedMethods?.contains(where: { $0.id == method.id }) == true },
              set: { _ in controller.toggleMethod(method.selection) }))
              .disabled(!method.enabled)
          }
          Divider()
          Button("Refresh Methods") { controller.capabilities.refresh(threadID: controller.selected?.threadID, applyAssociations: true) }
            .disabled(!controller.capabilities.isConnected || controller.capabilities.isRefreshing)
          Button("Manage Methods…") {
            UserDefaults.standard.set("research-guidance", forKey: "scholium.settings.selectedPane")
            UserDefaults.standard.set("Agent Integration", forKey: "scholium.settings.researchGuidanceCategory")
            openSettings()
          }
          }
          Menu("Web Search") {
          Picker("Web Search", selection: Binding(
            get: { controller.selected?.preferences.webSearch ?? .runtimeDefault },
            set: controller.setWebSearch)) {
            ForEach(AgentChatPreferences.WebSearch.allCases, id: \.self) { mode in
              Text(AgentChatControlLabels.webSearch(mode)).tag(mode)
            }
          }
          }.disabled(controller.isBusy)
          Button("Context") { showsContext = true }
        } label: {
          Label("Chat Actions", systemImage: "plus").labelStyle(.iconOnly)
            .foregroundStyle(.primary)
        }
        .help("Chat Actions").accessibilityLabel("Chat Actions")
        .accessibilityIdentifier("scholium.chat.addMaterial")
        AgentChatModelMenu(models: controller.models,
          preferences: controller.selected?.preferences ?? .init(), selectedModel: controller.selectedModel,
          isEnabled: !controller.isBusy && controller.account != nil,
          selectModel: controller.setModel, selectEffort: controller.setEffort)
        Menu {
          Picker(
            "Permission",
            selection: Binding(
              get: { controller.selected?.permission ?? .ask }, set: controller.setPermission)
          ) {
            Text("Ask for Approval").tag(AgentChatPermission.ask)
            Text("Full Access").tag(AgentChatPermission.fullAccess)
          }
          .pickerStyle(.inline)
        } label: {
          Label(
            "Permission",
            systemImage: controller.selected?.permission == .fullAccess
              ? "shield" : "hand.raised"
          )
          .labelStyle(.iconOnly).foregroundStyle(.primary)
        }
        .disabled(controller.isBusy)
        .accessibilityLabel("Permission")
        .accessibilityValue(
          controller.selected?.permission == .fullAccess
            ? String(localized: "Full Access") : String(localized: "Ask for Approval")
        )
        .accessibilityIdentifier("scholium.chat.permission")
        .help(
          controller.selected?.permission == .fullAccess
            ? String(localized: "Full Access") : String(localized: "Ask for Approval"))
        Spacer(minLength: 0)
        if controller.state == .working || controller.state == .compacting || controller.state == .stopping {
          Button {
            controller.stop()
          } label: {
            Image(systemName: "stop.fill")
          }
          .disabled(controller.state == .stopping)
          .help("Stop").accessibilityLabel("Stop")
        }
        Button {
          controller.send()
        } label: {
          Image(systemName: "arrow.up")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(ScholiumColorRole.accent.color)
        .controlSize(.regular)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!controller.canSend)
        .help(controller.state == .disconnected
          ? String(localized: "Connect an agent before sending.", bundle: .module)
          : String(localized: "Send", bundle: .module))
        .accessibilityLabel("Send")
      }
      .controlSize(.regular)
      .scholiumMenuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      if controller.state == .disconnected && controller.selected?.draft.isEmpty == false {
        Text("Connect an agent before sending.").font(.caption).foregroundStyle(.secondary)
      }
      if !controller.selectionIsAvailable {
        Text("Choose an available model and reasoning level.").font(.caption).foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.borderless)
    .padding(12)
    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 24))
    .overlay(alignment: .top) {
      if completion.query != nil {
        AgentChatComposerCandidates(completion: completion, candidates: completionCandidates)
          .offset(y: -(CGFloat(max(1, completionCandidates.count)) * 44 + 18))
      }
    }
    .padding(ScholiumSidebarLayout.edgeInset)
  }

  @ViewBuilder
  private func approvalView(_ approval: AgentChatApproval) -> some View {
    if let request = approval.runtimeApproval {
      AgentChatRuntimeApprovalView(request: request, technicalDetail: approval.technicalDetail ?? "",
        decision: approval.runtimeDecision, failure: approval.failure) {
        controller.answerRuntimeApproval(approval.id, decision: $0)
      }.id(approval.id)
    } else if !approval.questions.isEmpty {
      AgentChatQuestionForm(questions: approval.questions, answers: Binding(
        get: { controller.questionAnswers(approval.id) },
        set: { controller.editQuestionAnswers(approval.id, values: $0) }),
        isSubmitting: approval.submission != nil, failure: approval.failure,
        toolContext: approval.toolQuestionContext, technicalDetail: approval.technicalDetail,
        reply: { controller.answer(approval.id, allow: true) },
        skip: { controller.answer(approval.id, allow: false) })
        .id(approval.id)
    } else {
    GroupBox {
    VStack(alignment: .leading) {
      if approval.updatePreview != nil {
        Button("Review Changes") { comparisonRequest = approval }
          .accessibilityIdentifier("scholium.chat.reviewProposedChanges")
      }
      ScrollView {
        Text(approval.detail).font(.caption).textSelection(.enabled).frame(
          maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 150)
      if let technicalDetail = approval.technicalDetail {
        DisclosureGroup("Operation Details") {
          ScrollView { Text(technicalDetail).font(.caption).textSelection(.enabled) }.frame(
            maxHeight: 100)
        }
      }
      HStack {
        Button("Decline") { controller.answer(approval.id, allow: false) }
        Spacer(minLength: 8)
        Button("Allow Once") { controller.answer(approval.id, allow: true) }
      }
    }.padding(6)
    } label: { Text(approval.title).font(.headline) }
    .padding().id(approval.id)
    }
  }
}

private struct AgentChatScrollMetrics: Equatable {
  let height: CGFloat
  let bottomInset: CGFloat
  let bottomDistance: CGFloat
}
