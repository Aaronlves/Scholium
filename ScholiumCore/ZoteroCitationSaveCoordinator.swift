import Foundation
import ScholiumContracts

public struct ZoteroCitationPairEvidence: Sendable {
    public let record: ZoteroCitationPairRecovery
    public let sourceBefore: Data?
    public let sourceAfter: Data
    public let companionBefore: Data?
    public let companionAfter: Data?
    public let companionDisplaced: Data?
}

/// One source/companion pair operation. Application owns the existing source
/// lease; this actor adds no process, engine, or cross-filesystem atomicity claim.
public actor ZoteroCitationSaveCoordinator {
    private let triptychID: UUID
    private let repositories: [UUID: VaultRepository]
    private let controlStore: TriptychControlStore
    private let recoveryStore: TriptychMutationRecoveryStore
    private let afterSource: (@Sendable () async throws -> Void)?
    private let afterCompanion: (@Sendable () async throws -> Void)?
    private let afterRetainedCompletion: (@Sendable () async throws -> Void)?

    public init(
        triptychID: UUID, repositories: [UUID: VaultRepository],
        controlStore: TriptychControlStore, recoveryStore: TriptychMutationRecoveryStore
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        afterSource = nil
        afterCompanion = nil
        afterRetainedCompletion = nil
    }

    init(
        triptychID: UUID, repositories: [UUID: VaultRepository],
        controlStore: TriptychControlStore, recoveryStore: TriptychMutationRecoveryStore,
        afterSource: (@Sendable () async throws -> Void)?,
        afterCompanion: (@Sendable () async throws -> Void)? = nil,
        afterRetainedCompletion: (@Sendable () async throws -> Void)? = nil
    ) {
        self.triptychID = triptychID
        self.repositories = repositories
        self.controlStore = controlStore
        self.recoveryStore = recoveryStore
        self.afterSource = afterSource
        self.afterCompanion = afterCompanion
        self.afterRetainedCompletion = afterRetainedCompletion
    }

    public func save(
        target: NoteMutationTarget, source: String, edit: ZoteroCitationEdit
    ) async throws -> SaveResult {
        try await requireScope(vaultID: target.documentID.vaultID)
        try await requireIdentity(target)
        try await cleanupCompletedCitationRemainders(noteID: target.stableNoteID, vaultID: target.documentID.vaultID)
        let repository = try repository(target.documentID.vaultID)
        let before = try await repository.preflightExisting(
            relativePath: target.relativePath, expectedRevision: target.revision
        )
        let snapshot = try await controlStore.citationSnapshot(
            noteID: target.stableNoteID, vaultID: target.documentID.vaultID,
            sourceFingerprint: before.fingerprint
        )
        guard snapshot.revision == edit.expectedRevision else { throw ZoteroCitationSaveError.companionConflict }
        guard snapshot.status == .available || snapshot.status == .absent else {
            throw ZoteroCitationSaveError.invalidCompanion("The existing citation companion must be resolved before live citations can be changed.")
        }
        let beforeCompanion = try await controlStore.citationCompanionBytes(noteID: target.stableNoteID)
        guard beforeCompanion.map({ DocumentFingerprint(data: $0) }) == edit.expectedRevision else {
            throw ZoteroCitationSaveError.companionConflict
        }
        let afterBytes = Data(source.utf8)
        let companion = try candidate(noteID: target.stableNoteID, vaultID: target.documentID.vaultID, source: afterBytes, data: edit.data)
        let requiredBefore = try await controlStore.identityRecord(id: target.stableNoteID)?.citationCompanionRequired == true
        let record = try await recoveryStore.prepareCitationSave(
            noteID: target.stableNoteID, vaultID: target.documentID.vaultID, relativePath: target.relativePath,
            sourceBefore: Data(before.rawContent.utf8), sourceAfter: afterBytes,
            companionBefore: beforeCompanion, companionAfter: companion, companionRequiredBefore: requiredBefore
        )
        guard record.triptychID == triptychID else { throw ZoteroCitationSaveError.identityChanged }
        do {
            try await requireScope(vaultID: record.vaultID)
            try await requireIdentity(target)
            if record.companionRequiredAfter {
                try await setDeclaration(record, required: true, expected: record.companionRequiredBefore)
            }
            if before.fingerprint != record.sourceAfter {
                switch try await repository.saveOutcome(
                    relativePath: target.relativePath, changeSet: .exactContent(source), expectedRevision: target.revision
                ) {
                case .committed: break
                case .notWritten(let reason):
                    try await complete(record, target: target)
                    throw ZoteroCitationSaveError.sourceNotWritten(reason)
                case .recoveryRequired:
                    throw ZoteroCitationSaveError.recoveryRequired(record)
                }
            }
            try await afterSource?()
            return try await finishCompanion(record, expectedCompanion: edit.expectedRevision)
        } catch let error as ZoteroCitationSaveError {
            if case .sourceNotWritten = error { throw error }
            _ = try? await reconcileCompanionReplacement(record)
            throw ZoteroCitationSaveError.recoveryRequired(record)
        } catch {
            _ = try? await reconcileCompanionReplacement(record)
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
    }

    /// Used by a managed duplicate after occurrence IDs have been reminted.
    /// The reserved identity and both checked-absent preimages precede creation.
    public func create(
        id: VaultQualifiedNoteID, noteID: UUID, source: String, data: ZoteroCitationData
    ) async throws -> SaveResult {
        try await requireScope(vaultID: id.vaultID)
        let repository = try repository(id.vaultID)
        try await repository.preflightNewFile(relativePath: id.relativePath)
        guard try await controlStore.identityRecord(id: noteID) == nil,
            try await controlStore.identityRecord(vaultID: id.vaultID, relativePath: id.relativePath) == nil,
            try await controlStore.citationCompanionBytes(noteID: noteID) == nil
        else { throw ZoteroCitationSaveError.identityChanged }
        try await cleanupCompletedCitationRemainders(noteID: noteID, vaultID: id.vaultID)
        let bytes = Data(source.utf8)
        let companion = try candidate(noteID: noteID, vaultID: id.vaultID, source: bytes, data: data)
        let record = try await recoveryStore.prepareCitationSave(
            noteID: noteID, vaultID: id.vaultID, relativePath: id.relativePath,
            sourceBefore: nil, sourceAfter: bytes, companionBefore: nil, companionAfter: companion,
            companionRequiredBefore: false
        )
        guard record.triptychID == triptychID else { throw ZoteroCitationSaveError.identityChanged }
        do {
            try await requireScope(vaultID: record.vaultID)
            let document = try await repository.create(relativePath: id.relativePath, content: source)
            try await requireScope(vaultID: record.vaultID)
            guard
                try await controlStore.identity(
                    forVaultID: id.vaultID, relativePath: id.relativePath,
                    fingerprint: document.fingerprint, preferredID: noteID
                )?.id == noteID
            else { throw ZoteroCitationSaveError.identityChanged }
            try await setDeclaration(record, required: true, expected: false)
            try await afterSource?()
            return try await finishCompanion(record, expectedCompanion: nil)
        } catch { throw ZoteroCitationSaveError.recoveryRequired(record) }
    }

    public func reconcile(
        _ record: ZoteroCitationPairRecovery, target: NoteMutationTarget
    ) async throws -> ZoteroCitationPairState {
        try await requireScope(vaultID: record.vaultID)
        try requireRecordTarget(record, target: target)
        _ = try await recoveryStore.citationSaveEvidence(record)
        guard try await reconcileCompanionReplacement(record) else { return .conflicted }
        return try await canonicalPairState(record, target: target)
    }

    private func canonicalPairState(
        _ record: ZoteroCitationPairRecovery, target: NoteMutationTarget,
        acceptingOriginalPair: Bool = false
    ) async throws -> ZoteroCitationPairState {
        try await requireScope(vaultID: record.vaultID)
        try requireRecordTarget(record, target: target)
        let repository = try repository(record.vaultID)
        let source: NoteDocument
        do {
            source = try await repository.load(relativePath: record.relativePath)
        } catch VaultRepositoryError.fileDoesNotExist {
            guard record.sourceBefore == nil, record.companionBefore == nil,
                try await controlStore.identityRecord(id: record.noteID) == nil,
                try await controlStore.identityRecord(vaultID: record.vaultID, relativePath: record.relativePath) == nil,
                try await controlStore.citationCompanionBytes(noteID: record.noteID) == nil
            else {
                return .conflicted
            }
            try await repository.preflightNewFile(relativePath: record.relativePath)
            try await requireScope(vaultID: record.vaultID)
            return .unchanged
        }
        try await requireIdentity(target)
        guard source.fingerprint == target.revision else { return .conflicted }
        let companion = try await controlStore.citationCompanionBytes(noteID: record.noteID)
        let revision = companion.map { DocumentFingerprint(data: $0) }
        guard try await repository.load(relativePath: record.relativePath).fingerprint == source.fingerprint else {
            return .conflicted
        }
        let required = try await controlStore.identityRecord(id: record.noteID)?.citationCompanionRequired == true
        try await requireScope(vaultID: record.vaultID)
        if source.fingerprint == record.sourceAfter, revision == record.companionAfter {
            return required == record.companionRequiredAfter ? .committed : .sourceCommitted
        }
        if acceptingOriginalPair, source.fingerprint == record.sourceBefore, revision == record.companionBefore { return .unchanged }
        if source.fingerprint == record.sourceAfter, revision == record.companionBefore { return .sourceCommitted }
        if source.fingerprint == record.sourceBefore, revision == record.companionBefore { return .unchanged }
        return .conflicted
    }

    /// Explicit recovery of this transaction's reserved creation identity only.
    /// Equal bytes at a foreign identity never grant permission to reassign it.
    public func recoverCreationIdentity(_ record: ZoteroCitationPairRecovery) async throws -> NoteMutationTarget {
        try await requireScope(vaultID: record.vaultID)
        guard record.triptychID == triptychID, record.sourceBefore == nil,
            record.companionBefore == nil
        else { throw ZoteroCitationSaveError.identityChanged }
        _ = try await recoveryStore.citationSaveEvidence(record)
        let repository = try repository(record.vaultID)
        _ = try await repository.preflightExisting(relativePath: record.relativePath, expectedRevision: record.sourceAfter)
        try await requireScope(vaultID: record.vaultID)
        _ = try await controlStore.reconcileManagedCreationIdentity(
            vaultID: record.vaultID, relativePath: record.relativePath,
            intendedRevision: record.sourceAfter, reservedIdentityID: record.noteID, sourceIsPresent: true
        )
        let target = NoteMutationTarget(
            documentID: VaultQualifiedNoteID(vaultID: record.vaultID, relativePath: record.relativePath),
            stableNoteID: record.noteID, revision: record.sourceAfter
        )
        try await requireIdentity(target)
        _ = try await repository.preflightExisting(relativePath: record.relativePath, expectedRevision: record.sourceAfter)
        try await requireScope(vaultID: record.vaultID)
        return target
    }

    /// Explicit recovery resumes only metadata after the intended source and
    /// old companion are proven. It never writes or rolls back Markdown.
    public func resume(
        _ record: ZoteroCitationPairRecovery, target: NoteMutationTarget
    ) async throws -> SaveResult {
        try await requireScope(vaultID: record.vaultID)
        let state = try await reconcile(record, target: target)
        guard state == .sourceCommitted || state == .committed else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        let repository = try repository(record.vaultID)
        guard try await repository.interruptedSaveRecoveries().allSatisfy({ $0.relativePath != record.relativePath }) else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        if state == .committed {
            let result = try await currentResult(record)
            try await requireScope(vaultID: record.vaultID)
            try await recoveryStore.completeCitationSave(record)
            return result
        }
        return try await finishCompanion(record, expectedCompanion: record.companionBefore)
    }

    /// Deliberate completion requires fresh proof of an original or intended
    /// pair. Displaced external bytes remain durable under a completion receipt;
    /// automatic reconciliation and resume cannot make that disposition.
    public func complete(
        _ record: ZoteroCitationPairRecovery, target: NoteMutationTarget,
        explicitlyCompletingRetainedEvidence: Bool = false
    ) async throws {
        try await requireScope(vaultID: record.vaultID)
        try requireRecordTarget(record, target: target)
        _ = try await recoveryStore.citationSaveEvidence(record)
        guard try await reconcileCompanionReplacement(record, allowingRetainedDisplacement: explicitlyCompletingRetainedEvidence) else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        let state = try await canonicalPairState(record, target: target, acceptingOriginalPair: true)
        guard state == .committed || state == .unchanged else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        let repository = try repository(record.vaultID)
        guard try await repository.interruptedSaveRecoveries().allSatisfy({ $0.relativePath != record.relativePath }) else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        if state == .unchanged, let identity = try await controlStore.identityRecord(id: record.noteID) {
            try await setDeclaration(record, required: record.companionRequiredBefore, expected: identity.citationCompanionRequired == true)
        }
        guard try await canonicalPairState(record, target: target, acceptingOriginalPair: true) == state else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        try await requireScope(vaultID: record.vaultID)
        let retainedEvidence = try await recoveryStore.citationSaveEvidence(record)
        try await recoveryStore.completeCitationSave(
            record, retainingDisplacedEvidenceAt: explicitlyCompletingRetainedEvidence ? state : nil)
        if retainedEvidence.companionDisplaced != nil {
            try await afterRetainedCompletion?()
            try await cleanupCompletedCitationRemainders(noteID: record.noteID, vaultID: record.vaultID)
        }
    }

    /// Receipt-backed housekeeping is retried before a later write, including
    /// after a restart between receipt publication and physical cleanup. It
    /// never requires or restores the historical canonical source/companion.
    private func cleanupCompletedCitationRemainders(noteID: UUID, vaultID: UUID) async throws {
        try await requireScope(vaultID: vaultID)
        var remainders: [String: (bytes: Data, authorized: Bool)] = [:]
        for record in try await recoveryStore.retainedCitationSaves()
        where record.noteID == noteID && record.vaultID == vaultID {
            try await requireScope(vaultID: vaultID)
            guard record.triptychID == triptychID else { throw ZoteroCitationSaveError.identityChanged }
            let evidence = try await recoveryStore.retainedCitationSaveEvidence(record)
            for (name, bytes) in try await controlStore.citationReplacementRemainders(noteID: noteID, transactionID: record.id) {
                let previous = remainders[name]
                guard previous == nil || previous?.bytes == bytes else {
                    throw ZoteroCitationSaveError.invalidCompanion("A citation replacement remainder changed during retained-evidence inspection.")
                }
                let matches = bytes == evidence.companionBefore || bytes == evidence.companionAfter || bytes == evidence.companionDisplaced
                remainders[name] = (bytes, matches || previous?.authorized == true)
            }
        }
        // Control returns a UUID-bound staging name only for its transaction;
        // the shared deletion name can match any validated receipt for this Note.
        // Prove every observed remainder before cleaning any of them.
        guard remainders.values.allSatisfy(\.authorized) else {
            throw ZoteroCitationSaveError.invalidCompanion("A newer citation replacement remainder remains unchanged beside the retained completion evidence.")
        }
        for name in remainders.keys.sorted() {
            guard let remainder = remainders[name] else { continue }
            try await requireScope(vaultID: vaultID)
            try await controlStore.discardCitationReplacementRemainder(name: name, expected: remainder.bytes)
        }
    }

    private func finishCompanion(
        _ record: ZoteroCitationPairRecovery, expectedCompanion: DocumentFingerprint?
    ) async throws -> SaveResult {
        try await requireScope(vaultID: record.vaultID)
        let target = NoteMutationTarget(
            documentID: VaultQualifiedNoteID(vaultID: record.vaultID, relativePath: record.relativePath),
            stableNoteID: record.noteID, revision: record.sourceAfter
        )
        try await requireIdentity(target)
        let repository = try repository(record.vaultID)
        _ = try await repository.preflightExisting(relativePath: record.relativePath, expectedRevision: record.sourceAfter)
        let evidence = try await recoveryStore.citationSaveEvidence(record)
        if record.companionRequiredAfter {
            guard let identity = try await controlStore.identityRecord(id: record.noteID) else { throw ZoteroCitationSaveError.identityChanged }
            try await setDeclaration(record, required: true, expected: identity.citationCompanionRequired == true)
        }
        guard try await reconcileCompanionReplacement(record) else { throw ZoteroCitationSaveError.recoveryRequired(record) }
        let currentCompanion = try await controlStore.citationCompanionBytes(noteID: record.noteID)
        let currentRevision = currentCompanion.map { DocumentFingerprint(data: $0) }
        if currentRevision != record.companionAfter {
            try await requireScope(vaultID: record.vaultID)
            try await controlStore.replaceCitationCompanionBytes(
                noteID: record.noteID, expectedRevision: expectedCompanion,
                candidate: evidence.companionAfter, transactionID: record.id
            )
        }
        guard let identity = try await controlStore.identityRecord(id: record.noteID) else { throw ZoteroCitationSaveError.identityChanged }
        try await setDeclaration(record, required: record.companionRequiredAfter, expected: identity.citationCompanionRequired == true)
        try await afterCompanion?()
        guard try await reconcile(record, target: target) == .committed else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        let result = try await currentResult(record)
        try await requireScope(vaultID: record.vaultID)
        // Exact pair readback proves success; redundant journal cleanup is
        // housekeeping and may be retried without another source write.
        try? await recoveryStore.completeCitationSave(record)
        return result
    }

    private func currentResult(_ record: ZoteroCitationPairRecovery) async throws -> SaveResult {
        try await requireScope(vaultID: record.vaultID)
        let document = try await repository(record.vaultID).load(relativePath: record.relativePath)
        let snapshot = try await controlStore.citationSnapshot(
            noteID: record.noteID, vaultID: record.vaultID, sourceFingerprint: document.fingerprint
        )
        guard document.fingerprint == record.sourceAfter, snapshot.revision == record.companionAfter,
            snapshot.status == (record.companionRequiredAfter ? .available : .absent)
        else { throw ZoteroCitationSaveError.recoveryRequired(record) }
        try await requireIdentity(
            NoteMutationTarget(
                documentID: VaultQualifiedNoteID(vaultID: record.vaultID, relativePath: record.relativePath),
                stableNoteID: record.noteID, revision: record.sourceAfter
            ))
        guard try await repository(record.vaultID).load(relativePath: record.relativePath).fingerprint == record.sourceAfter else {
            throw ZoteroCitationSaveError.recoveryRequired(record)
        }
        try await requireScope(vaultID: record.vaultID)
        return SaveResult(document: document.withCitationSnapshot(snapshot))
    }

    private func candidate(noteID: UUID, vaultID: UUID, source: Data, data: ZoteroCitationData?) throws -> Data? {
        guard source.count <= VaultSourceReadLimits.maximumNoteByteCount else {
            throw ZoteroCitationSaveError.invalidCompanion("The Note exceeds its supported byte limit.")
        }
        guard let text = NoteDocument.decodeUTF8PreservingBOM(source) else { throw ZoteroCitationError.invalidSource }
        guard let data else {
            let snapshot = ZoteroCitationSnapshot(noteID: noteID, vaultID: vaultID, status: .absent)
            let document = NoteDocument(relativePath: "Citation validation.md", rawContent: text, citationSnapshot: snapshot)
            let catalog = ZoteroMarkdownFields(parsing: document)
            guard document.frontmatterState != .malformed, catalog.canMutate,
                catalog.fields.allSatisfy(\.isCompleted)
            else {
                throw ZoteroCitationError.invalidSource
            }
            return nil
        }
        let companion = ZoteroCitationCompanion(
            noteID: noteID, vaultID: vaultID, sourceFingerprint: DocumentFingerprint(data: source), data: data
        )
        try companion.validate(noteID: noteID, vaultID: vaultID)
        try ZoteroMarkdownFields.validateCompanion(source: text, data: data)
        return try TriptychControlStore.citationCompanionEncoding(companion)
    }

    private func repository(_ vaultID: UUID) throws -> VaultRepository {
        guard let repository = repositories[vaultID], repository.identity.id == vaultID else {
            throw ZoteroCitationSaveError.identityChanged
        }
        return repository
    }

    private func requireIdentity(_ target: NoteMutationTarget) async throws {
        guard let identity = try await controlStore.identityRecord(id: target.stableNoteID),
            identity.vaultID == target.documentID.vaultID, identity.relativePath == target.relativePath
        else { throw ZoteroCitationSaveError.identityChanged }
    }

    private func requireScope(vaultID: UUID) async throws {
        let manifest = try await controlStore.manifest()
        guard manifest.schemaVersion == TriptychManifest.currentSchemaVersion,
            Set(manifest.vaultIDs.keys) == Set(WorkspaceVaultSlot.allCases),
            Set(manifest.vaultIDs.values).count == WorkspaceVaultSlot.allCases.count,
            manifest.id == triptychID, manifest.vaultIDs.values.contains(vaultID)
        else {
            throw ZoteroCitationSaveError.identityChanged
        }
    }

    private func requireRecordTarget(_ record: ZoteroCitationPairRecovery, target: NoteMutationTarget) throws {
        guard record.triptychID == triptychID, record.noteID == target.stableNoteID,
            record.vaultID == target.documentID.vaultID, record.relativePath == target.relativePath
        else { throw ZoteroCitationSaveError.identityChanged }
    }

    private func setDeclaration(_ record: ZoteroCitationPairRecovery, required: Bool, expected: Bool) async throws {
        try await requireScope(vaultID: record.vaultID)
        try await controlStore.setCitationCompanionRequired(
            noteID: record.noteID, vaultID: record.vaultID, relativePath: record.relativePath,
            required: required, expectedRequired: expected
        )
    }

    /// The physical companion primitive retains a transaction-named swap file.
    /// Known before/candidate bytes are already journaled. A distinct displaced
    /// revision is copied durably and remains a blocker, even if canonical bytes
    /// happen to match the attempted candidate.
    private func reconcileCompanionReplacement(
        _ record: ZoteroCitationPairRecovery, allowingRetainedDisplacement: Bool = false
    ) async throws -> Bool {
        try await requireScope(vaultID: record.vaultID)
        let evidence = try await recoveryStore.citationSaveEvidence(record)
        let remainders = try await controlStore.citationReplacementRemainders(noteID: record.noteID, transactionID: record.id)
        for (name, bytes) in remainders {
            if bytes == evidence.companionBefore || bytes == evidence.companionAfter {
                try await requireScope(vaultID: record.vaultID)
                try await controlStore.discardCitationReplacementRemainder(name: name, expected: bytes)
            } else {
                try await recoveryStore.retainDisplacedCitationCompanion(record, bytes: bytes)
            }
        }
        return try await recoveryStore.citationSaveEvidence(record).companionDisplaced == nil || allowingRetainedDisplacement
    }
}
