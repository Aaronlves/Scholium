import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

struct RetainedCreatedDocument: Sendable {
    let document: NoteDocument
    let identityRecoveryWarning: String
}

enum CreatedDocumentIdentityRollbackError: LocalizedError, Sendable {
    case sourceRolledBack(path: String, identityFailure: String)
    case sourcePresenceUncertain(
        path: String,
        identityFailure: String,
        rollbackFailure: String,
        observationFailure: String
    )

    var errorDescription: String? {
        switch self {
        case .sourceRolledBack(let path, let identityFailure):
            "Scholium removed the newly created source at \(path) after portable identity setup failed. No new Note remains. Identity: \(identityFailure)"
        case .sourcePresenceUncertain(
            let path,
            let identityFailure,
            let rollbackFailure,
            let observationFailure
        ):
            "Scholium could not determine whether the newly created note at \(path) remains after stable identity setup and rollback both failed. Do not repeat creation until the vault has been refreshed and inspected. Identity: \(identityFailure) Rollback: \(rollbackFailure) Observation: \(observationFailure)"
        }
    }
}

enum ManagedCreationFinalVerificationError: LocalizedError, Sendable {
    case sourceAndIdentityNotJointlyProven(String)

    var errorDescription: String? {
        switch self {
        case .sourceAndIdentityNotJointlyProven(let path):
            "Scholium created \(path) but could not jointly prove its final source and reserved portable identity. Recovery must reconcile the creation before it can be reported as complete."
        }
    }
}
extension WorkspaceHandle {
    func importMarkdown(
        at sourceURL: URL,
        intoVault vaultID: UUID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let resolved = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolved.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true,
            values.isSymbolicLink != true,
            resolved.pathExtension.caseInsensitiveCompare("md") == .orderedSame
        else {
            throw DocumentImportError.unsupportedSource(sourceURL.path)
        }
        let sourceData = try Data(contentsOf: resolved, options: [.mappedIfSafe])
        guard NoteDocument.decodeUTF8PreservingBOM(sourceData) != nil else {
            throw DocumentImportError.unsupportedSource(sourceURL.path)
        }

        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: vaultID)
        let document = try await repository.importMarkdown(
            preferredFilename: resolved.lastPathComponent,
            sourceData: sourceData
        )
        let id = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: document.relativePath
        )
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            guard
                try await services.controlStore.identity(
                    forVaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint
                ) != nil
            else {
                throw NoteIdentityRecoveryError.identityUnresolved(document.relativePath)
            }
        } catch let identityError {
            guard
                let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                    repository: repository,
                    document: document,
                    identityError: identityError
                )
            else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: id,
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    func importMarkdownSource(
        _ source: String,
        at id: VaultQualifiedNoteID
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)

        let document = try await repository.create(
            relativePath: id.relativePath,
            content: source
        )
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            guard
                try await services.controlStore.identity(
                    forVaultID: id.vaultID,
                    relativePath: id.relativePath,
                    fingerprint: document.fingerprint
                ) != nil
            else {
                throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
            }
        } catch let identityError {
            guard
                let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                    repository: repository,
                    document: document,
                    identityError: identityError
                )
            else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: id,
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning
        )
    }

    /// The sole managed creator for GUI and MCP delivery. It
    /// composes one fixed authored-YAML scaffold and one
    /// complete candidate, atomically claims the path, and then commits the
    /// portable stable identity before publishing a source-ahead result.
    func createManagedNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> WorkspaceMutationOutcome<WorkspaceManagedNoteCommit> {
        try requireActive()
        guard services.manifest.vaultIDs.contains(where: { $0.value == request.vaultID }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(request.vaultID)
        }
        if let barrier = managedCreationPreLeaseBarrierForTesting {
            await barrier()
        }
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let reservedIdentity: UUID
        switch request.authority {
        case .researcher:
            reservedIdentity = UUID()
        case .mcp(let identity):
            reservedIdentity = identity
        }
        let registeredVault = try vault(id: request.vaultID)
        let initialSource = try ManagedNoteSourceBuilder.source(
            for: request,
            vaultRole: registeredVault.role
        )
        let repository = try repository(vaultID: request.vaultID)

        var ordinal = 1
        while true {
            try Task.checkCancellation()
            let relativePath: String =
                switch request.destination {
                case .exact(let path):
                    path
                case .untitled(let folderRelativePath):
                    if let folderRelativePath, !folderRelativePath.isEmpty {
                        "\(folderRelativePath)/\(ordinal == 1 ? "Untitled.md" : "Untitled \(ordinal).md")"
                    } else {
                        ordinal == 1 ? "Untitled.md" : "Untitled \(ordinal).md"
                    }
                }
            let id = VaultQualifiedNoteID(
                vaultID: request.vaultID,
                relativePath: relativePath
            )
            if try await services.controlStore.identityRecord(
                vaultID: request.vaultID,
                relativePath: relativePath
            ) != nil {
                switch request.destination {
                case .exact:
                    throw DocumentCreationError.portableIdentityAlreadyExists
                case .untitled:
                    ordinal += 1
                    continue
                }
            }
            do {
                let document = try await repository.create(
                    relativePath: relativePath,
                    content: initialSource
                )
                if let barrier = managedCreationPostSourceBarrierForTesting {
                    await barrier()
                }
                var committedDocument = document
                var stableIdentity = WorkspaceNoteIdentityState.unresolved
                var createdIdentityRecord: NoteIdentityRecord?
                var identityRecoveryWarning: String?
                do {
                    guard
                        let identity = try await services.controlStore.identity(
                            forVaultID: request.vaultID,
                            relativePath: relativePath,
                            fingerprint: document.fingerprint,
                            preferredID: reservedIdentity
                        )
                    else {
                        throw NoteIdentityRecoveryError.identityUnresolved(relativePath)
                    }
                    if identity.id != reservedIdentity {
                        throw DocumentCreationError.reservedIdentityMismatch
                    }
                    stableIdentity = .resolved(identity.id)
                    createdIdentityRecord = identity
                } catch let identityError {
                    let retained: RetainedCreatedDocument
                    do {
                        guard
                            let result = try await retainedCreatedDocumentAfterIdentityFailure(
                                repository: repository,
                                document: document,
                                identityError: identityError
                            )
                        else {
                            throw identityError
                        }
                        retained = result
                    } catch let rollbackError as CreatedDocumentIdentityRollbackError {
                        if case .researcher = request.authority,
                            case .sourcePresenceUncertain = rollbackError
                        {
                            let record = try await recordManagedCreationRecovery(
                                vaultID: request.vaultID,
                                relativePath: relativePath,
                                reservedIdentityID: reservedIdentity,
                                intendedRevision: document.fingerprint,
                                repository: repository,
                                failure: rollbackError.localizedDescription
                            )
                            throw TriptychTransactionError.recoveryRequired(record)
                        }
                        throw rollbackError
                    }
                    committedDocument = retained.document
                    identityRecoveryWarning = retained.identityRecoveryWarning
                    if case .researcher = request.authority {
                        let record = try await recordManagedCreationRecovery(
                            vaultID: request.vaultID,
                            relativePath: relativePath,
                            reservedIdentityID: reservedIdentity,
                            intendedRevision: document.fingerprint,
                            repository: repository,
                            failure: retained.identityRecoveryWarning
                        )
                        throw TriptychTransactionError.recoveryRequired(record)
                    }
                }

                if identityRecoveryWarning == nil {
                    do {
                        let finalDocument = try await repository.load(
                            relativePath: relativePath
                        )
                        let finalIdentity = try await services.controlStore
                            .identityRecord(
                                vaultID: request.vaultID,
                                relativePath: relativePath
                            )
                        guard finalDocument.fingerprint == document.fingerprint,
                            finalIdentity?.id == reservedIdentity,
                            finalIdentity?.fingerprint == document.fingerprint
                        else {
                            throw
                                ManagedCreationFinalVerificationError
                                .sourceAndIdentityNotJointlyProven(relativePath)
                        }
                        committedDocument = finalDocument
                        stableIdentity = .resolved(reservedIdentity)
                        createdIdentityRecord = finalIdentity
                    } catch {
                        let verification =
                            ManagedCreationFinalVerificationError
                            .sourceAndIdentityNotJointlyProven(relativePath)
                        if case .researcher = request.authority {
                            let record = try await recordManagedCreationRecovery(
                                vaultID: request.vaultID,
                                relativePath: relativePath,
                                reservedIdentityID: reservedIdentity,
                                intendedRevision: document.fingerprint,
                                repository: repository,
                                failure: verification.localizedDescription
                            )
                            throw TriptychTransactionError.recoveryRequired(record)
                        }
                        throw verification
                    }
                }

                sourceAheadIdentityRecords[id] = createdIdentityRecord
                // Queue the only complete derived rebuild before releasing the
                // source lease. A matching watcher event therefore remains
                // behind this owned task instead of starting a duplicate cycle.
                scheduleSourceCommitRefresh(id: id, kind: .creation)
                endSourceMutation(mutationLease)
                ownsMutation = false
                return WorkspaceMutationOutcome(
                    committedValue: WorkspaceManagedNoteCommit(
                        id: id,
                        vaultRole: registeredVault.role,
                        stableIdentity: stableIdentity,
                        document: committedDocument,
                    ),
                    identityRecoveryWarning: identityRecoveryWarning
                )
            } catch let error as VaultRepositoryError {
                switch error {
                case .fileAlreadyExists, .pathCollision:
                    guard case .untitled = request.destination else { throw error }
                    ordinal += 1
                default:
                    throw error
                }
            }
        }
    }

    private func recordManagedCreationRecovery(
        vaultID: UUID,
        relativePath: String,
        reservedIdentityID: UUID,
        intendedRevision: DocumentFingerprint,
        repository: VaultRepository,
        failure: String
    ) async throws -> TriptychMutationRecoveryRecord {
        let observed: DocumentFingerprint?
        let state: TriptychMutationRecoveryState
        let sourceDetail: String
        do {
            let document = try await repository.load(relativePath: relativePath)
            observed = document.fingerprint
            state =
                document.fingerprint == intendedRevision
                ? .intendedBytesRemain
                : .externallyChanged
            sourceDetail = "The managed path currently has revision \(document.fingerprint.sha256)."
        } catch VaultRepositoryError.fileDoesNotExist {
            observed = nil
            state = .missing
            sourceDetail = "The managed path is currently absent."
        } catch {
            observed = nil
            state = .unreadable
            sourceDetail = "The managed path could not be read: \(error.localizedDescription)"
        }
        let identityDetail: String
        do {
            if let identity = try await services.controlStore.identityRecord(
                vaultID: vaultID,
                relativePath: relativePath
            ) {
                identityDetail = " Portable identity \(identity.id.uuidString) remains at revision \(identity.fingerprint.sha256)."
            } else {
                identityDetail = " No portable identity is currently assigned to the path."
            }
        } catch {
            identityDetail = " Portable identity state is unreadable: \(error.localizedDescription)"
        }
        let record = TriptychMutationRecoveryRecord(
            triptychID: id,
            operation: .noteCreation,
            failure: failure,
            files: [
                TriptychMutationRecoveryFile(
                    vaultID: vaultID,
                    path: relativePath,
                    role: .createdNote,
                    beforeRevision: nil,
                    intendedRevision: intendedRevision,
                    observedRevision: observed,
                    state: state,
                    detail: sourceDetail + identityDetail
                )
            ],
            managedCreation: ManagedCreationRecoveryReference(
                target: VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: relativePath
                ),
                reservedIdentityID: reservedIdentityID,
            )
        )
        do {
            try await services.transactionRecoveryStore.record(record)
        } catch {
            throw TriptychTransactionError.recoveryPersistenceFailed(
                record,
                error.localizedDescription
            )
        }
        return record
    }

    private static func schemaProfile(for slot: WorkspaceVaultSlot) -> SchemaProfileID {
        switch slot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    static func isNonemptyManagedValue(_ value: YAMLValue) -> Bool {
        switch value {
        case .string(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .integer, .double, .boolean:
            true
        case .array(let values):
            !values.isEmpty && values.allSatisfy(isNonemptyManagedValue)
        case .object(let values):
            !values.isEmpty && values.values.allSatisfy(isNonemptyManagedValue)
        case .null:
            false
        }
    }

    /// Claims one default directory name. The returned path is a location, not
    /// a new portable identity or source mutation.
    func createUntitledFolder(
        inVault vaultID: UUID,
        parentRelativePath: String?
    ) async throws -> WorkspaceMutationOutcome<VaultRelativeFolderPath> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: vaultID)
        var ordinal = 1
        while true {
            try Task.checkCancellation()
            let name = ordinal == 1 ? "Untitled Folder" : "Untitled Folder \(ordinal)"
            let relativePath =
                if let parentRelativePath, !parentRelativePath.isEmpty {
                    parentRelativePath + "/" + name
                } else {
                    name
                }
            do {
                let folder = try await repository.createFolder(relativePath: relativePath)
                scheduleCommittedMutationRefresh(
                    WorkspaceRefreshPayload(
                        publication: .explicit,
                        failureDisposition: .staleAfterCommittedMutation(
                            affectedVaultIDs: [vaultID]
                        ),
                        sourceCatalogPreparation: Self.catalogPreparation(
                            refreshFolderVaultIDs: [vaultID]
                        )
                    ))
                endSourceMutation(mutationLease)
                ownsMutation = false
                return WorkspaceMutationOutcome(committedValue: folder)
            } catch VaultRepositoryError.fileAlreadyExists {
                ordinal += 1
            } catch VaultRepositoryError.pathCollision {
                ordinal += 1
            }
        }
    }

    func moveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        try await coordinatedMoveFolder(
            inVault: vaultID,
            from: sourceRelativePath,
            to: destinationRelativePath
        )
    }

    func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try await duplicateDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision,
            expectedStableNoteID: nil
        )
    }

    func duplicateDocument(
        _ target: NoteMutationTarget,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try await duplicateDocument(
            target.documentID,
            to: destinationRelativePath,
            expectedRevision: target.revision,
            expectedStableNoteID: target.stableNoteID
        )
    }

    private func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        expectedStableNoteID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteDocument> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let repository = try repository(vaultID: id.vaultID)
        let identity = try await resolvedIdentity(
            for: id,
            expectedRevision: expectedRevision
        )
        try requireExpectedIdentity(
            expectedStableNoteID,
            resolved: identity.id,
            relativePath: id.relativePath
        )
        let document = try await repository.duplicate(
            relativePath: id.relativePath,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
        var committedDocument = document
        var identityRecoveryWarning: String?
        do {
            _ = try await services.controlStore.duplicateIdentity(
                from: identity.id,
                to: destinationRelativePath,
                fingerprint: document.fingerprint
            )

        } catch let identityError {
            guard
                let retained = try await retainedCreatedDocumentAfterIdentityFailure(
                    repository: repository,
                    document: document,
                    identityError: identityError
                )
            else {
                throw identityError
            }
            committedDocument = retained.document
            identityRecoveryWarning = retained.identityRecoveryWarning
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return await finishCreatedDocumentMutation(
            id: VaultQualifiedNoteID(
                vaultID: id.vaultID,
                relativePath: destinationRelativePath
            ),
            document: committedDocument,
            identityRecoveryWarning: identityRecoveryWarning,
        )
    }

    /// Creation and duplication first commit a no-replace source and then
    /// establish portable identity. If identity setup fails, rollback is
    /// revision checked. A failed rollback is never ignored: this helper
    /// distinguishes a proven retained source from unreadable presence so the
    /// managed researcher creator can persist one recovery duty, while older
    /// import and duplication callers keep their existing warning boundary.
    private func retainedCreatedDocumentAfterIdentityFailure(
        repository: VaultRepository,
        document: NoteDocument,
        identityError: any Error
    ) async throws -> RetainedCreatedDocument? {
        do {
            try await repository.removeCreatedFileForRollback(
                relativePath: document.relativePath,
                createdRevision: document.fingerprint
            )
        } catch {
            let rollbackError = error
            do {
                let retained = try await repository.load(
                    relativePath: document.relativePath
                )
                return RetainedCreatedDocument(
                    document: retained,
                    identityRecoveryWarning:
                        "The source remains at \(document.relativePath) because stable identity setup failed and exact rollback was refused. Do not create or import it again; recover its identity instead. Identity: \(identityError.localizedDescription) Rollback: \(rollbackError.localizedDescription)"
                )
            } catch VaultRepositoryError.fileDoesNotExist {
                // The delete may have committed before its own verification
                // failed. A direct read now proves there is no retained source.
                throw CreatedDocumentIdentityRollbackError.sourceRolledBack(
                    path: document.relativePath,
                    identityFailure: identityError.localizedDescription
                )
            } catch {
                throw CreatedDocumentIdentityRollbackError.sourcePresenceUncertain(
                    path: document.relativePath,
                    identityFailure: identityError.localizedDescription,
                    rollbackFailure: rollbackError.localizedDescription,
                    observationFailure: error.localizedDescription
                )
            }
        }
        throw CreatedDocumentIdentityRollbackError.sourceRolledBack(
            path: document.relativePath,
            identityFailure: identityError.localizedDescription
        )
    }

    private func finishCreatedDocumentMutation(
        id: VaultQualifiedNoteID,
        document: NoteDocument,
        identityRecoveryWarning: String?
    ) async -> WorkspaceMutationOutcome<NoteDocument> {
        var identityRecoveryWarning = identityRecoveryWarning
        let derivedRefreshWarning: String?
        do {
            let refreshed = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: Self.catalogPreparation(
                    upserts: [id],
                    refreshFolderVaultIDs: [id.vaultID]
                )
            )
            if identityRecoveryWarning != nil,
                refreshed.document(id: id)?.stableIdentity.resolvedID != nil
            {
                identityRecoveryWarning = nil
            }
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: document,
            derivedRefreshWarning: derivedRefreshWarning,
            identityRecoveryWarning: identityRecoveryWarning,
        )
    }

}
