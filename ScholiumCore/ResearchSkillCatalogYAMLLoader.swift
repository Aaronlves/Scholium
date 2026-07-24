import ScholiumContracts
import Yams
import Foundation

extension ResearchSkillCatalog {
    static func parse(yaml: String) throws -> Self {
        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw ResearchSkillCatalogError.malformedCatalog("The YAML root is not a mapping.")
        }
        let schemaVersion = integerValue(root["schema_version"]) ?? 0
        let status = root["status"] as? String ?? "active"
        guard let rawPackages = root["packages"] as? [[String: Any]] else {
            throw ResearchSkillCatalogError.malformedCatalog("The packages list is missing.")
        }
        let entries = try rawPackages.map { raw in
            guard let id = raw["id"] as? String,
                  let name = raw["name"] as? String,
                  let description = raw["description"] as? String,
                  let classValue = raw["class"] as? String,
                  let skillClass = ResearchSkillClass(rawValue: classValue),
                  let role = raw["role"] as? String,
                  let version = raw["version"] as? String,
                  let updatePolicy = raw["update_policy"] as? String,
                  let resourcePath = raw["path"] as? String else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Every package requires id, name, description, class, role, version, update_policy, and path."
                )
            }
            let modes = try modeValues(raw["supported_modes"], field: "supported_modes", id: id)
            let actions = try actionValues(
                raw["supported_actions"],
                field: "supported_actions",
                id: id
            )
            let functions = try functionValues(
                raw["supported_functions"],
                field: "supported_functions",
                id: id
            )
            let capabilities = try capabilityValues(
                raw["capabilities"],
                field: "capabilities",
                id: id
            )
            let citationStyles = try stringValues(
                raw["citation_styles"],
                field: "citation_styles",
                id: id
            )
            let citationStyleResources = try mappingValues(
                raw["citation_style_resources"],
                field: "citation_style_resources",
                id: id
            )
            let automaticModes = try modeValues(
                raw["automatic_modes"],
                field: "automatic_modes",
                id: id
            )
            let compatiblePractices = try stringValues(
                raw["compatible_practices"],
                field: "compatible_practices",
                id: id
            )
            let dependencies = try stringValues(raw["required_skills"], field: "required_skills", id: id)
            let practiceResources = try mappingValues(
                raw["practice_resources"],
                field: "practice_resources",
                id: id
            )
            return ResearchSkillCatalogEntry(
                id: id,
                name: name,
                description: description,
                skillClass: skillClass,
                role: role,
                version: version,
                supportedActions: actions,
                supportedFunctions: functions,
                capabilities: capabilities,
                citationStyles: citationStyles,
                citationStyleResources: citationStyleResources,
                supportedModes: modes,
                automaticModes: automaticModes,
                compatiblePracticeIDs: compatiblePractices,
                requiredSkillIDs: dependencies,
                practiceResources: practiceResources,
                updatePolicy: updatePolicy,
                resourcePath: resourcePath
            )
        }
        return try Self(schemaVersion: schemaVersion, status: status, entries: entries)
    }

    private static func actionValues(
        _ rawValue: Any?,
        field: String,
        id: String
    ) throws -> [ResearchActionID] {
        let values = try stringValues(rawValue, field: field, id: id)
        return try values.map { value in
            guard let actionID = ResearchActionID(rawValue: value) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "Skill \(id) declares an invalid \(field) value: \(value)."
                )
            }
            return actionID
        }
    }

    /// Yams may bridge a YAML integer through Foundation when the catalog is
    /// loaded by an executable rather than a test bundle. Accept only exact
    /// integral representations so the CLI and embedded app enforce the same
    /// schema gate without weakening it to arbitrary numeric coercion.
    private static func integerValue(_ raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(exactly: value)
        case let value as UInt64:
            return Int(exactly: value)
        case let value as NSNumber:
            guard value.doubleValue.rounded(.towardZero) == value.doubleValue else {
                return nil
            }
            return Int(exactly: value.int64Value)
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func stringValues(
        _ raw: Any?,
        field: String,
        id: String
    ) throws -> [String] {
        guard let raw else { return [] }
        guard let values = raw as? [Any] else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "\(id).\(field) must be a list."
            )
        }
        guard values.allSatisfy({ $0 is String }) else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "\(id).\(field) must contain only strings."
            )
        }
        return values.compactMap { $0 as? String }
    }

    private static func modeValues(
        _ raw: Any?,
        field: String,
        id: String
    ) throws -> [ResearchSkillMode] {
        try stringValues(raw, field: field, id: id).map { value in
            guard let mode = ResearchSkillMode(rawValue: value) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "\(id).\(field) contains unsupported mode \(value)."
                )
            }
            return mode
        }
    }

    private static func functionValues(
        _ raw: Any?,
        field: String,
        id: String
    ) throws -> [ResearchFunctionID] {
        try stringValues(raw, field: field, id: id).map { value in
            guard let function = ResearchFunctionID(rawValue: value) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "\(id).\(field) contains unsupported function \(value)."
                )
            }
            return function
        }
    }

    private static func capabilityValues(
        _ raw: Any?,
        field: String,
        id: String
    ) throws -> [ResearchSkillCapability] {
        try stringValues(raw, field: field, id: id).map { value in
            guard let capability = ResearchSkillCapability(rawValue: value) else {
                throw ResearchSkillCatalogError.malformedCatalog(
                    "\(id).\(field) contains unsupported capability \(value)."
                )
            }
            return capability
        }
    }

    private static func mappingValues(
        _ raw: Any?,
        field: String,
        id: String
    ) throws -> [String: String] {
        guard let raw else { return [:] }
        guard let values = raw as? [String: Any],
              values.values.allSatisfy({ $0 is String }) else {
            throw ResearchSkillCatalogError.malformedCatalog(
                "\(id).\(field) must be a string-to-string mapping."
            )
        }
        return values.compactMapValues { $0 as? String }
    }
}
