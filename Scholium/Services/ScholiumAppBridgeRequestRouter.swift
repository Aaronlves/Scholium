import ScholiumApplication
import ScholiumContracts

/// Routes the authenticated local transport into the running App's MCP
/// owner. It has no Run, Session, pairing, task, or durable research state.
@MainActor
final class ScholiumAppBridgeRequestRouter {
    private let mcpRouter: MCPAppBridgeRequestRouter

    init(
        runtime: WorkspaceRuntime,
        flushEditors: @escaping MCPAppBridgeRequestRouter.EditorFlusher,
        openTriptychs: @escaping MCPAppBridgeRequestRouter.OpenTriptychs,
        didConfirmChange: @escaping @MainActor (AgentChange) -> Void = { _ in }
    ) {
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
        await mcpRouter.handle(request.mcpRequest)
    }
}
