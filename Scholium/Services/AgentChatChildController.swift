import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

enum AgentChatParentReceipt: Equatable {
    case received, unconfirmed, unavailable
    func label(locale: Locale) -> String {
        switch self {
        case .received: ScholiumL10n.string("Received by Parent", locale: locale)
        case .unconfirmed: ScholiumL10n.string("Parent Receipt Not Confirmed", locale: locale)
        case .unavailable: ScholiumL10n.string("Parent Unavailable", locale: locale)
        }
    }
}

/// A view port into the originating conversation's draft and ordinary send owner.
@MainActor struct AgentChatParentCoordination {
    let changes: AnyPublisher<Void, Never>
    let draft: () -> String
    let edit: (String) -> Void
    let canEdit: () -> Bool
    let canSend: () -> Bool
    let send: (String?, @escaping @MainActor (AgentChatParentReceipt) -> Void) -> Void
    let open: () -> Void
}

/// One inspection's transient requests and snapshots. No child execution or Note owner.
@MainActor final class AgentChatChildController: ObservableObject, Identifiable {
    let id = UUID()
    let childID: String
    let parentID: String
    let parentTitle: String
    @Published private(set) var snapshot: AgentChatChildHistory.Snapshot?
    @Published private(set) var isWorking = false
    @Published private(set) var isDisconnected = false
    @Published private(set) var pendingStop: String?
    @Published private(set) var error: AgentChatChildFailure?
    @Published private(set) var isSending = false
    @Published private(set) var receipt: AgentChatParentReceipt?
    private let coordination: AgentChatParentCoordination?
    private let inspect: ((String) -> AgentChatChildController?)?
    private var parentObservation: AnyCancellable?
    private let request: CodexChatChildReader.Request
    private var operation: Task<Void, Never>?
    private var connectionObservation: AnyCancellable?
    private var cursors: Set<String> = []
    private var isClosed = false

    init(
        childID: String, parentID: String, parentTitle: String,
        connection: AnyPublisher<Bool, Never>, coordination: AgentChatParentCoordination? = nil,
        inspect: ((String) -> AgentChatChildController?)? = nil,
        request: @escaping CodexChatChildReader.Request
    ) {
        self.childID = childID
        self.parentID = parentID
        self.parentTitle = parentTitle
        self.request = request
        self.coordination = coordination
        self.inspect = inspect
        parentObservation = coordination?.changes.sink { [weak self] in self?.objectWillChange.send() }
        connectionObservation = connection.removeDuplicates().sink { [weak self] connected in
            guard !connected else { return }
            self?.isDisconnected = true
            self?.operation?.cancel()
            self?.isWorking = false
        }
    }

    var canStop: Bool { !isClosed && !isWorking && !isDisconnected && error == nil && pendingStop == nil && snapshot?.activeTurnID != nil }
    var hasParent: Bool { coordination != nil }
    var draft: String { coordination?.draft() ?? "" }
    var canEdit: Bool { !isClosed && coordination?.canEdit() == true }
    var canSend: Bool {
        !isClosed && !isDisconnected && !isSending && snapshot != nil && coordination?.canSend() == true
    }
    func editDraft(_ value: String) {
        guard canEdit else { return }
        receipt = nil
        coordination?.edit(value)
    }
    func askParent() {
        guard canSend else { return }
        isSending = true
        receipt = nil
        coordination?.send(snapshot?.metadata.name) { [weak self] result in
            self?.isSending = false
            self?.receipt = result
        }
    }
    func openParent() { coordination?.open() }

    var canInspectReports: Bool { !isClosed && !isDisconnected && snapshot != nil && inspect != nil }

    func reportedAgent(targetID: String, messageID: String) -> AgentChatChildController? {
        guard canInspectReports,
            let report = messages.first(where: { $0.id == messageID })?.value.activity?.delegation,
            report.senderThreadID == childID, report.targets.contains(where: { $0.id == targetID })
        else { return nil }
        return inspect?(targetID)
    }

    func refresh() {
        run { [self] in
            snapshot = try await load()
            cursors.removeAll()
            confirmStop()
        }
    }

    func loadEarlier() {
        guard let cursor = snapshot?.page.nextCursor, !cursors.contains(cursor) else { return }
        run { [self] in
            let page = try await CodexChatChildReader.older(childID: childID, cursor: cursor, request: request)
            try Task.checkCancellation()
            guard page.nextCursor != cursor, page.nextCursor.map({ !cursors.contains($0) }) ?? true else {
                throw CodexConnectionError.invalidMessage
            }
            if let snapshot { self.snapshot = try CodexChatChildReader.prepending(page, to: snapshot) }
            cursors.insert(cursor)
            confirmStop()
        }
    }

    func stop() {
        guard canStop, let turn = snapshot?.activeTurnID else { return }
        run { [self] in
            let current = try await load()
            snapshot = current
            guard current.activeTurnID == turn else {
                error = .changedTurn
                return
            }
            pendingStop = turn
            do {
                _ = try await request("turn/interrupt", ["threadId": .string(childID), "turnId": .string(turn)])
            } catch CodexConnectionError.server(let message) {
                pendingStop = nil
                throw CodexConnectionError.server(message)
            }
            for delay in [0, 250, 500, 1_000] {
                if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
                snapshot = try await load()
                cursors.removeAll()
                confirmStop()
                if pendingStop == nil { break }
            }
        }
    }

    func cancel() {
        isClosed = true
        operation?.cancel()
        operation = nil
        connectionObservation?.cancel()
        connectionObservation = nil
        parentObservation?.cancel()
        parentObservation = nil
        isWorking = false
    }

    private func confirmStop() {
        if let pendingStop, snapshot?.confirmsEnd(of: pendingStop) == true { self.pendingStop = nil }
    }
    private func load() async throws -> AgentChatChildHistory.Snapshot {
        let value = try await CodexChatChildReader.load(childID: childID, parentID: parentID, request: request)
        try Task.checkCancellation()
        return value
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        guard !isClosed, !isWorking, !isDisconnected else { return }
        isWorking = true
        error = nil
        operation = Task { [weak self] in
            defer { self?.isWorking = false }
            do { try await work() } catch is CancellationError {} catch CodexConnectionError.invalidMessage {
                if !Task.isCancelled { self?.error = .unverified }
            } catch CodexConnectionError.disconnected { self?.isDisconnected = true } catch CodexConnectionError.timedOut {
                if !Task.isCancelled { self?.error = .timedOut }
            } catch let failure as AgentChatChildFailure { if !Task.isCancelled { self?.error = failure } } catch {
                if !Task.isCancelled { self?.error = .runtime(error.localizedDescription) }
            }
        }
    }

    struct Message: Identifiable {
        let value: AgentChatMessage
        let hasAdditionalMaterial: Bool
        var id: String { value.id }
    }
    var messages: [Message] {
        (snapshot?.page.turns ?? []).flatMap { turn in
            turn.items.compactMap { item -> Message? in
                let id = turn.id + "/" + item.id
                var message: AgentChatMessage
                var hasAdditionalMaterial = false
                switch item.content {
                case .assistant(let text, let phase):
                    message = .init(id: id, role: .assistant, text: text, phase: phase)
                case .user(let text, let additional):
                    hasAdditionalMaterial = additional
                    message = .init(id: id, role: .user, text: text)
                case .activity(let value):
                    let activity = AgentChatActivityProjection.withLocalizedFailure(value)
                    message = .init(id: id, role: .operation, text: "", activity: activity)
                }
                message.turnID = turn.id
                return .init(value: message, hasAdditionalMaterial: hasAdditionalMaterial)
            }
        }
    }
}

enum AgentChatChildFailure: Error, Equatable {
    case unavailable, unverified, changedTurn, timedOut
    case runtime(String)
    func label(locale: Locale) -> String {
        switch self {
        case .unavailable: ScholiumL10n.string("The Agent is unavailable in this conversation.", locale: locale)
        case .unverified: ScholiumL10n.string("The Agent's relationship or history could not be verified.", locale: locale)
        case .changedTurn: ScholiumL10n.string("The Agent's active turn changed. Review its current state before stopping it.", locale: locale)
        case .timedOut: ScholiumL10n.string("The Agent did not confirm this request. Refresh its state.", locale: locale)
        case .runtime(let message): message
        }
    }
}
