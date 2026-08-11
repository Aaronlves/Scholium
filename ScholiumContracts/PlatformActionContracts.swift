import Foundation

public enum PlatformActionSelector: String, Codable, CaseIterable, Hashable, Sendable {
    case source
    case focalNotes = "focal_notes"
    case passage
    case citationStyle = "citation_style"
    case feedback
    case fidelityChecks = "fidelity_checks"
}

public enum PlatformActionOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case search
    case read
    case inspectRelations = "inspect_relations"
    case inspectProperties = "inspect_properties"
    case queryRecords = "query_records"
    case useZotero = "use_zotero"
    case discuss
    case modifyInitialNote = "modify_initial_note"
    case extendWriteSet = "extend_write_set"
    case checkFidelity = "check_fidelity"
    case continueResearch = "continue_research"
}

public struct PlatformActionDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchActionID { actionID }

    public let actionID: ResearchActionID
    public let executionKind: ResearchActionExecutionKind
    public let allowedTargetRoles: [ResearchActionTargetRole]
    public let requiredSelectors: [PlatformActionSelector]
    public let optionalSelectors: [PlatformActionSelector]
    public let operations: [PlatformActionOperation]

    /// The closed mutation kinds an authenticated Run may request for a new
    /// Bounded Write Set member. The Action's initial writable target remains
    /// governed by `ResearchAuthorityEnvelope.writeOperations`; extension
    /// authority is always a later researcher or policy decision.
    public var extensionWriteOperations: [ResearchDocumentWriteOperation] {
        guard operations.contains(.modifyInitialNote),
              operations.contains(.extendWriteSet) else { return [] }
        return [.createNote, .modifyMarkdown, .modifyProperties]
    }

    public init(
        actionID: ResearchActionID,
        executionKind: ResearchActionExecutionKind,
        allowedTargetRoles: [ResearchActionTargetRole],
        requiredSelectors: [PlatformActionSelector] = [],
        optionalSelectors: [PlatformActionSelector] = [],
        operations: [PlatformActionOperation]
    ) throws {
        guard !allowedTargetRoles.isEmpty,
              Set(allowedTargetRoles).count == allowedTargetRoles.count,
              Set(allowedTargetRoles).isSubset(of: executionKind.allowedTargetRoles),
              Set(requiredSelectors).count == requiredSelectors.count,
              Set(optionalSelectors).count == optionalSelectors.count,
              Set(requiredSelectors).isDisjoint(with: Set(optionalSelectors)),
              !operations.isEmpty,
              Set(operations).count == operations.count else {
            throw PlatformActionContractError.invalidDefinition
        }
        if let reserved = Self.reservedExecutionKind(for: actionID),
           reserved != executionKind {
            throw PlatformActionContractError.invalidDefinition
        }
        self.actionID = actionID
        self.executionKind = executionKind
        self.allowedTargetRoles = ResearchActionTargetRole.allCases.filter(
            Set(allowedTargetRoles).contains
        )
        self.requiredSelectors = PlatformActionSelector.allCases.filter(
            Set(requiredSelectors).contains
        )
        self.optionalSelectors = PlatformActionSelector.allCases.filter(
            Set(optionalSelectors).contains
        )
        self.operations = PlatformActionOperation.allCases.filter(
            Set(operations).contains
        )
    }

    private static func reservedExecutionKind(
        for actionID: ResearchActionID
    ) -> ResearchActionExecutionKind? {
        switch actionID {
        case .discuss: .discussion
        case .analyze: .analysis
        case .synthesize: .synthesis
        case .write: .writing
        case .critique: .critique
        case .checkFidelity: .checkFidelity
        case .manuscript: .manuscript
        default: nil
        }
    }

    public func validate(profile: ResearchAcademicActionProfile) throws {
        guard profile.actionID == actionID,
              Set(profile.applicableRoles).isSubset(of: Set(allowedTargetRoles)) else {
            throw PlatformActionContractError.profileExceedsPlatform(actionID)
        }
    }
}

public enum PlatformActionCatalog {
    public static let definitions: [PlatformActionDefinition] = [
        try! PlatformActionDefinition(
            actionID: .discuss,
            executionKind: .discussion,
            allowedTargetRoles: ResearchActionTargetRole.allCases,
            optionalSelectors: [.focalNotes, .passage],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .discuss, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .analyze,
            executionKind: .analysis,
            allowedTargetRoles: [.analysis],
            requiredSelectors: [.source],
            optionalSelectors: [.focalNotes],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .modifyInitialNote, .extendWriteSet, .checkFidelity, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .synthesize,
            executionKind: .synthesis,
            allowedTargetRoles: [.topic],
            optionalSelectors: [.focalNotes, .passage],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .modifyInitialNote, .extendWriteSet, .checkFidelity, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .write,
            executionKind: .writing,
            allowedTargetRoles: [.work],
            optionalSelectors: [.focalNotes, .passage, .citationStyle, .feedback],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .modifyInitialNote, .extendWriteSet, .checkFidelity, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .critique,
            executionKind: .critique,
            allowedTargetRoles: [.work],
            optionalSelectors: [.focalNotes, .passage],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .checkFidelity,
            executionKind: .checkFidelity,
            allowedTargetRoles: ResearchActionTargetRole.allCases,
            optionalSelectors: [.focalNotes, .passage, .citationStyle, .fidelityChecks],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .checkFidelity, .continueResearch]
        ),
        try! PlatformActionDefinition(
            actionID: .manuscript,
            executionKind: .manuscript,
            allowedTargetRoles: [.work],
            optionalSelectors: [.focalNotes, .citationStyle, .feedback],
            operations: [.search, .read, .inspectRelations, .inspectProperties, .queryRecords, .useZotero, .checkFidelity, .continueResearch]
        ),
    ]

    public static func definition(for actionID: ResearchActionID) -> PlatformActionDefinition? {
        definitions.first { $0.actionID == actionID }
    }
}

public enum PlatformActionContractError: LocalizedError, Hashable, Sendable {
    case invalidDefinition
    case profileExceedsPlatform(ResearchActionID)

    public var errorDescription: String? {
        switch self {
        case .invalidDefinition:
            "The protected Platform Action definition is invalid."
        case .profileExceedsPlatform(let actionID):
            "The academic Profile exceeds the protected boundary for \(actionID.rawValue)."
        }
    }
}
