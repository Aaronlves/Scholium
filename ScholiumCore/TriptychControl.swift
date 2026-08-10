import CryptoKit
import Darwin
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

    private struct IdentityFileSnapshot {
        var payload: IdentityFile
        var data: Data
    }

    private struct AnalysisZoteroBindingFile: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        var bindings: [AnalysisZoteroBinding]

        init(bindings: [AnalysisZoteroBinding]) {
            schemaVersion = Self.currentSchemaVersion
            self.bindings = bindings.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case bindings
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            guard schemaVersion == Self.currentSchemaVersion else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported Zotero binding schema \(schemaVersion)."
                )
            }
            bindings = try container.decode([AnalysisZoteroBinding].self, forKey: .bindings)
            guard Set(bindings.map(\.noteID)).count == bindings.count else {
                throw DecodingError.dataCorruptedError(
                    forKey: .bindings,
                    in: container,
                    debugDescription: "A Note may have at most one Zotero binding."
                )
            }
        }
    }

    public let controlURL: URL

    private let manifestURL: URL
    private let settingsURL: URL
    private let identitiesURL: URL
    private let analysisZoteroBindingsURL: URL
    private let fileManager: FileManager
    private let controlWriteHook: (@Sendable (URL) throws -> Void)?
    private let controlCreateHook: (@Sendable (URL) throws -> Void)?

    public init(worksVaultURL: URL, fileManager: FileManager = .default) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        self.fileManager = fileManager
        controlWriteHook = nil
        controlCreateHook = nil
    }

    init(
        worksVaultURL: URL,
        fileManager: FileManager = .default,
        controlWriteHook: @escaping @Sendable (URL) throws -> Void,
        controlCreateHook: (@Sendable (URL) throws -> Void)? = nil
    ) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        self.fileManager = fileManager
        self.controlWriteHook = controlWriteHook
        self.controlCreateHook = controlCreateHook
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
        try createEncodedFileIfMissing(
            TriptychManifest(
                id: preferredTriptychID ?? UUID(),
                vaultIDs: vaultIDs,
                createdAt: now,
                updatedAt: now
            ),
            at: manifestURL
        )
        try createEncodedFileIfMissing(TriptychSettings(), at: settingsURL)
        try createEncodedFileIfMissing(
            IdentityFile(records: []),
            at: identitiesURL
        )
        try createEncodedFileIfMissing(
            AnalysisZoteroBindingFile(bindings: []),
            at: analysisZoteroBindingsURL
        )

        let manifestData = try Data(
            contentsOf: manifestURL,
            options: [.mappedIfSafe]
        )
        guard var manifest = try? decoder().decode(
            TriptychManifest.self,
            from: manifestData
        ) else {
            throw TriptychControlError.invalidManifest
        }
        if manifest.vaultIDs != vaultIDs {
            manifest.vaultIDs = vaultIDs
            manifest.updatedAt = now
            let candidate = try encodedData(manifest)
            let readback = try replaceExactFile(
                at: manifestURL,
                expected: manifestData,
                candidate: candidate,
                conflict: TriptychControlError.invalidManifest
            )
            guard readback == candidate,
                  let decoded = try? decoder().decode(
                      TriptychManifest.self,
                      from: readback
                  ), decoded.vaultIDs == vaultIDs else {
                throw TriptychControlError.invalidManifest
            }
            manifest = decoded
        }
        _ = try settings()
        _ = try identitySnapshot()
        _ = try zoteroBindings()
        return manifest
    }

    public func manifest() throws -> TriptychManifest {
        guard let manifest: TriptychManifest = try decodeIfPresent(TriptychManifest.self, from: manifestURL) else {
            throw TriptychControlError.invalidManifest
        }
        return manifest
    }

    public func settings() throws -> TriptychSettingsSnapshot {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw TriptychControlError.settingsMissing
        }
        let data = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
        let settings = try decodeValidatedSettings(data)
        return TriptychSettingsSnapshot(
            settings: settings,
            revision: SettingsRevision(fingerprint: DocumentFingerprint(data: data))
        )
    }

    @discardableResult
    public func saveSettings(
        _ settings: TriptychSettings,
        expectedRevision: SettingsRevision
    ) throws -> TriptychSettingsSnapshot {
        do {
            try TriptychSettingsValidator.validate(settings)
        } catch {
            throw TriptychControlError.settingsNeedsReview(error.localizedDescription)
        }
        try ensureControlDirectory()
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw TriptychControlError.settingsMissing
        }
        let current = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
        guard DocumentFingerprint(data: current) == expectedRevision.fingerprint else {
            throw TriptychControlError.settingsRevisionConflict
        }
        let candidate = try encodedData(settings)
        let readback = try replaceExactFile(
            at: settingsURL,
            expected: current,
            candidate: candidate,
            conflict: TriptychControlError.settingsRevisionConflict
        )
        guard readback == candidate,
              let decoded = try? decodeValidatedSettings(readback),
              decoded == settings else {
            throw TriptychControlError.settingsCorrupted
        }
        return TriptychSettingsSnapshot(
            settings: decoded,
            revision: SettingsRevision(fingerprint: DocumentFingerprint(data: readback))
        )
    }

    public func zoteroBindings() throws -> AnalysisZoteroBindingsSnapshot {
        guard fileManager.fileExists(atPath: analysisZoteroBindingsURL.path) else {
            throw TriptychControlError.invalidZoteroBindings
        }
        let data = try Data(contentsOf: analysisZoteroBindingsURL, options: [.mappedIfSafe])
        guard let payload = try? decoder().decode(AnalysisZoteroBindingFile.self, from: data) else {
            throw TriptychControlError.invalidZoteroBindings
        }
        return AnalysisZoteroBindingsSnapshot(
            bindings: payload.bindings,
            revision: DocumentFingerprint(data: data)
        )
    }

    @discardableResult
    public func setZoteroBinding(
        _ binding: AnalysisZoteroBinding,
        expectedRevision: DocumentFingerprint
    ) throws -> AnalysisZoteroBindingsSnapshot {
        try updateZoteroBindings(expectedRevision: expectedRevision) { bindings in
            bindings.removeAll { $0.noteID == binding.noteID }
            bindings.append(binding)
        }
    }

    @discardableResult
    public func clearZoteroBinding(
        for noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) throws -> AnalysisZoteroBindingsSnapshot {
        try updateZoteroBindings(expectedRevision: expectedRevision) { bindings in
            bindings.removeAll { $0.noteID == noteID }
        }
    }

    public func identity(
        forVaultID vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createIfMissing: Bool = true
    ) throws -> NoteIdentityRecord? {
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
        let expectedRecordID: UUID
        if let index = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) {
            guard payload.records[index].fingerprint != fingerprint else {
                return payload.records[index]
            }
            payload.records[index].fingerprint = fingerprint
            payload.records[index].updatedAt = Date()
            expectedRecordID = payload.records[index].id
        } else {
            guard createIfMissing else { return nil }
            let record = NoteIdentityRecord(
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: fingerprint
            )
            expectedRecordID = record.id
            payload.records.append(record)
        }
        try ensureControlDirectory()
        try commitIdentityPayload(payload, replacing: &snapshot)
        guard let record = snapshot.payload.records.first(where: {
                  $0.id == expectedRecordID
                      && $0.vaultID == vaultID
                      && $0.relativePath == relativePath
                      && $0.fingerprint == fingerprint
              }) else {
            throw TriptychControlError.invalidIdentities
        }
        return record
    }

    private static func hasUniqueIdentityRecords(
        _ records: [NoteIdentityRecord]
    ) -> Bool {
        Set(records.map(\.id)).count == records.count
            && Set(records.map {
                "\($0.vaultID.uuidString.lowercased())\u{0}\($0.relativePath)"
            }).count == records.count
    }

    public func identityRecord(vaultID: UUID, relativePath: String) throws -> NoteIdentityRecord? {
        try identityPayload().records.first {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }
    }

    /// Resolves the current controlled location of one stable Note identity.
    /// Callers must still revalidate the current source revision before a
    /// consequential operation.
    public func identityRecord(id: UUID) throws -> NoteIdentityRecord? {
        try identityPayload().records.first { $0.id == id }
    }

    public func moveIdentity(
        id: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
        return snapshot.payload.records[index]
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload

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
                try commitIdentityPayload(payload, replacing: &snapshot)
                return snapshot.payload.records[byDestination]
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
            try commitIdentityPayload(payload, replacing: &snapshot)
            return snapshot.payload.records[byDestination]
        } else {
            let recovered = NoteIdentityRecord(
                id: id,
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: fingerprint
            )
            payload.records.append(recovered)
            try commitIdentityPayload(payload, replacing: &snapshot)
            guard let committed = snapshot.payload.records.first(where: {
                $0.id == recovered.id
            }) else {
                throw TriptychControlError.invalidIdentities
            }
            return committed
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
        let movedID = payload.records[index].id
        try commitIdentityPayload(payload, replacing: &snapshot)
        guard let moved = snapshot.payload.records.first(where: { $0.id == movedID }) else {
            throw TriptychControlError.invalidIdentities
        }
        return moved
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

        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
        let updatedIDs = Set(updated.map(\.id))
        return snapshot.payload.records
            .filter { updatedIDs.contains($0.id) }
            .sorted { $0.relativePath < $1.relativePath }
    }

    public func duplicateIdentity(
        from sourceID: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        var snapshot = try identitySnapshot()
        let source = snapshot.payload.records.first(where: { $0.id == sourceID })
        guard let source else { throw CocoaError(.fileNoSuchFile) }
        var payload = snapshot.payload
        let duplicate = NoteIdentityRecord(
            vaultID: source.vaultID,
            relativePath: relativePath,
            fingerprint: fingerprint,
            duplicatedFrom: sourceID
        )
        payload.records.append(duplicate)
        try commitIdentityPayload(payload, replacing: &snapshot)
        if let sourceBinding = try zoteroBindings().binding(for: sourceID) {
            do {
                let duplicateBinding = try AnalysisZoteroBinding(
                    noteID: duplicate.id,
                    library: sourceBinding.library,
                    itemKey: sourceBinding.itemKey
                )
                let bindingSnapshot = try zoteroBindings()
                _ = try setZoteroBinding(
                    duplicateBinding,
                    expectedRevision: bindingSnapshot.revision
                )
            } catch {
                var rollbackPayload = snapshot.payload
                rollbackPayload.records.removeAll { $0.id == duplicate.id }
                try? commitIdentityPayload(
                    rollbackPayload,
                    replacing: &snapshot
                )
                throw error
            }
        }
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
        let bindingSnapshot = try zoteroBindings()
        if bindingSnapshot.binding(for: id) != nil {
            _ = try clearZoteroBinding(
                for: id,
                expectedRevision: bindingSnapshot.revision
            )
        }
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
            zoteroBinding: try zoteroBindings().binding(for: id),
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
        if let binding = backup.zoteroBinding {
            let snapshot = try zoteroBindings()
            if let existing = snapshot.binding(for: backup.record.id) {
                guard existing == binding else {
                    throw TriptychControlError.invalidZoteroBindings
                }
            } else {
                _ = try setZoteroBinding(binding, expectedRevision: snapshot.revision)
            }
        }
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
            try commitIdentityPayload(payload, replacing: &snapshot)
            payload = snapshot.payload
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
        guard let committed = snapshot.payload.records.first(where: {
            $0.id == record.id
        }) else {
            throw TriptychControlError.invalidIdentities
        }
        return committed
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
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
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
        try commitIdentityPayload(payload, replacing: &snapshot)
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
        try identitySnapshot().payload
    }

    private func identitySnapshot() throws -> IdentityFileSnapshot {
        guard fileManager.fileExists(atPath: identitiesURL.path) else {
            throw TriptychControlError.invalidIdentities
        }
        let data = try Data(contentsOf: identitiesURL, options: [.mappedIfSafe])
        guard let payload = try? decoder().decode(IdentityFile.self, from: data),
              Self.hasUniqueIdentityRecords(payload.records) else {
            throw TriptychControlError.invalidIdentities
        }
        return IdentityFileSnapshot(payload: payload, data: data)
    }

    private func commitIdentityPayload(
        _ payload: IdentityFile,
        replacing snapshot: inout IdentityFileSnapshot
    ) throws {
        let candidate = try encodedData(payload)
        let readback = try replaceExactFile(
            at: identitiesURL,
            expected: snapshot.data,
            candidate: candidate,
            conflict: TriptychControlError.identitiesRevisionConflict
        )
        guard readback == candidate,
              let decoded = try? decoder().decode(IdentityFile.self, from: readback),
              Self.hasUniqueIdentityRecords(decoded.records) else {
            throw TriptychControlError.invalidIdentities
        }
        snapshot = IdentityFileSnapshot(payload: decoded, data: readback)
    }

    private func ensureControlDirectory() throws {
        try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decoder().decode(type, from: Data(contentsOf: url))
    }

    private func createEncodedFileIfMissing<T: Encodable>(
        _ value: T,
        at url: URL
    ) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        let candidate = try encodedData(value)
        try controlCreateHook?(url)
        do {
            try candidate.write(to: url, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Another process won the no-replace claim. Its bytes are the
            // portable authority and are validated by the caller.
        }
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encodedData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decodeValidatedSettings(_ data: Data) throws -> TriptychSettings {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any] else {
            throw TriptychControlError.settingsCorrupted
        }
        guard let rawVersion = envelope["schemaVersion"] else {
            throw TriptychControlError.settingsOldSchema(nil)
        }
        guard let number = rawVersion as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw TriptychControlError.settingsCorrupted
        }
        let version = number.intValue
        guard version >= TriptychSettings.currentSchemaVersion else {
            throw TriptychControlError.settingsOldSchema(version)
        }
        guard version <= TriptychSettings.currentSchemaVersion else {
            throw TriptychControlError.settingsFutureSchema(version)
        }
        let settings: TriptychSettings
        do {
            settings = try decoder().decode(TriptychSettings.self, from: data)
        } catch {
            throw TriptychControlError.settingsCorrupted
        }
        do {
            try TriptychSettingsValidator.validate(settings)
        } catch {
            throw TriptychControlError.settingsNeedsReview(error.localizedDescription)
        }
        return settings
    }

    /// Replaces a portable control file only if the exact authorized preimage
    /// is still the atomically displaced file. NSFileCoordinator covers
    /// participating sync providers; the swap/readback proof detects an
    /// uncoordinated writer in the final-check window and restores its bytes.
    private func replaceExactFile(
        at url: URL,
        expected: Data,
        candidate: Data,
        conflict: @autoclosure () -> Error
    ) throws -> Data {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var outcome: Result<Data, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            outcome = Result {
                let initial = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                guard initial == expected else { throw conflict() }

                let stagingURL = coordinatedURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".\(coordinatedURL.lastPathComponent)-staging-\(UUID().uuidString.lowercased())"
                    )
                var stagingExists = false
                defer {
                    if stagingExists { try? self.fileManager.removeItem(at: stagingURL) }
                }
                try candidate.write(to: stagingURL, options: .withoutOverwriting)
                stagingExists = true
                let stagingDescriptor = Darwin.open(stagingURL.path, O_RDONLY | O_NOFOLLOW)
                guard stagingDescriptor >= 0 else { throw POSIXError(.EIO) }
                defer { Darwin.close(stagingDescriptor) }
                var stagingStatus = stat()
                guard fstat(stagingDescriptor, &stagingStatus) == 0,
                      (stagingStatus.st_mode & S_IFMT) == S_IFREG,
                      stagingStatus.st_nlink == 1,
                      fsync(stagingDescriptor) == 0 else {
                    throw POSIXError(.EIO)
                }

                let rechecked = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                guard rechecked == expected else { throw conflict() }
                try self.controlWriteHook?(coordinatedURL)

                guard renameatx_np(
                    AT_FDCWD,
                    stagingURL.path,
                    AT_FDCWD,
                    coordinatedURL.path,
                    UInt32(RENAME_SWAP)
                ) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }

                let canonical = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                let displaced = try Data(contentsOf: stagingURL, options: [.mappedIfSafe])
                guard canonical == candidate, displaced == expected else {
                    if canonical == candidate {
                        _ = renameatx_np(
                            AT_FDCWD,
                            stagingURL.path,
                            AT_FDCWD,
                            coordinatedURL.path,
                            UInt32(RENAME_SWAP)
                        )
                    }
                    throw conflict()
                }
                try self.fileManager.removeItem(at: stagingURL)
                stagingExists = false
                let directoryDescriptor = Darwin.open(
                    coordinatedURL.deletingLastPathComponent().path,
                    O_RDONLY | O_DIRECTORY
                )
                if directoryDescriptor >= 0 {
                    defer { Darwin.close(directoryDescriptor) }
                    guard fsync(directoryDescriptor) == 0 else { throw POSIXError(.EIO) }
                }
                let readback = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                guard readback == candidate else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return readback
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }

    private func updateZoteroBindings(
        expectedRevision: DocumentFingerprint,
        change: (inout [AnalysisZoteroBinding]) -> Void
    ) throws -> AnalysisZoteroBindingsSnapshot {
        let snapshot = try zoteroBindings()
        guard snapshot.revision == expectedRevision else {
            throw TriptychControlError.zoteroBindingsRevisionConflict
        }
        var bindings = snapshot.bindings
        change(&bindings)
        let payload = AnalysisZoteroBindingFile(bindings: bindings)
        let candidate = try encodedData(payload)
        let current = try Data(
            contentsOf: analysisZoteroBindingsURL,
            options: [.mappedIfSafe]
        )
        guard DocumentFingerprint(data: current) == expectedRevision else {
            throw TriptychControlError.zoteroBindingsRevisionConflict
        }
        let readback = try replaceExactFile(
            at: analysisZoteroBindingsURL,
            expected: current,
            candidate: candidate,
            conflict: TriptychControlError.zoteroBindingsRevisionConflict
        )
        guard readback == candidate,
              let decoded = try? decoder().decode(AnalysisZoteroBindingFile.self, from: readback) else {
            throw TriptychControlError.invalidZoteroBindings
        }
        return AnalysisZoteroBindingsSnapshot(
            bindings: decoded.bindings,
            revision: DocumentFingerprint(data: readback)
        )
    }

    private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
