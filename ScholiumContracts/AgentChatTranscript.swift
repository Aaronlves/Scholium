import Foundation

/// Public runtime observations. These values grant no execution or source authority.
public enum AgentChatTranscript {
    public struct Item: Equatable, Sendable {
        public enum Content: Equatable, Sendable {
            case assistant(text: String, phase: AgentChatMessage.Phase?)
            case user(text: String, hasAdditionalMaterial: Bool)
            case activity(AgentChatActivity)
        }
        public let id: String
        public let content: Content
        public let clientMessageID: String?
        public let asyncQuestions: [AgentChatQuestion]?
        public let isManagedTool: Bool
        public let isStreaming: Bool
        public init(
            id: String, content: Content, clientMessageID: String? = nil, isManagedTool: Bool = false,
            asyncQuestions: [AgentChatQuestion]? = nil, isStreaming: Bool = false
        ) {
            self.asyncQuestions = asyncQuestions
            self.id = id
            self.content = content
            self.clientMessageID = clientMessageID
            self.isManagedTool = isManagedTool
            self.isStreaming = isStreaming
        }
    }

    public struct Turn: Equatable, Sendable {
        public enum Status: String, Codable, Sendable {
            case inProgress, completed, interrupted, failed
            public var runStatus: AgentChatActivity.Status {
                switch self {
                case .inProgress: .running
                case .completed: .completed
                case .interrupted: .interrupted
                case .failed: .failed
                }
            }
        }
        public let id: String
        public let status: Status
        public enum Items: Equatable, Sendable {
            case full([Item])
            case references(Set<String>)
            case notLoaded
        }
        public let itemContent: Items
        public let error: String?
        public let timing: AgentChatTurnTiming
        public var items: [Item] {
            if case .full(let items) = itemContent { return items }
            return []
        }
        public init(
            id: String, status: Status, items: Items, error: String? = nil,
            timing: AgentChatTurnTiming = .init()
        ) {
            self.id = id
            self.status = status
            self.itemContent = items
            self.error = error
            self.timing = timing
        }
        public var messageIDs: Set<String> {
            var ids: Set<String>
            switch itemContent {
            case .full(let items):
                ids = []
                for item in items {
                    ids.insert(item.id)
                    ids.insert("runtime:\(item.id)")
                    if let clientID = item.clientMessageID { ids.insert(clientID) }
                }
            case .references(let references): ids = references
            case .notLoaded: ids = []
            }
            ids.insert("plan:\(id)")
            return ids
        }
    }
}
