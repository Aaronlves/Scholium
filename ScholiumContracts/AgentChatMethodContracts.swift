import Foundation

public struct AgentChatMethodSelection: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let title: String
    public let path: String
    public init(name: String, title: String, path: String) {
        self.name = name
        self.title = title
        self.path = path
    }
}

public struct AgentChatMethod: Equatable, Identifiable, Sendable {
    public var id: String { selection.id }
    public let selection: AgentChatMethodSelection
    public let description: String
    public let enabled: Bool
    public let scope: String
    public let dependencies: [String]
    public var isProtected: Bool { selection.name == "scholium-core-protocol" }
    public init(
        selection: AgentChatMethodSelection, description: String, enabled: Bool,
        scope: String, dependencies: [String] = []
    ) {
        self.selection = selection
        self.description = description
        self.enabled = enabled
        self.scope = scope
        self.dependencies = dependencies
    }
}

public struct AgentChatMethodInventory: Equatable, Sendable {
    public let methods: [AgentChatMethod]
    public let errors: [String]
    public init(methods: [AgentChatMethod], errors: [String]) {
        self.methods = methods
        self.errors = errors
    }
}

public struct AgentChatConnectedTool: Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let title: String
    public let connectionStatus: String?
    public let authStatus: String
    public let tools: [String]
    public init(name: String, title: String, connectionStatus: String?, authStatus: String, tools: [String]) {
        self.name = name
        self.title = title
        self.connectionStatus = connectionStatus
        self.authStatus = authStatus
        self.tools = tools
    }
}
