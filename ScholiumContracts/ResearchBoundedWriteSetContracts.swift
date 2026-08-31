import Foundation

/// The closed document mutations that Scholium can perform and attribute to
/// one Agent Run. Skill/Profile prose cannot add executable cases.
public enum ResearchDocumentWriteOperation: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case createNote = "create_note"
    case modifyMarkdown = "modify_markdown"
    case modifySource = "modify_source"
    case modifyMetadata = "modify_metadata"
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

public enum ResearchWriteSetActivityOrigin: String, Codable, Hashable, Sendable {
    case initialAction = "initial_action"
    case agentActivity = "agent_activity"
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
    case absent
    case created(committedRevision: DocumentFingerprint)

    public var expectedRevision: DocumentFingerprint? {
        switch self {
        case .existing(let revision): revision
        case .created(let revision): revision
        case .absent: nil
        }
    }
}

/// One canonical field the Agent may supply while creating an Analysis of a
/// particular source type. This projection deliberately excludes authored
/// YAML bytes, reserved identities, and any creation authority. Preference is
/// presentation guidance only.
public struct ResearchAnalysisCreationFieldPlan: Codable, Hashable, Sendable {
    public let key: String
    public let valueKind: PropertyValueKind
    public let allowedValues: [String]?
    public let isPreferred: Bool

    public init(
        key: String,
        valueKind: PropertyValueKind,
        allowedValues: [String]? = nil,
        isPreferred: Bool
    ) throws {
        guard !key.isEmpty,
              key.utf8.count <= 64,
              Set(allowedValues ?? []).count == (allowedValues?.count ?? 0),
              (valueKind == .choice) == (allowedValues != nil) else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.key = key
        self.valueKind = valueKind
        self.allowedValues = allowedValues
        self.isPreferred = isPreferred
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key
        case valueKind = "value_kind"
        case allowedValues = "allowed_values"
        case isPreferred = "is_preferred"
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
            isPreferred: container.decode(Bool.self, forKey: .isPreferred)
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
        guard fields.count <= 256,
              Set(fields.map(\.key)).count == fields.count,
              fields.allSatisfy({ $0.key != "type" }) else {
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

public struct ResearchMetadataWriteFieldPlan: Codable, Hashable, Sendable {
    public let key: String
    public let valueKind: PropertyValueKind
    public let allowedValues: [String]?

    public init(
        key: String,
        valueKind: PropertyValueKind,
        allowedValues: [String]? = nil
    ) throws {
        guard ResearchBoundedWriteValidation.validMetadataKey(key),
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

/// One current document tracked for an Agent Run. It contains no source bytes
/// or academic relation. The Run Session establishes attribution; this value
/// records the exact target, operation, and revision used by Scholium's writer.
public struct ResearchBoundedWriteSetEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchWriteTargetHandle { handle }

    public let handle: ResearchWriteTargetHandle
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let allowedOperations: [ResearchDocumentWriteOperation]
    public let allowedMetadataKeys: [String]
    public let metadataWritePlans: [ResearchMetadataWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public var expectation: ResearchWriteSetTargetExpectation
    public let activityOrigin: ResearchWriteSetActivityOrigin
    public var state: ResearchWriteSetEntryState
    public var metadataRevision: DocumentFingerprint?
    public var zoteroBindingsRevision: DocumentFingerprint?

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        allowedOperations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint,
        allowedMetadataKeys: [String] = [],
        metadataWritePlans: [ResearchMetadataWriteFieldPlan] = [],
        metadataRevision: DocumentFingerprint? = nil,
        zoteroBindingsRevision: DocumentFingerprint? = nil,
        activityOrigin: ResearchWriteSetActivityOrigin,
        state: ResearchWriteSetEntryState = .ready
    ) throws {
        let operations = Array(Set(allowedOperations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let metadataKeys = Array(Set(allowedMetadataKeys)).sorted()
        let metadataPlans = metadataWritePlans.sorted { $0.key < $1.key }
        let includesZoteroBinding = operations.contains(where: \.isZoteroBindingOperation)
        guard !operations.isEmpty,
              operations.count == allowedOperations.count,
              operations.contains(.createNote) == false,
              operations.contains(.modifyMetadata) == !metadataKeys.isEmpty,
              metadataKeys == metadataPlans.map(\.key),
              operations.contains(.modifyMetadata) || metadataRevision == nil,
              metadataRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              includesZoteroBinding == (zoteroBindingsRevision != nil),
              !includesZoteroBinding || role == .analysis,
              zoteroBindingsRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              state != .consumed else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allowedOperations = operations
        self.allowedMetadataKeys = metadataKeys
        self.metadataWritePlans = metadataPlans
        analysisCreationPlans = []
        expectation = .existing(expectedRevision: expectedRevision)
        self.activityOrigin = activityOrigin
        self.state = state
        self.metadataRevision = metadataRevision
        self.zoteroBindingsRevision = zoteroBindingsRevision
    }

    public init(
        handle: ResearchWriteTargetHandle,
        reservedNoteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        analysisCreationPlans: [ResearchAnalysisCreationSourcePlan] = [],
        activityOrigin: ResearchWriteSetActivityOrigin,
        state: ResearchWriteSetEntryState = .ready
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              !title.isEmpty,
              title.utf8.count <= 1_024,
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
        allowedMetadataKeys = []
        metadataWritePlans = []
        self.analysisCreationPlans = analysisCreationPlans.sorted {
            $0.sourceType.rawValue < $1.sourceType.rawValue
        }
        expectation = .absent
        self.activityOrigin = activityOrigin
        self.state = state
        metadataRevision = nil
        zoteroBindingsRevision = nil
    }

    public var expectedRevision: DocumentFingerprint? {
        get { expectation.expectedRevision }
        set {
            guard let newValue, case .existing = expectation else { return }
            expectation = .existing(expectedRevision: newValue)
        }
    }

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
        case allowedMetadataKeys = "allowed_metadata_keys"
        case metadataWritePlans = "metadata_write_plans"
        case analysisCreationPlans = "analysis_creation_plans"
        case expectation
        case activityOrigin = "activity_origin"
        case state
        case metadataRevision = "metadata_revision"
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
        let metadataKeys = try container.decode(
            [String].self,
            forKey: .allowedMetadataKeys
        )
        let metadataWritePlans = try container.decode(
            [ResearchMetadataWriteFieldPlan].self,
            forKey: .metadataWritePlans
        )
        let analysisCreationPlans = try container.decode(
            [ResearchAnalysisCreationSourcePlan].self,
            forKey: .analysisCreationPlans
        )
        let expectation = try container.decode(
            ResearchWriteSetTargetExpectation.self,
            forKey: .expectation
        )
        let origin = try container.decode(
                ResearchWriteSetActivityOrigin.self,
                forKey: .activityOrigin
            )
        let state = try container.decode(ResearchWriteSetEntryState.self, forKey: .state)
        let metadataRevision = try container.decodeIfPresent(
            DocumentFingerprint.self,
            forKey: .metadataRevision
        )
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
                allowedMetadataKeys: metadataKeys,
                metadataWritePlans: metadataWritePlans,
                metadataRevision: metadataRevision,
                zoteroBindingsRevision: zoteroBindingsRevision,
                activityOrigin: origin,
                state: state
            )
        case .absent:
            guard metadataRevision == nil, zoteroBindingsRevision == nil,
                  operations == [.createNote], metadataKeys.isEmpty,
                  metadataWritePlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                analysisCreationPlans: analysisCreationPlans,
                activityOrigin: origin,
                state: state
            )
        case .created(let committedRevision):
            guard metadataRevision == nil, zoteroBindingsRevision == nil,
                  operations == [.createNote], metadataKeys.isEmpty,
                  metadataWritePlans.isEmpty,
                  state == .consumed else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                analysisCreationPlans: analysisCreationPlans,
                activityOrigin: origin,
                state: .ready
            )
            self.expectation = .created(
                committedRevision: committedRevision
            )
            self.state = .consumed
        }
    }
}

public struct ResearchBoundedWriteSet: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 7
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

    public func ledgerRevision() throws -> DocumentFingerprint {
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
    public let metadataKeys: [String]

    public init(
        role: ResearchActionTargetRole,
        relativePath: String,
        operations: [ResearchDocumentWriteOperation],
        metadataKeys: [String] = []
    ) throws {
        let providedCount = operations.count
        let operations = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        let keys = Array(Set(metadataKeys)).sorted()
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              !operations.isEmpty,
              operations.count == providedCount,
              operations.contains(.createNote) == (operations == [.createNote]),
              operations.contains(.modifyMetadata) == !keys.isEmpty,
              !operations.contains(where: \.isZoteroBindingOperation)
                || role == .analysis,
              keys.count == metadataKeys.count,
              keys.count <= ResearchAuthorityEnvelope.maximumEditableMetadataKeyCount,
              keys.allSatisfy(ResearchBoundedWriteValidation.validMetadataKey) else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
        self.role = role
        self.relativePath = relativePath
        self.operations = operations
        self.metadataKeys = keys
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operations
        case metadataKeys = "metadata_keys"
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
            metadataKeys: container.decodeIfPresent(
                [String].self,
                forKey: .metadataKeys
            ) ?? []
        )
    }
}

public struct ResearchWriteSetExtensionIntent: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

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
    case absent
}

public struct ResearchWriteSetCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchWriteTargetHandle { handle }

    public let handle: ResearchWriteTargetHandle
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let operations: [ResearchDocumentWriteOperation]
    public let metadataKeys: [String]
    public let metadataWritePlans: [ResearchMetadataWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public let expectation: ResearchWriteSetCandidateExpectation
    public let metadataRevision: DocumentFingerprint?
    public let zoteroBindingsRevision: DocumentFingerprint?

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        operations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint,
        metadataKeys: [String] = [],
        metadataWritePlans: [ResearchMetadataWriteFieldPlan] = [],
        metadataRevision: DocumentFingerprint? = nil,
        zoteroBindingsRevision: DocumentFingerprint? = nil
    ) throws {
        let canonicalOperations = Array(Set(operations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let metadataKeys = Array(Set(metadataKeys)).sorted()
        let metadataPlans = metadataWritePlans.sorted { $0.key < $1.key }
        let includesZoteroBinding = canonicalOperations.contains(
            where: \.isZoteroBindingOperation
        )
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !canonicalOperations.isEmpty,
              canonicalOperations.count == operations.count,
              !canonicalOperations.contains(.createNote),
              canonicalOperations.contains(.modifyMetadata) == !metadataKeys.isEmpty,
              metadataKeys == metadataPlans.map(\.key),
              canonicalOperations.contains(.modifyMetadata) || metadataRevision == nil,
              metadataRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
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
        self.metadataKeys = metadataKeys
        self.metadataWritePlans = metadataPlans
        analysisCreationPlans = []
        expectation = .existing(expectedRevision: expectedRevision)
        self.metadataRevision = metadataRevision
        self.zoteroBindingsRevision = zoteroBindingsRevision
    }

    public init(
        handle: ResearchWriteTargetHandle,
        reservedNoteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
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
        metadataKeys = []
        metadataWritePlans = []
        self.analysisCreationPlans = analysisCreationPlans.sorted {
            $0.sourceType.rawValue < $1.sourceType.rawValue
        }
        expectation = .absent
        metadataRevision = nil
        zoteroBindingsRevision = nil
    }

    public var expectedRevision: DocumentFingerprint? {
        guard case .existing(let revision) = expectation else { return nil }
        return revision
    }

    public var expectsAbsence: Bool {
        if case .absent = expectation { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case noteID = "note_id"
        case note, role, title, operations
        case metadataKeys = "metadata_keys"
        case metadataWritePlans = "metadata_write_plans"
        case analysisCreationPlans = "analysis_creation_plans"
        case expectation
        case metadataRevision = "metadata_revision"
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
        let metadataKeys = try container.decode(
            [String].self,
            forKey: .metadataKeys
        )
        let metadataWritePlans = try container.decode(
            [ResearchMetadataWriteFieldPlan].self,
            forKey: .metadataWritePlans
        )
        let analysisCreationPlans = try container.decode(
            [ResearchAnalysisCreationSourcePlan].self,
            forKey: .analysisCreationPlans
        )
        let metadataRevision = try container.decodeIfPresent(
            DocumentFingerprint.self,
            forKey: .metadataRevision
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
                metadataKeys: metadataKeys,
                metadataWritePlans: metadataWritePlans,
                metadataRevision: metadataRevision,
                zoteroBindingsRevision: zoteroBindingsRevision
            )
        case .absent:
            guard metadataRevision == nil, zoteroBindingsRevision == nil,
                  operations == [.createNote], metadataKeys.isEmpty,
                  metadataWritePlans.isEmpty else {
                throw ResearchBoundedWriteSetError.invalidEntry
            }
            try self.init(
                handle: handle,
                reservedNoteID: noteID,
                note: note,
                role: role,
                title: title,
                analysisCreationPlans: analysisCreationPlans
            )
        }
    }
}

public enum ResearchWriteSetExtensionState: String, Codable, Hashable, Sendable {
    case pending
    case recorded
    case unchanged
    case stale
}

public struct ResearchWriteSetExtensionRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let intent: ResearchWriteSetExtensionIntent
    public let intentDigest: DocumentFingerprint
    public let candidates: [ResearchWriteSetCandidate]
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
              expiresAt > receivedAt,
              expiresAt.timeIntervalSince(receivedAt) <= 30 * 60,
              (state == .recorded) == !allowed.isEmpty,
              (state == .pending) == (decidedAt == nil) else {
            throw ResearchBoundedWriteSetError.invalidExtensionRecord
        }
        self.id = id
        self.runID = runID
        self.triptychID = triptychID
        self.intent = intent
        self.intentDigest = intentDigest
        self.candidates = candidates
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
        case candidates
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
    public let metadataKeys: [String]
    public let metadataWritePlans: [ResearchMetadataWriteFieldPlan]
    public let analysisCreationPlans: [ResearchAnalysisCreationSourcePlan]
    public let state: ResearchWriteSetEntryState
    public let expectsAbsence: Bool

    public init(_ entry: ResearchBoundedWriteSetEntry) {
        title = entry.title
        relativePath = entry.note.relativePath
        role = entry.role
        operations = entry.allowedOperations
        metadataKeys = entry.allowedMetadataKeys
        metadataWritePlans = entry.metadataWritePlans
        analysisCreationPlans = entry.analysisCreationPlans
        state = entry.state
        expectsAbsence = entry.expectsAbsence
    }

    private init(
        title: String,
        relativePath: String,
        role: ResearchActionTargetRole,
        operations: [ResearchDocumentWriteOperation],
        metadataKeys: [String],
        metadataWritePlans: [ResearchMetadataWriteFieldPlan],
        analysisCreationPlans: [ResearchAnalysisCreationSourcePlan],
        state: ResearchWriteSetEntryState,
        expectsAbsence: Bool
    ) throws {
        let canonical = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        let keys = Array(Set(metadataKeys)).sorted()
        let metadataPlans = metadataWritePlans.sorted { $0.key < $1.key }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              ResearchBoundedWriteValidation.validPath(relativePath),
              !canonical.isEmpty,
              canonical.count == operations.count,
              keys.count == metadataKeys.count,
              canonical.contains(.modifyMetadata) == !keys.isEmpty,
              keys == metadataPlans.map(\.key),
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
        self.metadataKeys = keys
        self.metadataWritePlans = metadataPlans
        self.analysisCreationPlans = analysisCreationPlans
        self.state = state
        self.expectsAbsence = expectsAbsence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case relativePath = "relative_path"
        case role, operations
        case metadataKeys = "metadata_keys"
        case metadataWritePlans = "metadata_write_plans"
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
            metadataKeys: container.decode([String].self, forKey: .metadataKeys),
            metadataWritePlans: container.decode(
                [ResearchMetadataWriteFieldPlan].self,
                forKey: .metadataWritePlans
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
    public static let currentSchemaVersion = 4

    public let schemaVersion: Int
    /// One client-generated attempt identity. Retrying the same intent keeps
    /// this UUID; a materially new write must use a new UUID.
    public let requestID: UUID
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let operation: ResearchDocumentWriteOperation
    /// Body text for `modify_markdown` and `create_note`. It is never complete
    /// document source; `create_note` carries only the separate typed
    /// `authoredYAML` values for the fixed scaffold.
    public let content: String
    /// Complete authored Markdown source for `modify_source`. This remains
    /// separate from body content so a caller cannot accidentally turn a
    /// body-only operation into a full-source replacement.
    public let source: String?
    public let metadata: [CanonicalPropertyInput]
    public let authoredYAML: AuthoredNoteYAML?
    public let analysisMetadata: AnalysisCreationMetadata?

    public init(
        requestID: UUID = UUID(),
        role: ResearchActionTargetRole,
        relativePath: String,
        operation: ResearchDocumentWriteOperation = .modifyMarkdown,
        content: String = "",
        source: String? = nil,
        metadata: [CanonicalPropertyInput] = [],
        authoredYAML: AuthoredNoteYAML? = nil,
        analysisMetadata: AnalysisCreationMetadata? = nil
    ) throws {
        let shapeIsValid = switch operation {
        case .createNote:
            source == nil && metadata.isEmpty
        case .modifyMarkdown:
            source == nil && metadata.isEmpty && authoredYAML == nil
                && analysisMetadata == nil
        case .modifySource:
            source != nil && content.isEmpty && metadata.isEmpty
                && authoredYAML == nil && analysisMetadata == nil
        case .modifyMetadata:
            source == nil && content.isEmpty && !metadata.isEmpty
                && authoredYAML == nil && analysisMetadata == nil
        case .setZoteroBinding, .clearZoteroBinding:
            false
        }
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              shapeIsValid,
              !content.unicodeScalars.contains(where: { $0.value == 0 }),
              content.utf8.count <= ResearchBoundedWriteSet
                .maximumDocumentUTF8ByteCount,
              source?.unicodeScalars.contains(where: { $0.value == 0 }) != true,
              source.map(\.utf8.count) ?? 0 <= ResearchBoundedWriteSet
                .maximumDocumentUTF8ByteCount,
              Set(metadata.map(\.key)).count == metadata.count else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.role = role
        self.relativePath = relativePath
        self.operation = operation
        self.content = content
        self.source = source
        self.metadata = metadata.sorted { $0.key < $1.key }
        self.authoredYAML = authoredYAML
        self.analysisMetadata = analysisMetadata
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case role
        case relativePath = "relative_path"
        case operation, content, source, metadata
        case authoredYAML = "authored_yaml"
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
        let source: String?
        switch operation {
        case .modifyMarkdown:
            guard container.contains(.content) else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            content = try container.decode(String.self, forKey: .content)
            source = try container.decodeIfPresent(String.self, forKey: .source)
        case .modifySource:
            guard container.contains(.source) else {
                throw ResearchBoundedWriteSetError.invalidWrite
            }
            source = try container.decode(String.self, forKey: .source)
            content = try container.decodeIfPresent(
                String.self,
                forKey: .content
            ) ?? ""
        case .createNote, .modifyMetadata,
             .setZoteroBinding, .clearZoteroBinding:
            content = try container.decodeIfPresent(
                String.self,
                forKey: .content
            ) ?? ""
            source = try container.decodeIfPresent(String.self, forKey: .source)
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            operation: operation,
            content: content,
            source: source,
            metadata: container.decodeIfPresent(
                [CanonicalPropertyInput].self,
                forKey: .metadata
            ) ?? [],
            authoredYAML: container.decodeIfPresent(
                AuthoredNoteYAML.self,
                forKey: .authoredYAML
            ),
            analysisMetadata: container.decodeIfPresent(
                AnalysisCreationMetadata.self,
                forKey: .analysisMetadata
            )
        )
    }
}

/// A portable Zotero relationship mutation is authorized by one Analysis
/// member, but it is not a Markdown document write. Its payload therefore has
/// no source content, managed metadata values, or document revision.
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
        case .createNote, .modifyMarkdown, .modifySource, .modifyMetadata:
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
        case .modifyMarkdown, .modifySource:
            expectationShapeIsValid = expectedRevision != nil
        case .modifyMetadata:
            expectationShapeIsValid = true
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
    public let priorExpectedRevision: DocumentFingerprint?
    public let observedRevision: DocumentFingerprint?
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
        priorExpectedRevision: DocumentFingerprint?,
        observedRevision: DocumentFingerprint?,
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
              priorExpectedRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              observedRevision.map(
                ResearchBoundedWriteValidation.validFingerprint
              ) ?? true,
              priorExpectedRevision != observedRevision,
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
            priorExpectedRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .priorExpectedRevision
            ),
            observedRevision: container.decodeIfPresent(
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
        case .invalidEntry: "A tracked Agent activity target is invalid."
        case .invalidWriteSet: "The Run's Agent activity ledger is invalid."
        case .invalidIntent: "The Agent activity request is invalid."
        case .invalidExtensionRecord: "The Agent activity record is invalid."
        case .invalidWrite: "The document write request is invalid or too large."
        case .invalidWriteRecord: "The document write transaction record is invalid."
        case .invalidConflictResolution: "The write-conflict resolution is invalid."
        case .limitExceeded: "The Agent activity ledger limit was reached; record the work in a smaller request."
        case .targetUnavailable: "The requested document is unavailable or does not match its stable identity."
        case .targetNotAuthorized: "The document is not yet tracked for this Run. Record the target before writing."
        case .operationNotAuthorized: "The requested operation is not tracked or supported for this document."
        case .requestPending: "Another Agent activity update is still being recorded."
        case .staleAuthorization: "The tracked document revision changed."
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

    static func validMetadataKey(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count
                <= ResearchAuthorityEnvelope.maximumMetadataKeyUTF8ByteCount
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
