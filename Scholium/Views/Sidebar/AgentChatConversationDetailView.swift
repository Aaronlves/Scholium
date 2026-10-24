import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

/// One mounted conversation's transient presentation. Reading history outlives it.
struct AgentChatConversationDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    @ObservedObject var controller: AgentChatController
    let isVisible: Bool
    let addSelection: (UUID) async -> Bool
    let noteChoices: [WorkspaceCatalogNote]
    let prepareNotes: @MainActor (UUID) throws -> (@MainActor (WorkspaceCatalogNote) async throws -> Void)
    var noteCatalogCache = AgentChatNoteCatalogCache()
    let openReference: (URL) -> Bool
    let openAttachment: (AgentChatAttachment, WindowOpenDisposition) -> Void
    let showChanges: (UUID) -> Void
    let showConversationChanges: ([UUID]) -> Void
    var changes: [AgentChange]? = nil
    var pendingDocuments: [DocumentChangeSummary]? = nil
    var changesError: String? = nil
    @AppStorage(AgentChatInputBehavior.key) private var inputBehavior = AgentChatInputBehavior.steer
    private var isAwayFromLatest: Bool { readingSession.isAwayFromLatest }
    private var expandedActivityIDs: Set<String> {
        get { readingSession.expandedActivities }
        nonmutating set { readingSession.expandedActivities = newValue }
    }
    private var inspectedActivityIDs: Set<String> {
        guard presentation.showsFind, let id = presentation.find.selectedID else { return expandedActivityIDs }
        return expandedActivityIDs.union([id])
    }
    @State private var fileSelectionTask: Task<Void, Never>?
    @State private var topBarHeight: CGFloat = 0
    @State private var entryMeasurementID: UUID?
    @State private var transcriptMountID = UUID()

    @Bindable var presentation: AgentChatDetailPresentation
    let readingSession: AgentChatReadingSession
    let nativeSession: AgentChatComposerSession
    private var isCurrentConversation: Bool { nativeSession.conversationID == controller.selectedID }
    private var displayedConversation: AgentChatConversation? {
        controller.conversations.first { $0.id == nativeSession.conversationID }
    }
    let focusRequest: UUID?
    let consumeFocusRequest: (UUID) -> Void
    @Binding var replyNavigation: AgentChatReplyNavigation?
    let openReply: (AgentChatReplyNavigation) -> Void
    let showList: () -> Void
    let newConversation: () -> Void
    let didRestoreConversation: () -> Void
    let renameConversation: (AgentChatConversation) -> Void
    let showAccountUsage: () -> Void

    var body: some View {
        GeometryReader { geometry in
            conversationDetail(viewportHeight: geometry.size.height)
        }
        .allowsHitTesting(isVisible && isCurrentConversation)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isVisible || !isCurrentConversation)
        .sheet(item: queuedMessageEditorTarget) { target in
            AgentChatQueuedMessageEditor(
                target: target,
                save: { controller.editQueuedMessage(target.message.id, text: $0, in: target.conversationID) },
                close: { presentation.queueEditTarget = nil })
        }
        .sheet(item: $presentation.inspectedAgent) { child in
            AgentChatChildInspector(child: child, openReference: openReference)
        }
        .sheet(item: $presentation.notePickerTarget) { target in
            AgentChatNotePicker(notes: noteChoices, noteCatalogCache: noteCatalogCache) { note in try prepareNote(note, in: target.id) }
        }
        .sheet(item: $presentation.pdfPagesTarget) { target in AgentChatPDFPagesView(controller: controller, target: target) }
        .sheet(item: $presentation.comparisonRequest) { request in
            if let preview = request.updatePreview {
                AgentChatUpdateComparisonSheet(controller: controller, requestID: request.id, preview: preview)
            }
        }
        .onDisappear {
            suspendTransientPresentation()
        }
        .onChange(of: focusRequest, initial: true) { _, request in
            guard let request, isVisible, isCurrentConversation else { return }
            presentation.messageIsFocused = true
            consumeFocusRequest(request)
        }
        .onChange(of: isVisible) { _, visible in
            if visible, isCurrentConversation, let focusRequest {
                presentation.messageIsFocused = true
                consumeFocusRequest(focusRequest)
            } else if visible, isCurrentConversation, presentation.showsFind {
                // A retained native field has already consumed its first focus
                // request. Preserve the active Find context on ordinary return.
                presentation.findFocusRequest = UUID()
            }
            readingSession.setPresentationActive(visible && isCurrentConversation, for: transcriptMountID)
            if !visible {
                suspendTransientPresentation()
            }
        }
        .onChange(of: presentation.find.query) { _, _ in refreshFind(reset: true) }
        .onChange(of: displayedConversation?.messages) { _, _ in
            if presentation.showsFind { refreshFind() }
        }
    }

    private func suspendTransientPresentation() {
        if readingSession.ownsPresentation(transcriptMountID) { readingSession.endUserScroll() }
        fileSelectionTask?.cancel()
        presentation.completion.dismiss()
        presentation.messageIsFocused = false
        presentation.showsTurns = false
        presentation.showsFiles = false
        presentation.showsAgents = false
        presentation.contextAnchor = nil
        presentation.notePickerTarget = nil
        presentation.pdfPagesTarget = nil
        presentation.inspectedAgent = nil
        presentation.comparisonRequest = nil
    }

    /// Hiding dismisses the sheet presentation while its existing target keeps
    /// unsaved writing. Only the editor's explicit Cancel or Save clears it.
    var queuedMessageEditorTarget: Binding<AgentChatQueueEditTarget?> {
        Binding(
            get: { isVisible && isCurrentConversation ? presentation.queueEditTarget : nil },
            set: { target in
                if let target { presentation.queueEditTarget = target }
            })
    }

    private var header: some View {
        AgentChatHeader(
            title: displayedConversation?.title.isEmpty == false ? displayedConversation!.title : String(localized: "New Conversation"),
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
                if pendingRequest != nil || controller.pendingAsyncQuestion != nil || controller.selected?.isAvailable == false
                    || AgentChatContextPresentation.fraction(controller.selected?.contextUsage) == nil
                {
                    Button("Context Window") { presentation.contextAnchor = .conversation }
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
        guard isCurrentConversation else { return }
        if !presentation.showsFind, let window = nativeSession.host.window {
            presentation.findReturnFocus = AgentChatFindReturnFocus(window: window)
        }
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
        presentation.find.refresh(messages: displayedConversation?.messages ?? [], reset: reset)
    }

    private func dismissFind() {
        let returnFocus = presentation.findReturnFocus
        presentation.findReturnFocus = nil
        presentation.showsFind = false
        presentation.find = .init()
        presentation.findFocusRequest = nil
        let restored = isVisible && isCurrentConversation && returnFocus?.restore(in: nativeSession.host.window) == true
        presentation.messageIsFocused = restored && returnFocus?.targets(nativeSession.host.editor) == true
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
        return (displayedConversation?.messages ?? []).filter {
            !active.contains($0.id) || (presentation.showsFind && presentation.find.selectedID == $0.id)
        }
    }

    private var timelineItems: [AgentChatTimelineItem] { AgentChatTimelineItem.group(timelineMessages) }
    private var isHydratingHistory: Bool {
        isCurrentConversation && controller.isRefreshingHistory && displayedConversation?.threadID != nil
    }
    @discardableResult
    private func revealMessage(_ id: String) -> Bool {
        guard let item = timelineItems.first(where: { $0.messages.contains(where: { $0.id == id }) }) else { return false }
        if item.isProcess { expandedActivityIDs.insert(id) }
        readingSession.navigate(to: item.id, in: timelineItems.map(\.id))
        return true
    }

    @ViewBuilder
    private func historyPagingButton(earlier: Bool, ids: [String], readerIDs: Set<String>) -> some View {
        let range = readingSession.pagingRange(in: ids)
        if earlier ? range.lowerBound > 0 : range.upperBound < ids.count {
            Button {
                readingSession.page(earlier: earlier, in: ids, readerIDs: readerIDs)
            } label: {
                Label(
                    earlier ? "Earlier Messages" : "Later Messages",
                    systemImage: earlier ? ScholiumSidebarAction.earlier.symbol : ScholiumSidebarAction.later.symbol)
            }
            .buttonStyle(ScholiumContentActionButtonStyle()).font(.callout)
            .accessibilityLabel(Text(earlier ? "Earlier Messages" : "Later Messages", bundle: .module))
            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
            .overlay(alignment: .trailing) {
                if readingSession.pendingHistoryPage?.earlier == earlier {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                }
            }
            .disabled(readingSession.pendingHistoryPage != nil)
            .accessibilityValue(readingSession.pendingHistoryPage?.earlier == earlier ? Text("Loading…", bundle: .module) : Text(""))
            .accessibilityIdentifier(earlier ? "scholium.chat.earlier" : "scholium.chat.later")
        }
    }

    private var currentReadingRequestID: String? {
        guard let itemID = readingSession.currentReadingItemID,
            let item = timelineItems.first(where: { $0.id == itemID }),
            let turnID = item.messages.first?.turnID
        else { return readingSession.currentReadingItemID }
        return timelineMessages.first(where: { $0.turnID == turnID && $0.role == .user })?.id
    }

    private var conversationTopBar: some View {
        VStack(spacing: 0) {
            header
            AgentChatConnectionStatus(controller: controller)
            if presentation.showsFind {
                AgentChatFindBar(
                    query: $presentation.find.query, focusRequest: presentation.findFocusRequest,
                    position: presentation.find.position, count: presentation.find.messageIDs.count,
                    move: { backwards in presentation.find.move(backwards: backwards) }, dismiss: dismissFind,
                    isActive: isVisible && isCurrentConversation)
            }
            if isHydratingHistory, !timelineMessages.isEmpty {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ProgressView().controlSize(.small)
                    Text("Updating Conversation…", bundle: .module)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ScholiumSidebarLayout.textInset)
                .padding(.vertical, ScholiumSidebarLayout.itemSpacing)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scholium.chat.historyRefreshing")
            }
        }
    }

    private func conversationDetail(viewportHeight: CGFloat) -> some View {
        let projection = AgentChatTimelineProjection(timelineMessages)
        let visibleTimelineItems = Array(projection.items[readingSession.history.range(in: projection.ids)])
        let preparingIDs = readingSession.pendingHistoryPage?.itemIDs ?? []
        let lastPresentedID = visibleTimelineItems.last { !preparingIDs.contains($0.id) }?.id
        let replyReaderIDs = projection.replyReaderIDs
        let visibleReplyReaderIDs = replyReaderIDs.intersection(visibleTimelineItems.map(\.id))
        let transcriptIsReady = readingSession.isPresentationReady(transcriptMountID)
        let editableRequestIDs = Set(controller.editableRequests.map(\.id))
        let branchTurnIDs = Set(controller.branchPoints.compactMap(\.turnID))
        return ScrollView {
            // Transcript geometry must describe the loaded messages, rather than
            // LazyVStack's changing estimates as long replies enter the viewport.
            VStack(alignment: .leading, spacing: ScholiumChatAppearance.messageSpacing) {
                if isHydratingHistory, displayedConversation?.messages.isEmpty != false {
                    ScholiumContentStateView(
                        title: Text("Loading Conversation…", bundle: .module),
                        indicator: .progress,
                        placement: .leading, density: .compact
                    )
                    .accessibilityIdentifier("scholium.chat.historyLoading")
                } else if displayedConversation?.messages.isEmpty != false {
                    ScholiumContentStateView(
                        title: Text("New Conversation"),
                        detail: Text("Discuss your research here. Add a passage or name a note to begin."),
                        indicator: .symbol("bubble.left.and.bubble.right"),
                        placement: .leading, density: .compact
                    )
                    .accessibilityIdentifier("scholium.chat.emptyConversation")
                }
                historyPagingButton(earlier: true, ids: projection.ids, readerIDs: replyReaderIDs)
                if !visibleTimelineItems.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleTimelineItems) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                if presentation.showsFind, let message = item.messages.first(where: { $0.id == presentation.find.selectedID }),
                                    let passage = AgentChatSearch.passage(in: message, query: AgentChatSearch.query(presentation.find.query))
                                {
                                    Label("Matching Message", systemImage: ScholiumSidebarAction.search.symbol)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(passage).font(.callout).textSelection(.enabled)
                                }
                                timelineItem(
                                    item, projection: projection,
                                    editableRequestIDs: editableRequestIDs, branchTurnIDs: branchTurnIDs)
                            }
                            .environment(\.chatReadingPresentation, .init(id: transcriptMountID, session: readingSession, itemID: item.id))
                            .environment(
                                \.scholiumDocumentSurfaceVisibility,
                                surfaceVisibility.isActive && preparingIDs.contains(item.id) ? .preparing : surfaceVisibility
                            )
                            .frame(height: preparingIDs.contains(item.id) ? 0 : nil, alignment: .top)
                            .opacity(preparingIDs.contains(item.id) ? 0 : 1)
                            .allowsHitTesting(!preparingIDs.contains(item.id))
                            .accessibilityHidden(preparingIDs.contains(item.id))
                            .padding(.bottom, preparingIDs.contains(item.id) || item.id == lastPresentedID ? 0 : ScholiumChatAppearance.messageSpacing)
                            .id(item.id)
                            .background(AgentChatReadingMarker(id: item.id, session: readingSession))
                        }
                    }
                }
                historyPagingButton(earlier: false, ids: projection.ids, readerIDs: replyReaderIDs)
                if readingSession.history.last == nil { currentActivity(projection: projection) }
                Color.clear.frame(height: 1).id("latest")
            }.padding(.horizontal, ScholiumSidebarLayout.textInset)
                .padding(.vertical, ScholiumSidebarLayout.edgeInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!isVisible || !isCurrentConversation)
                .background(AgentChatScrollBoundary())
                .background(AgentChatTranscriptViewport(session: readingSession, presentationID: transcriptMountID))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.chat.transcript.content")
        }
        .accessibilityIdentifier("scholium.chat.transcript")
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
        .environment(\.chatReadingInteraction, { readingSession.pause() })
        .environment(\.chatReadingPresentation, .init(id: transcriptMountID, session: readingSession))
        .simultaneousGesture(TapGesture().onEnded { presentation.completion.dismiss() })
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .onScrollPhaseChange { _, phase in
            guard isVisible, isCurrentConversation, readingSession.ownsPresentation(transcriptMountID) else { return }
            if phase == .tracking || phase == .interacting {
                readingSession.beginUserScroll()
            } else if phase == .idle {
                readingSession.endUserScroll()
            } else {
                readingSession.isScrolling = phase == .decelerating
            }
        }
        .frame(maxHeight: .infinity)
        .opacity(transcriptIsReady ? 1 : 0)
        .allowsHitTesting(isVisible && isCurrentConversation && transcriptIsReady)
        .accessibilityHidden(!isVisible || !isCurrentConversation || !transcriptIsReady)
        .overlay(alignment: .topLeading) {
            if !transcriptIsReady, !visibleReplyReaderIDs.isEmpty {
                ScholiumContentStateView(
                    title: Text("Loading Conversation…", bundle: .module),
                    indicator: .progress,
                    placement: .leading, density: .compact
                )
                .padding(.horizontal, ScholiumSidebarLayout.textInset)
                .padding(.vertical, ScholiumSidebarLayout.edgeInset)
                .accessibilityIdentifier("scholium.chat.transcript.hydrating")
            }
        }
        .onChange(of: readingSession.initialTranscriptPhase) { _, phase in
            if phase == .positioning || phase == .visible {
                recordEntryHydrationIfReady(visibleReaderIDs: visibleReplyReaderIDs)
            }
        }
        .task(id: replyNavigation) {
            guard let target = replyNavigation, isCurrentConversation,
                target.conversationID == nativeSession.conversationID,
                revealMessage(target.messageID)
            else { return }
            if replyNavigation?.id == target.id { replyNavigation = nil }
        }
        .onChange(of: presentation.find.selectedID) { _, id in
            guard readingSession.ownsPresentation(transcriptMountID) else { return }
            if let id,
                let item = projection.items
                    .first(where: { $0.messages.contains(where: { $0.id == id }) })
            {
                readingSession.navigate(to: item.id, in: projection.ids)
            }
        }
        // The native safe area measures the complete dock. Replies can
        // scroll beneath its glass while the viewport retains enough
        // bottom inset to bring every final-message action into reach.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AgentChatConversationBottomArea(viewportHeight: max(0, viewportHeight - topBarHeight)) {
                AgentChatConversationAccessories(
                    readingSession: readingSession, hasActivity: hasConversationActivity,
                    latest: { readingSession.latest(in: projection.ids) }
                ) {
                    conversationActivityButtons
                }
            } input: { availableHeight in
                if controller.selected?.isAvailable == false {
                    Button("Restore Chat") {
                        if let id = controller.selectedID {
                            controller.setArchived(id, archived: false)
                            didRestoreConversation()
                        }
                    }.buttonStyle(.glass).padding()
                } else {
                    inputDock(viewportHeight: availableHeight)
                }
            }
            .disabled(!isVisible || !isCurrentConversation)
            .accessibilityHidden(!isVisible || !isCurrentConversation)
        }
        .safeAreaBar(edge: .top, spacing: 0) {
            conversationTopBar
                .disabled(!isVisible || !isCurrentConversation)
                .accessibilityHidden(!isVisible || !isCurrentConversation)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    topBarHeight = $0
                }
        }
        .onAppear {
            readingSession.beginPresentation(transcriptMountID, isActive: isVisible && isCurrentConversation)
            if presentation.showsFind { refreshFind() }
            presentation.arrivalBaseline = Set(projection.messages.map(\.id))
            readingSession.mount(in: projection.ids, readerIDs: replyReaderIDs)
            recordEntryMountIfNeeded(visibleReaderIDs: mountedReplyReaderIDs(in: projection))
        }
        .onChange(of: isVisible) { _, visible in if visible { recordEntryMountIfNeeded(visibleReaderIDs: mountedReplyReaderIDs(in: projection)) } }
        .onChange(of: projection.ids) { _, ids in
            guard readingSession.ownsPresentation(transcriptMountID) else { return }
            readingSession.contentDidChange(in: ids, readerIDs: replyReaderIDs)
        }
        .onChange(of: replyReaderIDs) { _, readerIDs in
            guard readingSession.ownsPresentation(transcriptMountID) else { return }
            readingSession.contentDidChange(in: projection.ids, readerIDs: readerIDs)
        }
        .onDisappear {
            if readingSession.ownsPresentation(transcriptMountID) { presentation.arrivalBaseline = nil }
            readingSession.endPresentation(transcriptMountID)
        }
    }

    private func mountedReplyReaderIDs(in projection: AgentChatTimelineProjection) -> Set<String> {
        projection.replyReaderIDs.intersection(projection.items[readingSession.history.range(in: projection.ids)].map(\.id))
    }

    private func recordEntryMountIfNeeded(visibleReaderIDs: Set<String>) {
        guard isVisible, readingSession.ownsPresentation(transcriptMountID), PerformanceProbe.shared.measuresChatEntry,
            let id = PerformanceProbe.shared.chatEntryID(in: nativeSession.conversationID)
        else { return }
        entryMeasurementID = id
        PerformanceProbe.shared.markChatDetailMounted(id, readerCount: visibleReaderIDs.count)
        recordEntryHydrationIfReady(visibleReaderIDs: visibleReaderIDs)
    }

    private func recordEntryHydrationIfReady(visibleReaderIDs: Set<String>) {
        guard readingSession.ownsPresentation(transcriptMountID), let entryMeasurementID,
            readingSession.areReadersHydrated(visibleReaderIDs)
        else { return }
        let conversationID = nativeSession.conversationID
        let presentationID = transcriptMountID
        PerformanceProbe.shared.markChatReadersHydrated(entryMeasurementID) { [weak readingSession, weak controller] in
            guard let readingSession else { return false }
            return controller?.selectedID == conversationID
                && readingSession.viewport?.window != nil
                && readingSession.isPresentationReady(presentationID)
                && readingSession.viewportRequest == nil
        }
    }

    @ViewBuilder
    private func timelineItem(
        _ item: AgentChatTimelineItem, projection: AgentChatTimelineProjection,
        editableRequestIDs: Set<String>, branchTurnIDs: Set<String>
    ) -> some View {
        if item.isProcess {
            let turnID = item.messages.first?.turnID
            let status = projection.carriesTurnStatus(item) ? turnPresentation(turnID, projection: projection) : nil
            let activeActivityID = projection.activeActivityID(for: turnID)
            AgentChatProcessView(
                messages: Array(item.messages),
                window: Binding(
                    get: { readingSession.processWindows[item.id] ?? .init() },
                    set: { readingSession.processWindows[item.id] = $0 }),
                forceExpanded: presentation.showsFind && item.messages.contains { $0.id == presentation.find.selectedID },
                isActive: controller.isBusy && turnID != nil && turnID == controller.currentTurnID,
                status: status,
                preservesReading: readingSession.isRetainingPosition || readingSession.isScrolling || isAwayFromLatest,
                hasInspectedActivity: item.messages.contains { expandedActivityIDs.contains($0.id) },
                inspectedActivityIDs: inspectedActivityIDs,
                revealedActivityID: presentation.showsFind ? presentation.find.selectedID : nil,
                animates: isVisible && controller.approvals.isEmpty,
                inspect: { readingSession.pause() },
                userExpansion: Binding(
                    get: { readingSession.processExpansions[item.id] },
                    set: { readingSession.processExpansions[item.id] = $0 }),
                toolGroupExpansions: Binding(
                    get: { readingSession.toolGroupExpansions },
                    set: { readingSession.toolGroupExpansions = $0 })
            ) { message in
                if let activity = message.activity {
                    activityRow(message, activity: activity, activeActivityID: activeActivityID)
                } else if let plan = message.plan {
                    AgentChatPlanView(
                        plan: plan,
                        savedExpansion: Binding(
                            get: { readingSession.planExpansions[message.id] },
                            set: { readingSession.planExpansions[message.id] = $0 }))
                } else {
                    AgentChatMarkdown(
                        text: message.text, readerID: message.id, isStreaming: message.isStreaming
                    ).foregroundStyle(.secondary)
                }
            }
        } else if let message = item.messages.first {
            if message.role == .assistant && projection.carriesTurnStatus(item) {
                let status = turnPresentation(message.turnID, projection: projection)
                AgentChatTurnStatus(
                    presentation: status,
                    isVisible: isVisible)
            }
            messageView(
                message, hasEditBoundary: editableRequestIDs.contains(message.id),
                hasBranchBoundary: message.turnID.map { branchTurnIDs.contains($0) } ?? false)
            if message.role == .user {
                AgentChatConnectionStatus(
                    controller: controller,
                    messageID: message.id)
            }
            if message.role == .user && projection.carriesTurnStatus(item) {
                let status = turnPresentation(message.turnID, projection: projection)
                AgentChatTurnStatus(
                    presentation: status,
                    isVisible: isVisible)
            }
        }
    }

    private func messageView(_ message: AgentChatMessage, hasEditBoundary: Bool, hasBranchBoundary: Bool) -> some View {
        let conversationID = nativeSession.conversationID
        let actionItems = messageActionItems(
            message, in: conversationID, hasEditBoundary: hasEditBoundary, hasBranchBoundary: hasBranchBoundary)
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
                            text: message.text, readerID: message.id, isStreaming: message.isStreaming, expandsToFillWidth: message.role != .user,
                            quoteSelection: canQuote(message) ? { selection in quote(message, selection: selection, in: conversationID) } : nil,
                            allowsNativeParagraph: message.role == .user)
                    }
                    if !message.attachments.isEmpty || !message.localMaterials.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(message.attachments) { attachment in
                                    AgentChatMaterialChip(attachment: attachment, remove: nil, open: { openAttachment(attachment, $0) })
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
                    if hasEditBoundary || hasBranchBoundary || canQuote(message) {
                        ForEach(actionItems) { item in
                            AgentChatActionButton(label: item.id, systemImage: item.symbol, action: item.action)
                                .disabled(!item.isEnabled)
                        }
                    }
                }
                .buttonStyle(ScholiumContentActionButtonStyle())
                .contextMenu {
                    ForEach(actionItems) { item in
                        Button(LocalizedStringKey(item.id), systemImage: item.symbol, action: item.action)
                            .disabled(!item.isEnabled)
                    }
                }
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

    private struct MessageAction: Identifiable {
        let id: String
        let symbol: String
        var isEnabled = true
        let action: () -> Void
    }

    private func messageActionItems(
        _ message: AgentChatMessage, in conversationID: UUID?, hasEditBoundary: Bool, hasBranchBoundary: Bool
    ) -> [MessageAction] {
        var items: [MessageAction] = []
        if hasEditBoundary {
            items.append(
                .init(
                    id: "Edit in New Branch", symbol: ScholiumSidebarAction.edit.symbol,
                    isEnabled: controller.canBranch, action: { controller.editInNewBranch(message.id) }))
        }
        if let turnID = message.turnID, hasBranchBoundary {
            items.append(
                .init(
                    id: "Branch from This Turn", symbol: ScholiumSidebarAction.branch.symbol,
                    isEnabled: controller.canBranch, action: { controller.branch(through: turnID) }))
            if controller.canRetryInNewBranch(turnID: turnID) {
                items.append(
                    .init(
                        id: "Retry in New Branch", symbol: ScholiumSidebarAction.retry.symbol,
                        action: { controller.retryInNewBranch(turnID: turnID) }))
            }
        }
        if canQuote(message) {
            items.append(
                .init(
                    id: "Quote in Reply", symbol: ScholiumSidebarAction.quote.symbol,
                    action: { quote(message, selection: nil, in: conversationID) }))
        }
        return items
    }

    private func shouldAnimateArrival(_ message: AgentChatMessage) -> Bool {
        guard let arrivalBaseline = presentation.arrivalBaseline else { return false }
        return !arrivalBaseline.contains(message.id) && allowsReplyMotion
    }

    private var allowsReplyMotion: Bool {
        isVisible && !readingSession.isRetainingPosition && !readingSession.isScrolling && !isAwayFromLatest && !controller.isRefreshingHistory
    }

    @ViewBuilder private func quoteCards(_ quotes: [AgentChatReplyQuote], editable: Bool) -> some View {
        if !quotes.isEmpty {
            let owner = nativeSession.conversationID
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

    @ViewBuilder
    private func activityRow(_ message: AgentChatMessage, activity: AgentChatActivity, activeActivityID: String?) -> some View {
        let isCurrent = isVisible && activeActivityID == message.id
        let orbStyle = isCurrent ? AgentChatActivityOrbStyle.style(for: activity) : nil
        let noteTarget = AgentChatActivityProjection.noteTarget(activity, catalog: noteCatalogCache.catalog(notes: noteChoices))
        VStack(alignment: .leading, spacing: 4) {
            if let report = activity.delegation {
                AgentChatDelegationView(
                    report: report, operationStatus: activity.status,
                    orbStyle: orbStyle,
                    openAgent: { target in
                        guard isCurrentConversation, let conversation = nativeSession.conversationID else { return }
                        presentation.inspectedAgent = controller.childController(targetID: target, messageID: message.id, in: conversation)
                    },
                    expansion: Binding(
                        get: { inspectedActivityIDs.contains(message.id) },
                        set: { expanded in
                            readingSession.pause()
                            if expanded { expandedActivityIDs.insert(message.id) } else { expandedActivityIDs.remove(message.id) }
                        }))
            } else {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { inspectedActivityIDs.contains(message.id) },
                        set: { expanded in
                            readingSession.pause()
                            if expanded { expandedActivityIDs.insert(message.id) } else { expandedActivityIDs.remove(message.id) }
                        })
                ) {
                    AgentChatActivityDetails(activity: activity, openNote: { _ = openReference($0) })
                } label: {
                    AgentChatActivitySummary(
                        activity: activity,
                        noteTarget: noteTarget,
                        openNote: { _ = openReference($0) })
                }
                .disclosureGroupStyle(
                    AgentChatDisclosureStyle(
                        animates: isVisible,
                        symbol: activity.status.isActive || activity.status == .completed ? activity.kind.symbol : activity.status.symbol,
                        orbStyle: orbStyle,
                        allowsLabelInteraction: noteTarget != nil
                    ))
            }
        }
        .font(.callout)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.activity.\(message.id)")
    }

    private func turnPresentation(_ turnID: String?, projection: AgentChatTimelineProjection) -> AgentChatTurnPresentation {
        let record = turnID.flatMap { controller.selected?.turns[$0] }
        let live = controller.isBusy && turnID != nil && turnID == controller.currentTurnID
        let messages = projection.messages(for: turnID).filter { $0.role != .user }
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
    private func currentActivity(projection: AgentChatTimelineProjection) -> some View {
        if controller.isBusy, !isHydratingHistory {
            let hasHeader =
                controller.currentTurnID.map { turn in
                    projection.hasMessages(for: turn)
                } ?? false
            if !hasHeader {
                if controller.state == .working || controller.state == .stopping || controller.state == .compacting {
                    let presentation = turnPresentation(controller.currentTurnID, projection: projection)
                    AgentChatTurnStatus(
                        presentation: presentation,
                        isVisible: isVisible
                    )
                    .accessibilityIdentifier("scholium.chat.currentActivity")
                } else if controller.state == .branching {
                    HStack {
                        Text(
                            ScholiumL10n.string("Creating Branch…", locale: locale))
                        Button("Cancel") { controller.stop() }.accessibilityIdentifier("scholium.chat.cancelBranch")
                    }.font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conversationChangeIDs: Set<UUID> {
        Set(controller.selected?.messages.compactMap(\.changeID) ?? [])
    }

    private var conversationActivityButtons: some View {
        HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            filesButton
            agentsButton
        }
    }

    private var hasConversationActivity: Bool {
        let hasChanges = !conversationChangeIDs.isEmpty
        let hasAgents =
            controller.selected.map {
                !AgentChatAgentRoster(messages: $0.messages, threadID: $0.threadID).entries.isEmpty
            } ?? false
        return hasChanges || hasAgents
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
        let receiptIDs = conversationChangeIDs
        if !receiptIDs.isEmpty {
            let noteIDs = Set(DocumentChangesScope.noteIDs(forReceiptIDs: Array(receiptIDs), in: changes ?? []))
            let pendingChanges = (pendingDocuments ?? []).filter { noteIDs.contains($0.noteID) }
                .sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
            Button {
                presentChanges()
            } label: {
                Label(
                    pendingDocuments == nil || pendingChanges.isEmpty ? String(localized: "Changes") : String(localized: "Changes: \(pendingChanges.count)"),
                    systemImage: "pencil.line"
                )
            }
            .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
            .accessibilityIdentifier("scholium.chat.showFiles")
            .popover(isPresented: $presentation.showsFiles, arrowEdge: .leading) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Pending Changes").font(.headline)
                        Spacer()
                        Button("Close") { presentation.showsFiles = false }.keyboardShortcut(.cancelAction)
                    }
                    if let changesError {
                        Text(verbatim: changesError).textSelection(.enabled)
                    } else if pendingDocuments == nil || changes == nil {
                        ProgressView("Loading Changes…")
                    } else if pendingChanges.isEmpty {
                        Text("No changes awaiting review.").foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(pendingChanges) { change in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Button(change.relativePath.split(separator: "/").last.map(String.init) ?? change.relativePath) {
                                                _ = openReference(AgentChatReference.url(noteID: change.noteID))
                                            }.buttonStyle(.link).help("Open Note")
                                                .contextMenu { AgentChatNoteMenu(url: AgentChatReference.url(noteID: change.noteID)) }
                                            Text(change.relativePath)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("View Changes") {
                                            presentation.showsFiles = false
                                            showChanges(change.noteID)
                                        }
                                    }
                                }
                            }
                        }.frame(maxHeight: 280)
                    }
                    Button("All Changes") {
                        presentation.showsFiles = false
                        showConversationChanges(Array(receiptIDs))
                    }
                }.padding().frame(width: 360)
            }
        }
    }

    private func chooseFiles(replacing materialID: UUID? = nil) {
        guard isCurrentConversation, fileSelectionTask == nil, let conversationID = nativeSession.conversationID,
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

    private func prepareNote(_ note: WorkspaceCatalogNote, in conversationID: UUID) throws -> (@MainActor () async throws -> Void) {
        let addPreparedNote = try prepareNotes(conversationID)
        return { [controller] in
            var failure: (any Error)?
            let prepared = await controller.performMaterialPreparation(in: conversationID) {
                do { try await addPreparedNote(note) } catch {
                    failure = error
                    throw error
                }
            }
            guard prepared else { throw failure ?? CancellationError() }
        }
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
            candidates =
                isPreparing
                ? AgentChatComposerCatalog.materials(preorderedNotes: [])
                : noteCatalogCache.catalog(notes: noteChoices).materialCandidates
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
            let work: @MainActor () async throws -> Void
            do { work = try prepareNote(note, in: conversationID) } catch {
                controller.reportMaterialError(error.localizedDescription, in: conversationID)
                finish(false)
                return
            }
            Task { @MainActor in
                do {
                    try await work()
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
            SettingsNavigationRequest.reveal(.agentSkills)
            openSettings()
        case .context:
            presentation.contextAnchor = AgentChatContextPresentation.fraction(controller.selected?.contextUsage) == nil ? .conversation : .composer
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

    private func inputDock(viewportHeight: CGFloat) -> some View {
        let conversationID = nativeSession.conversationID
        let pending = pendingRequest
        let asyncMessage = pending == nil ? controller.pendingAsyncQuestion : nil
        let title =
            pending?.toolQuestionContext != nil
            ? String(localized: "Tool Input Request", bundle: .module)
            : pending?.questions.isEmpty == false || asyncMessage != nil
                ? String(localized: "Answer Agent", bundle: .module)
                : String(localized: "Review Permission", bundle: .module)
        let turnID = controller.currentTurnID
        return AgentChatInputArea(
            hasQueue: !controller.queuedMessages.isEmpty, viewportHeight: viewportHeight,
            hasPreparedContent: hasPreparedComposerContent
        ) {
            AgentChatQueueView(
                messages: controller.queuedMessages,
                isWorking: controller.state == .working,
                blockedReason: { controller.queuedMessageBlockReason($0.id) },
                canSend: { isCurrentConversation && controller.canSendQueuedMessage($0.id) },
                send: { id in if isCurrentConversation { _ = controller.sendQueuedMessage(id) } },
                canSteer: { isCurrentConversation && controller.canSteerQueuedMessage($0.id) },
                steer: { id in if isCurrentConversation, let turnID { _ = controller.steerQueuedMessage(id, expectedTurnID: turnID) } },
                remove: { id in if isCurrentConversation { controller.removeQueuedMessage(id) } },
                edit: { message in
                    guard isCurrentConversation, let conversationID else { return }
                    presentation.queueEditTarget = .init(conversationID: conversationID, message: message)
                })
        } input: {
            AgentChatInputDock(
                requestID: pending.map { "approval:\($0.id)" } ?? asyncMessage.map { "question:\($0.id)" }, requestTitle: title,
                requestCount: controller.pendingRequestCount, isActive: isVisible && isCurrentConversation,
                isReadingHistory: readingSession.isRetainingPosition || readingSession.isScrolling || isAwayFromLatest,
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
                        canSubmit: controller.canSubmitAsyncQuestion(message.id),
                        stop: controller.state == .working ? { controller.stop() } : nil,
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

    private var composerBlockReason: String? {
        guard let conversation = controller.selected,
            !conversation.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            conversation.pendingMessageID == nil,
            !controller.preparingMaterials.contains(conversation.id),
            let reason = controller.sendBlockReason(message: controller.draftMessage(conversation), in: conversation),
            reason != controller.materialInputIssue && reason != controller.materialErrors[conversation.id],
            conversation.selectedMethods?.allSatisfy(controller.capabilities.contains) != false
        else { return nil }
        return reason
    }

    private var hasPreparedComposerContent: Bool {
        guard let conversation = controller.selected else { return false }
        return conversation.selectedMethods?.isEmpty == false
            || !conversation.attachments.isEmpty || !conversation.localMaterials.isEmpty
            || conversation.draftReplyQuotes?.isEmpty == false
            || conversation.draftCoordinationTarget != nil
            || controller.preparingMaterials.contains(conversation.id)
            || controller.materialInputIssue != nil || controller.materialErrors[conversation.id] != nil
            || composerBlockReason != nil
            || !nativeSession.retainedInputs.isEmpty
    }

    private var composer: some View {
        let conversationID = nativeSession.conversationID
        return AgentChatComposerLayout(hasPreparedContent: hasPreparedComposerContent) {
            preparedComposerContent
        } input: { maximumHeight in
            AgentChatComposerInput(
                text: Binding(
                    get: { controller.conversations.first { $0.id == conversationID }?.draft ?? "" },
                    set: { value in
                        if let conversationID { controller.editDraft(value, in: conversationID) }
                    }),
                isFocused: Binding(get: { presentation.messageIsFocused }, set: { presentation.messageIsFocused = $0 }),
                nativeSession: nativeSession,
                readCurrentDraft: { controller.conversations.first { $0.id == conversationID }?.draft ?? "" },
                isEnabled: controller.isLoaded && isCurrentConversation,
                submit: {
                    guard controller.selectedID == conversationID, presentation.completion.canSubmit(in: conversationID) else { return }
                    controller.submitDraft(whileWorking: inputBehavior)
                },
                completion: presentation.completion, candidates: completionCandidates, candidateQuery: presentation.completion.query,
                canChooseCompletion: { canChooseCompletion($0, in: conversationID) },
                chooseCompletion: { candidate, finish in chooseCompletion(candidate, in: conversationID, finish: finish) },
                transferMaterials: { materials, origin in
                    guard isVisible, isCurrentConversation, let conversationID else { return }
                    guard !controller.preparingMaterials.contains(conversationID) else {
                        controller.reportMaterialError(ScholiumL10n.string("Finish preparing the current material before adding another."), in: conversationID)
                        return
                    }
                    let addPreparedNote: @MainActor (WorkspaceCatalogNote) async throws -> Void
                    do { addPreparedNote = try prepareNotes(conversationID) } catch {
                        controller.reportMaterialError(error.localizedDescription, in: conversationID)
                        return
                    }
                    Task { @MainActor in
                        await controller.addTransferredMaterials(materials, origin: origin, to: conversationID) { item in
                            let note = try AgentChatPasteboardSnapshot.resolve(item, in: noteChoices)
                            try await addPreparedNote(note)
                        }
                    }
                },
                maximumHeight: maximumHeight
            )
            .frame(maxWidth: .infinity)
        } controls: {
            composerControls
        }
        .buttonStyle(.plain)
    }

    private var preparedComposerContent: some View {
        let conversationID = nativeSession.conversationID
        return VStack(alignment: .leading, spacing: ScholiumSidebarLayout.itemSpacing) {
            ForEach(nativeSession.retainedInputs, id: \.self) { earlierInput in
                VStack(alignment: .leading, spacing: ScholiumSidebarLayout.textSpacing) {
                    Text("Earlier Input Retained").font(.caption.weight(.medium))
                    Text("The draft changed elsewhere. Copy this earlier input before discarding it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: earlierInput).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
                        ScholiumCopyButton(label: "Copy Earlier Input", contentIdentity: earlierInput) {
                            NSPasteboard.general.clearContents()
                            return NSPasteboard.general.setString(earlierInput, forType: .string)
                        }
                        Button("Discard Earlier Input", role: .destructive) { nativeSession.discardRetainedInput(earlierInput) }
                    }
                }
                .accessibilityIdentifier("scholium.chat.retainedInput")
            }
            if let methods = controller.selected?.selectedMethods, !methods.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(methods) { method in
                            Button {
                                if isCurrentConversation { controller.toggleMethod(method) }
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
                                remove: { if isCurrentConversation { controller.removeAttachment(attachment.id) } },
                                open: { openAttachment(attachment, $0) })
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
            if let reason = composerBlockReason {
                Text(verbatim: reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            quoteCards(controller.selected?.draftReplyQuotes ?? [], editable: true)
            if let target = controller.selected?.draftCoordinationTarget {
                coordinationReference(target, editable: true)
                if target.parentThreadID != controller.selected?.threadID {
                    Text("This Agent belongs to the original conversation.", bundle: .module)
                        .font(.caption).foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
                }
            }
        }
    }

    private var composerControls: some View {
        let conversationID = nativeSession.conversationID
        return HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Menu {
                Button("Choose File…") { chooseFiles() }
                    .disabled(fileSelectionTask != nil || conversationID.map { controller.preparingMaterials.contains($0) } == true)
                Button {
                    if isCurrentConversation, let conversationID { presentation.notePickerTarget = .init(id: conversationID) }
                } label: {
                    Text("Choose Note…", bundle: .module)
                }
                .disabled(conversationID == nil || conversationID.map { controller.preparingMaterials.contains($0) } == true)
                Button("Add Selection to Chat") {
                    guard isCurrentConversation, let conversationID else { return }
                    Task { @MainActor in
                        if await addSelection(conversationID), isCurrentConversation, isVisible { presentation.messageIsFocused = true }
                    }
                }
                .disabled(conversationID == nil || conversationID.map { controller.preparingMaterials.contains($0) } == true)
                Divider()
                Button {
                    if isCurrentConversation { presentation.completion.begin("$") }
                } label: {
                    Text("Skills", bundle: .module)
                }
                Divider()
                Button {
                    if isCurrentConversation { presentation.completion.begin("/") }
                } label: {
                    Text("Commands", bundle: .module)
                }
            } label: {
                AgentChatComposerIcon(content: .add)
                    .agentChatComposerControl()
            }
            .scholiumContentActionMenu()
            .agentChatComposerControl()
            .help("Add to Chat").accessibilityLabel("Add to Chat")
            .accessibilityIdentifier("scholium.chat.addMaterial")
            AgentChatPermissionMenu(
                permission: controller.selected?.permission ?? .ask,
                isEnabled: isCurrentConversation && !controller.isBusy,
                select: { if isCurrentConversation { controller.setPermission($0) } })
            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
            if AgentChatContextPresentation.fraction(controller.selected?.contextUsage) != nil {
                AgentChatContextMeter(usage: controller.selected?.contextUsage) { presentation.contextAnchor = .composer }
                    .popover(isPresented: contextIsPresented(at: .composer), arrowEdge: .bottom) { contextPanel }
            }
            AgentChatConfigurationMenu(
                models: controller.models,
                preferences: controller.selected?.preferences ?? .init(), selectedModel: controller.selectedModel,
                selectedEffort: controller.selectedEffort,
                isEnabled: isCurrentConversation && !controller.isBusy, canSelectModel: controller.account != nil,
                selectModel: { if isCurrentConversation { controller.setModel($0) } },
                selectEffort: { if isCurrentConversation { controller.setEffort($0) } },
                selectWebSearch: { if isCurrentConversation { controller.setWebSearch($0) } }
            )
            AgentChatComposerActionButton(
                state: controller.state,
                hasInput: controller.selected?.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                canSend: controller.canSend,
                queuesInput: inputBehavior == .queue,
                submit: {
                    guard controller.selectedID == conversationID, presentation.completion.canSubmit(in: conversationID) else { return }
                    controller.submitDraft(whileWorking: inputBehavior)
                },
                stop: { if isCurrentConversation { controller.stop() } })
        }
        .controlSize(.regular)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onChange(of: AgentChatContextPresentation.fraction(controller.selected?.contextUsage) != nil) { _, available in
            if !available, presentation.contextAnchor == .composer { presentation.contextAnchor = nil }
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
                    Button("Review Changes") { presentation.comparisonRequest = approval }
                        .accessibilityLabel("Review Changes")
                        .accessibilityIdentifier("scholium.chat.reviewProposedChanges")
                }
                AgentChatContentScroll {
                    Text(approval.detail).font(.callout).textSelection(.enabled).frame(
                        maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button("Decline") { controller.answer(approval.id, allow: false) }
                        .accessibilityLabel("Decline")
                    Spacer(minLength: 8)
                    Button("Allow Once") { controller.answer(approval.id, allow: true) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                }.controlSize(.regular)
            }.buttonStyle(ScholiumContentActionButtonStyle(restingRole: .primaryText)).id(approval.id)
        }
    }
}
