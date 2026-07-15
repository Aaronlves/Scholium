import Foundation

public enum ResearchPromptKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dialogue
    case critique

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dialogue: "Dialogue"
        case .critique: "Critique"
        }
    }

    public var requiredPlaceholders: [String] {
        switch self {
        case .dialogue:
            ["{{researcher_instruction}}", "{{selected_notes}}", "{{editing_rules}}"]
        case .critique:
            ["{{critique_scope}}", "{{critique_lens}}", "{{selected_ranges}}", "{{additional_instructions}}"]
        }
    }
}

public enum ResearchPromptOrigin: String, Codable, Sendable {
    case scholium
    case researcher
}

public enum ResearchGuidanceError: LocalizedError, Sendable {
    case invalidActiveTemplate(ResearchPromptKind, [String])

    public var errorDescription: String? {
        switch self {
        case .invalidActiveTemplate(let kind, let issues):
            return "The active \(kind.displayName) template needs attention in Settings → Research Guidance. \(issues.joined(separator: " "))"
        }
    }
}

public struct ResearchPromptTemplate: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var kind: ResearchPromptKind
    public var name: String
    public var source: String
    public var origin: ResearchPromptOrigin

    public init(
        id: UUID = UUID(),
        kind: ResearchPromptKind,
        name: String,
        source: String,
        origin: ResearchPromptOrigin = .researcher
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.source = source
        self.origin = origin
    }

    public var validationIssues: [String] {
        var issues: [String] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter a template name.")
        }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Enter template instructions.")
        }
        for placeholder in kind.requiredPlaceholders where !source.contains(placeholder) {
            issues.append("Missing required placeholder \(placeholder).")
        }
        return issues
    }
}

public extension ResearchPromptTemplate {
    static let defaultDialogue = ResearchPromptTemplate(
        id: UUID(uuidString: "82E8370D-D378-44F9-9E82-E4F70F941001")!,
        kind: .dialogue,
        name: "Scholium Dialogue",
        source: TriptychSettings.defaultDialoguePromptTemplate,
        origin: .scholium
    )

    static let defaultCritique = ResearchPromptTemplate(
        id: UUID(uuidString: "82E8370D-D378-44F9-9E82-E4F70F941002")!,
        kind: .critique,
        name: "Scholium Critique",
        source: TriptychSettings.defaultCritiquePromptTemplate,
        origin: .scholium
    )
}
