import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

/// One mounted conversation's transient presentation. Reading history outlives it.
struct AgentChatConversationDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @AppStorage(AgentChatInputBehavior.key) private var inputBehavior = AgentChatInputBehavior.steer
    @AppStorage(AgentChangeViewedLedger.key) private var viewedChangeData = Data()
    private var readingIsPaused: Bool {
        get { readingSession.isPaused }
        nonmutating set { if newValue { readingSession.pause() } else { readingSession.isPaused = false } }
    }
    private var isAwayFromLatest: Bool { readingSession.isAwayFromLatest }
    private var expandedActivityIDs: Set<String> {
        get { readingSession.expandedActivities }
        nonmutating set { readingSession.expandedActivities = newValue }
    }
    @State private var fileSelectionTask: Task<Void, Never>?

    @Bindable var presentation: AgentChatDetailPresentation
    let readingSession: AgentChatReadingSession
    let focusRequest: UUID?
    let consumeFocusRequest: (UUID) -> Void
    let replyNavigation: AgentChatReplyNavigation?
    let openReply: (AgentChatReplyNavigation) -> Void
    let showList: () -> Void
    let newConversation: () -> Void
    let didRestoreConversation: () -> Void
    let renameConversation: (AgentChatConversation) -> Void
    let showAccountUsage: () -> Void
    let showDiagnostics: (String?, String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            AgentChatConnectionStatus(controller: controller) { showDiagnostics(nil, $0) }
            conversationDetail
        }
        .sheet(item: $presentation.queueEditTarget) { target in
            AgentChatQueuedMessageEditor(
                message: target.message,
                save: { controller.editQueuedMessage(target.message.id, text: $0, in: target.conversationID) },
                close: { presentation.queueEditTarget = nil })
        }
        .sheet(item: $presentation.inspectedAgent) { child in
            AgentChatChildInspector(child: child, openReference: openReference)
        }
        .sheet(item: $presentation.notePickerTarget) { target in
            AgentChatNotePicker(notes: noteChoices) { note in try await prepareNote(note, in: target.id) }
        }
        .sheet(item: $presentation.pdfPagesTarget) { target in AgentChatPDFPagesView(controller: controller, target: target) }
        .sheet(item: $presentation.comparisonRequest) { request in
            if let preview = request.updatePreview {
                AgentChatUpdateComparisonSheet(controller: controller, requestID: request.id, preview: preview)
            }
        }
        .onDisappear { fileSelectionTask?.cancel() }
        .onChange(of: focusRequest, initial: true) { _, request in
            guard let request else { return }
            presentation.messageIsFocused = isVisible
            consumeFocusRequest(request)
        }
        .onChange(of: isVisible) { _, visible in
            if visible, controller.contextPresentationID != nil { presentation.messageIsFocused = true }
            if !visible {
                presentation.completion.dismiss()
                presentation.messageIsFocused = false
                presentation.showsFiles = false
                presentation.showsAgents = false
                presentation.contextAnchor = nil
            }
        }
        .onChange(of: presentation.find.query) { _, _ in refreshFind(reset: true) }
        .onChange(of: controller.selected?.messages) { _, _ in
            if presentation.showsFind { refreshFind() }
        }
    }

    private var header: some View {
        AgentChatHeader(
            title: controller.selected?.title.isEmpty == false ? controller.selected!.title : String(localized: "New Conversation"),
            back: showList, canCreate: controller.isLoaded, newConversation: newConversation
        ) {
            Menu {
                Button("Conversation Outline", systemImage: ScholiumSidebarAction.outline.symbol) {
                    presentation.showsTurns = true
                }
                .disabled(!timelineMessages.contains { $0.role == .user })
                .accessibilityIdentifier("scholium.chat.outlineButton")
                Button("Find in Conversation") {
                    openFind()
                }
                Button("Rename Conversation…") {
                    if let conversation = controller.selected { renameConversation(conversation) }
                }
                if let origin = controller.selected?.branchOrigin {
                    Button("Open Original Conversation") { controller.select(origin.conversationID) }
                        .disabled(!controller.conversations.contains(where: { $0.id == origin.conversationID }))
                }
                Divider()
                Button("Account Usage") { openAccountUsage() }
                if pendingRequest != nil || controller.pendingAsyncQuestion != nil || controller.selected?.isAvailable == false {
                    Button("Context Window") { presentation.contextAnchor = .conversation }
                }
                Button("Diagnostics…") {
                    showDiagnostics(nil, nil)
                }
            } label: {
                ScholiumSidebarHeaderIcon(systemImage: ScholiumSidebarAction.more.symbol)
            }
            .scholiumSidebarHeaderControl()
            .accessibilityLabel("Chat Options")
            .accessibilityIdentifier("scholium.chat.options")
            .popover(isPresented: contextIsPresented(at: .conversation), arrowEdge: .leading) {
                contextPanel
            }
            .popover(isPresented: $presentation.showsTurns, arrowEdge: .leading) {
                AgentChatConversationOutline(
                    messages: timelineMessages, currentMessageID: currentReadingRequestID
                ) { id in
                    presentation.showsTurns = false
                    revealMessage(id)
                }
            }
        }
    }

    private func openFind() {
        presentation.showsFind = true
        presentation.messageIsFocused = false
        presentation.findFocusRequest = UUID()
        refreshFind()
    }

    private func presentChanges() {
        presentation.showsAgents = false
        presentation.showsFiles = true
    }

    private func presentAgents(_ presented: Bool = true) {
        presentation.showsFiles = false
        presentation.showsAgents = presented
    }

    private func refreshFind(reset: Bool = false) {
        presentation.find.refresh(messages: controller.selected?.messages ?? [], reset: reset)
    }

    private func dismissFind() {
        presentation.showsFind = false
        presentation.find = .init()
        presentation.messageIsFocused = isVisible && controller.selected?.isAvailable == true
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
            !active.contains($0.id) || (presentation.showsFind && presentation.find.selectedID == $0.id)
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

    private var conversationDetail: some View {
        VStack(spacing: 0) {
            if controller.selected?.pendingMessageID != nil, !controller.isBusy {
                Button("Continue Without Resending") { controller.confirmContinueAfterUncertainDelivery() }
                    .padding(8)
            }
            Group {
                if presentation.showsFind {
                    AgentChatFindBar(
                        query: $presentation.find.query, focusRequest: presentation.findFocusRequest,
                        position: presentation.find.position, count: presentation.find.messageIDs.count,
                        move: { backwards in presentation.find.move(backwards: backwards) }, dismiss: dismissFind)
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
                                if presentation.showsFind, let message = item.messages.first(where: { $0.id == presentation.find.selectedID }),
                                    let passage = AgentChatSearch.passage(in: message, query: AgentChatSearch.query(presentation.find.query))
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
                            openReply(.init(conversationID: target.conversationID, messageID: target.messageID))
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
                .simultaneousGesture(TapGesture().onEnded { presentation.completion.dismiss() })
                .scrollEdgeEffectHidden(true, for: .bottom)
                .onScrollPhaseChange { _, phase in
                    presentation.transcriptIsScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    readingSession.isScrolling = presentation.transcriptIsScrolling
                    if phase == .tracking || phase == .interacting { readingSession.pause() }
                    if phase == .idle { readingSession.viewport?.capture() }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                        if hasConversationAccessories {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                                    conversationActivityButtons
                                    conversationNavigationButtons
                                }.fixedSize(horizontal: true, vertical: false)
                                VStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                                    conversationActivityButtons
                                    conversationNavigationButtons
                                }
                            }
                        }
                        if controller.selected?.isAvailable == false {
                            Button("Restore Chat") {
                                if let id = controller.selectedID {
                                    controller.setArchived(id, archived: false)
                                    didRestoreConversation()
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
                .onChange(of: presentation.find.selectedID) { _, id in
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
            if presentation.showsFind { refreshFind() }
            presentation.arrivalBaseline = Set(timelineMessages.map(\.id))
            if !readingIsPaused { readingSession.history.latest(in: timelineItems.map(\.id)) }
        }
        .onChange(of: timelineItems.map(\.id)) { _, ids in
            if !readingIsPaused { readingSession.history.latest(in: ids) }
        }
        .onDisappear { presentation.arrivalBaseline = nil }
        .task { if isVisible && pendingRequest == nil && controller.pendingAsyncQuestion == nil { presentation.messageIsFocused = true } }
        .id(controller.selectedID)
    }

    @ViewBuilder
    private func timelineItem(_ item: AgentChatTimelineItem) -> some View {
        if item.isProcess {
            AgentChatProcessView(
                messages: item.messages,
                isActive: controller.isBusy && controller.currentTurnID != nil && item.messages.first?.turnID == controller.currentTurnID,
                forceExpanded: presentation.showsFind && item.messages.contains { $0.id == presentation.find.selectedID },
                status: item.carriesTurnStatus(in: timelineMessages) ? turnPresentation(item.messages.first?.turnID) : nil,
                preservesReading: isAwayFromLatest || readingIsPaused || presentation.transcriptIsScrolling,
                hasInspectedActivity: item.messages.contains { expandedActivityIDs.contains($0.id) },
                animates: isVisible && !reduceMotion && controller.approvals.isEmpty,
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
                AgentChatTurnStatus(presentation: turnPresentation(message.turnID), animates: isVisible && !reduceMotion)
            }
            messageView(message)
            if message.role == .user && item.carriesTurnStatus(in: timelineMessages) {
                AgentChatTurnStatus(presentation: turnPresentation(message.turnID), animates: isVisible && !reduceMotion)
            }
        }
    }

    private func messageView(_ message: AgentChatMessage) -> some View {
        let conversationID = controller.selectedID
        return AgentChatMessageActionVisibility {
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
                                        material: material, isEmbeddedInComposer: true, preview: { try await controller.previewLocalMaterial(material) },
                                        remove: nil, replace: nil)
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
        } actions: {
            if message.role == .user || (message.role == .assistant && message.phase != .commentary && message.asyncQuestion == nil) {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    if message.role == .user { Spacer(minLength: 0) }
                    if message.role == .assistant, !message.text.isEmpty, !controller.isBusy || message.turnID != controller.currentTurnID {
                        AgentChatReplyActions(
                            text: message.text, openNote: { _ = openReference($0) },
                            context: .init(reply: message, history: controller.selected?.messages ?? []),
                            openAttachment: openAttachment, previewMaterial: { try await controller.previewLocalMaterial($0) })
                    }
                    if hasMessageActions(message) {
                        messageActions(message, in: conversationID)
                            .labelStyle(ScholiumSidebarActionLabelStyle())
                    }
                }
                .buttonStyle(ScholiumContentActionButtonStyle())
                .contextMenu { messageActions(message, in: conversationID) }
            }
        }
        .modifier(
            AgentChatMessageArrival(
                enabled: shouldAnimateArrival(message),
                waitsForContent: message.asyncQuestion == nil && !message.text.isEmpty)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.role == .user ? ScholiumL10n.string("You", locale: locale) : "Codex")
    }

    private func hasMessageActions(_ message: AgentChatMessage) -> Bool {
        controller.editableRequests.contains(where: { $0.id == message.id })
            || message.turnID.map { turnID in controller.branchPoints.contains(where: { $0.turnID == turnID }) } == true
            || canQuote(message)
    }

    @ViewBuilder
    private func messageActions(_ message: AgentChatMessage, in conversationID: UUID?) -> some View {
        if controller.editableRequests.contains(where: { $0.id == message.id }) {
            Button("Edit in New Branch", systemImage: ScholiumSidebarAction.edit.symbol) { controller.editInNewBranch(message.id) }
                .disabled(!controller.canBranch)
                .help("Edit in New Branch").accessibilityLabel("Edit in New Branch")
        }
        if let turnID = message.turnID, controller.branchPoints.contains(where: { $0.turnID == turnID }) {
            Button("Branch from This Turn", systemImage: ScholiumSidebarAction.branch.symbol) { controller.branch(through: turnID) }
                .disabled(!controller.canBranch)
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
        guard let arrivalBaseline = presentation.arrivalBaseline else { return false }
        return !arrivalBaseline.contains(message.id) && allowsReplyMotion
    }

    private var allowsReplyMotion: Bool {
        isVisible && !isAwayFromLatest && !readingIsPaused && !presentation.transcriptIsScrolling && !controller.isRefreshingHistory
    }

    @ViewBuilder private func quoteCards(_ quotes: [AgentChatReplyQuote], editable: Bool) -> some View {
        if !quotes.isEmpty {
            let owner = controller.selectedID
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(quotes) { quote in
                        AgentChatReplyQuoteCard(
                            quote: quote, isEmbeddedInComposer: editable,
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
                                openReply(.init(conversationID: quote.conversationID, messageID: quote.messageID))
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
        presentation.messageIsFocused = true
    }

    private func coordinationReference(_ target: AgentChatCoordinationTarget, editable: Bool = false) -> some View {
        AgentChatCoordinationReferenceView(
            target: target,
            inspect: { presentation.inspectedAgent = controller.childController(target: target) },
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

    @ViewBuilder
    private func activityRow(_ message: AgentChatMessage) -> some View {
        if let activity = message.activity {
            VStack(alignment: .leading, spacing: 4) {
                if let report = activity.delegation {
                    AgentChatDelegationView(
                        report: report, operationStatus: activity.status,
                        openAgent: { target in
                            guard let conversation = controller.selectedID else { return }
                            presentation.inspectedAgent = controller.childController(targetID: target, messageID: message.id, in: conversation)
                        },
                        expansion: Binding(
                            get: { expandedActivityIDs.contains(message.id) },
                            set: { expanded in
                                readingIsPaused = true
                                if expanded { expandedActivityIDs.insert(message.id) } else { expandedActivityIDs.remove(message.id) }
                            }))
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
                    showDiagnostics(message.id, nil)
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
            let hasHeader =
                controller.currentTurnID.map { turn in
                    timelineMessages.contains { $0.turnID == turn }
                } ?? false
            if !hasHeader {
                if controller.state == .working || controller.state == .stopping || controller.state == .compacting {
                    AgentChatTurnStatus(
                        presentation: turnPresentation(controller.currentTurnID),
                        animates: isVisible && !reduceMotion
                    )
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
        AgentChangeViewedLedger(data: viewedChangeData).pending(
            changes ?? [], receiptIDs: conversationChangeIDs)
    }

    private var conversationActivityButtons: some View {
        HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            filesButton
            agentsButton
        }
    }

    private var hasConversationAccessories: Bool {
        let hasChanges = !conversationChangeIDs.isEmpty
        let hasAgents =
            controller.selected.map {
                !AgentChatAgentRoster(messages: $0.messages, threadID: $0.threadID).entries.isEmpty
            } ?? false
        return hasChanges || hasAgents || isAwayFromLatest || readingSession.history.last != nil
    }

    private var conversationNavigationButtons: some View {
        HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            if isAwayFromLatest || readingSession.history.last != nil {
                Button {
                    readingSession.latest(in: timelineItems.map(\.id))
                } label: {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.later.symbol, placement: .action)
                }
                .scholiumIconControl()
                .help("Latest Reply").accessibilityLabel("Latest Reply")
            }
        }
    }

    @ViewBuilder private var agentsButton: some View {
        if let conversation = controller.selected {
            let agents = AgentChatAgentRoster(
                messages: conversation.messages, threadID: conversation.threadID
            ).entries
            if !agents.isEmpty {
                Button {
                    presentAgents(!presentation.showsAgents)
                } label: {
                    Label(
                        ScholiumL10n.string("\(agents.count) agents", locale: locale), systemImage: "person.2"
                    )
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                .accessibilityIdentifier("scholium.chat.showAgents")
                .popover(isPresented: $presentation.showsAgents, arrowEdge: .bottom) {
                    AgentChatAgentRosterView(entries: agents) { entry in
                        guard controller.selectedID == conversation.id else { throw CancellationError() }
                        guard
                            let child = controller.childController(
                                targetID: entry.id, messageID: entry.messageID, in: conversation.id)
                        else { throw AgentChatChildFailure.unverified }
                        defer { child.cancel() }
                        return try await child.readMetadata()
                    } open: { entry in
                        presentation.showsAgents = false
                        guard controller.selectedID == conversation.id else { return }
                        presentation.inspectedAgent = controller.childController(
                            targetID: entry.id, messageID: entry.messageID, in: conversation.id)
                    } close: {
                        presentation.showsAgents = false
                    }
                }
            }
        }
    }

    @ViewBuilder private var filesButton: some View {
        if !conversationChangeIDs.isEmpty {
            Button {
                presentChanges()
            } label: {
                Label(
                    changes == nil || pendingChanges.isEmpty ? String(localized: "Changes") : String(localized: "Changes: \(pendingChanges.count)"),
                    systemImage: "pencil.line"
                )
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
            .accessibilityIdentifier("scholium.chat.showFiles")
            .popover(isPresented: $presentation.showsFiles, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Changes to Review").font(.headline)
                        Spacer()
                        Button("Close") { presentation.showsFiles = false }.keyboardShortcut(.cancelAction)
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
                                            presentation.showsFiles = false
                                            showChanges(change.id)
                                        }
                                    }
                                }
                            }
                        }.frame(maxHeight: 280)
                    }
                    Button("All Changes") {
                        presentation.showsFiles = false
                        showConversationChanges(Array(conversationChangeIDs))
                    }
                }.padding().frame(width: 360)
            }
        }
    }

    private func chooseFiles(replacing materialID: UUID? = nil) {
        guard fileSelectionTask == nil, let conversationID = controller.selectedID,
            !controller.preparingMaterials.contains(conversationID)
        else { return }
        controller.reportMaterialError(nil, in: conversationID)
        fileSelectionTask = Task { @MainActor in
            do {
                let urls = try await fileSelectionPresenter.requiredForFileSelection().selectURLs(
                    .init(
                        kind: .files(allowedContentTypes: [.pdf, .plainText, .image], allowsMultipleSelection: materialID == nil)))
                fileSelectionTask = nil
                guard let urls, !Task.isCancelled else { return }
                prepareFiles(urls, to: conversationID, replacing: materialID)
            } catch {
                fileSelectionTask = nil
                if !(error is CancellationError) { controller.reportMaterialError(error.localizedDescription, in: conversationID) }
            }
        }
    }

    private func prepareFiles(_ urls: [URL], to conversationID: UUID, replacing materialID: UUID? = nil) {
        Task { @MainActor in
            await controller.addLocalFiles(urls, to: conversationID, replacing: materialID)
        }
    }

    private func prepareNote(_ note: WorkspaceCatalogNote, in conversationID: UUID) async throws {
        var failure: (any Error)?
        let prepared = await controller.performMaterialPreparation(in: conversationID) {
            do { try await addNote(note, conversationID) } catch {
                failure = error
                throw error
            }
        }
        guard prepared else { throw failure ?? CancellationError() }
    }

    private var completionCandidates: [AgentChatComposerCandidate] {
        guard let query = presentation.completion.query else { return [] }
        let candidates: [AgentChatComposerCandidate]
        switch query.trigger {
        case "$":
            candidates = AgentChatComposerCatalog.skills(
                methods: controller.capabilities.methods,
                canRefresh: controller.capabilities.isConnected && !controller.capabilities.isRefreshing)
        case "@":
            let isPreparing = controller.selectedID.map { controller.preparingMaterials.contains($0) } ?? false
            candidates = AgentChatComposerCatalog.materials(notes: isPreparing ? [] : noteChoices)
        default:
            candidates = AgentChatComposerCatalog.commands(
                isBusy: controller.isBusy, hasChanges: !conversationChangeIDs.isEmpty,
                hasAgents: controller.selected.map {
                    !AgentChatAgentRoster(messages: $0.messages, threadID: $0.threadID).entries.isEmpty
                } ?? false)
        }
        return AgentChatComposerCatalog.matching(candidates, query: query.text)
            .filter { canChooseCompletion($0, in: controller.selectedID) }
    }

    private func canChooseCompletion(_ candidate: AgentChatComposerCandidate, in conversationID: UUID?) -> Bool {
        guard isVisible, conversationID == controller.selectedID,
            controller.selected?.isAvailable == true
        else { return false }
        switch candidate.action {
        case .file:
            return fileSelectionTask == nil && conversationID.map { !controller.preparingMaterials.contains($0) } == true
        case .notePicker, .note, .selection:
            return conversationID.map { !controller.preparingMaterials.contains($0) } == true
        case .webSearch: return !controller.isBusy
        case .refreshMethods: return controller.capabilities.isConnected && !controller.capabilities.isRefreshing
        case .method(let selected):
            return controller.capabilities.methods.contains { $0.selection.id == selected.id && $0.enabled && !$0.isProtected }
        case .changes: return !conversationChangeIDs.isEmpty
        case .agents:
            return controller.selected.map { !AgentChatAgentRoster(messages: $0.messages, threadID: $0.threadID).entries.isEmpty } ?? false
        default: return true
        }
    }

    private func chooseCompletion(
        _ candidate: AgentChatComposerCandidate, in conversationID: UUID?, finish: @escaping (Bool) -> Void
    ) {
        guard let conversationID, conversationID == controller.selectedID else {
            finish(false)
            return
        }
        switch candidate.action {
        case .note(let note):
            Task { @MainActor in
                do {
                    try await prepareNote(note, in: conversationID)
                    finish(true)
                } catch { finish(false) }
            }
            return
        case .selection:
            Task { @MainActor in
                finish(await addSelection(conversationID))
            }
            return
        default: break
        }
        finish(true)
        switch candidate.action {
        case .file: chooseFiles()
        case .notePicker: presentation.notePickerTarget = .init(id: conversationID)
        case .selection, .note: break
        case .methods:
            presentation.completion.begin("$")
        case .refreshMethods:
            controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
        case .manageMethods:
            SettingsNavigationRequest.select(.agents, agentCategory: .capabilities)
            openSettings()
        case .context: presentation.contextAnchor = .composer
        case .usage: openAccountUsage()
        case .find:
            openFind()
        case .outline: presentation.showsTurns = true
        case .changes:
            presentChanges()
        case .agents:
            presentAgents()
        case .webSearch(let mode): controller.setWebSearch(mode)
        case .method(let method): controller.toggleMethod(method)
        }
    }

    private func openAccountUsage() {
        presentation.contextAnchor = nil
        presentation.showsTurns = false
        showAccountUsage()
    }

    private func contextIsPresented(at anchor: AgentChatDetailPresentation.ContextAnchor) -> Binding<Bool> {
        Binding(
            get: { presentation.contextAnchor == anchor },
            set: { presented in
                if presented { presentation.contextAnchor = anchor } else if presentation.contextAnchor == anchor { presentation.contextAnchor = nil }
            })
    }

    private var contextPanel: some View {
        AgentChatContextView(
            usage: controller.selected?.contextUsage,
            ledger: AgentChatContextLedger(
                conversation: controller.selected,
                modelName: controller.selectedModel?.name ?? controller.selected?.preferences.model,
                effort: controller.selectedEffort),
            canCompact: controller.canCompact,
            compact: {
                presentation.contextAnchor = nil
                controller.compactContext()
            })
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
        return AgentChatInputArea(hasQueue: !controller.queuedMessages.isEmpty) {
            AgentChatQueueView(
                messages: controller.queuedMessages,
                canSend: { controller.canSendQueuedMessage($0.id) },
                send: { _ = controller.sendQueuedMessage($0) },
                canSteer: { controller.canSteerQueuedMessage($0.id) },
                steer: { id in if let turnID { _ = controller.steerQueuedMessage(id, expectedTurnID: turnID) } },
                remove: { controller.removeQueuedMessage($0) },
                edit: { message in
                    guard let conversationID else { return }
                    presentation.queueEditTarget = .init(conversationID: conversationID, message: message)
                })
        } input: {
            AgentChatInputDock(
                requestID: pending.map { "approval:\($0.id)" } ?? asyncMessage.map { "question:\($0.id)" }, requestTitle: title,
                requestCount: controller.approvals.count + (asyncMessage == nil ? 0 : 1), isActive: isVisible,
                isReadingHistory: isAwayFromLatest || readingIsPaused || presentation.transcriptIsScrolling,
                isEditingDraft: presentation.messageIsFocused
                    && (controller.selected?.draft.isEmpty == false
                        || presentation.completion.isComposing),
                composerIsFocused: $presentation.messageIsFocused,
                onRequestExpanded: {
                    presentation.completion.dismiss()
                    presentation.contextAnchor = nil
                }
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
            .onChange(of: pending?.id) { _, _ in presentation.contextAnchor = nil }
            .onChange(of: asyncMessage?.id) { _, _ in presentation.contextAnchor = nil }
        } candidates: {
            if presentation.completion.query != nil {
                AgentChatComposerCandidates(completion: presentation.completion, candidates: completionCandidates)
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
                            Button {
                                controller.toggleMethod(method)
                            } label: {
                                Label(method.title, systemImage: ScholiumSidebarAction.remove.symbol)
                            }
                            .buttonStyle(ScholiumContentActionButtonStyle())
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
                                attachment: attachment, isEmbeddedInComposer: true,
                                remove: { controller.removeAttachment(attachment.id) },
                                open: { openAttachment(attachment) })
                        }
                        ForEach(controller.selected?.localMaterials ?? []) { material in
                            AgentChatLocalMaterialChip(
                                material: material, isEmbeddedInComposer: true, preview: { try await controller.previewLocalMaterial(material) },
                                remove: { if let conversationID { controller.removeLocalMaterial(material.id, from: conversationID) } },
                                replace: { chooseFiles(replacing: material.id) },
                                usePages: {
                                    if let conversationID { presentation.pdfPagesTarget = .init(material: material, conversationID: conversationID) }
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
                isFocused: Binding(get: { presentation.messageIsFocused }, set: { presentation.messageIsFocused = $0 }),
                conversationID: conversationID,
                isEnabled: controller.isLoaded,
                submit: {
                    guard controller.selectedID == conversationID, presentation.completion.canSubmit(in: conversationID) else { return }
                    controller.submitDraft(whileWorking: inputBehavior)
                },
                completion: presentation.completion, candidates: completionCandidates, candidateQuery: presentation.completion.query,
                canChooseCompletion: { canChooseCompletion($0, in: conversationID) },
                chooseCompletion: { candidate, finish in chooseCompletion(candidate, in: conversationID, finish: finish) },
                transferMaterials: { materials, origin in
                    guard let conversationID else { return }
                    guard !controller.preparingMaterials.contains(conversationID) else {
                        controller.reportMaterialError(ScholiumL10n.string("Finish preparing the current material before adding another."), in: conversationID)
                        return
                    }
                    Task { @MainActor in
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
                    Button("Choose File…") { chooseFiles() }
                        .disabled(fileSelectionTask != nil || conversationID.map { controller.preparingMaterials.contains($0) } == true)
                    Button {
                        presentation.completion.begin("@")
                    } label: {
                        Text("Choose Note…", bundle: .module)
                    }
                    Button {
                        presentation.completion.begin("$")
                    } label: {
                        Text("Skills", bundle: .module)
                    }
                    Divider()
                    Button {
                        presentation.completion.begin("/")
                    } label: {
                        Text("Commands", bundle: .module)
                    }
                } label: {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.add.symbol, placement: .action)
                        .accessibilityLabel("Add to Chat")
                }
                .scholiumContentActionMenu()
                .help("Add to Chat").accessibilityLabel("Add to Chat")
                .accessibilityIdentifier("scholium.chat.addMaterial")
                AgentChatContextMeter(usage: controller.selected?.contextUsage) { presentation.contextAnchor = .composer }
                    .popover(isPresented: contextIsPresented(at: .composer), arrowEdge: .bottom) {
                        contextPanel
                    }
                AgentChatConfigurationMenu(
                    models: controller.models,
                    preferences: controller.selected?.preferences ?? .init(), selectedModel: controller.selectedModel,
                    selectedEffort: controller.selectedEffort,
                    permission: controller.selected?.permission ?? .ask,
                    isEnabled: !controller.isBusy, canSelectModel: controller.account != nil,
                    selectModel: controller.setModel, selectEffort: controller.setEffort,
                    selectPermission: controller.setPermission, selectWebSearch: controller.setWebSearch
                )
                .font(.caption).menuIndicator(.visible)
                Spacer(minLength: 0)
                AgentChatComposerActionButton(
                    state: controller.state, canSend: controller.canSend,
                    queuesInput: inputBehavior == .queue,
                    submit: {
                        guard controller.selectedID == conversationID, presentation.completion.canSubmit(in: conversationID) else { return }
                        controller.submitDraft(whileWorking: inputBehavior)
                    },
                    submitAlternate: {
                        guard controller.selectedID == conversationID, presentation.completion.canSubmit(in: conversationID) else { return }
                        controller.submitDraft(whileWorking: inputBehavior == .queue ? .steer : .queue)
                    }, stop: controller.stop)
            }
            .controlSize(.regular)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            if controller.selected?.permission == .fullAccess {
                Text("Full Access").font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Permission").accessibilityValue("Full Access")
            }
            if controller.state == .disconnected && controller.selected?.draft.isEmpty == false {
                Text("Connect an agent before sending.").font(.caption).foregroundStyle(.secondary)
            }
            if !controller.selectionIsAvailable {
                Text("Choose an available model and reasoning level.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
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
                    Button("Review Changes") { presentation.comparisonRequest = approval }
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
