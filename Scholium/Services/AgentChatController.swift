import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

enum AgentChatInteractionReply {
    case note(Bool)
    case questions([String: String])
    case runtime(AgentChatRuntimeApproval.Decision)
}

struct AgentChatApproval: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let questions: [AgentChatQuestion]
    var toolInputDetails: String? = nil
    var runtimeRequestID: MCPJSONValue? = nil
    var turnID: String? = nil
    var submission: Bool? = nil
    var failure: String? = nil
    var updatePreview: AgentNoteUpdatePreview? = nil
    var runtimeApproval: AgentChatRuntimeApproval? = nil
    var runtimeDecision: AgentChatRuntimeApproval.Decision? = nil
    var runtimeItemID: String? = nil
    var toolQuestionContext: String? = nil
    var isSubmitting: Bool { submission != nil || runtimeDecision != nil }
}

/// Triptych conversation inventory and one runtime connection; execution is keyed by conversation.
@MainActor
final class AgentChatController: ObservableObject, AgentChatContextReceiving {
    // Module-internal members are shared only by these file-level extensions.
    // The @MainActor controller remains the sole Triptych conversation owner.
    enum State { case disconnected, connecting, loadingHistory, ready, working, compacting, branching, stopping }
    enum ConnectionState { case disconnected, connecting, ready }
    @Published var contextPresentationID: UUID?
    @Published var conversations: [AgentChatConversation] = []
    @Published var selectedID: UUID?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var executions: [UUID: AgentChatExecutionState] = [:]
    @Published var connectionError: String?
    @Published var isRenewingSettings = false
    @Published var settingsRenewalError: String?
    var settingsRenewalID: UUID?
    var settingsRenewalTask: Task<Void, Never>?
    var connectedExecutable: URL?
    var state: State { state(for: selectedID) }
    var approvals: [AgentChatApproval] { selectedID.flatMap { executions[$0]?.approvals } ?? [] }
    var error: String? { selectedID.flatMap { executions[$0]?.error } ?? connectionError }
    var token: UUID? {
        guard let id = selectedID, executions[id]?.admissionID != nil else { return nil }
        return executions[id]?.routeToken
    }
    @Published var account: String?
    @Published var runtimeVersion: String?
    @Published var models: [AgentChatModel] = []
    @Published var runtimeDefaults = AgentChatPreferences()
    @Published var quotas: [AgentChatQuota] = []
    @Published var quotaError: String?
    @Published var isRefreshingQuota = false
    @Published var isLoaded = false
    let capabilities: AgentChatCapabilitiesController
    private var capabilityObservation: AnyCancellable?
    let triptychID: UUID
    let runtimeHome: URL
    let workspaceDirectory: @MainActor () async throws -> URL
    var connectedHome: URL?
    private let storage: AgentChatStorage
    let saveHistory: @MainActor ([AgentChatConversation]) async throws -> Void
    // References provisional history messages only; the live draft stays editable
    // until its write-ahead snapshot has been saved and input dispatch begins.
    var pendingDraftConsumption: [UUID: String] = [:]
    let materialStore: AgentChatMaterialStore
    @Published var preparingMaterials: Set<UUID> = []
    @Published var materialErrors: [UUID: String] = [:]
    var materialTasks: [UUID: Task<Bool, Never>] = [:]
    let toolHandler: @MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse
    let displayWindow: @MainActor (UUID) -> AgentChatDisplayScope?
    let previewUpdate: @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview
    var runtime: CodexAppServer?
    @Published var continuationExecution: CodexWritingContinuation?
    var continuationID: UUID?
    var eventTask: Task<Void, Never>?
    var persistenceTask: Task<Void, Never>?
    var connectionTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?
    private let notificationSink: AgentChatNotificationSink
    var quotaTask: Task<Void, Never>?
    var connectionID: UUID?
    var helperURL: URL?
    var workingDirectory: URL?
    var connectionDefaults: UserDefaults
    var automaticConnection = false
    var reconnectAttempt = 0
    var connectedAt: ContinuousClock.Instant?
    var reconnectTask: Task<Void, Never>?
    var connectionIntentKey: String { "agent.codex.connected.\(triptychID.uuidString)" }

    init(
        triptychID: UUID, root: URL,
        workspaceDirectory: @escaping @MainActor () async throws -> URL,
        methodDefaults: UserDefaults = .standard,
        saveHistory: (@MainActor ([AgentChatConversation]) async throws -> Void)? = nil,
        displayWindow: @escaping @MainActor (UUID) -> AgentChatDisplayScope? = { _ in nil },
        notificationSink: @escaping AgentChatNotificationSink = { _, _ in },
        previewUpdate: @escaping @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview = { _ in
            throw AgentCollaborationError.invalidRequest("Note comparison is unavailable.")
        },
        toolHandler: @escaping @MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse
    ) {
        self.triptychID = triptychID
        self.workspaceDirectory = workspaceDirectory
        self.toolHandler = toolHandler
        self.displayWindow = displayWindow
        self.previewUpdate = previewUpdate
        self.notificationSink = notificationSink
        connectionDefaults = methodDefaults
        capabilities = AgentChatCapabilitiesController()
        runtimeHome = root.appendingPathComponent("Codex", isDirectory: true)
        let storage = AgentChatStorage(
            root: root.appendingPathComponent(triptychID.uuidString, isDirectory: true))
        self.storage = storage
        self.saveHistory = saveHistory ?? { try await storage.save($0) }
        materialStore = AgentChatMaterialStore(
            root: root.appendingPathComponent(triptychID.uuidString, isDirectory: true)
                .appendingPathComponent("Materials", isDirectory: true))
        capabilities.mayChange = { [weak self] in self?.hasActiveExecutions == false && self?.isRenewingSettings == false }
        capabilityObservation = capabilities.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        initialLoadTask = Task { [weak self] in await self?.load() }
    }

    var suggestedRuntimePath: String? {
        ScholiumAgentIntegrationResources.codexRuntimeURL()?.path
    }

    func selectNotification(_ route: AgentChatNotificationRoute) async -> Bool {
        guard route.triptychID == triptychID else { return false }
        await initialLoadTask?.value
        guard !Task.isCancelled, isLoaded, conversation(route.conversationID) != nil else { return false }
        select(route.conversationID)
        contextPresentationID = UUID()
        return true
    }

    func childController(targetID: String, messageID: String, in conversationID: UUID) -> AgentChatChildController? {
        let report = conversation(conversationID)?.messages.first { $0.id == messageID }?.activity?.delegation
        let origins = conversations.filter { $0.threadID == report?.senderThreadID && $0.threadID != nil }
        let origin = origins.count == 1 ? origins[0] : nil
        if report?.targets.contains(where: { $0.id == targetID }) == true, targetID == origin?.threadID, let origin {
            select(origin.id)
            contextPresentationID = UUID()
            return nil
        }
        let parentID = origin?.threadID ?? ""
        return childController(
            target: .init(parentThreadID: parentID, childThreadID: targetID),
            originID: report?.targets.contains(where: { $0.id == targetID }) == true ? origin?.id : nil)
    }

    func childController(target: AgentChatCoordinationTarget) -> AgentChatChildController {
        childController(target: target, originID: originID(for: target))
    }

    private func originID(for target: AgentChatCoordinationTarget) -> UUID? {
        let origins = conversations.filter { $0.threadID == target.parentThreadID }
        return origins.count == 1 ? origins[0].id : nil
    }

    func canOpenParent(for target: AgentChatCoordinationTarget) -> Bool { originID(for: target) != nil }
    func openParent(for target: AgentChatCoordinationTarget) {
        guard let origin = originID(for: target) else { return }
        select(origin)
        contextPresentationID = UUID()
    }

    func removeDraftCoordinationTarget() {
        guard selected?.isAvailable == true else { return }
        update { $0.draftCoordinationTarget = nil }
        persist()
    }

    private func childController(target: AgentChatCoordinationTarget, originID: UUID?) -> AgentChatChildController {
        let parentID = target.parentThreadID
        let targetID = target.childThreadID
        let runtime = self.runtime
        let connection = connectionID
        return AgentChatChildController(
            childID: targetID, parentID: parentID,
            parentTitle: originID.flatMap { conversation($0)?.title } ?? "",
            connection: $connectionState.map { $0 == .ready }.eraseToAnyPublisher(),
            openParent: originID.map { origin in
                { [weak self] in
                    guard self?.conversation(origin)?.threadID == parentID else { return }
                    self?.openParent(for: target)
                }
            },
            inspect: { [weak self] targetID in
                guard let self, let connection, self.connectionID == connection,
                    self.connectionState == .ready, let originID,
                    self.conversation(originID)?.threadID == parentID
                else { return nil }
                return self.childController(
                    target: .init(parentThreadID: parentID, childThreadID: targetID),
                    originID: originID)
            }
        ) {
            @MainActor [weak self] method, params in
            guard let self, let connection, self.connectionID == connection, let runtime,
                self.connectionState == .ready
            else { throw CodexConnectionError.disconnected }
            guard let originID, self.conversation(originID)?.threadID == parentID else {
                throw AgentChatChildFailure.unavailable
            }
            try Task.checkCancellation()
            let value = try await runtime.request(method, params: params)
            guard self.connectionID == connection else { throw CodexConnectionError.disconnected }
            try Task.checkCancellation()
            return value
        }
    }

    func notify(_ event: AgentChatNotificationRoute.Event, in id: UUID, turnID: String) {
        let connection = connectionID
        guard connection != nil else { return }
        let route = AgentChatNotificationRoute(triptychID: triptychID, conversationID: id, event: event)
        notificationSink(route) { [weak self] in
            guard let self, self.connectionID == connection, let execution = self.executions[id],
                self.conversation(id)?.isAvailable == true
            else { return false }
            if event == .inputRequired {
                return execution.turnID == turnID && execution.state == .working
                    && execution.approvals.contains { !$0.isSubmitting }
            }
            return execution.notificationTurnID == turnID && execution.state == .ready
        }
    }

    func notifyInput(in id: UUID) {
        guard let turn = executions[id]?.turnID else { return }
        notify(.inputRequired, in: id, turnID: turn)
    }
    var suggestedHelperPath: String? { ScholiumAgentIntegrationResources.chatHelperURL()?.path }
    var selected: AgentChatConversation? { conversations.first { $0.id == selectedID } }
    var isBusy: Bool { selectedID.map(isBusy(in:)) ?? (connectionState == .connecting) }
    var hasActiveExecutions: Bool { executions.values.contains(where: \.isBusy) || continuationExecution?.isActive == true }

    var writingContinuationModels: [AgentChatModel] {
        models.filter(CodexWritingContinuation.supports)
    }

    func canRequestWritingContinuation(model: String) -> Bool {
        connectionState == .ready && account != nil && !isRenewingSettings && !capabilities.isChanging
            && models.contains { $0.model == model && CodexWritingContinuation.supports($0) }
    }

    /// Isolated generation shares the authenticated transport, never Chat drafts,
    /// retained conversations, materials, Skills or source-mutation admission.
    func writingContinuation(_ request: CodexWritingContinuationRequest) async throws -> String {
        guard canRequestWritingContinuation(model: request.model), let runtime, let connectionID,
            let workingDirectory, let model = models.first(where: { $0.model == request.model })
        else { throw CodexWritingContinuationError.unavailable }
        guard continuationExecution == nil else { throw CodexWritingContinuationError.busy }
        let identity = UUID()
        continuationID = identity
        let execution = CodexWritingContinuation(runtime: runtime, skillPaths: capabilities.methods.map { $0.selection.path }) { [weak self] in
            guard let self, self.continuationID == identity else { return }
            self.continuationExecution = nil
            self.continuationID = nil
        }
        continuationExecution = execution
        do {
            let suffix = try await execution.run(request, model: model, cwd: workingDirectory)
            try Task.checkCancellation()
            guard self.connectionID == connectionID else { throw CodexWritingContinuationError.unavailable }
            return suffix
        } catch {
            // Failed preflight starts no task and therefore needs no async teardown.
            if !execution.isActive, continuationID == identity {
                continuationExecution = nil
                continuationID = nil
            }
            throw error
        }
    }
    var needsInput: Bool {
        executions.values.contains { $0.approvals.contains { !$0.isSubmitting } }
            || conversations.contains { $0.isAvailable == true && $0.messages.contains { $0.asyncQuestion?.isPending == true } }
    }
    var needsInputPublisher: AnyPublisher<Bool, Never> {
        $executions.combineLatest($conversations).map { executions, conversations in
            executions.values.contains { $0.approvals.contains { !$0.isSubmitting } }
                || conversations.contains { $0.isAvailable == true && $0.messages.contains { $0.asyncQuestion?.isPending == true } }
        }.removeDuplicates().eraseToAnyPublisher()
    }
    var isRefreshingHistory: Bool { selectedID.flatMap { executions[$0]?.isRefreshingHistory } ?? false }
    func state(for id: UUID?) -> State {
        switch connectionState {
        case .disconnected: return .disconnected
        case .connecting: return .connecting
        case .ready:
            guard let id else { return .ready }
            return executions[id]?.isRefreshingHistory == true ? .loadingHistory : executions[id]?.state ?? .ready
        }
    }
    func isBusy(in id: UUID) -> Bool {
        connectionState == .connecting || isRenewingSettings || executions[id]?.isBusy == true
    }
    func approvalCount(in id: UUID) -> Int { executions[id]?.approvals.filter { $0.questions.isEmpty && !$0.isSubmitting }.count ?? 0 }
    func questionCount(in id: UUID) -> Int {
        (executions[id]?.approvals.filter { !$0.questions.isEmpty && $0.submission == nil }.count ?? 0)
            + (conversation(id)?.messages.filter { $0.asyncQuestion?.isPending == true }.count ?? 0)
    }
    func canArchive(_ id: UUID) -> Bool { executions[id] != nil && executions[id]?.isBusy == false }
    func owns(token: UUID) -> Bool { executionID(for: token) != nil }
    func executionID(for token: UUID) -> UUID? {
        executions.first { $0.value.routeToken == token && $0.value.admissionID != nil }?.key
    }
    var currentTurnID: String? { selectedID.flatMap { executions[$0]?.turnID } }
    func runtimeContext(for token: UUID) -> ScholiumMCPRuntimeContext? {
        guard let id = executionID(for: token), executions[id]?.state == .working,
            let thread = conversation(id)?.threadID, let turn = executions[id]?.turnID
        else { return nil }
        return .init(threadID: thread, turnID: turn)
    }
    func conversation(_ id: UUID) -> AgentChatConversation? {
        conversations.first { $0.id == id }
    }
    var selectedModel: AgentChatModel? { selected.flatMap { model(for: $0.preferences) } }
    func model(for preferences: AgentChatPreferences) -> AgentChatModel? {
        if let model = preferences.model ?? runtimeDefaults.model { return models.first { $0.model == model } }
        return models.first(where: \.isDefault)
    }
    var selectedEffort: String? { selected.flatMap { effort(for: $0.preferences) } }
    func effort(for preferences: AgentChatPreferences) -> String? {
        preferences.effort ?? (preferences.model == nil ? runtimeDefaults.effort : nil)
            ?? model(for: preferences)?.defaultEffort
    }
    var selectionIsAvailable: Bool {
        guard let preferences = selected?.preferences else { return false }
        return selectionIsAvailable(preferences)
    }
    func selectionIsAvailable(_ preferences: AgentChatPreferences) -> Bool {
        if preferences.model != nil && model(for: preferences) == nil { return false }
        if let effort = preferences.effort, model(for: preferences)?.efforts.contains(effort) != true { return false }
        return true
    }
    var historyUnavailable: Bool {
        selectedID.flatMap { executions[$0]?.historyUnavailable } ?? false
    }

    func retryHistory() {
        if let selectedID { refreshHistory(in: selectedID) }
    }

    var canCompact: Bool {
        state == .ready && account != nil && !isBusy && !historyUnavailable && selected?.threadID != nil
            && !capabilities.isChanging && !isRenewingSettings
            && selected?.isAvailable == true && selected?.pendingMessageID == nil
    }
    var canBranch: Bool {
        state == .ready && !isBusy && !historyUnavailable && account != nil && selectionIsAvailable
            && !capabilities.isChanging && !isRenewingSettings
            && selected?.threadID != nil && selected?.pendingMessageID == nil
    }
    var branchPoints: [AgentChatMessage] {
        var seen: Set<String> = []
        return (selected?.messages ?? []).reversed().filter {
            guard $0.role != .operation, !$0.text.isEmpty, let turn = $0.turnID,
                turn != selectedID.flatMap({ executions[$0]?.turnID })
            else { return false }
            return seen.insert(turn).inserted
        }
    }

    func branch(through turnID: String) {
        createBranch(at: turnID, editing: nil)
    }

    var editableRequests: [AgentChatMessage] {
        var seen: Set<String> = []
        let ended = Set(branchPoints.compactMap(\.turnID))
        return (selected?.messages ?? []).filter {
            guard $0.role == .user, let turn = $0.turnID, ended.contains(turn) else { return false }
            return seen.insert(turn).inserted
        }.reversed()
    }

    func editInNewBranch(_ messageID: String) {
        guard let message = editableRequests.first(where: { $0.id == messageID }), let turnID = message.turnID else { return }
        createBranch(at: turnID, editing: messageID)
    }

    /// A request can be retried in a new branch after a failed or interrupted
    /// turn, or after a completed turn that produced a final answer. The source
    /// conversation is preserved and the new branch opens with the exact
    /// request as a draft; sending it remains an explicit researcher action.
    func canRetryInNewBranch(turnID: String) -> Bool {
        guard canBranch, editableRequests.contains(where: { $0.turnID == turnID }),
            let status = selected?.turns[turnID]?.status
        else { return false }
        switch status {
        case .failed, .interrupted: return true
        case .completed: return true
        case .inProgress: return false
        }
    }

    func retryInNewBranch(turnID: String) {
        guard canBranch,
            let message = editableRequests.first(where: { $0.turnID == turnID })
        else { return }
        createBranch(at: turnID, editing: message.id)
    }

    private func createBranch(at turnID: String, editing messageID: String?) {
        guard canBranch, let source = selected, let sourceThread = source.threadID, let runtime,
            branchPoints.contains(where: { $0.turnID == turnID })
        else { return }
        let connection = connectionID
        let sourceID = source.id
        executions[sourceID]?.state = .branching
        executions[sourceID]?.error = nil
        executions[sourceID]?.operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.connectionID == connection { self.executions[sourceID]?.state = .ready }
            }
            do {
                let history = try await runtime.request(
                    "thread/read",
                    params: ["threadId": .string(sourceThread), "includeTurns": .bool(true)])
                guard self.connectionID == connection, !Task.isCancelled else { return }
                let prefix = try CodexChatBranch.turnIDs(in: history, threadID: sourceThread, through: turnID)
                let turnIDs = messageID == nil ? prefix : Array(prefix.dropLast())
                try self.hydrate(history, in: sourceID)
                guard let hydrated = self.conversation(sourceID) else { return }
                let editedRequest = messageID.flatMap { id in hydrated.messages.first { $0.id == id } }
                if let messageID {
                    guard editedRequest?.role == .user, editedRequest?.turnID == turnID,
                        hydrated.messages.first(where: { $0.role == .user && $0.turnID == turnID })?.id == messageID
                    else { throw CodexConnectionError.invalidMessage }
                }
                // Validate attribution before creating any runtime branch.
                _ = try CodexChatBranch.retainedMessages(source: hydrated, through: turnIDs)
                // No source execution token or automatic goal continuation may enter the new thread.
                let branchRoute = UUID()
                var params = try self.threadParameters(source, configuration: self.toolConfiguration(token: branchRoute))
                params["threadId"] = .string(sourceThread)
                params[messageID == nil ? "lastTurnId" : "beforeTurnId"] = .string(turnID)
                params["deferGoalContinuation"] = .bool(true)
                let result = try await runtime.request("thread/fork", params: params)
                guard self.connectionID == connection, !Task.isCancelled else { return }
                guard let thread = result.objectValue?["thread"]?.objectValue,
                    let newThread = thread["id"]?.stringValue
                else { throw CodexConnectionError.invalidMessage }
                try CodexChatBranch.confirm(result, threadID: newThread, expected: turnIDs)
                var branch = try CodexChatBranch.project(
                    source: hydrated, threadID: newThread,
                    retaining: turnIDs, boundary: turnID, position: messageID == nil ? .through : .before)
                if let editedRequest {
                    branch.draft = editedRequest.text
                    branch.draftCoordinationTarget = editedRequest.coordinationTarget
                    branch.draftReplyQuotes = editedRequest.replyQuotes
                    branch.attachments = editedRequest.attachments
                    branch.localMaterials = editedRequest.localMaterials
                    branch.selectedMethods = editedRequest.methods
                }
                branch.title = String(localized: "Branch: \(source.title)")
                self.conversations.insert(branch, at: 0)
                self.executions[branch.id] = .init()
                self.executions[branch.id]?.routeToken = branchRoute
                if self.selectedID == sourceID { self.selectedID = branch.id }
                self.persist()
            } catch {
                guard self.connectionID == connection, !Task.isCancelled else { return }
                self.executions[sourceID]?.error = String(
                    localized:
                        "The conversation branch could not be confirmed. The original conversation is preserved. \(error.localizedDescription)")
            }
        }
    }
    var canSend: Bool {
        guard let selected else { return false }
        return canSend(message: draftMessage(selected), in: selected)
            && !preparingMaterials.contains(selected.id)
    }

    /// A queued message is admitted only while a confirmed turn is active. It
    /// uses the same source, method, model and material validation as immediate
    /// input, but never shares the active turn's runtime identity.
    var canQueue: Bool {
        guard let selected, let execution = executions[selected.id], execution.state == .working,
            execution.turnID != nil
        else { return false }
        return canSend(message: draftMessage(selected), in: selected)
            && !preparingMaterials.contains(selected.id)
    }

    var queuedMessages: [AgentChatMessage] { selected?.queuedMessages ?? [] }

    func draftMessage(_ conversation: AgentChatConversation) -> AgentChatMessage {
        var message = AgentChatMessage(
            role: .user, text: conversation.draft,
            attachments: conversation.attachments, localMaterials: conversation.localMaterials)
        message.methods = conversation.selectedMethods
        message.coordinationTarget = conversation.draftCoordinationTarget
        message.replyQuotes = conversation.draftReplyQuotes
        return message
    }

    func canSend(message: AgentChatMessage, in conversation: AgentChatConversation) -> Bool {
        let execution = executions[conversation.id]
        return isLoaded && connectionState == .ready && account != nil && selectionIsAvailable(conversation.preferences)
            && (!isRenewingSettings || execution?.state == .working)
            && capabilities.workspaceReady && !capabilities.isChanging && (message.methods ?? []).allSatisfy(capabilities.contains)
            && !message.localMaterials.contains(where: { $0.issue != nil })
            && (!message.localMaterials.contains(where: \.requiresImageInput)
                || model(for: conversation.preferences)?.inputModalities.contains("image") == true)
            && execution != nil && execution?.historyUnavailable == false && execution?.isSending == false && execution?.isRefreshingHistory == false
            && (execution?.state == .ready || (execution?.state == .working && execution?.turnID != nil))
            && runtime != nil && conversation.isAvailable == true && conversation.pendingMessageID == nil
            && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (message.coordinationTarget == nil || message.coordinationTarget?.parentThreadID == conversation.threadID)
    }

    private func load() async {
        do {
            conversations = try await storage.load()
            guard conversations.allSatisfy({ $0.triptychID == triptychID }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            for index in conversations.indices {
                if conversations[index].lastRunStatus?.isActive == true {
                    conversations[index].lastRunStatus = .interrupted
                }
                for message in conversations[index].messages.indices {
                    if conversations[index].messages[message].plan?.runStatus.isActive == true {
                        conversations[index].messages[message].plan?.runStatus = .interrupted
                    }
                    if let activity = conversations[index].messages[message].activity {
                        conversations[index].messages[message].activity =
                            AgentChatActivityProjection.afterConnectionLoss(activity)
                    }
                }
            }
            selectedID =
                conversations.filter { $0.isAvailable == true }
                .sorted { $0.updatedAt > $1.updatedAt }.first?.id
            executions = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, AgentChatExecutionState()) })
            isLoaded = true
            if selectedID == nil { newConversation() }
            if connectionDefaults.bool(forKey: connectionIntentKey) {
                connectConfigured(automatically: true)
            }
        } catch {
            self.connectionError = String(
                localized: "Conversation history could not be opened: \(error.localizedDescription)")
        }
    }

}
