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
    methodDefaults: UserDefaults? = nil,
    contextAccessPreferences: AgentContextAccessPreferences? = nil,
    displayWindow: @escaping @MainActor (UUID) -> AgentChatDisplayScope? = { _ in nil },
    notificationSink: @escaping AgentChatNotificationSink = { _, _ in },
    previewUpdate: @escaping @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview = { _ in
        throw AgentCollaborationError.invalidRequest("Note comparison is unavailable.")
    },
    toolHandler: @escaping @MainActor (ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse
) -> AgentChatController {
    fixtureChatControllerWithAdmission(
        triptychID: triptychID, root: root,
        workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
        methodDefaults: methodDefaults, contextAccessPreferences: contextAccessPreferences, displayWindow: displayWindow,
        notificationSink: notificationSink, previewUpdate: previewUpdate,
        toolHandler: { request, _ in await toolHandler(request) })
}

/// Owns only a generated test suite. Explicit caller stores are never removed.
/// This ordinary, non-actor class owns the synchronous Foundation cleanup;
/// no actor-isolated controller or permission owner is accessed from deinit.
final class AgentChatFixturePreferenceStore {
    let suiteName: String
    let defaults: UserDefaults

    init() {
        suiteName = "scholium.qa.fixtureChat.\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }
}

@MainActor
func fixtureChatControllerWithAdmission(
    triptychID: UUID, root: URL,
    workspaceDirectory: @escaping @MainActor () async throws -> URL,
    methodDefaults: UserDefaults? = nil,
    contextAccessPreferences: AgentContextAccessPreferences? = nil,
    saveHistory: (@MainActor ([AgentChatConversation]) async throws -> Void)? = nil,
    displayWindow: @escaping @MainActor (UUID) -> AgentChatDisplayScope? = { _ in nil },
    observeCurrentState: @escaping @MainActor (AgentChatDisplayScope, UUID, @escaping @MainActor () -> Bool) async throws -> AgentChatDocumentObservation =
        { _, _, _ in
            throw ScholiumMCPFailure.chatObservation(.workspaceNotReady)
        },
    notificationSink: @escaping AgentChatNotificationSink = { _, _ in },
    previewUpdate: @escaping @MainActor (ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview = { _ in
        throw AgentCollaborationError.invalidRequest("Note comparison is unavailable.")
    },
    toolHandler: @escaping @MainActor (ScholiumMCPBridgeRequest, AgentMutationAdmission?) async -> ScholiumMCPBridgeResponse
) -> AgentChatController {
    let ownedStore =
        methodDefaults == nil || contextAccessPreferences == nil
        ? AgentChatFixturePreferenceStore() : nil
    let resolvedDefaults = methodDefaults ?? ownedStore!.defaults
    let resolvedContext =
        contextAccessPreferences
        ?? AgentContextAccessPreferences(defaults: ownedStore!.defaults)
    return AgentChatController(
        triptychID: triptychID, root: root,
        workspaceDirectory: { [ownedStore] in
            // The controller's existing closure retains its generated suite for
            // the whole fixture lifetime, including an admitted asynchronous read.
            defer { withExtendedLifetime(ownedStore) {} }
            return try await workspaceDirectory()
        },
        methodDefaults: resolvedDefaults, contextAccessPreferences: resolvedContext,
        saveHistory: saveHistory, displayWindow: displayWindow,
        observeCurrentState: observeCurrentState, notificationSink: notificationSink,
        previewUpdate: previewUpdate, toolHandler: toolHandler)
}
