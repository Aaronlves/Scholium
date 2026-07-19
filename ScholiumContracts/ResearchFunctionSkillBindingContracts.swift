import Foundation

/// The role one Triptych-local Researcher Skill plays in a Research Function.
/// These values are Settings/backend semantics, not Research Strip labels.
public enum ResearchFunctionSkillBindingRole: String, Codable, Hashable, Sendable {
    /// Replaces the release-managed primary package for this function while
    /// leaving the function's permissions and completion contract unchanged.
    case primary
    /// Adds one bounded specialist package beneath the primary workflow.
    case supplemental
    /// Selects one exact Practice resource from a researcher-owned library.
    case practice
}

/// Settings-facing metadata for one structurally valid Triptych-local package.
/// Package identifiers are opaque selection values; presentation uses `name`
/// and never derives a label or capability from an identifier or filename.
public struct ResearchFunctionSkillCandidate: Codable, Hashable, Identifiable, Sendable {
    public let packageID: String
    public let name: String
    public let description: String
    public let version: String
    public let supportedFunctions: [ResearchFunctionID]
    public let availableRoles: [ResearchFunctionSkillBindingRole]
    public let practiceIDs: [String]

    public var id: String { packageID }

    public init(
        packageID: String,
        name: String,
        description: String,
        version: String,
        supportedFunctions: [ResearchFunctionID],
        availableRoles: [ResearchFunctionSkillBindingRole],
        practiceIDs: [String] = []
    ) {
        self.packageID = packageID
        self.name = name
        self.description = description
        self.version = version
        self.supportedFunctions = Self.unique(supportedFunctions)
        self.availableRoles = Self.unique(availableRoles)
        self.practiceIDs = Array(Set(practiceIDs)).sorted()
    }

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen: Set<Value> = []
        return values.filter { seen.insert($0).inserted }
    }
}

/// The complete researcher-selected guidance profile for one visible function.
/// A save replaces only this function's profile and preserves all other
/// function and citation bindings.
public struct ResearchFunctionSkillSelection: Codable, Hashable, Sendable {
    public let function: ResearchFunctionID
    public let primaryPackageID: String?
    public let supplementalPackageIDs: [String]
    public let selectedPractices: [ResearchPracticeSelection]

    public init(
        function: ResearchFunctionID,
        primaryPackageID: String? = nil,
        supplementalPackageIDs: [String] = [],
        selectedPractices: [ResearchPracticeSelection] = []
    ) {
        self.function = function
        self.primaryPackageID = primaryPackageID
        self.supplementalPackageIDs = Self.unique(supplementalPackageIDs)
        self.selectedPractices = Self.unique(
            selectedPractices,
            by: \ResearchPracticeSelection.selectionID
        )
    }

    public var isEmpty: Bool {
        primaryPackageID == nil
            && supplementalPackageIDs.isEmpty
            && selectedPractices.isEmpty
    }

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen: Set<Value> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func unique<Value, Key: Hashable>(
        _ values: [Value],
        by keyPath: KeyPath<Value, Key>
    ) -> [Value] {
        var seen: Set<Key> = []
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

public enum ResearchFunctionSkillBindingIssueCode: String, Codable, Hashable, Sendable {
    case functionHasNoSkill = "function_has_no_skill"
    case malformedBinding = "malformed_binding"
    case invalidPackage = "invalid_package"
    case unsupportedFunction = "unsupported_function"
    case invalidRole = "invalid_role"
    case invalidPractice = "invalid_practice"
}

public struct ResearchFunctionSkillBindingIssue: Codable, Hashable, Sendable {
    public let code: ResearchFunctionSkillBindingIssueCode
    public let selectedPackageID: String?
    public let selectedPracticeID: String?

    public init(
        code: ResearchFunctionSkillBindingIssueCode,
        selectedPackageID: String? = nil,
        selectedPracticeID: String? = nil
    ) {
        self.code = code
        self.selectedPackageID = selectedPackageID
        self.selectedPracticeID = selectedPracticeID
    }
}

/// Delivery-neutral Settings state. The Research Strip never receives this
/// value and therefore cannot inspect or select package identifiers.
public struct ResearchFunctionSkillBindingStatus: Codable, Hashable, Sendable {
    public let function: ResearchFunctionID
    public let candidates: [ResearchFunctionSkillCandidate]
    public let selection: ResearchFunctionSkillSelection
    public let bindingRevision: DocumentFingerprint?
    public let issue: ResearchFunctionSkillBindingIssue?

    public init(
        function: ResearchFunctionID,
        candidates: [ResearchFunctionSkillCandidate],
        selection: ResearchFunctionSkillSelection,
        bindingRevision: DocumentFingerprint?,
        issue: ResearchFunctionSkillBindingIssue?
    ) {
        self.function = function
        self.candidates = candidates.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.packageID < rhs.packageID : lhs.name < rhs.name
        }
        self.selection = selection
        self.bindingRevision = bindingRevision
        self.issue = issue
    }
}
