import Foundation
import ScholiumContracts

/// Delivery belongs to one retained researcher message, independently of the
/// next draft and the Agent turn. Preflight has no transcript delivery status.
enum AgentChatMessageDelivery: Equatable {
    case sending, unconfirmed

    static func status(
        for message: AgentChatMessage,
        pendingMessageID: String?, sendingMessageID: String?
    ) -> Self? {
        guard message.role == .user, pendingMessageID == message.id else { return nil }
        return sendingMessageID == message.id ? .sending : .unconfirmed
    }
}

/// Captured identity for a rendered Continue Without Resending action.
struct AgentChatDeliveryRecoveryTarget: Equatable {
    let conversationID: UUID
    let messageID: String
}
