import Foundation

/// Versioned semantic profiles understood by Scholium. A profile describes how
/// metadata participates in workflow views; it never replaces exact Markdown.
public enum SchemaProfileID: String, Codable, CaseIterable, Sendable {
    case analysis = "analysis"
    case topicMarkdown = "topic-markdown"
    case draftProject = "draft-project"
    case genericMarkdown = "generic-markdown"
}

public enum WorkflowProfileResolver {
    /// Registered vault role is the only semantic profile authority.
    public static func resolve(vaultRole: VaultRole) -> SchemaProfileID {
        switch vaultRole {
        case .sourceCorpus: return .analysis
        case .topicKnowledge: return .topicMarkdown
        case .draftProject: return .draftProject
        case .other: return .genericMarkdown
        }
    }
}

public extension YAMLValue {
    var displayScalar: String {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        case .null: "null"
        case .array(let values): values.map(\.displayScalar).joined(separator: ", ")
        case .object(let values):
            values.keys.sorted().compactMap { key in
                values[key].map { "\(key): \($0.displayScalar)" }
            }.joined(separator: "; ")
        }
    }

}
