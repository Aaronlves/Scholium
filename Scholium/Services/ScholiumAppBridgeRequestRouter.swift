import ScholiumApplication
import ScholiumContracts

/// Routes the authenticated local transport into the running App's MCP
/// owner. It has no Run, Session, pairing, task, or durable research state.
@MainActor
final class ScholiumAppBridgeRequestRouter {
    private let mcpRouter: MCPAppBridgeRequestRouter
    private let chatHandler: (@MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse)?

    init(
        runtime: WorkspaceRuntime,
        flushEditors: @escaping MCPAppBridgeRequestRouter.EditorFlusher,
        openTriptychs: @escaping MCPAppBridgeRequestRouter.OpenTriptychs,
        didConfirmChange: @escaping @MainActor (AgentChange) -> Void = { _ in },
        chatHandler: (@MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse)? = nil
    ) {
        self.chatHandler = chatHandler
        mcpRouter = MCPAppBridgeRequestRouter(
            runtime: runtime,
            flushEditors: flushEditors,
            openTriptychs: openTriptychs,
            didConfirmChange: didConfirmChange
        )
    }

    func handle(
        _ request: ScholiumAppBridgeRequest
    ) async -> ScholiumMCPBridgeResponse {
        if request.mcpRequest.conversationToken != nil {
            if let chatHandler { return await chatHandler(request.mcpRequest) }
            return try! ScholiumMCPBridgeResponse(requestID: request.mcpRequest.requestID, error: ScholiumMCPFailure(
                code: .workspaceNotReady, message: "The conversation is unavailable.", recovery: "Reconnect the conversation in Scholium."
            ))
        }
        return await mcpRouter.handle(request.mcpRequest)
    }

    func handleChatOperation(_ request: ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse {
        await mcpRouter.handle(request)
    }

    func previewChatUpdate(_ request: ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview {
        try await mcpRouter.previewUpdate(request)
    }
}
