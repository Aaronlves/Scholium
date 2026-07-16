import Foundation
import ScholiumContracts

/// Portable, researcher-controlled bindings stored beside the Triptych.
/// Package identifiers are data, not interface labels, and are never inferred
/// from filenames or global agent configuration.
public struct ResearchSkillBindingDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// Optional Triptych-local primary-package overrides keyed by semantic
    /// Research Function identifier.
    public let functionBindings: [String: String]
    /// Explicit supplemental Researcher Skills. These refine a function but
    /// never replace its permission or completion boundary.
    public let functionSkillBindings: [String: [String]]
    /// Exact researcher-owned Practice selections keyed by function. A
    /// Practice library never activates merely because it is compatible.
    public let functionPracticeBindings: [String: [ResearchPracticeSelection]]
    public let citationBinding: String?
    /// Explicit semantic style identifier selected with `citationBinding`.
    /// Optional for compatibility decoding of pre-style binding documents.
    public let citationStyle: String?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        functionBindings: [String: String] = [:],
        functionSkillBindings: [String: [String]] = [:],
        functionPracticeBindings: [String: [ResearchPracticeSelection]] = [:],
        citationBinding: String? = nil,
        citationStyle: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.functionBindings = functionBindings
        self.functionSkillBindings = functionSkillBindings
        self.functionPracticeBindings = functionPracticeBindings
        self.citationBinding = citationBinding
        let normalized = citationStyle?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self.citationStyle = normalized?.isEmpty == false ? normalized : nil
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case functionBindings = "function_bindings"
        case functionSkillBindings = "function_skill_bindings"
        case functionPracticeBindings = "function_practice_bindings"
        case citationBinding = "citation_binding"
        case citationStyle = "citation_style"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(
                Int.self,
                forKey: .schemaVersion
            ) ?? Self.currentSchemaVersion,
            functionBindings: try container.decodeIfPresent(
                [String: String].self,
                forKey: .functionBindings
            ) ?? [:],
            functionSkillBindings: try container.decodeIfPresent(
                [String: [String]].self,
                forKey: .functionSkillBindings
            ) ?? [:],
            functionPracticeBindings: try container.decodeIfPresent(
                [String: [ResearchPracticeSelection]].self,
                forKey: .functionPracticeBindings
            ) ?? [:],
            citationBinding: try container.decodeIfPresent(
                String.self,
                forKey: .citationBinding
            ),
            citationStyle: try container.decodeIfPresent(
                String.self,
                forKey: .citationStyle
            )
        )
    }
}

public struct ResearchSkillBindingSnapshot: Hashable, Sendable {
    public let document: ResearchSkillBindingDocument
    public let revision: DocumentFingerprint

    public init(document: ResearchSkillBindingDocument, revision: DocumentFingerprint) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchSkillBindingSource: String, Codable, Hashable, Sendable {
    case bundledDefault = "bundled_default"
    case triptychBinding = "triptych_binding"
    case none
}

public enum ResearchSkillBindingIssue: Hashable, Sendable {
    case missing
    case malformed(String)
    case invalidPackage(String)
    case unsupportedFunction(packageID: String, function: ResearchFunctionID)
    case missingCapability(ResearchSkillCapability)
    case citationStyleMissing(packageID: String)
    case citationStyleMismatch(packageID: String, requested: String)
}

public struct ResearchSkillBindingResolution: Hashable, Sendable {
    public let source: ResearchSkillBindingSource
    public let package: ResearchSkillPackage?
    public let bundledTemplateAvailable: Bool
    public let installedCandidateIDs: [String]
    public let issue: ResearchSkillBindingIssue?
    public let citationStyle: String?
    /// Fingerprint of the safe raw binding file, even when its contents are
    /// malformed. Settings can therefore repair a malformed document without
    /// bypassing revision checks.
    public let bindingRevision: DocumentFingerprint?

    public init(
        source: ResearchSkillBindingSource,
        package: ResearchSkillPackage? = nil,
        bundledTemplateAvailable: Bool = false,
        installedCandidateIDs: [String] = [],
        issue: ResearchSkillBindingIssue? = nil,
        citationStyle: String? = nil,
        bindingRevision: DocumentFingerprint? = nil
    ) {
        self.source = source
        self.package = package
        self.bundledTemplateAvailable = bundledTemplateAvailable
        self.installedCandidateIDs = Array(Set(installedCandidateIDs)).sorted()
        self.issue = issue
        self.citationStyle = citationStyle
        self.bindingRevision = bindingRevision
    }

    public var isActive: Bool { package != nil && issue == nil }
}

public enum ResearchSkillBindingError: LocalizedError, Sendable {
    case unsafeBindingFile
    case staleBindingFile
    case invalidBindingDocument(String)
    case unresolvedBinding(ResearchSkillBindingIssue)

    public var errorDescription: String? {
        switch self {
        case .unsafeBindingFile:
            "The Triptych Research Skill binding file is not a safe regular file."
        case .staleBindingFile:
            "Research Skill bindings changed on disk. Reload them before saving."
        case .invalidBindingDocument(let reason):
            "Research Skill bindings are invalid. \(reason)"
        case .unresolvedBinding(let issue):
            "Research Skill binding cannot be resolved: \(String(describing: issue))"
        }
    }
}

/// Core result of adopting a bundled citation starter. Application projects
/// this into researcher-facing names and never exposes the chosen storage ID
/// as an interface decision.
public struct ResearchSkillCitationAdoption: Hashable, Sendable {
    public let package: ResearchSkillPackage
    public let binding: ResearchSkillBindingSnapshot

    public init(
        package: ResearchSkillPackage,
        binding: ResearchSkillBindingSnapshot
    ) {
        self.package = package
        self.binding = binding
    }
}
