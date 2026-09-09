import Foundation
import ScholiumContracts

struct AgentChatDisplayScope: Equatable {
    let windowID: UUID
    let registrationID: UUID
}

@MainActor
struct AgentNoteDisplayWindow {
    let registrationID = UUID()
    struct State: Equatable {
        let triptychID: UUID
        let canDisplay: Bool
        let visibleConversationID: UUID?
    }
    let state: () -> State?
    let display: (AgentNoteDisplayTarget, @escaping @MainActor () -> Bool) async throws -> Void
}

extension WorkspaceStore {
    func registerNoteDisplayWindow(id: UUID, window: AgentNoteDisplayWindow) { noteDisplayWindows[id] = window }
    func unregisterNoteDisplayWindow(id: UUID) { noteDisplayWindows[id] = nil }

    func chatDisplayWindow(triptychID: UUID, conversationID: UUID) -> AgentChatDisplayScope? {
        let matches = noteDisplayWindows.filter { _, window in
            guard let state = window.state() else { return false }
            return state.triptychID == triptychID && state.canDisplay && state.visibleConversationID == conversationID
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return .init(windowID: match.key, registrationID: match.value.registrationID)
    }

    func displayWindowValues(triptychID: UUID) -> [MCPJSONValue] {
        noteDisplayWindows.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { id in
            guard let state = noteDisplayWindows[id]?.state(), state.triptychID == triptychID else { return nil }
            return .object(["window_id": .string(id.uuidString.lowercased()), "can_display": .bool(state.canDisplay)])
        }
    }

    func displayAgentNote(windowID: UUID, target: AgentNoteDisplayTarget, request: ScholiumMCPBridgeRequest) async throws {
        guard let window = noteDisplayWindows[windowID] else { throw Self.displayUnavailable() }
        func admitted() -> Bool {
            guard noteDisplayWindows[windowID]?.registrationID == window.registrationID, let current = noteDisplayWindows[windowID]?.state(), current.triptychID == target.triptychID, current.canDisplay else { return false }
            if request.conversationToken != nil { return chatRegistry.admitsDisplay(request, windowID: windowID) }
            return true
        }
        guard admitted() else { throw Self.displayUnavailable() }
        try await window.display(target, admitted)
    }

    static func displayUnavailable() -> ScholiumMCPFailure {
        .init(code: .workspaceNotReady, message: "The originating window or conversation is not available for display.",
            recovery: "Select the intended window and conversation, then request display again. No window is foregrounded automatically.")
    }
}
