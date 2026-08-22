import CryptoKit
import Darwin
import Foundation
import ScholiumContracts

public struct ManagedCreationIdentityReconciliation: Hashable, Sendable {
    public let identity: NoteIdentityRecord?
    public let previousReservedIdentity: NoteIdentityRecord?

    init(
        identity: NoteIdentityRecord?,
        previousReservedIdentity: NoteIdentityRecord?
    ) {
        self.identity = identity
        self.previousReservedIdentity = previousReservedIdentity
    }
}

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

    /// Preserves the entire unsupported portable-control owner as one opaque
    /// directory. No file inside it is decoded or migrated, and the three
    /// research vault roots are outside the moved range.
    @discardableResult
    public nonisolated static func preserveUnsupportedControlBundle(
        worksVaultURL: URL,
        fileManager: FileManager = .default
    ) async throws -> URL {
        let controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        guard try await unsupportedControlStateExists(
            worksVaultURL: worksVaultURL
        ) else {
            throw ExactStatePreservationError.preservationFailed(
                "The portable control folder changed and no longer requires recovery. Reload its current state."
            )
        }
        let expectedToken = try recoveryToken(
            controlURL: controlURL,
            fileManager: fileManager
        )
        guard try await unsupportedControlStateExists(
            worksVaultURL: worksVaultURL
        ) else {
            throw ExactStatePreservationError.preservationFailed(
                "The portable control folder changed and no longer requires recovery. Reload its current state."
            )
        }
        return try ExactStatePreserver.preserve(
            controlURL,
            kind: .directory,
            recoveryStem: ".scholium.unsupported",
            directoryEligibility: {
                try recoveryToken(controlURL: $0, fileManager: fileManager)
                    == expectedToken
            },
            fileManager: fileManager
        )
    }

    private nonisolated static func unsupportedControlStateExists(
        worksVaultURL: URL
    ) async throws -> Bool {
        let store = TriptychControlStore(worksVaultURL: worksVaultURL)
        let controlURL = store.controlURL
        guard ExactStatePreserver.entryExists(at: controlURL) else { return false }
        let values = try controlURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ExactStatePreservationError.unsafe(
                "The portable control owner is linked or is not a directory."
            )
        }
        let manifest: TriptychManifest
        do {
            manifest = try await store.manifest()
        } catch let error as TriptychControlError {
            if case .invalidManifest = error { return true }
            throw error
        }
        guard manifest.schemaVersion == TriptychManifest.currentSchemaVersion,
              Set(manifest.vaultIDs.keys) == Set(WorkspaceVaultSlot.allCases),
              Set(manifest.vaultIDs.values).count == WorkspaceVaultSlot.allCases.count else {
            return true
        }
        do {
            try await store.validateExistingSupportedControlState()
            let researchConfiguration = ResearchConfigurationStore(
                controlURL: controlURL,
                triptychID: manifest.id
            )
            _ = try await researchConfiguration.registrationSnapshot()
            _ = try await researchConfiguration.profileSnapshot()
            _ = try await researchConfiguration.collaborationSnapshot()
            _ = try await researchConfiguration.citationMethodSnapshot()
            return false
        } catch is ResearchCitationMethodContractError {
            return true
        } catch let error as ResearchConfigurationStoreError {
            if case .invalidDocument = error { return true }
            throw error
        } catch let error as TriptychControlError {
            switch error {
            case .invalidManifest, .settingsMissing, .settingsOldSchema,
                 .settingsFutureSchema, .settingsCorrupted,
                 .invalidZoteroBindings, .invalidIdentities:
                return true
            default:
                throw error
            }
        } catch is NoteMetadataError {
            return true
        }
    }

    private nonisolated static func recoveryToken(
        controlURL: URL,
        fileManager: FileManager
    ) throws -> DocumentFingerprint {
        let root = controlURL.standardizedFileURL
        var enumerationFailure: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ],
            options: [],
            errorHandler: { _, error in
                enumerationFailure = error
                return false
            }
        ) else {
            throw ExactStatePreservationError.unsafe(
                "The portable control directory could not be enumerated for recovery."
            )
        }
        let entries = enumerator.compactMap { $0 as? URL }.sorted {
            $0.path < $1.path
        }
        if let enumerationFailure {
            throw ExactStatePreservationError.unsafe(
                "The portable control directory could not be read completely: \(enumerationFailure.localizedDescription)"
            )
        }
        var token = Data()
        for url in entries {
            let rootParts = root.pathComponents
            let parts = url.standardizedFileURL.pathComponents
            guard parts.count > rootParts.count,
                  Array(parts.prefix(rootParts.count)) == rootParts else {
                throw ExactStatePreservationError.unsafe(
                    "Portable control recovery escaped its authorized directory."
                )
            }
            let relativePath = parts.dropFirst(rootParts.count).joined(separator: "/")
            token.append(Data(relativePath.utf8))
            token.append(0)
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            if values.isSymbolicLink == true {
                token.append(2)
                token.append(Data(try fileManager.destinationOfSymbolicLink(
                    atPath: url.path
                ).utf8))
            } else if values.isDirectory == true {
                token.append(3)
            } else if values.isRegularFile == true {
                token.append(1)
                token.append(try Data(contentsOf: url, options: [.mappedIfSafe]))
            } else {
                throw ExactStatePreservationError.unsafe(
                    "Portable control state at \(url.path) has an unsupported type."
                )
            }
            token.append(0xff)
        }
        return DocumentFingerprint(data: token)
    }

    private let manifestURL: URL
    private let settingsURL: URL
    private let identitiesURL: URL
    private let analysisZoteroBindingsURL: URL
    private let attachmentCatalogURL: URL
    private let noteMetadataCatalogURL: URL
    private let fileManager: FileManager
    private let controlWriteHook: (@Sendable (URL) throws -> Void)?
    private let controlPostSwapHook: (@Sendable (URL) throws -> Void)?
    private let controlCreateHook: (@Sendable (URL) throws -> Void)?
    private let portableControlLock: AdvisoryFileLock?

    public init(worksVaultURL: URL, fileManager: FileManager = .default) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        attachmentCatalogURL = controlURL
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        noteMetadataCatalogURL = controlURL
            .appendingPathComponent("note-metadata", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        self.fileManager = fileManager
        controlWriteHook = nil
        controlPostSwapHook = nil
        controlCreateHook = nil
        portableControlLock = nil
    }

    public init(
        worksVaultURL: URL,
        coordinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        attachmentCatalogURL = controlURL
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        noteMetadataCatalogURL = controlURL
            .appendingPathComponent("note-metadata", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        self.fileManager = fileManager
        controlWriteHook = nil
        controlPostSwapHook = nil
        controlCreateHook = nil
        let standardizedCoordinationURL = coordinationURL.standardizedFileURL
        try fileManager.createDirectory(
            at: standardizedCoordinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let coordinationDirectory = SecureRecordDirectory(
            trustedRootURL: standardizedCoordinationURL.deletingLastPathComponent(),
            components: [standardizedCoordinationURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        try coordinationDirectory.ensureDirectories([])
        portableControlLock = try AdvisoryFileLock(
            directory: coordinationDirectory,
            fileName: "portable-control.lock"
        )
    }

    init(
        worksVaultURL: URL,
        fileManager: FileManager = .default,
        controlWriteHook: @escaping @Sendable (URL) throws -> Void,
        controlCreateHook: (@Sendable (URL) throws -> Void)? = nil,
        controlPostSwapHook: (@Sendable (URL) throws -> Void)? = nil
    ) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        attachmentCatalogURL = controlURL
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        noteMetadataCatalogURL = controlURL
            .appendingPathComponent("note-metadata", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        self.fileManager = fileManager
        self.controlWriteHook = controlWriteHook
        self.controlPostSwapHook = controlPostSwapHook
        self.controlCreateHook = controlCreateHook
        portableControlLock = nil
    }

    init(
        worksVaultURL: URL,
        coordinationURL: URL,
        fileManager: FileManager = .default,
        controlWriteHook: @escaping @Sendable (URL) throws -> Void
    ) throws {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        analysisZoteroBindingsURL = controlURL.appendingPathComponent("analysis-zotero-bindings.json")
        attachmentCatalogURL = controlURL
            .appendingPathComponent("attachments", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        noteMetadataCatalogURL = controlURL
            .appendingPathComponent("note-metadata", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        self.fileManager = fileManager
        self.controlWriteHook = controlWriteHook
        controlPostSwapHook = nil
        controlCreateHook = nil
        let standardizedCoordinationURL = coordinationURL.standardizedFileURL
        try fileManager.createDirectory(
            at: standardizedCoordinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let coordinationDirectory = SecureRecordDirectory(
            trustedRootURL: standardizedCoordinationURL.deletingLastPathComponent(),
            components: [standardizedCoordinationURL.lastPathComponent],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        try coordinationDirectory.ensureDirectories([])
        portableControlLock = try AdvisoryFileLock(
            directory: coordinationDirectory,
            fileName: "portable-control.lock"
        )
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
        try ensureAttachmentCatalogDirectory()
        try ensureNoteMetadataCatalogDirectory()

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
        switch try settingsLoadState() {
        case .current, .needsReview:
            break
        case .missing:
            throw TriptychControlError.settingsMissing
        case .oldSchema(let version):
            throw TriptychControlError.settingsOldSchema(version)
        case .futureSchema(let version):
            throw TriptychControlError.settingsFutureSchema(version)
        case .corrupted:
            throw TriptychControlError.settingsCorrupted
        }
        _ = try identitySnapshot()
        _ = try zoteroBindings()
        _ = try noteMetadataRecords()
        return manifest
    }

    public func manifest() throws -> TriptychManifest {
        do {
            guard let manifest: TriptychManifest = try decodeIfPresent(
                TriptychManifest.self,
                from: manifestURL
            ) else {
                throw TriptychControlError.invalidManifest
            }
            return manifest
        } catch is DecodingError {
            throw TriptychControlError.invalidManifest
        }
    }

    /// Validates only portable control files that already exist. Missing
    /// current files remain bootstrap-able; unsupported or damaged existing
    /// files fail before any machine-local registration is changed.
    public func validateExistingSupportedControlState() throws {
        if fileManager.fileExists(atPath: settingsURL.path) {
            switch try settingsLoadState() {
            case .current, .needsReview, .missing:
                break
            case .oldSchema(let version):
                throw TriptychControlError.settingsOldSchema(version)
            case .futureSchema(let version):
                throw TriptychControlError.settingsFutureSchema(version)
            case .corrupted:
                throw TriptychControlError.settingsCorrupted
            }
        }
        if fileManager.fileExists(atPath: identitiesURL.path) {
            _ = try identitySnapshot()
        }
        if fileManager.fileExists(atPath: analysisZoteroBindingsURL.path) {
            _ = try zoteroBindings()
        }
        if fileManager.fileExists(atPath: noteMetadataCatalogURL.path) {
            _ = try noteMetadataRecords()
        }
    }

    public func settings() throws -> TriptychSettingsSnapshot {
        switch try settingsLoadState() {
        case .current(let snapshot):
            return snapshot
        case .needsReview(_, _, let reason):
            throw TriptychControlError.settingsNeedsReview(reason)
        case .missing:
            throw TriptychControlError.settingsMissing
        case .oldSchema(let version):
            throw TriptychControlError.settingsOldSchema(version)
        case .futureSchema(let version):
            throw TriptychControlError.settingsFutureSchema(version)
        case .corrupted:
            throw TriptychControlError.settingsCorrupted
        }
    }

    public func settingsLoadState() throws -> TriptychSettingsLoadState {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return .missing
        }
        let data = try Data(contentsOf: settingsURL, options: [.mappedIfSafe])
        return decodeSettingsLoadState(data)
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

    public func attachmentRecords() throws -> [PortableAttachmentRecord] {
        guard fileManager.fileExists(atPath: attachmentCatalogURL.path) else {
            return []
        }
        try validateAttachmentCatalogDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: attachmentCatalogURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        var records: [PortableAttachmentRecord] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let record = try? decoder().decode(
                    PortableAttachmentRecord.self,
                    from: Data(contentsOf: url, options: [.mappedIfSafe])
                  ),
                  url.deletingPathExtension().lastPathComponent
                    == record.id.uuidString.lowercased() else {
                throw ImageAttachmentError.invalidCatalog
            }
            records.append(record)
        }
        guard Set(records.map(\.id)).count == records.count,
              Set(records.map { "\($0.vaultID.uuidString):\($0.location)" })
                .count == records.count else {
            throw ImageAttachmentError.invalidCatalog
        }
        return records.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    public func registerAttachment(
        vaultID: UUID,
        location: AttachmentLocation,
        preferredID: UUID = UUID()
    ) throws -> (record: PortableAttachmentRecord, created: Bool) {
        try withPortableControlLock {
            try ensureAttachmentCatalogDirectory()
            if let existing = try attachmentRecords().first(where: {
                $0.vaultID == vaultID && $0.location == location
            }) {
                return (existing, false)
            }
            let record = PortableAttachmentRecord(
                id: preferredID,
                vaultID: vaultID,
                location: location
            )
            let url = attachmentRecordURL(id: record.id)
            guard !fileManager.fileExists(atPath: url.path) else {
                throw ImageAttachmentError.catalogConflict
            }
            let candidate = try encodedData(record)
            try controlCreateHook?(url)
            do {
                try candidate.write(to: url, options: .withoutOverwriting)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                throw ImageAttachmentError.catalogConflict
            } catch {
                if let current = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    if current == candidate { return (record, true) }
                    throw ImageAttachmentError.catalogCommitUncertain(
                        error.localizedDescription
                    )
                }
                throw error
            }
            let readback: Data
            do {
                readback = try Data(contentsOf: url, options: [.mappedIfSafe])
            } catch {
                throw ImageAttachmentError.catalogCommitUncertain(
                    error.localizedDescription
                )
            }
            guard readback == candidate,
                  (try? decoder().decode(PortableAttachmentRecord.self, from: readback))
                    == record else {
                throw ImageAttachmentError.catalogCommitUncertain(
                    "The record readback did not match the exact candidate bytes."
                )
            }
            return (record, true)
        }
    }

    public func removeAttachment(_ expected: PortableAttachmentRecord) throws {
        try withPortableControlLock {
            let url = attachmentRecordURL(id: expected.id)
            guard fileManager.fileExists(atPath: url.path) else { return }
            let expectedData = try encodedData(expected)
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var outcome: Result<Void, Error>?
            coordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                outcome = Result {
                    let current = try Data(
                        contentsOf: coordinatedURL,
                        options: [.mappedIfSafe]
                    )
                    guard current == expectedData else {
                        throw ImageAttachmentError.catalogConflict
                    }
                    try self.fileManager.removeItem(at: coordinatedURL)
                    guard !self.fileManager.fileExists(atPath: coordinatedURL.path) else {
                        throw ImageAttachmentError.catalogConflict
                    }
                }
            }
            if let coordinationError { throw coordinationError }
            guard let outcome else { throw ImageAttachmentError.catalogConflict }
            try outcome.get()
        }
    }

    /// Reads every portable Note metadata file as an immutable snapshot. A
    /// damaged or unexpectedly named record invalidates the complete catalog;
    /// callers must never publish a silently incomplete metadata projection.
    public func noteMetadataRecords() throws -> [NoteMetadataSnapshot] {
        guard fileManager.fileExists(atPath: noteMetadataCatalogURL.path) else {
            return []
        }
        try validateNoteMetadataCatalogDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: noteMetadataCatalogURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        let identities = Dictionary(
            uniqueKeysWithValues: try identityPayload().records.map { ($0.id, $0) }
        )
        let profilesByVaultID = try noteMetadataProfilesByVaultID()
        var snapshots: [NoteMetadataSnapshot] = []
        for url in urls {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw NoteMetadataError.invalidCatalog
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard let record = try? decoder().decode(
                NoteMetadataRecord.self,
                from: data
            ), url.deletingPathExtension().lastPathComponent
                == record.noteID.uuidString.lowercased() else {
                throw NoteMetadataError.invalidCatalog
            }
            try validateNoteMetadataRecord(
                record,
                identities: identities,
                profilesByVaultID: profilesByVaultID
            )
            snapshots.append(NoteMetadataSnapshot(
                record: record,
                revision: DocumentFingerprint(data: data)
            ))
        }
        guard Set(snapshots.map(\.record.noteID)).count == snapshots.count else {
            throw NoteMetadataError.invalidCatalog
        }
        return snapshots.sorted {
            $0.record.noteID.uuidString < $1.record.noteID.uuidString
        }
    }

    public func noteMetadata(noteID: UUID) throws -> NoteMetadataSnapshot? {
        let url = noteMetadataRecordURL(noteID: noteID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        try validateNoteMetadataCatalogDirectory()
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NoteMetadataError.invalidRecord(noteID)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let record = try? decoder().decode(NoteMetadataRecord.self, from: data),
              record.noteID == noteID else {
            throw NoteMetadataError.invalidRecord(noteID)
        }
        let identities = Dictionary(
            uniqueKeysWithValues: try identityPayload().records.map { ($0.id, $0) }
        )
        try validateNoteMetadataRecord(
            record,
            identities: identities,
            profilesByVaultID: try noteMetadataProfilesByVaultID()
        )
        return NoteMetadataSnapshot(
            record: record,
            revision: DocumentFingerprint(data: data)
        )
    }

    /// Creates or compare-and-swap replaces one metadata record. `nil`
    /// expected revision authorizes only creation; it never overwrites a
    /// record that appeared concurrently through another Scholium instance or
    /// a sync participant.
    @discardableResult
    public func saveNoteMetadata(
        noteID: UUID,
        fields: [String: YAMLValue],
        expectedRevision: DocumentFingerprint?
    ) throws -> NoteMetadataSnapshot {
        try withPortableControlLock {
            guard let identity = try identityRecord(id: noteID) else {
                throw NoteMetadataError.identityUnavailable(noteID)
            }
            let profilesByVaultID = try noteMetadataProfilesByVaultID()
            guard let profile = profilesByVaultID[identity.vaultID],
                  NoteMetadataContractCatalog.validate(
                    fields: fields,
                    profile: profile
                  ).isEmpty else {
                throw NoteMetadataError.invalidRecord(noteID)
            }
            try ensureNoteMetadataCatalogDirectory()
            let record = NoteMetadataRecord(noteID: noteID, fields: fields)
            let candidate = try record.encodedPortableData()
            let url = noteMetadataRecordURL(noteID: noteID)
            let readback: Data
            if fileManager.fileExists(atPath: url.path) {
                let current = try Data(contentsOf: url, options: [.mappedIfSafe])
                guard let expectedRevision,
                      DocumentFingerprint(data: current) == expectedRevision else {
                    throw NoteMetadataError.revisionConflict(noteID)
                }
                do {
                    readback = try replaceExactFile(
                        at: url,
                        expected: current,
                        candidate: candidate,
                        conflict: NoteMetadataError.revisionConflict(noteID)
                    )
                } catch let error as TriptychControlError {
                    if case .controlFileCommitUncertain(let reason) = error {
                        throw NoteMetadataError.commitUncertain(noteID, reason)
                    }
                    throw error
                }
            } else {
                guard expectedRevision == nil else {
                    throw NoteMetadataError.revisionConflict(noteID)
                }
                try controlCreateHook?(url)
                do {
                    try candidate.write(to: url, options: .withoutOverwriting)
                } catch let error as CocoaError where error.code == .fileWriteFileExists {
                    throw NoteMetadataError.revisionConflict(noteID)
                } catch {
                    if let current = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                       current == candidate {
                        readback = current
                    } else if fileManager.fileExists(atPath: url.path) {
                        throw NoteMetadataError.commitUncertain(
                            noteID,
                            error.localizedDescription
                        )
                    } else {
                        throw error
                    }
                    guard let decoded = try? decoder().decode(
                        NoteMetadataRecord.self,
                        from: readback
                    ), decoded == record else {
                        throw NoteMetadataError.commitUncertain(
                            noteID,
                            "The record readback did not match the candidate."
                        )
                    }
                    return NoteMetadataSnapshot(
                        record: decoded,
                        revision: DocumentFingerprint(data: readback)
                    )
                }
                do {
                    readback = try Data(contentsOf: url, options: [.mappedIfSafe])
                } catch {
                    throw NoteMetadataError.commitUncertain(
                        noteID,
                        error.localizedDescription
                    )
                }
            }
            guard readback == candidate,
                  let decoded = try? decoder().decode(
                    NoteMetadataRecord.self,
                    from: readback
                  ), decoded == record else {
                throw NoteMetadataError.commitUncertain(
                    noteID,
                    "The record readback did not match the exact candidate bytes."
                )
            }
            return NoteMetadataSnapshot(
                record: decoded,
                revision: DocumentFingerprint(data: readback)
            )
        }
    }

    /// Removes only the exact loaded metadata revision. This is used by
    /// bounded creation rollback and permanent deletion; ordinary field edits
    /// retain an empty record instead of turning absence into an ambiguous
    /// write state.
    public func removeNoteMetadata(_ expected: NoteMetadataSnapshot) throws {
        try withPortableControlLock {
            let id = expected.record.noteID
            let url = noteMetadataRecordURL(noteID: id)
            guard fileManager.fileExists(atPath: url.path) else { return }
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var outcome: Result<Void, Error>?
            coordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                outcome = Result {
                    let current = try Data(
                        contentsOf: coordinatedURL,
                        options: [.mappedIfSafe]
                    )
                    guard DocumentFingerprint(data: current) == expected.revision else {
                        throw NoteMetadataError.revisionConflict(id)
                    }
                    try self.fileManager.removeItem(at: coordinatedURL)
                    guard !self.fileManager.fileExists(atPath: coordinatedURL.path) else {
                        throw NoteMetadataError.commitUncertain(
                            id,
                            "The record still exists after deletion."
                        )
                    }
                }
            }
            if let coordinationError { throw coordinationError }
            guard let outcome else {
                throw NoteMetadataError.commitUncertain(
                    id,
                    "The coordinated deletion produced no result."
                )
            }
            try outcome.get()
        }
    }

    @discardableResult
    public func setZoteroBinding(
        _ binding: AnalysisZoteroBinding,
        expectedRevision: DocumentFingerprint
    ) throws -> AnalysisZoteroBindingsSnapshot {
        try withPortableControlLock {
            guard try identityRecord(id: binding.noteID) != nil else {
                throw TriptychControlError.invalidIdentityCandidate(binding.noteID)
            }
            return try updateZoteroBindings(expectedRevision: expectedRevision) { bindings in
                bindings.removeAll { $0.noteID == binding.noteID }
                bindings.append(binding)
            }
        }
    }

    @discardableResult
    public func clearZoteroBinding(
        for noteID: UUID,
        expectedRevision: DocumentFingerprint
    ) throws -> AnalysisZoteroBindingsSnapshot {
        try withPortableControlLock {
            try updateZoteroBindings(expectedRevision: expectedRevision) { bindings in
                bindings.removeAll { $0.noteID == noteID }
            }
        }
    }

    public func identity(
        forVaultID vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createIfMissing: Bool = true,
        preferredID: UUID? = nil
    ) throws -> NoteIdentityRecord? {
        var snapshot = try identitySnapshot()
        var payload = snapshot.payload
        let expectedRecordID: UUID
        if let index = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) {
            guard preferredID == nil || payload.records[index].id == preferredID else {
                throw TriptychControlError.invalidIdentities
            }
            guard payload.records[index].fingerprint != fingerprint else {
                return payload.records[index]
            }
            payload.records[index].fingerprint = fingerprint
            payload.records[index].updatedAt = Date()
            expectedRecordID = payload.records[index].id
        } else {
            guard createIfMissing else { return nil }
            let record = NoteIdentityRecord(
                id: preferredID ?? UUID(),
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

    /// Commits a path move against the portable identity inventory.
    ///
    /// The filesystem move and this identity write are separate actors, so a
    /// watcher or explicit refresh may leave the in-memory ID one step ahead
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
                // exact source path is the stronger move precondition.
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
        try withPortableControlLock {
            var snapshot = try identitySnapshot()
            var payload = snapshot.payload
            guard let record = payload.records.first(where: { $0.id == id }) else {
                return nil
            }
            guard record.vaultID == vaultID, record.relativePath == relativePath else {
                throw TriptychControlError.invalidIdentityCandidate(id)
            }
            guard try zoteroBindings().binding(for: id) == nil else {
                // Creation recovery cannot turn an uncertain observation into
                // integration-deletion authority. Permanent deletion uses its
                // durable exact preimage overload below.
                throw TriptychControlError.invalidIdentityCandidate(id)
            }
            payload.records.removeAll { $0.id == id }
            payload.pendingRebindings.removeAll { $0.noteID == id }
            payload.unresolvedAmbiguities = payload.unresolvedAmbiguities.compactMap {
                ambiguity in
                var ambiguity = ambiguity
                ambiguity.candidateIDs.removeAll { $0 == id }
                return ambiguity.candidateIDs.isEmpty ? nil : ambiguity
            }
            try commitIdentityPayload(payload, replacing: &snapshot)
            return record
        }
    }

    /// Reconciles one researcher-managed creation in a single portable-control
    /// critical section. The caller already owns the source-operation lease and
    /// supplies only an exact source-present/absent observation. Recovery may
    /// add or remove only its own reserved identity. Any other identity at the
    /// path stops reconciliation, regardless of source-byte equality.
    public func reconcileManagedCreationIdentity(
        vaultID: UUID,
        relativePath: String,
        intendedRevision: DocumentFingerprint,
        reservedIdentityID: UUID,
        sourceIsPresent: Bool
    ) throws -> ManagedCreationIdentityReconciliation {
        guard let portableControlLock else {
            throw TriptychControlError.invalidIdentityCandidate(reservedIdentityID)
        }
        return try portableControlLock.withExclusiveLock {
            var snapshot = try identitySnapshot()
            let originalPayload = snapshot.payload
            let bindingSnapshot = try zoteroBindings()
            var payload = snapshot.payload
            let pathIdentity = payload.records.first(where: {
                $0.vaultID == vaultID && $0.relativePath == relativePath
            })
            let reservedIdentity = payload.records.first(where: {
                $0.id == reservedIdentityID
            })

            if sourceIsPresent {
                if let reservedIdentity {
                    guard reservedIdentity.vaultID == vaultID,
                          reservedIdentity.relativePath == relativePath,
                          reservedIdentity.fingerprint == intendedRevision,
                          pathIdentity?.id == reservedIdentityID else {
                        throw TriptychControlError.invalidIdentityCandidate(
                            reservedIdentityID
                        )
                    }
                    return ManagedCreationIdentityReconciliation(
                        identity: reservedIdentity,
                        previousReservedIdentity: reservedIdentity
                    )
                }
                guard pathIdentity == nil,
                      bindingSnapshot.binding(for: reservedIdentityID) == nil,
                      !payload.pendingRebindings.contains(where: {
                          $0.noteID == reservedIdentityID
                      }),
                      !payload.unresolvedAmbiguities.contains(where: {
                          $0.candidateIDs.contains(reservedIdentityID)
                      }) else {
                    throw TriptychControlError.invalidIdentityCandidate(
                        pathIdentity?.id ?? reservedIdentityID
                    )
                }
                payload.records.append(NoteIdentityRecord(
                    id: reservedIdentityID,
                    vaultID: vaultID,
                    relativePath: relativePath,
                    fingerprint: intendedRevision
                ))
            } else {
                guard pathIdentity?.id == reservedIdentityID || pathIdentity == nil,
                      reservedIdentity == nil
                        || (reservedIdentity?.vaultID == vaultID
                            && reservedIdentity?.relativePath == relativePath
                            && reservedIdentity?.fingerprint == intendedRevision) else {
                    throw TriptychControlError.invalidIdentityCandidate(
                        pathIdentity?.id ?? reservedIdentityID
                    )
                }
                guard bindingSnapshot.binding(for: reservedIdentityID) == nil,
                      !payload.pendingRebindings.contains(where: {
                          $0.noteID == reservedIdentityID
                      }),
                      !payload.unresolvedAmbiguities.contains(where: {
                          $0.candidateIDs.contains(reservedIdentityID)
                      }) else {
                    throw TriptychControlError.invalidIdentityCandidate(
                        reservedIdentityID
                    )
                }
                if reservedIdentity != nil {
                    payload.records.removeAll { $0.id == reservedIdentityID }
                }
            }

            try commitIdentityPayload(payload, replacing: &snapshot)
            guard try zoteroBindings().revision == bindingSnapshot.revision else {
                try commitIdentityPayload(originalPayload, replacing: &snapshot)
                throw TriptychControlError.invalidZoteroBindings
            }
            let final = snapshot.payload.records.first(where: {
                $0.id == reservedIdentityID
            })
            if sourceIsPresent {
                guard final?.vaultID == vaultID,
                      final?.relativePath == relativePath,
                      final?.fingerprint == intendedRevision else {
                    throw TriptychControlError.invalidIdentities
                }
                return ManagedCreationIdentityReconciliation(
                    identity: final,
                    previousReservedIdentity: reservedIdentity
                )
            }
            guard final == nil else {
                throw TriptychControlError.invalidIdentities
            }
            return ManagedCreationIdentityReconciliation(
                identity: nil,
                previousReservedIdentity: reservedIdentity
            )
        }
    }

    public func rollbackManagedCreationIdentity(
        _ reconciliation: ManagedCreationIdentityReconciliation,
        vaultID: UUID,
        relativePath: String
    ) throws {
        guard let portableControlLock else {
            throw TriptychControlError.invalidIdentities
        }
        try portableControlLock.withExclusiveLock {
            var snapshot = try identitySnapshot()
            let current = snapshot.payload.records.first(where: {
                $0.vaultID == vaultID && $0.relativePath == relativePath
            })
            guard current == reconciliation.identity else {
                throw TriptychControlError.invalidIdentities
            }
            guard current != reconciliation.previousReservedIdentity else { return }
            var payload = snapshot.payload
            if let current {
                guard try zoteroBindings().binding(for: current.id) == nil else {
                    throw TriptychControlError.invalidZoteroBindings
                }
                payload.records.removeAll { $0.id == current.id }
            }
            if let previous = reconciliation.previousReservedIdentity {
                guard !payload.records.contains(where: {
                    $0.id == previous.id
                        || ($0.vaultID == vaultID
                            && $0.relativePath == relativePath)
                }) else {
                    throw TriptychControlError.invalidIdentities
                }
                payload.records.append(previous)
            }
            try commitIdentityPayload(payload, replacing: &snapshot)
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
        guard Self.hasUniqueIdentityRecords(payload.records) else {
            throw TriptychControlError.invalidIdentities
        }
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

    private func ensureAttachmentCatalogDirectory() throws {
        try ensureControlDirectory()
        try fileManager.createDirectory(
            at: attachmentCatalogURL,
            withIntermediateDirectories: true
        )
        try validateAttachmentCatalogDirectory()
    }

    private func ensureNoteMetadataCatalogDirectory() throws {
        try ensureControlDirectory()
        try fileManager.createDirectory(
            at: noteMetadataCatalogURL,
            withIntermediateDirectories: true
        )
        try validateNoteMetadataCatalogDirectory()
    }

    private func validateNoteMetadataCatalogDirectory() throws {
        let ownerURL = noteMetadataCatalogURL.deletingLastPathComponent()
        for url in [controlURL, ownerURL, noteMetadataCatalogURL] {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw NoteMetadataError.invalidCatalog
            }
        }
        let canonicalControl = controlURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCatalog = noteMetadataCatalogURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = canonicalControl.path.hasSuffix("/")
            ? canonicalControl.path
            : canonicalControl.path + "/"
        guard canonicalCatalog.path.hasPrefix(rootPath) else {
            throw NoteMetadataError.invalidCatalog
        }
    }

    private func noteMetadataRecordURL(noteID: UUID) -> URL {
        noteMetadataCatalogURL.appendingPathComponent(
            "\(noteID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func noteMetadataProfilesByVaultID() throws -> [UUID: SchemaProfileID] {
        Dictionary(uniqueKeysWithValues: try manifest().vaultIDs.map { slot, vaultID in
            let profile: SchemaProfileID = switch slot {
            case .paperAnalysis: .analysis
            case .topicKnowledge: .topicMarkdown
            case .output: .draftProject
            }
            return (vaultID, profile)
        })
    }

    private func validateNoteMetadataRecord(
        _ record: NoteMetadataRecord,
        identities: [UUID: NoteIdentityRecord],
        profilesByVaultID: [UUID: SchemaProfileID]
    ) throws {
        guard let identity = identities[record.noteID],
              let profile = profilesByVaultID[identity.vaultID],
              NoteMetadataContractCatalog.validate(
                fields: record.fields,
                profile: profile
              ).isEmpty else {
            throw NoteMetadataError.invalidRecord(record.noteID)
        }
    }

    private func validateAttachmentCatalogDirectory() throws {
        let attachmentsURL = attachmentCatalogURL.deletingLastPathComponent()
        for url in [controlURL, attachmentsURL, attachmentCatalogURL] {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw ImageAttachmentError.invalidCatalog
            }
        }
        let canonicalControl = controlURL.resolvingSymlinksInPath().standardizedFileURL
        let canonicalCatalog = attachmentCatalogURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let rootPath = canonicalControl.path.hasSuffix("/")
            ? canonicalControl.path
            : canonicalControl.path + "/"
        guard canonicalCatalog.path.hasPrefix(rootPath) else {
            throw ImageAttachmentError.invalidCatalog
        }
    }

    private func attachmentRecordURL(id: UUID) -> URL {
        attachmentCatalogURL.appendingPathComponent(
            "\(id.uuidString.lowercased()).json",
            isDirectory: false
        )
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
        switch decodeSettingsLoadState(data) {
        case .current(let snapshot): return snapshot.settings
        case .needsReview(_, _, let reason):
            throw TriptychControlError.settingsNeedsReview(reason)
        case .missing: throw TriptychControlError.settingsMissing
        case .oldSchema(let version): throw TriptychControlError.settingsOldSchema(version)
        case .futureSchema(let version): throw TriptychControlError.settingsFutureSchema(version)
        case .corrupted: throw TriptychControlError.settingsCorrupted
        }
    }

    private func decodeSettingsLoadState(_ data: Data) -> TriptychSettingsLoadState {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any] else {
            return .corrupted
        }
        guard let rawVersion = envelope["schemaVersion"] else {
            return .oldSchema(nil)
        }
        guard let number = rawVersion as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return .corrupted
        }
        let version = number.intValue
        guard version >= TriptychSettings.currentSchemaVersion else {
            return .oldSchema(version)
        }
        guard version <= TriptychSettings.currentSchemaVersion else {
            return .futureSchema(version)
        }
        let settings: TriptychSettings
        do {
            settings = try decoder().decode(TriptychSettings.self, from: data)
        } catch {
            return .corrupted
        }
        let revision = SettingsRevision(
            fingerprint: DocumentFingerprint(data: data)
        )
        do {
            try TriptychSettingsValidator.validate(settings)
        } catch {
            return .needsReview(
                settings: settings,
                revision: revision,
                reason: error.localizedDescription
            )
        }
        return .current(TriptychSettingsSnapshot(
            settings: settings,
            revision: revision
        ))
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
        var swapOccurred = false
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
                swapOccurred = true

                do {
                    try self.controlPostSwapHook?(coordinatedURL)
                    let canonical = try Data(contentsOf: coordinatedURL, options: [.mappedIfSafe])
                    let displaced = try Data(contentsOf: stagingURL, options: [.mappedIfSafe])
                    guard canonical == candidate, displaced == expected else {
                        if canonical == candidate,
                           renameatx_np(
                            AT_FDCWD,
                            stagingURL.path,
                            AT_FDCWD,
                            coordinatedURL.path,
                            UInt32(RENAME_SWAP)
                           ) == 0 {
                            swapOccurred = false
                            throw conflict()
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
                } catch {
                    if !swapOccurred { throw error }
                    if let controlError = error as? TriptychControlError,
                       case .controlFileCommitUncertain = controlError {
                        throw controlError
                    }
                    throw TriptychControlError.controlFileCommitUncertain(
                        error.localizedDescription
                    )
                }
            }
        }
        if let coordinationError {
            if swapOccurred {
                throw TriptychControlError.controlFileCommitUncertain(
                    coordinationError.localizedDescription
                )
            }
            throw coordinationError
        }
        guard let outcome else {
            if swapOccurred {
                throw TriptychControlError.controlFileCommitUncertain(
                    CocoaError(.fileWriteUnknown).localizedDescription
                )
            }
            throw CocoaError(.fileWriteUnknown)
        }
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

    private func withPortableControlLock<T>(
        _ operation: () throws -> T
    ) throws -> T {
        if let portableControlLock {
            return try portableControlLock.withExclusiveLock(operation)
        }
        return try operation()
    }

    private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
