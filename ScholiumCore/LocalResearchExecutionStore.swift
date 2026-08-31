import Foundation
import ScholiumContracts

/// Machine-local Action Run execution evidence. Frozen Action identity and assembled
/// instructions are allowed here and are never projected into the portable
/// record type.
public struct LocalResearchExecutionRecord: Codable, Hashable, Identifiable, Sendable {
    public let triptychID: UUID
    public let snapshot: ResearchActionRunSnapshot
    public var preparedInstructions: String
    public var isCompacted: Bool
    public var discussion: ResearchDiscussionExecutionContract?
    public var boundedWriteSet: ResearchBoundedWriteSet
    public var writeSetExtensionRecords: [ResearchWriteSetExtensionRecord]
    public var documentWriteRecords: [ResearchDocumentWriteRecord]
    public var zoteroBindingWriteRecords: [ResearchZoteroBindingWriteRecord]
    public var writeConflictResolutionRecords: [ResearchWriteConflictResolutionRecord]
    public var continuationRequests: [ResearchContinuationRequestRecord]
    public var resultPayload: ResearchRunResultPayload?
    public var writeReport: ResearchRunWriteReport?
    public var completion: ResearchActionRunCompletion?
    public var completionSubmissionDigest: String?

    public var id: UUID { snapshot.runID }

    public init(
        triptychID: UUID,
        snapshot: ResearchActionRunSnapshot,
        preparedInstructions: String,
        isCompacted: Bool = false,
        discussion: ResearchDiscussionExecutionContract? = nil,
        boundedWriteSet: ResearchBoundedWriteSet? = nil,
        writeSetExtensionRecords: [ResearchWriteSetExtensionRecord] = [],
        documentWriteRecords: [ResearchDocumentWriteRecord] = [],
        zoteroBindingWriteRecords: [ResearchZoteroBindingWriteRecord] = [],
        writeConflictResolutionRecords: [ResearchWriteConflictResolutionRecord] = [],
        continuationRequests: [ResearchContinuationRequestRecord] = [],
        resultPayload: ResearchRunResultPayload? = nil,
        writeReport: ResearchRunWriteReport? = nil,
        completion: ResearchActionRunCompletion? = nil,
        completionSubmissionDigest: String? = nil
    ) throws {
        let completionRecommendationShapeMatches: Bool
        if let completion {
            if snapshot.actionSnapshot.actionID == .analyze {
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
        case .followUp:
            continuationMatches = snapshot.continuationLineage?.requestID
                    == snapshot.runID
                && snapshot.continuationHandoff?.parentRecordID
                    == snapshot.continuationLineage?.parentRunID
                && snapshot.continuationHandoff?.initiator == .researcher
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
                            snapshot.actionSnapshot.authority.writableNotes
                                .map(\.noteID)
                        )))
        }
        let initialWritableIDs = Set(
            snapshot.actionSnapshot.authority.writableNotes.map(\.noteID)
        )
        let writeSetIDs = Set(resolvedWriteSet.entries.map(\.noteID))
        let operationalShapeMatches = isCompacted
            ? preparedInstructions.isEmpty
                && resolvedWriteSet.entries.isEmpty
                && writeSetExtensionRecords.isEmpty
                && documentWriteRecords.isEmpty
                && zoteroBindingWriteRecords.isEmpty
                && writeConflictResolutionRecords.isEmpty
                && completion.map({ [.complete, .unverified].contains($0.state) }) == true
            : initialWritableIDs.isSubset(of: writeSetIDs)
        try snapshot.request.validate()
        guard snapshot.request.actionID == snapshot.actionSnapshot.actionID,
              snapshot.request.target == snapshot.actionSnapshot.target,
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
              resultPayload?.runID == snapshot.runID || resultPayload == nil,
              writeReport?.runID == snapshot.runID || writeReport == nil,
              isCompacted || writeReport.map({ report in
                  let reportIDs = Set(report.confirmedModifiedNotes.map(\.noteID))
                    .union(report.unmodifiedNotes.map(\.noteID))
                  return reportIDs == Set(resolvedWriteSet.entries
                    .filter { !$0.expectsAbsence }.map(\.noteID))
              }) ?? true,
              completion?.runID == snapshot.runID || completion == nil,
              completion?.actionID == snapshot.request.actionID || completion == nil,
              completionRecommendationShapeMatches,
              writeReport == nil || completion != nil else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "The local execution does not match its frozen Action run."
            )
        }
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
        self.resultPayload = resultPayload
        self.writeReport = writeReport
        self.completion = completion
        self.completionSubmissionDigest = completionSubmissionDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
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
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            snapshot: container.decode(ResearchActionRunSnapshot.self, forKey: .snapshot),
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
            resultPayload: container.decodeIfPresent(
                ResearchRunResultPayload.self,
                forKey: .resultPayload
            ),
            writeReport: container.decodeIfPresent(
                ResearchRunWriteReport.self,
                forKey: .writeReport
            ),
            completion: container.decodeIfPresent(
                ResearchActionRunCompletion.self,
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
        snapshot: ResearchActionRunSnapshot
    ) throws -> ResearchBoundedWriteSet {
        let action = snapshot.actionSnapshot
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
                activityOrigin: .initialAction
            )
        }
        return try ResearchBoundedWriteSet(
            runID: snapshot.runID,
            triptychID: triptychID,
            entries: entries
        )
    }
}

/// Stable deletion and recovery authority wrapped around the evolving private
/// execution journal. System Trash reads only this envelope; payload revision
/// changes therefore cannot make unrelated Notes undeletable.
struct LocalResearchExecutionEnvelope: Codable, Hashable, Sendable {
    static let formatIdentifier = "org.scholium.local-research-execution"
    static let currentFormatRevision = 1
    static let currentPayloadRevision = 2

    enum AuthorityState: String, Codable, Hashable, Sendable {
        case live
        case recoveryRequired = "recovery_required"
        case terminal

        var blocksSystemTrash: Bool { self != .terminal }
    }

    let formatIdentifier: String
    let formatRevision: Int
    let payloadRevision: Int
    let runID: UUID
    let triptychID: UUID
    let noteIDs: [UUID]
    let authorityState: AuthorityState
    let payloadFingerprint: DocumentFingerprint
    let payload: Data

    init(record: LocalResearchExecutionRecord, payload: Data) {
        formatIdentifier = Self.formatIdentifier
        formatRevision = Self.currentFormatRevision
        payloadRevision = Self.currentPayloadRevision
        runID = record.id
        triptychID = record.triptychID
        noteIDs = LocalResearchExecutionStore.noteIDs(in: record)
            .sorted { $0.uuidString < $1.uuidString }
        authorityState = LocalResearchExecutionStore.authorityState(of: record)
        payloadFingerprint = DocumentFingerprint(data: payload)
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case formatIdentifier = "format_identifier"
        case formatRevision = "format_revision"
        case payloadRevision = "payload_revision"
        case runID = "run_id"
        case triptychID = "triptych_id"
        case noteIDs = "note_ids"
        case authorityState = "authority_state"
        case payloadFingerprint = "payload_fingerprint"
        case payload
    }

    init(from decoder: Decoder) throws {
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: LocalResearchExecutionStoreError.unsupportedField
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatIdentifier = try container.decode(String.self, forKey: .formatIdentifier)
        formatRevision = try container.decode(Int.self, forKey: .formatRevision)
        payloadRevision = try container.decode(Int.self, forKey: .payloadRevision)
        runID = try container.decode(UUID.self, forKey: .runID)
        triptychID = try container.decode(UUID.self, forKey: .triptychID)
        noteIDs = try container.decode([UUID].self, forKey: .noteIDs)
        authorityState = try container.decode(AuthorityState.self, forKey: .authorityState)
        payloadFingerprint = try container.decode(
            DocumentFingerprint.self,
            forKey: .payloadFingerprint
        )
        payload = try container.decode(Data.self, forKey: .payload)
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
    case unsupportedField(String)
    case unsupportedPayloadRevision(Int)

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
        case .unsupportedField(let field):
            "The Local Research Execution contains unsupported field \(field)."
        case .unsupportedPayloadRevision(let revision):
            "The Local Research Execution payload revision \(revision) is unsupported."
        }
    }
}

public struct LocalResearchExecutionListing: Sendable {
    public let records: [LocalResearchExecutionRecord]
    public let issues: [LocalResearchExecutionStoreIssue]
}

private struct LocalResearchExecutionAuthorityEntry: Hashable, Sendable {
    let runID: UUID
    let noteIDs: Set<UUID>
    let authorityState: LocalResearchExecutionEnvelope.AuthorityState
}

private struct LocalResearchExecutionPayloadRecoveryEntry: Hashable, Sendable {
    let authority: LocalResearchExecutionAuthorityEntry
    let item: LocalResearchExecutionRecoveryItem
}

private struct LocalResearchExecutionStoreSnapshot: Sendable {
    let records: [LocalResearchExecutionRecord]
    let authorities: [LocalResearchExecutionAuthorityEntry]
    let issues: [LocalResearchExecutionStoreIssue]
    let unscopedRecoveryItems: [LocalResearchExecutionRecoveryItem]
    let payloadRecoveryEntries: [LocalResearchExecutionPayloadRecoveryEntry]

    var publicListing: LocalResearchExecutionListing {
        LocalResearchExecutionListing(records: records, issues: issues)
    }

    func recoveryItems(affectedNoteIDs: Set<UUID>?) -> [LocalResearchExecutionRecoveryItem] {
        guard let affectedNoteIDs else { return unscopedRecoveryItems }
        return payloadRecoveryEntries
            .filter {
                $0.authority.authorityState.blocksSystemTrash
                    && !$0.authority.noteIDs.isDisjoint(with: affectedNoteIDs)
            }
            .map(\.item)
            .sorted { $0.fileName < $1.fileName }
    }
}

/// Private per-run execution storage. Each run is isolated so one malformed or
/// partially synchronized file cannot make unrelated completion state usable.
public actor LocalResearchExecutionStore {
    private static let maximumPayloadByteCount = 16 * 1024 * 1024
    /// Allows the existing payload boundary plus JSON base64 and envelope
    /// overhead; it does not broaden the decoded Run payload limit.
    private static let maximumStoredByteCount = 24 * 1024 * 1024
    /// Existing physical layout epoch. Kept in one owner so record semantics
    /// never depend on parsing a version from a directory or lock-file name.
    private static let storageLayoutEpoch = "v10"
    private static let storageDirectoryName = "research-execution-\(storageLayoutEpoch)"
    private static let coordinationLockName = "execution-\(storageLayoutEpoch).lock"
    private static let unsupportedExecutionDirectory = "unsupported-executions"

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                Self.storageDirectoryName,
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumStoredByteCount
        )
        try storage.ensureDirectories([
            "critique-handoffs",
            Self.unsupportedExecutionDirectory,
        ])
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: Self.coordinationLockName
            )
        } catch {
            throw LocalResearchExecutionStoreError.unsafeStore(error.localizedDescription)
        }
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [
                nil,
                "critique-handoffs",
                Self.unsupportedExecutionDirectory,
            ])
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
            let (canonicalRecord, data) = try Self.canonicalizedExecution(record)
            do {
                let readback = try storage.createExclusive(
                    data,
                    directory: nil,
                    fileName: Self.fileName(record.id)
                )
                let stored = try Self.decodeExecution(
                    from: readback,
                    fileName: Self.fileName(record.id),
                    triptychID: triptychID
                ).record
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
    /// still needed for continuation and idempotency.
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
            if let existingIndex = current.writeSetExtensionRecords.firstIndex(where: {
                $0.id == extensionRecord.id
            }) {
                let existing = current.writeSetExtensionRecords[existingIndex]
                if existing.state == .stale,
                   existing.runID == extensionRecord.runID,
                   existing.triptychID == extensionRecord.triptychID,
                   existing.intent == extensionRecord.intent,
                   existing.intentDigest == extensionRecord.intentDigest,
                   existing.candidates == extensionRecord.candidates {
                    current.writeSetExtensionRecords[existingIndex] = extensionRecord
                    return
                }
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
            let allowedHandles = entries.map(\.handle).sorted {
                $0.rawValue < $1.rawValue
            }
            guard state == .recorded || entries.isEmpty,
                  state != .recorded || !entries.isEmpty,
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
                          Set(entry.allowedMetadataKeys)
                            .isSuperset(of: Set(existing.allowedMetadataKeys)),
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
                        == (conflict.operation == .modifyMetadata
                            ? refreshedEntry.metadataRevision
                            : refreshedEntry.expectedRevision),
                      refreshedEntry.handle == entry.handle,
                      refreshedEntry.noteID == entry.noteID,
                      refreshedEntry.note == entry.note,
                      refreshedEntry.role == entry.role,
                      refreshedEntry.title == entry.title,
                      refreshedEntry.allowedOperations == entry.allowedOperations,
                      refreshedEntry.allowedMetadataKeys
                        == entry.allowedMetadataKeys,
                      refreshedEntry.metadataWritePlans
                        == entry.metadataWritePlans,
                      (conflict.operation == .modifyMetadata
                        || refreshedEntry.metadataRevision == entry.metadataRevision),
                      refreshedEntry.zoteroBindingsRevision
                        == entry.zoteroBindingsRevision,
                      refreshedEntry.activityOrigin == entry.activityOrigin,
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
                  (write.operation == .modifyMetadata
                    ? current.boundedWriteSet.entries[entryIndex].metadataRevision
                    : current.boundedWriteSet.entries[entryIndex].expectedRevision)
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
                          case .absent = current
                            .boundedWriteSet.entries[entryIndex].expectation else {
                        throw ResearchBoundedWriteSetError.invalidWriteRecord
                    }
                    current.boundedWriteSet.entries[entryIndex].expectation = .created(
                        committedRevision: observedRevision
                    )
                    current.boundedWriteSet.entries[entryIndex].state = .consumed
                } else {
                    if write.operation == .modifyMetadata {
                        current.boundedWriteSet.entries[entryIndex].metadataRevision
                            = observedRevision
                    } else if let observedRevision {
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
                    guard case .absent = current
                        .boundedWriteSet.entries[entryIndex].expectation else {
                        throw ResearchBoundedWriteSetError.invalidWriteRecord
                    }
                    current.boundedWriteSet.entries[entryIndex].expectation = .created(
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
            try readStoreSnapshot().publicListing
        }
    }


    /// Verifies the stable authority envelope needed to scope System Trash.
    /// An unsupported payload remains visible in diagnostics but does not make
    /// unrelated Note deletion depend on its private journal revision.
    public func validateDeletionAuthority() throws {
        let snapshot = try lock.withSharedLock { try readStoreSnapshot() }
        guard snapshot.unscopedRecoveryItems.isEmpty else {
            throw SystemTrashPreparationError.localExecutionRecoveryRequired(
                LocalResearchExecutionRecoveryPreview(
                    triptychID: triptychID,
                    items: snapshot.unscopedRecoveryItems
                )
            )
        }
    }

    /// Moves exact opaque bytes into protected machine-local archival storage.
    /// Confirmation is fingerprint-bound and stale previews fail closed.
    public func archiveUnsupportedExecutions(
        _ preview: LocalResearchExecutionRecoveryPreview
    ) throws -> LocalResearchExecutionArchiveCommit {
        guard preview.triptychID == triptychID, !preview.items.isEmpty else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "The local execution recovery preview does not match this Triptych."
            )
        }
        return try lock.withExclusiveLock {
            let current = try readStoreSnapshot()
            let affectedNoteIDs = preview.affectedNoteIDs.map(Set.init)
            guard preview.affectedNoteIDs == nil || affectedNoteIDs?.isEmpty == false,
                  current.recoveryItems(affectedNoteIDs: affectedNoteIDs)
                    == preview.items else {
                throw LocalResearchExecutionStoreError.unsafeStore(
                    "The unreadable local execution files changed before archival."
                )
            }
            var archived: [String] = []
            for item in preview.items {
                let bytes = try storage.read(directory: nil, fileName: item.fileName)
                guard DocumentFingerprint(data: bytes) == item.fingerprint else {
                    throw LocalResearchExecutionStoreError.unsafeStore(
                        "\(item.fileName) changed before archival."
                    )
                }
                if let existing = try storage.readIfPresent(
                    directory: Self.unsupportedExecutionDirectory,
                    fileName: item.fileName
                ) {
                    guard existing == bytes else {
                        throw LocalResearchExecutionStoreError.unsafeStore(
                            "The unsupported execution archive already contains different bytes for \(item.fileName)."
                        )
                    }
                } else {
                    let readback = try storage.createExclusive(
                        bytes,
                        directory: Self.unsupportedExecutionDirectory,
                        fileName: item.fileName
                    )
                    guard readback == bytes else {
                        throw LocalResearchExecutionStoreError.unsafeStore(
                            "The archived bytes for \(item.fileName) did not match."
                        )
                    }
                }
                try storage.remove(
                    directory: nil,
                    fileName: item.fileName,
                    expected: bytes
                )
                archived.append(item.fileName)
            }
            return LocalResearchExecutionArchiveCommit(
                previewID: preview.id,
                archivedFileNames: archived
            )
        }
    }

    /// Returns the local Action runs whose private state mentions one of the
    /// supplied Notes.
    public func executionIDs(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        let snapshot = try lock.withSharedLock { try readStoreSnapshot() }
        try requireValidDeletionAuthority(snapshot)
        return snapshot.authorities
            .filter { !$0.noteIDs.isDisjoint(with: noteIDs) }
            .map(\.runID)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Returns relevant Runs that can still write, finish, recover a write, or
    /// start dependent work. A confirmed system-Trash operation must reject
    /// these before moving source: deleting their journals would otherwise
    /// hide live authority while the agent can still race the saved revision.
    public func activeExecutionIDs(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        let snapshot = try lock.withSharedLock { try readStoreSnapshot() }
        try requireValidDeletionAuthority(snapshot)
        let recoveryItems = snapshot.recoveryItems(affectedNoteIDs: noteIDs)
        guard recoveryItems.isEmpty else {
            throw SystemTrashPreparationError.localExecutionRecoveryRequired(
                LocalResearchExecutionRecoveryPreview(
                    triptychID: triptychID,
                    affectedNoteIDs: noteIDs,
                    items: recoveryItems
                )
            )
        }
        return snapshot.authorities
            .filter {
                !$0.noteIDs.isDisjoint(with: noteIDs)
                    && $0.authorityState.blocksSystemTrash
            }
            .map(\.runID)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Removes machine-local execution evidence after the native Trash moves
    /// and associated finished Record deletions have durably committed.
    @discardableResult
    public func purgeExecutions(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        return try lock.withExclusiveLock {
            let snapshot = try readStoreSnapshot()
            try requireValidDeletionAuthority(snapshot)
            let removed = snapshot.authorities
                .filter { !$0.noteIDs.isDisjoint(with: noteIDs) }
                .map(\.runID)
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

    fileprivate static func authorityState(
        of record: LocalResearchExecutionRecord
    ) -> LocalResearchExecutionEnvelope.AuthorityState {
        if record.boundedWriteSet.entries.contains(where: {
            $0.state == .recoveryRequired
        }) || record.documentWriteRecords.contains(where: {
            $0.state == .recoveryRequired
        }) || record.zoteroBindingWriteRecords.contains(where: {
            $0.state == .recoveryRequired
        }) {
            return .recoveryRequired
        }
        guard let completion = record.completion else { return .live }
        if completion.state == .prepared { return .live }
        if record.boundedWriteSet.entries.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return .live }
        if record.documentWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return .live }
        if record.zoteroBindingWriteRecords.contains(where: {
            [.writing, .recoveryRequired].contains($0.state)
        }) { return .live }
        if record.writeSetExtensionRecords.contains(where: {
            [.pending, .recorded].contains($0.state)
        }) { return .live }
        if record.continuationRequests.contains(where: {
            [.pending, .allowed, .created].contains($0.state)
        }) { return .live }
        return .terminal
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
        origin: ResearchContinuationOrigin? = nil,
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
            case (.pending, .allowed), (.pending, .stale),
                 (.allowed, .created), (.allowed, .stale): true
            default: false
            }
            guard allowedTransition else {
                throw ResearchContinuationContractError.invalidRecord
            }
            let resolvedOrigin = origin
                ?? (state == .created ? current.origin : nil)
            record.continuationRequests[index] = try ResearchContinuationRequestRecord(
                id: current.id,
                parentRunID: current.parentRunID,
                triptychID: current.triptychID,
                request: current.request,
                requestFingerprint: current.requestFingerprint,
                state: state,
                origin: resolvedOrigin,
                receivedAt: current.receivedAt,
                expiresAt: current.expiresAt,
                decidedAt: decidedAt,
                childRunID: childRunID
            )
        }
    }

    @discardableResult
    public func setCompletion(
        _ completion: ResearchActionRunCompletion,
        resultPayload: ResearchRunResultPayload? = nil,
        writeReport: ResearchRunWriteReport? = nil,
        submissionDigest: String?,
        runID: UUID
    ) throws -> LocalResearchExecutionRecord {
        try update(runID) { record in
            guard completion.runID == runID,
                  completion.actionID == record.snapshot.request.actionID,
                  resultPayload?.runID == runID || resultPayload == nil,
                  record.resultPayload == nil
                    || resultPayload == nil
                    || record.resultPayload == resultPayload,
                  writeReport?.runID == runID || writeReport == nil,
                  completion.state == .cancelled
                    || (completion.actionID.writesTarget == (writeReport != nil)),
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
            return try Self.decodeExecution(
                from: data,
                fileName: Self.fileName(id),
                triptychID: triptychID
            ).record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw LocalResearchExecutionStoreError.executionNotFound(id)
            }
            throw LocalResearchExecutionStoreError.unsafeStore(error.localizedDescription)
        }
    }

    private func readStoreSnapshot() throws -> LocalResearchExecutionStoreSnapshot {
        var records: [LocalResearchExecutionRecord] = []
        var authorities: [LocalResearchExecutionAuthorityEntry] = []
        var issues: [LocalResearchExecutionStoreIssue] = []
        var unscopedRecoveryItems: [LocalResearchExecutionRecoveryItem] = []
        var payloadRecoveryEntries: [LocalResearchExecutionPayloadRecoveryEntry] = []
        for fileName in try storage.fileNames(in: nil)
            where fileName.hasSuffix(".json") {
            let data: Data
            do {
                data = try storage.read(directory: nil, fileName: fileName)
            } catch {
                throw LocalResearchExecutionStoreError.unsafeStore(
                    error.localizedDescription
                )
            }
            do {
                let envelope = try Self.decodeEnvelope(
                    from: data,
                    fileName: fileName,
                    triptychID: triptychID
                )
                let authority = LocalResearchExecutionAuthorityEntry(
                    runID: envelope.runID,
                    noteIDs: Set(envelope.noteIDs),
                    authorityState: envelope.authorityState
                )
                authorities.append(authority)
                do {
                    let decoded = try Self.decodeCurrentPayload(from: envelope)
                    try Self.validatePayload(decoded, matches: envelope)
                    records.append(decoded)
                } catch LocalResearchExecutionStoreError.executionIdentityMismatch(_) {
                    authorities.removeLast()
                    issues.append(LocalResearchExecutionStoreIssue(
                        location: Self.storageDirectoryName,
                        fileName: fileName,
                        reason: LocalResearchExecutionStoreError
                            .executionIdentityMismatch(envelope.runID)
                            .localizedDescription
                    ))
                    unscopedRecoveryItems.append(LocalResearchExecutionRecoveryItem(
                        fileName: fileName,
                        fingerprint: DocumentFingerprint(data: data)
                    ))
                } catch {
                    let item = LocalResearchExecutionRecoveryItem(
                        fileName: fileName,
                        fingerprint: DocumentFingerprint(data: data)
                    )
                    issues.append(LocalResearchExecutionStoreIssue(
                        location: Self.storageDirectoryName,
                        fileName: fileName,
                        reason: error.localizedDescription
                    ))
                    payloadRecoveryEntries.append(
                        LocalResearchExecutionPayloadRecoveryEntry(
                            authority: authority,
                            item: item
                        )
                    )
                }
            } catch {
                issues.append(LocalResearchExecutionStoreIssue(
                    location: Self.storageDirectoryName,
                    fileName: fileName,
                    reason: error.localizedDescription
                ))
                unscopedRecoveryItems.append(LocalResearchExecutionRecoveryItem(
                    fileName: fileName,
                    fingerprint: DocumentFingerprint(data: data)
                ))
            }
        }
        return LocalResearchExecutionStoreSnapshot(
            records: records.sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            },
            authorities: authorities.sorted { $0.runID.uuidString < $1.runID.uuidString },
            issues: issues.sorted { $0.id < $1.id },
            unscopedRecoveryItems: unscopedRecoveryItems.sorted {
                $0.fileName < $1.fileName
            },
            payloadRecoveryEntries: payloadRecoveryEntries.sorted {
                $0.item.fileName < $1.item.fileName
            }
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
            let (canonicalRecord, data) = try Self.canonicalizedExecution(record)
            let readback = try storage.replace(
                data,
                directory: nil,
                fileName: Self.fileName(id)
            )
            let stored = try Self.decodeExecution(
                from: readback,
                fileName: Self.fileName(id),
                triptychID: triptychID
            ).record
            guard stored == canonicalRecord else {
                throw LocalResearchExecutionStoreError.executionIdentityMismatch(id)
            }
            return stored
        }
    }

    private nonisolated static func canAdvance(
        _ existing: ResearchActionRunCompletion,
        to replacement: ResearchActionRunCompletion,
        snapshot: ResearchActionRunSnapshot
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
              existing.actionID == replacement.actionID,
              existing.targetFingerprint == replacement.targetFingerprint,
              existing.materialFingerprints == replacement.materialFingerprints,
              existing.summary == replacement.summary,
              existing.didModifyTarget == replacement.didModifyTarget,
              existing.literatureRecommendations
                == replacement.literatureRecommendations,
              existing.completedAt == replacement.completedAt,
              existing.fidelityEvidenceKey == nil
                  || existing.fidelityEvidenceKey == replacement.fidelityEvidenceKey,
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

    nonisolated static func noteIDs(
        in record: LocalResearchExecutionRecord
    ) -> Set<UUID> {
        let request = record.snapshot.request
        var noteIDs: Set<UUID> = [request.target.noteID]
        noteIDs.formUnion(request.materials.map(\.noteID))
        noteIDs.formUnion(request.fidelityTargets?.map(\.noteID) ?? [])

        let action = record.snapshot.actionSnapshot
        noteIDs.insert(action.target.noteID)
        noteIDs.formUnion(action.authority.readableNotes.map(\.noteID))
        noteIDs.formUnion(action.authority.writableNotes.map(\.noteID))
        noteIDs.formUnion(action.platformInputs.focalNotes.map(\.noteID))
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

    private static func decodeEnvelope(
        from data: Data,
        fileName: String,
        triptychID: UUID
    ) throws -> LocalResearchExecutionEnvelope {
        let envelope = try decode(LocalResearchExecutionEnvelope.self, from: data)
        guard envelope.formatIdentifier == LocalResearchExecutionEnvelope.formatIdentifier,
              envelope.formatRevision == LocalResearchExecutionEnvelope.currentFormatRevision,
              envelope.triptychID == triptychID,
              fileName == Self.fileName(envelope.runID),
              !envelope.noteIDs.isEmpty,
              envelope.noteIDs == envelope.noteIDs.sorted(by: {
                  $0.uuidString < $1.uuidString
              }),
              Set(envelope.noteIDs).count == envelope.noteIDs.count,
              envelope.payload.count <= maximumPayloadByteCount,
              envelope.payloadFingerprint == DocumentFingerprint(data: envelope.payload) else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "\(fileName) has an invalid local execution authority envelope."
            )
        }
        return envelope
    }

    private static func decodeCurrentPayload(
        from envelope: LocalResearchExecutionEnvelope
    ) throws -> LocalResearchExecutionRecord {
        guard envelope.payloadRevision
                == LocalResearchExecutionEnvelope.currentPayloadRevision else {
            throw LocalResearchExecutionStoreError.unsupportedPayloadRevision(
                envelope.payloadRevision
            )
        }
        return try decode(LocalResearchExecutionRecord.self, from: envelope.payload)
    }

    private static func validatePayload(
        _ record: LocalResearchExecutionRecord,
        matches envelope: LocalResearchExecutionEnvelope
    ) throws {
        guard record.id == envelope.runID,
              record.triptychID == envelope.triptychID,
              noteIDs(in: record) == Set(envelope.noteIDs),
              authorityState(of: record) == envelope.authorityState else {
            throw LocalResearchExecutionStoreError.executionIdentityMismatch(envelope.runID)
        }
    }

    private static func decodeExecution(
        from data: Data,
        fileName: String,
        triptychID: UUID
    ) throws -> (
        envelope: LocalResearchExecutionEnvelope,
        record: LocalResearchExecutionRecord
    ) {
        let envelope = try decodeEnvelope(
            from: data,
            fileName: fileName,
            triptychID: triptychID
        )
        let record = try decodeCurrentPayload(from: envelope)
        try validatePayload(record, matches: envelope)
        return (envelope, record)
    }

    private static func canonicalizedExecution(
        _ value: LocalResearchExecutionRecord
    ) throws -> (LocalResearchExecutionRecord, Data) {
        let payload = try makeEncoder().encode(value)
        let canonicalRecord = try decode(LocalResearchExecutionRecord.self, from: payload)
        let canonicalPayload = try makeEncoder().encode(canonicalRecord)
        guard canonicalPayload.count <= maximumPayloadByteCount else {
            throw LocalResearchExecutionStoreError.unsafeStore(
                "The Local Research Execution payload exceeds its byte boundary."
            )
        }
        let envelope = LocalResearchExecutionEnvelope(
            record: canonicalRecord,
            payload: canonicalPayload
        )
        let encodedEnvelope = try makeEncoder().encode(envelope)
        let canonicalEnvelope = try decode(
            LocalResearchExecutionEnvelope.self,
            from: encodedEnvelope
        )
        return (canonicalRecord, try makeEncoder().encode(canonicalEnvelope))
    }

    private func requireValidDeletionAuthority(
        _ snapshot: LocalResearchExecutionStoreSnapshot
    ) throws {
        guard snapshot.unscopedRecoveryItems.isEmpty else {
            throw SystemTrashPreparationError.localExecutionRecoveryRequired(
                LocalResearchExecutionRecoveryPreview(
                    triptychID: triptychID,
                    items: snapshot.unscopedRecoveryItems
                )
            )
        }
    }

}
