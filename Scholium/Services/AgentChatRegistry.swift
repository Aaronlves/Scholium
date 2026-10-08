import Foundation
import ScholiumApplication
import ScholiumContracts

@MainActor
final class AgentChatRegistry {
    private var controllers: [UUID: AgentChatController] = [:]
    private let root: URL
    private let workspaceDirectory: @MainActor (UUID) async throws -> URL
    private let displayWindow: @MainActor (UUID, UUID) -> AgentChatDisplayScope?
    private let observeCurrentState:
        @MainActor (UUID, AgentChatDisplayScope, UUID, @escaping @MainActor () -> Bool) async throws -> AgentChatDocumentObservation
    private let handler: @MainActor (ScholiumMCPBridgeRequest, AgentMutationAdmission?) async -> ScholiumMCPBridgeResponse
    private let previewUpdate: @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview
    private let notificationSink: AgentChatNotificationSink

    init(
        root: URL,
        workspaceDirectory: @escaping @MainActor (UUID) async throws -> URL,
        displayWindow: @escaping @MainActor (UUID, UUID) -> AgentChatDisplayScope? = { _, _ in nil },
        observeCurrentState:
            @escaping @MainActor (UUID, AgentChatDisplayScope, UUID, @escaping @MainActor () -> Bool) async throws -> AgentChatDocumentObservation = {
                _, _, _, _ in
                throw ScholiumMCPFailure.chatObservation(.workspaceNotReady)
            },
        notificationSink: @escaping AgentChatNotificationSink = { _, _ in },
        previewUpdate: @escaping @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview,
        handler: @escaping @MainActor (ScholiumMCPBridgeRequest, AgentMutationAdmission?) async -> ScholiumMCPBridgeResponse
    ) {
        self.root = root
        self.workspaceDirectory = workspaceDirectory
        self.displayWindow = displayWindow
        self.observeCurrentState = observeCurrentState
        self.handler = handler
        self.previewUpdate = previewUpdate
        self.notificationSink = notificationSink
    }

    func controller(for triptychID: UUID) -> AgentChatController {
        if let current = controllers[triptychID] { return current }
        let displayWindow = self.displayWindow
        let controller = AgentChatController(
            triptychID: triptychID,
            root: root,
            workspaceDirectory: { [workspaceDirectory] in try await workspaceDirectory(triptychID) },
            displayWindow: { displayWindow(triptychID, $0) },
            observeCurrentState: { [observeCurrentState] scope, conversation, admitted in
                try await observeCurrentState(triptychID, scope, conversation, admitted)
            },
            notificationSink: notificationSink,
            previewUpdate: previewUpdate,
            toolHandler: handler
        )
        controllers[triptychID] = controller
        return controller
    }

    func admitsDisplay(_ request: ScholiumMCPBridgeRequest, windowID: UUID) -> Bool {
        guard let token = request.conversationToken,
            let owner = controllers.values.first(where: { $0.owns(token: token) })
        else { return false }
        return owner.admitsDisplay(request, windowID: windowID)
    }

    func handle(_ request: ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse {
        if let token = request.conversationToken,
            let controller = controllers.values.first(where: { $0.owns(token: token) })
        {
            return await controller.handle(request)
        }
        if request.tool == .observeCurrentState {
            return try! .init(requestID: request.requestID, error: .chatObservation(.workspaceNotReady))
        }
        return try! .init(
            requestID: request.requestID,
            error: .init(
                code: .workspaceNotReady,
                message: "The conversation connection expired.",
                recovery: "Reconnect in Scholium Chat."
            )
        )
    }

    func disconnect(triptychID: UUID) async {
        await controllers[triptychID]?.disconnect()
    }

    func shutdown() async {
        for controller in controllers.values {
            await controller.disconnect()
        }
    }
}
