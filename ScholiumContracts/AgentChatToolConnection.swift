import Foundation

public struct AgentChatToolConnection: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable { case remote, local }
    public var id: String { name }
    public var name: String
    public var kind: Kind
    public var address: String
    public var arguments: [String]
    public var enabled: Bool
    public var bearerTokenVariable: String
    public var environmentVariables: [String]
    public let canEditEnvironmentVariables: Bool
    public let isEditable: Bool
    public init(
        name: String = "", kind: Kind = .remote, address: String = "", arguments: [String] = [],
        enabled: Bool = true, bearerTokenVariable: String = "", environmentVariables: [String] = [],
        canEditEnvironmentVariables: Bool = true, isEditable: Bool = true
    ) {
        self.name = name
        self.kind = kind
        self.address = address
        self.arguments = arguments
        self.enabled = enabled
        self.isEditable = isEditable
        self.bearerTokenVariable = bearerTokenVariable
        self.environmentVariables = environmentVariables
        self.canEditEnvironmentVariables = canEditEnvironmentVariables
    }
}
