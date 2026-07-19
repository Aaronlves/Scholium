import Foundation

/// Settings-facing metadata for one valid Triptych-local citation method.
/// `packageID` is an opaque semantic selection value and is never interface
/// copy or a filename-derived capability claim.
public struct ResearchCitationMethodCandidate: Codable, Hashable, Identifiable, Sendable {
    public let packageID: String
    public let name: String
    public let description: String
    public let version: String
    public let citationStyles: [String]

    public var id: String { packageID }

    public init(
        packageID: String,
        name: String,
        description: String,
        version: String,
        citationStyles: [String]
    ) {
        self.packageID = packageID
        self.name = name
        self.description = description
        self.version = version
        self.citationStyles = Array(Set(citationStyles)).sorted()
    }
}

public enum ResearchCitationMethodIssueCode: String, Codable, Hashable, Sendable {
    case missing
    case malformedBinding = "malformed_binding"
    case invalidPackage = "invalid_package"
    case missingCapability = "missing_capability"
    case citationStyleMissing = "citation_style_missing"
    case citationStyleMismatch = "citation_style_mismatch"
}

public struct ResearchCitationMethodIssue: Codable, Hashable, Sendable {
    public let code: ResearchCitationMethodIssueCode
    public let selectedPackageID: String?

    public init(code: ResearchCitationMethodIssueCode, selectedPackageID: String? = nil) {
        self.code = code
        self.selectedPackageID = selectedPackageID
    }
}

public struct ResearchCitationMethodStatus: Codable, Hashable, Sendable {
    public let bundledTemplateAvailable: Bool
    public let candidates: [ResearchCitationMethodCandidate]
    public let activePackageID: String?
    /// The semantic citation-style identifier explicitly selected in
    /// Settings. It is never inferred from a package name or resource path.
    public let activeCitationStyle: String?
    public let bindingRevision: DocumentFingerprint?
    public let issue: ResearchCitationMethodIssue?

    public init(
        bundledTemplateAvailable: Bool,
        candidates: [ResearchCitationMethodCandidate],
        activePackageID: String?,
        activeCitationStyle: String? = nil,
        bindingRevision: DocumentFingerprint?,
        issue: ResearchCitationMethodIssue?
    ) {
        self.bundledTemplateAvailable = bundledTemplateAvailable
        self.candidates = candidates.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.packageID < rhs.packageID : lhs.name < rhs.name
        }
        self.activePackageID = activePackageID
        self.activeCitationStyle = activeCitationStyle
        self.bindingRevision = bindingRevision
        self.issue = issue
    }
}

public struct ResearchCitationMethodSelection: Codable, Hashable, Sendable {
    public let packageID: String
    public let citationStyle: String

    public init(packageID: String, citationStyle: String) {
        self.packageID = packageID
        self.citationStyle = citationStyle.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
