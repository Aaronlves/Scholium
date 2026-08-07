import Foundation

/// The closed document mutations that the Platform can authorize for one
/// exact Bounded Write Set member. Method/Profile prose cannot add cases.
public enum ResearchDocumentWriteOperation: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case modifyMarkdown = "modify_markdown"
    case modifyProperties = "modify_properties"
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
    case stale
    case conflict
    case recoveryRequired = "recovery_required"
    case abandoned
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
    public var expectedRevision: DocumentFingerprint
    public let checkpointID: UUID
    public let authorizationBasis: ResearchWriteSetAuthorizationBasis
    public let authorizationPolicy: ResearchCollaborationPolicy?
    public let policyRevision: DocumentFingerprint?
    public let expiresAt: Date
    public var state: ResearchWriteSetEntryState

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        allowedOperations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint,
        checkpointID: UUID,
        authorizationBasis: ResearchWriteSetAuthorizationBasis,
        authorizationPolicy: ResearchCollaborationPolicy? = nil,
        policyRevision: DocumentFingerprint? = nil,
        expiresAt: Date,
        state: ResearchWriteSetEntryState = .ready
    ) throws {
        let operations = Array(Set(allowedOperations)).sorted {
            $0.rawValue < $1.rawValue
        }
        guard !operations.isEmpty,
              operations.count == allowedOperations.count,
              ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              expiresAt.timeIntervalSinceReferenceDate.isFinite,
              (authorizationBasis == .collaborationPolicy)
                == (authorizationPolicy != nil && policyRevision != nil),
              policyRevision.map(ResearchBoundedWriteValidation.validFingerprint) ?? true else {
            throw ResearchBoundedWriteSetError.invalidEntry
        }
        self.handle = handle
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allowedOperations = operations
        self.expectedRevision = expectedRevision
        self.checkpointID = checkpointID
        self.authorizationBasis = authorizationBasis
        self.authorizationPolicy = authorizationPolicy
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
        self.state = state
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case noteID = "note_id"
        case note, role, title
        case allowedOperations = "allowed_operations"
        case expectedRevision = "expected_revision"
        case checkpointID = "checkpoint_id"
        case authorizationBasis = "authorization_basis"
        case authorizationPolicy = "authorization_policy"
        case policyRevision = "policy_revision"
        case expiresAt = "expires_at"
        case state
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            handle: container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .handle
            ),
            noteID: container.decode(UUID.self, forKey: .noteID),
            note: container.decode(VaultQualifiedNoteID.self, forKey: .note),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            title: container.decode(String.self, forKey: .title),
            allowedOperations: container.decode(
                [ResearchDocumentWriteOperation].self,
                forKey: .allowedOperations
            ),
            expectedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedRevision
            ),
            checkpointID: container.decode(UUID.self, forKey: .checkpointID),
            authorizationBasis: container.decode(
                ResearchWriteSetAuthorizationBasis.self,
                forKey: .authorizationBasis
            ),
            authorizationPolicy: container.decodeIfPresent(
                ResearchCollaborationPolicy.self,
                forKey: .authorizationPolicy
            ),
            policyRevision: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .policyRevision
            ),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            state: container.decode(ResearchWriteSetEntryState.self, forKey: .state)
        )
    }
}

public struct ResearchBoundedWriteSet: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
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

    public init(
        role: ResearchActionTargetRole,
        relativePath: String,
        operations: [ResearchDocumentWriteOperation]
    ) throws {
        let providedCount = operations.count
        let operations = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              !operations.isEmpty,
              operations.count == providedCount else {
            throw ResearchBoundedWriteSetError.invalidIntent
        }
        self.role = role
        self.relativePath = relativePath
        self.operations = operations
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case role
        case relativePath = "relative_path"
        case operations
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
            )
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

public struct ResearchWriteSetCandidate: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchWriteTargetHandle { handle }

    public let handle: ResearchWriteTargetHandle
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let operations: [ResearchDocumentWriteOperation]
    public let expectedRevision: DocumentFingerprint

    public init(
        handle: ResearchWriteTargetHandle,
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        operations: [ResearchDocumentWriteOperation],
        expectedRevision: DocumentFingerprint
    ) throws {
        let canonicalOperations = Array(Set(operations)).sorted {
            $0.rawValue < $1.rawValue
        }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchBoundedWriteValidation.validPath(note.relativePath),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
              !canonicalOperations.isEmpty,
              canonicalOperations.count == operations.count,
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
        self.expectedRevision = expectedRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case handle
        case noteID = "note_id"
        case note, role, title, operations
        case expectedRevision = "expected_revision"
    }

    public init(from decoder: Decoder) throws {
        try ResearchBoundedWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            error: .invalidEntry
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            handle: container.decode(
                ResearchWriteTargetHandle.self,
                forKey: .handle
            ),
            noteID: container.decode(UUID.self, forKey: .noteID),
            note: container.decode(VaultQualifiedNoteID.self, forKey: .note),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            title: container.decode(String.self, forKey: .title),
            operations: container.decode(
                [ResearchDocumentWriteOperation].self,
                forKey: .operations
            ),
            expectedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedRevision
            )
        )
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
    public let state: ResearchWriteSetEntryState

    public init(_ entry: ResearchBoundedWriteSetEntry) {
        title = entry.title
        relativePath = entry.note.relativePath
        role = entry.role
        operations = entry.allowedOperations
        state = entry.state
    }

    private init(
        title: String,
        relativePath: String,
        role: ResearchActionTargetRole,
        operations: [ResearchDocumentWriteOperation],
        state: ResearchWriteSetEntryState
    ) throws {
        let canonical = Array(Set(operations)).sorted { $0.rawValue < $1.rawValue }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf8.count <= 1_024,
              ResearchBoundedWriteValidation.validPath(relativePath),
              !canonical.isEmpty,
              canonical.count == operations.count else {
            throw ResearchBoundedWriteSetError.invalidWriteSet
        }
        self.title = title
        self.relativePath = relativePath
        self.role = role
        self.operations = canonical
        self.state = state
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case title
        case relativePath = "relative_path"
        case role, operations, state
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
            state: container.decode(ResearchWriteSetEntryState.self, forKey: .state)
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
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// One client-generated attempt identity. Retrying the same intent keeps
    /// this UUID; a materially new write must use a new UUID.
    public let requestID: UUID
    public let role: ResearchActionTargetRole
    public let relativePath: String
    public let operation: ResearchDocumentWriteOperation
    public let content: String

    public init(
        requestID: UUID = UUID(),
        role: ResearchActionTargetRole,
        relativePath: String,
        operation: ResearchDocumentWriteOperation = .modifyMarkdown,
        content: String
    ) throws {
        guard ResearchBoundedWriteValidation.validPath(relativePath),
              !content.unicodeScalars.contains(where: { $0.value == 0 }),
              content.utf8.count <= ResearchBoundedWriteSet
                .maximumDocumentUTF8ByteCount else {
            throw ResearchBoundedWriteSetError.invalidWrite
        }
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.role = role
        self.relativePath = relativePath
        self.operation = operation
        self.content = content
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case role
        case relativePath = "relative_path"
        case operation, content
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
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            relativePath: container.decode(String.self, forKey: .relativePath),
            operation: container.decode(
                ResearchDocumentWriteOperation.self,
                forKey: .operation
            ),
            content: container.decode(String.self, forKey: .content)
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
    public let expectedRevision: DocumentFingerprint
    public let intendedRevision: DocumentFingerprint
    public var observedRevision: DocumentFingerprint?
    public var state: ResearchDocumentWriteState
    public let checkpointID: UUID
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
        expectedRevision: DocumentFingerprint,
        intendedRevision: DocumentFingerprint,
        observedRevision: DocumentFingerprint? = nil,
        state: ResearchDocumentWriteState,
        checkpointID: UUID,
        startedAt: Date,
        finishedAt: Date? = nil,
        warning: String? = nil,
        recoveryRecordID: UUID? = nil
    ) throws {
        guard actor != .unknown,
              ResearchBoundedWriteValidation.validFingerprint(requestFingerprint),
              ResearchBoundedWriteValidation.validFingerprint(expectedRevision),
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
              warning.map({ $0.utf8.count <= 4_096 }) ?? true else {
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
        self.checkpointID = checkpointID
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
        case checkpointID = "checkpoint_id"
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
            expectedRevision: container.decode(
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
            checkpointID: container.decode(UUID.self, forKey: .checkpointID),
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
/// retries cannot create duplicate checkpoints or decisions.
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
    public let checkpointID: UUID?
    public let state: ResearchWriteConflictResolutionState
    public let targetView: ResearchBoundedWriteSetViewEntry
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
        checkpointID: UUID? = nil,
        state: ResearchWriteConflictResolutionState,
        targetView: ResearchBoundedWriteSetViewEntry,
        resolvedAt: Date
    ) throws {
        let shapeIsValid = switch (action, state) {
        case (.refreshAuthority, .readyToRetry):
            checkpointID != nil && targetView.state == .ready
        case (.abandonWrite, .abandoned):
            checkpointID == nil && targetView.state == .abandoned
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
        self.checkpointID = checkpointID
        self.state = state
        self.targetView = targetView
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
        case checkpointID = "checkpoint_id"
        case state
        case targetView = "target_view"
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
            checkpointID: container.decodeIfPresent(UUID.self, forKey: .checkpointID),
            state: container.decode(
                ResearchWriteConflictResolutionState.self,
                forKey: .state
            ),
            targetView: container.decode(
                ResearchBoundedWriteSetViewEntry.self,
                forKey: .targetView
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
