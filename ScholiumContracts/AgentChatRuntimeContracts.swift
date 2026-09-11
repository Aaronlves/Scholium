import Foundation

/// Researcher choices. Runtime Default is an explicit absence of an override.
public struct AgentChatPreferences: Codable, Equatable, Sendable {
    public enum WebSearch: String, Codable, CaseIterable, Sendable {
        case runtimeDefault, disabled, cached, live
    }
    public var model: String?
    public var effort: String?
    public var webSearch: WebSearch

    public init(model: String? = nil, effort: String? = nil, webSearch: WebSearch = .runtimeDefault) {
        self.model = model
        self.effort = effort
        self.webSearch = webSearch
    }
}

public struct AgentChatModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let model: String
    public let name: String
    public let efforts: [String]
    public let defaultEffort: String
    public let isDefault: Bool
    public let inputModalities: [String]

    public init(
        id: String, model: String, name: String, efforts: [String],
        defaultEffort: String, isDefault: Bool, inputModalities: [String]
    ) {
        self.id = id
        self.model = model
        self.name = name
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.isDefault = isDefault
        self.inputModalities = inputModalities
    }
}

/// The latest runtime usage observation, not a local tokenizer or quota estimate.
public struct AgentChatContextUsage: Codable, Equatable, Sendable {
    public let lastTurnTokens: Int
    public let totalTokens: Int
    public let capacity: Int?

    public init(lastTurnTokens: Int, totalTokens: Int, capacity: Int?) {
        self.lastTurnTokens = lastTurnTokens
        self.totalTokens = totalTokens
        self.capacity = capacity
    }
}

public struct AgentChatQuota: Equatable, Identifiable, Sendable {
    public struct Window: Equatable, Sendable {
        public let usedPercent: Int
        public let durationMinutes: Int?
        public let resetsAt: Date?
        public init(usedPercent: Int, durationMinutes: Int?, resetsAt: Date?) {
            self.usedPercent = usedPercent
            self.durationMinutes = durationMinutes
            self.resetsAt = resetsAt
        }
    }
    public let id: String
    public let name: String
    public let primary: Window?
    public let secondary: Window?
    public init(id: String, name: String, primary: Window?, secondary: Window?) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
    }
}

public struct AgentChatPlan: Codable, Equatable, Sendable {
    public struct Step: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable { case pending, inProgress, completed }
        public let step: String
        public let status: Status
        public init(step: String, status: Status) {
            self.step = step
            self.status = status
        }
    }
    public let turnID: String
    public let explanation: String?
    public let steps: [Step]
    public var runStatus: AgentChatActivity.Status
    public init(turnID: String, explanation: String?, steps: [Step]) {
        self.turnID = turnID
        self.explanation = explanation
        self.steps = steps
        self.runStatus = .running
    }
}
