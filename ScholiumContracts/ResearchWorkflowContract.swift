import Foundation

public enum ResearchWorkflowPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case readOnly = "read-only"
    case candidateOnly = "candidate-only"
    case directEditAuthorized = "direct-edit-authorized"
}

public enum ResearchWorkflowDurability: String, Codable, CaseIterable, Hashable, Sendable {
    case ephemeral
    case handoff
    case durableUpdate = "durable-update"
}

public enum ResearchWorkflowObjectKind: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case dialogue
    case zoteroItem = "zotero-item"
    case sourceFile = "source-file"
    case inlineMaterial = "inline-material"
    case workspaceCatalog = "workspace-catalog"
    case skillResource = "skill-resource"
    case other
}

/// One exact task object. Its fingerprint is a revision check, never a
/// permission token.
public struct ResearchWorkflowObjectReference: Codable, Hashable, Sendable {
    public let kind: ResearchWorkflowObjectKind
    public let identifier: String
    public let fingerprint: DocumentFingerprint?

    public init(
        kind: ResearchWorkflowObjectKind,
        identifier: String,
        fingerprint: DocumentFingerprint? = nil
    ) {
        self.kind = kind
        self.identifier = identifier
        self.fingerprint = fingerprint
    }

    public var identity: String { "\(kind.rawValue):\(identifier)" }
}

public enum ResearchUnitAuthorization: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case scopeDeclared = "scope-declared"
    case scopeChangeAuthorized = "scope-change-authorized"
}

/// Ephemeral Research Unit context for one agent task. The durable source of
/// truth remains the note's exact YAML.
public struct ResearchWorkflowResearchUnit: Codable, Hashable, Sendable {
    public let currentScope: String?
    public let currentLimitations: [String]
    public let proposedScope: String?
    public let proposedLimitations: [String]

    public init(
        currentScope: String? = nil,
        currentLimitations: [String] = [],
        proposedScope: String? = nil,
        proposedLimitations: [String] = []
    ) {
        self.currentScope = currentScope
        self.currentLimitations = currentLimitations
        self.proposedScope = proposedScope
        self.proposedLimitations = proposedLimitations
    }

    public var proposesChange: Bool {
        proposedScope != nil || !proposedLimitations.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case currentScope = "current_scope"
        case currentLimitations = "current_limitations"
        case proposedScope = "proposed_scope"
        case proposedLimitations = "proposed_limitations"
    }
}

public enum ResearchWorkflowResponseContractSource: String, Codable, Hashable, Sendable {
    case none
    case requestSnapshot = "request-snapshot"
    case legacyFallback = "legacy-fallback"
}

public enum ResearchPracticeApplication: String, Codable, Hashable, Sendable {
    case supplement
    case replace
}

/// An explicit researcher-owned Practice selection. Compatibility remains a
/// routing hint and does not activate a Practice automatically.
public struct ResearchPracticeSelection: Codable, Hashable, Sendable {
    public let packageID: String
    public let practiceID: String
    public let application: ResearchPracticeApplication
    public let officialSkillID: String?
    public let editablePoint: String?
    public let scope: String?
    public let reason: String?
    public let precedence: Int?

    public init(
        packageID: String,
        practiceID: String,
        application: ResearchPracticeApplication = .supplement,
        officialSkillID: String? = nil,
        editablePoint: String? = nil,
        scope: String? = nil,
        reason: String? = nil,
        precedence: Int? = nil
    ) {
        self.packageID = packageID
        self.practiceID = practiceID
        self.application = application
        self.officialSkillID = officialSkillID
        self.editablePoint = editablePoint
        self.scope = scope
        self.reason = reason
        self.precedence = precedence
    }

    public var selectionID: String { "\(packageID):\(practiceID)" }

    private enum CodingKeys: String, CodingKey {
        case packageID = "package_id"
        case practiceID = "practice_id"
        case application
        case officialSkillID = "official_skill_id"
        case editablePoint = "editable_point"
        case scope
        case reason
        case precedence
    }
}

public enum ResearchWorkflowAuditState: String, Codable, Hashable, Sendable {
    case none
    case auditNeeded = "audit-needed"
    case audited
    case stale
}

/// The explicit status of material passed to a later phase. A handoff is an
/// input for reassessment, not accepted or settled knowledge.
public struct ResearchWorkflowHandoff: Codable, Hashable, Sendable {
    /// A handoff is always provisional input for reassessment. Setting this to
    /// false is structurally invalid and never converts material into settled
    /// researcher knowledge.
    public let provisional: Bool
    public let summary: String
    public let evidenceStatus: String
    public let basis: [ResearchWorkflowObjectReference]
    public let reconstructionStatus: String?
    public let unresolvedQuestions: [String]
    public let candidateTargets: [ResearchWorkflowObjectReference]
    public let checksRequired: [String]

    public init(
        provisional: Bool = true,
        summary: String,
        evidenceStatus: String,
        basis: [ResearchWorkflowObjectReference] = [],
        reconstructionStatus: String? = nil,
        unresolvedQuestions: [String] = [],
        candidateTargets: [ResearchWorkflowObjectReference] = [],
        checksRequired: [String] = []
    ) {
        self.provisional = provisional
        self.summary = summary
        self.evidenceStatus = evidenceStatus
        self.basis = basis
        self.reconstructionStatus = reconstructionStatus
        self.unresolvedQuestions = unresolvedQuestions
        self.candidateTargets = candidateTargets
        self.checksRequired = checksRequired
    }

    private enum CodingKeys: String, CodingKey {
        case provisional
        case summary
        case evidenceStatus = "evidence_status"
        case basis
        case reconstructionStatus = "reconstruction_status"
        case unresolvedQuestions = "unresolved_questions"
        case candidateTargets = "candidate_targets"
        case checksRequired = "checks_required"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provisional = try container.decodeIfPresent(Bool.self, forKey: .provisional) ?? true
        summary = try container.decode(String.self, forKey: .summary)
        evidenceStatus = try container.decode(String.self, forKey: .evidenceStatus)
        basis = try container.decodeIfPresent(
            [ResearchWorkflowObjectReference].self,
            forKey: .basis
        ) ?? []
        reconstructionStatus = try container.decodeIfPresent(
            String.self,
            forKey: .reconstructionStatus
        )
        unresolvedQuestions = try container.decodeIfPresent(
            [String].self,
            forKey: .unresolvedQuestions
        ) ?? []
        candidateTargets = try container.decodeIfPresent(
            [ResearchWorkflowObjectReference].self,
            forKey: .candidateTargets
        ) ?? []
        checksRequired = try container.decodeIfPresent(
            [String].self,
            forKey: .checksRequired
        ) ?? []
    }
}

public struct ResearchWorkflowPhaseContract: Codable, Hashable, Sendable {
    public let phase: Int
    public let mode: ResearchSkillMode
    public let purpose: String
    public let requiredSkillIDs: [String]
    public let selectedPractices: [ResearchPracticeSelection]
    public let readSet: [ResearchWorkflowObjectReference]
    public let writeSet: [ResearchWorkflowObjectReference]
    public let permission: ResearchWorkflowPermission
    public let permissionBasis: String
    public let output: String
    public let stopCondition: String
    public let durability: ResearchWorkflowDurability
    public let handoff: ResearchWorkflowHandoff
    public let auditState: ResearchWorkflowAuditState

    public init(
        phase: Int,
        mode: ResearchSkillMode,
        purpose: String,
        requiredSkillIDs: [String],
        selectedPractices: [ResearchPracticeSelection] = [],
        readSet: [ResearchWorkflowObjectReference],
        writeSet: [ResearchWorkflowObjectReference],
        permission: ResearchWorkflowPermission,
        permissionBasis: String,
        output: String,
        stopCondition: String,
        durability: ResearchWorkflowDurability,
        handoff: ResearchWorkflowHandoff,
        auditState: ResearchWorkflowAuditState = .none
    ) {
        self.phase = phase
        self.mode = mode
        self.purpose = purpose
        self.requiredSkillIDs = Self.unique(requiredSkillIDs)
        self.selectedPractices = selectedPractices
        self.readSet = Self.unique(readSet)
        self.writeSet = Self.unique(writeSet)
        self.permission = permission
        self.permissionBasis = permissionBasis
        self.output = output
        self.stopCondition = stopCondition
        self.durability = durability
        self.handoff = handoff
        self.auditState = auditState
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case mode
        case purpose
        case requiredSkillIDs = "required_skills"
        case selectedPractices = "selected_practices"
        case readSet = "read_set"
        case writeSet = "write_set"
        case permission
        case permissionBasis = "permission_basis"
        case output
        case stopCondition = "stop_condition"
        case durability
        case handoff
        case auditState = "audit_state"
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public struct ResearchWorkflowContract: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let mode: ResearchSkillMode
    public let taskObject: String
    public let purpose: String
    public let originalReadSet: [ResearchWorkflowObjectReference]
    public let originalWriteSet: [ResearchWorkflowObjectReference]
    public let researchUnit: ResearchWorkflowResearchUnit?
    public let researchUnitAuthorization: ResearchUnitAuthorization
    public let dialogueTarget: UUID?
    public let responseContractSource: ResearchWorkflowResponseContractSource
    public let phases: [ResearchWorkflowPhaseContract]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        mode: ResearchSkillMode,
        taskObject: String,
        purpose: String,
        originalReadSet: [ResearchWorkflowObjectReference],
        originalWriteSet: [ResearchWorkflowObjectReference],
        researchUnit: ResearchWorkflowResearchUnit? = nil,
        researchUnitAuthorization: ResearchUnitAuthorization = .none,
        dialogueTarget: UUID? = nil,
        responseContractSource: ResearchWorkflowResponseContractSource = .none,
        phases: [ResearchWorkflowPhaseContract]
    ) {
        self.schemaVersion = schemaVersion
        self.mode = mode
        self.taskObject = taskObject
        self.purpose = purpose
        self.originalReadSet = Self.unique(originalReadSet)
        self.originalWriteSet = Self.unique(originalWriteSet)
        self.researchUnit = researchUnit
        self.researchUnitAuthorization = researchUnitAuthorization
        self.dialogueTarget = dialogueTarget
        self.responseContractSource = responseContractSource
        self.phases = phases
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchWorkflowContractError.invalid(
                "Unsupported workflow contract schema version \(schemaVersion)."
            )
        }
        try Self.requireText(taskObject, field: "task_object")
        try Self.requireText(purpose, field: "purpose")
        guard !phases.isEmpty else {
            throw ResearchWorkflowContractError.invalid(
                "A workflow contract requires at least one phase."
            )
        }
        if phases.count == 1 {
            guard mode != .mixed, mode != .all, phases[0].mode == mode else {
                throw ResearchWorkflowContractError.invalid(
                    "A one-phase contract must use the same ordinary top-level and phase mode."
                )
            }
        } else if mode != .mixed {
            throw ResearchWorkflowContractError.invalid(
                "A contract with multiple phases must use mixed mode."
            )
        }
        guard phases.map(\.phase) == Array(1...phases.count) else {
            throw ResearchWorkflowContractError.invalid(
                "Workflow phases must be numbered consecutively from 1."
            )
        }
        let allowedRead = Set(originalReadSet)
        let allowedWrite = Set(originalWriteSet)
        for reference in originalReadSet + originalWriteSet {
            try Self.validate(reference: reference)
        }
        for phase in phases {
            guard phase.mode != .mixed, phase.mode != .all else {
                throw ResearchWorkflowContractError.invalid(
                    "Phase \(phase.phase) must use one ordinary mode."
                )
            }
            try Self.requireText(phase.purpose, field: "phase.purpose")
            try Self.requireText(phase.output, field: "phase.output")
            try Self.requireText(phase.stopCondition, field: "phase.stop_condition")
            try Self.requireText(phase.handoff.summary, field: "phase.handoff.summary")
            try Self.requireText(
                phase.handoff.evidenceStatus,
                field: "phase.handoff.evidence_status"
            )
            guard phase.handoff.provisional else {
                throw ResearchWorkflowContractError.invalid(
                    "Phase \(phase.phase) handoff must remain provisional."
                )
            }
            guard phase.readSet.allSatisfy(allowedRead.contains) else {
                throw ResearchWorkflowContractError.invalid(
                    "Phase \(phase.phase) reads outside the original read boundary."
                )
            }
            guard phase.writeSet.allSatisfy(allowedWrite.contains) else {
                throw ResearchWorkflowContractError.invalid(
                    "Phase \(phase.phase) writes outside the original write boundary."
                )
            }
            for reference in phase.readSet + phase.writeSet {
                try Self.validate(reference: reference)
            }
            for skillID in phase.requiredSkillIDs where !Self.isIdentifier(skillID) {
                throw ResearchWorkflowContractError.invalid(
                    "Phase \(phase.phase) contains an invalid required Skill identifier: \(skillID)."
                )
            }
            switch phase.permission {
            case .readOnly:
                guard phase.writeSet.isEmpty, phase.durability != .durableUpdate else {
                    throw ResearchWorkflowContractError.invalid(
                        "A read-only phase cannot declare a research write or durable update."
                    )
                }
            case .candidateOnly:
                guard phase.writeSet.isEmpty, phase.durability != .durableUpdate else {
                    throw ResearchWorkflowContractError.invalid(
                        "A candidate-only phase cannot declare a research write or durable update."
                    )
                }
            case .directEditAuthorized:
                try Self.requireText(
                    phase.permissionBasis,
                    field: "phase.permission_basis"
                )
                guard !phase.writeSet.isEmpty, phase.durability == .durableUpdate else {
                    throw ResearchWorkflowContractError.invalid(
                        "A direct-edit phase requires an exact write set and durable-update status."
                    )
                }
                guard phase.writeSet.allSatisfy({ $0.fingerprint != nil }) else {
                    throw ResearchWorkflowContractError.invalid(
                        "Every directly edited target requires its current fingerprint."
                    )
                }
            }
            for selection in phase.selectedPractices {
                try Self.validate(selection: selection)
            }
        }
        if let researchUnit {
            guard researchUnit.currentScope?.trimmedNonempty != nil
                    || researchUnit.proposedScope?.trimmedNonempty != nil else {
                throw ResearchWorkflowContractError.invalid(
                    "Research Unit context requires a current or proposed scope."
                )
            }
            guard researchUnitAuthorization != .none else {
                throw ResearchWorkflowContractError.invalid(
                    "Declared Research Unit context requires an explicit authorization state."
                )
            }
            if researchUnit.proposesChange,
               researchUnitAuthorization != .scopeChangeAuthorized {
                throw ResearchWorkflowContractError.invalid(
                    "A proposed Research Unit change requires scope-change-authorized."
                )
            }
        } else if researchUnitAuthorization != .none {
            throw ResearchWorkflowContractError.invalid(
                "Research Unit authorization cannot be declared without Research Unit context."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case mode
        case taskObject = "task_object"
        case purpose
        case originalReadSet = "original_read_set"
        case originalWriteSet = "original_write_set"
        case researchUnit = "research_unit"
        case researchUnitAuthorization = "research_unit_authorization"
        case dialogueTarget = "dialogue_target"
        case responseContractSource = "response_contract_source"
        case phases
    }

    private static func validate(reference: ResearchWorkflowObjectReference) throws {
        try requireText(reference.identifier, field: "object.identifier")
        if let fingerprint = reference.fingerprint {
            guard fingerprint.sha256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil,
            fingerprint.byteCount >= 0 else {
                throw ResearchWorkflowContractError.invalid(
                    "An object fingerprint is malformed."
                )
            }
        }
    }

    private static func validate(selection: ResearchPracticeSelection) throws {
        guard isIdentifier(selection.packageID), isIdentifier(selection.practiceID) else {
            throw ResearchWorkflowContractError.invalid(
                "Practice selections require stable lowercase package and Practice identifiers."
            )
        }
        if selection.application == .replace {
            for (value, field) in [
                (selection.officialSkillID, "official_skill_id"),
                (selection.editablePoint, "editable_point"),
                (selection.scope, "scope"),
                (selection.reason, "reason"),
            ] {
                guard value?.trimmedNonempty != nil else {
                    throw ResearchWorkflowContractError.invalid(
                        "A replacement Practice requires \(field)."
                    )
                }
            }
            guard selection.officialSkillID.map(isIdentifier) == true else {
                throw ResearchWorkflowContractError.invalid(
                    "A replacement Practice requires a stable official Skill identifier."
                )
            }
        }
    }

    private static func requireText(_ text: String, field: String) throws {
        guard text.trimmedNonempty != nil else {
            throw ResearchWorkflowContractError.invalid("\(field) cannot be empty.")
        }
    }

    private static func isIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen: Set<T> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum ResearchWorkflowContractError: LocalizedError, Sendable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason):
            "The workflow contract is invalid. \(reason)"
        }
    }
}

public struct ResolvedResearchSkillResource: Codable, Hashable, Sendable {
    public let relativePath: String
    public let revision: DocumentFingerprint
    public let source: String

    public init(relativePath: String, revision: DocumentFingerprint, source: String) {
        self.relativePath = relativePath
        self.revision = revision
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case revision
        case source
    }
}

public struct ResolvedResearchSkillSelection: Codable, Hashable, Sendable {
    public let id: String
    public let origin: ResearchSkillOrigin
    public let version: String
    public let packageRevision: DocumentFingerprint
    public let availableResourcePaths: [String]
    public let loadedResources: [ResolvedResearchSkillResource]

    public init(
        id: String,
        origin: ResearchSkillOrigin,
        version: String,
        packageRevision: DocumentFingerprint,
        availableResourcePaths: [String],
        loadedResources: [ResolvedResearchSkillResource]
    ) {
        self.id = id
        self.origin = origin
        self.version = version
        self.packageRevision = packageRevision
        self.availableResourcePaths = availableResourcePaths
        self.loadedResources = loadedResources
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case origin
        case version
        case packageRevision = "package_revision"
        case availableResourcePaths = "available_resources"
        case loadedResources = "loaded_resources"
    }
}

public struct ResolvedResearchWorkflowPhase: Codable, Hashable, Sendable {
    public let contract: ResearchWorkflowPhaseContract
    public let packages: [ResolvedResearchSkillSelection]
    public let warnings: [String]
    public let blockingConflicts: [String]
    public let renderedInstructions: String

    public init(
        contract: ResearchWorkflowPhaseContract,
        packages: [ResolvedResearchSkillSelection],
        warnings: [String],
        blockingConflicts: [String],
        renderedInstructions: String
    ) {
        self.contract = contract
        self.packages = packages
        self.warnings = warnings
        self.blockingConflicts = blockingConflicts
        self.renderedInstructions = renderedInstructions
    }

    private enum CodingKeys: String, CodingKey {
        case contract
        case packages
        case warnings
        case blockingConflicts = "blocking_conflicts"
        case renderedInstructions = "rendered_instructions"
    }
}

public struct ResolvedResearchWorkflowEnvelope: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let contract: ResearchWorkflowContract
    public let phases: [ResolvedResearchWorkflowPhase]
    public let warnings: [String]
    public let blockingConflicts: [String]
    public let renderedInstructions: String

    public var isExecutable: Bool { blockingConflicts.isEmpty }

    public init(
        contract: ResearchWorkflowContract,
        phases: [ResolvedResearchWorkflowPhase],
        warnings: [String],
        blockingConflicts: [String],
        renderedInstructions: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.contract = contract
        self.phases = phases
        self.warnings = warnings
        self.blockingConflicts = blockingConflicts
        self.renderedInstructions = renderedInstructions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case contract
        case phases
        case warnings
        case blockingConflicts = "blocking_conflicts"
        case renderedInstructions = "rendered_instructions"
        case isExecutable = "is_executable"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(contract, forKey: .contract)
        try container.encode(phases, forKey: .phases)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(blockingConflicts, forKey: .blockingConflicts)
        try container.encode(renderedInstructions, forKey: .renderedInstructions)
        try container.encode(isExecutable, forKey: .isExecutable)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        contract = try container.decode(ResearchWorkflowContract.self, forKey: .contract)
        phases = try container.decode([ResolvedResearchWorkflowPhase].self, forKey: .phases)
        warnings = try container.decode([String].self, forKey: .warnings)
        blockingConflicts = try container.decode([String].self, forKey: .blockingConflicts)
        renderedInstructions = try container.decode(String.self, forKey: .renderedInstructions)
    }
}

public struct ResearchAuditMarker: Codable, Hashable, Sendable {
    public let target: ResearchWorkflowObjectReference
    public let fingerprint: DocumentFingerprint
    public let auditScope: [String]
    public let evidenceRevisions: [DocumentFingerprint]
    public let phase: Int
    public let sourceMode: ResearchSkillMode
    public let substantive: Bool

    public init(
        target: ResearchWorkflowObjectReference,
        fingerprint: DocumentFingerprint,
        auditScope: [String],
        evidenceRevisions: [DocumentFingerprint] = [],
        phase: Int,
        sourceMode: ResearchSkillMode,
        substantive: Bool = true
    ) {
        self.target = target
        self.fingerprint = fingerprint
        self.auditScope = Self.normalized(auditScope)
        self.evidenceRevisions = Self.normalized(evidenceRevisions)
        self.phase = phase
        self.sourceMode = sourceMode
        self.substantive = substantive
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case fingerprint
        case auditScope = "audit_scope"
        case evidenceRevisions = "evidence_revisions"
        case phase
        case sourceMode = "source_mode"
        case substantive
    }

    private static func normalized(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()
    }

    private static func normalized(_ values: [DocumentFingerprint]) -> [DocumentFingerprint] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.sha256, $0) })
            .values.sorted { $0.sha256 < $1.sha256 }
    }
}

public struct ResearchCompletedAudit: Codable, Hashable, Sendable {
    public let target: ResearchWorkflowObjectReference
    public let fingerprint: DocumentFingerprint
    public let auditScope: [String]
    public let evidenceRevisions: [DocumentFingerprint]

    public init(
        target: ResearchWorkflowObjectReference,
        fingerprint: DocumentFingerprint,
        auditScope: [String],
        evidenceRevisions: [DocumentFingerprint] = []
    ) {
        self.target = target
        self.fingerprint = fingerprint
        self.auditScope = Array(Set(auditScope)).sorted()
        self.evidenceRevisions = Dictionary(
            uniqueKeysWithValues: evidenceRevisions.map { ($0.sha256, $0) }
        ).values.sorted { $0.sha256 < $1.sha256 }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case fingerprint
        case auditScope = "audit_scope"
        case evidenceRevisions = "evidence_revisions"
    }
}

public struct ResearchAuditPlanningInput: Codable, Hashable, Sendable {
    public let markers: [ResearchAuditMarker]
    public let completedAudits: [ResearchCompletedAudit]

    public init(
        markers: [ResearchAuditMarker],
        completedAudits: [ResearchCompletedAudit] = []
    ) {
        self.markers = markers
        self.completedAudits = completedAudits
    }

    private enum CodingKeys: String, CodingKey {
        case markers
        case completedAudits = "completed_audits"
    }
}

public struct ResearchAuditJob: Codable, Hashable, Sendable {
    public let target: ResearchWorkflowObjectReference
    public let fingerprint: DocumentFingerprint
    public let auditScope: [String]
    public let evidenceRevisions: [DocumentFingerprint]

    public init(marker: ResearchAuditMarker) {
        self.target = marker.target
        self.fingerprint = marker.fingerprint
        self.auditScope = marker.auditScope
        self.evidenceRevisions = marker.evidenceRevisions
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case fingerprint
        case auditScope = "audit_scope"
        case evidenceRevisions = "evidence_revisions"
    }
}

public struct ResearchAuditPlan: Codable, Hashable, Sendable {
    public let scheduled: [ResearchAuditJob]
    public let reused: [ResearchAuditJob]
    public let ignoredAuditPhaseMarkers: Int

    public init(
        scheduled: [ResearchAuditJob],
        reused: [ResearchAuditJob],
        ignoredAuditPhaseMarkers: Int
    ) {
        self.scheduled = scheduled
        self.reused = reused
        self.ignoredAuditPhaseMarkers = ignoredAuditPhaseMarkers
    }

    private enum CodingKeys: String, CodingKey {
        case scheduled
        case reused
        case ignoredAuditPhaseMarkers = "ignored_audit_phase_markers"
    }
}

public enum ResearchAuditPlanner {
    public static func plan(_ input: ResearchAuditPlanningInput) throws -> ResearchAuditPlan {
        for marker in input.markers {
            guard marker.phase > 0 else {
                throw ResearchWorkflowContractError.invalid(
                    "Audit markers require a positive phase number."
                )
            }
            guard !marker.auditScope.isEmpty else {
                throw ResearchWorkflowContractError.invalid(
                    "Audit markers require a nonempty audit scope."
                )
            }
            try validate(reference: marker.target, fingerprint: marker.fingerprint)
            guard marker.auditScope.allSatisfy({ $0.trimmedNonempty != nil }) else {
                throw ResearchWorkflowContractError.invalid(
                    "Audit scopes cannot contain empty values."
                )
            }
            for evidence in marker.evidenceRevisions {
                try validate(fingerprint: evidence)
            }
        }
        for audit in input.completedAudits {
            try validate(reference: audit.target, fingerprint: audit.fingerprint)
            guard !audit.auditScope.isEmpty,
                  audit.auditScope.allSatisfy({ $0.trimmedNonempty != nil }) else {
                throw ResearchWorkflowContractError.invalid(
                    "Completed audits require a nonempty audit scope."
                )
            }
            for evidence in audit.evidenceRevisions {
                try validate(fingerprint: evidence)
            }
        }
        let eligible = input.markers.filter { $0.substantive && $0.sourceMode != .audit }
        let ignored = input.markers.count - input.markers.filter { $0.sourceMode != .audit }.count
        var finalByTarget: [String: (phase: Int, index: Int, fingerprint: String)] = [:]
        for (index, marker) in eligible.enumerated() {
            let key = marker.target.identity
            let current = finalByTarget[key]
            if current == nil || marker.phase > current!.phase
                || (marker.phase == current!.phase && index > current!.index) {
                finalByTarget[key] = (marker.phase, index, marker.fingerprint.sha256)
            }
        }
        var seen: Set<AuditKey> = []
        let finalMarkers = eligible.filter { marker in
            finalByTarget[marker.target.identity]?.fingerprint == marker.fingerprint.sha256
        }.filter { marker in
            seen.insert(AuditKey(marker)).inserted
        }
        let completed = Set(input.completedAudits.map(AuditKey.init))
        var scheduled: [ResearchAuditJob] = []
        var reused: [ResearchAuditJob] = []
        for marker in finalMarkers {
            let job = ResearchAuditJob(marker: marker)
            if completed.contains(AuditKey(marker)) {
                reused.append(job)
            } else {
                scheduled.append(job)
            }
        }
        let ordering: (ResearchAuditJob, ResearchAuditJob) -> Bool = {
            if $0.target.identity != $1.target.identity {
                return $0.target.identity < $1.target.identity
            }
            return $0.auditScope.joined(separator: "\u{0}")
                < $1.auditScope.joined(separator: "\u{0}")
        }
        return ResearchAuditPlan(
            scheduled: scheduled.sorted(by: ordering),
            reused: reused.sorted(by: ordering),
            ignoredAuditPhaseMarkers: ignored
        )
    }

    private static func validate(
        reference: ResearchWorkflowObjectReference,
        fingerprint: DocumentFingerprint
    ) throws {
        guard reference.identifier.trimmedNonempty != nil else {
            throw ResearchWorkflowContractError.invalid(
                "Audit targets require a nonempty identifier."
            )
        }
        if let embedded = reference.fingerprint, embedded != fingerprint {
            throw ResearchWorkflowContractError.invalid(
                "An audit target fingerprint conflicts with its exact post-write fingerprint."
            )
        }
        try validate(fingerprint: fingerprint)
    }

    private static func validate(fingerprint: DocumentFingerprint) throws {
        guard fingerprint.sha256.range(
            of: #"^[0-9a-f]{64}$"#,
            options: .regularExpression
        ) != nil,
        fingerprint.byteCount >= 0 else {
            throw ResearchWorkflowContractError.invalid(
                "An audit fingerprint is malformed."
            )
        }
    }

    private struct AuditKey: Hashable {
        let targetIdentity: String
        let fingerprint: String
        let scope: [String]
        let evidence: [String]

        init(_ marker: ResearchAuditMarker) {
            targetIdentity = marker.target.identity
            fingerprint = marker.fingerprint.sha256
            scope = Self.normalizedScope(marker.auditScope)
            evidence = Self.normalizedEvidence(marker.evidenceRevisions)
        }

        init(_ audit: ResearchCompletedAudit) {
            targetIdentity = audit.target.identity
            fingerprint = audit.fingerprint.sha256
            scope = Self.normalizedScope(audit.auditScope)
            evidence = Self.normalizedEvidence(audit.evidenceRevisions)
        }

        private static func normalizedScope(_ values: [String]) -> [String] {
            Array(Set(values.compactMap(\.trimmedNonempty))).sorted()
        }

        private static func normalizedEvidence(
            _ values: [DocumentFingerprint]
        ) -> [String] {
            Array(Set(values.map(\.sha256))).sorted()
        }
    }
}

private extension String {
    var trimmedNonempty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
