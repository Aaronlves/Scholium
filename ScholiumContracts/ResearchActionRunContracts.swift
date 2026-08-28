import Foundation

public enum ResearchActionScopeKind: String, Codable, Hashable, Sendable {
    case whole
    case passage
}

/// Whole/Passage remains a delivery-neutral semantic choice. Passage scope
/// uses the same exact-source anchor as Comments and never stores rendered
/// text as writable authority.
public struct ResearchActionScope: Codable, Hashable, Sendable {
    public let kind: ResearchActionScopeKind
    public let selection: CommentAnchor?

    public static let whole = Self(kind: .whole)

    public static func passage(_ selection: CommentAnchor) -> Self {
        Self(kind: .passage, selection: selection)
    }

    public init(
        kind: ResearchActionScopeKind,
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

public enum ResearchActionRunRepairReasonCode: String, Codable, Hashable, Sendable {
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
public struct ResearchActionRunRepairReason: Codable, Hashable, Sendable {
    public let code: ResearchActionRunRepairReasonCode
    public let actionID: ResearchActionID?
    public let expectedRoles: [ResearchActionTargetRole]
    public let sourceAccessFailure: ResearchSourceAccessFailure?

    public init(
        code: ResearchActionRunRepairReasonCode,
        actionID: ResearchActionID? = nil,
        expectedRoles: [ResearchActionTargetRole] = [],
        sourceAccessFailure: ResearchSourceAccessFailure? = nil
    ) {
        self.code = code
        self.actionID = actionID
        self.expectedRoles = Array(Set(expectedRoles)).sorted { $0.rawValue < $1.rawValue }
        self.sourceAccessFailure = sourceAccessFailure
    }
}

public struct ResearchActionRunCheckAvailability: Codable, Hashable, Sendable {
    public let check: FidelityCheck
    public let isEnabled: Bool
    public let repairReasons: [ResearchActionRunRepairReason]

    public init(
        check: FidelityCheck,
        isEnabled: Bool,
        repairReasons: [ResearchActionRunRepairReason] = []
    ) {
        self.check = check
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
    }
}

public struct ResearchActionRunAvailability: Codable, Hashable, Identifiable, Sendable {
    public let actionID: ResearchActionID
    public let isEnabled: Bool
    public let repairReasons: [ResearchActionRunRepairReason]
    public let fidelityChecks: [ResearchActionRunCheckAvailability]

    public var id: ResearchActionID { actionID }

    public init(
        actionID: ResearchActionID,
        isEnabled: Bool,
        repairReasons: [ResearchActionRunRepairReason] = [],
        fidelityChecks: [ResearchActionRunCheckAvailability] = []
    ) {
        self.actionID = actionID
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
        self.fidelityChecks = fidelityChecks
    }
}

/// A deterministic, explicitly sourced reason that one read-only note may be
/// useful as Material. Suggestions are navigation aids only: they never imply
/// evidential support, authorize retrieval, or select the note automatically.
public struct ResearchActionMaterialSuggestionReason: Codable, Hashable, Sendable {
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

public struct ResearchActionMaterialCandidate: Codable, Hashable, Identifiable, Sendable {
    public let material: ResearchActionNoteSnapshot
    /// Search-only aliases projected from the current catalog. They do not
    /// enter a prepared request or become authoritative Material identity.
    public let aliases: [String]
    public let suggestionReasons: [ResearchActionMaterialSuggestionReason]
    public let isSelectable: Bool
    public let repairReasons: [ResearchActionRunRepairReason]

    public var id: UUID { material.id }

    public init(
        material: ResearchActionNoteSnapshot,
        aliases: [String] = [],
        suggestionReasons: [ResearchActionMaterialSuggestionReason] = [],
        isSelectable: Bool = true,
        repairReasons: [ResearchActionRunRepairReason] = []
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

public struct ResearchActionRunRequest: Codable, Hashable, Sendable {
    public let actionID: ResearchActionID
    public let target: ResearchActionNoteSnapshot
    public let materials: [ResearchActionNoteSnapshot]
    public let instruction: String?
    public let scope: ResearchActionScope?
    public let checks: Set<FidelityCheck>
    /// Optional request-scoped presentation modules for a read-only Discuss.
    ///
    /// Nil inherits the current Triptych default at preparation time. An
    /// explicit empty array requests only the required Academic Outcome.
    /// Values remain ordered by `DialogueResponseModule.allCases` so App and
    /// CLI encoders produce one stable wire representation.
    public let dialogueResponseModules: [DialogueResponseModule]?
    /// One shared Fidelity run may audit every Application-confirmed target
    /// from a multi-note Write. Nil preserves the single-target wire shape.
    public let fidelityTargets: [ResearchActionNoteSnapshot]?

    public init(
        actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        materials: [ResearchActionNoteSnapshot] = [],
        instruction: String? = nil,
        scope: ResearchActionScope? = nil,
        checks: Set<FidelityCheck> = [],
        dialogueResponseModules: [DialogueResponseModule]? = nil,
        fidelityTargets: [ResearchActionNoteSnapshot]? = nil
    ) {
        self.actionID = actionID
        self.target = target
        self.materials = materials
        let normalized = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.instruction = normalized?.isEmpty == false ? normalized : nil
        self.scope = scope
        self.checks = checks
        self.dialogueResponseModules = dialogueResponseModules.map { modules in
            modules.sorted { lhs, rhs in
                let lhsIndex = DialogueResponseModule.allCases.firstIndex(of: lhs) ?? 0
                let rhsIndex = DialogueResponseModule.allCases.firstIndex(of: rhs) ?? 0
                return lhsIndex < rhsIndex
            }
        }
        if actionID == .checkFidelity {
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

    public func validate() throws {
        guard actionID.allowedTargetRoles.contains(target.role) else {
            throw ResearchActionRunContractError.invalidTargetRole(
                actionID: actionID,
                role: target.role
            )
        }
        guard !target.title.isEmpty else {
            throw ResearchActionRunContractError.emptyTargetTitle
        }
        let materialIDs = materials.map(\.noteID)
        guard Set(materialIDs).count == materialIDs.count else {
            throw ResearchActionRunContractError.duplicateMaterial
        }
        guard !materials.contains(where: {
            $0.noteID == target.noteID || $0.note == target.note
        }) else {
            throw ResearchActionRunContractError.targetRepeatedAsMaterial
        }
        guard materials.allSatisfy({ !$0.title.isEmpty }) else {
            throw ResearchActionRunContractError.inactiveMaterial
        }
        if actionID == .checkFidelity {
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
                      !$0.title.isEmpty
                          && ResearchActionID.checkFidelity.allowedTargetRoles.contains($0.role)
                  }) else {
                throw ResearchActionRunContractError.invalidFidelityTargets
            }
        } else if fidelityTargets != nil {
            throw ResearchActionRunContractError.unexpectedFidelityTargets
        }
        if actionID == .discuss {
            if let dialogueResponseModules,
               Set(dialogueResponseModules).count != dialogueResponseModules.count {
                throw ResearchActionRunContractError.duplicateDialogueResponseModule
            }
        } else if dialogueResponseModules != nil {
            throw ResearchActionRunContractError.unexpectedDialogueResponseModules
        }
        if let scope {
            switch scope.kind {
            case .whole:
                guard scope.selection == nil else {
                    throw ResearchActionRunContractError.invalidScope
                }
            case .passage:
                guard let selection = scope.selection,
                      selection.fingerprint == target.fingerprint else {
                    throw ResearchActionRunContractError.invalidScope
                }
            }
        }
        if actionID == .checkFidelity {
            guard !checks.isEmpty else {
                throw ResearchActionRunContractError.missingFidelityCheck
            }
        } else if !checks.isEmpty {
            throw ResearchActionRunContractError.unexpectedFidelityCheck
        }
        if actionID == .discuss, instruction == nil {
            throw ResearchActionRunContractError.emptyInstruction(actionID)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionID, target, materials, instruction, scope, checks
        case dialogueResponseModules
        case fidelityTargets
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionRunContractCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            actionID: try container.decode(ResearchActionID.self, forKey: .actionID),
            target: try container.decode(ResearchActionNoteSnapshot.self, forKey: .target),
            materials: try container.decodeIfPresent(
                [ResearchActionNoteSnapshot].self,
                forKey: .materials
            ) ?? [],
            instruction: try container.decodeIfPresent(String.self, forKey: .instruction),
            scope: try container.decodeIfPresent(ResearchActionScope.self, forKey: .scope),
            checks: try container.decodeIfPresent(Set<FidelityCheck>.self, forKey: .checks) ?? [],
            dialogueResponseModules: try container.decodeIfPresent(
                [DialogueResponseModule].self,
                forKey: .dialogueResponseModules
            ),
            fidelityTargets: try container.decodeIfPresent(
                [ResearchActionNoteSnapshot].self,
                forKey: .fidelityTargets
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(target, forKey: .target)
        if !materials.isEmpty { try container.encode(materials, forKey: .materials) }
        try container.encodeIfPresent(instruction, forKey: .instruction)
        try container.encodeIfPresent(scope, forKey: .scope)
        if !checks.isEmpty { try container.encode(checks, forKey: .checks) }
        try container.encodeIfPresent(dialogueResponseModules, forKey: .dialogueResponseModules)
        try container.encodeIfPresent(fidelityTargets, forKey: .fidelityTargets)
    }

    public var resolvedFidelityTargets: [ResearchActionNoteSnapshot] {
        actionID == .checkFidelity ? (fidelityTargets ?? [target]) : []
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
            throw ResearchActionRunContractError.invalidCompletion(
                "Unsupported continuation-lineage field \(unknown)."
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchActionRunContractError.invalidCompletion(
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

/// Immutable request-time evidence for one prepared Action run.
///
/// It records the frozen request and resolution evidence needed to execute and
/// complete that run; protected execution details remain in Local Execution.
public enum ResearchAnalysisSourceRoute: String, Codable, Hashable, Sendable {
    /// Scholium resolved and fingerprinted one explicit local source binding.
    case scholiumSource = "scholium_source"
    /// The Run froze a portable Zotero relationship and bibliographic context;
    /// the external Agent retrieves paper data through its own integration.
    case externalZotero = "external_zotero"
    /// The researcher supplied the source directly to the external Agent.
    /// Scholium receives no path, bytes, or source-access claim.
    case researcherProvided = "researcher_provided"
}

public struct ResearchActionRunSnapshot: Codable, Hashable, Sendable {
    public let runID: UUID
    public let request: ResearchActionRunRequest
    /// Public Action identity and frozen authority when the run is resolved.
    public let actionSnapshot: ResearchActionSnapshot
    public let recordID: UUID?
    /// Analysis-only, task-scoped bibliographic context. This projection is
    /// never written back to Markdown and is not a source-evidence claim.
    public let zoteroBibliographicContext: ZoteroBibliographicContext?
    /// Exact source identity and revision validated for Analyze. This safe
    /// projection contains no bookmark, absolute path, or source bytes.
    public let sourceReference: ResearchSourceReference?
    /// Frozen Analyze source routing. This distinguishes an intentionally
    /// researcher-provided source from an accidentally missing binding without
    /// fabricating a `ResearchSourceReference` for material Scholium never saw.
    public let analysisSourceRoute: ResearchAnalysisSourceRoute?
    /// Exact citation style selected for this run, when citation checking is active.
    public let citationStyle: String?
    public let continuationLineage: ResearchContinuationLineage?
    /// Explicit academic handoff for an independently resolved Continue
    /// Research child. It contains only selected claims and current owner
    /// checks, never a prior Context response or transient permission state.
    public let continuationHandoff: ResearchContinuationHandoffContext?
    /// Machine-local preparation evidence for a researcher-requested
    /// Resynthesize child. It never enters the portable Research Record.
    public let resynthesisContext: SynthesisMaterialChangedAttentionContext?
    public let confirmationToken: UUID
    public let preparedAt: Date

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case runID
        case request
        case actionSnapshot
        case recordID
        case zoteroBibliographicContext
        case sourceReference
        case analysisSourceRoute
        case citationStyle
        case continuationLineage
        case continuationHandoff
        case resynthesisContext
        case confirmationToken
        case preparedAt
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionRunContractCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            runID: try container.decode(UUID.self, forKey: .runID),
            request: try container.decode(ResearchActionRunRequest.self, forKey: .request),
            actionSnapshot: try container.decode(
                ResearchActionSnapshot.self,
                forKey: .actionSnapshot
            ),
            recordID: try container.decodeIfPresent(UUID.self, forKey: .recordID),
            zoteroBibliographicContext: try container.decodeIfPresent(
                ZoteroBibliographicContext.self,
                forKey: .zoteroBibliographicContext
            ),
            sourceReference: try container.decodeIfPresent(
                ResearchSourceReference.self,
                forKey: .sourceReference
            ),
            analysisSourceRoute: try container.decodeIfPresent(
                ResearchAnalysisSourceRoute.self,
                forKey: .analysisSourceRoute
            ),
            citationStyle: try container.decodeIfPresent(
                String.self,
                forKey: .citationStyle
            ),
            continuationLineage: try container.decodeIfPresent(
                ResearchContinuationLineage.self,
                forKey: .continuationLineage
            ),
            continuationHandoff: try container.decodeIfPresent(
                ResearchContinuationHandoffContext.self,
                forKey: .continuationHandoff
            ),
            resynthesisContext: try container.decodeIfPresent(
                SynthesisMaterialChangedAttentionContext.self,
                forKey: .resynthesisContext
            ),
            confirmationToken: try container.decode(
                UUID.self,
                forKey: .confirmationToken
            ),
            preparedAt: try container.decode(Date.self, forKey: .preparedAt)
        )
    }

    public init(
        runID: UUID = UUID(),
        request: ResearchActionRunRequest,
        actionSnapshot: ResearchActionSnapshot,
        recordID: UUID? = nil,
        zoteroBibliographicContext: ZoteroBibliographicContext? = nil,
        sourceReference: ResearchSourceReference? = nil,
        analysisSourceRoute: ResearchAnalysisSourceRoute? = nil,
        citationStyle: String? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        continuationHandoff: ResearchContinuationHandoffContext? = nil,
        resynthesisContext: SynthesisMaterialChangedAttentionContext? = nil,
        confirmationToken: UUID = UUID(),
        preparedAt: Date = Date()
    ) throws {
        try request.validate()
        guard request.actionID == actionSnapshot.actionID else {
            throw ResearchActionRunContractError.inconsistentActionSnapshot(
                requestActionID: request.actionID,
                snapshotActionID: actionSnapshot.actionID
            )
        }
        guard request.target == actionSnapshot.target else {
            throw ResearchActionRunContractError.inconsistentActionTarget
        }
        self.runID = runID
        self.request = request
        self.actionSnapshot = actionSnapshot
        self.recordID = recordID
        self.zoteroBibliographicContext = zoteroBibliographicContext
        self.sourceReference = sourceReference
        self.analysisSourceRoute = analysisSourceRoute
        self.citationStyle = citationStyle
        self.continuationLineage = continuationLineage
        self.continuationHandoff = continuationHandoff
        self.resynthesisContext = resynthesisContext
        self.confirmationToken = confirmationToken
        self.preparedAt = preparedAt
    }
}

public struct ResearchActionRunPreparation: Codable, Hashable, Sendable {
    public let snapshot: ResearchActionRunSnapshot
    public let instructions: String
    public let state: ResearchActionRunState
    public let reusedCompletion: ResearchActionRunCompletion?
    /// The authoritative preparation committed, but a disposable workspace
    /// projection did not refresh. Callers must retain this preparation and
    /// retry only refresh, never the actionID mutation.
    public let derivedRefreshWarning: String?
    public let nextActions: [AgentCommandAction]?

    public var runID: UUID { snapshot.runID }

    public init(
        snapshot: ResearchActionRunSnapshot,
        instructions: String,
        state: ResearchActionRunState = .prepared,
        reusedCompletion: ResearchActionRunCompletion? = nil,
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
            throw ResearchActionRunContractError.invalidCompletion(
                "Every Fidelity outcome requires an attributed summary."
            )
        }
        switch state {
        case .passed:
            guard findings.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
                    "A passed Fidelity check cannot also report unresolved findings."
                )
            }
        case .issuesFound:
            guard !findings.isEmpty else {
                throw ResearchActionRunContractError.invalidCompletion(
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
public struct ResearchActionFidelityTargetSubmission: Codable, Hashable, Sendable {
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
public struct ResearchActionFidelityTargetResult: Codable, Hashable, Sendable {
    public let target: ResearchActionNoteSnapshot
    public let outcomes: [FidelityCheckOutcome]

    public init(
        target: ResearchActionNoteSnapshot,
        outcomes: [FidelityCheckOutcome]
    ) {
        self.target = target
        self.outcomes = outcomes
    }
}

public struct ResearchActionRunCompletionSubmission: Codable, Hashable, Sendable {
    public let runID: UUID
    public let confirmationToken: UUID
    public let recordTitle: ResearchRecordTitle
    /// Read-only completion evidence. A keyed Develop or Revise
    /// omits this value because Scholium reads every frozen target itself.
    public let finalTargetFingerprint: DocumentFingerprint?
    public let finalMaterialFingerprints: [UUID: DocumentFingerprint]
    public let summary: String
    public let didModifyTarget: Bool
    public let fidelityOutcomes: [FidelityCheckOutcome]
    /// Present for a shared multi-note Fidelity run. A single-target run may
    /// continue using `fidelityOutcomes` for wire compatibility.
    public let fidelityTargetSubmissions: [ResearchActionFidelityTargetSubmission]?
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?
    public let submittedAt: Date
    public let childRunIDs: [UUID]?

    public init(
        runID: UUID,
        confirmationToken: UUID,
        recordTitle: ResearchRecordTitle,
        finalTargetFingerprint: DocumentFingerprint? = nil,
        finalMaterialFingerprints: [UUID: DocumentFingerprint] = [:],
        summary: String,
        didModifyTarget: Bool,
        fidelityOutcomes: [FidelityCheckOutcome] = [],
        fidelityTargetSubmissions: [ResearchActionFidelityTargetSubmission] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil,
        childRunIDs: [UUID] = [],
        submittedAt: Date = Date()
    ) {
        self.runID = runID
        self.confirmationToken = confirmationToken
        self.recordTitle = recordTitle
        self.finalTargetFingerprint = finalTargetFingerprint
        self.finalMaterialFingerprints = finalMaterialFingerprints
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
public struct ResearchActionRunCompletion: Codable, Hashable, Sendable {
    public let runID: UUID
    public let actionID: ResearchActionID
    public let state: ResearchActionRunState
    public let recordTitle: ResearchRecordTitle
    public let targetFingerprint: DocumentFingerprint
    public let materialFingerprints: [UUID: DocumentFingerprint]
    public let summary: String
    public let didModifyTarget: Bool
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let fidelityTargetResults: [ResearchActionFidelityTargetResult]?
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
        actionID: ResearchActionID,
        state: ResearchActionRunState,
        recordTitle: ResearchRecordTitle,
        targetFingerprint: DocumentFingerprint,
        materialFingerprints: [UUID: DocumentFingerprint],
        summary: String,
        didModifyTarget: Bool,
        fidelityOutcomes: [FidelityCheckOutcome],
        fidelityTargetResults: [ResearchActionFidelityTargetResult] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil,
        fidelityEvidenceKey: ResearchFidelityEvidenceKey? = nil,
        reusedFidelityRunID: UUID? = nil,
        childRunIDs: [UUID] = [],
        completedAt: Date = Date(),
        derivedRefreshWarning: String? = nil,
        nextActions: [AgentCommandAction] = []
    ) {
        self.runID = runID
        self.actionID = actionID
        self.state = state
        self.recordTitle = recordTitle
        self.targetFingerprint = targetFingerprint
        self.materialFingerprints = materialFingerprints
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

/// A stable audit key. A changed Target, Material revision, check,
/// registered Skill entry or Profile revision creates a new key
/// and therefore cannot silently reuse stale Fidelity evidence.
public struct ResearchFidelityEvidenceKey: Codable, Hashable, Sendable {
    public let revision: DocumentFingerprint

    public init(
        snapshot: ResearchActionRunSnapshot,
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
        if let style = snapshot.citationStyle {
            lines.append("citation-style:\(style)")
        }
        let method = snapshot.actionSnapshot.method
        lines.append(
            "method:\(method.registration.key.description):\(method.primaryMarkdownRevision.sha256):\(method.primaryMarkdownRevision.byteCount)"
        )
        revision = DocumentFingerprint(content: lines.joined(separator: "\n"))
    }
}

/// Read-only record projection kept separate from Dialogue, Critique, Human
/// Review, Comments, and Fidelity findings even when storage is shared.
public struct ResearchActionRunRecordProjection: Codable, Hashable, Identifiable, Sendable {
    public let snapshot: ResearchActionRunSnapshot
    public let completion: ResearchActionRunCompletion?
    /// Exact agent handoff persisted for the run. A method-unresolved
    /// preflight may be replaced once by its finalized immutable execution
    /// packet; unresolved preflight records may omit it.
    public let preparedInstructions: String?

    public var id: UUID { snapshot.runID }

    public init(
        snapshot: ResearchActionRunSnapshot,
        completion: ResearchActionRunCompletion? = nil,
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

public enum ResearchActionRunContractError: LocalizedError, Sendable {
    case targetUnavailable
    case targetChanged
    case targetIdentityChanged
    case inactiveTarget
    case invalidTargetRole(actionID: ResearchActionID, role: ResearchActionTargetRole)
    case inconsistentActionSnapshot(
        requestActionID: ResearchActionID,
        snapshotActionID: ResearchActionID
    )
    case inconsistentActionTarget
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
    case invalidScope
    case missingFidelityCheck
    case unexpectedFidelityCheck
    case duplicateDialogueResponseModule
    case unexpectedDialogueResponseModules
    case citationStyleUnavailable
    case emptyInstruction(ResearchActionID)
    case preparationNotFound(UUID)
    case activeDiscussionExists(UUID)
    case confirmationMismatch
    case completionAlreadyRecorded(UUID)
    case invalidCompletion(String)
    case cancellationAfterCompletion(UUID)
    case unresolvedWriteRecovery(UUID)
    case committedWritesRequireCompletion(UUID)
    case activeResultRequired

    public var errorDescription: String? {
        switch self {
        case .targetUnavailable:
            "The Action Target is not available in the current Triptych generation."
        case .targetChanged:
            "The Action Target changed after the sheet captured it. Reload the current note before continuing."
        case .targetIdentityChanged:
            "The Action Target no longer has the same stable identity."
        case .inactiveTarget:
            "The Action Target is not available for this operation."
        case .invalidTargetRole(_, let role):
            "This Action is not available for a \(role.rawValue) Target."
        case .inconsistentActionSnapshot(let requestActionID, let snapshotActionID):
            "The Run request Action \(requestActionID.rawValue) does not match the frozen Action \(snapshotActionID.rawValue)."
        case .inconsistentActionTarget:
            "The Run request Target does not match the exact frozen Action Target."
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
        case .invalidScope:
            "Passage scope requires a selection from the exact Target revision; Whole scope has no selection."
        case .missingFidelityCheck:
            "Fidelity requires Content, Citations, or both."
        case .unexpectedFidelityCheck:
            "Fidelity checks belong only to the Fidelity actionID."
        case .duplicateDialogueResponseModule:
            "Each optional Discuss response module may be selected only once."
        case .unexpectedDialogueResponseModules:
            "Discuss response modules belong only to the Discuss actionID."
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
        case .activeResultRequired:
            "This Note already has an active Action with saved Agent changes awaiting its Research Result. Resume that Action instead of starting another."
        }
    }
}

private enum ResearchActionRunContractCoding {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchActionRunContractCodingKey.self
        )
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) })
        else {
            throw ResearchActionRunContractError.invalidCompletion(
                "The contract contains an unknown field."
            )
        }
    }
}

private struct ResearchActionRunContractCodingKey: CodingKey {
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
