import Foundation
import ScholiumContracts

/// Only opaque identity and revision data cross into macOS Notification Center.
struct AgentChangeNotificationRoute: Codable, Hashable, Sendable {
    let triptychID: UUID
    let changeID: UUID
    let noteID: UUID
    let operation: AgentChangeOperation
    let afterFingerprint: DocumentFingerprint?

    init(_ change: AgentChange) {
        triptychID = change.triptychID
        changeID = change.id
        noteID = change.noteID
        operation = change.operation
        afterFingerprint = change.afterFingerprint
    }

    var identifier: String { "scholium.agent-change.\(triptychID).\(noteID)" }

    func matches(_ change: AgentChange) -> Bool {
        triptychID == change.triptychID && changeID == change.id
            && noteID == change.noteID && operation == change.operation
            && afterFingerprint == change.afterFingerprint
    }
}

/// Only opaque local identities and an event category enter Notification Center.
struct AgentChatNotificationRoute: Codable, Hashable, Sendable {
    enum Event: String, Codable, Sendable { case completed, failed, inputRequired }
    let triptychID: UUID
    let conversationID: UUID
    let event: Event
    var identifier: String { "scholium.chat.\(triptychID).\(conversationID)" }
}

typealias AgentChatNotificationSink =
    @MainActor (
        AgentChatNotificationRoute, @escaping @MainActor () -> Bool
    ) -> Void

enum SystemNotificationRoute: Codable, Hashable, Sendable {
    case agentChange(AgentChangeNotificationRoute)
    case chat(AgentChatNotificationRoute)

    var triptychID: UUID {
        switch self {
        case .agentChange(let route): route.triptychID
        case .chat(let route): route.triptychID
        }
    }
    var identifier: String {
        switch self {
        case .agentChange(let route): route.identifier
        case .chat(let route): route.identifier
        }
    }
    var title: String {
        switch self {
        case .agentChange: ScholiumL10n.string("Agent Changes")
        case .chat: ScholiumL10n.string("Chat")
        }
    }
    var body: String {
        switch self {
        case .agentChange: ScholiumL10n.string("An Agent changed a Note. Open Scholium to inspect the change.")
        case .chat(let route):
            switch route.event {
            case .completed: ScholiumL10n.string("A conversation has finished. Open Scholium to read the response.")
            case .failed: ScholiumL10n.string("A conversation could not finish. Open Scholium to inspect it.")
            case .inputRequired: ScholiumL10n.string("A conversation needs your input. Open Scholium to respond.")
            }
        }
    }
}
