import Foundation
import ScholiumContracts

public enum ResearchSkillBindingSource: String, Codable, Hashable, Sendable {
    case bundledDefault = "bundled_default"
    case triptychBinding = "triptych_binding"
    case installedDefault = "installed_default"
    case researcherSkill = "researcher_skill"
    case disabled
    case none
}

public enum ResearchSkillBindingIssue: Hashable, Sendable {
    case missing
    case disabled
    case malformed(String)
    case invalidPackage(String)
    case unsupportedFunction(packageID: String, function: ResearchFunctionID)
    case unsupportedAction(packageID: String, actionID: ResearchActionID)
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
    /// Fingerprint of the owning capability document, or of the exact retained
    /// legacy bytes when malformed state still requires explicit repair.
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
    case workingMethodRestoreRecoveryRequired(String)
    case workingMethodEditRecoveryRequired(String)
    case workingMethodBindingRecoveryRequired

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
        case .workingMethodRestoreRecoveryRequired(let packageID):
            "Working Method restoration could not prove one complete package-and-binding outcome for \(packageID). Reload Research Guidance and inspect its recovery snapshots before running this Action."
        case .workingMethodEditRecoveryRequired(let packageID):
            "Working Method editing could not prove one authoritative revision for \(packageID). Reload Research Guidance and inspect its recovery snapshots before running this Action."
        case .workingMethodBindingRecoveryRequired:
            "Working Method bindings may have committed, but their durable state could not be proved. Reload Research Guidance before making another change."
        }
    }
}
