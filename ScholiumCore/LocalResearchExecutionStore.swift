import Foundation
import ScholiumContracts

/// Machine-local execution evidence. Protected Function identity and assembled
/// instructions are allowed here and are never projected into the portable
/// record type.
public struct LocalResearchExecutionRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 17

    public let schemaVersion: Int
    public let triptychID: UUID
    public let snapshot: ResearchFunctionSnapshot
    public var preparedInstructions: String
    public var isCompacted: Bool
    public var discussion: ResearchDiscussionExecutionContract?
    public var boundedWriteSet: ResearchBoundedWriteSet
    public var writeSetExtensionRecords: [ResearchWriteSetExtensionRecord]
    public var documentWriteRecords: [ResearchDocumentWriteRecord]
    public var zoteroBindingWriteRecords: [ResearchZoteroBindingWriteRecord]
    public var writeConflictResolutionRecords: [ResearchWriteConflictResolutionRecord]
    public var continuationRequests: [ResearchContinuationRequestRecord]
    public var methodImprovementRun: ResearchMethodImprovementRun?
    public var resultPayload: ResearchRunResultPayload?
    public var writeReport: ResearchRunWriteReport?
    public var completion: ResearchFunctionCompletion?
    public var completionSubmissionDigest: String?

    public var id: UUID { snapshot.runID }

    public init(
        triptychID: UUID,
        snapshot: ResearchFunctionSnapshot,
        preparedInstructions: String,
        isCompacted: Bool = false,
        discussion: ResearchDiscussionExecutionContract? = nil,
        boundedWriteSet: ResearchBoundedWriteSet? = nil,
        writeSetExtensionRecords: [ResearchWriteSetExtensionRecord] = [],
        documentWriteRecords: [ResearchDocumentWriteRecord] = [],
        zoteroBindingWriteRecords: [ResearchZoteroBindingWriteRecord] = [],
        writeConflictResolutionRecords: [ResearchWriteConflictResolutionRecord] = [],
        continuationRequests: [ResearchContinuationRequestRecord] = [],
        methodImprovementRun: ResearchMethodImprovementRun? = nil,
        resultPayload: ResearchRunResultPayload? = nil,
        writeReport: ResearchRunWriteReport? = nil,
        completion: ResearchFunctionCompletion? = nil,
        completionSubmissionDigest: String? = nil
    ) throws {
        let completionRecommendationShapeMatches: Bool
        if let completion {
            if snapshot.actionSnapshot?.actionID == .analyze {
                switch completion.state {
                case .complete, .unverified, .stale:
                    completionRecommendationShapeMatches = completion
                        .literatureRecommendations.map { $0.count <= 256 } ?? true
                case .prepared, .cancelled:
                    completionRecommendationShapeMatches = completion
                        .literatureRecommendations == nil
                }
            } else {
                completionRecommendationShapeMatches = completion
                    .literatureRecommendations == nil
            }
        } else {
            completionRecommendationShapeMatches = true
        }
        let resolvedWriteSet = try boundedWriteSet ?? Self.initialBoundedWriteSet(
            triptychID: triptychID,
            snapshot: snapshot
        )
        let continuationMatches: Bool
        switch snapshot.continuationLineage?.kind {
        case nil:
            continuationMatches = snapshot.continuationHandoff == nil
        case .continueResearch:
            continuationMatches = snapshot.continuationLineage?.requestID
                    == snapshot.runID
                && snapshot.continuationHandoff?.parentRecordID
                    == snapshot.continuationLineage?.parentRunID
                && snapshot.continuationHandoff?.initiator == .agent
                && snapshot.resynthesisContext == nil
        case .resynthesis:
            continuationMatches = snapshot.continuationLineage?.requestID
                    == snapshot.runID
                && snapshot.continuationLineage?.parentRunID
                    == snapshot.resynthesisContext?.recordID
                && snapshot.resynthesisContext?.topicNoteID
                    == snapshot.request.target.noteID
                && snapshot.continuationHandoff == nil
                && (isCompacted
                    || Set(resolvedWriteSet.entries.map(\.noteID))
                        .isSuperset(of: Set(
                            snapshot.actionSnapshot?.authority.writableNotes
                                .map(\.noteID) ?? []
                        )))
        }
        let initialWritableIDs = Set(
            snapshot.actionSnapshot?.authority.writableNotes.map(\.noteID) ?? []
        )
        let writeSetIDs = Set(resolvedWriteSet.entries.map(\.noteID))
        let methodImprovementMatches = methodImprovementRun.map { improvement in
            improvement.parentRecordID == snapshot.runID
                && improvement.triptychID == triptychID
                && improvement.registrationKey
                    == snapshot.actionSnapshot?.method.registration.key
                && improvement.actionID
                    == snapshot.actionSnapshot?.actionID
        } ?? true
        let operationalShapeMatches = isCompacted
            ? preparedInstructions.isEmpty
                && resolvedWriteSet.entries.isEmpty
                && writeSetExtensionRecords.isEmpty
                && documentWriteRecords.isEmpty
                && zoteroBindingWriteRecords.isEmpty
                && writeConflictResolutionRecords.isEmpty
                && completion.map({ [.complete, .unverified].contains($0.state) }) == true
            : initialWritableIDs.isSubset(of: writeSetIDs)
        guard snapshot.actionSnapshot != nil,
              snapshot.runID == snapshot.recordID,
              preparedInstructions.utf8.count <= 2 * 1024 * 1024,
              discussion?.id == snapshot.runID || discussion == nil,
              continuationMatches,
              resolvedWriteSet.runID == snapshot.runID,
              resolvedWriteSet.triptychID == triptychID,
              operationalShapeMatches,
              writeSetExtensionRecords.count <= 256,
              Set(writeSetExtensionRecords.map(\.id)).count
                == writeSetExtensionRecords.count,
              writeSetExtensionRecords.allSatisfy({
                  $0.runID == snapshot.runID && $0.triptychID == triptychID
              }),
              documentWriteRecords.count + zoteroBindingWriteRecords.count
                <= ResearchBoundedWriteSet.maximumWritesPerRun,
              Set(documentWriteRecords.map(\.id)).count
                == documentWriteRecords.count,
              documentWriteRecords.allSatisfy({ $0.runID == snapshot.runID }),
              Set(zoteroBindingWriteRecords.map(\.id)).count
                == zoteroBindingWriteRecords.count,
              zoteroBindingWriteRecords.allSatisfy({ write in
                  guard write.runID == snapshot.runID,
                        let entry = resolvedWriteSet.entry(handle: write.target)
                  else { return false }
                  return entry.role == .analysis
                      && entry.allowedOperations.contains(write.operation)
                      && write.intendedBinding.map({
                          $0.noteID == entry.noteID
                      }) ?? true
              }),
              writeConflictResolutionRecords.count <= 256,
              Set(writeConflictResolutionRecords.map(\.id)).count
                == writeConflictResolutionRecords.count,
              writeConflictResolutionRecords.allSatisfy({ resolution in
                  resolution.runID == snapshot.runID
                      && resolvedWriteSet.entry(handle: resolution.target) != nil
              }),
              continuationRequests.count <= 64,
              Set(continuationRequests.map(\.id)).count
                == continuationRequests.count,
              continuationRequests.allSatisfy({
                  $0.parentRunID == snapshot.runID && $0.triptychID == triptychID
              }),
              methodImprovementMatches,
              resultPayload?.runID == snapshot.runID || resultPayload == nil,
              writeReport?.runID == snapshot.runID || writeReport == nil,
              isCompacted || writeReport.map({ report in
                  let reportIDs = Set(report.confirmedModifiedNotes.map(\.noteID))
                    .union(report.unmodifiedNotes.map(\.noteID))
                  return reportIDs == Set(resolvedWriteSet.entries
                    .filter { !$0.expectsAbsence }.map(\.noteID))
              }) ?? true,
              completion?.runID == snapshot.runID || completion == nil,
              completion?.function == snapshot.request.function || completion == nil,
              completionRecommendationShapeMatches,
              writeReport == nil || completion != nil else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "The local execution does not match its frozen Action run."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.snapshot = snapshot
        self.preparedInstructions = preparedInstructions
        self.isCompacted = isCompacted
        self.discussion = discussion
        self.boundedWriteSet = resolvedWriteSet
        self.writeSetExtensionRecords = writeSetExtensionRecords
        self.documentWriteRecords = documentWriteRecords
        self.zoteroBindingWriteRecords = zoteroBindingWriteRecords
        self.writeConflictResolutionRecords = writeConflictResolutionRecords
        self.continuationRequests = continuationRequests
        self.methodImprovementRun = methodImprovementRun
        self.resultPayload = resultPayload
        self.writeReport = writeReport
        self.completion = completion
        self.completionSubmissionDigest = completionSubmissionDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case snapshot
        case preparedInstructions = "prepared_instructions"
        case isCompacted = "is_compacted"
        case discussion
        case boundedWriteSet = "bounded_write_set"
        case writeSetExtensionRecords = "write_set_extension_records"
        case documentWriteRecords = "document_write_records"
        case zoteroBindingWriteRecords = "zotero_binding_write_records"
        case writeConflictResolutionRecords = "write_conflict_resolution_records"
        case continuationRequests = "continuation_requests"
        case methodImprovementRun = "method_improvement_run"
        case resultPayload = "result_payload"
        case writeReport = "write_report"
        case completion
        case completionSubmissionDigest = "completion_submission_digest"
    }

    public init(from decoder: Decoder) throws {
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: LocalResearchExecutionStoreError.unsupportedField
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LocalResearchExecutionStoreError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            snapshot: container.decode(ResearchFunctionSnapshot.self, forKey: .snapshot),
            preparedInstructions: container.decode(
                String.self,
                forKey: .preparedInstructions
            ),
            isCompacted: container.decode(Bool.self, forKey: .isCompacted),
            discussion: container.decodeIfPresent(
                ResearchDiscussionExecutionContract.self,
                forKey: .discussion
            ),
            boundedWriteSet: container.decode(
                ResearchBoundedWriteSet.self,
                forKey: .boundedWriteSet
            ),
            writeSetExtensionRecords: container.decode(
                [ResearchWriteSetExtensionRecord].self,
                forKey: .writeSetExtensionRecords
            ),
            documentWriteRecords: container.decode(
                [ResearchDocumentWriteRecord].self,
                forKey: .documentWriteRecords
            ),
            zoteroBindingWriteRecords: container.decode(
                [ResearchZoteroBindingWriteRecord].self,
                forKey: .zoteroBindingWriteRecords
            ),
            writeConflictResolutionRecords: container.decode(
                [ResearchWriteConflictResolutionRecord].self,
                forKey: .writeConflictResolutionRecords
            ),
            continuationRequests: container.decode(
                [ResearchContinuationRequestRecord].self,
                forKey: .continuationRequests
            ),
            methodImprovementRun: container.decodeIfPresent(
                ResearchMethodImprovementRun.self,
                forKey: .methodImprovementRun
            ),
            resultPayload: container.decodeIfPresent(
                ResearchRunResultPayload.self,
                forKey: .resultPayload
            ),
            writeReport: container.decodeIfPresent(
                ResearchRunWriteReport.self,
                forKey: .writeReport
            ),
            completion: container.decodeIfPresent(
                ResearchFunctionCompletion.self,
                forKey: .completion
            ),
            completionSubmissionDigest: container.decodeIfPresent(
                String.self,
                forKey: .completionSubmissionDigest
            )
        )
    }

    private static func initialBoundedWriteSet(
        triptychID: UUID,
        snapshot: ResearchFunctionSnapshot
    ) throws -> ResearchBoundedWriteSet {
        guard let action = snapshot.actionSnapshot else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "A local execution has no frozen Action for its bounded write set."
            )
        }
        let entries = try action.authority.writableNotes.map { note in
            try ResearchBoundedWriteSetEntry(
                handle: ResearchWriteTargetHandle(
                    runID: snapshot.runID,
                    noteID: note.noteID
                ),
                noteID: note.noteID,
                note: note.note,
                role: note.role,
                title: note.title,
                allowedOperations: action.authority.writeOperations,
                expectedRevision: note.fingerprint,
                authorizationBasis: .initialAction,
                expiresAt: snapshot.preparedAt.addingTimeInterval(24 * 60 * 60)
            )
        }
        return try ResearchBoundedWriteSet(
            runID: snapshot.runID,
            triptychID: triptychID,
            entries: entries
        )
    }
}

public struct LocalResearchExecutionStoreIssue: Hashable, Identifiable, Sendable {
    public let location: String
    public let fileName: String
    public let reason: String

    public var id: String { "\(location)/\(fileName)" }

    public init(location: String, fileName: String, reason: String) {
        self.location = location
        self.fileName = fileName
        self.reason = reason
    }
}

public enum LocalResearchExecutionStoreError: LocalizedError, Sendable {
    case unsafeStore(String)
    case executionAlreadyExists(UUID)
    case executionNotFound(UUID)
    case executionAlreadyCompleted(UUID)
    case executionIdentityMismatch(UUID)
    case completionMismatch(UUID)
    case agentAnalysisCreationAlreadyExists(UUID)
    case agentAnalysisCreationNotFound(UUID)
    case agentAnalysisCreationMismatch(UUID)
    case unsupportedField(String)
    case unsupportedSchemaVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsafeStore(let reason):
            "The Local Research Execution store is unsafe or unavailable: \(reason)"
        case .executionAlreadyExists(let id):
            "Research execution \(id.uuidString) already exists."
        case .executionNotFound(let id):
            "Research execution \(id.uuidString) was not found."
        case .executionAlreadyCompleted(let id):
            "Research execution \(id.uuidString) already has different completion evidence."
        case .executionIdentityMismatch(let id):
            "Research execution \(id.uuidString) does not match its file identity."
        case .completionMismatch(let id):
            "Action completion does not match its prepared run: \(id.uuidString)"
        case .agentAnalysisCreationAlreadyExists(let id):
            "Agent Analysis creation \(id.uuidString) already exists with different evidence."
        case .agentAnalysisCreationNotFound(let id):
            "Agent Analysis creation \(id.uuidString) was not found."
        case .agentAnalysisCreationMismatch(let id):
            "Agent Analysis creation \(id.uuidString) does not match its request-owned evidence."
        case .unsupportedField(let field):
            "The Local Research Execution contains unsupported field \(field)."
        case .unsupportedSchemaVersion(let version):
            "The Local Research Execution schema version \(version) is unsupported."
        }
    }
}

public struct LocalResearchExecutionListing: Sendable {
    public let records: [LocalResearchExecutionRecord]
    public let issues: [LocalResearchExecutionStoreIssue]
}

public enum LocalAgentAnalysisCreationBindingState: String, Codable, Hashable, Sendable {
    /// The request is durable, but no Zotero binding mutation has begun.
    case reserved
    /// A binding mutation crossed its invocation boundary. Replay must inspect
    /// the authoritative binding and may never issue another write by inference.
    case writing
    /// The binding owner proved that the attempted mutation did not commit, so
    /// an exact retry may begin again after re-reading current authority.
    case retryable
    /// The requested binding was read back exactly.
    case committed
}

/// Machine-local idempotency evidence for the source-ahead portion of one
/// Agent-originated Analysis creation. It is not a Run, portable relationship,
/// or write authority; the portable binding and Note remain independently
/// authoritative.
public struct LocalAgentAnalysisCreationRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let triptychID: UUID
    public let runID: UUID
    public let requestFingerprint: DocumentFingerprint
    public let target: VaultQualifiedNoteID
    public let reservedIdentityID: UUID
    public let requestedBinding: AnalysisZoteroBinding
    public var bindingState: LocalAgentAnalysisCreationBindingState

    public var id: UUID { runID }

    public init(
        triptychID: UUID,
        runID: UUID,
        requestFingerprint: DocumentFingerprint,
        target: VaultQualifiedNoteID,
        reservedIdentityID: UUID,
        requestedBinding: AnalysisZoteroBinding,
        bindingState: LocalAgentAnalysisCreationBindingState = .reserved
    ) throws {
        guard requestedBinding.noteID == reservedIdentityID else {
            throw LocalResearchExecutionStoreError.agentAnalysisCreationMismatch(runID)
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.runID = runID
        self.requestFingerprint = requestFingerprint
        self.target = target
        self.reservedIdentityID = reservedIdentityID
        self.requestedBinding = requestedBinding
        self.bindingState = bindingState
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case runID = "run_id"
        case requestFingerprint = "request_fingerprint"
        case target
        case reservedIdentityID = "reserved_identity_id"
        case requestedBinding = "requested_binding"
        case bindingState = "binding_state"
    }

    public init(from decoder: Decoder) throws {
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: LocalResearchExecutionStoreError.unsupportedField
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LocalResearchExecutionStoreError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            runID: container.decode(UUID.self, forKey: .runID),
            requestFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .requestFingerprint
            ),
            target: container.decode(VaultQualifiedNoteID.self, forKey: .target),
            reservedIdentityID: container.decode(UUID.self, forKey: .reservedIdentityID),
            requestedBinding: container.decode(
                AnalysisZoteroBinding.self,
                forKey: .requestedBinding
            ),
            bindingState: container.decode(
                LocalAgentAnalysisCreationBindingState.self,
                forKey: .bindingState
            )
        )
    }
}


/// Private per-run execution storage. Each run is isolated so one malformed or
/// partially synchronized file cannot make unrelated completion state usable.
public actor LocalResearchExecutionStore {
    private static let maximumExecutionByteCount = 16 * 1024 * 1024
    private static let agentAnalysisCreationDirectory = "agent-analysis-creations"

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v10", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "research-execution-v10",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumExecutionByteCount
        )
        try storage.ensureDirectories([
            "critique-handoffs",
            Self.agentAnalysisCreationDirectory,
        ])
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: "execution-v10.lock"
            )
        } catch {
            throw LocalResearchExecutionStoreError.unsafeStore(error.localizedDescription)
        }
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [
                nil,
                "critique-handoffs",
                Self.agentAnalysisCreationDirectory,
            ])
        }
    }

    @discardableResult
    public func createAgentAnalysisCreation(
        _ record: LocalAgentAnalysisCreationRecord
    ) throws -> LocalAgentAnalysisCreationRecord {
        guard record.triptychID == triptychID else {
            throw LocalResearchExecutionStoreError.agentAnalysisCreationMismatch(record.id)
        }
        return try lock.withExclusiveLock {
            let (canonicalRecord, data) = try Self.canonicalized(record)
            do {
                let readback = try storage.createExclusive(
                    data,
                    directory: Self.agentAnalysisCreationDirectory,
                    fileName: Self.fileName(record.id)
                )
                let stored = try Self.decode(
                    LocalAgentAnalysisCreationRecord.self,
                    from: readback
                )
                guard stored == canonicalRecord else {
                    throw LocalResearchExecutionStoreError
                        .agentAnalysisCreationMismatch(record.id)
                }
                return stored
            } catch let error as SecureRecordDirectoryError {
                if case .alreadyExists = error {
                    let existing = try readAgentAnalysisCreation(id: record.id)
                    if existing == canonicalRecord { return existing }
                    throw LocalResearchExecutionStoreError
                        .agentAnalysisCreationAlreadyExists(record.id)
                }
                throw LocalResearchExecutionStoreError.unsafeStore(
                    error.localizedDescription
                )
            }
        }
    }

    public func agentAnalysisCreation(
        id: UUID
    ) throws -> LocalAgentAnalysisCreationRecord {
        try lock.withSharedLock { try readAgentAnalysisCreation(id: id) }
    }

    public func agentAnalysisCreationIfPresent(
        id: UUID
    ) throws -> LocalAgentAnalysisCreationRecord? {
        try lock.withSharedLock {
            do { return try readAgentAnalysisCreation(id: id) }
            catch LocalResearchExecutionStoreError.agentAnalysisCreationNotFound {
                return nil
            }
        }
    }

    @discardableResult
    public func advanceAgentAnalysisCreationBinding(
        runID: UUID,
        to state: LocalAgentAnalysisCreationBindingState
    ) throws -> LocalAgentAnalysisCreationRecord {
        try lock.withExclusiveLock {
            var record = try readAgentAnalysisCreation(id: runID)
            let allowed = switch (record.bindingState, state) {
            case (.reserved, .reserved), (.reserved, .writing),
                 (.writing, .writing), (.writing, .retryable),
                 (.writing, .committed),
                 (.retryable, .retryable), (.retryable, .writing),
                 (.committed, .committed):
                true
            default:
                false
            }
            guard allowed else {
                throw LocalResearchExecutionStoreError
                    .agentAnalysisCreationMismatch(runID)
            }
            if record.bindingState == state { return record }
            record.bindingState = state
            let (canonicalRecord, data) = try Self.canonicalized(record)
            let readback = try storage.replace(
                data,
                directory: Self.agentAnalysisCreationDirectory,
                fileName: Self.fileName(runID)
            )
            let stored = try Self.decode(
                LocalAgentAnalysisCreationRecord.self,
                from: readback
            )
            guard stored == canonicalRecord else {
                throw LocalResearchExecutionStoreError
                    .agentAnalysisCreationMismatch(runID)
            }
            return stored
        }
    }

    @discardableResult
    public func create(
        _ record: LocalResearchExecutionRecord
    ) throws -> LocalResearchExecutionRecord {
        guard record.triptychID == triptychID else {
            throw LocalResearchExecutionStoreError.executionIdentityMismatch(record.id)
        }
        return try lock.withExclusiveLock {
            let (canonicalRecord, data) = try Self.canonicalized(record)
            do {
                let readback = try storage.createExclusive(
                    data,
                    directory: nil,
                    fileName: Self.fileName(record.id)
                )
                let stored = try Self.decode(
                    LocalResearchExecutionRecord.self,
                    from: readback
                )
                guard stored == canonicalRecord else {
                    throw LocalResearchExecutionStoreError.executionIdentityMismatch(record.id)
                }
                return stored
            } catch let error as SecureRecordDirectoryError {
                if case .alreadyExists = error {
                    let existing = try readRecord(id: record.id)
                    if existing == canonicalRecord { return existing }
                    throw LocalResearchExecutionStoreError.executionAlreadyExists(record.id)
                }
                throw LocalResearchExecutionStoreError.unsafeStore(error.localizedDescription)
            }
        }
    }

    public func record(id: UUID) throws -> LocalResearchExecutionRecord {
        try lock.withSharedLock { try readRecord(id: id) }
    }

    public func recordIfPresent(id: UUID) throws -> LocalResearchExecutionRecord? {
        try lock.withSharedLock {
            do { return try readRecord(id: id) }
            catch LocalResearchExecutionStoreError.executionNotFound { return nil }
        }
    }

    /// Replaces a finalized Run's operational journal with the small receipt
    /// still needed for continuation, Method improvement, and idempotency.
    @discardableResult
    public func compactCompleted(runID: UUID) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            if current.isCompacted { return }
            guard current.completion.map({
                [.complete, .unverified].contains($0.state)
            }) == true,
            !current.writeSetExtensionRecords.contains(where: \.isUnresolved),
            !current.documentWriteRecords.contains(where: {
                [.writing, .recoveryRequired].contains($0.state)
            }),
            !current.zoteroBindingWriteRecords.contains(where: {
                [.writing, .recoveryRequired].contains($0.state)
            }) else {
                throw LocalResearchExecutionStoreError.unsafeStore(
                    "An unfinished Run cannot be compacted."
                )
            }
            current.preparedInstructions = ""
            current.boundedWriteSet = try ResearchBoundedWriteSet(
                runID: current.id,
                triptychID: current.triptychID
            )
            current.writeSetExtensionRecords = []
            current.documentWriteRecords = []
            current.zoteroBindingWriteRecords = []
            current.writeConflictResolutionRecords = []
            current.isCompacted = true
        }
    }

    @discardableResult
    public func installWriteSetExtension(
        _ extensionRecord: ResearchWriteSetExtensionRecord
    ) throws -> LocalResearchExecutionRecord {
        try update(extensionRecord.runID) { current in
            guard current.triptychID == extensionRecord.triptychID else {
                throw ResearchBoundedWriteSetError.invalidExtensionRecord
            }
            if let existing = current.writeSetExtensionRecords.first(where: {
                $0.id == extensionRecord.id
            }) {
                guard existing == extensionRecord else {
                    throw ResearchBoundedWriteSetError.invalidExtensionRecord
                }
                return
            }
            guard !current.writeSetExtensionRecords.contains(where: \.isUnresolved),
                  current.writeSetExtensionRecords.count < 256 else {
                throw ResearchBoundedWriteSetError.requestPending
            }
            current.writeSetExtensionRecords.append(extensionRecord)
            current.writeSetExtensionRecords.sort { $0.receivedAt < $1.receivedAt }
        }
    }

    public func writeSetExtension(
        runID: UUID,
        requestID: UUID
    ) throws -> ResearchWriteSetExtensionRecord {
        let record = try self.record(id: runID)
        guard let request = record.writeSetExtensionRecords.first(where: {
            $0.id == requestID
        }) else {
            throw ResearchBoundedWriteSetError.targetUnavailable
        }
        return request
    }

    @discardableResult
    public func resolveWriteSetExtension(
        runID: UUID,
        requestID: UUID,
        state: ResearchWriteSetExtensionState,
        entries: [ResearchBoundedWriteSetEntry],
        decidedAt: Date
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            guard let index = current.writeSetExtensionRecords.firstIndex(where: {
                $0.id == requestID
            }) else {
                throw ResearchBoundedWriteSetError.targetUnavailable
            }
            let pending = current.writeSetExtensionRecords[index]
            if !pending.isUnresolved {
                let handles = entries.map(\.handle).sorted { $0.rawValue < $1.rawValue }
                guard pending.state == state,
                      pending.allowedHandles == handles else {
                    throw ResearchBoundedWriteSetError.invalidExtensionRecord
                }
                return
            }
            guard pending.expiresAt > decidedAt else {
                current.writeSetExtensionRecords[index] = try ResearchWriteSetExtensionRecord(
                    id: pending.id,
                    runID: pending.runID,
                    triptychID: pending.triptychID,
                    intent: pending.intent,
                    intentDigest: pending.intentDigest,
                    candidates: pending.candidates,
                    policy: pending.policy,
                    policyRevision: pending.policyRevision,
                    state: .expired,
                    receivedAt: pending.receivedAt,
                    expiresAt: pending.expiresAt,
                    decidedAt: decidedAt
                )
                return
            }
            let allowedHandles = entries.map(\.handle).sorted {
                $0.rawValue < $1.rawValue
            }
            guard state == .allowedSubset || entries.isEmpty,
                  state != .allowedSubset || !entries.isEmpty,
                  Set(allowedHandles).isSubset(of: Set(pending.candidates.map(\.handle)))
            else {
                throw ResearchBoundedWriteSetError.invalidExtensionRecord
            }
            var allEntries = current.boundedWriteSet.entries
            for entry in entries {
                if let existingIndex = allEntries.firstIndex(where: {
                    $0.noteID == entry.noteID
                }) {
                    let existing = allEntries[existingIndex]
                    let priorOperations = Set(
                        existing.allowedOperations.filter { $0 != .createNote }
                    )
                    guard entry.handle == existing.handle,
                          entry.note == existing.note,
                          entry.role == existing.role,
                          entry.title == existing.title,
                          entry.state == .ready,
                          entry.expectedRevision != nil,
                          !entry.allowedOperations.contains(.createNote),
                          Set(entry.allowedOperations)
                            .isSuperset(of: priorOperations),
                          Set(entry.allowedPropertyKeys)
                            .isSuperset(of: Set(existing.allowedPropertyKeys)),
                          existing.state == .ready
                            || (existing.state == .consumed
                                && existing.wasCreated),
                          !current.documentWriteRecords.contains(where: {
                              $0.target == existing.handle
                                  && [.writing, .recoveryRequired]
                                    .contains($0.state)
                          }) else {
                        throw ResearchBoundedWriteSetError.invalidEntry
                    }
                    allEntries[existingIndex] = entry
                } else {
                    allEntries.append(entry)
                }
            }
            guard allEntries.count <= ResearchBoundedWriteSet.maximumEntriesPerRun else {
                throw ResearchBoundedWriteSetError.limitExceeded
            }
            current.boundedWriteSet = try ResearchBoundedWriteSet(
                runID: current.snapshot.runID,
                triptychID: current.triptychID,
                entries: allEntries
            )
            current.writeSetExtensionRecords[index] = try ResearchWriteSetExtensionRecord(
                id: pending.id,
                runID: pending.runID,
                triptychID: pending.triptychID,
                intent: pending.intent,
                intentDigest: pending.intentDigest,
                candidates: pending.candidates,
                policy: pending.policy,
                policyRevision: pending.policyRevision,
                state: state,
                allowedHandles: allowedHandles,
                receivedAt: pending.receivedAt,
                expiresAt: pending.expiresAt,
                decidedAt: decidedAt
            )
        }
    }

    /// Narrows a member that has no in-progress or unknown write fail closed.
    /// A write already in progress keeps its transaction state and must settle
    /// through recovery instead of being relabeled underneath the write.
    @discardableResult
    public func markWriteSetEntryStale(
        runID: UUID,
        handle: ResearchWriteTargetHandle
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            guard let index = current.boundedWriteSet.entries.firstIndex(where: {
                $0.handle == handle
            }) else {
                throw ResearchBoundedWriteSetError.targetNotAuthorized
            }
            guard [.ready, .conflict].contains(
                current.boundedWriteSet.entries[index].state
            ) else {
                throw ResearchBoundedWriteSetError.staleAuthorization
            }
            current.boundedWriteSet.entries[index].state = .stale
        }
    }

    /// Atomically records one explicit conflict decision and narrows or
    /// refreshes only its exact write-set member. Existing change evidence and
    /// conflict records remain immutable recovery evidence.
    @discardableResult
    public func resolveWriteConflict(
        _ resolution: ResearchWriteConflictResolutionRecord,
        refreshedEntry: ResearchBoundedWriteSetEntry?
    ) throws -> LocalResearchExecutionRecord {
        try update(resolution.runID) { current in
            if let existing = current.writeConflictResolutionRecords.first(where: {
                $0.id == resolution.id
            }) {
                guard existing == resolution else {
                    throw ResearchBoundedWriteSetError.invalidConflictResolution
                }
                return
            }
            guard current.writeConflictResolutionRecords.count < 256,
                  let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                      $0.handle == resolution.target
                  }),
                  current.boundedWriteSet.entries[entryIndex].state == .conflict,
                  let conflict = current.documentWriteRecords
                    .filter({
                        $0.target == resolution.target && $0.state == .conflict
                    })
                    .max(by: { $0.startedAt < $1.startedAt }),
                  conflict.id == resolution.conflictOperationID else {
                throw ResearchBoundedWriteSetError.invalidConflictResolution
            }
            let entry = current.boundedWriteSet.entries[entryIndex]
            switch resolution.action {
            case .refreshAuthority:
                guard let refreshedEntry,
                      resolution.state == .readyToRetry,
                      resolution.observedRevision
                        == refreshedEntry.expectedRevision,
                      refreshedEntry.handle == entry.handle,
                      refreshedEntry.noteID == entry.noteID,
                      refreshedEntry.note == entry.note,
                      refreshedEntry.role == entry.role,
                      refreshedEntry.title == entry.title,
                      refreshedEntry.allowedOperations == entry.allowedOperations,
                      refreshedEntry.allowedPropertyKeys
                        == entry.allowedPropertyKeys,
                      refreshedEntry.propertyWritePlans
                        == entry.propertyWritePlans,
                      refreshedEntry.authorizationBasis == entry.authorizationBasis,
                      refreshedEntry.authorizationPolicy == entry.authorizationPolicy,
                      refreshedEntry.policyRevision == entry.policyRevision,
                      refreshedEntry.expiresAt == entry.expiresAt,
                      refreshedEntry.state == .ready else {
                    throw ResearchBoundedWriteSetError.invalidConflictResolution
                }
                current.boundedWriteSet.entries[entryIndex] = refreshedEntry
            case .abandonWrite:
                guard refreshedEntry == nil,
                      resolution.state == .abandoned else {
                    throw ResearchBoundedWriteSetError.invalidConflictResolution
                }
                current.boundedWriteSet.entries[entryIndex].state = .abandoned
            }
            current.writeConflictResolutionRecords.append(resolution)
            current.writeConflictResolutionRecords.sort {
                $0.resolvedAt < $1.resolvedAt
            }
        }
    }

    @discardableResult
    public func beginDocumentWrite(
        _ write: ResearchDocumentWriteRecord
    ) throws -> LocalResearchExecutionRecord {
        try update(write.runID) { current in
            if let existing = current.documentWriteRecords.first(where: {
                $0.id == write.id
            }) {
                guard existing == write else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                return
            }
            guard write.state == .writing,
                  current.documentWriteRecords.count
                    + current.zoteroBindingWriteRecords.count
                    < ResearchBoundedWriteSet.maximumWritesPerRun,
                  let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                      $0.handle == write.target
                  }),
                  current.boundedWriteSet.entries[entryIndex].state == .ready,
                  current.boundedWriteSet.entries[entryIndex].expectedRevision
                    == write.expectedRevision else {
                throw ResearchBoundedWriteSetError.staleAuthorization
            }
            current.boundedWriteSet.entries[entryIndex].state = .writing
            current.documentWriteRecords.append(write)
            current.documentWriteRecords.sort { $0.startedAt < $1.startedAt }
        }
    }

    @discardableResult
    public func recordDocumentWriteOutcome(
        _ write: ResearchDocumentWriteRecord,
        entryState: ResearchWriteSetEntryState
    ) throws -> LocalResearchExecutionRecord {
        try update(write.runID) { current in
            if let existing = current.documentWriteRecords.first(where: {
                $0.id == write.id
            }) {
                guard existing == write else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                return
            }
            guard write.state != .writing,
                  current.documentWriteRecords.count
                    + current.zoteroBindingWriteRecords.count
                    < ResearchBoundedWriteSet.maximumWritesPerRun,
                  let index = current.boundedWriteSet.entries.firstIndex(where: {
                      $0.handle == write.target
                  }) else {
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
            current.boundedWriteSet.entries[index].state = entryState
            current.documentWriteRecords.append(write)
            current.documentWriteRecords.sort { $0.startedAt < $1.startedAt }
        }
    }

    @discardableResult
    public func finishDocumentWrite(
        runID: UUID,
        operationID: UUID,
        state: ResearchDocumentWriteState,
        observedRevision: DocumentFingerprint?,
        warning: String?,
        recoveryRecordID: UUID? = nil,
        finishedAt: Date
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            guard let writeIndex = current.documentWriteRecords.firstIndex(where: {
                $0.id == operationID
            }),
            let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                $0.handle == current.documentWriteRecords[writeIndex].target
            }) else {
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
            var write = current.documentWriteRecords[writeIndex]
            if write.state != .writing {
                guard write.state == state,
                      write.observedRevision == observedRevision,
                      write.warning == warning,
                      write.recoveryRecordID == recoveryRecordID else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                return
            }
            write.state = state
            write.observedRevision = observedRevision
            write.finishedAt = finishedAt
            write.warning = warning
            write.recoveryRecordID = recoveryRecordID
            current.documentWriteRecords[writeIndex] = write
            switch state {
            case .committed, .unchanged:
                if write.operation == .createNote {
                    guard state == .committed,
                          let observedRevision,
                          case .absent(let settingsRevision) = current
                            .boundedWriteSet.entries[entryIndex].expectation else {
                        throw ResearchBoundedWriteSetError.invalidWriteRecord
                    }
                    current.boundedWriteSet.entries[entryIndex].expectation = .created(
                        settingsRevision: settingsRevision,
                        committedRevision: observedRevision
                    )
                    current.boundedWriteSet.entries[entryIndex].state = .consumed
                } else {
                    if let observedRevision {
                        current.boundedWriteSet.entries[entryIndex].expectedRevision
                            = observedRevision
                    }
                    current.boundedWriteSet.entries[entryIndex].state = .ready
                }
            case .conflict:
                current.boundedWriteSet.entries[entryIndex].state = .conflict
            case .recoveryRequired:
                current.boundedWriteSet.entries[entryIndex].state = .recoveryRequired
            case .abandoned:
                current.boundedWriteSet.entries[entryIndex].state = .ready
            case .writing:
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
        }
    }

    @discardableResult
    public func beginZoteroBindingWrite(
        _ write: ResearchZoteroBindingWriteRecord
    ) throws -> LocalResearchExecutionRecord {
        try update(write.runID) { current in
            if let existing = current.zoteroBindingWriteRecords.first(where: {
                $0.id == write.id
            }) {
                guard existing == write else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                return
            }
            guard write.state == .writing,
                  current.documentWriteRecords.count
                    + current.zoteroBindingWriteRecords.count
                    < ResearchBoundedWriteSet.maximumWritesPerRun,
                  let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                      $0.handle == write.target
                  }),
                  current.boundedWriteSet.entries[entryIndex].state == .ready,
                  current.boundedWriteSet.entries[entryIndex]
                    .zoteroBindingsRevision == write.expectedRevision,
                  current.boundedWriteSet.entries[entryIndex].allowedOperations
                    .contains(write.operation),
                  write.intendedBinding.map({
                      $0.noteID == current.boundedWriteSet.entries[entryIndex].noteID
                  }) ?? true else {
                throw ResearchBoundedWriteSetError.staleAuthorization
            }
            current.boundedWriteSet.entries[entryIndex].state = .writing
            current.zoteroBindingWriteRecords.append(write)
            current.zoteroBindingWriteRecords.sort { $0.startedAt < $1.startedAt }
        }
    }

    @discardableResult
    public func finishZoteroBindingWrite(
        runID: UUID,
        operationID: UUID,
        state: ResearchZoteroBindingWriteState,
        observedRevision: DocumentFingerprint?,
        warning: String?,
        finishedAt: Date
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            guard let writeIndex = current.zoteroBindingWriteRecords.firstIndex(where: {
                $0.id == operationID
            }),
            let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                $0.handle == current.zoteroBindingWriteRecords[writeIndex].target
            }) else {
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
            var write = current.zoteroBindingWriteRecords[writeIndex]
            if write.state != .writing {
                guard write.state == state,
                      write.observedRevision == observedRevision,
                      write.warning == warning else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                return
            }
            write.state = state
            write.observedRevision = observedRevision
            write.finishedAt = finishedAt
            write.warning = warning
            current.zoteroBindingWriteRecords[writeIndex] = write
            switch state {
            case .committed, .unchanged, .conflict, .abandoned:
                if let observedRevision {
                    current.boundedWriteSet.entries[entryIndex]
                        .zoteroBindingsRevision = observedRevision
                }
                current.boundedWriteSet.entries[entryIndex].state = .ready
            case .recoveryRequired:
                current.boundedWriteSet.entries[entryIndex].state = .recoveryRequired
            case .writing:
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
        }
    }

    /// Reconciles a write linked to the pending recovery record selected by the
    /// researcher. A creation may still be `.writing` with no link when the
    /// process stopped after persisting the stable recovery record but before
    /// finishing the Local Execution update; the same locked mutation attaches
    /// that deterministic record and settles the write.
    @discardableResult
    public func reconcileDocumentWriteRecovery(
        runID: UUID,
        operationID: UUID,
        recoveryRecordID: UUID,
        observedRevision: DocumentFingerprint?,
        reconciledAt: Date
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { current in
            guard let writeIndex = current.documentWriteRecords.firstIndex(where: {
                $0.id == operationID
            }),
            let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                $0.handle == current.documentWriteRecords[writeIndex].target
            }) else {
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
            var write = current.documentWriteRecords[writeIndex]
            let canAttachInterruptedCreation = write.operation == .createNote
                && write.state == .writing
                && write.recoveryRecordID == nil
                && write.expectedRevision == nil
            guard write.recoveryRecordID == recoveryRecordID
                    || canAttachInterruptedCreation else {
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
            if write.state != .recoveryRequired && !canAttachInterruptedCreation {
                guard [.committed, .abandoned].contains(write.state) else {
                    throw ResearchBoundedWriteSetError.recoveryRequired
                }
                return
            }
            let state: ResearchDocumentWriteState
            if observedRevision == write.intendedRevision {
                state = .committed
            } else if observedRevision == write.expectedRevision {
                state = .abandoned
            } else {
                state = .recoveryRequired
            }
            write.state = state
            write.recoveryRecordID = recoveryRecordID
            write.observedRevision = observedRevision
            write.finishedAt = state == .recoveryRequired ? write.finishedAt : reconciledAt
            write.warning = state == .recoveryRequired
                ? "The current bytes still match neither the expected nor intended revision."
                : nil
            current.documentWriteRecords[writeIndex] = write
            switch state {
            case .committed:
                guard let observedRevision else {
                    throw ResearchBoundedWriteSetError.invalidWriteRecord
                }
                if write.operation == .createNote {
                    guard case .absent(let settingsRevision) = current
                        .boundedWriteSet.entries[entryIndex].expectation else {
                        throw ResearchBoundedWriteSetError.invalidWriteRecord
                    }
                    current.boundedWriteSet.entries[entryIndex].expectation = .created(
                        settingsRevision: settingsRevision,
                        committedRevision: observedRevision
                    )
                    current.boundedWriteSet.entries[entryIndex].state = .consumed
                } else {
                    current.boundedWriteSet.entries[entryIndex].expectedRevision
                        = observedRevision
                    current.boundedWriteSet.entries[entryIndex].state = .ready
                }
            case .abandoned:
                current.boundedWriteSet.entries[entryIndex].state = .ready
            case .recoveryRequired:
                current.boundedWriteSet.entries[entryIndex].state = .recoveryRequired
            case .writing, .unchanged, .conflict:
                throw ResearchBoundedWriteSetError.invalidWriteRecord
            }
        }
    }

    public func listing() throws -> LocalResearchExecutionListing {
        try lock.withSharedLock {
            try readListing()
        }
    }

    /// Installs the one current, explicitly researcher-started Method
    /// improvement Run on its source Action execution. A later feedback
    /// revision replaces the terminal prior Run instead of creating history.
    @discardableResult
    public func installMethodImprovement(
        _ improvement: ResearchMethodImprovementRun
    ) throws -> LocalResearchExecutionRecord {
        try update(improvement.parentRecordID) { record in
            guard record.triptychID == improvement.triptychID,
                  record.completion.map({
                      [.complete, .unverified].contains($0.state)
                  }) == true,
                  record.resultPayload != nil else {
                throw ResearchMethodImprovementError.runUnavailable
            }
            if let existing = record.methodImprovementRun,
               existing.id == improvement.id {
                guard existing == improvement else {
                    throw ResearchMethodImprovementError.invalidContract
                }
                return
            }
            if let existing = record.methodImprovementRun,
               existing.state == .writing {
                throw ResearchMethodImprovementError.runUnavailable
            }
            record.methodImprovementRun = improvement
        }
    }

    public func methodImprovement(
        id: UUID
    ) throws -> ResearchMethodImprovementRun {
        let listing = try self.listing()
        guard listing.issues.isEmpty,
              let improvement = listing.records.compactMap(
                \.methodImprovementRun
              ).first(where: { $0.id == id }) else {
            throw ResearchMethodImprovementError.runUnavailable
        }
        return improvement
    }

    @discardableResult
    public func beginMethodImprovement(
        runID: UUID,
        submission: ResearchMethodImprovementSubmission,
        submissionFingerprint: DocumentFingerprint
    ) throws -> LocalResearchExecutionRecord {
        let improvement = try methodImprovement(id: runID)
        return try update(improvement.parentRecordID) { record in
            guard let current = record.methodImprovementRun,
                  current.id == runID else {
                throw ResearchMethodImprovementError.runUnavailable
            }
            if current.state == .writing {
                guard current.submissionFingerprint == submissionFingerprint,
                      current.pendingSubmission == submission else {
                    throw ResearchMethodImprovementError.resultAlreadySubmitted
                }
                return
            }
            guard current.state == .prepared else {
                throw ResearchMethodImprovementError.resultAlreadySubmitted
            }
            record.methodImprovementRun = try current.beginning(
                submission: submission,
                submissionFingerprint: submissionFingerprint
            )
        }
    }

    @discardableResult
    public func completeMethodImprovement(
        runID: UUID,
        submissionFingerprint: DocumentFingerprint,
        receipt: ResearchMethodImprovementReceipt
    ) throws -> LocalResearchExecutionRecord {
        let improvement = try methodImprovement(id: runID)
        return try update(improvement.parentRecordID) { record in
            guard let current = record.methodImprovementRun,
                  current.id == runID else {
                throw ResearchMethodImprovementError.runUnavailable
            }
            if current.state == .completed {
                guard current.submissionFingerprint == submissionFingerprint,
                      current.receipt == receipt else {
                    throw ResearchMethodImprovementError.resultAlreadySubmitted
                }
                return
            }
            guard current.state == .writing,
                  current.submissionFingerprint == submissionFingerprint else {
                throw ResearchMethodImprovementError.runUnavailable
            }
            record.methodImprovementRun = try current.completing(
                submissionFingerprint: submissionFingerprint,
                receipt: receipt
            )
        }
    }

    @discardableResult
    public func cancelMethodImprovement(
        runID: UUID
    ) throws -> LocalResearchExecutionRecord {
        let improvement = try methodImprovement(id: runID)
        return try update(improvement.parentRecordID) { record in
            guard let current = record.methodImprovementRun,
                  current.id == runID else {
                throw ResearchMethodImprovementError.runUnavailable
            }
            if current.state == .cancelled { return }
            record.methodImprovementRun = try current.cancelling()
        }
    }


    /// Fails closed before a destructive note transaction begins. A malformed
    /// execution file may contain note-specific private state, so Scholium may
    /// not claim permanent deletion while leaving it uninterpreted.
    public func validateStoreHealth() throws {
        let listing = try listing()
        guard listing.issues.isEmpty else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
    }

    /// Returns the local Action runs whose private state mentions one of the
    /// supplied Notes.
    public func executionIDs(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        let listing = try listing()
        guard listing.issues.isEmpty else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
        return listing.records
            .filter { !Self.noteIDs(in: $0).isDisjoint(with: noteIDs) }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Returns relevant Runs that can still write, finish, recover a write, or
    /// start dependent work. A confirmed system-Trash operation must reject
    /// these before moving source: deleting their journals would otherwise
    /// hide live authority while the agent can still race the saved revision.
    public func activeExecutionIDs(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        let listing = try listing()
        guard listing.issues.isEmpty else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
        return listing.records
            .filter {
                !Self.noteIDs(in: $0).isDisjoint(with: noteIDs)
                    && Self.hasLiveAuthority($0)
            }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Removes machine-local execution evidence after the native Trash moves
    /// and associated finished Record deletions have durably committed.
    @discardableResult
    public func purgeExecutions(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        return try lock.withExclusiveLock {
            let listing = try readListing()
            guard listing.issues.isEmpty else {
                throw LocalResearchExecutionStoreError.unsafeStore(
                    listing.issues.map(\.id).joined(separator: ", ")
                )
            }
            let removed = listing.records
                .filter { !Self.noteIDs(in: $0).isDisjoint(with: noteIDs) }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            for runID in removed {
                try storage.removeIfPresent(
                    directory: nil,
                    fileName: Self.fileName(runID)
                )
            }
            return removed
        }
    }

    private static func hasLiveAuthority(_ record: LocalResearchExecutionRecord) -> Bool {
        guard let completion = record.completion else { return true }
        if completion.state == .prepared { return true }
        if record.boundedWriteSet.entries.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return true }
        if record.documentWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return true }
        if record.zoteroBindingWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return true }
        if record.writeSetExtensionRecords.contains(where: {
            [.pending, .allowedSubset].contains($0.state)
        }) { return true }
        if record.continuationRequests.contains(where: {
            [.pending, .allowed, .created].contains($0.state)
        }) { return true }
        if let state = record.methodImprovementRun?.state,
           [.prepared, .writing].contains(state) { return true }
        return false
    }

    /// Stages the one canonical Agent/Scholium result payload on its Run.
    /// Exact replay is idempotent; a second, different payload fails closed so
    /// a timeout cannot silently replace already submitted academic content.
    @discardableResult
    public func stageResultPayload(
        _ payload: ResearchRunResultPayload
    ) throws -> LocalResearchExecutionRecord {
        try update(payload.runID) { record in
            guard record.snapshot.runID == payload.runID,
                  record.completion == nil else {
                throw ResearchAgentResultContractError.invalidSubmission
            }
            if let existing = record.resultPayload {
                guard existing == payload else {
                    throw ResearchAgentResultContractError.resultAlreadySubmitted
                }
                return
            }
            record.resultPayload = payload
        }
    }

    @discardableResult
    public func installContinuationRequest(
        _ request: ResearchContinuationRequestRecord
    ) throws -> LocalResearchExecutionRecord {
        try update(request.parentRunID) { record in
            guard record.triptychID == request.triptychID,
                  record.resultPayload != nil,
                  record.completion.map({
                      [.complete, .unverified].contains($0.state)
                  }) == true else {
                throw ResearchContinuationContractError.parentNotFinalized
            }
            if let existing = record.continuationRequests.first(where: {
                $0.id == request.id
            }) {
                guard existing == request else {
                    throw ResearchContinuationContractError.invalidRecord
                }
                return
            }
            guard record.continuationRequests.count < 64 else {
                throw ResearchContinuationContractError.invalidRecord
            }
            record.continuationRequests.append(request)
            record.continuationRequests.sort { $0.receivedAt < $1.receivedAt }
        }
    }

    public func continuationRequest(
        parentRunID: UUID,
        requestID: UUID
    ) throws -> ResearchContinuationRequestRecord {
        let record = try self.record(id: parentRunID)
        guard let request = record.continuationRequests.first(where: {
            $0.id == requestID
        }) else {
            throw ResearchContinuationContractError.invalidRecord
        }
        return request
    }

    @discardableResult
    public func transitionContinuationRequest(
        parentRunID: UUID,
        requestID: UUID,
        state: ResearchContinuationRequestState,
        authorizationBasis: ResearchContinuationAuthorizationBasis? = nil,
        childRunID: UUID? = nil,
        decidedAt: Date
    ) throws -> LocalResearchExecutionRecord {
        try update(parentRunID) { record in
            guard let index = record.continuationRequests.firstIndex(where: {
                $0.id == requestID
            }) else {
                throw ResearchContinuationContractError.invalidRecord
            }
            let current = record.continuationRequests[index]
            if current.state == state, current.childRunID == childRunID { return }
            let allowedTransition: Bool = switch (current.state, state) {
            case (.pending, .allowed), (.pending, .declined),
                 (.pending, .stale), (.pending, .expired),
                 (.allowed, .created), (.allowed, .stale): true
            default: false
            }
            guard allowedTransition else {
                throw ResearchContinuationContractError.invalidRecord
            }
            let resolvedBasis = authorizationBasis
                ?? (state == .created ? current.authorizationBasis : nil)
            record.continuationRequests[index] = try ResearchContinuationRequestRecord(
                id: current.id,
                parentRunID: current.parentRunID,
                triptychID: current.triptychID,
                request: current.request,
                requestFingerprint: current.requestFingerprint,
                policy: current.policy,
                policyRevision: current.policyRevision,
                state: state,
                authorizationBasis: resolvedBasis,
                receivedAt: current.receivedAt,
                expiresAt: current.expiresAt,
                decidedAt: decidedAt,
                childRunID: childRunID
            )
        }
    }

    @discardableResult
    public func setCompletion(
        _ completion: ResearchFunctionCompletion,
        resultPayload: ResearchRunResultPayload? = nil,
        writeReport: ResearchRunWriteReport? = nil,
        submissionDigest: String?,
        runID: UUID
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { record in
            guard completion.runID == runID,
                  completion.function == record.snapshot.request.function,
                  resultPayload?.runID == runID || resultPayload == nil,
                  record.resultPayload == nil
                    || resultPayload == nil
                    || record.resultPayload == resultPayload,
                  writeReport?.runID == runID || writeReport == nil,
                  completion.state == .cancelled
                    || ([.develop, .revise].contains(completion.function)
                        == (writeReport != nil)),
                  record.writeReport == nil || record.writeReport == writeReport else {
                throw LocalResearchExecutionStoreError.completionMismatch(runID)
            }
            if let existing = record.completion {
                if existing == completion {
                    if record.completionSubmissionDigest == submissionDigest {
                        return
                    }
                    guard [.unverified, .stale].contains(
                        existing.state
                    ) else {
                        throw LocalResearchExecutionStoreError.executionAlreadyCompleted(runID)
                    }
                    // The coordinator has revalidated this external
                    // submission against current bytes and it reconstructs
                    // the exact same nonterminal evidence. Accept its digest
                    // before internal orchestration attempts advancement.
                    record.completionSubmissionDigest = submissionDigest
                    return
                }
                guard Self.canAdvance(existing, to: completion, snapshot: record.snapshot) else {
                    throw LocalResearchExecutionStoreError.executionAlreadyCompleted(runID)
                }
            }
            if record.resultPayload == nil {
                record.resultPayload = resultPayload
            }
            record.writeReport = writeReport
            record.completion = completion
            record.completionSubmissionDigest = submissionDigest
        }
    }

    public func discardUncompleted(runID: UUID) throws {
        try lock.withExclusiveLock {
            let current = try readRecord(id: runID)
            guard current.completion == nil else {
                throw LocalResearchExecutionStoreError.executionAlreadyCompleted(runID)
            }
            try storage.removeIfPresent(directory: nil, fileName: Self.fileName(runID))
        }
    }

    public func removeCompleted(runID: UUID) throws {
        try lock.withExclusiveLock {
            let current = try readRecord(id: runID)
            guard current.completion.map({
                [.complete, .unverified].contains($0.state)
            }) == true else {
                throw LocalResearchExecutionStoreError.executionAlreadyCompleted(runID)
            }
            try storage.removeIfPresent(directory: nil, fileName: Self.fileName(runID))
        }
    }

    private func readRecord(id: UUID) throws -> LocalResearchExecutionRecord {
        do {
            let data = try storage.read(directory: nil, fileName: Self.fileName(id))
            let record = try Self.decode(
                LocalResearchExecutionRecord.self,
                from: data
            )
            guard record.id == id, record.triptychID == triptychID else {
                throw LocalResearchExecutionStoreError.executionIdentityMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw LocalResearchExecutionStoreError.executionNotFound(id)
            }
            throw LocalResearchExecutionStoreError.unsafeStore(error.localizedDescription)
        }
    }

    private func readAgentAnalysisCreation(
        id: UUID
    ) throws -> LocalAgentAnalysisCreationRecord {
        do {
            let data = try storage.read(
                directory: Self.agentAnalysisCreationDirectory,
                fileName: Self.fileName(id)
            )
            let record = try Self.decode(
                LocalAgentAnalysisCreationRecord.self,
                from: data
            )
            guard record.id == id, record.triptychID == triptychID else {
                throw LocalResearchExecutionStoreError
                    .agentAnalysisCreationMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw LocalResearchExecutionStoreError
                    .agentAnalysisCreationNotFound(id)
            }
            throw LocalResearchExecutionStoreError.unsafeStore(
                error.localizedDescription
            )
        }
    }

    private func readListing() throws -> LocalResearchExecutionListing {
        var records: [LocalResearchExecutionRecord] = []
        var issues: [LocalResearchExecutionStoreIssue] = []
        for fileName in try storage.fileNames(in: nil)
            where fileName.hasSuffix(".json") {
            do {
                let data = try storage.read(directory: nil, fileName: fileName)
                let record = try Self.decode(
                    LocalResearchExecutionRecord.self,
                    from: data
                )
                guard record.triptychID == triptychID,
                      fileName == Self.fileName(record.id) else {
                    throw LocalResearchExecutionStoreError.executionIdentityMismatch(record.id)
                }
                records.append(record)
            } catch {
                issues.append(LocalResearchExecutionStoreIssue(
                    location: "research-execution-v10",
                    fileName: fileName,
                    reason: error.localizedDescription
                ))
            }
        }
        return LocalResearchExecutionListing(
            records: records.sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            },
            issues: issues.sorted { $0.id < $1.id }
        )
    }

    @discardableResult
    private func update(
        _ id: UUID,
        _ body: (inout LocalResearchExecutionRecord) throws -> Void
    ) throws -> LocalResearchExecutionRecord {
        try lock.withExclusiveLock {
            var record = try readRecord(id: id)
            let original = record
            try body(&record)
            if record == original { return original }
            let (canonicalRecord, data) = try Self.canonicalized(record)
            let readback = try storage.replace(
                data,
                directory: nil,
                fileName: Self.fileName(id)
            )
            let stored = try Self.decode(
                LocalResearchExecutionRecord.self,
                from: readback
            )
            guard stored == canonicalRecord else {
                throw LocalResearchExecutionStoreError.executionIdentityMismatch(id)
            }
            return stored
        }
    }

    private nonisolated static func canAdvance(
        _ existing: ResearchFunctionCompletion,
        to replacement: ResearchFunctionCompletion,
        snapshot: ResearchFunctionSnapshot
    ) -> Bool {
        let stateAdvances: Bool
        switch (existing.state, replacement.state) {
        case (.unverified, .complete),
             (.stale, .complete):
            stateAdvances = true
        default:
            stateAdvances = false
        }
        guard stateAdvances,
              existing.runID == replacement.runID,
              existing.function == replacement.function,
              existing.targetFingerprint == replacement.targetFingerprint,
              existing.materialFingerprints == replacement.materialFingerprints,
              existing.summary == replacement.summary,
              existing.didModifyTarget == replacement.didModifyTarget,
              existing.actuallyUsedMaterialNoteIDs
                == replacement.actuallyUsedMaterialNoteIDs,
              existing.literatureRecommendations
                == replacement.literatureRecommendations,
              existing.completedAt == replacement.completedAt,
              existing.fidelityEvidenceKey == nil
                  || existing.fidelityEvidenceKey == replacement.fidelityEvidenceKey,
              existing.reusedFidelityRunID == nil
                  || existing.reusedFidelityRunID == replacement.reusedFidelityRunID,
              existing.derivedRefreshWarning == nil
                  || existing.derivedRefreshWarning == replacement.derivedRefreshWarning,
              Set(existing.fidelityOutcomes).isSubset(of: Set(replacement.fidelityOutcomes)),
              Set(existing.fidelityTargetResults ?? []).isSubset(
                  of: Set(replacement.fidelityTargetResults ?? [])
              ),
              Set(existing.childRunIDs ?? []).isSubset(
                  of: Set(replacement.childRunIDs ?? [])
              ) else {
            return false
        }
        let allowed = snapshot.request.checks
        return Set(replacement.fidelityOutcomes.map(\.check)).isSubset(of: allowed)
    }

    private nonisolated static func noteIDs(
        in record: LocalResearchExecutionRecord
    ) -> Set<UUID> {
        let request = record.snapshot.request
        var noteIDs: Set<UUID> = [request.target.noteID]
        noteIDs.formUnion(request.materials.map(\.noteID))
        noteIDs.formUnion(request.fidelityTargets?.map(\.noteID) ?? [])

        if let action = record.snapshot.actionSnapshot {
            noteIDs.insert(action.target.noteID)
            noteIDs.formUnion(action.authority.readableNotes.map(\.noteID))
            noteIDs.formUnion(action.authority.writableNotes.map(\.noteID))
            noteIDs.formUnion(action.platformInputs.focalNotes.map(\.noteID))
        }
        noteIDs.formUnion(record.boundedWriteSet.entries.map(\.noteID))
        if let report = record.writeReport {
            noteIDs.formUnion(report.confirmedModifiedNotes.map(\.noteID))
            noteIDs.formUnion(report.unmodifiedNotes.map(\.noteID))
            noteIDs.formUnion(report.observedFingerprints.keys)
        }
        return noteIDs
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }


    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try makeDecoder().decode(type, from: data)
    }

    private static func canonicalized<T: Codable>(_ value: T) throws -> (T, Data) {
        let first = try makeEncoder().encode(value)
        let canonical = try makeDecoder().decode(T.self, from: first)
        return (canonical, try makeEncoder().encode(canonical))
    }
}
