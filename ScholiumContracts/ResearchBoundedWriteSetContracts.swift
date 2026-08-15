import Foundation

/// The closed document mutations that the Platform can authorize for one
/// exact Bounded Write Set member. Method/Profile prose cannot add cases.
public enum ResearchDocumentWriteOperation: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case createNote = "create_note"
    case modifyMarkdown = "modify_markdown"
    case modifyProperties = "modify_properties"
    case setZoteroBinding = "set_zotero_binding"
    case clearZoteroBinding = "clear_zotero_binding"

    public var isZoteroBindingOperation: Bool {
        self == .setZoteroBinding || self == .clearZoteroBinding
    }
}

public struct ResearchWriteTargetHandle: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard (20...96).contains(rawValue.utf8.count),
              rawValue.unicodeScalars.allSatisfy({ scalar in
                  (48...57).contains(scalar.value)
                      || (65...90).contains(scalar.value)
                      || (97...122).contains(scalar.value)
                      || scalar == "-" || scalar == "_"
              }) else { return nil }
        self.rawValue = rawValue
    }

    public init(runID: UUID, noteID: UUID) {
        rawValue = String(DocumentFingerprint(
            content: "\(runID.uuidString.lowercased()):write-target:\(noteID.uuidString.lowercased())"
        ).sha256.prefix(40))
    }
}

public enum ResearchWriteSetAuthorizationBasis: String, Codable, Hashable, Sendable {
    case initialAction = "initial_action"
    case explicitResearcherDecision = "explicit_researcher_decision"
    case collaborationPolicy = "collaboration_policy"
}

public enum ResearchWriteSetEntryState: String, Codable, Hashable, Sendable {
    case ready
    case writing
    case consumed
    case stale
    case conflict
    case recoveryRequired = "recovery_required"
    case abandoned
}

public enum ResearchWriteSetTargetExpectation: Codable, Hashable, Sendable {
    case existing(expectedRevision: DocumentFingerprint)
    case absent(settingsRevision: SettingsRevision)
    case created(
        settingsRevision: SettingsRevision,
        committedRevision: DocumentFingerprint
    )

    public var expectedRevision: DocumentFingerprint? {
        switch self {
        case .existing(let revision): revision
        case .created(_, let revision): revision
        case .absent: nil
        }
    }

    public var settingsRevision: SettingsRevision? {
        switch self {
        case .absent(let revision), .created(let revision, _): revision
        case .existing: nil
        }
    }
}

/// One canonical field the Agent may supply while creating an Analysis of a
/// particular source type. This projection deliberately excludes seed bytes,
/// Settings revisions, reserved identities, and values already supplied by
/// the researcher-owned seed.
public struct ResearchAnalysisCreationFieldPlan: Codable, Hashable, Sendable {
    public let key: String
    public let valueKind: PropertyValueKind
    public let allowedValues: [String]?
    public let isRequired: Bool

    public init(
        key: String,
        valueKind: PropertyValueKind,
        allowedValues: [String]? = nil,
        isRequired: Bool
    ) throws {
        guard let contract = PropertyContractCatalog.contract(
            for: key,
            profile: .analysis
        ), contract.valueKind == valueKind,
              contract.allowedValues == allowedValues else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.key = key
        self.valueKind = valueKind
        self.allowedValues = allowedValues
        self.isRequired = isRequired
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case valueKind = "value_kind"
        case allowedValues = "allowed_values"
        case isRequired = "is_required"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            valueKind: container.decode(PropertyValueKind.self, forKey: .valueKind),
            allowedValues: container.decodeIfPresent(
                [String].self,
                forKey: .allowedValues
            ),
            isRequired: container.decode(Bool.self, forKey: .isRequired)
        )
    }
}

public struct ResearchAnalysisCreationSourcePlan: Codable, Hashable, Sendable {
    public let sourceType: AnalysisSourceType
    public let fields: [ResearchAnalysisCreationFieldPlan]

    public init(
        sourceType: AnalysisSourceType,
        fields: [ResearchAnalysisCreationFieldPlan]
    ) throws {
        let applicable = Set(
            AnalysisSourceTypeProfileCatalog.profile(for: sourceType).applicableFields
        )
        guard fields.count <= PropertyContractCatalog.analysisCanonicalKeys.count,
              Set(fields.map(\.key)).count == fields.count,
              fields.allSatisfy({ $0.key != "type" && applicable.contains($0.key) }) else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.sourceType = sourceType
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceType = "source_type"
        case fields
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceType: container.decode(AnalysisSourceType.self, forKey: .sourceType),
            fields: container.decode(
                [ResearchAnalysisCreationFieldPlan].self,
                forKey: .fields
            )
        )
    }
}

public struct ResearchPropertyWriteFieldPlan: Codable, Hashable, Sendable {
    public let key: String
    public let valueKind: PropertyValueKind
    public let allowedValues: [String]?

    public init(
        key: String,
        valueKind: PropertyValueKind,
        allowedValues: [String]? = nil
    ) throws {
        guard ResearchBoundedWriteValidation.validPropertyKey(key),
              allowedValues.map({ values in
                  !values.isEmpty && Set(values).count == values.count
                      && values.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 })
              }) ?? true else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.key = key
        self.valueKind = valueKind
        self.allowedValues = allowedValues
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case valueKind = "value_kind"
        case allowedValues = "allowed_values"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            key: container.decode(String.self, forKey: .key),
            valueKind: container.decode(PropertyValueKind.self, forKey: .valueKind),
            allowedValues: container.decodeIfPresent(
                [String].self,
                forKey: .allowedValues
            )
        )
    }
}

/// One current document member. It contains no source bytes or academic
/// relation and never authorizes access without the owning Run Session.
public struct ResearchBoundedWriteSetEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchWriteTargetHandle { handle }

    public let handle: ResearchWriteTargetHandle
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let allowedOperations: [ResearchDocumentWriteOperation]
    public let allowedPropertyKeys: [String]
    public let propertyWritePlans: [ResearchPropertyWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public var expectation: ResearchWriteSetTargetExpectation
    public let authorizationBasis: ResearchWriteSetAuthorizationBasis
    public let authorizationPolicy: ResearchCollaborationPolicy?
    public let policyRevision: DocumentFingerprint?
    public let expiresAt: Date
    public var state: ResearchWriteSetEntryState
    public var zoteroBindingsRevision: DocumentFingerprint?

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        allowedOperations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint,
        allowedPropertyKeys: [String] = [],
        propertyWritePlans: [ResearchPropertyWriteFieldPlan] = [],
        zoteroBindingsRevision: DocumentFingerprint? = nil,
        authorizationBasis: ResearchWriteSetAuthorizationBasis,
        authorizationPolicy: ResearchCollaborationPolicy? = nil,
        policyRevision: DocumentFingerprint? = nil,
        expiresAt: Date,
        state: ResearchWriteSetEntryState = .ready
    ) throws {
        let operations = Array(Set(allowedOperations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let propertyKeys = Array(Set(allowedPropertyKeys)).sorted()
        let propertyPlans = propertyWritePlans.sorted { $0.key < $1.key }
        let includesZoteroBinding = operations.contains(where: \.isZoteroBindingOperation)
        guard !operations.isEmpty,
              operations.count == allowedOperations.count,
              operations.contains(.createNote) == false,
              operations.contains(.modifyProperties) == !propertyKeys.isEmpty,
              propertyKeys == propertyPlans.map(\.key),
              includesZoteroBinding == (zoteroBindingsRevision != nil),
              !includesZoteroBinding || role == .analysis,
              zoteroBindingsRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              (authorizationBasis == .collaborationPolicy)
                == (authorizationPolicy != nil && policyRevision != nil),
              policyRevision.map(ResearchBoundedWriteValidation.validFingerprint) ?? true,
              state != .consumed else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allowedOperations = operations
        self.allowedPropertyKeys = propertyKeys
        self.propertyWritePlans = propertyPlans
        analysisCreationPlans = []
        expectation = .existing(expectedRevision: expectedRevision)
        self.authorizationBasis = authorizationBasis
        self.authorizationPolicy = authorizationPolicy
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
        self.state = state
        self.zoteroBindingsRevision = zoteroBindingsRevision
    }

    public init(
        handle: ResearchWriteTargetHandle,
        reservedNoteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        settingsRevision: SettingsRevision,
        analysisCreationPlans: [ResearchAnalysisCreationSourcePlan] = [],
        authorizationBasis: ResearchWriteSetAuthorizationBasis,
        authorizationPolicy: ResearchCollaborationPolicy? = nil,
        policyRevision: DocumentFingerprint? = nil,
        expiresAt: Date,
        state: ResearchWriteSetEntryState = .ready
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              !title.isEmpty,
              title.utf8.count <= 1_024,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              (authorizationBasis == .collaborationPolicy)
                == (authorizationPolicy != nil && policyRevision != nil),
              policyRevision.map(ResearchBoundedWriteValidation.validFingerprint) ?? true,
              state != .consumed,
              (role == .analysis)
                == (Set(analysisCreationPlans.map(\.sourceType))
                    == Set(AnalysisSourceType.allCases)) else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        noteID = reservedNoteID
        self.note = note
        self.role = role
        self.title = title
        allowedOperations = [.createNote]
        allowedPropertyKeys = []
        propertyWritePlans = []
        self.analysisCreationPlans = analysisCreationPlans.sorted {
            $0.sourceType.rawValue < $1.sourceType.rawValue
        }
        expectation = .absent(settingsRevision: settingsRevision)
        self.authorizationBasis = authorizationBasis
        self.authorizationPolicy = authorizationPolicy
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
        self.state = state
        zoteroBindingsRevision = nil
    }

    public var expectedRevision: DocumentFingerprint? {
        get { expectation.expectedRevision }
        set {
            guard let newValue, case .existing = expectation else { return }
            expectation = .existing(expectedRevision: newValue)
        }
    }

    public var settingsRevision: SettingsRevision? { expectation.settingsRevision }
    public var expectsAbsence: Bool {
        if case .absent = expectation { return true }
        return false
    }

    public var wasCreated: Bool {
        if case .created = expectation { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case noteID = "note_id"
        case note, role, title
        case allowedOperations = "allowed_operations"
        case allowedPropertyKeys = "allowed_property_keys"
        case propertyWritePlans = "property_write_plans"
        case analysisCreationPlans = "analysis_creation_plans"
        case expectation
        case authorizationBasis = "authorization_basis"
        case authorizationPolicy = "authorization_policy"
        case policyRevision = "policy_revision"
        case expiresAt = "expires_at"
        case state
        case zoteroBindingsRevision = "zotero_bindings_revision"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let handle = try container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .handle
            )
        let noteID = try container.decode(UUID.self, forKey: .noteID)
        let note = try container.decode(VaultQualifiedNoteID.self, forKey: .note)
        let role = try container.decode(ResearchActionTargetRole.self, forKey: .role)
        let title = try container.decode(String.self, forKey: .title)
        let operations = try container.decode(
            [ResearchDocumentWriteOperation].self,
            forKey: .allowedOperations
        )
        let propertyKeys = try container.decode(
            [String].self,
            forKey: .allowedPropertyKeys
        )
        let propertyWritePlans = try container.decode(
            [ResearchPropertyWriteFieldPlan].self,
            forKey: .propertyWritePlans
        )
        let analysisCreationPlans = try container.decode(
            [ResearchAnalysisCreationSourcePlan].self,
            forKey: .analysisCreationPlans
        )
        let expectation = try container.decode(
            ResearchWriteSetTargetExpectation.self,
            forKey: .expectation
        )
        let basis = try container.decode(
                ResearchWriteSetAuthorizationBasis.self,
                forKey: .authorizationBasis
            )
        let policy = try container.decodeIfPresent(
                ResearchCollaborationPolicy.self,
                forKey: .authorizationPolicy
            )
        let policyRevision = try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .policyRevision
            )
        let expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        let state = try container.decode(ResearchWriteSetEntryState.self, forKey: .state)
        let zoteroBindingsRevision = try container.decodeIfPresent(
            DocumentFingerprint.self,
            forKey: .zoteroBindingsRevision
        )
        switch expectation {
        case .existing(let revision):
            guard analysisCreationPlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                noteID: noteID,
                note: note,
                role: role,
                title: title,
                allowedOperations: operations,
                expectedRevision: revision,
                allowedPropertyKeys: propertyKeys,
                propertyWritePlans: propertyWritePlans,
                zoteroBindingsRevision: zoteroBindingsRevision,
                authorizationBasis: basis,
                authorizationPolicy: policy,
                policyRevision: policyRevision,
                expiresAt: expiresAt,
                state: state
            )
        case .absent(let settingsRevision):
            guard zoteroBindingsRevision == nil,
                  operations == [.createNote], propertyKeys.isEmpty,
                  propertyWritePlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                settingsRevision: settingsRevision,
                analysisCreationPlans: analysisCreationPlans,
                authorizationBasis: basis,
                authorizationPolicy: policy,
                policyRevision: policyRevision,
                expiresAt: expiresAt,
                state: state
            )
        case .created(let settingsRevision, let committedRevision):
            guard zoteroBindingsRevision == nil,
                  operations == [.createNote], propertyKeys.isEmpty,
                  propertyWritePlans.isEmpty,
                  state == .consumed else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                settingsRevision: settingsRevision,
                analysisCreationPlans: analysisCreationPlans,
                authorizationBasis: basis,
                authorizationPolicy: policy,
                policyRevision: policyRevision,
                expiresAt: expiresAt,
                state: .ready
            )
            self.expectation = .created(
                settingsRevision: settingsRevision,
                committedRevision: committedRevision
            )
            self.state = .consumed
        }
    }
}

public struct ResearchBoundedWriteSet: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3
    public static let maximumEntriesPerRequest = 16
    public static let maximumEntriesPerRun = 64
    public static let maximumWritesPerRun = 256
    public static let maximumIntentUTF8ByteCount = 128 * 1_024
    public static let maximumDocumentUTF8ByteCount = 512 * 1_024

    public let schemaVersion: Int
    public let runID: UUID
    public let triptychID: UUID
    public var entries: [ResearchBoundedWriteSetEntry]

    public init(
        runID: UUID,
        triptychID: UUID,
        entries: [ResearchBoundedWriteSetEntry] = []
    ) throws {
        let entries = entries.sorted { $0.handle.rawValue < $1.handle.rawValue }
        guard entries.count <= Self.maximumEntriesPerRun,
              Set(entries.map(\.handle)).count == entries.count,
              Set(entries.map(\.noteID)).count == entries.count,
              Set(entries.map(\.note)).count == entries.count else {
            throw ResearchBoundedWriteSetError.invalidWriteSet
        }
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.triptychID = triptychID
        self.entries = entries
    }

    public func entry(handle: ResearchWriteTargetHandle) -> ResearchBoundedWriteSetEntry? {
        entries.first { $0.handle == handle }
    }

    public func authorizationRevision() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(self))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case triptychID = "triptych_id"
        case entries
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidWriteSet
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchBoundedWriteSetError.invalidWriteSet
        }
        try self.init(
            runID: container.decode(UUID.self, forKey: .runID),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            entries: container.decode(
                [ResearchBoundedWriteSetEntry].self,
                forKey: .entries
            )
        )
    }
}

/// Agent-facing selector. Stable identity and current revision are resolved by
/// Scholium after Session authentication; neither is copied by the Agent.
public struct ResearchWriteSetTargetSelector: Codable, Hashable, Sendable {
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let operations: [ResearchDocumentWriteOperation]
    public let propertyKeys: [String]

    public init(
        role: ResearchActionTargetRole,
        relativePath: String,
        operations: [ResearchDocumentWriteOperation],
        propertyKeys: [String] = []
    ) throws {
        let providedCount = operations.count
        let operations = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        let keys = Array(Set(propertyKeys)).sorted()
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              !operations.isEmpty,
              operations.count == providedCount,
              operations.contains(.createNote) == (operations == [.createNote]),
              operations.contains(.modifyProperties) == !keys.isEmpty,
              !operations.contains(where: \.isZoteroBindingOperation)
                || role == .analysis,
              keys.count == propertyKeys.count,
              keys.count <= ResearchAuthorityEnvelope.maximumEditablePropertyKeyCount,
              keys.allSatisfy(ResearchBoundedWriteValidation.validPropertyKey) else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
        self.role = role
        self.relativePath = relativePath
        self.operations = operations
        self.propertyKeys = keys
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operations
        case propertyKeys = "property_keys"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidIntent
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            operations: container.decode(
                [ResearchDocumentWriteOperation].self,
                forKey: .operations
            ),
            propertyKeys: container.decodeIfPresent(
                [String].self,
                forKey: .propertyKeys
            ) ?? []
        )
    }
}

public struct ResearchWriteSetExtensionIntent: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let targets: [ResearchWriteSetTargetSelector]
    public let academicReason: String

    public init(
        targets: [ResearchWriteSetTargetSelector],
        academicReason: String
    ) throws {
        let canonical = targets.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            return $0.relativePath < $1.relativePath
        }
        let reason = academicReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty,
              canonical.count <= ResearchBoundedWriteSet.maximumEntriesPerRequest,
              Set(canonical.map { "\($0.role.rawValue):\($0.relativePath)" }).count
                == canonical.count,
              !reason.isEmpty,
              reason.utf8.count <= 16 * 1_024 else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
        schemaVersion = Self.currentSchemaVersion
        self.targets = canonical
        self.academicReason = reason
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard (try? encoder.encode(self).count) ?? .max
                <= ResearchBoundedWriteSet.maximumIntentUTF8ByteCount else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case targets
        case academicReason = "academic_reason"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidIntent
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
        try self.init(
            targets: container.decode(
                [ResearchWriteSetTargetSelector].self,
                forKey: .targets
            ),
            academicReason: container.decode(String.self, forKey: .academicReason)
        )
    }
}

public enum ResearchWriteSetCandidateExpectation: Codable, Hashable, Sendable {
    case existing(expectedRevision: DocumentFingerprint)
    case absent(settingsRevision: SettingsRevision)
}

public struct ResearchWriteSetCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchWriteTargetHandle { handle }

    public let handle: ResearchWriteTargetHandle
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let operations: [ResearchDocumentWriteOperation]
    public let propertyKeys: [String]
    public let propertyWritePlans: [ResearchPropertyWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public let expectation: ResearchWriteSetCandidateExpectation
    public let zoteroBindingsRevision: DocumentFingerprint?

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        operations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint,
        propertyKeys: [String] = [],
        propertyWritePlans: [ResearchPropertyWriteFieldPlan] = [],
        zoteroBindingsRevision: DocumentFingerprint? = nil
    ) throws {
        let canonicalOperations = Array(Set(operations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let propertyKeys = Array(Set(propertyKeys)).sorted()
        let propertyPlans = propertyWritePlans.sorted { $0.key < $1.key }
        let includesZoteroBinding = canonicalOperations.contains(
            where: \.isZoteroBindingOperation
        )
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !canonicalOperations.isEmpty,
              canonicalOperations.count == operations.count,
              !canonicalOperations.contains(.createNote),
              canonicalOperations.contains(.modifyProperties) == !propertyKeys.isEmpty,
              propertyKeys == propertyPlans.map(\.key),
              includesZoteroBinding == (zoteroBindingsRevision != nil),
              !includesZoteroBinding || role == .analysis,
              zoteroBindingsRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              !title.isEmpty,
              title.utf8.count <= 1_024 else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title
        self.operations = canonicalOperations
        self.propertyKeys = propertyKeys
        self.propertyWritePlans = propertyPlans
        analysisCreationPlans = []
        expectation = .existing(expectedRevision: expectedRevision)
        self.zoteroBindingsRevision = zoteroBindingsRevision
    }

    public init(
        handle: ResearchWriteTargetHandle,
        reservedNoteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        settingsRevision: SettingsRevision,
        analysisCreationPlans: [ResearchAnalysisCreationSourcePlan] = []
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              !title.isEmpty,
              title.utf8.count <= 1_024,
              (role == .analysis)
                == (Set(analysisCreationPlans.map(\.sourceType))
                    == Set(AnalysisSourceType.allCases)) else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        noteID = reservedNoteID
        self.note = note
        self.role = role
        self.title = title
        operations = [.createNote]
        propertyKeys = []
        propertyWritePlans = []
        self.analysisCreationPlans = analysisCreationPlans.sorted {
            $0.sourceType.rawValue < $1.sourceType.rawValue
        }
        expectation = .absent(settingsRevision: settingsRevision)
        zoteroBindingsRevision = nil
    }

    public var expectedRevision: DocumentFingerprint? {
        guard case .existing(let revision) = expectation else { return nil }
        return revision
    }

    public var settingsRevision: SettingsRevision? {
        guard case .absent(let revision) = expectation else { return nil }
        return revision
    }

    public var expectsAbsence: Bool { settingsRevision != nil }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case noteID = "note_id"
        case note, role, title, operations
        case propertyKeys = "property_keys"
        case propertyWritePlans = "property_write_plans"
        case analysisCreationPlans = "analysis_creation_plans"
        case expectation
        case zoteroBindingsRevision = "zotero_bindings_revision"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let handle = try container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .handle
            )
        let noteID = try container.decode(UUID.self, forKey: .noteID)
        let note = try container.decode(VaultQualifiedNoteID.self, forKey: .note)
        let role = try container.decode(ResearchActionTargetRole.self, forKey: .role)
        let title = try container.decode(String.self, forKey: .title)
        let operations = try container.decode(
            [ResearchDocumentWriteOperation].self,
            forKey: .operations
        )
        let propertyKeys = try container.decode(
            [String].self,
            forKey: .propertyKeys
        )
        let propertyWritePlans = try container.decode(
            [ResearchPropertyWriteFieldPlan].self,
            forKey: .propertyWritePlans
        )
        let analysisCreationPlans = try container.decode(
            [ResearchAnalysisCreationSourcePlan].self,
            forKey: .analysisCreationPlans
        )
        let zoteroBindingsRevision = try container.decodeIfPresent(
            DocumentFingerprint.self,
            forKey: .zoteroBindingsRevision
        )
        switch try container.decode(
            ResearchWriteSetCandidateExpectation.self,
            forKey: .expectation
        ) {
        case .existing(let revision):
            guard analysisCreationPlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                noteID: noteID,
                note: note,
                role: role,
                title: title,
                operations: operations,
                expectedRevision: revision,
                propertyKeys: propertyKeys,
                propertyWritePlans: propertyWritePlans,
                zoteroBindingsRevision: zoteroBindingsRevision
            )
        case .absent(let settingsRevision):
            guard zoteroBindingsRevision == nil,
                  operations == [.createNote], propertyKeys.isEmpty,
                  propertyWritePlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                settingsRevision: settingsRevision,
                analysisCreationPlans: analysisCreationPlans
            )
        }
    }
}

public enum ResearchWriteSetExtensionState: String, Codable, Hashable, Sendable {
    case pending
    case allowedSubset = "allowed_subset"
    case continueWithoutChanges = "continue_without_changes"
    case stale
    case expired
    case cancelled
}

public struct ResearchWriteSetExtensionRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let intent: ResearchWriteSetExtensionIntent
    public let intentDigest: DocumentFingerprint
    public let candidates: [ResearchWriteSetCandidate]
    public let policy: ResearchCollaborationPolicy
    public let policyRevision: DocumentFingerprint
    public var state: ResearchWriteSetExtensionState
    public var allowedHandles: [ResearchWriteTargetHandle]
    public let receivedAt: Date
    public let expiresAt: Date
    public var decidedAt: Date?

    public var isUnresolved: Bool { state == .pending }

    public init(
        id: UUID,
        runID: UUID,
        triptychID: UUID,
        intent: ResearchWriteSetExtensionIntent,
        intentDigest: DocumentFingerprint,
        candidates: [ResearchWriteSetCandidate],
        policy: ResearchCollaborationPolicy,
        policyRevision: DocumentFingerprint,
        state: ResearchWriteSetExtensionState,
        allowedHandles: [ResearchWriteTargetHandle] = [],
        receivedAt: Date,
        expiresAt: Date,
        decidedAt: Date? = nil
    ) throws {
        let candidates = candidates.sorted { $0.handle.rawValue < $1.handle.rawValue }
        let allowed = allowedHandles.sorted { $0.rawValue < $1.rawValue }
        let candidateHandles = Set(candidates.map(\.handle))
        guard !candidates.isEmpty,
              candidates.count <= ResearchBoundedWriteSet.maximumEntriesPerRequest,
              candidateHandles.count == candidates.count,
              Set(allowed).count == allowed.count,
              Set(allowed).isSubset(of: candidateHandles),
              ResearchBoundedWriteValidation.validFingerprint(intentDigest),
              ResearchBoundedWriteValidation.validFingerprint(policyRevision),
              expiresAt > receivedAt,
              expiresAt.timeIntervalSince(receivedAt) <= 30 * 60,
              (state == .allowedSubset) == !allowed.isEmpty,
              (state == .pending) == (decidedAt == nil) else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        self.id = id
        self.runID = runID
        self.triptychID = triptychID
        self.intent = intent
        self.intentDigest = intentDigest
        self.candidates = candidates
        self.policy = policy
        self.policyRevision = policyRevision
        self.state = state
        self.allowedHandles = allowed
        self.receivedAt = receivedAt
        self.expiresAt = expiresAt
        self.decidedAt = decidedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case runID = "run_id"
        case triptychID = "triptych_id"
        case intent
        case intentDigest = "intent_digest"
        case candidates, policy
        case policyRevision = "policy_revision"
        case state
        case allowedHandles = "allowed_handles"
        case receivedAt = "received_at"
        case expiresAt = "expires_at"
        case decidedAt = "decided_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidExtensionRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            runID: container.decode(UUID.self, forKey: .runID),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            intent: container.decode(
                ResearchWriteSetExtensionIntent.self,
                forKey: .intent
            ),
            intentDigest: container.decode(
                DocumentFingerprint.self,
                forKey: .intentDigest
            ),
            candidates: container.decode(
                [ResearchWriteSetCandidate].self,
                forKey: .candidates
            ),
            policy: container.decode(
                ResearchCollaborationPolicy.self,
                forKey: .policy
            ),
            policyRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .policyRevision
            ),
            state: container.decode(
                ResearchWriteSetExtensionState.self,
                forKey: .state
            ),
            allowedHandles: container.decode(
                [ResearchWriteTargetHandle].self,
                forKey: .allowedHandles
            ),
            receivedAt: container.decode(Date.self, forKey: .receivedAt),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            decidedAt: container.decodeIfPresent(Date.self, forKey: .decidedAt)
        )
    }
}

public struct ResearchBoundedWriteSetViewEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(role.rawValue):\(relativePath)" }

    public let title: String
    public let relativePath: String
    public let role: ResearchActionTargetRole
    public let operations: [ResearchDocumentWriteOperation]
    public let propertyKeys: [String]
    public let propertyWritePlans: [ResearchPropertyWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public let state: ResearchWriteSetEntryState
    public let expectsAbsence: Bool

    public init(_ entry: ResearchBoundedWriteSetEntry) {
        title = entry.title
        relativePath = entry.note.relativePath
        role = entry.role
        operations = entry.allowedOperations
        propertyKeys = entry.allowedPropertyKeys
        propertyWritePlans = entry.propertyWritePlans
        analysisCreationPlans = entry.analysisCreationPlans
        state = entry.state
        expectsAbsence = entry.expectsAbsence
    }

    private init(
        title: String,
        relativePath: String,
        role: ResearchActionTargetRole,
        operations: [ResearchDocumentWriteOperation],
        propertyKeys: [String],
        propertyWritePlans: [ResearchPropertyWriteFieldPlan],
        analysisCreationPlans: [ResearchAnalysisCreationSourcePlan],
        state: ResearchWriteSetEntryState,
        expectsAbsence: Bool
    ) throws {
        let canonical = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        let keys = Array(Set(propertyKeys)).sorted()
        let propertyPlans = propertyWritePlans.sorted { $0.key < $1.key }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              ResearchBoundedWriteValidation.validPath(relativePath),
              !canonical.isEmpty,
              canonical.count == operations.count,
              keys.count == propertyKeys.count,
              canonical.contains(.modifyProperties) == !keys.isEmpty,
              keys == propertyPlans.map(\.key),
              (role == .analysis && canonical == [.createNote])
                == (Set(analysisCreationPlans.map(\.sourceType))
                    == Set(AnalysisSourceType.allCases)),
              expectsAbsence == (canonical == [.createNote] && state != .consumed) else {
            throw ResearchBoundedWriteSetError.invalidWriteSet
        }
        self.title = title
        self.relativePath = relativePath
        self.role = role
        self.operations = canonical
        self.propertyKeys = keys
        self.propertyWritePlans = propertyPlans
        self.analysisCreationPlans = analysisCreationPlans
        self.state = state
        self.expectsAbsence = expectsAbsence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case relativePath = "relative_path"
        case role, operations
        case propertyKeys = "property_keys"
        case propertyWritePlans = "property_write_plans"
        case analysisCreationPlans = "analysis_creation_plans"
        case state
        case expectsAbsence = "expects_absence"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidWriteSet
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            title: container.decode(String.self, forKey: .title),
            relativePath: container.decode(String.self, forKey: .relativePath),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            operations: container.decode(
                [ResearchDocumentWriteOperation].self,
                forKey: .operations
            ),
            propertyKeys: container.decode([String].self, forKey: .propertyKeys),
            propertyWritePlans: container.decode(
                [ResearchPropertyWriteFieldPlan].self,
                forKey: .propertyWritePlans
            ),
            analysisCreationPlans: container.decode(
                [ResearchAnalysisCreationSourcePlan].self,
                forKey: .analysisCreationPlans
            ),
            state: container.decode(ResearchWriteSetEntryState.self, forKey: .state),
            expectsAbsence: container.decode(Bool.self, forKey: .expectsAbsence)
        )
    }
}

public struct ResearchWriteSetExtensionResult: Codable, Hashable, Sendable {
    public let requestID: UUID
    public let state: ResearchWriteSetExtensionState
    public let entries: [ResearchBoundedWriteSetViewEntry]
    public let message: String

    public init(
        requestID: UUID,
        state: ResearchWriteSetExtensionState,
        entries: [ResearchBoundedWriteSetViewEntry],
        message: String
    ) {
        self.requestID = requestID
        self.state = state
        self.entries = entries
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case requestID = "request_id"
        case state, entries, message
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidExtensionRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode(
            [ResearchBoundedWriteSetViewEntry].self,
            forKey: .entries
        )
        let message = try container.decode(String.self, forKey: .message)
        guard entries.count <= ResearchBoundedWriteSet.maximumEntriesPerRun,
              Set(entries.map(\.id)).count == entries.count,
              !message.isEmpty,
              message.utf8.count <= 4_096 else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        self.init(
            requestID: try container.decode(UUID.self, forKey: .requestID),
            state: try container.decode(
                ResearchWriteSetExtensionState.self,
                forKey: .state
            ),
            entries: entries,
            message: message
        )
    }
}

public struct ResearchDocumentWriteIntent: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    /// One client-generated attempt identity. Retrying the same intent keeps
    /// this UUID; a materially new write must use a new UUID.
    public let requestID: UUID
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let operation: ResearchDocumentWriteOperation
    /// Body text for `modify_markdown` and `create_note`. It is never complete
    /// document source and cannot carry frontmatter authority.
    public let content: String
    public let properties: [CanonicalPropertyInput]
    public let analysisMetadata: AnalysisCreationMetadata?

    public init(
        requestID: UUID = UUID(),
        role: ResearchActionTargetRole,
        relativePath: String,
        operation: ResearchDocumentWriteOperation = .modifyMarkdown,
        content: String = "",
        properties: [CanonicalPropertyInput] = [],
        analysisMetadata: AnalysisCreationMetadata? = nil
    ) throws {
        let shapeIsValid = switch operation {
        case .createNote:
            properties.isEmpty
        case .modifyMarkdown:
            properties.isEmpty && analysisMetadata == nil
        case .modifyProperties:
            content.isEmpty && !properties.isEmpty && analysisMetadata == nil
        case .setZoteroBinding, .clearZoteroBinding:
            false
        }
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              shapeIsValid,
              !content.unicodeScalars.contains(where: { $0.value == 0 }),
              content.utf8.count <= ResearchBoundedWriteSet
                .maximumDocumentUTF8ByteCount,
              Set(properties.map(\.key)).count == properties.count else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.role = role
        self.relativePath = relativePath
        self.operation = operation
        self.content = content
        self.properties = properties.sorted { $0.key < $1.key }
        self.analysisMetadata = analysisMetadata
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case role
        case relativePath = "relative_path"
        case operation, content, properties
        case analysisMetadata = "analysis_metadata"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidWrite
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        let operation = try container.decode(
            ResearchDocumentWriteOperation.self,
            forKey: .operation
        )
        let content: String
        switch operation {
        case .modifyMarkdown:
            guard container.contains(.content) else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            content = try container.decode(String.self, forKey: .content)
        case .createNote, .modifyProperties,
             .setZoteroBinding, .clearZoteroBinding:
            content = try container.decodeIfPresent(
                String.self,
                forKey: .content
            ) ?? ""
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            operation: operation,
            content: content,
            properties: container.decodeIfPresent(
                [CanonicalPropertyInput].self,
                forKey: .properties
            ) ?? [],
            analysisMetadata: container.decodeIfPresent(
                AnalysisCreationMetadata.self,
                forKey: .analysisMetadata
            )
        )
    }
}

/// A portable Zotero relationship mutation is authorized by one Analysis
/// member, but it is not a Markdown document write. Its payload therefore has
/// no source content, Property values, or document revision.
public struct ResearchZoteroBindingWriteIntent: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestID: UUID
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let operation: ResearchDocumentWriteOperation
    public let library: ZoteroLibraryIdentity?
    public let itemKey: String?

    public init(
        requestID: UUID = UUID(),
        role: ResearchActionTargetRole,
        relativePath: String,
        operation: ResearchDocumentWriteOperation,
        library: ZoteroLibraryIdentity? = nil,
        itemKey: String? = nil
    ) throws {
        let normalizedKey: String?
        switch operation {
        case .setZoteroBinding:
            guard let library, let itemKey else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            normalizedKey = try AnalysisZoteroBinding(
                noteID: UUID(),
                library: library,
                itemKey: itemKey
            ).itemKey
        case .clearZoteroBinding:
            guard library == nil, itemKey == nil else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            normalizedKey = nil
        case .createNote, .modifyMarkdown, .modifyProperties:
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        guard role == .analysis,
              ResearchBoundedWriteValidation.validPath(relativePath) else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.role = role
        self.relativePath = relativePath
        self.operation = operation
        self.library = library
        self.itemKey = normalizedKey
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case role
        case relativePath = "relative_path"
        case operation, library
        case itemKey = "item_key"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidWrite
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            operation: container.decode(
                ResearchDocumentWriteOperation.self,
                forKey: .operation
            ),
            library: container.decodeIfPresent(
                ZoteroLibraryIdentity.self,
                forKey: .library
            ),
            itemKey: container.decodeIfPresent(String.self, forKey: .itemKey)
        )
    }
}

public enum ResearchZoteroBindingWriteState: String, Codable, Hashable, Sendable {
    case writing
    case committed
    case unchanged
    case conflict
    case recoveryRequired = "recovery_required"
    case abandoned
}

/// Machine-local idempotency and recovery evidence for one binding mutation.
/// It contains only the intended stable relationship, never Zotero metadata or
/// research source.
public struct ResearchZoteroBindingWriteRecord: Codable, Hashable, Identifiable,
    Sendable
{
    public let id: UUID
    public let runID: UUID
    public let target: ResearchWriteTargetHandle
    public let operation: ResearchDocumentWriteOperation
    public let requestFingerprint: DocumentFingerprint
    public let expectedRevision: DocumentFingerprint
    public let intendedBinding: AnalysisZoteroBinding?
    public var observedRevision: DocumentFingerprint?
    public var state: ResearchZoteroBindingWriteState
    public let startedAt: Date
    public var finishedAt: Date?
    public var warning: String?

    public init(
        id: UUID,
        runID: UUID,
        target: ResearchWriteTargetHandle,
        operation: ResearchDocumentWriteOperation,
        requestFingerprint: DocumentFingerprint,
        expectedRevision: DocumentFingerprint,
        intendedBinding: AnalysisZoteroBinding?,
        observedRevision: DocumentFingerprint? = nil,
        state: ResearchZoteroBindingWriteState,
        startedAt: Date,
        finishedAt: Date? = nil,
        warning: String? = nil
    ) throws {
        guard operation.isZoteroBindingOperation,
              (operation == .setZoteroBinding) == (intendedBinding != nil),
              ResearchBoundedWriteValidation.validFingerprint(requestFingerprint),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              observedRevision.map(ResearchBoundedWriteValidation.validFingerprint)
                ?? true,
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt.map({
                  $0.timeIntervalSinceReferenceDate.isFinite && $0 >= startedAt
              }) ?? true,
              (state == .writing) == (finishedAt == nil),
              warning.map({ !$0.isEmpty && $0.utf8.count <= 4_096 }) ?? true else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        self.id = id
        self.runID = runID
        self.target = target
        self.operation = operation
        self.requestFingerprint = requestFingerprint
        self.expectedRevision = expectedRevision
        self.intendedBinding = intendedBinding
        self.observedRevision = observedRevision
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case runID = "run_id"
        case target, operation
        case requestFingerprint = "request_fingerprint"
        case expectedRevision = "expected_revision"
        case intendedBinding = "intended_binding"
        case observedRevision = "observed_revision"
        case state
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case warning
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidWriteRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            runID: container.decode(UUID.self, forKey: .runID),
            target: container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .target
            ),
            operation: container.decode(
                ResearchDocumentWriteOperation.self,
                forKey: .operation
            ),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            expectedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedRevision
            ),
            intendedBinding: container.decodeIfPresent(
                AnalysisZoteroBinding.self,
                forKey: .intendedBinding
            ),
            observedRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .observedRevision
            ),
            state: container.decode(
                ResearchZoteroBindingWriteState.self,
                forKey: .state
            ),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            finishedAt: container.decodeIfPresent(Date.self, forKey: .finishedAt),
            warning: container.decodeIfPresent(String.self, forKey: .warning)
        )
    }
}

public struct ResearchZoteroBindingWriteResult: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let state: ResearchZoteroBindingWriteState
    public let target: ResearchBoundedWriteSetViewEntry
    public let message: String
    public let warning: String?

    public init(
        operationID: UUID,
        state: ResearchZoteroBindingWriteState,
        target: ResearchBoundedWriteSetViewEntry,
        message: String,
        warning: String? = nil
    ) {
        self.operationID = operationID
        self.state = state
        self.target = target
        self.message = message
        self.warning = warning
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID = "operation_id"
        case state, target, message, warning
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidWriteRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let message = try container.decode(String.self, forKey: .message)
        let warning = try container.decodeIfPresent(String.self, forKey: .warning)
        guard !message.isEmpty,
              message.utf8.count <= 4_096,
              warning.map({ !$0.isEmpty && $0.utf8.count <= 4_096 }) ?? true else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        self.init(
            operationID: try container.decode(UUID.self, forKey: .operationID),
            state: try container.decode(
                ResearchZoteroBindingWriteState.self,
                forKey: .state
            ),
            target: try container.decode(
                ResearchBoundedWriteSetViewEntry.self,
                forKey: .target
            ),
            message: message,
            warning: warning
        )
    }
}

public enum ResearchDocumentWriteState: String, Codable, Hashable, Sendable {
    case writing
    case committed
    case unchanged
    case conflict
    case recoveryRequired = "recovery_required"
    case abandoned
}

public struct ResearchDocumentWriteRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let target: ResearchWriteTargetHandle
    public let actor: ResearchContextActorClass
    public let operation: ResearchDocumentWriteOperation
    public let requestFingerprint: DocumentFingerprint
    public let expectedRevision: DocumentFingerprint?
    public let intendedRevision: DocumentFingerprint
    public var observedRevision: DocumentFingerprint?
    public var state: ResearchDocumentWriteState
    public let startedAt: Date
    public var finishedAt: Date?
    public var warning: String?
    public var recoveryRecordID: UUID?

    public init(
        id: UUID,
        runID: UUID,
        target: ResearchWriteTargetHandle,
        actor: ResearchContextActorClass,
        operation: ResearchDocumentWriteOperation,
        requestFingerprint: DocumentFingerprint,
        expectedRevision: DocumentFingerprint?,
        intendedRevision: DocumentFingerprint,
        observedRevision: DocumentFingerprint? = nil,
        state: ResearchDocumentWriteState,
        startedAt: Date,
        finishedAt: Date? = nil,
        warning: String? = nil,
        recoveryRecordID: UUID? = nil
    ) throws {
        let expectationShapeIsValid: Bool
        switch operation {
        case .createNote:
            expectationShapeIsValid = expectedRevision == nil
        case .modifyMarkdown, .modifyProperties:
            expectationShapeIsValid = expectedRevision != nil
        case .setZoteroBinding, .clearZoteroBinding:
            expectationShapeIsValid = false
        }
        guard actor == .agent,
              ResearchBoundedWriteValidation.validFingerprint(requestFingerprint),
              expectedRevision.map(ResearchBoundedWriteValidation.validFingerprint) ?? true,
              ResearchBoundedWriteValidation.validFingerprint(intendedRevision),
              observedRevision.map(ResearchBoundedWriteValidation.validFingerprint)
                ?? true,
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt.map({
                  $0.timeIntervalSinceReferenceDate.isFinite && $0 >= startedAt
              }) ?? true,
              (state == .writing) == (finishedAt == nil),
              recoveryRecordID == nil
                || state == .recoveryRequired
                || (finishedAt != nil && [.committed, .abandoned].contains(state)),
              warning.map({ $0.utf8.count <= 4_096 }) ?? true,
              expectationShapeIsValid else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        self.id = id
        self.runID = runID
        self.target = target
        self.actor = actor
        self.operation = operation
        self.requestFingerprint = requestFingerprint
        self.expectedRevision = expectedRevision
        self.intendedRevision = intendedRevision
        self.observedRevision = observedRevision
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.warning = warning
        self.recoveryRecordID = recoveryRecordID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case runID = "run_id"
        case target, actor, operation
        case requestFingerprint = "request_fingerprint"
        case expectedRevision = "expected_revision"
        case intendedRevision = "intended_revision"
        case observedRevision = "observed_revision"
        case state
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case warning
        case recoveryRecordID = "recovery_record_id"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidWriteRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            runID: container.decode(UUID.self, forKey: .runID),
            target: container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .target
            ),
            actor: container.decode(
                ResearchContextActorClass.self,
                forKey: .actor
            ),
            operation: container.decode(
                ResearchDocumentWriteOperation.self,
                forKey: .operation
            ),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            expectedRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .expectedRevision
            ),
            intendedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .intendedRevision
            ),
            observedRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .observedRevision
            ),
            state: container.decode(
                ResearchDocumentWriteState.self,
                forKey: .state
            ),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            finishedAt: container.decodeIfPresent(Date.self, forKey: .finishedAt),
            warning: container.decodeIfPresent(String.self, forKey: .warning),
            recoveryRecordID: container.decodeIfPresent(
                UUID.self,
                forKey: .recoveryRecordID
            )
        )
    }
}

public struct ResearchDocumentWriteResult: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let state: ResearchDocumentWriteState
    public let target: ResearchBoundedWriteSetViewEntry
    public let message: String
    public let warning: String?
    public let recoveryRecordID: UUID?

    public init(
        operationID: UUID,
        state: ResearchDocumentWriteState,
        target: ResearchBoundedWriteSetViewEntry,
        message: String,
        warning: String? = nil,
        recoveryRecordID: UUID? = nil
    ) {
        self.operationID = operationID
        self.state = state
        self.target = target
        self.message = message
        self.warning = warning
        self.recoveryRecordID = recoveryRecordID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID = "operation_id"
        case state, target, message, warning
        case recoveryRecordID = "recovery_record_id"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: ResearchBoundedWriteSetError.invalidWriteRecord
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let message = try container.decode(String.self, forKey: .message)
        guard !message.isEmpty, message.utf8.count <= 4_096 else {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        let warning = try container.decodeIfPresent(String.self, forKey: .warning)
        if let warning,
           warning.isEmpty || warning.utf8.count > 4_096 {
            throw ResearchBoundedWriteSetError.invalidWriteRecord
        }
        self.init(
            operationID: try container.decode(UUID.self, forKey: .operationID),
            state: try container.decode(
                ResearchDocumentWriteState.self,
                forKey: .state
            ),
            target: try container.decode(
                ResearchBoundedWriteSetViewEntry.self,
                forKey: .target
            ),
            message: message,
            warning: warning,
            recoveryRecordID: try container.decodeIfPresent(
                UUID.self,
                forKey: .recoveryRecordID
            )
        )
    }
}

public enum ResearchWriteConflictResolutionAction: String, Codable, Hashable,
    Sendable
{
    case refreshAuthority = "refresh_authority"
    case abandonWrite = "abandon_write"
}

public enum ResearchWriteConflictResolutionState: String, Codable, Hashable,
    Sendable
{
    case readyToRetry = "ready_to_retry"
    case abandoned
}

/// One explicit decision for a single conflicted write-set member. The client
/// request identity is hidden by the CLI; it is persisted only so transport
/// retries cannot create duplicate change-evidence records or decisions.
public struct ResearchWriteConflictResolutionIntent: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let requestID: UUID
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let action: ResearchWriteConflictResolutionAction

    public init(
        requestID: UUID = UUID(),
        role: ResearchActionTargetRole,
        relativePath: String,
        action: ResearchWriteConflictResolutionAction
    ) throws {
        guard ResearchBoundedWriteValidation.validPath(relativePath) else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.role = role
        self.relativePath = relativePath
        self.action = action
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case role
        case relativePath = "relative_path"
        case action
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidConflictResolution
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            action: container.decode(
                ResearchWriteConflictResolutionAction.self,
                forKey: .action
            )
        )
    }
}

/// Machine-local evidence for one refresh or abandonment. It records no
/// Markdown bytes and does not become a second document authority.
public struct ResearchWriteConflictResolutionRecord: Codable, Hashable,
    Identifiable, Sendable
{
    public let id: UUID
    public let clientRequestID: UUID
    public let runID: UUID
    public let target: ResearchWriteTargetHandle
    public let conflictOperationID: UUID
    public let action: ResearchWriteConflictResolutionAction
    public let requestFingerprint: DocumentFingerprint
    public let priorExpectedRevision: DocumentFingerprint
    public let observedRevision: DocumentFingerprint
    public let state: ResearchWriteConflictResolutionState
    public let resolvedAt: Date

    public init(
        id: UUID,
        clientRequestID: UUID,
        runID: UUID,
        target: ResearchWriteTargetHandle,
        conflictOperationID: UUID,
        action: ResearchWriteConflictResolutionAction,
        requestFingerprint: DocumentFingerprint,
        priorExpectedRevision: DocumentFingerprint,
        observedRevision: DocumentFingerprint,
        state: ResearchWriteConflictResolutionState,
        resolvedAt: Date
    ) throws {
        let shapeIsValid = switch (action, state) {
        case (.refreshAuthority, .readyToRetry),
             (.abandonWrite, .abandoned):
            true
        default:
            false
        }
        guard ResearchBoundedWriteValidation.validFingerprint(requestFingerprint),
              ResearchBoundedWriteValidation.validFingerprint(priorExpectedRevision),
              ResearchBoundedWriteValidation.validFingerprint(observedRevision),
              resolvedAt.timeIntervalSinceReferenceDate.isFinite,
              shapeIsValid else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
        }
        self.id = id
        self.clientRequestID = clientRequestID
        self.runID = runID
        self.target = target
        self.conflictOperationID = conflictOperationID
        self.action = action
        self.requestFingerprint = requestFingerprint
        self.priorExpectedRevision = priorExpectedRevision
        self.observedRevision = observedRevision
        self.state = state
        self.resolvedAt = resolvedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case clientRequestID = "client_request_id"
        case runID = "run_id"
        case target
        case conflictOperationID = "conflict_operation_id"
        case action
        case requestFingerprint = "request_fingerprint"
        case priorExpectedRevision = "prior_expected_revision"
        case observedRevision = "observed_revision"
        case state
        case resolvedAt = "resolved_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidConflictResolution
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            clientRequestID: container.decode(UUID.self, forKey: .clientRequestID),
            runID: container.decode(UUID.self, forKey: .runID),
            target: container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .target
            ),
            conflictOperationID: container.decode(
                UUID.self,
                forKey: .conflictOperationID
            ),
            action: container.decode(
                ResearchWriteConflictResolutionAction.self,
                forKey: .action
            ),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            priorExpectedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .priorExpectedRevision
            ),
            observedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .observedRevision
            ),
            state: container.decode(
                ResearchWriteConflictResolutionState.self,
                forKey: .state
            ),
            resolvedAt: container.decode(Date.self, forKey: .resolvedAt)
        )
    }
}

public struct ResearchWriteConflictResolutionResult: Codable, Hashable, Sendable {
    public let operationID: UUID
    public let state: ResearchWriteConflictResolutionState
    public let target: ResearchBoundedWriteSetViewEntry
    public let message: String

    public init(
        operationID: UUID,
        state: ResearchWriteConflictResolutionState,
        target: ResearchBoundedWriteSetViewEntry,
        message: String
    ) throws {
        guard !message.isEmpty, message.utf8.count <= 4_096 else {
            throw ResearchBoundedWriteSetError.invalidConflictResolution
        }
        self.operationID = operationID
        self.state = state
        self.target = target
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case operationID = "operation_id"
        case state, target, message
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidConflictResolution
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            operationID: container.decode(UUID.self, forKey: .operationID),
            state: container.decode(
                ResearchWriteConflictResolutionState.self,
                forKey: .state
            ),
            target: container.decode(
                ResearchBoundedWriteSetViewEntry.self,
                forKey: .target
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public enum ResearchBoundedWriteSetError: LocalizedError, Hashable, Sendable {
    case invalidEntry
    case invalidWriteSet
    case invalidIntent
    case invalidExtensionRecord
    case invalidWrite
    case invalidWriteRecord
    case invalidConflictResolution
    case limitExceeded
    case targetUnavailable
    case targetNotAuthorized
    case operationNotAuthorized
    case requestPending
    case staleAuthorization
    case recoveryRequired

    public var errorDescription: String? {
        switch self {
        case .invalidEntry: "A bounded write-set entry is invalid."
        case .invalidWriteSet: "The Run's bounded write set is invalid."
        case .invalidIntent: "The write-set extension request is invalid."
        case .invalidExtensionRecord: "The write-set decision record is invalid."
        case .invalidWrite: "The document write request is invalid or too large."
        case .invalidWriteRecord: "The document write transaction record is invalid."
        case .invalidConflictResolution: "The write-conflict resolution is invalid."
        case .limitExceeded: "The bounded write-set limit was reached; extend it in a smaller request."
        case .targetUnavailable: "The requested document is unavailable or does not match its stable identity."
        case .targetNotAuthorized: "The document is not a current member of this Run's bounded write set."
        case .operationNotAuthorized: "The requested operation is outside this document's bounded authority."
        case .requestPending: "This write-set extension is waiting for the researcher's decision."
        case .staleAuthorization: "The document revision or collaboration authorization changed."
        case .recoveryRequired: "The write result is not yet known; resolve its recovery state before continuing."
        }
    }
}

private enum ResearchBoundedWriteValidation {
    static func validFingerprint(_ value: DocumentFingerprint) -> Bool {
        value.byteCount >= 0
            && value.sha256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
            ) != nil
    }

    static func validPath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 4_096,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    static func validPropertyKey(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count
                <= ResearchAuthorityEnvelope.maximumPropertyKeyUTF8ByteCount
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }
}

private enum ResearchBoundedWriteCoding {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>,
        error: ResearchBoundedWriteSetError
    ) throws {
        let raw = try decoder.container(keyedBy: ResearchBoundedWriteCodingKey.self)
        let permitted = Set(allowed)
        guard raw.allKeys.allSatisfy({ permitted.contains($0.stringValue) }) else {
            throw error
        }
    }
}

private struct ResearchBoundedWriteCodingKey: CodingKey {
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
