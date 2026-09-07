import AppKit
import ScholiumContracts
import SwiftUI

struct AgentChatView: View {
  @Environment(\.openSettings) private var openSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject var controller: AgentChatController
  let isVisible: Bool
  let addSelection: () -> Void
  let openReference: (URL) -> Bool
  let openAttachment: (AgentChatAttachment) -> Void
  let showInLibrary: (URL) -> Void
  let showChanges: (UUID) -> Void
  let showConversationChanges: ([UUID]) -> Void
  @State private var approvalAnswers: [String: String] = [:]
  @State private var showsArchived = false
  @State private var isSelectingChats = false
  @State private var selectedChatIDs: Set<UUID> = []
  @State private var isAwayFromLatest = false
  @State private var showsConversationList = true
  @State private var showsFiles = false
  @FocusState private var messageIsFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      header
      connectionStatus
      if showsConversationList {
        conversationList
        if isSelectingChats { selectionActions }
      } else {
        conversationDetail
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scholium.chat")
    .onChange(of: showsConversationList) { _, _ in endChatSelection() }
    .onChange(of: showsArchived) { _, _ in endChatSelection() }
    .onChange(of: controller.conversations.map(\.id)) { _, ids in
      selectedChatIDs.formIntersection(ids)
    }
    .onChange(of: controller.contextPresentationID) { _, _ in
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
      if !visible {
        messageIsFocused = false
        showsFiles = false
      }
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
        .disabled(controller.isBusy || !controller.isLoaded || isSelectingChats)
        .help("New Conversation").accessibilityLabel("New Conversation")
        .accessibilityIdentifier("scholium.chat.newConversation")
        if showsConversationList {
          archiveMenu
        } else {
          Menu {
            Button("Conversation Changes") {
              showConversationChanges(controller.selected?.messages.compactMap(\.changeID) ?? [])
            }.accessibilityIdentifier("scholium.chat.changeHistory")
          } label: {
            ScholiumSidebarHeaderIcon(systemImage: "ellipsis")
          }
          .scholiumSidebarHeaderControl()
          .accessibilityLabel("Chat Options")
          .accessibilityIdentifier("scholium.chat.options")
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
      .disabled(controller.isBusy || visibleConversations.isEmpty)
    } label: {
      ScholiumSidebarHeaderIcon(systemImage: "archivebox")
    }
    .scholiumSidebarHeaderControl()
    .help("Archived Chats").accessibilityLabel("Archived Chats")
    .accessibilityIdentifier("scholium.chat.archived")
  }

  @ViewBuilder
  private var connectionStatus: some View {
    if controller.state == .disconnected {
      Button("Connect Codex") { controller.connectConfigured() }
        .disabled(!controller.isLoaded).padding(8)
    } else if controller.state == .connecting {
      ProgressView("Connecting…").controlSize(.small).padding(8)
    } else if controller.account == nil {
      Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy).padding(8)
    }
    if let error = controller.error {
      VStack(alignment: .leading, spacing: 6) {
        Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
        !$0.messages.isEmpty || !$0.draft.isEmpty || !$0.attachments.isEmpty || $0.archivedAt != nil
      }
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
                        if controller.isBusy && controller.selectedID == conversation.id {
                          Image(systemName: "ellipsis").accessibilityLabel("In Progress")
                        } else if !isSelectingChats {
                          Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                        }
                      }
                      Text(
                        !conversation.draft.isEmpty
                          ? conversation.draft
                          : conversation.messages.last(where: { $0.role != .operation }).map {
                            String($0.text.prefix(120))
                          } ?? ""
                      )
                      .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                  }
                  .padding(.horizontal, ScholiumSidebarLayout.rowInset).padding(.vertical, 14)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(
                  controller.isBusy
                    && (isSelectingChats || controller.selectedID != conversation.id)
                )
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
            showsArchived
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
        guard !controller.isBusy else { return }
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
      .disabled(selectedChatIDs.isEmpty || controller.isBusy)
      .accessibilityIdentifier("scholium.chat.applySelection")
    }
    .padding(12)
  }

  private func endChatSelection() {
    isSelectingChats = false
    selectedChatIDs.removeAll()
  }

  private var conversationDetail: some View {
    VStack(spacing: 0) {
      if controller.selected?.pendingMessageID != nil, !controller.isBusy {
        Button("Continue Without Resending") { controller.confirmContinueAfterUncertainDelivery() }
          .padding(8)
      }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            if controller.selected?.messages.isEmpty != false {
              Text("Discuss your research here. Add a passage or name a note to begin.")
                .foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(AgentChatTimelineItem.group(controller.selected?.messages ?? [])) { item in
              timelineItem(item).id(item.id)
            }
            Color.clear.frame(height: 1).id("latest")
          }.padding(.horizontal, ScholiumSidebarLayout.textInset)
            .padding(.vertical, ScholiumSidebarLayout.edgeInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)
        .environment(
          \.openURL,
          OpenURLAction { url in
            if url.scheme == "scholium-note" {
              _ = openReference(url)
              return .handled
            }
            return url.scheme == "https" || url.scheme == "http" ? .systemAction : .discarded
          }
        )
        .onScrollGeometryChange(for: Bool.self) { geometry in
          geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            > 100
        } action: { _, away in
          isAwayFromLatest = away
        }
        if isAwayFromLatest {
          Button("Latest Reply") { proxy.scrollTo("latest", anchor: .bottom) }
            .buttonStyle(.link).font(.caption).padding(.bottom, 8)
        }
      }
      if let approval = controller.approvals.first { approvalView(approval) }
      currentActivity
      filesButton
      if controller.selected?.archivedAt != nil {
        Button("Restore Chat") {
          if let id = controller.selectedID {
            controller.setArchived(id, archived: false)
            showsArchived = false
          }
        }.padding()
      } else {
        composer
      }
    }
    .task { if isVisible { messageIsFocused = true } }
    .id(controller.selectedID)
  }

  @ViewBuilder
  private func timelineItem(_ item: AgentChatTimelineItem) -> some View {
    if item.isActivity {
      VStack(alignment: .leading, spacing: 8) {
        let quiet = item.messages.filter { $0.activity?.status == .completed || $0.activity == nil }
        let notable = item.messages.filter {
          $0.activity != nil && $0.activity?.status != .completed
        }
        if !quiet.isEmpty {
          DisclosureGroup {
            ForEach(quiet) { message in activityRow(message) }
          } label: {
            Text(activitySummary(quiet))
              .foregroundStyle(.secondary)
          }
        }
        ForEach(notable) { message in activityRow(message) }
      }.font(.callout)
    } else if let message = item.messages.first {
      messageView(message, showsSpeaker: item.showsSpeaker)
    }
  }

  private func activitySummary(_ messages: [AgentChatMessage]) -> String {
    var kinds: [AgentChatActivity.Kind] = []
    for message in messages {
      if let kind = message.activity?.kind, !kinds.contains(kind) { kinds.append(kind) }
    }
    guard !kinds.isEmpty else { return String(localized: "Activities: \(messages.count)") }
    return kinds.map { kind in
      "\(kind.label) · \(messages.filter { $0.activity?.kind == kind }.count)"
    }.joined(separator: "   ")
  }

  private func messageView(_ message: AgentChatMessage, showsSpeaker: Bool) -> some View {
    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
      if showsSpeaker {
        Text(message.role == .user ? String(localized: "You") : "Codex")
          .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 6) {
        AgentChatMarkdown(text: message.text, expandsToFillWidth: message.role != .user)
        ForEach(noteReferences(in: message.text), id: \.absoluteString) { url in
          Menu {
            Button("Open Note") { _ = openReference(url) }
            Button("Show in Library") { showInLibrary(url) }
          } label: {
            Label(referenceName(url, in: message.text), systemImage: "doc")
          }
          .menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
          .font(.caption)
        }
        if !message.attachments.isEmpty {
          ScrollView(.horizontal) {
            HStack(spacing: 8) {
              ForEach(message.attachments) { attachment in
                AgentChatMaterialChip(attachment: attachment, remove: nil, open: { openAttachment(attachment) })
              }
            }
          }
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
    .accessibilityLabel(message.role == .user ? String(localized: "You") : "Codex")
    .contextMenu {
      Button("Quote in Reply") {
        controller.editDraft(
          (controller.selected?.draft ?? "") + "\n> "
            + message.text.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n")
      }
    }
  }

  private func noteReferences(in text: String) -> [URL] {
    guard
      let attributed = try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
    else { return [] }
    var seen: Set<URL> = []
    return attributed.runs.compactMap { run in
      guard let url = run.link, AgentChatReference.parse(url) != nil, seen.insert(url).inserted
      else { return nil }
      return url
    }
  }

  private func referenceName(_ url: URL, in text: String) -> String {
    guard let parsed = try? AttributedString(markdown: text) else {
      return String(localized: "Note Actions")
    }
    for run in parsed.runs where run.link == url { return String(parsed[run.range].characters) }
    return String(localized: "Note Actions")
  }

  @ViewBuilder
  private func activityRow(_ message: AgentChatMessage) -> some View {
    if let activity = message.activity {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(
            systemName: activity.status.isActive ? activity.kind.symbol : activity.status.symbol
          )
          .accessibilityHidden(true)
          Text(activity.kind.label)
          Spacer(minLength: 0)
          Text(activity.status.label).foregroundStyle(.secondary)
        }
        if !activity.subject.isEmpty {
          Text(activity.subject).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if !activity.detail.isEmpty {
          if activity.status == .failed || activity.status == .uncertain {
            Text(activity.detail).textSelection(.enabled)
          } else {
            DisclosureGroup("Operation Details") {
              Text(activity.detail).monospaced().textSelection(.enabled)
            }
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
                  : activity?.kind.label ?? String(localized: "Codex is responding…"))
          if let subject = activity?.subject, !subject.isEmpty {
            Text(subject).lineLimit(2).help(subject)
          }
        }
        Spacer(minLength: 0)
      }
      .font(.caption).foregroundStyle(.secondary)
      .padding(.horizontal, 12).padding(.top, 8)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("scholium.chat.currentActivity")
    }
  }

  @ViewBuilder
  private var filesButton: some View {
    let files = AgentChatFileSummary.collect(controller.selected?.messages ?? [])
    let changed = files.filter { $0.file.effect?.isMutation == true }
    if !files.isEmpty {
      Button {
        showsFiles = true
      } label: {
        Label(
          changed.isEmpty
            ? String(localized: "Files: \(files.count)")
            : String(localized: "Changes: \(changed.count)"), systemImage: "doc.on.doc")
      }
      .buttonStyle(.borderless).font(.caption).padding(.top, 10)
      .accessibilityIdentifier("scholium.chat.showFiles")
      .popover(isPresented: $showsFiles, arrowEdge: .bottom) {
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

  @ViewBuilder
  private var fileSummary: some View {
    let files = AgentChatFileSummary.collect(controller.selected?.messages ?? [])
    if !files.isEmpty {
      VStack(alignment: .leading, spacing: 10) {
        let changed = files.filter { $0.file.effect?.isMutation == true }
        let unchanged = files.filter { $0.file.effect?.isMutation != true }
        ForEach(changed) { file in fileRow(file) }
        if !unchanged.isEmpty {
          DisclosureGroup {
            ForEach(unchanged) { file in fileRow(file) }
          } label: {
            Text(String(localized: "Without Recorded Edits: \(unchanged.count)"))
              .foregroundStyle(.secondary)
          }
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

  private var composer: some View {
    let conversationID = controller.selectedID
    return VStack(alignment: .leading) {
      if controller.selected?.attachments.isEmpty == false {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(controller.selected?.attachments ?? []) { attachment in
              AgentChatMaterialChip(attachment: attachment,
                remove: { controller.removeAttachment(attachment.id) },
                open: { openAttachment(attachment) })
            }
          }.padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
      AgentChatComposerInput(
        text: Binding(get: { controller.selected?.draft ?? "" }, set: { value in
          if let conversationID { controller.editDraft(value, in: conversationID) }
        }),
        isFocused: Binding(get: { messageIsFocused }, set: { messageIsFocused = $0 }),
        conversationID: conversationID,
        isEnabled: controller.isLoaded,
        submit: { if controller.canSend { controller.send() } }
      )
      .overlay(alignment: .topLeading) {
        if controller.selected?.draft.isEmpty != false {
          Text("Message").font(.body).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6).allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity)
      HStack {
        Menu {
          Button("Add Selection to Chat", action: addSelection)
          if !controller.models.isEmpty {
            Picker("Model", selection: $controller.model) {
              Text("Runtime Default").tag("")
              ForEach(controller.models, id: \.self) { Text($0).tag($0) }
            }.disabled(controller.isBusy)
          }
        } label: {
          Label("Add Material", systemImage: "plus").labelStyle(.iconOnly)
            .foregroundStyle(.primary)
        }
        .help("Add Material").accessibilityLabel("Add Material")
        .accessibilityIdentifier("scholium.chat.addMaterial")
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
        if controller.state == .working || controller.state == .stopping {
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
    }
    .buttonStyle(.borderless)
    .padding(12)
    .scholiumFloatingSurface(in: RoundedRectangle(cornerRadius: 24))
    .padding(ScholiumSidebarLayout.edgeInset)
  }

  private func approvalView(_ approval: AgentChatApproval) -> some View {
    VStack(alignment: .leading) {
      Text(approval.title).font(.headline)
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
      ForEach(approval.questions, id: \.id) { question in
        Text(question.prompt).font(.body)
        if !question.options.isEmpty {
          Menu("Choose an Answer") {
            ForEach(question.options, id: \.self) { value in
              Button(value) { approvalAnswers[question.id] = value }
            }
          }
        }
        TextField(
          "Your Answer",
          text: Binding(
            get: { approvalAnswers[question.id] ?? "" }, set: { approvalAnswers[question.id] = $0 })
        )
      }
      HStack {
        Button("Decline") {
          controller.answer(approval.id, allow: false)
          approvalAnswers = [:]
        }
        Button(
          approval.questions.isEmpty ? String(localized: "Allow Once") : String(localized: "Reply")
        ) {
          controller.answer(approval.id, allow: true, values: approvalAnswers)
          approvalAnswers = [:]
        }
        .disabled(approval.questions.contains { (approvalAnswers[$0.id] ?? "").isEmpty })
      }
    }.padding().id(approval.id)
  }
}
