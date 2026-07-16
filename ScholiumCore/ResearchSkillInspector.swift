import Foundation
import ScholiumContracts
import Yams

enum ResearchSkillInspector {
    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func isValidIdentifier(_ id: String) -> Bool {
        id.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    static func inspect(
        id: String,
        source: String,
        origin: ResearchSkillOrigin,
        additionalIssues: [String] = [],
        catalogEntry: ResearchSkillCatalogEntry? = nil,
        revision: DocumentFingerprint? = nil
    ) -> ResearchSkillPackage {
        var issues = additionalIssues
        if !isValidIdentifier(id) {
            issues.append("The package identifier must use 1–64 lowercase letters, numbers, or hyphens.")
        }
        var name = id
        var description = ""
        var localRole = "specialist"
        var localModes: [ResearchSkillMode] = [.all]
        var localFunctions: [ResearchFunctionID] = []
        var localCapabilities: [ResearchSkillCapability] = []
        var localCitationStyles: [String] = []
        var localCitationStyleResources: [String: String] = [:]
        var localAllowsEvolution = false
        var localCompatiblePractices: [String] = []
        var localDependencies: [String] = []
        var localPracticeResources: [String: String] = [:]
        let lines = source.components(separatedBy: .newlines)
        if lines.first != "---",
           !source.isEmpty {
            issues.append("SKILL.md must begin with YAML frontmatter delimited by ---.")
        } else if let closing = lines.dropFirst().firstIndex(of: "---") {
            let yaml = lines[1..<closing].joined(separator: "\n")
            do {
                let metadata = try Yams.load(yaml: yaml) as? [String: Any]
                name = (metadata?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                description = (metadata?["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.isEmpty { issues.append("Frontmatter requires a nonempty name.") }
                if description.isEmpty { issues.append("Frontmatter requires a nonempty description.") }
                if origin == .triptych, let rawRouting = metadata?["scholium"] {
                    guard let routing = rawRouting as? [String: Any] else {
                        issues.append("Frontmatter scholium metadata must be a mapping.")
                        throw LocalRoutingParseStop()
                    }
                    let allowed = Set([
                        "role",
                        "supported_functions",
                        "capabilities",
                        "citation_styles",
                        "citation_style_resources",
                        "allow_evolution",
                        "supported_modes",
                        "required_skills",
                        "compatible_practices",
                        "practice_resources",
                    ])
                    let unknown = routing.keys.filter { !allowed.contains($0) }.sorted()
                    if !unknown.isEmpty {
                        issues.append(
                            "Unsupported scholium routing "
                                + (unknown.count == 1 ? "field" : "fields")
                                + ": "
                                + unknown.joined(separator: ", ")
                                + "."
                        )
                    }
                    if let role = routing["role"] as? String,
                       ["workflow", "practice", "specialist"].contains(role) {
                        localRole = role
                    } else {
                        issues.append(
                            "scholium.role must be workflow, practice, or specialist."
                        )
                    }
                    localFunctions = Self.localEnumValues(
                        routing["supported_functions"],
                        field: "supported_functions",
                        parse: ResearchFunctionID.init(rawValue:),
                        issues: &issues
                    )
                    localCapabilities = Self.localEnumValues(
                        routing["capabilities"],
                        field: "capabilities",
                        parse: ResearchSkillCapability.init(rawValue:),
                        issues: &issues
                    )
                    localCitationStyles = Self.localCitationStyles(
                        routing["citation_styles"],
                        issues: &issues
                    )
                    localCitationStyleResources = Self.localCitationStyleResources(
                        routing["citation_style_resources"],
                        issues: &issues
                    )
                    if let raw = routing["allow_evolution"] {
                        if let allowed = raw as? Bool {
                            localAllowsEvolution = allowed
                        } else {
                            issues.append("scholium.allow_evolution must be true or false.")
                        }
                    }
                    localModes = Self.localModes(
                        routing["supported_modes"],
                        required: localFunctions.isEmpty,
                        issues: &issues
                    )
                    localDependencies = Self.localIdentifiers(
                        routing["required_skills"],
                        field: "required_skills",
                        issues: &issues
                    )
                    localCompatiblePractices = Self.localIdentifiers(
                        routing["compatible_practices"],
                        field: "compatible_practices",
                        issues: &issues
                    )
                    localPracticeResources = Self.localPracticeResources(
                        routing["practice_resources"],
                        issues: &issues
                    )
                    if localRole == "practice", localPracticeResources.isEmpty {
                        issues.append(
                            "Practice packages must declare at least one practice_resources entry."
                        )
                    } else if localRole != "practice", !localPracticeResources.isEmpty {
                        issues.append(
                            "Only Practice packages may declare practice_resources."
                        )
                    }
                }
            } catch {
                if !(error is LocalRoutingParseStop) {
                    issues.append("Frontmatter is malformed YAML: \(error.localizedDescription)")
                }
            }
            let body = lines[(closing + 1)...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { issues.append("SKILL.md requires instruction content after frontmatter.") }
        } else if !source.isEmpty {
            issues.append("SKILL.md is missing its closing frontmatter delimiter.")
        }
        if source.isEmpty, issues.isEmpty { issues.append("SKILL.md is empty.") }
        return ResearchSkillPackage(
            id: id,
            name: name.isEmpty ? id : name,
            description: description,
            source: source,
            origin: origin,
            skillClass: catalogEntry?.skillClass ?? .researcher,
            role: catalogEntry?.role ?? localRole,
            version: catalogEntry?.version ?? "local",
            updatePolicy: catalogEntry?.updatePolicy ?? "researcher-owned",
            supportedFunctions: catalogEntry?.supportedFunctions ?? localFunctions,
            capabilities: catalogEntry?.capabilities ?? localCapabilities,
            citationStyles: catalogEntry?.citationStyles ?? localCitationStyles,
            citationStyleResources: catalogEntry?.citationStyleResources
                ?? localCitationStyleResources,
            allowsEvolution: catalogEntry == nil && localAllowsEvolution,
            supportedModes: catalogEntry?.supportedModes ?? localModes,
            automaticModes: catalogEntry?.automaticModes ?? [],
            compatiblePracticeIDs: catalogEntry?.compatiblePracticeIDs
                ?? localCompatiblePractices,
            requiredSkillIDs: catalogEntry?.requiredSkillIDs ?? localDependencies,
            practiceResources: catalogEntry?.practiceResources ?? localPracticeResources,
            validationIssues: issues,
            revision: additionalIssues.isEmpty
                ? (revision ?? DocumentFingerprint(content: source))
                : nil
        )
    }

    private struct LocalRoutingParseStop: Error {}

    private static func localModes(
        _ raw: Any?,
        required: Bool,
        issues: inout [String]
    ) -> [ResearchSkillMode] {
        guard let raw else {
            if required {
                issues.append("scholium.supported_modes must be a nonempty list when supported_functions is omitted.")
            }
            return [.all]
        }
        guard let values = raw as? [Any], !values.isEmpty else {
            issues.append("scholium.supported_modes must be a nonempty list.")
            return [.all]
        }
        guard values.allSatisfy({ $0 is String }) else {
            issues.append("scholium.supported_modes must contain only strings.")
            return [.all]
        }
        var modes: [ResearchSkillMode] = []
        for value in values.compactMap({ $0 as? String }) {
            guard let mode = ResearchSkillMode(rawValue: value), mode != .mixed else {
                issues.append("Unsupported researcher Skill mode: \(value).")
                continue
            }
            modes.append(mode)
        }
        if modes.isEmpty {
            issues.append("scholium.supported_modes contains no usable mode.")
            return [.all]
        }
        return unique(modes)
    }

    private static func localIdentifiers(
        _ raw: Any?,
        field: String,
        issues: inout [String]
    ) -> [String] {
        guard let raw else { return [] }
        guard let values = raw as? [Any],
              values.allSatisfy({ $0 is String }) else {
            issues.append("scholium.\(field) must be a list of identifiers.")
            return []
        }
        let identifiers = values.compactMap { $0 as? String }
        for identifier in identifiers where !isValidIdentifier(identifier) {
            issues.append("Invalid identifier in scholium.\(field): \(identifier).")
        }
        return unique(identifiers.filter(isValidIdentifier))
    }

    private static func localEnumValues<Value: Hashable>(
        _ raw: Any?,
        field: String,
        parse: (String) -> Value?,
        issues: inout [String]
    ) -> [Value] {
        guard let raw else { return [] }
        guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
            issues.append("scholium.\(field) must be a list of strings.")
            return []
        }
        var result: [Value] = []
        for value in values.compactMap({ $0 as? String }) {
            guard let parsed = parse(value) else {
                issues.append("Unsupported value in scholium.\(field): \(value).")
                continue
            }
            result.append(parsed)
        }
        return unique(result)
    }

    private static func localCitationStyles(
        _ raw: Any?,
        issues: inout [String]
    ) -> [String] {
        guard let raw else { return [] }
        guard let values = raw as? [Any], values.allSatisfy({ $0 is String }) else {
            issues.append("scholium.citation_styles must be a list of identifiers.")
            return []
        }
        let normalized = values.compactMap { ($0 as? String)?.lowercased() }
        for value in normalized where value.range(
            of: #"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) == nil {
            issues.append("Invalid citation style identifier: \(value).")
        }
        return unique(normalized.filter { value in
            value.range(
                of: #"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
        })
    }

    private static func localPracticeResources(
        _ raw: Any?,
        issues: inout [String]
    ) -> [String: String] {
        guard let raw else { return [:] }
        guard let values = raw as? [String: Any],
              values.values.allSatisfy({ $0 is String }) else {
            issues.append(
                "scholium.practice_resources must be a string-to-string mapping."
            )
            return [:]
        }
        var resources: [String: String] = [:]
        for (identifier, rawPath) in values {
            guard isValidIdentifier(identifier) else {
                issues.append("Invalid Practice identifier: \(identifier).")
                continue
            }
            guard let path = rawPath as? String,
                  path.hasPrefix("references/"),
                  ResearchSkillResourcePath.isAllowed(path) else {
                issues.append("Invalid Practice resource path for \(identifier).")
                continue
            }
            resources[identifier] = path
        }
        return resources
    }

    private static func localCitationStyleResources(
        _ raw: Any?,
        issues: inout [String]
    ) -> [String: String] {
        guard let raw else { return [:] }
        guard let values = raw as? [String: Any],
              values.values.allSatisfy({ $0 is String }) else {
            issues.append(
                "scholium.citation_style_resources must be a string-to-string mapping."
            )
            return [:]
        }
        var resources: [String: String] = [:]
        for (rawStyle, rawPath) in values {
            let style = rawStyle.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard style.range(
                of: #"^[a-z0-9](?:[a-z0-9.-]{0,62}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil else {
                issues.append("Invalid citation style resource identifier: \(rawStyle).")
                continue
            }
            guard let path = rawPath as? String,
                  path.hasPrefix("references/"),
                  ResearchSkillResourcePath.isAllowed(path) else {
                issues.append("Invalid citation style resource path for \(style).")
                continue
            }
            resources[style] = path
        }
        return resources
    }
}
