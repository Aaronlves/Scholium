import Foundation

/// Stable semantic identifiers shared by the app, CLI, and Application layer.
/// User-facing labels and symbols remain presentation concerns.
public enum ResearchFunctionID: String, Codable, CaseIterable, Hashable, Sendable {
    case discuss
    case develop
    case fidelity
    case critique
    case revise
    case manuscript

    public var delivery: ResearchFunctionDelivery {
        .externalAgent
    }

    public var requiresAgentChangeEvidence: Bool {
        switch self {
        case .develop, .revise: true
        case .discuss, .fidelity, .critique, .manuscript: false
        }
    }

    public var writesTarget: Bool {
        switch self {
        case .develop, .revise: true
        case .discuss, .fidelity, .critique, .manuscript: false
        }
    }

    public var requiresFinalFidelity: Bool {
        switch self {
        case .develop, .revise, .manuscript: true
        case .discuss, .fidelity, .critique: false
        }
    }

    public var allowedTargetRoles: Set<ResearchFunctionTargetRole> {
        switch self {
        case .develop:
            [.analysis, .topic]
        case .critique, .revise, .manuscript:
            [.work]
        case .discuss, .fidelity:
            Set(ResearchFunctionTargetRole.allCases)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let function = Self(rawValue: value) {
            self = function
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Research Function: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ResearchFunctionDelivery: String, Codable, Hashable, Sendable {
    case externalAgent = "external_agent"
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
    public let selection: CommentAnchor?

    public static let whole = Self(kind: .whole)

    public static func passage(_ selection: CommentAnchor) -> Self {
        Self(kind: .passage, selection: selection)
    }

    public init(
        kind: ResearchFunctionScopeKind,
        selection: CommentAnchor? = nil
    ) {
        self.kind = kind
        self.selection = selection
    }
}

public enum FidelityCheck: String, Codable, CaseIterable, Hashable, Sendable {
    case content
    case citations
}

/// Decode-compatible identifiers from the retired conditional Method
/// selector. Current Actions expose no resource-choice phase and reject every
/// nonempty selection; these cases remain only for old machine-local payloads.
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
    /// The split bundled Methods are complete and adaptive. Legacy conditional
    /// resource values remain decodable for old machine-local records, but no
    /// current Function exposes them as a researcher or agent mode selector.
    var conditionalResources: [ResearchFunctionConditionalResource] {
        []
    }

}

public enum ResearchFunctionRepairReasonCode: String, Codable, Hashable, Sendable {
    case targetUnavailable = "target_unavailable"
    case targetChanged = "target_changed"
    case targetIdentityChanged = "target_identity_changed"
    case invalidTargetRole = "invalid_target_role"
    case inactiveTarget = "inactive_target"
    case missingWorkflow = "missing_workflow"
    case invalidWorkflow = "invalid_workflow"
    case citationStyleUnavailable = "citation_style_unavailable"
    case malformedBinding = "malformed_binding"
    case sourceAccessRequired = "source_access_required"
}

/// A localization-free repair code. Optional associated values identify the
/// semantic requirement without embedding interface prose in Contracts.
public struct ResearchFunctionRepairReason: Codable, Hashable, Sendable {
    public let code: ResearchFunctionRepairReasonCode
    public let function: ResearchFunctionID?
    public let expectedRoles: [ResearchFunctionTargetRole]
    public let sourceAccessFailure: ResearchSourceAccessFailure?

    public init(
        code: ResearchFunctionRepairReasonCode,
        function: ResearchFunctionID? = nil,
        expectedRoles: [ResearchFunctionTargetRole] = [],
        sourceAccessFailure: ResearchSourceAccessFailure? = nil
    ) {
        self.code = code
        self.function = function
        self.expectedRoles = Array(Set(expectedRoles)).sorted { $0.rawValue < $1.rawValue }
        self.sourceAccessFailure = sourceAccessFailure
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
    /// Optional request-scoped presentation modules for a read-only Discuss.
    ///
    /// Nil inherits the current Triptych default at preparation time. An
    /// explicit empty array requests only the required Academic Outcome.
    /// Values remain ordered by `DialogueResponseModule.allCases` so App and
    /// CLI encoders produce one stable wire representation.
    public let dialogueResponseModules: [DialogueResponseModule]?
    /// One shared Fidelity run may audit every Application-confirmed target
    /// from a multi-note Write. Nil preserves the single-target wire shape.
    public let fidelityTargets: [ResearchFunctionTarget]?

    public init(
        function: ResearchFunctionID,
        target: ResearchFunctionTarget,
        materials: [ResearchFunctionMaterial] = [],
        instruction: String? = nil,
        scope: ResearchFunctionScope? = nil,
        checks: Set<FidelityCheck> = [],
        commentIDs: [UUID] = [],
        conditionalResources: Set<ResearchFunctionConditionalResource>? = nil,
        dialogueResponseModules: [DialogueResponseModule]? = nil,
        fidelityTargets: [ResearchFunctionTarget]? = nil
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
        if function == .fidelity {
            let ordered = fidelityTargets?.sorted { lhs, rhs in
                if lhs.note.vaultID != rhs.note.vaultID {
                    return lhs.note.vaultID.uuidString < rhs.note.vaultID.uuidString
                }
                return lhs.note.relativePath < rhs.note.relativePath
            }
            self.fidelityTargets = ordered?.isEmpty == false ? ordered : nil
        } else {
            self.fidelityTargets = fidelityTargets
        }
    }

    /// Current split Methods never wait for a secondary mode choice. Nil and
    /// an explicit empty set remain distinguishable only for compatibility
    /// with already-decoded machine-local records.
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
            dialogueResponseModules: dialogueResponseModules,
            fidelityTargets: fidelityTargets
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
        if function == .fidelity {
            let targets = resolvedFidelityTargets
            let targetIDs = targets.map(\.noteID)
            let locations = targets.map(\.note)
            guard !targets.isEmpty,
                  Set(targetIDs).count == targetIDs.count,
                  Set(locations).count == locations.count,
                  targets.contains(where: {
                      $0.noteID == target.noteID && $0.note == target.note
                  }),
                  targets.allSatisfy({
                      $0.lifecycle == .active
                          && !$0.title.isEmpty
                          && ResearchFunctionID.fidelity.allowedTargetRoles.contains($0.role)
                  }) else {
                throw ResearchFunctionContractError.invalidFidelityTargets
            }
        } else if fidelityTargets != nil {
            throw ResearchFunctionContractError.unexpectedFidelityTargets
        }
        guard Set(commentIDs).count == commentIDs.count else {
            throw ResearchFunctionContractError.duplicateComment
        }
        guard (conditionalResources ?? []).allSatisfy({
            function.conditionalResources.contains($0)
        }) else {
            throw ResearchFunctionContractError.invalidMethodSelection
        }
        if function == .discuss {
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
        if function == .discuss, instruction == nil {
            throw ResearchFunctionContractError.emptyInstruction(function)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case function, target, materials, instruction, scope, checks, commentIDs
        case conditionalResources = "conditional_resources"
        case dialogueResponseModules
        case fidelityTargets
    }

    public init(from decoder: Decoder) throws {
        try ResearchFunctionContractCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
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
            ),
            fidelityTargets: try container.decodeIfPresent(
                [ResearchFunctionTarget].self,
                forKey: .fidelityTargets
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
        try container.encodeIfPresent(fidelityTargets, forKey: .fidelityTargets)
    }

    public var resolvedFidelityTargets: [ResearchFunctionTarget] {
        function == .fidelity ? (fidelityTargets ?? [target]) : []
    }
}

/// Decode-compatible transport for retired conditional-resource preflights.
/// No current Function produces a continuation that accepts this value.
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

public enum ResearchFunctionRecordKind: String, Codable, Hashable, Sendable {
    case discuss
    case critique
    case functionEnvelope = "function_envelope"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let kind = Self(rawValue: value) {
            self = kind
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Research Function record kind: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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

/// Correlation identity for one current Action-to-Action continuation.
///
/// Lineage is durable provenance only. It cannot replace the request decision,
/// current Action/Profile resolution, change evidence, grant, or completion checks.
public struct ResearchContinuationLineage: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public enum Kind: String, Codable, Hashable, Sendable {
        case continueResearch = "continue_research"
        case fidelity
        case resynthesis
    }

    public let schemaVersion: Int
    public let groupID: UUID
    public let parentRunID: UUID
    public let requestID: UUID
    public let kind: Kind

    public init(
        groupID: UUID,
        parentRunID: UUID,
        requestID: UUID,
        kind: Kind
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.groupID = groupID
        self.parentRunID = parentRunID
        self.requestID = requestID
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case groupID = "group_id"
        case parentRunID = "parent_run_id"
        case requestID = "request_id"
        case kind
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(
            keyedBy: ResearchContinuationLineageAnyCodingKey.self
        )
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).sorted()
            .first(where: { !allowed.contains($0) }) {
            throw ResearchFunctionContractError.invalidCompletion(
                "Unsupported continuation-lineage field \(unknown)."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchFunctionContractError.invalidCompletion(
                "Unsupported continuation-lineage schema version \(version)."
            )
        }
        self.init(
            groupID: try container.decode(UUID.self, forKey: .groupID),
            parentRunID: try container.decode(UUID.self, forKey: .parentRunID),
            requestID: try container.decode(UUID.self, forKey: .requestID),
            kind: try container.decode(Kind.self, forKey: .kind)
        )
    }
}

private struct ResearchContinuationLineageAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Immutable request-time evidence embedded in an existing Dialogue or
/// Critique record. It records only resources actually resolved for the run.
public struct ResearchFunctionSnapshot: Codable, Hashable, Sendable {
    public let runID: UUID
    public let request: ResearchFunctionRequest
    /// Public Action identity and frozen authority for new resolver-prepared
    /// runs. Nil is accepted only for retained Function-era records.
    public let actionSnapshot: ResearchActionSnapshot?
    public let recordKind: ResearchFunctionRecordKind
    public let recordID: UUID?
    /// Functions coordinated through independent child runs. Manuscript uses
    /// this for its selected phases; write-capable functions use it for their
    /// final-fingerprint Fidelity handoff. Each child retains its own
    /// permission, change-evidence, record, and completion state.
    public let requiredChildFunctions: [ResearchFunctionID]
    /// Request-time revisions of selected Comments or other structured
    /// evidence whose identifiers alone do not change when their content is
    /// edited.
    public let evidenceRevisions: [DocumentFingerprint]
    /// Analysis-only, task-scoped bibliographic context. This projection is
    /// never written back to Markdown and is not a source-evidence claim.
    public let zoteroBibliographicContext: ZoteroBibliographicContext?
    /// Exact source identity and revision validated for Analyze. This safe
    /// projection contains no bookmark, absolute path, or source bytes.
    public let sourceReference: ResearchSourceReference?
    /// Exact citation style selected for this run, when citation checking is active.
    public let citationStyle: String?
    public let continuationLineage: ResearchContinuationLineage?
    /// Explicit academic handoff for an independently resolved Continue
    /// Research child. It contains only selected claims and current owner
    /// checks, never a prior Context response or transient permission state.
    public let continuationHandoff: ResearchContinuationHandoffContext?
    /// Machine-local preparation evidence for a researcher-requested
    /// Resynthesize child. It never enters the portable Research Record.
    public let resynthesisContext: MaterialChangedSinceUseAttentionContext?
    public let fidelityHandoff: ResearchFunctionFidelityHandoff?
    /// Present only for Fidelity runs.
    public let fidelityInvocation: FidelityInvocationKind?
    public let confirmationToken: UUID
    public let preparedAt: Date

    public init(
        runID: UUID = UUID(),
        request: ResearchFunctionRequest,
        actionSnapshot: ResearchActionSnapshot? = nil,
        recordKind: ResearchFunctionRecordKind,
        recordID: UUID? = nil,
        requiredChildFunctions: [ResearchFunctionID] = [],
        evidenceRevisions: [DocumentFingerprint] = [],
        zoteroBibliographicContext: ZoteroBibliographicContext? = nil,
        sourceReference: ResearchSourceReference? = nil,
        citationStyle: String? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        continuationHandoff: ResearchContinuationHandoffContext? = nil,
        resynthesisContext: MaterialChangedSinceUseAttentionContext? = nil,
        fidelityHandoff: ResearchFunctionFidelityHandoff? = nil,
        fidelityInvocation: FidelityInvocationKind? = nil,
        confirmationToken: UUID = UUID(),
        preparedAt: Date = Date()
    ) {
        self.runID = runID
        self.request = request
        self.actionSnapshot = actionSnapshot
        self.recordKind = recordKind
        self.recordID = recordID
        self.requiredChildFunctions = Array(Set(requiredChildFunctions)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.evidenceRevisions = evidenceRevisions
        self.zoteroBibliographicContext = zoteroBibliographicContext
        self.sourceReference = sourceReference
        self.citationStyle = citationStyle
        self.continuationLineage = continuationLineage
        self.continuationHandoff = continuationHandoff
        self.resynthesisContext = resynthesisContext
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

/// Per-note agent submission for one shared Fidelity run. The Application
/// verifies both identity and the exact revision before accepting outcomes.
public struct ResearchFunctionFidelityTargetSubmission: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let fingerprint: DocumentFingerprint
    public let outcomes: [FidelityCheckOutcome]

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        fingerprint: DocumentFingerprint,
        outcomes: [FidelityCheckOutcome]
    ) {
        self.noteID = noteID
        self.note = note
        self.fingerprint = fingerprint
        self.outcomes = outcomes
    }
}

/// Durable, independently revision-bound result for one note inside a shared
/// Fidelity run. A stale peer never invalidates another target's result.
public struct ResearchFunctionFidelityTargetResult: Codable, Hashable, Sendable {
    public let target: ResearchFunctionTarget
    public let outcomes: [FidelityCheckOutcome]

    public init(
        target: ResearchFunctionTarget,
        outcomes: [FidelityCheckOutcome]
    ) {
        self.target = target
        self.outcomes = outcomes
    }
}

public struct ResearchFunctionCompletionSubmission: Codable, Hashable, Sendable {
    public let runID: UUID
    public let confirmationToken: UUID
    public let recordTitle: ResearchRecordTitle
    /// Legacy and read-only completion evidence. A keyed Develop or Revise
    /// omits this value because Scholium reads every frozen target itself.
    public let finalTargetFingerprint: DocumentFingerprint?
    public let finalMaterialFingerprints: [UUID: DocumentFingerprint]
    /// Stable IDs the agent reports actually using. Application validation
    /// intersects this testimony with the frozen Material set and exact
    /// revisions before it can enter a portable Research Record.
    public let actuallyUsedMaterialNoteIDs: [UUID]?
    public let summary: String
    public let didModifyTarget: Bool
    public let fidelityOutcomes: [FidelityCheckOutcome]
    /// Present for a shared multi-note Fidelity run. A single-target run may
    /// continue using `fidelityOutcomes` for wire compatibility.
    public let fidelityTargetSubmissions: [ResearchFunctionFidelityTargetSubmission]?
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?
    public let submittedAt: Date
    public let childRunIDs: [UUID]?

    public init(
        runID: UUID,
        confirmationToken: UUID,
        recordTitle: ResearchRecordTitle,
        finalTargetFingerprint: DocumentFingerprint? = nil,
        finalMaterialFingerprints: [UUID: DocumentFingerprint] = [:],
        actuallyUsedMaterialNoteIDs: [UUID]? = [],
        summary: String,
        didModifyTarget: Bool,
        fidelityOutcomes: [FidelityCheckOutcome] = [],
        fidelityTargetSubmissions: [ResearchFunctionFidelityTargetSubmission] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil,
        childRunIDs: [UUID] = [],
        submittedAt: Date = Date()
    ) {
        self.runID = runID
        self.confirmationToken = confirmationToken
        self.recordTitle = recordTitle
        self.finalTargetFingerprint = finalTargetFingerprint
        self.finalMaterialFingerprints = finalMaterialFingerprints
        self.actuallyUsedMaterialNoteIDs = actuallyUsedMaterialNoteIDs?.sorted {
            $0.uuidString < $1.uuidString
        }
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.didModifyTarget = didModifyTarget
        self.fidelityOutcomes = fidelityOutcomes
        self.fidelityTargetSubmissions = fidelityTargetSubmissions.isEmpty
            ? nil
            : fidelityTargetSubmissions
        self.literatureRecommendations = literatureRecommendations
        self.childRunIDs = childRunIDs.isEmpty ? nil : childRunIDs
        self.submittedAt = submittedAt
    }
}

/// Durable completion evidence. Fidelity remains attributed structured output,
/// not a hidden app judgment or a replacement for researcher acceptance or Critique.
public struct ResearchFunctionCompletion: Codable, Hashable, Sendable {
    public let runID: UUID
    public let function: ResearchFunctionID
    public let state: ResearchFunctionRunState
    public let recordTitle: ResearchRecordTitle
    public let targetFingerprint: DocumentFingerprint
    public let materialFingerprints: [UUID: DocumentFingerprint]
    public let actuallyUsedMaterialNoteIDs: [UUID]?
    public let summary: String
    public let didModifyTarget: Bool
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let fidelityTargetResults: [ResearchFunctionFidelityTargetResult]?
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?
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
        recordTitle: ResearchRecordTitle,
        targetFingerprint: DocumentFingerprint,
        materialFingerprints: [UUID: DocumentFingerprint],
        actuallyUsedMaterialNoteIDs: [UUID]? = [],
        summary: String,
        didModifyTarget: Bool,
        fidelityOutcomes: [FidelityCheckOutcome],
        fidelityTargetResults: [ResearchFunctionFidelityTargetResult] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil,
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
        self.recordTitle = recordTitle
        self.targetFingerprint = targetFingerprint
        self.materialFingerprints = materialFingerprints
        self.actuallyUsedMaterialNoteIDs = actuallyUsedMaterialNoteIDs?.sorted {
            $0.uuidString < $1.uuidString
        }
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.didModifyTarget = didModifyTarget
        self.fidelityOutcomes = fidelityOutcomes
        self.fidelityTargetResults = fidelityTargetResults.isEmpty
            ? nil
            : fidelityTargetResults
        self.literatureRecommendations = literatureRecommendations
        self.fidelityEvidenceKey = fidelityEvidenceKey
        self.reusedFidelityRunID = reusedFidelityRunID
        self.childRunIDs = childRunIDs.isEmpty ? nil : childRunIDs
        self.completedAt = completedAt
        self.derivedRefreshWarning = derivedRefreshWarning
        self.nextActions = nextActions.isEmpty ? nil : nextActions
    }
}

/// A stable audit key. A changed Target, Material/evidence revision, check,
/// registered primary Method, Practice, or Profile revision creates a new key
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
        if let style = snapshot.citationStyle {
            lines.append("citation-style:\(style)")
        }
        if let method = snapshot.actionSnapshot?.method {
            lines.append(
                "method:\(method.registration.key.description):\(method.primaryMarkdownRevision.sha256):\(method.primaryMarkdownRevision.byteCount)"
            )
            for practice in method.practices {
                lines.append(
                    "practice:\(practice.relativePath):\(practice.revision.sha256):\(practice.revision.byteCount)"
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
    case unexpectedWriteScope
    case duplicateWriteTarget
    case inactiveWriteTarget
    case writeTargetRepeatedAsMaterial
    case invalidFidelityTargets
    case unexpectedFidelityTargets
    case materialChanged(String)
    case sourceAccessUnavailable(ResearchSourceAccessFailure)
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
    case citationStyleUnavailable
    case emptyInstruction(ResearchFunctionID)
    case preparationNotFound(UUID)
    case activeDiscussionExists(UUID)
    case confirmationMismatch
    case completionAlreadyRecorded(UUID)
    case invalidCompletion(String)
    case cancellationAfterCompletion(UUID)
    case unresolvedWriteRecovery(UUID)
    case committedWritesRequireCompletion(UUID)

    public var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The Action Target is not available in the current Triptych generation."
        case .targetChanged:
            "The Action Target changed after the sheet captured it. Reload the current note before continuing."
        case .targetIdentityChanged:
            "The Action Target no longer has the same stable identity."
        case .inactiveTarget:
            "An Action requires an active Target, not a set-aside or trashed note."
        case .invalidTargetRole(_, let role):
            "This Action is not available for a \(role.rawValue) Target."
        case .emptyTargetTitle:
            "The Action Target must have a nonempty title projection."
        case .duplicateMaterial:
            "Each Action Material may be selected only once."
        case .targetRepeatedAsMaterial:
            "The Action Target cannot also be selected as Material."
        case .inactiveMaterial:
            "Action Materials must be active, identified notes."
        case .unexpectedWriteScope:
            "Only the current Analyze, Synthesize, or Write Action may carry its exact current Target as write scope."
        case .duplicateWriteTarget:
            "Each authorized Write target may appear only once."
        case .inactiveWriteTarget:
            "Every authorized Write target must be an active, identified note."
        case .writeTargetRepeatedAsMaterial:
            "A writable note cannot also be selected as read-only Material."
        case .invalidFidelityTargets:
            "A shared Fidelity run requires a unique, active set that includes its origin Target."
        case .unexpectedFidelityTargets:
            "Only Fidelity may carry a shared target set."
        case .materialChanged(let title):
            "The Material '\(title)' changed while the Action was being prepared."
        case .sourceAccessUnavailable(let failure):
            "Analyze requires the exact readable source. Source access failed with \(failure.code.rawValue); choose the source again before continuing."
        case .duplicateComment:
            "Each Comment may be selected only once."
        case .invalidScope:
            "Passage scope requires a selection from the exact Target revision; Whole scope has no selection."
        case .missingFidelityCheck:
            "Fidelity requires Content, Citations, or both."
        case .unexpectedFidelityCheck:
            "Fidelity checks belong only to the Fidelity function."
        case .invalidMethodSelection:
            "A selected internal method does not belong to this Action."
        case .duplicateDialogueResponseModule:
            "Each optional Discuss response module may be selected only once."
        case .unexpectedDialogueResponseModules:
            "Discuss response modules belong only to the Discuss function."
        case .methodSelectionNotRequired:
            "This Action has no pending conditional method selection."
        case .methodSelectionAlreadyResolved(let id):
            "Action methods are already finalized for run \(id.uuidString)."
        case .methodSelectionRequired(let id):
            "Select the conditional methods, including an explicit empty selection when the primary method is sufficient, before completing run \(id.uuidString)."
        case .citationStyleUnavailable:
            "Citation checking requires an active citation style in Research Guidance."
        case .emptyInstruction:
            "This Action requires a researcher instruction."
        case .preparationNotFound(let id):
            "Action preparation not found: \(id.uuidString)"
        case .activeDiscussionExists(let id):
            "Discussion \(id.uuidString) is already active for this Note. Reopen it from Active Discussions to add the whole-note turn."
        case .confirmationMismatch:
            "The completion does not match the prepared Action run."
        case .completionAlreadyRecorded(let id):
            "Action completion is already recorded: \(id.uuidString)"
        case .invalidCompletion(let reason):
            "The Action completion is invalid. \(reason)"
        case .cancellationAfterCompletion(let id):
            "A completed Action run cannot be cancelled: \(id.uuidString)"
        case .unresolvedWriteRecovery(let id):
            "Action run \(id.uuidString) has an unresolved document-write recovery and cannot be cancelled or finalized."
        case .committedWritesRequireCompletion(let id):
            "Action run \(id.uuidString) has confirmed Agent changes. Submit its Result to preserve Research Record and Note Review provenance before ending it."
        }
    }
}

private enum ResearchFunctionContractCoding {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchFunctionContractCodingKey.self
        )
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) })
        else {
            throw ResearchFunctionContractError.invalidCompletion(
                "The contract contains an unknown field."
            )
        }
    }
}

private struct ResearchFunctionContractCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
