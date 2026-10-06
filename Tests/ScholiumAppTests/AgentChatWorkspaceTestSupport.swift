import Foundation
import ScholiumApplication
import ScholiumContracts

@testable import ScholiumApp

@MainActor
struct ChatSidebarPreferenceFixture {
    let defaults: UserDefaults
    let preferences: ChatSidebarPreferences
    private let suiteName: String

    init(enabled: Bool? = nil) {
        suiteName = "scholium.qa.chatSidebar.\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
        if let enabled { defaults.set(enabled, forKey: ChatSidebarPreferences.enabledKey) }
        preferences = ChatSidebarPreferences(defaults: defaults)
    }

    func cleanup() { defaults.removePersistentDomain(forName: suiteName) }
}

func agentChatFixtureWorkspace(root: URL, triptychID: UUID) throws -> URL {
    let workspace = root.appendingPathComponent("Triptychs/\(triptychID.uuidString)/.scholium")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    let manifest = workspace.appendingPathComponent("manifest.json")
    if !FileManager.default.fileExists(atPath: manifest.path) { try Data("{}".utf8).write(to: manifest) }
    return workspace
}

@MainActor
func fixtureChatController(
    triptychID: UUID, root: URL,
    methodDefaults: UserDefaults = .standard,
    displayWindow: @escaping @MainActor (UUID) -> AgentChatDisplayScope? = { _ in nil },
    notificationSink: @escaping AgentChatNotificationSink = { _, _ in },
    previewUpdate: @escaping @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview = { _ in
        throw AgentCollaborationError.invalidRequest("Note comparison is unavailable.")
    },
    toolHandler: @escaping @MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse
) -> AgentChatController {
    AgentChatController(
        triptychID: triptychID, root: root,
        workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
        methodDefaults: methodDefaults, displayWindow: displayWindow,
        notificationSink: notificationSink, previewUpdate: previewUpdate,
        toolHandler: { request, _ in await toolHandler(request) })
}
