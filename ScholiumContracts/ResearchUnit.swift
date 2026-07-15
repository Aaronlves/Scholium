import Foundation

/// The small, researcher-authored scope declaration presented as Research Status.
///
/// This type is a semantic read-only projection of exact YAML. It deliberately
/// does not infer scope from folders, titles, links, or derived coverage.
public struct ResearchUnitDeclaration: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case absent
        case declared
        case invalid(String)
    }

    public let state: State
    public let scope: String?
    public let limitations: [String]

    public init(frontmatter: [String: YAMLValue]) {
        guard let rawValue = frontmatter["research_unit"] else {
            self.state = .absent
            self.scope = nil
            self.limitations = []
            return
        }

        guard case .object(let values) = rawValue else {
            self.state = .invalid("Research Status must be a mapping.")
            self.scope = nil
            self.limitations = []
            return
        }

        let allowedKeys = Set(["scope", "limitations"])
        let unknownKeys = values.keys.filter { !allowedKeys.contains($0) }.sorted()
        guard unknownKeys.isEmpty else {
            self.state = .invalid(
                "Unsupported "
                    + (unknownKeys.count == 1 ? "field" : "fields")
                    + ": "
                    + unknownKeys.joined(separator: ", ")
                    + "."
            )
            self.scope = nil
            self.limitations = []
            return
        }

        guard let rawScope = values["scope"],
              case .string(let scope) = rawScope,
              !scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.state = .invalid("Scope is required and cannot be empty.")
            self.scope = nil
            self.limitations = []
            return
        }

        var parsedLimitations: [String] = []
        if let rawLimitations = values["limitations"] {
            guard case .array(let values) = rawLimitations, !values.isEmpty else {
                self.state = .invalid("Limitations must be a non-empty list when present.")
                self.scope = scope
                self.limitations = []
                return
            }

            for value in values {
                guard case .string(let limitation) = value,
                      !limitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.state = .invalid("Each limitation must be a non-empty text value.")
                    self.scope = scope
                    self.limitations = []
                    return
                }
                parsedLimitations.append(limitation)
            }
        }

        self.state = .declared
        self.scope = scope
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
