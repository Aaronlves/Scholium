import Foundation
import ScholiumContracts
import ScholiumCore

/// One Triptych-wide review owner, shared by windows and Chat. It reads only
/// saved, identity-checked source and never mutates a Note or Settlement.
public actor DocumentChangeOperations: DocumentChangeUseCases {
    private let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func pendingChanges() async throws -> [DocumentChangeSummary] {
        try await reference.requireHandle().pendingDocumentChanges()
    }

    public func changeReview(noteID: UUID) async throws -> DocumentChangeReview {
        try await reference.requireHandle().documentChangeReview(noteID: noteID)
    }

    public func markReviewed(capture: DocumentChangeCapture) async throws -> ReviewedDocumentChange {
        try await reference.requireHandle().markDocumentReviewed(capture)
    }

    public func reviewedHistory() async throws -> [ReviewedDocumentChange] {
        try await reference.requireHandle().reviewedDocumentChanges()
    }

    public func reviewedChange(id: UUID) async throws -> ReviewedDocumentChangeDetail {
        try await reference.requireHandle().reviewedDocumentChange(id: id)
    }

    public func deleteReviewedHistory(ids: [UUID]) async throws {
        try await reference.requireHandle().deleteReviewedDocumentChanges(ids: Set(ids))
    }

    public func clearReviewedHistory() async throws {
        try await reference.requireHandle().clearReviewedDocumentChanges()
    }

    public func retention() async throws -> DocumentChangeRetention {
        try await reference.requireHandle().documentChangeRetention()
    }

    public func setRetention(_ retention: DocumentChangeRetention) async throws {
        try await reference.requireHandle().setDocumentChangeRetention(retention)
    }

    public func historyUsage() async throws -> DocumentChangeHistoryUsage {
        try await reference.requireHandle().documentChangeHistoryUsage()
    }
}

extension WorkspaceHandle {
    private func documentReviewStore() throws -> DocumentReviewStore {
        try requireActive()
        if let documentReviewIssue {
            throw DocumentChangeError.unavailable(documentReviewIssue)
        }
        guard let store = services.documentReviewStore else {
            throw DocumentChangeError.unavailable("The machine-local review store could not be opened.")
        }
        return store
    }

    func initializeDocumentReviewsFromOpeningSnapshot(_ snapshot: WorkspaceSnapshot) async {
        guard let store = services.documentReviewStore else { return }
        let receipts: [AgentChange]
        do {
            receipts = try await services.agentChangeStore.changes()
        } catch {
            documentReviewIssue = error.localizedDescription
            return
        }
        for note in snapshot.vaults.flatMap(\.documents) {
            guard let noteID = note.stableIdentity.resolvedID else { continue }
            if openingReviewCandidates[noteID] == nil {
                openingReviewCandidates[noteID] = note
            }
        }
        for (noteID, note) in openingReviewCandidates.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            do {
                if try await store.baseline(noteID: noteID, vaultID: note.id.vaultID) != nil {
                    continue
                }
                let source: Data?
                if let loaded = try? await repository(vaultID: note.id.vaultID)
                    .load(relativePath: note.id.relativePath),
                    loaded.fingerprint == note.fingerprint,
                    let identity = try? await services.controlStore.identityRecord(
                        vaultID: note.id.vaultID,
                        relativePath: note.id.relativePath
                    ), identity.id == noteID,
                    identity.fingerprint == note.fingerprint
                {
                    source = loaded.sourceBytes
                } else {
                    source = nil
                }
                try await store.initializeExisting(
                    noteID: noteID, vaultID: note.id.vaultID, source: source,
                    receiptVersions: Self.receiptVersions(
                        for: noteID, in: receipts
                    )
                )
            } catch {
                documentReviewIssue = error.localizedDescription
                return
            }
        }
        documentReviewIssue = nil
        openingReviewCandidates = [:]
    }

    private nonisolated static func receiptVersions(
        for noteID: UUID, in receipts: [AgentChange]
    ) -> [DocumentReviewStore.ReceiptVersion] {
        receipts.filter { change in
            change.noteID == noteID || (change.moveEffects?.contains { $0.noteID == noteID } ?? false)
        }.map(DocumentReviewStore.ReceiptVersion.init)
    }

    private func retryDocumentReviewInitializationIfNeeded() async {
        guard documentReviewIssue != nil, !openingReviewCandidates.isEmpty else { return }
        await initializeDocumentReviewsFromOpeningSnapshot(currentSnapshot)
    }

    func initializeNewDocumentReviews(
        from previous: WorkspaceSnapshot,
        to current: WorkspaceSnapshot
    ) async {
        guard let store = services.documentReviewStore else { return }
        let known = Set(
            previous.vaults.flatMap(\.documents).compactMap {
                $0.stableIdentity.resolvedID
            })
        let observedVaultIDs = Set(previous.vaults.map { $0.vault.id })
        for note in current.vaults.flatMap(\.documents) {
            guard let noteID = note.stableIdentity.resolvedID,
                !known.contains(noteID),
                previous.phase.isComplete || observedVaultIDs.contains(note.id.vaultID)
            else { continue }
            do {
                try await store.initializeNew(noteID: noteID, vaultID: note.id.vaultID)
            } catch {
                documentReviewIssue = error.localizedDescription
                return
            }
        }
    }

    func pendingDocumentChanges() async throws -> [DocumentChangeSummary] {
        await retryDocumentReviewInitializationIfNeeded()
        let store = try documentReviewStore()
        let snapshot = try await refresh()
        try requireActive()
        var result: [DocumentChangeSummary] = []
        for note in snapshot.vaults.flatMap(\.documents) {
            guard let noteID = note.stableIdentity.resolvedID else { continue }
            var baseline = try await store.baseline(noteID: noteID, vaultID: note.id.vaultID)
            if baseline == nil {
                try await store.initializeNew(noteID: noteID, vaultID: note.id.vaultID)
                baseline = try await store.baseline(noteID: noteID, vaultID: note.id.vaultID)
            }
            guard let baseline else { throw DocumentChangeError.noteUnavailable(noteID) }
            guard baseline.state != .known || baseline.fingerprint != note.fingerprint else {
                continue
            }
            result.append(
                DocumentChangeSummary(
                    noteID: noteID, vaultID: note.id.vaultID, role: note.vaultRole,
                    relativePath: note.id.relativePath,
                    startingRevision: baseline.fingerprint,
                    endingRevision: note.fingerprint,
                    savedAt: note.fileMetadata.modificationDate,
                    baselineState: baseline.state
                ))
        }
        return result.sorted {
            if $0.savedAt != $1.savedAt { return ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
            return $0.noteID.uuidString < $1.noteID.uuidString
        }
    }

    func documentChangeReview(noteID: UUID) async throws -> DocumentChangeReview {
        await retryDocumentReviewInitializationIfNeeded()
        let store = try documentReviewStore()
        let snapshot = try await refresh()
        let matches = snapshot.vaults.flatMap(\.documents).filter {
            $0.stableIdentity.resolvedID == noteID
        }
        guard matches.count == 1 else { throw DocumentChangeError.noteUnavailable(noteID) }
        let note = matches[0]
        let lease = try await beginSourceMutation()
        var ownsLease = true
        defer { if ownsLease { endSourceMutation(lease) } }
        let hydrated = try await hydrate(note)
        guard hydrated.stableIdentity.resolvedID == noteID else {
            throw DocumentChangeError.noteUnavailable(noteID)
        }
        let receiptVersions = Self.receiptVersions(
            for: noteID, in: try await services.agentChangeStore.changes()
        )
        if try await store.baseline(noteID: noteID, vaultID: note.id.vaultID) == nil {
            try await store.initializeNew(noteID: noteID, vaultID: note.id.vaultID)
        }
        let captured = try await store.capture(
            noteID: noteID, vaultID: note.id.vaultID, role: note.vaultRole,
            relativePath: note.id.relativePath,
            endingData: hydrated.document.sourceBytes,
            receiptVersions: receiptVersions
        )
        endSourceMutation(lease)
        ownsLease = false
        let baseline = captured.startingData.map(DocumentFingerprint.init(data:))
        let comparison: ExactSourceComparison?
        if let startingData = captured.startingData, let baseline {
            comparison = try ExactSourceComparisonBuilder.build(
                startingData: startingData, endingData: captured.endingData,
                startingRevision: baseline,
                endingRevision: captured.token.endingRevision
            )
        } else {
            comparison = nil
        }
        return DocumentChangeReview(
            summary: DocumentChangeSummary(
                noteID: noteID, vaultID: note.id.vaultID, role: note.vaultRole,
                relativePath: note.id.relativePath, startingRevision: baseline,
                endingRevision: captured.token.endingRevision,
                savedAt: note.fileMetadata.modificationDate,
                baselineState: captured.baselineState
            ),
            capture: captured.token, comparison: comparison,
            startingSource: captured.startingData.flatMap(NoteDocument.decodeUTF8PreservingBOM),
            endingSource: hydrated.document.rawContent
        )
    }

    func markDocumentReviewed(_ capture: DocumentChangeCapture) async throws -> ReviewedDocumentChange {
        let store = try documentReviewStore()
        _ = try await refresh()
        let lease = try await beginSourceMutation()
        var ownsLease = true
        defer { if ownsLease { endSourceMutation(lease) } }
        let matches = currentSnapshot.vaults.flatMap(\.documents).filter {
            $0.stableIdentity.resolvedID == capture.noteID
        }
        guard matches.count == 1 else {
            throw DocumentChangeError.noteUnavailable(capture.noteID)
        }
        let current = try await hydrate(matches[0])
        guard current.stableIdentity.resolvedID == capture.noteID else {
            throw DocumentChangeError.noteUnavailable(capture.noteID)
        }
        let batch: ReviewedDocumentChange
        do {
            batch = try await store.markReviewed(capture)
        } catch {
            endSourceMutation(lease)
            ownsLease = false
            await publishDocumentChangesChanged()
            throw error
        }
        endSourceMutation(lease)
        ownsLease = false
        await publishDocumentChangesChanged()
        return batch
    }

    func reviewedDocumentChanges() async throws -> [ReviewedDocumentChange] {
        let store = try documentReviewStore()
        let expired: Bool
        do {
            expired = try await store.expireHistory()
        } catch {
            await publishDocumentChangesChanged()
            throw error
        }
        let reclaimed: Bool
        do {
            reclaimed = try await reclaimReviewedOperationReceipts()
        } catch {
            if expired { await publishDocumentChangesChanged() }
            throw error
        }
        if expired || reclaimed {
            await publishDocumentChangesChanged()
        }
        return try await store.history()
    }

    func reviewedDocumentChange(id: UUID) async throws -> ReviewedDocumentChangeDetail {
        let detail = try await documentReviewStore().historyDetail(id: id)
        let comparison: ExactSourceComparison?
        if let startingData = detail.startingData,
            let starting = detail.batch.startingRevision
        {
            comparison = try ExactSourceComparisonBuilder.build(
                startingData: startingData, endingData: detail.endingData,
                startingRevision: starting,
                endingRevision: detail.batch.endingRevision
            )
        } else {
            comparison = nil
        }
        guard let endingSource = NoteDocument.decodeUTF8PreservingBOM(detail.endingData) else {
            throw DocumentChangeError.invalidRecord(detail.batch.noteID)
        }
        return ReviewedDocumentChangeDetail(
            batch: detail.batch, comparison: comparison,
            startingSource: detail.startingData.flatMap(NoteDocument.decodeUTF8PreservingBOM),
            endingSource: endingSource
        )
    }

    func deleteReviewedDocumentChanges(ids: Set<UUID>) async throws {
        do {
            try await documentReviewStore().deleteHistory(ids: ids)
        } catch {
            await publishDocumentChangesChanged()
            throw error
        }
        try await finishDocumentReviewCleanup()
    }

    func clearReviewedDocumentChanges() async throws {
        do {
            try await documentReviewStore().clearHistory()
        } catch {
            await publishDocumentChangesChanged()
            throw error
        }
        try await finishDocumentReviewCleanup()
    }

    func documentChangeRetention() async throws -> DocumentChangeRetention {
        try await documentReviewStore().retention()
    }

    func setDocumentChangeRetention(_ retention: DocumentChangeRetention) async throws {
        let store = try documentReviewStore()
        do {
            try await store.setRetention(retention)
        } catch {
            await publishDocumentChangesChanged()
            throw error
        }
        do {
            _ = try await store.expireHistory()
        } catch {
            await publishDocumentChangesChanged()
            throw DocumentChangeError.historyChangedCleanupPending(error.localizedDescription)
        }
        try await finishDocumentReviewCleanup()
    }

    func documentChangeHistoryUsage() async throws -> DocumentChangeHistoryUsage {
        let usage = try await documentReviewStore().historyUsage()
        let receiptBytes = try await services.agentChangeStore.retainedByteCount()
        return DocumentChangeHistoryUsage(
            count: usage.count, byteCount: usage.byteCount,
            protectedByteCount: usage.protectedByteCount + receiptBytes
        )
    }

    func publishDocumentChangesChanged() async {
        guard !isShutDown else { return }
        precondition(currentSnapshot.documentChangesGeneration < UInt64.max)
        currentSnapshot = currentSnapshot.withDocumentChangesGeneration(
            currentSnapshot.documentChangesGeneration + 1
        )
        await events.publishDocumentChangesChanged(snapshot: currentSnapshot)
    }

    private func finishDocumentReviewCleanup() async throws {
        do {
            try await reclaimReviewedOperationReceipts()
        } catch {
            await publishDocumentChangesChanged()
            throw DocumentChangeError.historyChangedCleanupPending(error.localizedDescription)
        }
        await publishDocumentChangesChanged()
    }

    /// The operational receipt is removed only after every affected Note has
    /// an old enough explicit review covering this exact receipt lifecycle
    /// version, no recovery transaction remains, and App Undo is excluded by
    /// the same source-operation gate through final removal.
    @discardableResult
    func reclaimReviewedOperationReceipts() async throws -> Bool {
        let store = try documentReviewStore()
        let lease = try await beginSourceMutation()
        defer { endSourceMutation(lease) }
        guard try await services.transactionRecoveryStore.pending().isEmpty else { return false }
        let receipts = try await services.agentChangeStore.changes()
        var removed = false
        for receipt in receipts {
            guard receipt.state == .confirmed || receipt.state == .undone,
                receipt.confirmedAt != nil
            else { continue }
            let effects: [(noteID: UUID, vaultID: UUID)]
            if let move = receipt.moveEffects {
                effects = move.map {
                    ($0.noteID, $0.destination.vaultID)
                }
            } else {
                guard
                    let vault = assignment.vaults.values.first(where: {
                        $0.role == receipt.role
                    })
                else { continue }
                effects = [(receipt.noteID, vault.id)]
            }
            guard !effects.isEmpty else { continue }
            let version = DocumentReviewStore.ReceiptVersion(receipt)
            var covered = true
            for effect in effects {
                guard
                    try await store.hasReclaimableCoverage(
                        noteID: effect.noteID, vaultID: effect.vaultID,
                        receipt: version
                    )
                else {
                    covered = false
                    break
                }
            }
            if covered {
                try await services.agentChangeStore.removeReclaimable(
                    id: receipt.id, expected: receipt
                )
                removed = true
            }
        }
        let retained = Set(
            try await services.agentChangeStore.changes().map(
                DocumentReviewStore.ReceiptVersion.init
            ))
        try await store.compactReceiptMetadata(retained: retained)
        return removed
    }
}
