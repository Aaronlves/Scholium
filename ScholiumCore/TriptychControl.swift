import CryptoKit
import Foundation
import ScholiumContracts

/// Owns the small, portable `.scholium` directory beside the Works vault.
public actor TriptychControlStore {
    private struct StoredIdentityAmbiguity: Codable {
        let vaultID: UUID
        let relativePath: String
        var fingerprint: DocumentFingerprint
        var candidateIDs: [UUID]
        let detectedAt: Date
    }

    private struct IdentityFile: Codable {
        var records: [NoteIdentityRecord]
        var pendingRebindings: [NoteIdentityPendingRebinding]
        var unresolvedAmbiguities: [StoredIdentityAmbiguity]

        init(
            records: [NoteIdentityRecord],
            pendingRebindings: [NoteIdentityPendingRebinding] = [],
            unresolvedAmbiguities: [StoredIdentityAmbiguity] = []
        ) {
            self.records = records
            self.pendingRebindings = pendingRebindings
            self.unresolvedAmbiguities = unresolvedAmbiguities
        }

        private enum CodingKeys: String, CodingKey {
            case records
            case pendingRebindings
            case unresolvedAmbiguities
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([NoteIdentityRecord].self, forKey: .records) ?? []
            pendingRebindings = try container.decodeIfPresent(
                [NoteIdentityPendingRebinding].self,
                forKey: .pendingRebindings
            ) ?? []
            unresolvedAmbiguities = try container.decodeIfPresent(
                [StoredIdentityAmbiguity].self,
                forKey: .unresolvedAmbiguities
            ) ?? []
        }
    }

    public let controlURL: URL

    private let manifestURL: URL
    private let settingsURL: URL
    private let identitiesURL: URL
    private let fileManager: FileManager

    public init(worksVaultURL: URL, fileManager: FileManager = .default) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        self.fileManager = fileManager
    }

    @discardableResult
    public func bootstrap(
        vaultIDs: [WorkspaceVaultSlot: UUID],
        preferredTriptychID: UUID? = nil
    ) throws -> TriptychManifest {
        guard Set(vaultIDs.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw TriptychControlError.invalidManifest
        }
        try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)

        let now = Date()
        let manifest: TriptychManifest
        if var existing: TriptychManifest = try decodeIfPresent(TriptychManifest.self, from: manifestURL) {
            existing.vaultIDs = vaultIDs
            existing.updatedAt = now
            manifest = existing
        } else {
            manifest = TriptychManifest(
                id: preferredTriptychID ?? UUID(),
                vaultIDs: vaultIDs,
                createdAt: now,
                updatedAt: now
            )
        }
        try encode(manifest, to: manifestURL)

        if !fileManager.fileExists(atPath: settingsURL.path) {
            try encode(TriptychSettings(), to: settingsURL)
        }
        if !fileManager.fileExists(atPath: identitiesURL.path) {
            try encode(IdentityFile(records: []), to: identitiesURL)
        }
        return manifest
    }

    public func manifest() throws -> TriptychManifest {
        guard let manifest: TriptychManifest = try decodeIfPresent(TriptychManifest.self, from: manifestURL) else {
            throw TriptychControlError.invalidManifest
        }
        return manifest
    }

    public func settings() throws -> TriptychSettings {
        try decodeIfPresent(TriptychSettings.self, from: settingsURL) ?? TriptychSettings()
    }

    public func saveSettings(_ settings: TriptychSettings) throws {
        try ensureControlDirectory()
        try encode(settings, to: settingsURL)
    }

    public func identity(
        forVaultID vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createIfMissing: Bool = true
    ) throws -> NoteIdentityRecord? {
        var payload = try identityPayload()
        if let index = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) {
            if payload.records[index].fingerprint != fingerprint {
                payload.records[index].fingerprint = fingerprint
                payload.records[index].updatedAt = Date()
                try encode(payload, to: identitiesURL)
            }
            return payload.records[index]
        }
        guard createIfMissing else { return nil }
        let record = NoteIdentityRecord(
            vaultID: vaultID,
            relativePath: relativePath,
            fingerprint: fingerprint
        )
        payload.records.append(record)
        try ensureControlDirectory()
        try encode(payload, to: identitiesURL)
        return record
    }

    public func identityRecord(vaultID: UUID, relativePath: String) throws -> NoteIdentityRecord? {
        try identityPayload().records.first {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }
    }

    public func moveIdentity(
        id: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        var payload = try identityPayload()
        guard let index = payload.records.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !payload.records.contains(where: {
            $0.id != id
                && $0.vaultID == payload.records[index].vaultID
                && $0.relativePath == relativePath
        }) else {
            throw TriptychControlError.identityPathAlreadyAssigned(relativePath)
        }
        let previousPath = payload.records[index].relativePath
        payload.records[index].relativePath = relativePath
        payload.records[index].fingerprint = fingerprint
        payload.records[index].updatedAt = Date()
        if previousPath != relativePath {
            Self.enqueuePendingRebinding(
                NoteIdentityPendingRebinding(
                    noteID: id,
                    vaultID: payload.records[index].vaultID,
                    previousRelativePath: previousPath,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                ),
                in: &payload.pendingRebindings
            )
        }
        try encode(payload, to: identitiesURL)
        return payload.records[index]
    }

    /// Commits a lifecycle move against the portable identity inventory.
    ///
    /// The filesystem move and this identity write are separate actors, so a
    /// watcher or checkpoint refresh may leave the in-memory ID one step ahead
    /// of the portable file. Resolve by stable ID first, then by the expected
    /// source path, and finally recreate the same stable ID if the record was
    /// lost. The operation is idempotent when the destination is already
    /// assigned to that identity.
    public func moveIdentity(
        id: UUID,
        vaultID: UUID,
        from sourcePath: String,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        var payload = try identityPayload()

        let index: Int
        if let byID = payload.records.firstIndex(where: { $0.id == id }) {
            guard payload.records[byID].vaultID == vaultID else {
                throw CocoaError(.fileReadNoPermission)
            }
            if payload.records[byID].relativePath == sourcePath
                || payload.records[byID].relativePath == relativePath {
                index = byID
            } else if let bySource = payload.records.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == sourcePath
            }) {
                // A stale in-memory ID must not move an unrelated note. The
                // exact source path is the stronger lifecycle precondition.
                index = bySource
            } else if let byDestination = payload.records.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == relativePath
            }) {
                var existing = payload.records[byDestination]
                existing.fingerprint = fingerprint
                existing.updatedAt = Date()
                payload.records[byDestination] = existing
                try encode(payload, to: identitiesURL)
                return existing
            } else {
                throw CocoaError(.fileNoSuchFile)
            }
        } else if let bySource = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == sourcePath
        }) {
            index = bySource
        } else if let byDestination = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) {
            var existing = payload.records[byDestination]
            existing.fingerprint = fingerprint
            existing.updatedAt = Date()
            payload.records[byDestination] = existing
            try encode(payload, to: identitiesURL)
            return existing
        } else {
            let recovered = NoteIdentityRecord(
                id: id,
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: fingerprint
            )
            payload.records.append(recovered)
            try encode(payload, to: identitiesURL)
            return recovered
        }

        guard !payload.records.contains(where: {
            $0.id != payload.records[index].id
                && $0.vaultID == vaultID
                && $0.relativePath == relativePath
        }) else {
            throw TriptychControlError.identityPathAlreadyAssigned(relativePath)
        }

        let previousPath = payload.records[index].relativePath
        payload.records[index].relativePath = relativePath
        payload.records[index].fingerprint = fingerprint
        payload.records[index].updatedAt = Date()
        if previousPath != relativePath {
            Self.enqueuePendingRebinding(
                NoteIdentityPendingRebinding(
                    noteID: payload.records[index].id,
                    vaultID: vaultID,
                    previousRelativePath: previousPath,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                ),
                in: &payload.pendingRebindings
            )
        }
        try encode(payload, to: identitiesURL)
        return payload.records[index]
    }

    /// Rebinds every note moved by one directory rename in one portable-state
    /// write. Folder paths themselves are deliberately absent from this store.
    /// The method is idempotent when every identity already names its intended
    /// destination.
    public func moveIdentities(
        _ moves: [FolderNoteMoveCommit]
    ) throws -> [NoteIdentityRecord] {
        guard !moves.isEmpty else { return [] }
        let ids = moves.map(\.stableNoteID)
        guard Set(ids).count == ids.count else {
            throw TriptychControlError.invalidManifest
        }
        let destinations = moves.map {
            "\($0.destination.vaultID.uuidString):\($0.destination.relativePath)"
        }
        guard Set(destinations).count == destinations.count else {
            throw TriptychControlError.invalidManifest
        }

        var payload = try identityPayload()
        let movingIDs = Set(ids)
        for move in moves {
            guard let record = payload.records.first(where: {
                $0.id == move.stableNoteID
            }), record.vaultID == move.source.vaultID,
                  move.source.vaultID == move.destination.vaultID,
                  record.relativePath == move.source.relativePath
                    || record.relativePath == move.destination.relativePath else {
                throw TriptychControlError.invalidIdentityCandidate(move.stableNoteID)
            }
            guard !payload.records.contains(where: {
                !movingIDs.contains($0.id)
                    && $0.vaultID == move.destination.vaultID
                    && $0.relativePath == move.destination.relativePath
            }) else {
                throw TriptychControlError.identityPathAlreadyAssigned(
                    move.destination.relativePath
                )
            }
        }

        let timestamp = Date()
        var updated: [NoteIdentityRecord] = []
        for move in moves {
            guard let index = payload.records.firstIndex(where: {
                $0.id == move.stableNoteID
            }) else {
                throw TriptychControlError.invalidIdentityCandidate(move.stableNoteID)
            }
            let previousPath = payload.records[index].relativePath
            payload.records[index].relativePath = move.destination.relativePath
            payload.records[index].fingerprint = move.committedRevision
            payload.records[index].updatedAt = timestamp
            if previousPath != move.destination.relativePath {
                Self.enqueuePendingRebinding(
                    NoteIdentityPendingRebinding(
                        noteID: move.stableNoteID,
                        vaultID: move.destination.vaultID,
                        previousRelativePath: previousPath,
                        relativePath: move.destination.relativePath,
                        fingerprint: move.committedRevision
                    ),
                    in: &payload.pendingRebindings
                )
            }
            updated.append(payload.records[index])
        }
        try encode(payload, to: identitiesURL)
        return updated.sorted { $0.relativePath < $1.relativePath }
    }

    public func duplicateIdentity(
        from sourceID: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        let source = try identityPayload().records.first(where: { $0.id == sourceID })
        guard let source else { throw CocoaError(.fileNoSuchFile) }
        var payload = try identityPayload()
        let duplicate = NoteIdentityRecord(
            vaultID: source.vaultID,
            relativePath: relativePath,
            fingerprint: fingerprint,
            duplicatedFrom: sourceID
        )
        payload.records.append(duplicate)
        try encode(payload, to: identitiesURL)
        return duplicate
    }

    /// Removes the portable stable identity and every pending identity record
    /// that could reintroduce it after a researcher confirms permanent
    /// deletion. The exact vault and path are required to prevent a stale UI
    /// command from purging a reused identity or a different vault's note.
    @discardableResult
    public func purgeIdentity(
        id: UUID,
        vaultID: UUID,
        relativePath: String
    ) throws -> NoteIdentityRecord? {
        var payload = try identityPayload()
        guard let record = payload.records.first(where: { $0.id == id }) else { return nil }
        guard record.vaultID == vaultID, record.relativePath == relativePath else {
            throw TriptychControlError.invalidIdentityCandidate(id)
        }
        payload.records.removeAll { $0.id == id }
        payload.pendingRebindings.removeAll { $0.noteID == id }
        payload.unresolvedAmbiguities = payload.unresolvedAmbiguities.compactMap { ambiguity in
            var ambiguity = ambiguity
            ambiguity.candidateIDs.removeAll { $0 == id }
            return ambiguity.candidateIDs.isEmpty ? nil : ambiguity
        }
        try encode(payload, to: identitiesURL)
        return record
    }

    func prepareIdentityPurge(
        id: UUID,
        vaultID: UUID,
        relativePath: String
    ) throws -> PermanentDeletionIdentityBackup? {
        let payload = try identityPayload()
        guard let record = payload.records.first(where: { $0.id == id }) else { return nil }
        guard record.vaultID == vaultID, record.relativePath == relativePath else {
            throw TriptychControlError.invalidIdentityCandidate(id)
        }
        return PermanentDeletionIdentityBackup(
            record: record,
            pendingRebindings: payload.pendingRebindings.filter { $0.noteID == id },
            ambiguities: payload.unresolvedAmbiguities.compactMap { ambiguity in
                guard ambiguity.candidateIDs.contains(id) else { return nil }
                return PermanentDeletionIdentityAmbiguity(
                    vaultID: ambiguity.vaultID,
                    relativePath: ambiguity.relativePath,
                    fingerprint: ambiguity.fingerprint,
                    candidateIDs: ambiguity.candidateIDs,
                    detectedAt: ambiguity.detectedAt
                )
            }
        )
    }

    func restorePurgedIdentity(_ backup: PermanentDeletionIdentityBackup?) throws {
        guard let backup else { return }
        var payload = try identityPayload()
        if let existing = payload.records.first(where: { $0.id == backup.record.id }) {
            guard try persistentlyEquivalent(existing, backup.record) else {
                throw TriptychControlError.invalidIdentityCandidate(backup.record.id)
            }
        } else {
            guard !payload.records.contains(where: {
                $0.vaultID == backup.record.vaultID
                    && $0.relativePath == backup.record.relativePath
            }) else {
                throw TriptychControlError.identityPathAlreadyAssigned(backup.record.relativePath)
            }
            payload.records.append(backup.record)
        }
        for pending in backup.pendingRebindings where !payload.pendingRebindings.contains(pending) {
            payload.pendingRebindings.append(pending)
        }
        for ambiguity in backup.ambiguities {
            let restored = StoredIdentityAmbiguity(
                vaultID: ambiguity.vaultID,
                relativePath: ambiguity.relativePath,
                fingerprint: ambiguity.fingerprint,
                candidateIDs: ambiguity.candidateIDs,
                detectedAt: ambiguity.detectedAt
            )
            if let index = payload.unresolvedAmbiguities.firstIndex(where: {
                $0.vaultID == restored.vaultID && $0.relativePath == restored.relativePath
            }) {
                let existing = payload.unresolvedAmbiguities[index]
                guard existing.fingerprint == restored.fingerprint,
                      existing.candidateIDs == restored.candidateIDs else {
                    throw TriptychControlError.invalidIdentityCandidate(backup.record.id)
                }
            } else {
                payload.unresolvedAmbiguities.append(restored)
            }
        }
        try encode(payload, to: identitiesURL)
    }

    /// Reconciles one vault inventory in one atomic portable-state write.
    ///
    /// Exact paths are claimed before fingerprint matching so an external copy
    /// whose path sorts earlier cannot steal the original note's identity. A
    /// unique unused fingerprint match preserves identity across an external
    /// rename. Ambiguous matches remain unresolved until the researcher chooses
    /// an existing identity or confirms that the file is a new note.
    public func reconcileIdentityInventory(
        vaultID: UUID,
        documents: [(relativePath: String, fingerprint: DocumentFingerprint)]
    ) throws -> NoteIdentityReconciliation {
        var payload = try identityPayload()
        var result: [String: NoteIdentityRecord] = [:]
        var rebound: [NoteIdentityRebinding] = []
        var ambiguities: [NoteIdentityAmbiguity] = []
        var claimedIDs: Set<UUID> = []
        var unmatched: [(relativePath: String, fingerprint: DocumentFingerprint)] = []
        var changed = false

        // First reserve every identity whose path still exists. This is the
        // authoritative signal that a same-fingerprint file is a copy rather
        // than a rename of that still-present note.
        for document in documents.sorted(by: { $0.relativePath < $1.relativePath }) {
            if let index = payload.records.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == document.relativePath
            }) {
                if payload.records[index].fingerprint != document.fingerprint {
                    payload.records[index].fingerprint = document.fingerprint
                    payload.records[index].updatedAt = Date()
                    changed = true
                }
                claimedIDs.insert(payload.records[index].id)
                result[document.relativePath] = payload.records[index]
                let unresolvedCount = payload.unresolvedAmbiguities.count
                payload.unresolvedAmbiguities.removeAll {
                    $0.vaultID == vaultID && $0.relativePath == document.relativePath
                }
                if payload.unresolvedAmbiguities.count != unresolvedCount { changed = true }
            } else {
                unmatched.append(document)
            }
        }

        for document in unmatched {
            if let unresolvedIndex = payload.unresolvedAmbiguities.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == document.relativePath
            }) {
                let stored = payload.unresolvedAmbiguities[unresolvedIndex]
                let candidates = stored.candidateIDs.compactMap { candidateID in
                    payload.records.first { record in
                        record.id == candidateID
                            && record.vaultID == vaultID
                            && !claimedIDs.contains(record.id)
                    }
                }
                if payload.unresolvedAmbiguities[unresolvedIndex].fingerprint != document.fingerprint {
                    payload.unresolvedAmbiguities[unresolvedIndex].fingerprint = document.fingerprint
                    changed = true
                }
                ambiguities.append(NoteIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidates: candidates
                ))
                continue
            }
            let candidateIndices = payload.records.indices.filter { index in
                payload.records[index].vaultID == vaultID
                    && payload.records[index].fingerprint == document.fingerprint
                    && !claimedIDs.contains(payload.records[index].id)
            }
            if candidateIndices.count == 1, let index = candidateIndices.first {
                let previousPath = payload.records[index].relativePath
                payload.records[index].relativePath = document.relativePath
                payload.records[index].updatedAt = Date()
                claimedIDs.insert(payload.records[index].id)
                result[document.relativePath] = payload.records[index]
                rebound.append(NoteIdentityRebinding(
                    id: payload.records[index].id,
                    previousRelativePath: previousPath,
                    relativePath: document.relativePath
                ))
                Self.enqueuePendingRebinding(
                    NoteIdentityPendingRebinding(
                        noteID: payload.records[index].id,
                        vaultID: vaultID,
                        previousRelativePath: previousPath,
                        relativePath: document.relativePath,
                        fingerprint: document.fingerprint
                    ),
                    in: &payload.pendingRebindings
                )
                changed = true
            } else if candidateIndices.isEmpty {
                let record = NoteIdentityRecord(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint
                )
                payload.records.append(record)
                claimedIDs.insert(record.id)
                result[document.relativePath] = record
                changed = true
            } else {
                payload.unresolvedAmbiguities.removeAll {
                    $0.vaultID == vaultID && $0.relativePath == document.relativePath
                }
                payload.unresolvedAmbiguities.append(StoredIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidateIDs: candidateIndices.map { payload.records[$0].id },
                    detectedAt: Date()
                ))
                changed = true
                ambiguities.append(NoteIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidates: candidateIndices.map { payload.records[$0] }
                ))
            }
        }
        if changed {
            try ensureControlDirectory()
            try encode(payload, to: identitiesURL)
        }
        return NoteIdentityReconciliation(
            identities: result,
            rebound: rebound.sorted { $0.relativePath < $1.relativePath },
            ambiguities: ambiguities.sorted { $0.relativePath < $1.relativePath },
            pendingRebindings: payload.pendingRebindings
                .filter { $0.vaultID == vaultID }
                .sorted { $0.relativePath < $1.relativePath }
        )
    }

    /// Resolves an ambiguous external rename after the researcher has seen the
    /// candidate paths. Passing `nil` creates a new identity for the file.
    public func resolveIdentityAmbiguity(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        candidateID: UUID?
    ) throws -> NoteIdentityRecord {
        var payload = try identityPayload()
        guard !payload.records.contains(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) else {
            throw TriptychControlError.identityPathAlreadyAssigned(relativePath)
        }

        let record: NoteIdentityRecord
        if let candidateID {
            let storedCandidates = payload.unresolvedAmbiguities.first(where: {
                $0.vaultID == vaultID && $0.relativePath == relativePath
            })?.candidateIDs
            guard let index = payload.records.firstIndex(where: {
                $0.id == candidateID && $0.vaultID == vaultID
            }), storedCandidates?.contains(candidateID) ?? (payload.records[index].fingerprint == fingerprint) else {
                throw TriptychControlError.invalidIdentityCandidate(candidateID)
            }
            let previousPath = payload.records[index].relativePath
            payload.records[index].relativePath = relativePath
            payload.records[index].updatedAt = Date()
            record = payload.records[index]
            Self.enqueuePendingRebinding(
                NoteIdentityPendingRebinding(
                    noteID: record.id,
                    vaultID: vaultID,
                    previousRelativePath: previousPath,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                ),
                in: &payload.pendingRebindings
            )
        } else {
            record = NoteIdentityRecord(
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: fingerprint
            )
            payload.records.append(record)
        }
        payload.unresolvedAmbiguities.removeAll {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }
        try ensureControlDirectory()
        try encode(payload, to: identitiesURL)
        return record
    }

    public func pendingIdentityRebindings(
        vaultID: UUID? = nil
    ) throws -> [NoteIdentityPendingRebinding] {
        let pending = try identityPayload().pendingRebindings
        return pending
            .filter { vaultID == nil || $0.vaultID == vaultID }
            .sorted {
                if $0.vaultID != $1.vaultID {
                    return $0.vaultID.uuidString < $1.vaultID.uuidString
                }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }

    /// Marks a path migration complete only after every app-owned reference
    /// has been migrated. Calling this method again is harmless, which makes a
    /// recovery retry safe after an interruption.
    public func completeIdentityRebinding(_ rebinding: NoteIdentityPendingRebinding) throws {
        var payload = try identityPayload()
        guard let record = payload.records.first(where: {
            $0.id == rebinding.noteID
                && $0.vaultID == rebinding.vaultID
                && $0.relativePath == rebinding.relativePath
        }) else {
            throw TriptychControlError.identityRebindingNotFound(rebinding.noteID)
        }
        _ = record
        payload.pendingRebindings.removeAll { pending in
            pending.noteID == rebinding.noteID
                && pending.vaultID == rebinding.vaultID
                && pending.previousRelativePath == rebinding.previousRelativePath
                && pending.relativePath == rebinding.relativePath
        }
        try encode(payload, to: identitiesURL)
    }

    private static func enqueuePendingRebinding(
        _ rebinding: NoteIdentityPendingRebinding,
        in pending: inout [NoteIdentityPendingRebinding]
    ) {
        pending.removeAll { existing in
            existing.noteID == rebinding.noteID && existing.vaultID == rebinding.vaultID
        }
        pending.append(rebinding)
    }

    private func identityPayload() throws -> IdentityFile {
        try decodeIfPresent(IdentityFile.self, from: identitiesURL) ?? IdentityFile(records: [])
    }

    private func ensureControlDirectory() throws {
        try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
