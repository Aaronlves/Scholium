import ScholiumContracts
import Foundation

private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(lhs) == encoder.encode(rhs)
}

/// Read-only compatibility archive for records created by the retired Human
/// Review model. Current product workflows cannot create or edit these
/// records; writes are limited to identity migration, permanent deletion, and
/// rollback of those lifecycle operations.
public actor HumanReviewStore {
    private struct Payload: Codable {
        let schemaVersion: Int
        var records: [UUID: HumanReviewRecord]
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var records: [UUID: HumanReviewRecord]
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        fileURL = storageURL.appendingPathComponent("human-reviews.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                records = payload.records
                loadFailure = payload.schemaVersion == 1
                    ? nil
                    : "Unsupported earlier Review archive schema version \(payload.schemaVersion)."
            } catch {
                records = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            records = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "earlier Review archive", reason: $0)
                .localizedDescription
        }
    }

    public func record(noteID: UUID) -> HumanReviewRecord? {
        records[noteID]
    }

    public func record(vaultID: UUID, relativePath: String) -> HumanReviewRecord? {
        records.values.first { $0.vaultID == vaultID && $0.relativePath == relativePath }
    }

    public func allRecords() -> [HumanReviewRecord] {
        records.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.relativePath < $1.relativePath }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Permanently removes the complete researcher-owned record for one note.
    /// This is intentionally distinct from removing an individual comment and
    /// is used only after the researcher confirms permanent note deletion.
    @discardableResult
    public func purge(noteID: UUID) throws -> HumanReviewRecord? {
        try requireHealthyStore(kind: "earlier Review archive")
        guard let removed = records[noteID] else { return nil }
        var proposed = records
        proposed.removeValue(forKey: noteID)
        try commit(proposed)
        return removed
    }

    func restorePurgedRecord(_ record: HumanReviewRecord) throws {
        try requireHealthyStore(kind: "earlier Review archive")
        if let existing = records[record.id] {
            guard try persistentlyEquivalent(existing, record) else {
                throw ResearchRecordStoreError.restorationConflict(
                    kind: "earlier Review archive",
                    identity: record.id.uuidString
                )
            }
            return
        }
        var proposed = records
        proposed[record.id] = record
        try commit(proposed)
    }

    @discardableResult
    public func migratePathIfPresent(
        noteID: UUID,
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> Bool {
        guard var record = records[noteID] else { return false }
        guard record.vaultID == vaultID else { throw HumanReviewError.recordVaultMismatch }
        if record.relativePath == destinationPath { return false }
        guard record.relativePath == sourcePath else {
            throw HumanReviewError.recordPathMismatch(
                expected: sourcePath,
                actual: record.relativePath
            )
        }
        record.relativePath = destinationPath
        record.updatedAt = Date()
        var proposed = records
        proposed[noteID] = record
        try commit(proposed)
        return true
    }

    #if DEBUG
    /// Seeds historical bytes for compatibility and lifecycle tests. This is
    /// internal to ScholiumCore tests and is not part of a release build.
    func seedLegacyArchiveForTesting(_ legacyRecords: [HumanReviewRecord]) throws {
        var proposed = records
        for record in legacyRecords {
            proposed[record.id] = record
        }
        try commit(proposed)
    }
    #endif

    private func commit(_ proposed: [UUID: HumanReviewRecord]) throws {
        try requireHealthyStore(kind: "earlier Review archive")
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Payload(schemaVersion: 1, records: proposed))

        // Keep the live authority byte-for-byte equivalent to what another
        // delivery surface will load. ISO-8601 persistence intentionally
        // canonicalizes subsecond Dates; retaining the pre-encoded values in
        // memory would otherwise make GUI and snapshot-CLI projections differ
        // until the next process launch.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonicalRecords = try decoder.decode(Payload.self, from: data).records
        try data.write(to: fileURL, options: .atomic)
        records = canonicalRecords
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }

}


public enum ResearchFunctionRecordStoreError: LocalizedError, Sendable {
    case runNotFound(UUID)
    case duplicateRun(UUID)
    case preparationMismatch(UUID)
    case completionMismatch(UUID)
    case runAlreadyCompleted(UUID)

    public var errorDescription: String? {
        switch self {
        case .runNotFound(let id):
            "Research Function run not found: \(id.uuidString)"
        case .duplicateRun(let id):
            "Research Function run is recorded more than once: \(id.uuidString)"
        case .preparationMismatch(let id):
            "Research Function preflight finalization does not preserve its fixed run: \(id.uuidString)"
        case .completionMismatch(let id):
            "Research Function completion does not match its prepared run: \(id.uuidString)"
        case .runAlreadyCompleted(let id):
            "Research Function run already has different completion evidence: \(id.uuidString)"
        }
    }
}

private func canFinalizeFunctionPreflight(
    _ current: ResearchFunctionSnapshot,
    as replacement: ResearchFunctionSnapshot
) -> Bool {
    guard current.request.awaitsResourceSelection,
          replacement.request.conditionalResources != nil,
          current.runID == replacement.runID,
          current.recordKind == replacement.recordKind,
          current.recordID == replacement.recordID,
          current.checkpointID == replacement.checkpointID,
          current.requiredChildFunctions == replacement.requiredChildFunctions,
          current.preparedOutput == replacement.preparedOutput,
          current.evidenceRevisions == replacement.evidenceRevisions,
          current.fidelityHandoff == replacement.fidelityHandoff,
          current.confirmationToken == replacement.confirmationToken,
          current.preparedAt == replacement.preparedAt,
          functionRequestsMatchExceptMethods(current.request, replacement.request),
          skillSelections(current.skills, areRetainedBy: replacement.skills),
          current.phases.count == replacement.phases.count else {
        return false
    }

    return zip(current.phases, replacement.phases).allSatisfy { old, new in
        old.phase == new.phase
            && old.function == new.function
            && old.citationStyle == new.citationStyle
            && skillSelections(old.skills, areRetainedBy: new.skills)
    }
}

private func functionRequestsMatchExceptMethods(
    _ lhs: ResearchFunctionRequest,
    _ rhs: ResearchFunctionRequest
) -> Bool {
    ResearchFunctionRequest(
        function: lhs.function,
        target: lhs.target,
        materials: lhs.materials,
        instruction: lhs.instruction,
        scope: lhs.scope,
        checks: lhs.checks,
        commentIDs: lhs.commentIDs,
        conditionalResources: nil
    ) == ResearchFunctionRequest(
        function: rhs.function,
        target: rhs.target,
        materials: rhs.materials,
        instruction: rhs.instruction,
        scope: rhs.scope,
        checks: rhs.checks,
        commentIDs: rhs.commentIDs,
        conditionalResources: nil
    )
}

private func skillSelections(
    _ current: [ResearchFunctionSkillSnapshot],
    areRetainedBy replacement: [ResearchFunctionSkillSnapshot]
) -> Bool {
    guard current.count == replacement.count else { return false }
    return current.allSatisfy { old in
        guard let new = replacement.first(where: {
            $0.packageID == old.packageID && $0.origin == old.origin
        }),
        new.version == old.version,
        new.packageRevision == old.packageRevision else {
            return false
        }
        return Set(old.loadedResources).isSubset(of: Set(new.loadedResources))
    }
}

private func canAdvanceFunctionCompletion(
    from existing: ResearchFunctionCompletion,
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
    guard existing.runID == replacement.runID,
          existing.function == replacement.function,
          existing.targetFingerprint == replacement.targetFingerprint,
          existing.materialFingerprints == replacement.materialFingerprints,
          existing.didModifyTarget == replacement.didModifyTarget,
          replacement.completedAt >= existing.completedAt,
          stateAdvances else {
        return false
    }
    let allowedChecks = snapshot.fidelityHandoff?.checks ?? snapshot.request.checks
    return Set(replacement.fidelityOutcomes.map(\.check)).isSubset(of: allowedChecks)
}

public actor DialogueStore {
    private struct Payload: Codable {
        let schemaVersion: Int
        var entries: [UUID: DialogueEntry]
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var entries: [UUID: DialogueEntry]
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        fileURL = storageURL.appendingPathComponent("dialogue.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                entries = payload.entries
                loadFailure = payload.schemaVersion == 2
                    ? nil
                    : "Unsupported Discussion schema version \(payload.schemaVersion)."
            } catch {
                entries = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            entries = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Discussion", reason: $0)
                .localizedDescription
        }
    }

    public func entry(id: UUID) throws -> DialogueEntry {
        guard let entry = entries[id] else { throw DialogueError.entryNotFound(id) }
        return entry
    }

    public func entries(noteID: UUID) -> [DialogueEntry] {
        entries.values.filter { entry in
            entry.selectedNotes.contains { $0.noteID == noteID }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func allEntries() -> [DialogueEntry] {
        entries.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func functionRecord(
        runID: UUID
    ) throws -> ResearchFunctionRecordProjection? {
        let matches = entries.values.filter { $0.functionSnapshot?.runID == runID }
        guard matches.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let entry = matches.first, let snapshot = entry.functionSnapshot else {
            return nil
        }
        return ResearchFunctionRecordProjection(
            snapshot: snapshot,
            completion: entry.functionCompletion,
            preparedInstructions: entry.preparedInstructions
        )
    }

    /// Returns the durable Research Function projections owned by Dialogue.
    /// Application merges this with the Critique authority when planning from
    /// committed evidence; derived workspace snapshots are not an authority for
    /// deduplication or Manuscript child selection.
    public func functionRecords() throws -> [ResearchFunctionRecordProjection] {
        let records = entries.values.compactMap { entry in
            entry.functionSnapshot.map {
                ResearchFunctionRecordProjection(
                    snapshot: $0,
                    completion: entry.functionCompletion,
                    preparedInstructions: entry.preparedInstructions
                )
            }
        }
        guard Set(records.map(\.id)).count == records.count else {
            let duplicated = Dictionary(grouping: records, by: \.id)
                .first(where: { $0.value.count > 1 })!.key
            throw ResearchFunctionRecordStoreError.duplicateRun(duplicated)
        }
        return records.sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Removes every Dialogue containing the note. Shared entries are deleted
    /// in full so permanent deletion cannot retain the deleted note's selected
    /// context, comments, quotations, replies, or generated transport text.
    @discardableResult
    public func purgeEntries(containing noteID: UUID) throws -> [DialogueEntry] {
        try requireHealthyStore(kind: "Discussion")
        let removed = entries.values.filter { entry in
            entry.selectedNotes.contains { $0.noteID == noteID }
        }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        let proposed = entries.filter { !removedIDs.contains($0.key) }
        try commit(proposed)
        return removed.sorted { $0.createdAt > $1.createdAt }
    }

    func restorePurgedEntries(_ removed: [DialogueEntry]) throws {
        try requireHealthyStore(kind: "Discussion")
        var proposed = entries
        for entry in removed {
            if let existing = proposed[entry.id] {
                guard try persistentlyEquivalent(existing, entry) else {
                    throw ResearchRecordStoreError.restorationConflict(
                        kind: "Discussion",
                        identity: entry.id.uuidString
                    )
                }
                continue
            }
            proposed[entry.id] = entry
        }
        guard proposed != entries else { return }
        try commit(proposed)
    }

    @discardableResult
    public func save(_ entry: DialogueEntry) throws -> DialogueEntry {
        guard !entry.instruction.isEmpty else { throw DialogueError.emptyInstruction }
        guard !entry.selectedNotes.isEmpty else { throw DialogueError.noSelectedNotes }
        let selectedNoteIDs = Set(entry.selectedNotes.map(\.noteID))
        let selectedNoteReferences = Set(entry.selectedNotes)
        guard selectedNoteIDs.count == entry.selectedNotes.count else {
            throw DialogueError.invalidCommentOwner
        }
        guard entry.includedComments.allSatisfy({ included in
            selectedNoteReferences.contains(included.note)
        }) else {
            throw DialogueError.invalidCommentOwner
        }
        var proposed = entries
        proposed[entry.id] = entry
        try commit(proposed)
        return entries[entry.id] ?? entry
    }

    /// Persists completion or cancellation evidence on the exact prepared run.
    /// Repeating the same completion is idempotent; replacing different
    /// evidence is rejected.
    @discardableResult
    public func setFunctionCompletion(
        _ completion: ResearchFunctionCompletion,
        runID: UUID
    ) throws -> DialogueEntry {
        guard completion.runID == runID else {
            throw ResearchFunctionRecordStoreError.completionMismatch(runID)
        }
        let matches = entries.values.filter { $0.functionSnapshot?.runID == runID }
        guard matches.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let current = matches.first, let snapshot = current.functionSnapshot else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard snapshot.request.function == completion.function else {
            throw ResearchFunctionRecordStoreError.completionMismatch(runID)
        }
        if let existing = current.functionCompletion {
            if existing == completion { return current }
            guard canAdvanceFunctionCompletion(
                from: existing,
                to: completion,
                snapshot: snapshot
            ) else {
                throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
            }
        }
        let updated = Self.replacingFunctionEvidence(
            in: current,
            snapshot: snapshot,
            completion: completion
        )
        var proposed = entries
        proposed[current.id] = updated
        try commit(proposed)
        return entries[current.id] ?? updated
    }

    /// Atomically turns one read-only, method-unresolved preflight into its
    /// immutable execution handoff. No Target, checkpoint, record identity,
    /// package revision, or already-loaded resource may change.
    @discardableResult
    public func finalizeFunctionPreflight(
        snapshot replacement: ResearchFunctionSnapshot,
        instructions: String,
        runID: UUID
    ) throws -> DialogueEntry {
        let matches = entries.values.filter { $0.functionSnapshot?.runID == runID }
        guard matches.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let current = matches.first, let snapshot = current.functionSnapshot else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard current.functionCompletion == nil else {
            throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
        }
        if snapshot == replacement, current.preparedInstructions == instructions {
            return current
        }
        guard canFinalizeFunctionPreflight(snapshot, as: replacement) else {
            throw ResearchFunctionRecordStoreError.preparationMismatch(runID)
        }
        let updated = Self.replacingFunctionPreparation(
            in: current,
            snapshot: replacement,
            instructions: instructions
        )
        var proposed = entries
        proposed[current.id] = updated
        try commit(proposed)
        return entries[current.id] ?? updated
    }

    /// Rolls back only an incomplete record created for the named run.
    @discardableResult
    public func discardPreparedFunctionRecord(runID: UUID) throws -> DialogueEntry {
        let matches = entries.values.filter { $0.functionSnapshot?.runID == runID }
        guard matches.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let entry = matches.first else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard entry.functionCompletion == nil else {
            throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
        }
        var proposed = entries
        proposed.removeValue(forKey: entry.id)
        try commit(proposed)
        return entry
    }

    @discardableResult
    public func appendReply(_ reply: DialogueReply, to entryID: UUID) throws -> DialogueEntry {
        guard !reply.text.isEmpty else { throw DialogueError.emptyReply }
        guard !reply.agentName.isEmpty else { throw DialogueError.emptyAgentName }
        guard var entry = entries[entryID] else { throw DialogueError.entryNotFound(entryID) }
        guard !entry.replies.contains(where: { $0.id == reply.id }) else {
            throw DialogueError.duplicateReply(reply.id)
        }
        try validateDialogueTarget(noteID: reply.noteID, commentID: reply.commentID, in: entry)
        entry.replies.append(reply)
        var proposed = entries
        proposed[entryID] = entry
        try commit(proposed)
        return entries[entryID] ?? entry
    }

    @discardableResult
    public func appendFollowUpComment(
        _ comment: DialogueFollowUpComment,
        to entryID: UUID
    ) throws -> DialogueEntry {
        guard !comment.text.isEmpty else { throw DialogueError.emptyFollowUpComment }
        guard var entry = entries[entryID] else { throw DialogueError.entryNotFound(entryID) }
        guard !entry.followUpComments.contains(where: { $0.id == comment.id }) else {
            throw DialogueError.duplicateFollowUpComment(comment.id)
        }
        try validateDialogueTarget(
            noteID: comment.noteID,
            commentID: comment.commentID,
            in: entry
        )
        entry.followUpComments.append(comment)
        var proposed = entries
        proposed[entryID] = entry
        try commit(proposed)
        return entries[entryID] ?? entry
    }

    private func validateDialogueTarget(
        noteID: UUID?,
        commentID: UUID?,
        in entry: DialogueEntry
    ) throws {
        if let noteID,
           !entry.selectedNotes.contains(where: { $0.noteID == noteID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let commentID,
           !entry.includedComments.contains(where: { $0.comment.id == commentID }) {
            throw DialogueError.invalidReplyTarget
        }
        if let noteID, let commentID,
           !entry.includedComments.contains(where: {
               $0.comment.id == commentID && $0.note.noteID == noteID
           }) {
            throw DialogueError.invalidReplyTarget
        }
    }

    /// Migrates only the current structured note references. The generated
    /// prompt remains an immutable historical record of what was copied.
    @discardableResult
    public func migratePathIfPresent(
        noteID: UUID,
        vaultID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> Int {
        var changedEntries = 0
        var updatedEntries = entries

        for (entryID, entry) in entries {
            let references = entry.selectedNotes.filter {
                $0.noteID == noteID && $0.vaultID == vaultID
            }
            guard !references.isEmpty else { continue }
            if let unexpected = references.first(where: {
                $0.relativePath != sourcePath && $0.relativePath != destinationPath
            }) {
                throw DialogueError.noteReferencePathMismatch(
                    expected: sourcePath,
                    actual: unexpected.relativePath
                )
            }
            guard references.contains(where: { $0.relativePath == sourcePath }) else { continue }

            let migratedNotes = entry.selectedNotes.map { note -> DialogueNoteReference in
                guard note.noteID == noteID,
                      note.vaultID == vaultID,
                      note.relativePath == sourcePath else { return note }
                return DialogueNoteReference(
                    noteID: note.noteID,
                    vaultID: note.vaultID,
                    vaultName: note.vaultName,
                    title: note.title,
                    relativePath: destinationPath,
                    fingerprint: note.fingerprint,
                    kind: note.kind
                )
            }
            let migratedReference = migratedNotes.first {
                $0.noteID == noteID && $0.vaultID == vaultID
            }
            let migratedComments = entry.includedComments.map { included -> DialogueIncludedComment in
                let note = included.note
                guard note.noteID == noteID,
                      note.vaultID == vaultID,
                      note.relativePath == sourcePath,
                      let migratedReference else { return included }
                return DialogueIncludedComment(
                    note: migratedReference,
                    comment: included.comment
                )
            }
            updatedEntries[entryID] = DialogueEntry(
                id: entry.id,
                triptychID: entry.triptychID,
                instruction: entry.instruction,
                selectedNotes: migratedNotes,
                includedComments: migratedComments,
                preparedInstructions: entry.preparedInstructions,
                checkpointID: entry.checkpointID,
                functionSnapshot: entry.functionSnapshot,
                functionCompletion: entry.functionCompletion,
                responseContract: entry.responseContract,
                requestedDestination: entry.requestedDestination,
                linkedNoteSummary: entry.linkedNoteSummary,
                createdAt: entry.createdAt,
                followUpComments: entry.followUpComments,
                replies: entry.replies
            )
            changedEntries += 1
        }

        guard changedEntries > 0 else { return 0 }
        try commit(updatedEntries)
        return changedEntries
    }

    private static func replacingFunctionEvidence(
        in entry: DialogueEntry,
        snapshot: ResearchFunctionSnapshot?,
        completion: ResearchFunctionCompletion?
    ) -> DialogueEntry {
        DialogueEntry(
            id: entry.id,
            triptychID: entry.triptychID,
            instruction: entry.instruction,
            selectedNotes: entry.selectedNotes,
            includedComments: entry.includedComments,
            preparedInstructions: entry.preparedInstructions,
            checkpointID: entry.checkpointID,
            functionSnapshot: snapshot,
            functionCompletion: completion,
            responseContract: entry.responseContract,
            requestedDestination: entry.requestedDestination,
            linkedNoteSummary: entry.linkedNoteSummary,
            createdAt: entry.createdAt,
            followUpComments: entry.followUpComments,
            replies: entry.replies
        )
    }

    private static func replacingFunctionPreparation(
        in entry: DialogueEntry,
        snapshot: ResearchFunctionSnapshot,
        instructions: String
    ) -> DialogueEntry {
        DialogueEntry(
            id: entry.id,
            triptychID: entry.triptychID,
            instruction: entry.instruction,
            selectedNotes: entry.selectedNotes,
            includedComments: entry.includedComments,
            preparedInstructions: instructions,
            checkpointID: entry.checkpointID,
            functionSnapshot: snapshot,
            functionCompletion: nil,
            responseContract: entry.responseContract,
            requestedDestination: entry.requestedDestination,
            linkedNoteSummary: entry.linkedNoteSummary,
            createdAt: entry.createdAt,
            followUpComments: entry.followUpComments,
            replies: entry.replies
        )
    }

    private func commit(_ proposed: [UUID: DialogueEntry]) throws {
        try requireHealthyStore(kind: "Discussion")
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Payload(schemaVersion: 2, entries: proposed))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonicalEntries = try decoder.decode(Payload.self, from: data).entries
        try data.write(to: fileURL, options: .atomic)
        entries = canonicalEntries
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }
}


public actor CritiqueRegistry {
    private struct Payload: Codable {
        let schemaVersion: Int
        var associations: [UUID: CritiqueAssociation]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private var associations: [UUID: CritiqueAssociation]
    private let loadFailure: String?

    public init(controlURL: URL, fileManager: FileManager = .default) {
        fileURL = controlURL.appendingPathComponent("critiques.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let payload = try decoder.decode(Payload.self, from: data)
                let normalized = Self.normalized(payload.associations)
                associations = normalized
                if payload.schemaVersion != 2 {
                    loadFailure = "Unsupported Critique schema version \(payload.schemaVersion)."
                } else if normalized.count != payload.associations.count {
                    loadFailure = "The file contains duplicate Work or Critique associations. Scholium selected the newest entries for reading but will not rewrite the file automatically."
                } else {
                    loadFailure = nil
                }
            } catch {
                associations = [:]
                loadFailure = error.localizedDescription
            }
        } else {
            associations = [:]
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Critique", reason: $0)
                .localizedDescription
        }
    }

    public func association(workNoteID: UUID) -> CritiqueAssociation? {
        associations.values.first { $0.workNoteID == workNoteID }
    }

    public func association(critiqueRelativePath: String) -> CritiqueAssociation? {
        associations.values.first { $0.critiqueRelativePath == critiqueRelativePath }
    }

    public func functionRecord(
        runID: UUID
    ) throws -> ResearchFunctionRecordProjection? {
        let matches = associations.values.flatMap(\.rounds).filter {
            $0.functionSnapshot?.runID == runID
        }
        guard matches.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let round = matches.first, let snapshot = round.functionSnapshot else {
            return nil
        }
        return ResearchFunctionRecordProjection(
            snapshot: snapshot,
            completion: round.functionCompletion,
            preparedInstructions: round.functionInstructions
        )
    }

    /// Returns the durable Research Function projections owned by Critique.
    /// Application keeps these evidential records distinct while merging their
    /// projections with Dialogue-backed runs for authoritative planning.
    public func functionRecords() throws -> [ResearchFunctionRecordProjection] {
        let records = associations.values.flatMap(\.rounds).compactMap { round in
            round.functionSnapshot.map {
                ResearchFunctionRecordProjection(
                    snapshot: $0,
                    completion: round.functionCompletion,
                    preparedInstructions: round.functionInstructions
                )
            }
        }
        guard Set(records.map(\.id)).count == records.count else {
            let duplicated = Dictionary(grouping: records, by: \.id)
                .first(where: { $0.value.count > 1 })!.key
            throw ResearchFunctionRecordStoreError.duplicateRun(duplicated)
        }
        return records.sorted {
            if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                return $0.snapshot.preparedAt > $1.snapshot.preparedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func associationsRelated(noteID: UUID, relativePath: String) -> [CritiqueAssociation] {
        associations.values.filter {
            $0.workNoteID == noteID || $0.critiqueRelativePath == relativePath
        }.sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func save(_ association: CritiqueAssociation) throws -> CritiqueAssociation {
        if associations.values.contains(where: {
            $0.id != association.id
                && $0.critiqueRelativePath == association.critiqueRelativePath
                && $0.workNoteID != association.workNoteID
        }) {
            throw CritiqueRegistryError.destinationAlreadyAssociated(association.critiqueRelativePath)
        }
        var updated = association
        updated.updatedAt = Date()
        var proposed = associations
        for duplicateID in proposed.values
            .filter({ $0.id != association.id && $0.workNoteID == association.workNoteID })
            .map(\.id) {
            proposed.removeValue(forKey: duplicateID)
        }
        proposed[association.id] = updated
        try commit(proposed)
        return associations[association.id] ?? updated
    }

    @discardableResult
    public func recordRequest(
        workNoteID: UUID,
        workRelativePath: String,
        targetFingerprint: DocumentFingerprint,
        critiqueRelativePath: String,
        checkpointID: UUID?,
        scope: CritiqueRequestScope,
        roundID: UUID = UUID(),
        functionSnapshot: ResearchFunctionSnapshot? = nil,
        functionCompletion: ResearchFunctionCompletion? = nil,
        functionInstructions: String? = nil,
        requestedAt: Date = Date()
    ) throws -> CritiqueAssociation {
        var association = association(workNoteID: workNoteID) ?? CritiqueAssociation(
            workNoteID: workNoteID,
            workRelativePath: workRelativePath,
            targetFingerprint: targetFingerprint,
            critiqueRelativePath: critiqueRelativePath,
            createdAt: requestedAt,
            updatedAt: requestedAt
        )
        association.workRelativePath = workRelativePath
        association.targetFingerprint = targetFingerprint
        association.critiqueRelativePath = critiqueRelativePath
        association.rounds.append(CritiqueRound(
            id: roundID,
            requestedAt: requestedAt,
            targetFingerprint: targetFingerprint,
            checkpointID: checkpointID,
            scope: scope,
            functionSnapshot: functionSnapshot,
            functionCompletion: functionCompletion,
            functionInstructions: functionInstructions
        ))
        return try save(association)
    }

    @discardableResult
    public func setFunctionCompletion(
        _ completion: ResearchFunctionCompletion,
        runID: UUID
    ) throws -> CritiqueAssociation {
        guard completion.runID == runID else {
            throw ResearchFunctionRecordStoreError.completionMismatch(runID)
        }
        let locations = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.functionSnapshot?.runID == runID
                    ? (association.id, index, round)
                    : nil
            }
        }
        guard locations.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let (associationID, index, round) = locations.first,
              var association = associations[associationID],
              let snapshot = round.functionSnapshot else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard snapshot.request.function == completion.function else {
            throw ResearchFunctionRecordStoreError.completionMismatch(runID)
        }
        if let existing = round.functionCompletion {
            if existing == completion { return association }
            guard canAdvanceFunctionCompletion(
                from: existing,
                to: completion,
                snapshot: snapshot
            ) else {
                throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
            }
        }
        association.rounds[index] = CritiqueRound(
            id: round.id,
            requestedAt: round.requestedAt,
            targetFingerprint: round.targetFingerprint,
            checkpointID: round.checkpointID,
            scope: round.scope,
            functionSnapshot: snapshot,
            functionCompletion: completion,
            functionInstructions: round.functionInstructions,
            actionableFindings: round.actionableFindings,
            findingDispositions: round.findingDispositions,
            completedAt: round.completedAt
        )
        return try save(association)
    }

    /// Freezes the actionable finding set from the completed, version-bound
    /// Critique document. Later disposition never reparses or silently changes
    /// this researcher-facing round boundary.
    @discardableResult
    public func captureActionableFindings(
        runID: UUID,
        findings: [CritiqueFinding]
    ) throws -> CritiqueAssociation {
        let locations = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.functionSnapshot?.runID == runID
                    ? (association.id, index, round)
                    : nil
            }
        }
        guard locations.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let (associationID, index, round) = locations.first,
              var association = associations[associationID],
              round.functionCompletion?.function == .critique,
              round.functionCompletion?.state == .complete else {
            throw CritiqueRegistryError.roundNotReady(runID)
        }
        let normalized = CritiqueRound(
            id: round.id,
            requestedAt: round.requestedAt,
            targetFingerprint: round.targetFingerprint,
            checkpointID: round.checkpointID,
            scope: round.scope,
            functionSnapshot: round.functionSnapshot,
            functionCompletion: round.functionCompletion,
            functionInstructions: round.functionInstructions,
            actionableFindings: findings,
            findingDispositions: round.findingDispositions,
            completedAt: round.completedAt
        )
        if !round.actionableFindings.isEmpty,
           round.actionableFindings != normalized.actionableFindings {
            throw CritiqueRegistryError.findingSetAlreadyCaptured(round.id)
        }
        if round == normalized { return association }
        association.rounds[index] = normalized
        return try save(association)
    }

    /// Records one researcher disposition without creating Research Activity.
    /// Accept is valid only against an observed changed Work revision or with
    /// an explicit researcher rationale that no text change is required.
    @discardableResult
    public func setFindingDisposition(
        roundID: UUID,
        findingID: String,
        decision: CritiqueFindingDispositionDecision,
        currentWorkRevision: DocumentFingerprint,
        rationale: String?,
        noTextChangeRationale: String?
    ) throws -> CritiqueAssociation {
        guard let (associationID, index, round) = roundLocation(roundID: roundID),
              var association = associations[associationID] else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        guard round.completedAt == nil else {
            throw CritiqueRegistryError.roundAlreadyCompleted(roundID)
        }
        guard round.actionableFindings.contains(where: { $0.id == findingID }) else {
            throw CritiqueRegistryError.findingNotFound(findingID)
        }
        let noChange = noTextChangeRationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptedRevision: DocumentFingerprint?
        let acceptedWithoutChange: String?
        if decision == .accept {
            if currentWorkRevision != round.targetFingerprint {
                acceptedRevision = currentWorkRevision
                acceptedWithoutChange = nil
            } else {
                guard noChange?.isEmpty == false else {
                    throw CritiqueRegistryError.acceptRequiresChangeOrRationale(findingID)
                }
                acceptedRevision = nil
                acceptedWithoutChange = noChange
            }
        } else {
            acceptedRevision = nil
            acceptedWithoutChange = nil
        }
        let disposition = CritiqueFindingDisposition(
            findingID: findingID,
            decision: decision,
            rationale: rationale,
            acceptedRevision: acceptedRevision,
            noTextChangeRationale: acceptedWithoutChange
        )
        var dispositions = round.findingDispositions.filter { $0.findingID != findingID }
        dispositions.append(disposition)
        association.rounds[index] = CritiqueRound(
            id: round.id,
            requestedAt: round.requestedAt,
            targetFingerprint: round.targetFingerprint,
            checkpointID: round.checkpointID,
            scope: round.scope,
            functionSnapshot: round.functionSnapshot,
            functionCompletion: round.functionCompletion,
            functionInstructions: round.functionInstructions,
            actionableFindings: round.actionableFindings,
            findingDispositions: dispositions,
            completedAt: nil
        )
        return try save(association)
    }

    /// Completes one fully disposed round. The returned association is
    /// idempotent; event projection remains an Application responsibility.
    @discardableResult
    public func completeRound(
        roundID: UUID,
        completedAt: Date = Date()
    ) throws -> CritiqueAssociation {
        guard let (associationID, index, round) = roundLocation(roundID: roundID),
              var association = associations[associationID] else {
            throw CritiqueRegistryError.roundNotFound(roundID)
        }
        if round.completedAt != nil { return association }
        guard round.isReadyToComplete else {
            throw CritiqueRegistryError.incompleteDispositions(roundID)
        }
        association.rounds[index] = CritiqueRound(
            id: round.id,
            requestedAt: round.requestedAt,
            targetFingerprint: round.targetFingerprint,
            checkpointID: round.checkpointID,
            scope: round.scope,
            functionSnapshot: round.functionSnapshot,
            functionCompletion: round.functionCompletion,
            functionInstructions: round.functionInstructions,
            actionableFindings: round.actionableFindings,
            findingDispositions: round.findingDispositions,
            completedAt: completedAt
        )
        return try save(association)
    }

    /// Critique keeps the prepared output and round identity fixed while the
    /// external agent finalizes only its conditional method references.
    @discardableResult
    public func finalizeFunctionPreflight(
        snapshot replacement: ResearchFunctionSnapshot,
        instructions: String,
        runID: UUID
    ) throws -> CritiqueAssociation {
        let locations = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.functionSnapshot?.runID == runID
                    ? (association.id, index, round)
                    : nil
            }
        }
        guard locations.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let (associationID, index, round) = locations.first,
              var association = associations[associationID],
              let snapshot = round.functionSnapshot else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard round.functionCompletion == nil else {
            throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
        }
        if snapshot == replacement, round.functionInstructions == instructions {
            return association
        }
        guard canFinalizeFunctionPreflight(snapshot, as: replacement) else {
            throw ResearchFunctionRecordStoreError.preparationMismatch(runID)
        }
        association.rounds[index] = CritiqueRound(
            id: round.id,
            requestedAt: round.requestedAt,
            targetFingerprint: round.targetFingerprint,
            checkpointID: round.checkpointID,
            scope: round.scope,
            functionSnapshot: replacement,
            functionCompletion: nil,
            functionInstructions: instructions,
            actionableFindings: round.actionableFindings,
            findingDispositions: round.findingDispositions,
            completedAt: round.completedAt
        )
        return try save(association)
    }

    /// Rolls back only the incomplete Critique round prepared for this run.
    /// An association with older rounds is retained; an otherwise empty
    /// association is removed.
    @discardableResult
    public func discardPreparedFunctionRecord(
        runID: UUID
    ) throws -> CritiqueRound {
        let locations = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.functionSnapshot?.runID == runID
                    ? (association.id, index, round)
                    : nil
            }
        }
        guard locations.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(runID)
        }
        guard let (associationID, index, round) = locations.first,
              var association = associations[associationID] else {
            throw ResearchFunctionRecordStoreError.runNotFound(runID)
        }
        guard round.functionCompletion == nil else {
            throw ResearchFunctionRecordStoreError.runAlreadyCompleted(runID)
        }
        association.rounds.remove(at: index)
        var proposed = associations
        if association.rounds.isEmpty {
            proposed.removeValue(forKey: associationID)
        } else {
            association.updatedAt = Date()
            proposed[associationID] = association
        }
        try commit(proposed)
        return round
    }

    /// Critique preparation may persist its round before the function snapshot
    /// is attached. This rollback key is therefore the immutable round identity
    /// rather than a run identity. Only an uncompleted round can be removed.
    @discardableResult
    public func discardPreparedRound(roundID: UUID) throws -> CritiqueRound {
        let locations = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.id == roundID ? (association.id, index, round) : nil
            }
        }
        guard locations.count <= 1 else {
            throw ResearchFunctionRecordStoreError.duplicateRun(roundID)
        }
        guard let (associationID, index, round) = locations.first,
              var association = associations[associationID] else {
            throw ResearchFunctionRecordStoreError.runNotFound(roundID)
        }
        guard round.functionCompletion == nil else {
            throw ResearchFunctionRecordStoreError.runAlreadyCompleted(roundID)
        }
        association.rounds.remove(at: index)
        var proposed = associations
        if association.rounds.isEmpty {
            proposed.removeValue(forKey: associationID)
        } else {
            association.updatedAt = Date()
            proposed[associationID] = association
        }
        try commit(proposed)
        return round
    }

    /// Keeps a Work association and its Critique destination attached to a
    /// stable note after a confirmed move. Historical target fingerprints are
    /// intentionally unchanged.
    @discardableResult
    public func movePath(
        noteID: UUID,
        from sourcePath: String,
        to destinationPath: String
    ) throws -> [CritiqueAssociation] {
        if let workAssociation = associations.values.first(where: { $0.workNoteID == noteID }),
           workAssociation.workRelativePath != sourcePath,
           workAssociation.workRelativePath != destinationPath {
            throw CritiqueRegistryError.workPathMismatch(
                expected: sourcePath,
                actual: workAssociation.workRelativePath
            )
        }
        var proposed = associations
        var changed: [CritiqueAssociation] = []
        for id in Array(proposed.keys) {
            guard var association = proposed[id] else { continue }
            var didChange = false
            if association.workNoteID == noteID && association.workRelativePath == sourcePath {
                association.workRelativePath = destinationPath
                didChange = true
            }
            if association.critiqueRelativePath == sourcePath {
                association.critiqueRelativePath = destinationPath
                didChange = true
            }
            guard didChange else { continue }
            association.updatedAt = Date()
            proposed[id] = association
            changed.append(association)
        }
        if !changed.isEmpty {
            try commit(proposed)
        }
        return changed.compactMap { associations[$0.id] }
    }

    public func remove(id: UUID) throws {
        var proposed = associations
        proposed.removeValue(forKey: id)
        try commit(proposed)
    }

    /// Removes associations owned by a deleted Work or pointing at a deleted
    /// Critique path. The Critique Markdown itself is handled by the vault
    /// deletion coordinator; this store owns only portable association state.
    @discardableResult
    public func purgeAssociations(
        noteID: UUID,
        relativePath: String
    ) throws -> [CritiqueAssociation] {
        try requireHealthyStore(kind: "Critique")
        let removed = associations.values.filter {
            $0.workNoteID == noteID || $0.critiqueRelativePath == relativePath
        }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        let proposed = associations.filter { !removedIDs.contains($0.key) }
        try commit(proposed)
        return removed.sorted { $0.createdAt < $1.createdAt }
    }

    func restorePurgedAssociations(_ removed: [CritiqueAssociation]) throws {
        try requireHealthyStore(kind: "Critique")
        var proposed = associations
        for association in removed {
            if let existing = proposed[association.id] {
                guard try persistentlyEquivalent(existing, association) else {
                    throw ResearchRecordStoreError.restorationConflict(
                        kind: "Critique",
                        identity: association.id.uuidString
                    )
                }
                continue
            }
            if proposed.values.contains(where: {
                $0.id != association.id
                    && ($0.workNoteID == association.workNoteID
                        || $0.critiqueRelativePath == association.critiqueRelativePath)
            }) {
                throw ResearchRecordStoreError.restorationConflict(
                    kind: "Critique",
                    identity: association.id.uuidString
                )
            }
            proposed[association.id] = association
        }
        guard proposed != associations else { return }
        try commit(proposed)
    }

    private func commit(_ proposed: [UUID: CritiqueAssociation]) throws {
        try requireHealthyStore(kind: "Critique")
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Payload(schemaVersion: 2, associations: proposed))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonicalAssociations = try decoder.decode(
            Payload.self,
            from: data
        ).associations
        try data.write(to: fileURL, options: .atomic)
        associations = canonicalAssociations
    }

    private func requireHealthyStore(kind: String) throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(kind: kind, reason: loadFailure)
        }
    }

    private func roundLocation(
        roundID: UUID
    ) -> (associationID: UUID, index: Int, round: CritiqueRound)? {
        let matches = associations.values.flatMap { association in
            association.rounds.enumerated().compactMap { index, round in
                round.id == roundID ? (association.id, index, round) : nil
            }
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func normalized(
        _ candidates: [UUID: CritiqueAssociation]
    ) -> [UUID: CritiqueAssociation] {
        var workIDs: Set<UUID> = []
        var critiquePaths: Set<String> = []
        var result: [UUID: CritiqueAssociation] = [:]
        for association in candidates.values.sorted(by: {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }) {
            guard workIDs.insert(association.workNoteID).inserted,
                  critiquePaths.insert(association.critiqueRelativePath).inserted else { continue }
            result[association.id] = association
        }
        return result
    }
}
