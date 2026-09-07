import ScholiumContracts

/// Research surfaces hand context to the current conversation through this
/// capability. Providers own transport, authentication, models and execution.
@MainActor protocol AgentChatContextReceiving: AnyObject {
    @discardableResult
    func attachContext(_ attachments: [AgentChatAttachment]) -> Bool
}
