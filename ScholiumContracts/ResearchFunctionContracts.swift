import Foundation

/// Stable semantic identifiers shared by the app, CLI, and Application layer.
/// User-facing labels and symbols remain presentation concerns.
public enum ResearchFunctionID: String, Codable, CaseIterable, Hashable, Sendable {
    case dialogue
    case develop
    case review
    case fidelity
    case critique
    case revise
    case manuscript

    public var delivery: ResearchFunctionDelivery {
        self == .review ? .humanReview : .externalAgent
    }

    public var requiresCheckpoint: Bool {
        switch self {
        case .develop, .critique, .revise, .manuscript: true
        case .dialogue, .review, .fidelity: false
        }
    }

    public var writesTarget: Bool {
        switch self {
        case .develop, .revise, .manuscript: true
        case .dialogue, .review, .fidelity, .critique: false
        }
    }

    public var requiresFinalFidelity: Bool {
        switch self {
        case .develop, .revise, .manuscript: true
        case .dialogue, .review, .fidelity, .critique: false
        }
    }

    public var allowedTargetRoles: Set<ResearchFunctionTargetRole> {
        switch self {
        case .develop, .review:
            [.analysis, .topic]
        case .critique, .revise, .manuscript:
            [.work]
        case .dialogue, .fidelity:
            Set(ResearchFunctionTargetRole.allCases)
        }
    }
}

public enum ResearchFunctionDelivery: String, Codable, Hashable, Sendable {
    case externalAgent = "external_agent"
    case humanReview = "human_review"
}

public enum ResearchFunctionTargetRole: String, Codable, CaseIterable, Hashable, Sendable {
    case analysis
    case topic
    case work

    public init?(vaultRole: VaultRole) {
        switch vaultRole {
        case .sourceCorpus: self = .analysis
        case .topicKnowledge: self = .topic
        case .draftProject: self = .work
        case .other: return nil
        }
    }

    public var vaultRoles: Set<VaultRole> {
        switch self {
        case .analysis: [.sourceCorpus]
        case .topic: [.topicKnowledge]
        case .work: [.draftProject]
        }
    }
}

/// One stable, fingerprint-bound document Target. The fingerprint is a
/// revision check, never an authorization token.
public struct ResearchFunctionTarget: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchFunctionTargetRole
    public let lifecycle: WorkspaceDocumentLifecycle
    public let fingerprint: DocumentFingerprint
    public let title: String

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        lifecycle: WorkspaceDocumentLifecycle = .active,
        fingerprint: DocumentFingerprint,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.role = role
        self.lifecycle = lifecycle
        self.fingerprint = fingerprint
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Read-only context selected inside a function panel. A Material is never an
/// implicit additional Target and carries its own revision identity.
public struct ResearchFunctionMaterial: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchFunctionTargetRole
    public let lifecycle: WorkspaceDocumentLifecycle
    public let fingerprint: DocumentFingerprint
    public let title: String

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        lifecycle: WorkspaceDocumentLifecycle = .active,
        fingerprint: DocumentFingerprint,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.role = role
        self.lifecycle = lifecycle
        self.fingerprint = fingerprint
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ResearchFunctionScopeKind: String, Codable, Hashable, Sendable {
    case whole
    case passage
}

/// Whole/Passage remains a delivery-neutral semantic choice. Passage scope
/// uses the same exact-source anchor as Comments and never stores rendered
/// text as writable authority.
public struct ResearchFunctionScope: Codable, Hashable, Sendable {
    public let kind: ResearchFunctionScopeKind
    public let selection: ResearcherCommentAnchor?

    public static let whole = Self(kind: .whole)

    public static func passage(_ selection: ResearcherCommentAnchor) -> Self {
        Self(kind: .passage, selection: selection)
    }

    public init(
        kind: ResearchFunctionScopeKind,
        selection: ResearcherCommentAnchor? = nil
    ) {
        self.kind = kind
        self.selection = selection
    }
}

public enum FidelityCheck: String, Codable, CaseIterable, Hashable, Sendable {
    case content
    case citations
}

/// Agent-selected conditional package resources. These values are semantic
/// choices in the function API, never Strip buttons or package identifiers.
public enum ResearchFunctionConditionalResource: String, Codable, CaseIterable, Hashable, Sendable {
    case developmentExploration = "development_exploration"
    case developmentSynthesis = "development_synthesis"
    case developmentExpression = "development_expression"
    case developmentDefinitionImpact = "development_definition_impact"
    case revisionFeedback = "revision_feedback"
    case revisionOutputContracts = "revision_output_contracts"
    case manuscriptGates = "manuscript_gates"

    public var kind: ResearchFunctionConditionalResourceKind {
        switch self {
        case .developmentExploration, .developmentSynthesis,
             .developmentExpression, .developmentDefinitionImpact:
            .method
        case .revisionFeedback:
            .method
        case .revisionOutputContracts:
            .template
        case .manuscriptGates:
            .checklist
        }
    }

    public var function: ResearchFunctionID {
        switch self {
        case .developmentExploration, .developmentSynthesis,
             .developmentExpression, .developmentDefinitionImpact:
            .develop
        case .revisionFeedback, .revisionOutputContracts:
            .revise
        case .manuscriptGates:
            .manuscript
        }
    }
}

public enum ResearchFunctionConditionalResourceKind: String, Codable, Hashable, Sendable {
    case method
    case template
    case checklist
}

public extension ResearchFunctionID {
    /// Conditional method references available to an external agent after it
    /// has inspected the fixed Target and read-only Materials. An empty
    /// selection still applies the complete primary method; these values are
    /// not an exhaustive taxonomy of philosophical activity.
    var conditionalResources: [ResearchFunctionConditionalResource] {
        ResearchFunctionConditionalResource.allCases.filter {
            $0.function == self
        }
    }

}

public enum ResearchSkillCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case citationVerification = "citation-verification"
    case citationFormatting = "citation-formatting"
    case bibliographyRecommendation = "bibliography-recommendation"
}

public enum ResearchFunctionRepairReasonCode: String, Codable, Hashable, Sendable {
    case targetUnavailable = "target_unavailable"
    case targetChanged = "target_changed"
    case targetIdentityChanged = "target_identity_changed"
    case invalidTargetRole = "invalid_target_role"
    case inactiveTarget = "inactive_target"
    case missingWorkflow = "missing_workflow"
    case invalidWorkflow = "invalid_workflow"
    case missingCapability = "missing_capability"
    case malformedBinding = "malformed_binding"
    case humanReviewOnly = "human_review_only"
}

/// A localization-free repair code. Optional associated values identify the
/// semantic requirement without embedding interface prose in Contracts.
public struct ResearchFunctionRepairReason: Codable, Hashable, Sendable {
    public let code: ResearchFunctionRepairReasonCode
    public let function: ResearchFunctionID?
    public let expectedRoles: [ResearchFunctionTargetRole]
    public let capability: ResearchSkillCapability?
    public let packageID: String?

    public init(
        code: ResearchFunctionRepairReasonCode,
        function: ResearchFunctionID? = nil,
        expectedRoles: [ResearchFunctionTargetRole] = [],
        capability: ResearchSkillCapability? = nil,
        packageID: String? = nil
    ) {
        self.code = code
        self.function = function
        self.expectedRoles = Array(Set(expectedRoles)).sorted { $0.rawValue < $1.rawValue }
        self.capability = capability
        self.packageID = packageID
    }
}

public struct ResearchFunctionCheckAvailability: Codable, Hashable, Sendable {
    public let check: FidelityCheck
    public let isEnabled: Bool
    public let repairReasons: [ResearchFunctionRepairReason]

    public init(
        check: FidelityCheck,
        isEnabled: Bool,
        repairReasons: [ResearchFunctionRepairReason] = []
    ) {
        self.check = check
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
    }
}

public struct ResearchFunctionAvailability: Codable, Hashable, Identifiable, Sendable {
    public let function: ResearchFunctionID
    public let delivery: ResearchFunctionDelivery
    public let isEnabled: Bool
    public let repairReasons: [ResearchFunctionRepairReason]
    public let fidelityChecks: [ResearchFunctionCheckAvailability]

    public var id: ResearchFunctionID { function }

    public init(
        function: ResearchFunctionID,
        delivery: ResearchFunctionDelivery? = nil,
        isEnabled: Bool,
        repairReasons: [ResearchFunctionRepairReason] = [],
        fidelityChecks: [ResearchFunctionCheckAvailability] = []
    ) {
        self.function = function
        self.delivery = delivery ?? function.delivery
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
        self.fidelityChecks = fidelityChecks
    }
}

/// A deterministic, explicitly sourced reason that one read-only note may be
/// useful as Material. Suggestions are navigation aids only: they never imply
/// evidential support, authorize retrieval, or select the note automatically.
public struct ResearchFunctionMaterialSuggestionReason: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case linkedFromSelectedPassage = "linked_from_selected_passage"
        case linkedFromTarget = "linked_from_target"
        case linksDirectlyToTarget = "links_directly_to_target"

        public var precedence: Int {
            switch self {
            case .linkedFromSelectedPassage: 0
            case .linkedFromTarget: 1
            case .linksDirectlyToTarget: 2
            }
        }
    }

    public let kind: Kind
    /// The note containing the exact, resolved one-hop link occurrence.
    public let sourceNote: VaultQualifiedNoteID
    public let sourceSpan: SourceSpan

    public init(
        kind: Kind,
        sourceNote: VaultQualifiedNoteID,
        sourceSpan: SourceSpan
    ) {
        self.kind = kind
        self.sourceNote = sourceNote
        self.sourceSpan = sourceSpan
    }
}

public struct ResearchFunctionMaterialCandidate: Codable, Hashable, Identifiable, Sendable {
    public let material: ResearchFunctionMaterial
    /// Search-only aliases projected from the current catalog. They do not
    /// enter a prepared request or become authoritative Material identity.
    public let aliases: [String]
    public let suggestionReasons: [ResearchFunctionMaterialSuggestionReason]
    public let isSelectable: Bool
    public let repairReasons: [ResearchFunctionRepairReason]

    public var id: UUID { material.id }

    public init(
        material: ResearchFunctionMaterial,
        aliases: [String] = [],
        suggestionReasons: [ResearchFunctionMaterialSuggestionReason] = [],
        isSelectable: Bool = true,
        repairReasons: [ResearchFunctionRepairReason] = []
    ) {
        self.material = material
        self.aliases = Array(Set(aliases.compactMap { alias in
            let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        })).sorted {
            let comparison = $0.localizedStandardCompare($1)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0 < $1
        }
        self.suggestionReasons = Array(Set(suggestionReasons)).sorted {
            if $0.kind.precedence != $1.kind.precedence {
                return $0.kind.precedence < $1.kind.precedence
            }
            if $0.sourceNote != $1.sourceNote {
                return $0.sourceNote < $1.sourceNote
            }
            if $0.sourceSpan.utf16LowerBound != $1.sourceSpan.utf16LowerBound {
                return $0.sourceSpan.utf16LowerBound < $1.sourceSpan.utf16LowerBound
            }
            return $0.sourceSpan.utf16UpperBound < $1.sourceSpan.utf16UpperBound
        }
        self.isSelectable = isSelectable
        self.repairReasons = repairReasons
    }

}

public struct ResearchFunctionRequest: Codable, Hashable, Sendable {
    public let function: ResearchFunctionID
    public let target: ResearchFunctionTarget
    public let materials: [ResearchFunctionMaterial]
    public let instruction: String?
    public let scope: ResearchFunctionScope?
    public let checks: Set<FidelityCheck>
    public let commentIDs: [UUID]
    public let conditionalResources: Set<ResearchFunctionConditionalResource>?
    /// Optional request-scoped presentation modules for Dialogue.
    ///
    /// Nil inherits the current Triptych default at preparation time. An
    /// explicit empty array requests only the required Academic Outcome.
    /// Values remain ordered by `DialogueResponseModule.allCases` so App and
    /// CLI encoders produce one stable wire representation.
    public let dialogueResponseModules: [DialogueResponseModule]?

    public init(
        function: ResearchFunctionID,
        target: ResearchFunctionTarget,
        materials: [ResearchFunctionMaterial] = [],
        instruction: String? = nil,
        scope: ResearchFunctionScope? = nil,
        checks: Set<FidelityCheck> = [],
        commentIDs: [UUID] = [],
        conditionalResources: Set<ResearchFunctionConditionalResource>? = nil,
        dialogueResponseModules: [DialogueResponseModule]? = nil
    ) {
        self.function = function
        self.target = target
        self.materials = materials
        let normalized = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instruction = normalized?.isEmpty == false ? normalized : nil
        self.scope = scope
        self.checks = checks
        self.commentIDs = commentIDs
        self.conditionalResources = conditionalResources
        self.dialogueResponseModules = dialogueResponseModules.map { modules in
            modules.sorted { lhs, rhs in
                let lhsIndex = DialogueResponseModule.allCases.firstIndex(of: lhs) ?? 0
                let rhsIndex = DialogueResponseModule.allCases.firstIndex(of: rhs) ?? 0
                return lhsIndex < rhsIndex
            }
        }
    }

    /// Nil is a deliberate preflight state for functions with conditional
    /// method references. An explicit empty set finalizes the run with the
    /// complete primary method and no conditional reference.
    public var awaitsResourceSelection: Bool {
        conditionalResources == nil && !function.conditionalResources.isEmpty
    }

    public func selectingResources(
        _ resources: Set<ResearchFunctionConditionalResource>
    ) throws -> ResearchFunctionRequest {
        let selected = ResearchFunctionRequest(
            function: function,
            target: target,
            materials: materials,
            instruction: instruction,
            scope: scope,
            checks: checks,
            commentIDs: commentIDs,
            conditionalResources: resources,
            dialogueResponseModules: dialogueResponseModules
        )
        try selected.validate()
        return selected
    }

    public func validate() throws {
        guard target.lifecycle == .active else {
            throw ResearchFunctionContractError.inactiveTarget
        }
        guard function.allowedTargetRoles.contains(target.role) else {
            throw ResearchFunctionContractError.invalidTargetRole(
                function: function,
                role: target.role
            )
        }
        guard !target.title.isEmpty else {
            throw ResearchFunctionContractError.emptyTargetTitle
        }
        let materialIDs = materials.map(\.noteID)
        guard Set(materialIDs).count == materialIDs.count else {
            throw ResearchFunctionContractError.duplicateMaterial
        }
        guard !materials.contains(where: {
            $0.noteID == target.noteID || $0.note == target.note
        }) else {
            throw ResearchFunctionContractError.targetRepeatedAsMaterial
        }
        guard materials.allSatisfy({ $0.lifecycle == .active && !$0.title.isEmpty }) else {
            throw ResearchFunctionContractError.inactiveMaterial
        }
        guard Set(commentIDs).count == commentIDs.count else {
            throw ResearchFunctionContractError.duplicateComment
        }
        guard (conditionalResources ?? []).allSatisfy({
            $0.function == function
        }) else {
            throw ResearchFunctionContractError.invalidMethodSelection
        }
        if function == .dialogue {
            if let dialogueResponseModules,
               Set(dialogueResponseModules).count != dialogueResponseModules.count {
                throw ResearchFunctionContractError.duplicateDialogueResponseModule
            }
        } else if dialogueResponseModules != nil {
            throw ResearchFunctionContractError.unexpectedDialogueResponseModules
        }
        if let scope {
            switch scope.kind {
            case .whole:
                guard scope.selection == nil else {
                    throw ResearchFunctionContractError.invalidScope
                }
            case .passage:
                guard let selection = scope.selection,
                      selection.fingerprint == target.fingerprint else {
                    throw ResearchFunctionContractError.invalidScope
                }
            }
        }
        if function == .fidelity {
            guard !checks.isEmpty else {
                throw ResearchFunctionContractError.missingFidelityCheck
            }
        } else if !checks.isEmpty {
            throw ResearchFunctionContractError.unexpectedFidelityCheck
        }
        if function == .dialogue, instruction == nil {
            throw ResearchFunctionContractError.emptyInstruction(function)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case function, target, materials, instruction, scope, checks, commentIDs
        case conditionalResources = "conditional_resources"
        case dialogueResponseModules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            function: try container.decode(ResearchFunctionID.self, forKey: .function),
            target: try container.decode(ResearchFunctionTarget.self, forKey: .target),
            materials: try container.decodeIfPresent(
                [ResearchFunctionMaterial].self,
                forKey: .materials
            ) ?? [],
            instruction: try container.decodeIfPresent(String.self, forKey: .instruction),
            scope: try container.decodeIfPresent(ResearchFunctionScope.self, forKey: .scope),
            checks: try container.decodeIfPresent(Set<FidelityCheck>.self, forKey: .checks) ?? [],
            commentIDs: try container.decodeIfPresent([UUID].self, forKey: .commentIDs) ?? [],
            conditionalResources: try container.decodeIfPresent(
                Set<ResearchFunctionConditionalResource>.self,
                forKey: .conditionalResources
            ),
            dialogueResponseModules: try container.decodeIfPresent(
                [DialogueResponseModule].self,
                forKey: .dialogueResponseModules
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(function, forKey: .function)
        try container.encode(target, forKey: .target)
        if !materials.isEmpty { try container.encode(materials, forKey: .materials) }
        try container.encodeIfPresent(instruction, forKey: .instruction)
        try container.encodeIfPresent(scope, forKey: .scope)
        if !checks.isEmpty { try container.encode(checks, forKey: .checks) }
        if !commentIDs.isEmpty { try container.encode(commentIDs, forKey: .commentIDs) }
        try container.encodeIfPresent(conditionalResources, forKey: .conditionalResources)
        try container.encodeIfPresent(dialogueResponseModules, forKey: .dialogueResponseModules)
    }
}

/// Agent-side finalization of a method-unresolved preflight. Interface
/// launchers never construct this value or expose its semantic method
/// references as interface modes.
public struct ResearchFunctionResourceSelectionSubmission: Codable, Hashable, Sendable {
    public let runID: UUID
    public let confirmationToken: UUID
    public let resources: Set<ResearchFunctionConditionalResource>

    public init(
        runID: UUID,
        confirmationToken: UUID,
        resources: Set<ResearchFunctionConditionalResource>
    ) {
        self.runID = runID
        self.confirmationToken = confirmationToken
        self.resources = resources
    }

    private enum CodingKeys: String, CodingKey {
        case runID, confirmationToken, resources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            runID: try container.decode(UUID.self, forKey: .runID),
            confirmationToken: try container.decode(UUID.self, forKey: .confirmationToken),
            resources: try container.decode(
                Set<ResearchFunctionConditionalResource>.self,
                forKey: .resources
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runID, forKey: .runID)
        try container.encode(confirmationToken, forKey: .confirmationToken)
        try container.encode(resources, forKey: .resources)
    }
}

public struct ResearchFunctionResourceSnapshot: Codable, Hashable, Sendable {
    public let relativePath: String
    public let revision: DocumentFingerprint

    public init(relativePath: String, revision: DocumentFingerprint) {
        self.relativePath = relativePath
        self.revision = revision
    }
}

public struct ResearchFunctionSkillSnapshot: Codable, Hashable, Sendable {
    public let packageID: String
    public let origin: ResearchSkillOrigin
    public let version: String
    public let packageRevision: DocumentFingerprint
    public let loadedResources: [ResearchFunctionResourceSnapshot]

    public init(
        packageID: String,
        origin: ResearchSkillOrigin,
        version: String,
        packageRevision: DocumentFingerprint,
        loadedResources: [ResearchFunctionResourceSnapshot]
    ) {
        self.packageID = packageID
        self.origin = origin
        self.version = version
        self.packageRevision = packageRevision
        self.loadedResources = loadedResources
    }

    public init(_ selection: ResolvedResearchSkillSelection) {
        self.init(
            packageID: selection.id,
            origin: selection.origin,
            version: selection.version,
            packageRevision: selection.packageRevision,
            loadedResources: selection.loadedResources.map {
                ResearchFunctionResourceSnapshot(
                    relativePath: $0.relativePath,
                    revision: $0.revision
                )
            }
        )
    }
}

/// Phase-local resolution evidence. Manuscript coordination and mandatory
/// final Fidelity remain isolated even when one function-run envelope links
/// their outcomes.
public struct ResearchFunctionPhaseSnapshot: Codable, Hashable, Sendable {
    public let phase: Int
    public let function: ResearchFunctionID
    public let skills: [ResearchFunctionSkillSnapshot]
    /// The explicit Triptych citation-style binding applied to this isolated
    /// Fidelity phase. Nil for non-citation phases.
    public let citationStyle: String?

    public init(
        phase: Int,
        function: ResearchFunctionID,
        skills: [ResearchFunctionSkillSnapshot],
        citationStyle: String? = nil
    ) {
        self.phase = phase
        self.function = function
        self.skills = skills
        self.citationStyle = citationStyle
    }
}

public enum ResearchFunctionRecordKind: String, Codable, Hashable, Sendable {
    case dialogue
    case critique
    case functionEnvelope = "function_envelope"
    case humanReview = "human_review"
}

public enum ResearchFunctionRunState: String, Codable, Hashable, Sendable {
    case prepared
    case awaitingFidelity = "awaiting_fidelity"
    case complete
    case unverified
    case stale
    case cancelled
}

/// Provenance for a Fidelity run. Manual and automatic invocations use the
/// same exact-revision audit contract and evidence key; this value records how
/// the run was initiated, not whether an audit actually completed.
public enum FidelityInvocationKind: Codable, Hashable, Sendable {
    case manual
    case automatic(parentRunID: UUID)
}

public struct ResearchFunctionFidelityHandoff: Codable, Hashable, Sendable {
    public let required: Bool
    public let checks: Set<FidelityCheck>
    /// The revision from which the write-capable run began. This is provenance
    /// for the handoff, not the revision that Fidelity is authorized to audit.
    /// Final Fidelity must be prepared independently against the post-edit
    /// Target fingerprint.
    public let preparedTargetFingerprint: DocumentFingerprint

    public init(
        required: Bool,
        checks: Set<FidelityCheck>,
        preparedTargetFingerprint: DocumentFingerprint
    ) {
        self.required = required
        self.checks = checks
        self.preparedTargetFingerprint = preparedTargetFingerprint
    }
}

public struct ResearchFunctionOutputSnapshot: Codable, Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let fingerprint: DocumentFingerprint

    public init(note: VaultQualifiedNoteID, fingerprint: DocumentFingerprint) {
        self.note = note
        self.fingerprint = fingerprint
    }
}

/// Immutable request-time evidence embedded in an existing Dialogue or
/// Critique record. It records only resources actually resolved for the run.
public struct ResearchFunctionSnapshot: Codable, Hashable, Sendable {
    public let runID: UUID
    public let request: ResearchFunctionRequest
    public let recordKind: ResearchFunctionRecordKind
    public let recordID: UUID?
    public let checkpointID: UUID?
    public let skills: [ResearchFunctionSkillSnapshot]
    public let phases: [ResearchFunctionPhaseSnapshot]
    /// Functions coordinated through independent child runs. Manuscript uses
    /// this for its selected phases; write-capable functions use it for their
    /// final-fingerprint Fidelity handoff. Each child retains its own
    /// permission, checkpoint, record, and completion evidence.
    public let requiredChildFunctions: [ResearchFunctionID]
    /// Separate writable evidential record prepared for a read-only Target,
    /// currently used by Critique.
    public let preparedOutput: ResearchFunctionOutputSnapshot?
    /// Request-time revisions of selected Comments or other structured
    /// evidence whose identifiers alone do not change when their content is
    /// edited.
    public let evidenceRevisions: [DocumentFingerprint]
    public let fidelityHandoff: ResearchFunctionFidelityHandoff?
    /// Present only for Fidelity runs.
    public let fidelityInvocation: FidelityInvocationKind?
    public let confirmationToken: UUID
    public let preparedAt: Date

    public init(
        runID: UUID = UUID(),
        request: ResearchFunctionRequest,
        recordKind: ResearchFunctionRecordKind,
        recordID: UUID? = nil,
        checkpointID: UUID? = nil,
        skills: [ResearchFunctionSkillSnapshot] = [],
        phases: [ResearchFunctionPhaseSnapshot] = [],
        requiredChildFunctions: [ResearchFunctionID] = [],
        preparedOutput: ResearchFunctionOutputSnapshot? = nil,
        evidenceRevisions: [DocumentFingerprint] = [],
        fidelityHandoff: ResearchFunctionFidelityHandoff? = nil,
        fidelityInvocation: FidelityInvocationKind? = nil,
        confirmationToken: UUID = UUID(),
        preparedAt: Date = Date()
    ) {
        self.runID = runID
        self.request = request
        self.recordKind = recordKind
        self.recordID = recordID
        self.checkpointID = checkpointID
        self.skills = skills
        self.phases = phases
        self.requiredChildFunctions = Array(Set(requiredChildFunctions)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.preparedOutput = preparedOutput
        self.evidenceRevisions = evidenceRevisions
        self.fidelityHandoff = fidelityHandoff
        self.fidelityInvocation = request.function == .fidelity
            ? (fidelityInvocation ?? .manual)
            : nil
        self.confirmationToken = confirmationToken
        self.preparedAt = preparedAt
    }

    public var resolvedFidelityInvocation: FidelityInvocationKind? {
        guard request.function == .fidelity else { return nil }
        return fidelityInvocation
    }
}

public struct ResearchFunctionPreparation: Codable, Hashable, Sendable {
    public let snapshot: ResearchFunctionSnapshot
    public let instructions: String
    public let state: ResearchFunctionRunState
    public let reusedCompletion: ResearchFunctionCompletion?
    /// The authoritative preparation committed, but a disposable workspace
    /// projection did not refresh. Callers must retain this preparation and
    /// retry only refresh, never the function mutation.
    public let derivedRefreshWarning: String?
    public let nextActions: [AgentCommandAction]?

    public var runID: UUID { snapshot.runID }
    public var awaitsResourceSelection: Bool { snapshot.request.awaitsResourceSelection }

    public init(
        snapshot: ResearchFunctionSnapshot,
        instructions: String,
        state: ResearchFunctionRunState = .prepared,
        reusedCompletion: ResearchFunctionCompletion? = nil,
        derivedRefreshWarning: String? = nil,
        nextActions: [AgentCommandAction] = []
    ) {
        self.snapshot = snapshot
        self.instructions = instructions
        self.state = state
        self.reusedCompletion = reusedCompletion
        self.derivedRefreshWarning = derivedRefreshWarning
        self.nextActions = nextActions.isEmpty ? nil : nextActions
    }
}

/// Explicit orchestration state returned when Application prepares the
/// required post-edit Fidelity child for a Develop or Revise run. A prepared
/// child is still pending agent work; only `state == .complete` with a durable
/// completion records finished audit evidence.
public struct AutomaticFidelityPreparation: Codable, Hashable, Sendable {
    public let parentRunID: UUID
    public let preparation: ResearchFunctionPreparation
    public let nextActions: [AgentCommandAction]?

    public init(
        parentRunID: UUID,
        preparation: ResearchFunctionPreparation,
        nextActions: [AgentCommandAction] = []
    ) {
        self.parentRunID = parentRunID
        self.preparation = preparation
        self.nextActions = nextActions.isEmpty ? nil : nextActions
    }

    public var state: ResearchFunctionRunState { preparation.state }
    public var effectiveFidelityRunID: UUID {
        preparation.reusedCompletion?.runID ?? preparation.runID
    }
    public var reusedExistingEvidence: Bool {
        preparation.reusedCompletion != nil
    }
}

public enum FidelityCheckOutcomeState: String, Codable, Hashable, Sendable {
    case passed
    case issuesFound = "issues_found"
    case unavailable
}

public struct FidelityCheckOutcome: Codable, Hashable, Sendable {
    public let check: FidelityCheck
    public let state: FidelityCheckOutcomeState
    public let summary: String
    public let findings: [String]

    public init(
        check: FidelityCheck,
        state: FidelityCheckOutcomeState,
        summary: String,
        findings: [String] = []
    ) {
        self.check = check
        self.state = state
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.findings = findings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func validate() throws {
        guard !summary.isEmpty else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Every Fidelity outcome requires an attributed summary."
            )
        }
        switch state {
        case .passed:
            guard findings.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "A passed Fidelity check cannot also report unresolved findings."
                )
            }
        case .issuesFound:
            guard !findings.isEmpty else {
                throw ResearchFunctionContractError.invalidCompletion(
                    "An issues-found Fidelity outcome requires at least one finding."
                )
            }
        case .unavailable:
            break
        }
    }
}

public struct ResearchFunctionCompletionSubmission: Codable, Hashable, Sendable {
    public let runID: UUID
    public let confirmationToken: UUID
    public let finalTargetFingerprint: DocumentFingerprint
    public let finalMaterialFingerprints: [UUID: DocumentFingerprint]
    public let summary: String
    public let didModifyTarget: Bool
    public let outputFingerprint: DocumentFingerprint?
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let submittedAt: Date
    public let childRunIDs: [UUID]?

    public init(
        runID: UUID,
        confirmationToken: UUID,
        finalTargetFingerprint: DocumentFingerprint,
        finalMaterialFingerprints: [UUID: DocumentFingerprint] = [:],
        summary: String,
        didModifyTarget: Bool,
        outputFingerprint: DocumentFingerprint? = nil,
        fidelityOutcomes: [FidelityCheckOutcome] = [],
        childRunIDs: [UUID] = [],
        submittedAt: Date = Date()
    ) {
        self.runID = runID
        self.confirmationToken = confirmationToken
        self.finalTargetFingerprint = finalTargetFingerprint
        self.finalMaterialFingerprints = finalMaterialFingerprints
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.didModifyTarget = didModifyTarget
        self.outputFingerprint = outputFingerprint
        self.fidelityOutcomes = fidelityOutcomes
        self.childRunIDs = childRunIDs.isEmpty ? nil : childRunIDs
        self.submittedAt = submittedAt
    }
}

/// Durable completion evidence. Fidelity remains attributed structured output,
/// not a hidden app judgment or a replacement for Human Review or Critique.
public struct ResearchFunctionCompletion: Codable, Hashable, Sendable {
    public let runID: UUID
    public let function: ResearchFunctionID
    public let state: ResearchFunctionRunState
    public let targetFingerprint: DocumentFingerprint
    public let materialFingerprints: [UUID: DocumentFingerprint]
    public let summary: String
    public let didModifyTarget: Bool
    public let outputFingerprint: DocumentFingerprint?
    public let fidelityOutcomes: [FidelityCheckOutcome]
    /// Deterministic identity of the exact final revision, evidence, checks,
    /// and resolved skill resources audited by this completion.
    public let fidelityEvidenceKey: ResearchFidelityEvidenceKey?
    /// When non-nil, this run reused already-completed Fidelity evidence
    /// instead of persisting a duplicate audit result.
    public let reusedFidelityRunID: UUID?
    public let childRunIDs: [UUID]?
    public let completedAt: Date
    /// A committed completion can carry a recoverable derived-refresh warning.
    /// It is not a failed or repeatable scholarly operation.
    public let derivedRefreshWarning: String?
    public let nextActions: [AgentCommandAction]?

    public init(
        runID: UUID,
        function: ResearchFunctionID,
        state: ResearchFunctionRunState,
        targetFingerprint: DocumentFingerprint,
        materialFingerprints: [UUID: DocumentFingerprint],
        summary: String,
        didModifyTarget: Bool,
        outputFingerprint: DocumentFingerprint? = nil,
        fidelityOutcomes: [FidelityCheckOutcome],
        fidelityEvidenceKey: ResearchFidelityEvidenceKey? = nil,
        reusedFidelityRunID: UUID? = nil,
        childRunIDs: [UUID] = [],
        completedAt: Date = Date(),
        derivedRefreshWarning: String? = nil,
        nextActions: [AgentCommandAction] = []
    ) {
        self.runID = runID
        self.function = function
        self.state = state
        self.targetFingerprint = targetFingerprint
        self.materialFingerprints = materialFingerprints
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.didModifyTarget = didModifyTarget
        self.outputFingerprint = outputFingerprint
        self.fidelityOutcomes = fidelityOutcomes
        self.fidelityEvidenceKey = fidelityEvidenceKey
        self.reusedFidelityRunID = reusedFidelityRunID
        self.childRunIDs = childRunIDs.isEmpty ? nil : childRunIDs
        self.completedAt = completedAt
        self.derivedRefreshWarning = derivedRefreshWarning
        self.nextActions = nextActions.isEmpty ? nil : nextActions
    }
}

/// A stable audit key. A changed Target, Material/evidence revision, check
/// selection, package revision, or loaded resource revision creates a new key
/// and therefore cannot silently reuse stale Fidelity evidence.
public struct ResearchFidelityEvidenceKey: Codable, Hashable, Sendable {
    public let revision: DocumentFingerprint

    public init(
        snapshot: ResearchFunctionSnapshot,
        finalTargetFingerprint: DocumentFingerprint,
        finalMaterialFingerprints: [UUID: DocumentFingerprint],
        checks: Set<FidelityCheck>
    ) {
        var lines = [
            "target-id:\(snapshot.request.target.noteID.uuidString.lowercased())",
            "target-sha256:\(finalTargetFingerprint.sha256)",
            "target-bytes:\(finalTargetFingerprint.byteCount)",
        ]
        for (id, fingerprint) in finalMaterialFingerprints.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            lines.append(
                "material:\(id.uuidString.lowercased()):\(fingerprint.sha256):\(fingerprint.byteCount)"
            )
        }
        for check in checks.sorted(by: { $0.rawValue < $1.rawValue }) {
            lines.append("check:\(check.rawValue)")
        }
        if let scope = snapshot.request.scope, scope.kind == .passage {
            lines.append("scope:passage")
            if let anchor = scope.selection {
                lines.append("scope-fingerprint:\(anchor.fingerprint.sha256)")
                lines.append("scope-utf8:\(anchor.utf8Range.lowerBound):\(anchor.utf8Range.upperBound)")
                lines.append("scope-utf16:\(anchor.utf16Range.lowerBound):\(anchor.utf16Range.upperBound)")
                lines.append("scope-lines:\(anchor.line):\(anchor.endLine)")
                lines.append("scope-quotation:\(anchor.quotation)")
                lines.append("scope-selected:\(anchor.selectedText ?? "")")
                lines.append("scope-before:\(anchor.contextBefore)")
                lines.append("scope-after:\(anchor.contextAfter)")
                lines.append("scope-state:\(anchor.state.rawValue)")
            }
        } else {
            // An omitted scope and an explicit Whole scope have identical
            // semantics. Keep their audit identity identical so delivery
            // adapters cannot schedule duplicate Fidelity work merely by
            // choosing a different Codable spelling for the default.
            lines.append("scope:whole")
        }
        for id in snapshot.request.commentIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            lines.append("comment:\(id.uuidString.lowercased())")
        }
        for revision in snapshot.evidenceRevisions.sorted(by: {
            if $0.sha256 != $1.sha256 { return $0.sha256 < $1.sha256 }
            return $0.byteCount < $1.byteCount
        }) {
            lines.append("evidence:\(revision.sha256):\(revision.byteCount)")
        }
        let fidelityPhaseSkills = snapshot.phases
            .filter { $0.function == .fidelity }
            .flatMap(\.skills)
        for style in snapshot.phases
            .filter({ $0.function == .fidelity })
            .compactMap(\.citationStyle)
            .sorted() {
            lines.append("citation-style:\(style)")
        }
        let auditSkills = fidelityPhaseSkills.isEmpty ? snapshot.skills : fidelityPhaseSkills
        for skill in auditSkills.sorted(by: { $0.packageID < $1.packageID }) {
            lines.append(
                "skill:\(skill.packageID):\(skill.packageRevision.sha256):\(skill.packageRevision.byteCount)"
            )
            for resource in skill.loadedResources.sorted(by: {
                $0.relativePath < $1.relativePath
            }) {
                lines.append(
                    "resource:\(skill.packageID):\(resource.relativePath):\(resource.revision.sha256):\(resource.revision.byteCount)"
                )
            }
        }
        revision = DocumentFingerprint(content: lines.joined(separator: "\n"))
    }
}

/// Read-only record projection kept separate from Dialogue, Critique, Human
/// Review, Comments, and Fidelity findings even when storage is shared.
public struct ResearchFunctionRecordProjection: Codable, Hashable, Identifiable, Sendable {
    public let snapshot: ResearchFunctionSnapshot
    public let completion: ResearchFunctionCompletion?
    /// Exact agent handoff persisted for the run. A method-unresolved
    /// preflight may be replaced once by its finalized immutable execution
    /// packet; unresolved preflight records may omit it.
    public let preparedInstructions: String?

    public var id: UUID { snapshot.runID }

    public init(
        snapshot: ResearchFunctionSnapshot,
        completion: ResearchFunctionCompletion? = nil,
        preparedInstructions: String? = nil
    ) {
        self.snapshot = snapshot
        self.completion = completion
        let normalized = preparedInstructions?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.preparedInstructions = normalized?.isEmpty == false ? normalized : nil
    }
}

public enum ResearchFunctionContractError: LocalizedError, Sendable {
    case targetUnavailable
    case targetChanged
    case targetIdentityChanged
    case inactiveTarget
    case invalidTargetRole(function: ResearchFunctionID, role: ResearchFunctionTargetRole)
    case emptyTargetTitle
    case duplicateMaterial
    case targetRepeatedAsMaterial
    case inactiveMaterial
    case materialChanged(String)
    case duplicateComment
    case invalidScope
    case missingFidelityCheck
    case unexpectedFidelityCheck
    case invalidMethodSelection
    case duplicateDialogueResponseModule
    case unexpectedDialogueResponseModules
    case methodSelectionNotRequired(ResearchFunctionID)
    case methodSelectionAlreadyResolved(UUID)
    case methodSelectionRequired(UUID)
    case missingCapability(ResearchSkillCapability)
    case emptyInstruction(ResearchFunctionID)
    case humanReviewMustUseRecordAPI
    case preparationNotFound(UUID)
    case confirmationMismatch
    case completionAlreadyRecorded(UUID)
    case invalidCompletion(String)
    case cancellationAfterCompletion(UUID)

    public var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The Research Function Target is not available in the current Triptych generation."
        case .targetChanged:
            "The Research Function Target changed after the panel captured it. Reload the current note before continuing."
        case .targetIdentityChanged:
            "The Research Function Target no longer has the same stable identity."
        case .inactiveTarget:
            "A Research Function requires an active Target, not a set-aside or trashed note."
        case .invalidTargetRole(let function, let role):
            "The \(function.rawValue) function is not available for a \(role.rawValue) Target."
        case .emptyTargetTitle:
            "The Research Function Target must have a nonempty title projection."
        case .duplicateMaterial:
            "Each Research Function Material may be selected only once."
        case .targetRepeatedAsMaterial:
            "The Research Function Target cannot also be selected as Material."
        case .inactiveMaterial:
            "Research Function Materials must be active, identified notes."
        case .materialChanged(let title):
            "The Material '\(title)' changed while the Research Function was being prepared."
        case .duplicateComment:
            "Each Comment may be selected only once."
        case .invalidScope:
            "Passage scope requires a selection from the exact Target revision; Whole scope has no selection."
        case .missingFidelityCheck:
            "Fidelity requires Content, Citations, or both."
        case .unexpectedFidelityCheck:
            "Fidelity checks belong only to the Fidelity function."
        case .invalidMethodSelection:
            "A selected internal method does not belong to this Research Function."
        case .duplicateDialogueResponseModule:
            "Each optional Dialogue response module may be selected only once."
        case .unexpectedDialogueResponseModules:
            "Dialogue response modules belong only to the Dialogue function."
        case .methodSelectionNotRequired(let function):
            "The \(function.rawValue) function has no pending conditional method selection."
        case .methodSelectionAlreadyResolved(let id):
            "Research Function methods are already finalized for run \(id.uuidString)."
        case .methodSelectionRequired(let id):
            "Select the conditional methods, including an explicit empty selection when the primary method is sufficient, before completing run \(id.uuidString)."
        case .missingCapability(let capability):
            "The Triptych has no active Researcher Skill for \(capability.rawValue)."
        case .emptyInstruction(let function):
            "The \(function.rawValue) function requires a researcher instruction."
        case .humanReviewMustUseRecordAPI:
            "Review is completed through the Human Review record API, not external-agent preparation."
        case .preparationNotFound(let id):
            "Research Function preparation not found: \(id.uuidString)"
        case .confirmationMismatch:
            "The completion does not match the prepared Research Function run."
        case .completionAlreadyRecorded(let id):
            "Research Function completion is already recorded: \(id.uuidString)"
        case .invalidCompletion(let reason):
            "The Research Function completion is invalid. \(reason)"
        case .cancellationAfterCompletion(let id):
            "A completed Research Function run cannot be cancelled: \(id.uuidString)"
        }
    }
}
