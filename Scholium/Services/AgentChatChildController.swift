import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

/// One inspection's transient requests and snapshots. No child execution or Note owner.
@MainActor final class AgentChatChildController: ObservableObject, Identifiable {
    enum Work { case refresh, loadEarlier, stop }

    let id = UUID()
    let childID: String
    let parentID: String
    let parentTitle: String
    @Published private(set) var snapshot: AgentChatChildHistory.Snapshot?
    @Published private(set) var work: Work?
    @Published private(set) var observedAt: Date?
    @Published private(set) var isDisconnected = false
    @Published private(set) var pendingStop: String?
    @Published private(set) var error: AgentChatChildFailure?
    private let navigateToParent: (() -> Void)?
    private let inspect: ((String) -> AgentChatChildController?)?
    private let request: CodexChatChildReader.Request
    private var operation: Task<Void, Never>?
    private var connectionObservation: AnyCancellable?
    private var cursors: Set<String> = []
    private var isClosed = false

    init(
        childID: String, parentID: String, parentTitle: String,
        connection: AnyPublisher<Bool, Never>, openParent: (() -> Void)? = nil,
        inspect: ((String) -> AgentChatChildController?)? = nil,
        request: @escaping CodexChatChildReader.Request
    ) {
        self.childID = childID
        self.parentID = parentID
        self.parentTitle = parentTitle
        self.request = request
        navigateToParent = openParent
        self.inspect = inspect
        connectionObservation = connection.removeDuplicates().sink { [weak self] connected in
            guard !connected else { return }
            self?.isDisconnected = true
            self?.operation?.cancel()
            self?.work = nil
        }
    }

    var isWorking: Bool { work != nil }
    var canRefresh: Bool { !isClosed && !isWorking && !isDisconnected }
    var canLoadEarlier: Bool {
        canRefresh && snapshot?.page.nextCursor.map { !cursors.contains($0) } == true
    }
    var canStop: Bool { canRefresh && error == nil && pendingStop == nil && snapshot?.activeTurnID != nil }
    var hasParent: Bool { !isClosed && navigateToParent != nil }
    func openParent() {
        guard hasParent else { return }
        navigateToParent?()
    }

    var canInspectReports: Bool { !isClosed && !isDisconnected && snapshot != nil && inspect != nil }

    func reportedAgent(targetID: String, messageID: String) -> AgentChatChildController? {
        guard canInspectReports,
            let report = messages.first(where: { $0.id == messageID })?.value.activity?.delegation,
            report.senderThreadID == childID, report.targets.contains(where: { $0.id == targetID })
        else { return nil }
        return inspect?(targetID)
    }

    /// Resolve a reported name without loading history or enabling child actions.
    func readMetadata() async throws -> AgentChatChildHistory.Metadata {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        guard !isDisconnected else { throw CodexConnectionError.disconnected }
        let metadata = try await CodexChatChildReader.verify(childID: childID, parentID: parentID, request: request)
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        guard !isDisconnected else { throw CodexConnectionError.disconnected }
        return metadata
    }

    func refresh() {
        run(.refresh) { [self] in
            replaceSnapshot(try await load())
        }
    }

    func loadEarlier() {
        guard canLoadEarlier, let cursor = snapshot?.page.nextCursor else { return }
        run(.loadEarlier) { [self] in
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
        run(.stop) { [self] in
            let current = try await load()
            replaceSnapshot(current)
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
                replaceSnapshot(try await load())
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
        work = nil
    }

    private func replaceSnapshot(_ value: AgentChatChildHistory.Snapshot) {
        snapshot = value
        observedAt = Date()
        cursors.removeAll()
        confirmStop()
    }

    private func confirmStop() {
        if let pendingStop, snapshot?.confirmsEnd(of: pendingStop) == true { self.pendingStop = nil }
    }
    private func load() async throws -> AgentChatChildHistory.Snapshot {
        let value = try await CodexChatChildReader.load(childID: childID, parentID: parentID, request: request)
        try Task.checkCancellation()
        return value
    }
    private func run(_ kind: Work, _ action: @escaping @MainActor () async throws -> Void) {
        guard canRefresh else { return }
        work = kind
        error = nil
        operation = Task { [weak self] in
            defer { self?.work = nil }
            do { try await action() } catch is CancellationError {} catch CodexConnectionError.invalidMessage {
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
