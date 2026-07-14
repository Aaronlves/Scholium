import Foundation

/// Versioned semantic profiles understood by Scholium. A profile describes how
/// metadata participates in workflow views; it never replaces exact Markdown.
public enum SchemaProfileID: String, Codable, CaseIterable, Sendable {
    case paperAnalysisV1 = "paper-analysis-yaml-v1"
    case topicMarkdown = "topic-markdown"
    case dissertationControlV3 = "dissertation-control-v3"
    case dissertationControlV4 = "dissertation-control-v4"
    case draftProject = "draft-project"
    case genericMarkdown = "generic-markdown"

    public func automaticSaveTimestampKey(in frontmatter: [String: YAMLValue]) -> String? {
        switch self {
        case .paperAnalysisV1:
            if frontmatter["updated"] != nil { return "updated" }
            if frontmatter["analysis_updated_at"] != nil { return "analysis_updated_at" }
            return "updated"
        case .draftProject:
            if frontmatter["updated"] != nil { return "updated" }
            if frontmatter["modified"] != nil { return "modified" }
            return nil
        case .topicMarkdown, .dissertationControlV3, .dissertationControlV4, .genericMarkdown:
            return nil
        }
    }
}

/// Canonical researcher-facing YAML vocabulary shared by the Analyses,
/// Topics, and Works triptych. Legacy aliases are read-only compatibility
/// inputs until a researcher deliberately edits that property.
public enum TriptychProperty {
    public static let legacyAliases: [String: [String]] = [
        "type": ["source_kind", "work_type"],
        "status": ["analysis_status", "lifecycle_status"],
        "created": ["analysis_created_at"],
        "updated": ["analysis_updated_at", "modified"],
        "access": ["source_access"],
        "locators": ["locator_status"],
        "relevance": ["relevance_rating"],
        "main_topic": ["primary_cluster"],
        "related_topics": ["secondary_clusters"],
        "follow_up": ["follow_up_leads"],
    ]

    public static func value(
        for canonicalKey: String,
        in frontmatter: [String: YAMLValue]
    ) -> YAMLValue? {
        if let value = frontmatter[canonicalKey] { return value }
        for alias in legacyAliases[canonicalKey] ?? [] {
            if let value = frontmatter[alias] { return value }
        }
        return nil
    }

    public static func legacyKey(
        for canonicalKey: String,
        in frontmatter: [String: YAMLValue]
    ) -> String? {
        (legacyAliases[canonicalKey] ?? []).first { frontmatter[$0] != nil }
    }
}

public enum WorkflowProfileResolver {
    /// Resolution order is registered vault role, explicit schema metadata,
    /// configurable legacy folder convention, then generic Markdown.
    public static func resolve(
        vaultRole: VaultRole,
        frontmatter: [String: YAMLValue],
        relativePath: String
    ) -> SchemaProfileID {
        switch vaultRole {
        case .sourceCorpus: return .paperAnalysisV1
        case .topicKnowledge: return .topicMarkdown
        case .dissertationControl:
            return frontmatter["schema_version"] == .string(SchemaProfileID.dissertationControlV4.rawValue)
                ? .dissertationControlV4
                : .dissertationControlV3
        case .draftProject: return .draftProject
        case .other: break
        }

        if frontmatter["schema_version"] == .string(SchemaProfileID.paperAnalysisV1.rawValue)
            || frontmatter["record_type"] == .string("paper_analysis") {
            return .paperAnalysisV1
        }
        if frontmatter["schema_version"] == .string(SchemaProfileID.dissertationControlV4.rawValue) {
            return .dissertationControlV4
        }
        if frontmatter["schema_version"] == .string(SchemaProfileID.dissertationControlV3.rawValue)
            || frontmatter["note_type"] != nil {
            return .dissertationControlV3
        }

        let components = relativePath.lowercased().split(separator: "/")
        if components.contains("papers") { return .paperAnalysisV1 }
        if components.contains("topics") { return .topicMarkdown }
        if components.contains("output") { return .draftProject }
        return .genericMarkdown
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
