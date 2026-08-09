import Foundation
import ScholiumContracts

public struct PortableResearchRecordStoreIssue: Hashable, Identifiable, Sendable {
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

/// One decoded portable Record bound to the exact persisted JSON bytes from
/// which it was read. The fingerprint is derived evidence only: it is never
/// written into the schema-5 Record or reconstructed from a re-encoding.
public struct PortableResearchRecordRevision: Hashable, Identifiable, Sendable {
    public let record: PortableResearchRecord
    public let fingerprint: DocumentFingerprint

    public var id: UUID { record.id }

    public init(
        record: PortableResearchRecord,
        fingerprint: DocumentFingerprint
    ) {
        self.record = record
        self.fingerprint = fingerprint
    }
}

public struct PortableResearchRecordListing: Sendable {
    public let revisions: [PortableResearchRecordRevision]
    public let issues: [PortableResearchRecordStoreIssue]
    /// A deterministic identity for the complete valid Record source set.
    /// Malformed and identity-mismatched files remain issues and never enter
    /// this manifest.
    public let sourceManifestHash: String

    public var records: [PortableResearchRecord] {
        revisions.map(\.record)
    }

    public init(
        revisions: [PortableResearchRecordRevision],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.revisions = revisions.sorted(by: Self.ordersRevisions)
        self.issues = issues
        sourceManifestHash = Self.manifestHash(revisions)
    }

    private static func ordersRevisions(
        _ lhs: PortableResearchRecordRevision,
        _ rhs: PortableResearchRecordRevision
    ) -> Bool {
        if lhs.record.finishedAt != rhs.record.finishedAt {
            return lhs.record.finishedAt > rhs.record.finishedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func manifestHash(
        _ revisions: [PortableResearchRecordRevision]
    ) -> String {
        let material = revisions.sorted {
            $0.id.uuidString < $1.id.uuidString
        }.map {
            "\($0.id.uuidString.lowercased())\u{1F}"
                + "\($0.fingerprint.sha256)\u{1F}"
                + "\($0.fingerprint.byteCount)"
        }.joined(separator: "\u{1E}")
        return DocumentFingerprint(content: material).sha256
    }
}

public struct PortableSettlementListing: Sendable {
    public let settlements: [SettlementRecord]
    public let issues: [PortableResearchRecordStoreIssue]

    public init(
        settlements: [SettlementRecord],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.settlements = settlements
        self.issues = issues
    }
}

public struct PortableResearchDiscussionListing: Sendable {
    public let discussions: [PortableResearchDiscussion]
    public let issues: [PortableResearchRecordStoreIssue]

    public init(
        discussions: [PortableResearchDiscussion],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.discussions = discussions
        self.issues = issues
    }
}

public enum ResearchRecordStoreV1Error: LocalizedError, Sendable {
    case unsafeStore(String)
    case replacementNotCommitted(String)
    case replacementCommitUncertain(String)
    case lifecycleNotCommitted(String)
    case lifecycleCommitUncertain(String)
    case recordAlreadyExists(UUID)
    case recordNotFound(UUID)
    case recordPermanentlyDeleted(UUID)
    case recordIdentityMismatch(UUID)
    case recommendationNotFound(UUID)
    case recordTooLarge(Int)
    case coordinationFailed(String)
    case discussionAlreadyExists(UUID)
    case activeDiscussionAlreadyExists(primaryNoteID: UUID, discussionID: UUID)
    case noteDeletionInProgress(UUID)
    case discussionNotFound(UUID)
    case discussionFinishConflict(UUID)
    case executionAlreadyExists(UUID)
    case executionNotFound(UUID)
    case executionAlreadyCompleted(UUID)
    case settlementChanged(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsafeStore(let reason):
            "The Research Record store is unsafe or unavailable: \(reason)"
        case .replacementNotCommitted(let reason):
            "The Research Record replacement did not commit: \(reason)"
        case .replacementCommitUncertain(let reason):
            "The Research Record replacement may have committed: \(reason)"
        case .lifecycleNotCommitted(let reason):
            "The Research Record deletion did not commit: \(reason)"
        case .lifecycleCommitUncertain(let reason):
            "The Research Record deletion may have committed: \(reason)"
        case .recordAlreadyExists(let id):
            "Research Record \(id.uuidString) already exists."
        case .recordNotFound(let id):
            "Research Record \(id.uuidString) was not found."
        case .recordPermanentlyDeleted(let id):
            "Research Record \(id.uuidString) was permanently deleted."
        case .recordIdentityMismatch(let id):
            "Research Record \(id.uuidString) does not match its file identity."
        case .recommendationNotFound(let id):
            "Literature recommendation \(id.uuidString) was not found in its Research Record."
        case .recordTooLarge(let count):
            "The Research Record exceeds the \(count)-byte storage boundary."
        case .coordinationFailed(let reason):
            "Portable Research Record coordination failed: \(reason)"
        case .discussionAlreadyExists(let id):
            "Discussion \(id.uuidString) already exists."
        case .activeDiscussionAlreadyExists(let primaryNoteID, let discussionID):
            "Note \(primaryNoteID.uuidString) already has active Discussion \(discussionID.uuidString)."
        case .noteDeletionInProgress(let noteID):
            "Note \(noteID.uuidString) is being permanently deleted and cannot enter a Discussion."
        case .discussionNotFound(let id):
            "Discussion \(id.uuidString) was not found."
        case .discussionFinishConflict(let id):
            "Discussion \(id.uuidString) conflicts with a finished Research Record."
        case .executionAlreadyExists(let id):
            "Research execution \(id.uuidString) already exists."
        case .executionNotFound(let id):
            "Research execution \(id.uuidString) was not found."
        case .executionAlreadyCompleted(let id):
            "Research execution \(id.uuidString) already has different completion evidence."
        case .settlementChanged(let noteID):
            "The current Settle state for \(noteID.uuidString) changed during the transaction."
        }
    }
}

/// Portable, one-file-per-record storage beside Works.
///
/// The actor serializes callers in one process. A machine-local advisory lock
/// serializes cooperating Scholium processes, while NSFileCoordinator gives
/// registered sync/file-provider participants a chance to coordinate access.
/// Every actual file open remains descriptor-relative and no-follow.
public actor PortableResearchRecordStore {
    private static let maximumRecordByteCount = 8 * 1024 * 1024
    private static let recordsDirectory = "records"

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private var storage: SecureRecordDirectory
    private let deletionMarkers: SecureRecordDirectory
    private var recordDeletionMarkers: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(
        controlURL: URL,
        applicationSupportURL: URL,
        triptychID: UUID
    ) throws {
        self.triptychID = triptychID
        storageURL = controlURL
            .appendingPathComponent("research-records", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        let initialStorage = SecureRecordDirectory(
            trustedRootURL: controlURL,
            components: ["research-records", "v1"],
            directoryMode: 0o755,
            fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount
        )
        storage = initialStorage
        let coordinationDirectory = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        try coordinationDirectory.ensureDirectories([])
        deletionMarkers = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "portable-record-deletions-v1",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 256
        )
        try deletionMarkers.ensureDirectories([])
        let initialRecordDeletionMarkers = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "portable-record-deletion-tombstones-v1",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 256
        )
        recordDeletionMarkers = initialRecordDeletionMarkers
        try initialRecordDeletionMarkers.ensureDirectories([])
        do {
            lock = try AdvisoryFileLock(
                directory: coordinationDirectory,
                fileName: "portable-records-v1.lock"
            )
        } catch {
            throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
        }
        try lock.withExclusiveLock {
            try deletionMarkers.removeAbandonedStagingFiles(in: [nil])
            try initialRecordDeletionMarkers.removeAbandonedStagingFiles(in: [nil])
            try Self.coordinateWrite(at: controlURL) {
                let directories = ["active", Self.recordsDirectory, "settlements"]
                try initialStorage.ensureDirectories(directories)
                try initialStorage.removeAbandonedStagingFiles(
                    in: directories.map(Optional.some)
                )
                try initialStorage.recoverAbandonedDeletionFiles(in: "records")
                try Self.recoverFinishedDiscussionCutovers(
                    storage: initialStorage,
                    triptychID: triptychID
                )
            }
        }
    }

    #if DEBUG
    /// Package-scoped deterministic seams for replacement-phase recovery
    /// tests. They change no path, mode, or byte boundary and are absent from
    /// release builds.
    package func setPreCommitFaultForTesting(
        _ fault: (@Sendable (String) throws -> Void)?
    ) {
        storage = SecureRecordDirectory(
            trustedRootURL: storage.trustedRootURL,
            components: storage.components,
            directoryMode: storage.directoryMode,
            fileMode: storage.fileMode,
            maximumByteCount: storage.maximumByteCount,
            preCommitFault: fault,
            postCommitFault: storage.postCommitFault
        )
    }

    package func setPostCommitFaultForTesting(
        _ fault: (@Sendable (String) throws -> Void)?
    ) {
        storage = SecureRecordDirectory(
            trustedRootURL: storage.trustedRootURL,
            components: storage.components,
            directoryMode: storage.directoryMode,
            fileMode: storage.fileMode,
            maximumByteCount: storage.maximumByteCount,
            preCommitFault: storage.preCommitFault,
            postCommitFault: fault
        )
    }

    package func setRecordDeletionMarkerPostCommitFaultForTesting(
        _ fault: (@Sendable (String) throws -> Void)?
    ) {
        recordDeletionMarkers = SecureRecordDirectory(
            trustedRootURL: recordDeletionMarkers.trustedRootURL,
            components: recordDeletionMarkers.components,
            directoryMode: recordDeletionMarkers.directoryMode,
            fileMode: recordDeletionMarkers.fileMode,
            maximumByteCount: recordDeletionMarkers.maximumByteCount,
            preCommitFault: recordDeletionMarkers.preCommitFault,
            postCommitFault: fault
        )
    }
    #endif

    @discardableResult
    public func createFinishedRecord(
        _ record: PortableResearchRecord
    ) throws -> PortableResearchRecord {
        guard record.triptychID == triptychID else {
            throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
        }
        let (canonicalRecord, data) = try Self.validatedStorageEncoding(of: record)
        return try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                try requireRecordNotPermanentlyDeleted(id: record.id)
                do {
                    let readback = try storage.createExclusive(
                        data,
                        directory: Self.recordsDirectory,
                        fileName: Self.fileName(record.id)
                    )
                    let stored = try Self.decode(
                        PortableResearchRecord.self,
                        from: readback
                    )
                    guard stored == canonicalRecord else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                    }
                    return stored
                } catch let error as SecureRecordDirectoryError {
                    if case .alreadyExists = error {
                        let existing = try readRecord(id: record.id)
                        if existing == canonicalRecord { return existing }
                        throw ResearchRecordStoreV1Error.recordAlreadyExists(record.id)
                    }
                    throw Self.map(error)
                }
            }
        }
    }

    public func record(id: UUID) throws -> PortableResearchRecord {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                try readRecord(id: id)
            }
        }
    }

    /// Removes only the selected portable record. Source Markdown, portable
    /// settlements, checkpoints, and machine-local recovery evidence are
    /// owned by separate stores and are intentionally outside this operation.
    @discardableResult
    public func deletePermanently(id: UUID) throws -> PortableResearchRecord {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let exactData: Data
                let record: PortableResearchRecord
                do {
                    exactData = try storage.read(
                        directory: Self.recordsDirectory,
                        fileName: Self.fileName(id)
                    )
                    record = try Self.decode(PortableResearchRecord.self, from: exactData)
                    guard record.id == id, record.triptychID == triptychID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
                    }
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error {
                        throw ResearchRecordStoreV1Error.recordNotFound(id)
                    }
                    throw Self.map(error)
                }
                try establishRecordDeletionMarker(id: id)
                do {
                    try storage.remove(
                        directory: Self.recordsDirectory,
                        fileName: Self.fileName(id),
                        expected: exactData
                    )
                    return record
                } catch let error as SecureRecordDirectoryError {
                    switch error {
                    case .replacementCommitUncertain:
                        do {
                            let source = try storage.readIfPresent(
                                directory: Self.recordsDirectory,
                                fileName: Self.fileName(id)
                            )
                            let isolated = try storage.readIfPresent(
                                directory: Self.recordsDirectory,
                                fileName: ".scholium-deleting-\(Self.fileName(id))"
                            )
                            if source == nil, isolated == nil {
                                try storage.synchronize(
                                    directories: [
                                        Self.recordsDirectory,
                                    ]
                                )
                                return record
                            }
                            if source == exactData, isolated == nil {
                                throw ResearchRecordStoreV1Error.lifecycleNotCommitted(
                                    "The exact record remains in Records."
                                )
                            }
                        } catch let reconciled as ResearchRecordStoreV1Error {
                            throw reconciled
                        } catch {
                            // Preserve the original uncertainty when the
                            // recovery-state inspection itself is unsafe.
                        }
                        throw ResearchRecordStoreV1Error.lifecycleCommitUncertain(
                            error.localizedDescription
                        )
                    default:
                        throw ResearchRecordStoreV1Error.lifecycleNotCommitted(
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }

    public func listing() throws -> PortableResearchRecordListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                var revisions: [PortableResearchRecordRevision] = []
                var issues: [PortableResearchRecordStoreIssue] = []
                let files = try storage.fileNames(in: Self.recordsDirectory)
                for fileName in files where fileName.hasSuffix(".json") {
                    do {
                        let data = try storage.read(
                            directory: Self.recordsDirectory,
                            fileName: fileName
                        )
                        let record = try Self.decode(
                            PortableResearchRecord.self,
                            from: data
                        )
                        guard fileName == Self.fileName(record.id),
                              record.triptychID == triptychID else {
                            throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                                record.id
                            )
                        }
                        revisions.append(PortableResearchRecordRevision(
                            record: record,
                            fingerprint: DocumentFingerprint(data: data)
                        ))
                    } catch {
                        issues.append(PortableResearchRecordStoreIssue(
                            location: Self.recordsDirectory,
                            fileName: fileName,
                            reason: error.localizedDescription
                        ))
                    }
                }
                return PortableResearchRecordListing(
                    revisions: revisions,
                    issues: issues.sorted { $0.id < $1.id }
                )
            }
        }
    }

    /// Atomically replaces the one current evaluation partition after both
    /// its own optimistic revision and the immutable finalized result have
    /// been revalidated under the portable-record lock.
    @discardableResult
    public func setResearcherEvaluation(
        _ draft: ResearcherEvaluationDraft,
        recordID: UUID,
        expectedEvaluationRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint,
        updatedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard try current.finalizedResultFingerprint()
                    == expectedResultFingerprint else {
                throw PortableResearchEvaluationMutationError.finalizedResultChanged
            }
            guard current.researcherEvaluation?.revision
                    == expectedEvaluationRevision else {
                throw PortableResearchEvaluationMutationError.staleEvaluationRevision
            }
            let evaluation = try PortableResearcherEvaluation(
                observedIssues: draft.observedIssues,
                noIssuesObserved: draft.noIssuesObserved,
                valuableDiscovery: draft.valuableDiscovery,
                note: draft.note,
                updatedAt: updatedAt
            )
            return try Self.replacingEvaluation(
                in: current,
                evaluation: evaluation
            )
        }
    }

    /// Clearing is the same compare-and-swap operation as save. Absence is
    /// represented only by nil; no tombstone or second evaluation owner is
    /// created.
    @discardableResult
    public func clearResearcherEvaluation(
        recordID: UUID,
        expectedEvaluationRevision: UUID,
        expectedResultFingerprint: DocumentFingerprint
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard try current.finalizedResultFingerprint()
                    == expectedResultFingerprint else {
                throw PortableResearchEvaluationMutationError.finalizedResultChanged
            }
            guard current.researcherEvaluation?.revision
                    == expectedEvaluationRevision else {
                throw PortableResearchEvaluationMutationError.staleEvaluationRevision
            }
            return try Self.replacingEvaluation(in: current, evaluation: nil)
        }
    }

    /// Atomically replaces the one current, still-unhandled Method feedback
    /// comment. The optional source evaluation revision is revalidated under
    /// the same lock; no evaluation text is copied into a second owner.
    @discardableResult
    public func setMethodFeedbackComment(
        _ draft: ResearchMethodFeedbackDraft,
        recordID: UUID,
        expectedCommentRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint,
        updatedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard try current.finalizedResultFingerprint()
                    == expectedResultFingerprint else {
                throw PortableResearchMethodFeedbackMutationError
                    .finalizedResultChanged
            }
            guard current.methodFeedbackComment?.revision
                    == expectedCommentRevision else {
                throw PortableResearchMethodFeedbackMutationError
                    .staleCommentRevision
            }
            if let sourceRevision = draft.sourceEvaluationRevision {
                guard current.researcherEvaluation?.revision == sourceRevision else {
                    throw PortableResearchMethodFeedbackMutationError
                        .sourceEvaluationChanged
                }
            }
            let comment = try PortableResearchMethodFeedbackComment(
                text: draft.text,
                sourceEvaluationRevision: draft.sourceEvaluationRevision,
                updatedAt: updatedAt
            )
            return try Self.replacingMethodFeedbackComment(
                in: current,
                comment: comment
            )
        }
    }

    @discardableResult
    public func clearMethodFeedbackComment(
        recordID: UUID,
        expectedCommentRevision: UUID,
        expectedResultFingerprint: DocumentFingerprint
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard try current.finalizedResultFingerprint()
                    == expectedResultFingerprint else {
                throw PortableResearchMethodFeedbackMutationError
                    .finalizedResultChanged
            }
            guard current.methodFeedbackComment?.revision
                    == expectedCommentRevision else {
                throw PortableResearchMethodFeedbackMutationError
                    .staleCommentRevision
            }
            return try Self.replacingMethodFeedbackComment(
                in: current,
                comment: nil
            )
        }
    }

    /// Replaces only one occurrence's researcher-owned handled state. The
    /// current record is reread under the portable-record lock so concurrent
    /// disposition, tombstone, and other record content are preserved by the
    /// single atomic replacement.
    @discardableResult
    public func setRecommendationDisposition(
        _ status: ResearchLiteratureRecommendationDispositionStatus,
        recommendationID: UUID,
        recordID: UUID,
        updatedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard let index = current.literatureRecommendations.firstIndex(where: {
                $0.id == recommendationID
            }) else {
                throw ResearchRecordStoreV1Error.recommendationNotFound(recommendationID)
            }
            let existing = current.literatureRecommendations[index]
            guard existing.disposition.status != status else { return current }
            let disposition = try PortableResearchRecommendationDisposition(
                status: status,
                updatedAt: updatedAt,
                researcherNote: existing.disposition.researcherNote
            )
            var recommendations = current.literatureRecommendations
            recommendations[index] = try existing.replacingDisposition(disposition)
            return try Self.replacingRecommendations(
                in: current,
                recommendations: recommendations
            )
        }
    }

    /// Replaces only one occurrence's optional researcher note and preserves
    /// its handled state. Passing nil or whitespace clears the note.
    @discardableResult
    public func setRecommendationNote(
        _ note: String?,
        recommendationID: UUID,
        recordID: UUID,
        updatedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard let index = current.literatureRecommendations.firstIndex(where: {
                $0.id == recommendationID
            }) else {
                throw ResearchRecordStoreV1Error.recommendationNotFound(recommendationID)
            }
            let existing = current.literatureRecommendations[index]
            let disposition = try PortableResearchRecommendationDisposition(
                status: existing.disposition.status,
                updatedAt: updatedAt,
                researcherNote: note
            )
            guard disposition.researcherNote != existing.disposition.researcherNote else {
                return current
            }
            var recommendations = current.literatureRecommendations
            recommendations[index] = try existing.replacingDisposition(disposition)
            return try Self.replacingRecommendations(
                in: current,
                recommendations: recommendations
            )
        }
    }

    private func replaceFinishedRecord(
        id: UUID,
        transform: (PortableResearchRecord) throws -> PortableResearchRecord
    ) throws -> PortableResearchRecord {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let current = try readRecord(id: id)
                let updated = try transform(current)
                guard updated != current else { return current }
                let (canonical, data) = try Self.validatedStorageEncoding(of: updated)
                do {
                    let readback = try storage.replace(
                        data,
                        directory: Self.recordsDirectory,
                        fileName: Self.fileName(id)
                    )
                    let stored = try Self.decode(
                        PortableResearchRecord.self,
                        from: readback
                    )
                    guard stored == canonical else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
                    }
                    return stored
                } catch SecureRecordDirectoryError.replacementNotCommitted(
                    let reason
                ) {
                    throw ResearchRecordStoreV1Error.replacementNotCommitted(reason)
                } catch SecureRecordDirectoryError.replacementCommitUncertain(
                    let reason
                ) {
                    throw ResearchRecordStoreV1Error.replacementCommitUncertain(reason)
                } catch let error as SecureRecordDirectoryError {
                    throw Self.map(error)
                }
            }
        }
    }

    /// Establishes a durable machine-local gate before permanent deletion
    /// mutates Markdown or identity state. The marker and active-record writes
    /// share the same cross-process lock, so a creator either wins before the
    /// gate and is later purged, or observes the gate and fails closed.
    public func markNoteDeletionStarted(noteIDs: Set<UUID>) throws {
        guard !noteIDs.isEmpty else { return }
        try lock.withExclusiveLock {
            for noteID in noteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                let data = Self.deletionMarkerData(noteID)
                do {
                    _ = try deletionMarkers.createExclusive(
                        data,
                        directory: nil,
                        fileName: Self.fileName(noteID)
                    )
                } catch let error as SecureRecordDirectoryError {
                    if case .alreadyExists = error {
                        let existing = try deletionMarkers.read(
                            directory: nil,
                            fileName: Self.fileName(noteID)
                        )
                        guard existing == data else {
                            throw ResearchRecordStoreV1Error.unsafeStore(
                                "A deletion marker does not match its Note identity."
                            )
                        }
                    } else {
                        throw Self.map(error)
                    }
                }
            }
        }
    }

    /// Removes only rollback-phase gates after the exact deleted Note state has
    /// been restored. Committed deletions retain their identity marker.
    public func clearNoteDeletionMarkers(noteIDs: Set<UUID>) throws {
        guard !noteIDs.isEmpty else { return }
        try lock.withExclusiveLock {
            for noteID in noteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                try deletionMarkers.removeIfPresent(
                    directory: nil,
                    fileName: Self.fileName(noteID)
                )
            }
        }
    }

    @discardableResult
    public func createActiveDiscussion(
        _ discussion: PortableResearchDiscussion
    ) throws -> PortableResearchDiscussion {
        guard discussion.triptychID == triptychID else {
            throw ResearchRecordStoreV1Error.recordIdentityMismatch(discussion.id)
        }
        let (canonical, data) = try Self.canonicalized(discussion)
        guard data.count <= Self.maximumRecordByteCount else {
            throw ResearchRecordStoreV1Error.recordTooLarge(Self.maximumRecordByteCount)
        }
        return try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                try requireNoDeletionMarkers(
                    noteIDs: Set(discussion.participatingNotes.map(\.noteID))
                )
                let active = try activeListingWithoutCoordination()
                guard active.issues.isEmpty else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        active.issues.map(\.id).joined(separator: ", ")
                    )
                }
                if let existing = active.discussions.first(where: { $0.id == discussion.id }) {
                    if existing == canonical { return existing }
                    throw ResearchRecordStoreV1Error.discussionAlreadyExists(discussion.id)
                }
                if let existing = active.discussions.first(where: {
                    $0.primaryNoteID == discussion.primaryNoteID
                }) {
                    throw ResearchRecordStoreV1Error.activeDiscussionAlreadyExists(
                        primaryNoteID: discussion.primaryNoteID,
                        discussionID: existing.id
                    )
                }
                do {
                    let readback = try storage.createExclusive(
                        data,
                        directory: "active",
                        fileName: Self.fileName(discussion.id)
                    )
                    let stored = try Self.decode(PortableResearchDiscussion.self, from: readback)
                    guard stored == canonical else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(discussion.id)
                    }
                    return stored
                } catch let error as SecureRecordDirectoryError {
                    if case .alreadyExists = error {
                        let existing = try readDiscussion(id: discussion.id)
                        if existing == canonical { return existing }
                        throw ResearchRecordStoreV1Error.discussionAlreadyExists(discussion.id)
                    }
                    throw Self.map(error)
                }
            }
        }
    }

    public func activeDiscussion(id: UUID) throws -> PortableResearchDiscussion {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                _ = try requireHealthyActiveListing()
                return try readDiscussion(id: id)
            }
        }
    }

    public func activeDiscussionIfPresent(id: UUID) throws -> PortableResearchDiscussion? {
        do {
            return try activeDiscussion(id: id)
        } catch ResearchRecordStoreV1Error.discussionNotFound(_) {
            return nil
        }
    }

    public func activeDiscussions(noteID: UUID? = nil) throws -> PortableResearchDiscussionListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                let listing = try activeListingWithoutCoordination()
                let discussions = listing.discussions.filter { discussion in
                    noteID == nil || discussion.participatingNotes.contains(where: {
                        $0.noteID == noteID
                    })
                }
                return PortableResearchDiscussionListing(
                    discussions: discussions,
                    issues: listing.issues
                )
            }
        }
    }

    @discardableResult
    public func appendDiscussionStatement(
        _ statement: PortableResearchStatement,
        to discussionID: UUID,
        at updatedAt: Date = Date()
    ) throws -> PortableResearchDiscussion {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                _ = try requireHealthyActiveListing()
                let current = try readDiscussion(id: discussionID)
                try requireNoDeletionMarkers(
                    noteIDs: Set(current.participatingNotes.map(\.noteID))
                )
                let updated = try current.appending(statement, at: updatedAt)
                if updated == current { return current }
                let (canonical, data) = try Self.canonicalized(updated)
                let readback = try storage.replace(
                    data,
                    directory: "active",
                    fileName: Self.fileName(discussionID)
                )
                let stored = try Self.decode(PortableResearchDiscussion.self, from: readback)
                guard stored == canonical else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(discussionID)
                }
                return stored
            }
        }
    }

    /// Atomically turns one Comment-only draft into the exact resolved
    /// Discuss Action. Concurrently appended Comments are preserved because
    /// the replacement is derived from the current file under the store lock.
    @discardableResult
    public func activateDiscussion(
        id: UUID,
        action: ResearchActionRecordIdentity,
        method: PortableResearchMethodReference,
        participatingNotes: [PortableResearchNoteRevision],
        statement: PortableResearchStatement,
        at updatedAt: Date = Date()
    ) throws -> PortableResearchDiscussion {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                _ = try requireHealthyActiveListing()
                let current = try readDiscussion(id: id)
                try requireNoDeletionMarkers(
                    noteIDs: Set(participatingNotes.map(\.noteID))
                )
                if current.action == action,
                   current.method == method,
                   current.participatingNotes == participatingNotes,
                   current.statements.contains(statement) {
                    return current
                }
                let updated = try current.activating(
                    action: action,
                    method: method,
                    participatingNotes: participatingNotes,
                    statement: statement,
                    at: updatedAt
                )
                let (canonical, data) = try Self.canonicalized(updated)
                guard data.count <= Self.maximumRecordByteCount else {
                    throw ResearchRecordStoreV1Error.recordTooLarge(
                        Self.maximumRecordByteCount
                    )
                }
                let readback = try storage.replace(
                    data,
                    directory: "active",
                    fileName: Self.fileName(id)
                )
                let stored = try Self.decode(
                    PortableResearchDiscussion.self,
                    from: readback
                )
                guard stored == canonical else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
                }
                return stored
            }
        }
    }

    /// Refreshes passage attachment only when the authoritative Markdown
    /// yields one reliable location. Ambiguity is retained explicitly and no
    /// scholarly statement text or note bytes are changed.
    @discardableResult
    public func reconcileDiscussionPassages(
        id: UUID,
        primaryDocument: NoteDocument
    ) throws -> PortableResearchDiscussion {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                _ = try requireHealthyActiveListing()
                let current = try readDiscussion(id: id)
                var changed = false
                let statements = try current.statements.map { statement in
                    guard let passage = statement.passage else { return statement }
                    if passage.fingerprint == primaryDocument.fingerprint,
                       passage.state == .attached {
                        return statement
                    }
                    let resolved = CommentAnchorBuilder.anchor(
                        forRenderedQuotation: passage.quotation,
                        contextBefore: passage.contextBefore,
                        contextAfter: passage.contextAfter,
                        in: primaryDocument
                    ) ?? passage.selectedText.flatMap {
                        CommentAnchorBuilder.anchor(
                            forRenderedQuotation: $0,
                            contextBefore: passage.contextBefore,
                            contextAfter: passage.contextAfter,
                            in: primaryDocument
                        )
                    }
                    var replacement = resolved ?? passage
                    if resolved == nil { replacement.state = .needsReattachment }
                    guard replacement != passage else { return statement }
                    changed = true
                    return try statement.replacingPassage(replacement)
                }
                guard changed else { return current }
                let updated = try current.replacingStatements(statements)
                let (canonical, data) = try Self.canonicalized(updated)
                let readback = try storage.replace(
                    data,
                    directory: "active",
                    fileName: Self.fileName(id)
                )
                let stored = try Self.decode(PortableResearchDiscussion.self, from: readback)
                guard stored == canonical else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
                }
                return stored
            }
        }
    }

    /// Completes one active Discussion as one finished record. The advisory
    /// lock hides the create-and-remove pair from every cooperating Scholium
    /// process. If the process stops between those writes, initialization
    /// reconciles the exact matching pair before exposing the store.
    @discardableResult
    public func finishDiscussion(
        id: UUID,
        participatingNotes: [PortableResearchNoteRevision],
        finishedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                _ = try requireHealthyActiveListing()
                let discussion: PortableResearchDiscussion
                do {
                    discussion = try readDiscussion(id: id)
                } catch ResearchRecordStoreV1Error.discussionNotFound(_) {
                    let existing = try readRecord(id: id)
                    guard existing.kind == .discussion else {
                        throw ResearchRecordStoreV1Error.discussionFinishConflict(id)
                    }
                    return existing
                }
                try requireNoDeletionMarkers(
                    noteIDs: Set(discussion.participatingNotes.map(\.noteID))
                )
                let record = try discussion.finishedRecord(
                    participatingNotes: participatingNotes,
                    finishedAt: finishedAt
                )
                let (canonical, data) = try Self.validatedStorageEncoding(of: record)
                do {
                    let readback = try storage.createExclusive(
                        data,
                        directory: Self.recordsDirectory,
                        fileName: Self.fileName(id)
                    )
                    let stored = try Self.decode(PortableResearchRecord.self, from: readback)
                    guard stored == canonical else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
                    }
                } catch let error as SecureRecordDirectoryError {
                    if case .alreadyExists = error {
                        let existing = try readRecord(id: id)
                        guard Self.isFinished(existing, from: discussion) else {
                            throw ResearchRecordStoreV1Error.discussionFinishConflict(id)
                        }
                    } else {
                        throw Self.map(error)
                    }
                }
                try storage.removeIfPresent(
                    directory: "active",
                    fileName: Self.fileName(id)
                )
                return try readRecord(id: id)
            }
        }
    }

    /// Active drafts are not retained after one of their participants is
    /// permanently deleted. Finished records survive and are rewritten only
    /// to replace the deleted participant's ending revision with a tombstone.
    public func handlePermanentDeletion(noteIDs: Set<UUID>) throws {
        guard !noteIDs.isEmpty else { return }
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let active = try activeListingWithoutCoordination()
                guard active.issues.isEmpty else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        active.issues.map(\.id).joined(separator: ", ")
                    )
                }
                for discussion in active.discussions
                    where !Set(discussion.participatingNotes.map(\.noteID))
                        .isDisjoint(with: noteIDs) {
                    try storage.removeIfPresent(
                        directory: "active",
                        fileName: Self.fileName(discussion.id)
                    )
                }
                for fileName in try storage.fileNames(in: Self.recordsDirectory)
                    where fileName.hasSuffix(".json") {
                        let data = try storage.read(
                            directory: Self.recordsDirectory,
                            fileName: fileName
                        )
                        let record = try Self.decode(PortableResearchRecord.self, from: data)
                        guard record.triptychID == triptychID,
                              fileName == Self.fileName(record.id) else {
                            throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                        }
                        guard record.participatingNotes.contains(where: {
                            noteIDs.contains($0.noteID) && !$0.isTombstone
                        }) else { continue }
                        let updatedNotes = try record.participatingNotes.map { note in
                            guard noteIDs.contains(note.noteID) else { return note }
                            return try PortableResearchNoteRevision(
                                noteID: note.noteID,
                                note: note.note,
                                role: note.role,
                                title: note.title,
                                startingRevision: note.startingRevision,
                                endingRevision: nil,
                                isTombstone: true
                            )
                        }
                        let updated = try Self.replacingParticipants(
                            in: record,
                            with: updatedNotes
                        )
                        let (_, encoded) = try Self.canonicalized(updated)
                        _ = try storage.replace(
                            encoded,
                            directory: Self.recordsDirectory,
                            fileName: fileName
                        )
                }
            }
        }
    }

    @discardableResult
    public func settle(
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        researcher: String = "Researcher",
        rationale: String?,
        settledAt: Date = Date()
    ) throws -> SettlementRecord {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let fileName = Self.fileName(noteID)
                let current: PortableSettlementState?
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: fileName
                    )
                    current = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error {
                        current = nil
                    } else {
                        throw Self.map(error)
                    }
                }
                if let current {
                    guard current.triptychID == triptychID,
                          current.settlement.noteID == noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                    }
                }
                let settlement = SettlementRecord(
                    noteID: noteID,
                    fingerprint: fingerprint,
                    settledAt: settledAt,
                    researcher: researcher,
                    rationale: rationale
                )
                let state = try PortableSettlementState(
                    triptychID: triptychID,
                    settlement: settlement
                )
                let (canonicalState, data) = try Self.canonicalized(state)
                let readback: Data
                do {
                    readback = try storage.replace(
                        data,
                        directory: "settlements",
                        fileName: fileName
                    )
                } catch SecureRecordDirectoryError.replacementNotCommitted(
                    let reason
                ) {
                    throw ResearchRecordStoreV1Error.replacementNotCommitted(reason)
                } catch SecureRecordDirectoryError.replacementCommitUncertain(
                    let reason
                ) {
                    throw ResearchRecordStoreV1Error.replacementCommitUncertain(reason)
                }
                let stored = try Self.decode(
                    PortableSettlementState.self,
                    from: readback
                )
                guard stored == canonicalState else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                }
                return stored.settlement
            }
        }
    }

    public func settlementListing() throws -> PortableSettlementListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                var settlements: [SettlementRecord] = []
                var issues: [PortableResearchRecordStoreIssue] = []
                for fileName in try storage.fileNames(in: "settlements")
                    where fileName.hasSuffix(".json") {
                    do {
                        let data = try storage.read(
                            directory: "settlements",
                            fileName: fileName
                        )
                        let state = try Self.decode(
                            PortableSettlementState.self,
                            from: data
                        )
                        guard state.triptychID == triptychID,
                              fileName == Self.fileName(state.settlement.noteID) else {
                            throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                                state.settlement.noteID
                            )
                        }
                        settlements.append(state.settlement)
                    } catch {
                        issues.append(PortableResearchRecordStoreIssue(
                            location: "settlements",
                            fileName: fileName,
                            reason: error.localizedDescription
                        ))
                    }
                }
                return PortableSettlementListing(
                    settlements: settlements.sorted {
                        if $0.settledAt != $1.settledAt {
                            return $0.settledAt > $1.settledAt
                        }
                        return $0.noteID.uuidString < $1.noteID.uuidString
                    },
                    issues: issues.sorted { $0.id < $1.id }
                )
            }
        }
    }

    public func latestSettlement(noteID: UUID) throws -> SettlementRecord? {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: Self.fileName(noteID)
                    )
                    let state = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                    guard state.triptychID == triptychID,
                          state.settlement.noteID == noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                    }
                    return state.settlement
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error { return nil }
                    throw Self.map(error)
                }
            }
        }
    }

    public func purgeSettlement(noteID: UUID) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                try storage.removeIfPresent(
                    directory: "settlements",
                    fileName: Self.fileName(noteID)
                )
            }
        }
    }

    /// Removes only the exact Settle state captured by a rollback journal.
    /// Passing nil proves that no Settle existed at capture time; a newly
    /// appearing state then aborts the transaction instead of being deleted.
    public func purgeSettlement(
        noteID: UUID,
        matching expected: SettlementRecord?
    ) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let current: PortableSettlementState
                do {
                    current = try Self.decode(
                        PortableSettlementState.self,
                        from: storage.read(
                            directory: "settlements",
                            fileName: Self.fileName(noteID)
                        )
                    )
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error { return }
                    throw Self.map(error)
                }
                guard current.triptychID == triptychID,
                      current.settlement.noteID == noteID else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                }
                guard let expected, current.settlement == expected else {
                    throw ResearchRecordStoreV1Error.settlementChanged(noteID)
                }
                try storage.removeIfPresent(
                    directory: "settlements",
                    fileName: Self.fileName(noteID)
                )
            }
        }
    }

    public func restoreSettlement(_ settlement: SettlementRecord) throws {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                do {
                    let data = try storage.read(
                        directory: "settlements",
                        fileName: Self.fileName(settlement.noteID)
                    )
                    let current = try Self.decode(
                        PortableSettlementState.self,
                        from: data
                    )
                    guard current.triptychID == triptychID,
                          current.settlement.noteID == settlement.noteID else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                            settlement.noteID
                        )
                    }
                    guard current.settlement == settlement else {
                        throw ResearchRecordStoreV1Error.settlementChanged(
                            settlement.noteID
                        )
                    }
                    return
                } catch let error as SecureRecordDirectoryError {
                    if case .notFound = error {
                        // Restore the journaled preimage below.
                    } else {
                        throw Self.map(error)
                    }
                }
                let state = try PortableSettlementState(
                    triptychID: triptychID,
                    settlement: settlement
                )
                let (canonicalState, data) = try Self.canonicalized(state)
                let readback = try storage.replace(
                    data,
                    directory: "settlements",
                    fileName: Self.fileName(settlement.noteID)
                )
                let stored = try Self.decode(
                    PortableSettlementState.self,
                    from: readback
                )
                guard stored == canonicalState else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                        settlement.noteID
                    )
                }
            }
        }
    }

    private func readDiscussion(id: UUID) throws -> PortableResearchDiscussion {
        do {
            let data = try storage.read(
                directory: "active",
                fileName: Self.fileName(id)
            )
            let discussion = try Self.decode(PortableResearchDiscussion.self, from: data)
            guard discussion.id == id, discussion.triptychID == triptychID else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return discussion
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw ResearchRecordStoreV1Error.discussionNotFound(id)
            }
            throw Self.map(error)
        }
    }

    private func activeListingWithoutCoordination() throws -> PortableResearchDiscussionListing {
        var discussions: [PortableResearchDiscussion] = []
        var issues: [PortableResearchRecordStoreIssue] = []
        for fileName in try storage.fileNames(in: "active") where fileName.hasSuffix(".json") {
            do {
                let discussion = try Self.decode(
                    PortableResearchDiscussion.self,
                    from: storage.read(directory: "active", fileName: fileName)
                )
                guard discussion.triptychID == triptychID,
                      fileName == Self.fileName(discussion.id) else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(discussion.id)
                }
                discussions.append(discussion)
            } catch {
                issues.append(PortableResearchRecordStoreIssue(
                    location: "active",
                    fileName: fileName,
                    reason: error.localizedDescription
                ))
            }
        }
        let byPrimary = Dictionary(grouping: discussions, by: \.primaryNoteID)
        for (primaryNoteID, duplicates) in byPrimary where duplicates.count > 1 {
            let ids = duplicates.map(\.id).sorted { $0.uuidString < $1.uuidString }
            for discussionID in ids {
                issues.append(PortableResearchRecordStoreIssue(
                    location: "active",
                    fileName: Self.fileName(discussionID),
                    reason: "Primary Note \(primaryNoteID.uuidString) has multiple active Discussions: "
                        + ids.map(\.uuidString).joined(separator: ", ")
                ))
            }
        }
        return PortableResearchDiscussionListing(
            discussions: discussions.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id.uuidString < $1.id.uuidString
            },
            issues: issues.sorted { $0.id < $1.id }
        )
    }

    private func requireHealthyActiveListing() throws -> PortableResearchDiscussionListing {
        let listing = try activeListingWithoutCoordination()
        guard listing.issues.isEmpty else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
        return listing
    }

    private func requireNoDeletionMarkers(noteIDs: Set<UUID>) throws {
        for noteID in noteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            do {
                let data = try deletionMarkers.read(
                    directory: nil,
                    fileName: Self.fileName(noteID)
                )
                guard data == Self.deletionMarkerData(noteID) else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        "A deletion marker does not match its Note identity."
                    )
                }
                throw ResearchRecordStoreV1Error.noteDeletionInProgress(noteID)
            } catch let error as SecureRecordDirectoryError {
                if case .notFound = error { continue }
                throw Self.map(error)
            }
        }
    }

    /// A machine-local completion may outlive its portable projection so an
    /// interrupted create can be repaired. Permanent deletion is different:
    /// this tombstone records researcher intent under the same cross-process
    /// lock as create/delete and prevents a later completion retry from
    /// recreating the selected Record.
    private func requireRecordNotPermanentlyDeleted(id: UUID) throws {
        let expected = Self.recordDeletionMarkerData(id)
        do {
            let observed = try recordDeletionMarkers.read(
                directory: nil,
                fileName: Self.fileName(id)
            )
            guard observed == expected else {
                throw ResearchRecordStoreV1Error.unsafeStore(
                    "A permanent Record-deletion tombstone does not match its identity."
                )
            }
            throw ResearchRecordStoreV1Error.recordPermanentlyDeleted(id)
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error { return }
            throw Self.map(error)
        }
    }

    private func establishRecordDeletionMarker(id: UUID) throws {
        let data = Self.recordDeletionMarkerData(id)
        do {
            _ = try recordDeletionMarkers.createExclusive(
                data,
                directory: nil,
                fileName: Self.fileName(id)
            )
        } catch let error as SecureRecordDirectoryError {
            if case .alreadyExists = error {
                let existing = try recordDeletionMarkers.read(
                    directory: nil,
                    fileName: Self.fileName(id)
                )
                guard existing == data else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        "A permanent Record-deletion tombstone does not match its identity."
                    )
                }
                do {
                    try recordDeletionMarkers.synchronize(directory: nil)
                } catch {
                    throw ResearchRecordStoreV1Error.lifecycleCommitUncertain(
                        "The permanent Record-deletion tombstone is present but its durability could not be confirmed: \(error.localizedDescription)"
                    )
                }
                return
            }
            if case .replacementCommitUncertain = error,
               (try? recordDeletionMarkers.read(
                   directory: nil,
                   fileName: Self.fileName(id)
               )) == data {
                throw ResearchRecordStoreV1Error.lifecycleCommitUncertain(
                    "The permanent Record-deletion tombstone may have committed; the Research Record was retained."
                )
            }
            throw Self.map(error)
        }
    }

    private static func deletionMarkerData(_ noteID: UUID) -> Data {
        Data(
            "{\"note_id\":\"\(noteID.uuidString.lowercased())\",\"schema_version\":1}\n".utf8
        )
    }

    private static func recordDeletionMarkerData(_ recordID: UUID) -> Data {
        Data(
            "{\"record_id\":\"\(recordID.uuidString.lowercased())\",\"schema_version\":1}\n".utf8
        )
    }

    private static func recoverFinishedDiscussionCutovers(
        storage: SecureRecordDirectory,
        triptychID: UUID
    ) throws {
        for fileName in try storage.fileNames(in: "active") where fileName.hasSuffix(".json") {
            let discussion: PortableResearchDiscussion
            do {
                discussion = try decode(
                    PortableResearchDiscussion.self,
                    from: storage.read(directory: "active", fileName: fileName)
                )
                guard discussion.triptychID == triptychID,
                      fileName == Self.fileName(discussion.id) else {
                    continue
                }
            } catch {
                // An unrelated malformed active draft remains visible as a
                // listing issue; recovery never guesses at its identity.
                continue
            }
            let finished: PortableResearchRecord
            do {
                finished = try decode(
                    PortableResearchRecord.self,
                    from: storage.read(directory: "records", fileName: fileName)
                )
            } catch let error as SecureRecordDirectoryError {
                if case .notFound = error { continue }
                throw Self.map(error)
            }
            guard isFinished(finished, from: discussion) else {
                throw ResearchRecordStoreV1Error.discussionFinishConflict(discussion.id)
            }
            try storage.removeIfPresent(directory: "active", fileName: fileName)
        }
    }

    private static func isFinished(
        _ record: PortableResearchRecord,
        from discussion: PortableResearchDiscussion
    ) -> Bool {
        guard let expectedTitle = try? discussion.recordTitle(),
              record.id == discussion.id,
              record.triptychID == discussion.triptychID,
              record.title == expectedTitle,
              record.kind == .discussion,
              record.action == discussion.action,
              record.method == discussion.method,
              record.sourceReference == nil,
              record.primaryNoteID == discussion.primaryNoteID,
              record.statements == discussion.statements,
              record.actuallyUsedMaterials.isEmpty,
              record.confirmedChanges.isEmpty,
              record.discrepancies.isEmpty,
              record.literatureRecommendations.isEmpty,
              record.startedAt == discussion.createdAt,
              record.finishedAt >= discussion.updatedAt else { return false }
        let activeByID = Dictionary(
            uniqueKeysWithValues: discussion.participatingNotes.map { ($0.noteID, $0) }
        )
        guard Set(activeByID.keys) == Set(record.participatingNotes.map(\.noteID)) else {
            return false
        }
        return record.participatingNotes.allSatisfy { note in
            guard let active = activeByID[note.noteID] else { return false }
            return note.note == active.note
                && note.role == active.role
                && note.title == active.title
                && note.startingRevision == active.startingRevision
                && !note.isTombstone
                && note.endingRevision != nil
        }
    }

    private static func replacingParticipants(
        in record: PortableResearchRecord,
        with participatingNotes: [PortableResearchNoteRevision]
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            contextUseReport: record.contextUseReport,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: record.literatureRecommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            researcherEvaluation: record.researcherEvaluation,
            methodFeedbackComment: record.methodFeedbackComment
        )
    }

    private static func replacingRecommendations(
        in record: PortableResearchRecord,
        recommendations: [ResearchLiteratureRecommendation]
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            contextUseReport: record.contextUseReport,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: recommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            researcherEvaluation: record.researcherEvaluation,
            methodFeedbackComment: record.methodFeedbackComment
        )
    }

    private static func replacingEvaluation(
        in record: PortableResearchRecord,
        evaluation: PortableResearcherEvaluation?
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            contextUseReport: record.contextUseReport,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: record.literatureRecommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            researcherEvaluation: evaluation,
            methodFeedbackComment: record.methodFeedbackComment
        )
    }

    private static func replacingMethodFeedbackComment(
        in record: PortableResearchRecord,
        comment: PortableResearchMethodFeedbackComment?
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            contextUseReport: record.contextUseReport,
            actuallyUsedMaterials: record.actuallyUsedMaterials,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: record.literatureRecommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            researcherEvaluation: record.researcherEvaluation,
            methodFeedbackComment: comment
        )
    }

    private func readRecord(id: UUID) throws -> PortableResearchRecord {
        do {
            let data = try storage.read(
                directory: Self.recordsDirectory,
                fileName: Self.fileName(id)
            )
            let record = try Self.decode(
                PortableResearchRecord.self,
                from: data
            )
            guard record.id == id, record.triptychID == triptychID else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw ResearchRecordStoreV1Error.recordNotFound(id)
            }
            throw Self.map(error)
        }
    }

    private static func fileName(_ id: UUID) -> String {
        id.uuidString.lowercased() + ".json"
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
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

    /// Validates the exact canonical portable bytes before any machine-local
    /// completion becomes authoritative. This shares the store's encoder and
    /// byte ceiling so an accepted Action can always materialize its Record.
    public nonisolated static func validateStorageEncoding(
        of record: PortableResearchRecord
    ) throws {
        _ = try validatedStorageEncoding(of: record)
    }

    private nonisolated static func validatedStorageEncoding(
        of record: PortableResearchRecord
    ) throws -> (PortableResearchRecord, Data) {
        let encoded = try canonicalized(record)
        guard encoded.1.count <= maximumRecordByteCount else {
            throw ResearchRecordStoreV1Error.recordTooLarge(maximumRecordByteCount)
        }
        return encoded
    }

    private static func map(_ error: SecureRecordDirectoryError) -> Error {
        ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
    }

    private static func coordinateWrite<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(ResearchRecordStoreV1Error.coordinationFailed(
                    "The coordinated Research Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                "The file coordinator did not execute the write."
            )
        }
        return try result.get()
    }

    private static func coordinateRead<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(ResearchRecordStoreV1Error.coordinationFailed(
                    "The coordinated Research Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreV1Error.coordinationFailed(
                "The file coordinator did not execute the read."
            )
        }
        return try result.get()
    }
}

private struct PortableSettlementState: Codable, Hashable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let triptychID: UUID
    let settlement: SettlementRecord

    init(triptychID: UUID, settlement: SettlementRecord) throws {
        guard !settlement.researcher.isEmpty,
              settlement.researcher.utf8.count <= 256,
              ResearchRecordStoreCodingValidation.isValidFingerprint(
                settlement.fingerprint
              ),
              !ResearchRecordStoreCodingValidation.containsAbsolutePath(
                settlement.researcher
              ),
              (settlement.rationale?.utf8.count ?? 0) <= 256 * 1024,
              !ResearchRecordStoreCodingValidation.containsAbsolutePath(
                settlement.rationale ?? ""
              ) else {
            throw PortableResearchRecordError.invalidRecord
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.settlement = settlement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case triptychID = "triptych_id"
        case settlement
    }

    private enum SettlementCodingKeys: String, CodingKey, CaseIterable {
        case id, noteID, fingerprint, settledAt, researcher, rationale
    }

    init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        let settlementDecoder = try container.superDecoder(forKey: .settlement)
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: settlementDecoder,
            allowed: SettlementCodingKeys.allCases.map(\.stringValue)
        )
        let settlementContainer = try settlementDecoder.container(
            keyedBy: SettlementCodingKeys.self
        )
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            settlement: SettlementRecord(
                id: settlementContainer.decode(UUID.self, forKey: .id),
                noteID: settlementContainer.decode(UUID.self, forKey: .noteID),
                fingerprint: settlementContainer.decode(
                    StrictResearchRecordFingerprint.self,
                    forKey: .fingerprint
                ).value,
                settledAt: settlementContainer.decode(Date.self, forKey: .settledAt),
                researcher: settlementContainer.decode(String.self, forKey: .researcher),
                rationale: settlementContainer.decodeIfPresent(
                    String.self,
                    forKey: .rationale
                )
            )
        )
    }
}

private struct StrictResearchRecordFingerprint: Decodable {
    let value: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256, byteCount
    }

    init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
        guard value.byteCount >= 0,
              value.sha256.count == 64,
              value.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw PortableResearchRecordError.invalidRecord
        }
        self.value = value
    }
}

/// Machine-local execution evidence. Protected Function identity and assembled
/// instructions are allowed here and are never projected into the portable
/// record type.
public struct LocalResearchExecutionRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 9

    public let schemaVersion: Int
    public let triptychID: UUID
    public let snapshot: ResearchFunctionSnapshot
    public let preparedInstructions: String
    public var discussion: ResearchDiscussionExecutionContract?
    public var boundedWriteSet: ResearchBoundedWriteSet
    public var writeSetExtensionRecords: [ResearchWriteSetExtensionRecord]
    public var documentWriteRecords: [ResearchDocumentWriteRecord]
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
        discussion: ResearchDiscussionExecutionContract? = nil,
        boundedWriteSet: ResearchBoundedWriteSet? = nil,
        writeSetExtensionRecords: [ResearchWriteSetExtensionRecord] = [],
        documentWriteRecords: [ResearchDocumentWriteRecord] = [],
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
                case .awaitingFidelity, .complete, .unverified, .stale:
                    completionRecommendationShapeMatches = completion
                        .literatureRecommendations.map { $0.count <= 256 } ?? false
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
                && snapshot.checkpointID != nil
                && snapshot.continuationHandoff == nil
                && Set(resolvedWriteSet.entries.map(\.noteID))
                    .isSuperset(of: Set(
                        snapshot.actionSnapshot?.authority.writableNotes
                            .map(\.noteID) ?? []
                    ))
        case .fidelity:
            if case .automatic(let parentRunID)? = snapshot.resolvedFidelityInvocation {
                continuationMatches = snapshot.request.function == .fidelity
                    && snapshot.continuationLineage?.parentRunID == parentRunID
                    && snapshot.checkpointID == nil
                    && snapshot.continuationHandoff == nil
            } else {
                continuationMatches = false
            }
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
        guard snapshot.actionSnapshot != nil,
              snapshot.runID == snapshot.recordID,
              preparedInstructions.utf8.count <= 2 * 1024 * 1024,
              discussion?.id == snapshot.runID || discussion == nil,
              continuationMatches,
              resolvedWriteSet.runID == snapshot.runID,
              resolvedWriteSet.triptychID == triptychID,
              initialWritableIDs.isSubset(of: writeSetIDs),
              writeSetExtensionRecords.count <= 256,
              Set(writeSetExtensionRecords.map(\.id)).count
                == writeSetExtensionRecords.count,
              writeSetExtensionRecords.allSatisfy({
                  $0.runID == snapshot.runID && $0.triptychID == triptychID
              }),
              documentWriteRecords.count
                <= ResearchBoundedWriteSet.maximumWritesPerRun,
              Set(documentWriteRecords.map(\.id)).count
                == documentWriteRecords.count,
              documentWriteRecords.allSatisfy({ $0.runID == snapshot.runID }),
              writeConflictResolutionRecords.count <= 256,
              Set(writeConflictResolutionRecords.map(\.id)).count
                == writeConflictResolutionRecords.count,
              writeConflictResolutionRecords.allSatisfy({ resolution in
                  guard resolution.runID == snapshot.runID,
                        let entry = resolvedWriteSet.entry(
                            handle: resolution.target
                        ) else { return false }
                  return resolution.targetView.role == entry.role
                      && resolution.targetView.relativePath
                        == entry.note.relativePath
                      && resolution.targetView.operations
                        == entry.allowedOperations
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
              writeReport.map({ report in
                  let reportIDs = Set(report.confirmedModifiedNotes.map(\.noteID))
                    .union(report.unmodifiedNotes.map(\.noteID))
                  return reportIDs == Set(resolvedWriteSet.entries.map(\.noteID))
              }) ?? true,
              completion?.runID == snapshot.runID || completion == nil,
              completion?.function == snapshot.request.function || completion == nil,
              completionRecommendationShapeMatches,
              writeReport == nil || completion != nil else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                "The local execution does not match its frozen Action run."
            )
        }
        schemaVersion = Self.currentSchemaVersion
        self.triptychID = triptychID
        self.snapshot = snapshot
        self.preparedInstructions = preparedInstructions
        self.discussion = discussion
        self.boundedWriteSet = resolvedWriteSet
        self.writeSetExtensionRecords = writeSetExtensionRecords
        self.documentWriteRecords = documentWriteRecords
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
        case discussion
        case boundedWriteSet = "bounded_write_set"
        case writeSetExtensionRecords = "write_set_extension_records"
        case documentWriteRecords = "document_write_records"
        case writeConflictResolutionRecords = "write_conflict_resolution_records"
        case continuationRequests = "continuation_requests"
        case methodImprovementRun = "method_improvement_run"
        case resultPayload = "result_payload"
        case writeReport = "write_report"
        case completion
        case completionSubmissionDigest = "completion_submission_digest"
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            snapshot: container.decode(ResearchFunctionSnapshot.self, forKey: .snapshot),
            preparedInstructions: container.decode(
                String.self,
                forKey: .preparedInstructions
            ),
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
            throw ResearchRecordStoreV1Error.unsafeStore(
                "A local execution has no frozen Action for its bounded write set."
            )
        }
        guard action.authority.writableNotes.isEmpty || snapshot.checkpointID != nil else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                "A writable Action has no Before Agent Work checkpoint."
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
                checkpointID: snapshot.checkpointID!,
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

public struct LocalResearchExecutionListing: Sendable {
    public let records: [LocalResearchExecutionRecord]
    public let issues: [PortableResearchRecordStoreIssue]
}


/// Private per-run execution storage. Each run is isolated so one malformed or
/// partially synchronized file cannot make unrelated completion state usable.
public actor LocalResearchExecutionStore {
    private static let maximumExecutionByteCount = 16 * 1024 * 1024

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        self.triptychID = triptychID
        storageURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v8", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: [
                "Triptychs",
                triptychID.uuidString,
                "research-execution-v8",
            ],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: Self.maximumExecutionByteCount
        )
        try storage.ensureDirectories(["critique-handoffs"])
        do {
            lock = try AdvisoryFileLock(
                directory: storage,
                fileName: "execution-v8.lock"
            )
        } catch {
            throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
        }
        try lock.withExclusiveLock {
            try storage.removeAbandonedStagingFiles(in: [nil, "critique-handoffs"])
        }
    }

    @discardableResult
    public func create(
        _ record: LocalResearchExecutionRecord
    ) throws -> LocalResearchExecutionRecord {
        guard record.triptychID == triptychID else {
            throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
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
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                }
                return stored
            } catch let error as SecureRecordDirectoryError {
                if case .alreadyExists = error {
                    let existing = try readRecord(id: record.id)
                    if existing == canonicalRecord { return existing }
                    throw ResearchRecordStoreV1Error.executionAlreadyExists(record.id)
                }
                throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
            }
        }
    }

    public func record(id: UUID) throws -> LocalResearchExecutionRecord {
        try lock.withSharedLock { try readRecord(id: id) }
    }

    public func recordIfPresent(id: UUID) throws -> LocalResearchExecutionRecord? {
        try lock.withSharedLock {
            do { return try readRecord(id: id) }
            catch ResearchRecordStoreV1Error.executionNotFound { return nil }
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
                if let existing = allEntries.first(where: { $0.noteID == entry.noteID }) {
                    guard existing == entry else {
                        throw ResearchBoundedWriteSetError.invalidEntry
                    }
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
    /// refreshes only its exact write-set member. Existing checkpoints and
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
                      resolution.checkpointID == refreshedEntry.checkpointID,
                      resolution.observedRevision
                        == refreshedEntry.expectedRevision,
                      resolution.targetView
                        == ResearchBoundedWriteSetViewEntry(refreshedEntry),
                      refreshedEntry.handle == entry.handle,
                      refreshedEntry.noteID == entry.noteID,
                      refreshedEntry.note == entry.note,
                      refreshedEntry.role == entry.role,
                      refreshedEntry.title == entry.title,
                      refreshedEntry.allowedOperations == entry.allowedOperations,
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
                      resolution.state == .abandoned,
                      resolution.checkpointID == nil else {
                    throw ResearchBoundedWriteSetError.invalidConflictResolution
                }
                current.boundedWriteSet.entries[entryIndex].state = .abandoned
                guard resolution.targetView == ResearchBoundedWriteSetViewEntry(
                    current.boundedWriteSet.entries[entryIndex]
                ) else {
                    throw ResearchBoundedWriteSetError.invalidConflictResolution
                }
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
                    < ResearchBoundedWriteSet.maximumWritesPerRun,
                  let entryIndex = current.boundedWriteSet.entries.firstIndex(where: {
                      $0.handle == write.target
                  }),
                  current.boundedWriteSet.entries[entryIndex].state == .ready,
                  current.boundedWriteSet.entries[entryIndex].expectedRevision
                    == write.expectedRevision,
                  current.boundedWriteSet.entries[entryIndex].checkpointID
                    == write.checkpointID else {
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
                if let observedRevision {
                    current.boundedWriteSet.entries[entryIndex].expectedRevision
                        = observedRevision
                }
                current.boundedWriteSet.entries[entryIndex].state = .ready
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

    /// Reconciles only a write that is already durably linked to the pending
    /// recovery record selected by the researcher. The caller supplies a fresh
    /// exact source observation after separately checking stable identity.
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
            guard write.recoveryRecordID == recoveryRecordID else {
                throw ResearchBoundedWriteSetError.recoveryRequired
            }
            if write.state != .recoveryRequired {
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
                current.boundedWriteSet.entries[entryIndex].expectedRevision
                    = observedRevision
                current.boundedWriteSet.entries[entryIndex].state = .ready
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
            throw ResearchRecordStoreV1Error.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
    }

    /// Returns the local Action runs whose private state mentions one of the
    /// supplied Notes. Permanent deletion uses this before removing the runs
    /// so dependent coordination requests can be purged in the same journaled
    /// privacy-finalization phase.
    public func executionIDs(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        let listing = try listing()
        guard listing.issues.isEmpty else {
            throw ResearchRecordStoreV1Error.unsafeStore(
                listing.issues.map(\.id).joined(separator: ", ")
            )
        }
        return listing.records
            .filter { !Self.noteIDs(in: $0).isDisjoint(with: noteIDs) }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// Removes machine-local runs that contain any permanently deleted note.
    /// Finished portable records are deliberately not touched; participant
    /// tombstones belong to the separate Research Record lifecycle.
    @discardableResult
    public func purgeExecutions(containing noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        return try lock.withExclusiveLock {
            let listing = try readListing()
            guard listing.issues.isEmpty else {
                throw ResearchRecordStoreV1Error.unsafeStore(
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
                throw ResearchFunctionRecordStoreError.completionMismatch(runID)
            }
            if let existing = record.completion {
                if existing == completion {
                    if record.completionSubmissionDigest == submissionDigest {
                        return
                    }
                    guard [.awaitingFidelity, .unverified, .stale].contains(
                        existing.state
                    ) else {
                        throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
                    }
                    // The coordinator has revalidated this external
                    // submission against current bytes and it reconstructs
                    // the exact same nonterminal evidence. Accept its digest
                    // before internal orchestration attempts advancement.
                    record.completionSubmissionDigest = submissionDigest
                    return
                }
                guard Self.canAdvance(existing, to: completion, snapshot: record.snapshot) else {
                    throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
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
                throw ResearchRecordStoreV1Error.executionAlreadyCompleted(runID)
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
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
            }
            return record
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error {
                throw ResearchRecordStoreV1Error.executionNotFound(id)
            }
            throw ResearchRecordStoreV1Error.unsafeStore(error.localizedDescription)
        }
    }

    private func readListing() throws -> LocalResearchExecutionListing {
        var records: [LocalResearchExecutionRecord] = []
        var issues: [PortableResearchRecordStoreIssue] = []
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
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
                }
                records.append(record)
            } catch {
                issues.append(PortableResearchRecordStoreIssue(
                    location: "research-execution-v8",
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
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(id)
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
        case (.awaitingFidelity, .complete),
             (.awaitingFidelity, .unverified),
             (.unverified, .complete),
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
        let allowed = snapshot.fidelityHandoff?.checks ?? snapshot.request.checks
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


private struct ResearchRecordStoreAnyCodingKey: CodingKey {
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

private enum ResearchRecordStoreCodingValidation {
    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.unicodeScalars.allSatisfy { scalar in
                ("0"..."9").contains(Character(scalar))
                    || ("a"..."f").contains(Character(scalar))
            }
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchRecordStoreAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw PortableResearchRecordError.unsupportedField(unknown)
        }
    }

    static func containsAbsolutePath(_ value: String) -> Bool {
        value.split(whereSeparator: { character in
            character.isWhitespace
                || "\"'`()[]{}<>,;".contains(character)
        }).contains { rawToken in
            let token = String(rawToken)
            if token.lowercased().hasPrefix("file://") { return true }
            if token.hasPrefix("/") && token.split(separator: "/").count > 1 {
                return true
            }
            let scalars = Array(token.unicodeScalars)
            return scalars.count >= 3
                && CharacterSet.letters.contains(scalars[0])
                && scalars[1] == ":"
                && (scalars[2] == "\\" || scalars[2] == "/")
        }
    }
}
