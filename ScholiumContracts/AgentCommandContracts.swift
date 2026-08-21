import Foundation

/// Delivery-neutral structured recovery code surfaced by an Agent command.
/// The CLI consumes this narrow contract without importing an Application
/// transport implementation or reconstructing its error taxonomy.
public protocol AgentCommandErrorCodeProviding: Error {
    var agentCommandErrorCode: String { get }
}

public enum AgentCommandActionKind: String, Codable, Hashable, Sendable {
    case inspect
    case reply
    case promote
    case selectResources = "select_resources"
    case submitResult = "submit_result"
    case cancel
}

/// A delivery-neutral, shell-safe next step. `command` is an argument vector,
/// never a shell-interpolated command string. `inputTemplate` is illustrative
/// JSON and may intentionally contain non-decodable replacement markers.
public struct AgentCommandAction: Codable, Hashable, Sendable {
    public let kind: AgentCommandActionKind
    public let label: String
    public let command: [String]
    public let inputTemplate: String?

    public init(
        kind: AgentCommandActionKind,
        label: String,
        command: [String],
        inputTemplate: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.command = command
        self.inputTemplate = inputTemplate
    }
}
