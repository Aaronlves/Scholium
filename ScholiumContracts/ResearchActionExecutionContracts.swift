import Foundation

/// Exact note identity and revision at the public Action boundary.
///
/// This deliberately mirrors only the stable note facts needed by an Action;
/// it contains no protected Function identity or storage locator.
public struct ResearchActionNoteSnapshot: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let lifecycle: WorkspaceDocumentLifecycle
    public let fingerprint: DocumentFingerprint
    public let title: String

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        lifecycle: WorkspaceDocumentLifecycle,
        fingerprint: DocumentFingerprint,
        title: String
    ) {
        self.noteID = noteID
        self.note = note
        self.role = role
        self.lifecycle = lifecycle
        self.fingerprint = fingerprint
        self.title = title
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID
        case note
        case role
        case lifecycle
        case fingerprint
        case title
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            noteID: try container.decode(UUID.self, forKey: .noteID),
            note: try container.decode(VaultQualifiedNoteID.self, forKey: .note),
            role: try container.decode(ResearchActionTargetRole.self, forKey: .role),
            lifecycle: try container.decode(
                WorkspaceDocumentLifecycle.self,
                forKey: .lifecycle
            ),
            fingerprint: try container.decode(
                DocumentFingerprint.self,
                forKey: .fingerprint
            ),
            title: try container.decode(String.self, forKey: .title)
        )
    }
}

public struct ResearchActionPlatformInputs: Codable, Hashable, Sendable {
    public let focalNotes: [ResearchActionNoteSnapshot]
    public let passage: CommentAnchor?
    public let fidelityChecks: [FidelityCheck]

    public init(
        focalNotes: [ResearchActionNoteSnapshot] = [],
        passage: CommentAnchor? = nil,
        fidelityChecks: Set<FidelityCheck> = []
    ) throws {
        guard focalNotes.count <= 16,
              Set(focalNotes.map(\.noteID)).count == focalNotes.count else {
            throw ResearchActionExecutionContractError.invalidParameter(
                "Platform focal Notes are duplicated or exceed the bounded maximum."
            )
        }
        self.focalNotes = focalNotes
        self.passage = passage
        self.fidelityChecks = fidelityChecks.sorted { $0.rawValue < $1.rawValue }
    }

    public func validated(
        for definition: PlatformActionDefinition,
        target: ResearchActionNoteSnapshot
    ) throws -> Self {
        let selectors = Set(definition.requiredSelectors + definition.optionalSelectors)
        guard (focalNotes.isEmpty || selectors.contains(.focalNotes)),
              (passage == nil || selectors.contains(.passage)),
              (fidelityChecks.isEmpty || selectors.contains(.fidelityChecks)),
              passage.map({ $0.fingerprint == target.fingerprint }) ?? true else {
            throw ResearchActionExecutionContractError.invalidParameter(
                "A Platform input is unsupported or stale for this Action."
            )
        }
        return self
    }
}

/// One closed, native value supplied to a declarative Action module.
/// Associated values are encoded explicitly so unknown future kinds fail
/// closed instead of being interpreted as text.
public struct ResearchAuthorityEnvelope: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEditablePropertyKeyCount = 64
    public static let maximumPropertyKeyUTF8ByteCount = 128

    public let schemaVersion: Int
    public let readableNotes: [ResearchActionNoteSnapshot]
    public let writableNotes: [ResearchActionNoteSnapshot]
    public let writeOperations: [ResearchDocumentWriteOperation]
    public let editablePropertyKeys: [String]

    public init(
        readableNotes: [ResearchActionNoteSnapshot],
        writableNotes: [ResearchActionNoteSnapshot],
        writeOperations: [ResearchDocumentWriteOperation],
        editablePropertyKeys: [String]
    ) throws {
        let reads = Self.canonicalNotes(readableNotes)
        let writes = Self.canonicalNotes(writableNotes)
        guard reads.count == readableNotes.count,
              writes.count == writableNotes.count else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Authority cannot repeat a note identity."
            )
        }
        guard writes.allSatisfy({ write in
            reads.contains(where: { $0 == write })
        }) else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Every writable note must exactly match one readable identity and revision."
            )
        }
        let operations = Array(Set(writeOperations)).sorted { $0.rawValue < $1.rawValue }
        let propertyKeys = Array(Set(editablePropertyKeys)).sorted()
        if writes.isEmpty {
            guard operations.isEmpty, propertyKeys.isEmpty else {
                throw ResearchActionExecutionContractError.invalidAuthority(
                    "Read-only authority cannot contain write operations or property keys."
                )
            }
        } else {
            guard !operations.isEmpty else {
                throw ResearchActionExecutionContractError.invalidAuthority(
                    "Writable authority requires at least one bounded operation."
                )
            }
        }
        guard operations.contains(.modifyProperties) == !propertyKeys.isEmpty else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Property keys and the modify-properties operation must be frozen together."
            )
        }
        guard propertyKeys.count <= Self.maximumEditablePropertyKeyCount,
              propertyKeys.allSatisfy({ key in
                  !key.isEmpty
                      && key.utf8.count
                          <= Self.maximumPropertyKeyUTF8ByteCount
                      && !key.unicodeScalars.contains(where: {
                          CharacterSet.controlCharacters.contains($0)
                      })
                      && !PropertyContractCatalog.isProtectedMachineKey(key)
              }) else {
            throw ResearchActionExecutionContractError.invalidAuthority(
                "Editable property keys exceed their bounded, nonprotected contract."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.readableNotes = reads
        self.writableNotes = writes
        self.writeOperations = operations
        self.editablePropertyKeys = propertyKeys
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case readableNotes = "readable_notes"
        case writableNotes = "writable_notes"
        case writeOperations = "write_operations"
        case editablePropertyKeys = "editable_property_keys"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionContractError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            readableNotes: container.decode(
                [ResearchActionNoteSnapshot].self,
                forKey: .readableNotes
            ),
            writableNotes: container.decode(
                [ResearchActionNoteSnapshot].self,
                forKey: .writableNotes
            ),
            writeOperations: container.decode(
                [ResearchDocumentWriteOperation].self,
                forKey: .writeOperations
            ),
            editablePropertyKeys: container.decode(
                [String].self,
                forKey: .editablePropertyKeys
            )
        )
    }

    private static func canonicalNotes(
        _ notes: [ResearchActionNoteSnapshot]
    ) -> [ResearchActionNoteSnapshot] {
        var seen: Set<UUID> = []
        return notes
            .sorted { $0.noteID.uuidString < $1.noteID.uuidString }
            .filter { seen.insert($0.noteID).inserted }
    }
}

/// Complete resolved Profile plus its exact semantic and storage revisions.
public struct ResearchActionResolvedProfileSnapshot: Codable, Hashable, Sendable {
    public let profile: ResearchAcademicActionProfile
    public let profileRevision: DocumentFingerprint
    public let profileDocumentRevision: DocumentFingerprint

    public init(
        profile: ResearchAcademicActionProfile,
        profileRevision: DocumentFingerprint,
        profileDocumentRevision: DocumentFingerprint
    ) throws {
        guard profileRevision == (try profile.contentRevision()) else {
            throw ResearchActionExecutionContractError.invalidProfileRevision
        }
        self.profile = profile
        self.profileRevision = profileRevision
        self.profileDocumentRevision = profileDocumentRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case profile
        case profileRevision = "profile_revision"
        case profileDocumentRevision = "profile_document_revision"
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profile: container.decode(ResearchAcademicActionProfile.self, forKey: .profile),
            profileRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .profileRevision
            ),
            profileDocumentRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .profileDocumentRevision
            )
        )
    }
}

public enum ResearchActionRepairReasonCode: String, Codable, Hashable, Sendable {
    case targetUnavailable = "target_unavailable"
    case targetChanged = "target_changed"
    case targetIdentityChanged = "target_identity_changed"
    case invalidTargetRole = "invalid_target_role"
    case inactiveTarget = "inactive_target"
    case sourceAccessRequired = "source_access_required"
    case methodMissing = "method_missing"
    case methodDisabled = "method_disabled"
    case methodInvalid = "method_invalid"
    case profileInvalid = "profile_invalid"
    case unsupportedCapability = "unsupported_capability"
}

public struct ResearchActionRepairReason: Codable, Hashable, Sendable {
    public let code: ResearchActionRepairReasonCode
    public let sourceAccessFailure: ResearchSourceAccessFailure?

    public init(
        code: ResearchActionRepairReasonCode,
        sourceAccessFailure: ResearchSourceAccessFailure? = nil
    ) {
        self.code = code
        self.sourceAccessFailure = sourceAccessFailure
    }
}

/// Non-authorizing Action row resolved against current configuration.
/// Preparation always resolves again; this value cannot be replayed as a
/// grant after a Profile, Skill, Target, or permission change.
public struct ResearchActionAvailability: Codable, Hashable, Identifiable, Sendable {
    public let definition: ResearchActionDefinition
    public let buttonName: String
    public let order: Int
    public let profile: ResearchActionResolvedProfileSnapshot
    public let isEnabled: Bool
    public let repairReasons: [ResearchActionRepairReason]

    public var id: ResearchActionID { definition.id }

    public init(
        definition: ResearchActionDefinition,
        buttonName: String,
        order: Int,
        profile: ResearchActionResolvedProfileSnapshot,
        isEnabled: Bool,
        repairReasons: [ResearchActionRepairReason] = []
    ) {
        self.definition = definition
        self.buttonName = buttonName
        self.order = order
        self.profile = profile
        self.isEnabled = isEnabled
        self.repairReasons = repairReasons
    }
}

/// Delivery-neutral request. The Application resolves the Action, Profile,
/// Method, current source, and authority again before creating a run.
public struct ResearchActionExecutionRequest: Codable, Hashable, Sendable {
    public let actionID: ResearchActionID
    /// The execution semantics presented to the researcher when the sheet was
    /// opened. Application resolution must still match this value before a
    /// run can be created; a changed Profile cannot silently turn a read-only
    /// sheet into a write-capable preparation.
    public let expectedExecutionKind: ResearchActionExecutionKind
    /// Exact semantic Profile revision shown by the sheet. This is a
    /// capability digest: changing read/write scope, property authority, or
    /// any other Profile field invalidates the presentation even when the
    /// execution kind is unchanged.
    public let expectedProfileRevision: DocumentFingerprint
    /// Exact Profile-document revision shown by a researcher-owned Action.
    /// Application defaults have no backing document and therefore use nil.
    public let expectedProfileDocumentRevision: DocumentFingerprint?
    public let target: ResearchActionNoteSnapshot
    public let platformInputs: ResearchActionPlatformInputs
    public let academicInputs: ResearchAcademicFieldValues

    public init(
        actionID: ResearchActionID,
        expectedExecutionKind: ResearchActionExecutionKind,
        expectedProfileRevision: DocumentFingerprint,
        expectedProfileDocumentRevision: DocumentFingerprint?,
        target: ResearchActionNoteSnapshot,
        platformInputs: ResearchActionPlatformInputs,
        academicInputs: ResearchAcademicFieldValues
    ) {
        self.actionID = actionID
        self.expectedExecutionKind = expectedExecutionKind
        self.expectedProfileRevision = expectedProfileRevision
        self.expectedProfileDocumentRevision = expectedProfileDocumentRevision
        self.target = target
        self.platformInputs = platformInputs
        self.academicInputs = academicInputs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionID
        case expectedExecutionKind
        case expectedProfileRevision
        case expectedProfileDocumentRevision
        case target
        case platformInputs
        case academicInputs
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionExecutionValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            actionID: try container.decode(ResearchActionID.self, forKey: .actionID),
            expectedExecutionKind: try container.decode(
                ResearchActionExecutionKind.self,
                forKey: .expectedExecutionKind
            ),
            expectedProfileRevision: try container.decode(
                DocumentFingerprint.self,
                forKey: .expectedProfileRevision
            ),
            expectedProfileDocumentRevision: try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .expectedProfileDocumentRevision
            ),
            target: try container.decode(
                ResearchActionNoteSnapshot.self,
                forKey: .target
            ),
            platformInputs: try container.decode(
                ResearchActionPlatformInputs.self,
                forKey: .platformInputs
            ),
            academicInputs: try container.decode(
                ResearchAcademicFieldValues.self,
                forKey: .academicInputs
            )
        )
    }
}

/// Public preparation result. The protected Function remains an internal
/// compatibility mechanism and is therefore absent from this value.
public enum ResearchActionRunState: String, Codable, Hashable, Sendable {
    case prepared
    case awaitingFidelity = "awaiting_fidelity"
    case complete
    case unverified
    case stale
    case cancelled
}

public struct ResearchActionPreparation: Codable, Hashable, Sendable {
    public let snapshot: ResearchActionSnapshot
    public let runID: UUID
    public let instructions: String
    public let state: ResearchActionRunState
    public let derivedRefreshWarning: String?
    public let nextActions: [AgentCommandAction]

    public init(
        snapshot: ResearchActionSnapshot,
        runID: UUID,
        instructions: String,
        state: ResearchActionRunState,
        derivedRefreshWarning: String? = nil,
        nextActions: [AgentCommandAction] = []
    ) {
        self.snapshot = snapshot
        self.runID = runID
        self.instructions = instructions
        self.state = state
        self.derivedRefreshWarning = derivedRefreshWarning
        self.nextActions = nextActions
    }
}


public struct ResearchActionFidelityPreparation: Codable, Hashable, Sendable {
    public let parentRunID: UUID
    public let preparation: ResearchActionPreparation
    public let effectiveRunID: UUID
    public let reusedExistingEvidence: Bool
    public let nextActions: [AgentCommandAction]

    public init(
        parentRunID: UUID,
        preparation: ResearchActionPreparation,
        effectiveRunID: UUID,
        reusedExistingEvidence: Bool,
        nextActions: [AgentCommandAction] = []
    ) {
        self.parentRunID = parentRunID
        self.preparation = preparation
        self.effectiveRunID = effectiveRunID
        self.reusedExistingEvidence = reusedExistingEvidence
        self.nextActions = nextActions
    }
}

public enum ResearchActionExecutionContractError: LocalizedError, Hashable, Sendable {
    case unsupportedField(String)
    case unknownParameter(String)
    case invalidParameter(String)
    case invalidAuthority(String)
    case invalidProfileRevision
    case actionUnavailable(ResearchActionID)
    case staleResolution

    public var errorDescription: String? {
        switch self {
        case .unsupportedField(let field):
            "Unsupported Research Action execution field: \(field)."
        case .unknownParameter(let id):
            "The Action request contains an unknown parameter: \(id)."
        case .invalidParameter(let reason):
            "The Action request contains an invalid parameter. \(reason)"
        case .invalidAuthority(let reason):
            "The Action authority envelope is invalid. \(reason)"
        case .invalidProfileRevision:
            "The resolved Action Profile origin and storage revision do not match."
        case .actionUnavailable(let actionID):
            "Action \(actionID.rawValue) is not currently available."
        case .staleResolution:
            "The Action, Method, Profile, Target, or authority changed during preparation."
        }
    }
}

enum ResearchActionExecutionValidation {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let raw = try decoder.container(keyedBy: ResearchActionExecutionAnyCodingKey.self)
        let permitted = Set(allowed)
        if let unknown = raw.allKeys.map(\.stringValue).sorted()
            .first(where: { !permitted.contains($0) }) {
            throw ResearchActionExecutionContractError.unsupportedField(unknown)
        }
    }
}

private struct ResearchActionExecutionAnyCodingKey: CodingKey {
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
