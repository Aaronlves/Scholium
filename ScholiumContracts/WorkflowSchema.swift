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
    public static func resolve(
        vaultRole: VaultRole,
        frontmatter _: [String: YAMLValue],
        relativePath _: String
    ) -> SchemaProfileID {
        switch vaultRole {
        case .sourceCorpus: return .analysis
        case .topicKnowledge: return .topicMarkdown
        case .draftProject: return .draftProject
        case .other: return .genericMarkdown
        }
    }
}

public extension YAMLValue {
    /// A read-only dotted-key projection for search, filters, and diagnostics.
    /// This is intentionally not a serializer or an editing representation.
    var flattenedScalarValues: [String: String] {
        guard case .object(let values) = self else { return [:] }
        var result: [String: String] = [:]
        Self.flatten(values, prefix: nil, into: &result)
        return result
    }

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

    private static func flatten(
        _ values: [String: YAMLValue],
        prefix: String?,
        into result: inout [String: String]
    ) {
        for key in values.keys.sorted() {
            guard let value = values[key] else { continue }
            let path = prefix.map { "\($0).\(key)" } ?? key
            if case .object(let nested) = value {
                flatten(nested, prefix: path, into: &result)
            } else {
                result[path] = value.displayScalar
            }
        }
    }
}
