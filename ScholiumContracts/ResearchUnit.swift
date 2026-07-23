import Foundation

/// A deliberately small indication of how much source material an Analysis
/// represents. It does not identify particular chapters or judge whether the
/// analysis is philosophically adequate.
public enum AnalysisCompletion: Codable, Hashable, Sendable {
    case complete
    case incomplete
    case represented(completed: Int, total: Int)

    public init?(yamlScalar: String) {
        let normalized = yamlScalar.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized.lowercased() {
        case "complete":
            self = .complete
        case "incomplete":
            self = .incomplete
        default:
            let components = normalized.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard components.count == 2,
                  let completed = Int(components[0].trimmingCharacters(in: .whitespaces)),
                  let total = Int(components[1].trimmingCharacters(in: .whitespaces)),
                  total > 0,
                  completed >= 0,
                  completed <= total else { return nil }
            self = .represented(completed: completed, total: total)
        }
    }

    public var yamlScalar: String {
        switch self {
        case .complete: "complete"
        case .incomplete: "incomplete"
        case .represented(let completed, let total): "\(completed)/\(total)"
        }
    }
}

/// The role-aware, researcher-authored boundary declaration projected from
/// exact YAML. Analysis uses completion; Topic and Work use scope. Every role
/// may state material limitations, and no value is inferred from Zotero or
/// derived document structure.
public struct ResearchUnitDeclaration: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case absent
        case declared
        case invalid(String)
    }

    public let state: State
    public let completion: AnalysisCompletion?
    public let scope: String?
    public let limitations: [String]

    public init(frontmatter: [String: YAMLValue], profile: SchemaProfileID) {
        guard let rawValue = frontmatter["research_unit"] else {
            self.state = .absent
            self.completion = nil
            self.scope = nil
            self.limitations = []
            return
        }

        guard case .object(let values) = rawValue else {
            self.state = .invalid("research_unit must be a mapping.")
            self.completion = nil
            self.scope = nil
            self.limitations = []
            return
        }

        let allowedKeys: Set<String>
        switch profile {
        case .analysis:
            allowedKeys = ["completion", "limitations"]
        case .topicMarkdown, .draftProject:
            allowedKeys = ["scope", "limitations"]
        case .genericMarkdown:
            self.state = .invalid("research_unit is not defined for this note role.")
            self.completion = nil
            self.scope = nil
            self.limitations = []
            return
        }
        let unknownKeys = values.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard unknownKeys.isEmpty else {
            self.state = .invalid(
                "Unsupported "
                    + (unknownKeys.count == 1 ? "field" : "fields")
                    + ": "
                    + unknownKeys.joined(separator: ", ")
                    + "."
            )
            self.completion = nil
            self.scope = nil
            self.limitations = []
            return
        }

        var parsedCompletion: AnalysisCompletion?
        if let rawCompletion = values["completion"] {
            guard case .string(let scalar) = rawCompletion,
                  let completion = AnalysisCompletion(yamlScalar: scalar) else {
                self.state = .invalid(
                    "Completion must be complete, incomplete, or a valid completed/total ratio."
                )
                self.completion = nil
                self.scope = nil
                self.limitations = []
                return
            }
            parsedCompletion = completion
        }

        var parsedScope: String?
        if let rawScope = values["scope"] {
            guard case .string(let scope) = rawScope,
                  !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.state = .invalid("Scope must be non-empty text when present.")
                self.completion = nil
                self.scope = nil
                self.limitations = []
                return
            }
            parsedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parsedLimitations: [String] = []
        if let rawLimitations = values["limitations"] {
            guard case .array(let values) = rawLimitations, !values.isEmpty else {
                self.state = .invalid("Limitations must be a non-empty list when present.")
                self.completion = parsedCompletion
                self.scope = parsedScope
                self.limitations = []
                return
            }

            for value in values {
                guard case .string(let limitation) = value,
                      !limitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.state = .invalid("Each limitation must be a non-empty text value.")
                    self.completion = parsedCompletion
                    self.scope = parsedScope
                    self.limitations = []
                    return
                }
                parsedLimitations.append(
                    limitation.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        let hasRoleValue = switch profile {
        case .analysis: parsedCompletion != nil
        case .topicMarkdown, .draftProject: parsedScope != nil
        case .genericMarkdown: false
        }
        guard hasRoleValue || !parsedLimitations.isEmpty else {
            self.state = .invalid("research_unit must contain at least one non-empty member.")
            self.completion = nil
            self.scope = nil
            self.limitations = []
            return
        }

        self.state = .declared
        self.completion = parsedCompletion
        self.scope = parsedScope
        self.limitations = parsedLimitations
    }

    public var isDeclared: Bool {
        if case .declared = state { return true }
        return false
    }

    public var isInvalid: Bool {
        if case .invalid = state { return true }
        return false
    }

    public var validationMessage: String? {
        guard case .invalid(let message) = state else { return nil }
        return message
    }
}
