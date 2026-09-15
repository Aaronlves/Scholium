/// The ordinary conversation send owner's outcome, including uncertain delivery.
enum AgentChatDeliveryReceipt: Equatable {
    case received, unconfirmed, unavailable
}
