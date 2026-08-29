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
/// written into the schema-16 Record or reconstructed from a re-encoding.
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

public struct PortableResearchNoteReviewListing: Sendable {
    public let reviews: [PortableResearchNoteReview]
    public let issues: [PortableResearchRecordStoreIssue]

    public init(
        reviews: [PortableResearchNoteReview],
        issues: [PortableResearchRecordStoreIssue]
    ) {
        self.reviews = reviews.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.issues = issues.sorted { $0.id < $1.id }
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
    case recordChanged(UUID)
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
        case .recordChanged(let id):
            "Research Record \(id.uuidString) changed after deletion was confirmed."
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
    private static let noteReviewsDirectory = "note-reviews"

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
                let directories = [
                    "active",
                    Self.recordsDirectory,
                    Self.noteReviewsDirectory,
                    "settlements",
                ]
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
                try requireNoDeletionMarkers(
                    noteIDs: Set(canonicalRecord.participatingNotes.map(\.noteID))
                )
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

    public func isRecordPermanentlyDeleted(id: UUID) -> Bool {
        (try? recordDeletionMarkers.read(
            directory: nil,
            fileName: Self.fileName(id)
        )) == Self.recordDeletionMarkerData(id)
    }

    /// Removes only the selected portable record. Source Markdown, portable
    /// settlements and machine-local Agent change evidence are
    /// owned by separate stores and are intentionally outside this operation.
    @discardableResult
    public func deletePermanently(
        id: UUID,
        expectedFingerprint: DocumentFingerprint? = nil
    ) throws -> PortableResearchRecord {
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
                    if let expectedFingerprint,
                       DocumentFingerprint(data: exactData) != expectedFingerprint {
                        throw ResearchRecordStoreV1Error.recordChanged(id)
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
                try recordListingWithoutLock()
            }
        }
    }

    public func noteReviewListing() throws -> PortableResearchNoteReviewListing {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL) {
                try noteReviewListingWithoutLock()
            }
        }
    }

    /// Removes only review activities whose finished Records no longer exist.
    /// A review with no remaining activities is removed as a whole. This is a
    /// separate idempotent step so an interrupted Record deletion can resume
    /// it after the durable Record-deletion marker proves the first step.
    public func removeNoteReviewActivities(recordIDs: Set<UUID>) throws {
        guard !recordIDs.isEmpty else { return }
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let listing = try noteReviewListingWithoutLock()
                guard listing.issues.isEmpty else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        listing.issues.map(\.reason).joined(separator: "; ")
                    )
                }
                for review in listing.reviews where review.coveredActivities
                    .contains(where: { recordIDs.contains($0.recordID) }) {
                    let fileName = Self.fileName(review.noteID)
                    let exactData = try storage.read(
                        directory: Self.noteReviewsDirectory,
                        fileName: fileName
                    )
                    let current = try Self.decode(
                        PortableResearchNoteReview.self,
                        from: exactData
                    )
                    guard current == review else {
                        throw ResearchRecordStoreV1Error.recordIdentityMismatch(
                            review.noteID
                        )
                    }
                    let remaining = review.coveredActivities.filter {
                        !recordIDs.contains($0.recordID)
                    }
                    if remaining.isEmpty {
                        try storage.remove(
                            directory: Self.noteReviewsDirectory,
                            fileName: fileName,
                            expected: exactData
                        )
                    } else {
                        let updated = try PortableResearchNoteReview(
                            noteID: review.noteID,
                            observedRevision: review.observedRevision,
                            reviewedAt: review.reviewedAt,
                            coveredActivities: remaining
                        )
                        let (_, data) = try Self.canonicalized(updated)
                        let readback = try storage.replace(
                            data,
                            directory: Self.noteReviewsDirectory,
                            fileName: fileName
                        )
                        guard try Self.decode(
                            PortableResearchNoteReview.self,
                            from: readback
                        ) == updated else {
                            throw ResearchRecordStoreV1Error
                                .recordIdentityMismatch(review.noteID)
                        }
                    }
                }
            }
        }
    }

    /// Records one explicit review of the Note's exact saved source. The
    /// caller cannot choose covered Records: they are derived from the exact
    /// portable Record source set revalidated under the store lock.
    @discardableResult
    public func markCurrentNoteReviewed(
        noteID: UUID,
        observedRevision: DocumentFingerprint,
        expectedRecordSourceManifestHash: String,
        reviewedAt: Date = Date()
    ) throws -> PortableResearchNoteReview {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let records = try recordListingWithoutLock()
                guard records.issues.isEmpty,
                      records.sourceManifestHash == expectedRecordSourceManifestHash else {
                    throw PortableResearchNoteReviewMutationError.recordProjectionChanged
                }
                let current = try readNoteReviewIfPresentWithoutLock(noteID: noteID)
                let covered = Set(current?.coveredActivities ?? [])
                let observed = records.records.compactMap { record ->
                    PortableResearchNoteActivityReference? in
                    guard record.confirmedChanges.contains(where: {
                        $0.noteID == noteID
                    }) else { return nil }
                    return PortableResearchNoteActivityReference(
                        recordID: record.id,
                        noteID: noteID
                    )
                }
                let pending = observed.filter { !covered.contains($0) }
                guard !pending.isEmpty else {
                    throw PortableResearchNoteReviewMutationError.noPendingAgentChanges
                }
                let review = try PortableResearchNoteReview(
                    noteID: noteID,
                    observedRevision: observedRevision,
                    reviewedAt: reviewedAt,
                    coveredActivities: Array(covered.union(observed))
                )
                let (canonical, data) = try Self.canonicalized(review)
                let fileName = Self.fileName(noteID)
                let readback: Data
                do {
                    if try storage.readIfPresent(
                        directory: Self.noteReviewsDirectory,
                        fileName: fileName
                    ) != nil {
                        readback = try storage.replace(
                            data,
                            directory: Self.noteReviewsDirectory,
                            fileName: fileName
                        )
                    } else {
                        readback = try storage.createExclusive(
                            data,
                            directory: Self.noteReviewsDirectory,
                            fileName: fileName
                        )
                    }
                } catch let error as SecureRecordDirectoryError {
                    switch error {
                    case .replacementNotCommitted(let reason):
                        throw ResearchRecordStoreV1Error
                            .replacementNotCommitted(reason)
                    case .replacementCommitUncertain(let reason):
                        throw ResearchRecordStoreV1Error
                            .replacementCommitUncertain(reason)
                    default:
                        throw Self.map(error)
                    }
                }
                let stored = try Self.decode(
                    PortableResearchNoteReview.self,
                    from: readback
                )
                guard stored == canonical else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
                }
                return stored
            }
        }
    }

    /// Atomically replaces the optional Method Feedback after its optimistic
    /// revision and the immutable finalized result have been revalidated under
    /// the portable-record lock.
    @discardableResult
    public func saveMethodFeedback(
        _ draft: ResearchMethodFeedbackDraft?,
        recordID: UUID,
        expectedMethodFeedbackRevision: UUID?,
        expectedResultFingerprint: DocumentFingerprint,
        updatedAt: Date = Date()
    ) throws -> PortableResearchRecord {
        try replaceFinishedRecord(id: recordID) { current in
            guard current.kind == .action else {
                throw PortableResearchMethodFeedbackMutationError.recordUnavailable
            }
            guard try current.finalizedResultFingerprint()
                    == expectedResultFingerprint else {
                throw PortableResearchMethodFeedbackMutationError.finalizedResultChanged
            }
            guard current.methodFeedbackComment?.revision
                    == expectedMethodFeedbackRevision else {
                throw PortableResearchMethodFeedbackMutationError
                    .staleMethodFeedbackRevision
            }
            let feedback: PortableResearchMethodFeedbackComment?
            if let feedbackText = draft?.text {
                if let existing = current.methodFeedbackComment,
                   existing.text == feedbackText {
                    feedback = existing
                } else {
                    feedback = try PortableResearchMethodFeedbackComment(
                        text: feedbackText,
                        updatedAt: updatedAt
                    )
                }
            } else {
                feedback = nil
            }
            return try Self.replacingMethodFeedback(
                in: current,
                methodFeedbackComment: feedback
            )
        }
    }

    /// Replaces only one occurrence's researcher-owned handled state. The
    /// current record is reread under the portable-record lock so concurrent
    /// response, tombstone, and other record content are preserved by the
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

    /// Establishes a durable machine-local gate before a confirmed system-Trash
    /// plan moves source files. The marker and active-record writes
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

    /// Releases only the short-lived gate owned by a completed or abandoned
    /// system-Trash plan. Permanent Record deletion markers remain separate.
    public func clearNoteDeletionGate(noteIDs: Set<UUID>) throws {
        guard !noteIDs.isEmpty else { return }
        try lock.withExclusiveLock {
            for noteID in noteIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                let expected = Self.deletionMarkerData(noteID)
                guard try deletionMarkers.readIfPresent(
                    directory: nil,
                    fileName: Self.fileName(noteID)
                ) != nil else { continue }
                try deletionMarkers.remove(
                    directory: nil,
                    fileName: Self.fileName(noteID),
                    expected: expected
                )
            }
        }
    }

    /// Removes unfinished Discussions directly participating in the deletion
    /// plan. It never forms a finished Record as a side effect of source loss.
    public func discardActiveDiscussions(noteIDs: Set<UUID>) throws -> [UUID] {
        guard !noteIDs.isEmpty else { return [] }
        return try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                let listing = try activeListingWithoutCoordination()
                guard listing.issues.isEmpty else {
                    throw ResearchRecordStoreV1Error.unsafeStore(
                        listing.issues.map(\.id).joined(separator: ", ")
                    )
                }
                let ids = listing.discussions.filter {
                    !Set($0.participatingNotes.map(\.noteID)).isDisjoint(with: noteIDs)
                }.map(\.id).sorted { $0.uuidString < $1.uuidString }
                for id in ids {
                    try storage.removeIfPresent(
                        directory: "active",
                        fileName: Self.fileName(id)
                    )
                }
                return ids
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

    /// Atomically retains one Agent reply, forms the finished Discussion
    /// Record, and removes the active Discussion. An exact retry after any
    /// uncertain outcome returns the same Record without creating another
    /// statement or re-opening the Discussion.
    @discardableResult
    public func finishDiscussion(
        id: UUID,
        appendingAgentStatement statement: PortableResearchStatement,
        participatingNotes: [PortableResearchNoteRevision],
        finishedAt: Date = Date()
    ) throws -> (record: PortableResearchRecord, replyWasAlreadyRecorded: Bool) {
        guard statement.author == .agent,
              statement.kind == .discussionTurn,
              statement.passage == nil,
              statement.lineReference == nil else {
            throw PortableResearchRecordError.invalidStatement
        }
        return try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL) {
                _ = try requireHealthyActiveListing()
                let discussion: PortableResearchDiscussion
                do {
                    discussion = try readDiscussion(id: id)
                } catch ResearchRecordStoreV1Error.discussionNotFound(_) {
                    let existing = try readRecord(id: id)
                    guard existing.kind == .discussion,
                          let retained = existing.statements.first(where: {
                              $0.id == statement.id
                          }),
                          Self.sameDiscussionReply(retained, as: statement) else {
                        throw ResearchRecordStoreV1Error.discussionFinishConflict(id)
                    }
                    return (existing, true)
                }
                try requireNoDeletionMarkers(
                    noteIDs: Set(discussion.participatingNotes.map(\.noteID))
                )

                let canonicalStatement: PortableResearchStatement
                let replyWasAlreadyRecorded: Bool
                if let retained = discussion.statements.first(where: {
                    $0.id == statement.id
                }) {
                    guard Self.sameDiscussionReply(retained, as: statement) else {
                        throw PortableResearchDiscussionError.duplicateStatement(
                            statement.id
                        )
                    }
                    canonicalStatement = retained
                    replyWasAlreadyRecorded = true
                } else {
                    canonicalStatement = statement
                    replyWasAlreadyRecorded = false
                }
                let updated = try discussion.appending(
                    canonicalStatement,
                    at: max(discussion.updatedAt, canonicalStatement.createdAt)
                )
                let record = try finishDiscussionWithoutCoordination(
                    updated,
                    participatingNotes: participatingNotes,
                    finishedAt: max(finishedAt, updated.updatedAt)
                )
                return (record, replyWasAlreadyRecorded)
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
                return try finishDiscussionWithoutCoordination(
                    discussion,
                    participatingNotes: participatingNotes,
                    finishedAt: finishedAt
                )
            }
        }
    }

    private func finishDiscussionWithoutCoordination(
        _ discussion: PortableResearchDiscussion,
        participatingNotes: [PortableResearchNoteRevision],
        finishedAt: Date
    ) throws -> PortableResearchRecord {
        let id = discussion.id
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

    private static func sameDiscussionReply(
        _ retained: PortableResearchStatement,
        as candidate: PortableResearchStatement
    ) -> Bool {
        retained.id == candidate.id
            && retained.author == candidate.author
            && retained.kind == candidate.kind
            && retained.attribution == candidate.attribution
            && retained.text == candidate.text
            && retained.passage == candidate.passage
            && retained.lineReference == candidate.lineReference
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
                try requireNoDeletionMarkers(noteIDs: [noteID])
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
        }
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
            zoteroBibliographicContext: record.zoteroBibliographicContext,
            analysisSourceRoute: record.analysisSourceRoute,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: recommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            methodFeedbackComment: record.methodFeedbackComment
        )
    }

    private static func replacingMethodFeedback(
        in record: PortableResearchRecord,
        methodFeedbackComment: PortableResearchMethodFeedbackComment?
    ) throws -> PortableResearchRecord {
        try PortableResearchRecord(
            id: record.id,
            triptychID: record.triptychID,
            title: record.title,
            kind: record.kind,
            action: record.action,
            method: record.method,
            sourceReference: record.sourceReference,
            zoteroBibliographicContext: record.zoteroBibliographicContext,
            analysisSourceRoute: record.analysisSourceRoute,
            continuationLineage: record.continuationLineage,
            primaryNoteID: record.primaryNoteID,
            participatingNotes: record.participatingNotes,
            statements: record.statements,
            resultDisposition: record.resultDisposition,
            academicResults: record.academicResults,
            fidelityCompletion: record.fidelityCompletion,
            confirmedChanges: record.confirmedChanges,
            discrepancies: record.discrepancies,
            literatureRecommendations: record.literatureRecommendations,
            startedAt: record.startedAt,
            finishedAt: record.finishedAt,
            methodFeedbackComment: methodFeedbackComment
        )
    }

    private func recordListingWithoutLock() throws -> PortableResearchRecordListing {
        var revisions: [PortableResearchRecordRevision] = []
        var issues: [PortableResearchRecordStoreIssue] = []
        for fileName in try storage.fileNames(in: Self.recordsDirectory)
            where fileName.hasSuffix(".json") {
            do {
                let data = try storage.read(
                    directory: Self.recordsDirectory,
                    fileName: fileName
                )
                let record = try Self.decode(PortableResearchRecord.self, from: data)
                guard fileName == Self.fileName(record.id),
                      record.triptychID == triptychID else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(record.id)
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
        return PortableResearchRecordListing(revisions: revisions, issues: issues)
    }

    private func noteReviewListingWithoutLock() throws
        -> PortableResearchNoteReviewListing {
        var reviews: [PortableResearchNoteReview] = []
        var issues: [PortableResearchRecordStoreIssue] = []
        for fileName in try storage.fileNames(in: Self.noteReviewsDirectory)
            where fileName.hasSuffix(".json") {
            do {
                let data = try storage.read(
                    directory: Self.noteReviewsDirectory,
                    fileName: fileName
                )
                let review = try Self.decode(
                    PortableResearchNoteReview.self,
                    from: data
                )
                guard fileName == Self.fileName(review.noteID) else {
                    throw ResearchRecordStoreV1Error.recordIdentityMismatch(review.noteID)
                }
                reviews.append(review)
            } catch {
                issues.append(PortableResearchRecordStoreIssue(
                    location: Self.noteReviewsDirectory,
                    fileName: fileName,
                    reason: error.localizedDescription
                ))
            }
        }
        return PortableResearchNoteReviewListing(reviews: reviews, issues: issues)
    }

    private func readNoteReviewIfPresentWithoutLock(
        noteID: UUID
    ) throws -> PortableResearchNoteReview? {
        do {
            guard let data = try storage.readIfPresent(
                directory: Self.noteReviewsDirectory,
                fileName: Self.fileName(noteID)
            ) else { return nil }
            let review = try Self.decode(PortableResearchNoteReview.self, from: data)
            guard review.noteID == noteID else {
                throw ResearchRecordStoreV1Error.recordIdentityMismatch(noteID)
            }
            return review
        } catch let error as SecureRecordDirectoryError {
            throw Self.map(error)
        }
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
              ResearchStoreCodingValidation.isValidFingerprint(
                settlement.fingerprint
              ),
              !ResearchStoreCodingValidation.containsAbsolutePath(
                settlement.researcher
              ),
              (settlement.rationale?.utf8.count ?? 0) <= 256 * 1024,
              !ResearchStoreCodingValidation.containsAbsolutePath(
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
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: PortableResearchRecordError.unsupportedField
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        let settlementDecoder = try container.superDecoder(forKey: .settlement)
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: settlementDecoder,
            allowed: SettlementCodingKeys.allCases.map(\.stringValue),
            onUnknownField: PortableResearchRecordError.unsupportedField
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
        try ResearchStoreCodingValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue),
            onUnknownField: PortableResearchRecordError.unsupportedField
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
