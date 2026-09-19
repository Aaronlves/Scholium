import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func importImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .importIntoAttachments
        )
        return try await registerPreparedAttachmentFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    func indexImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .indexAbsolutePath
        )
        return try await registerPreparedAttachmentFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: sourceURL
        )
    }

    func importPastedImageAttachment(
        at sourceURL: URL,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.prepareImage(
            at: sourceURL,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath,
            management: .importIntoAttachments
        )
        return try await registerPreparedAttachmentFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    func importPastedImageAttachment(
        data: Data,
        preferredFilename: String,
        for note: VaultQualifiedNoteID
    ) async throws -> PreparedSourceAttachment {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        let repository = try repository(vaultID: note.vaultID)
        _ = try await repository.load(relativePath: note.relativePath)
        let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let attachmentID = UUID()
        let preparedFile = try await fileStore.preparePastedImage(
            data: data,
            preferredFilename: preferredFilename,
            attachmentID: attachmentID,
            noteRelativePath: note.relativePath
        )
        return try await registerPreparedAttachmentFile(
            preparedFile,
            attachmentID: attachmentID,
            vaultID: note.vaultID,
            fileStore: fileStore,
            indexedSourceURL: nil
        )
    }

    private func registerPreparedAttachmentFile(
        _ preparedFile: PreparedVaultAttachmentFile,
        attachmentID: UUID,
        vaultID: UUID,
        fileStore: VaultAttachmentStore,
        indexedSourceURL: URL?
    ) async throws -> PreparedSourceAttachment {
        let existingIndexedRecord: PortableAttachmentRecord?
        if let indexedSourceURL {
            guard case .external(let reference) = preparedFile.location else {
                throw ImageAttachmentError.unsupportedImage(indexedSourceURL.path)
            }
            let canonicalPath =
                indexedSourceURL
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
            if let existingID = try await services.indexedAttachmentAccessStore
                .attachmentID(forAbsolutePath: canonicalPath),
                let candidate = try await services.controlStore.attachmentRecords()
                    .first(where: {
                        $0.id == existingID && $0.vaultID == vaultID
                            && $0.location == preparedFile.location
                    }),
                try await services.indexedAttachmentAccessStore.isAvailable(
                    attachmentID: candidate.id,
                    expectedFilename: reference.filename
                )
            {
                existingIndexedRecord = candidate
            } else {
                existingIndexedRecord = nil
            }
        } else {
            existingIndexedRecord = nil
        }

        let registration: (record: PortableAttachmentRecord, created: Bool)
        if let existingIndexedRecord {
            registration = (existingIndexedRecord, false)
        } else {
            do {
                registration = try await services.controlStore.registerAttachment(
                    vaultID: vaultID,
                    location: preparedFile.location,
                    preferredID: attachmentID
                )
            } catch {
                if let fingerprint = preparedFile.copiedFileFingerprint,
                    let copiedRelativePath = preparedFile.copiedRelativePath
                {
                    if let imageError = error as? ImageAttachmentError,
                        case .catalogCommitUncertain = imageError
                    {
                        throw error
                    }
                    do {
                        try await fileStore.removeCopiedImageIfExact(
                            relativePath: copiedRelativePath,
                            expectedFingerprint: fingerprint
                        )
                    } catch let cleanupError {
                        throw ImageAttachmentError.preparationCleanupFailed(
                            operation: error.localizedDescription,
                            cleanup: cleanupError.localizedDescription
                        )
                    }
                }
                throw error
            }
        }

        var createdLocalAccessRecord = false
        if let indexedSourceURL {
            guard case .external = registration.record.location else {
                throw ImageAttachmentError.unsupportedImage(indexedSourceURL.path)
            }
            do {
                if existingIndexedRecord == nil {
                    let canonicalPath =
                        indexedSourceURL
                        .resolvingSymlinksInPath()
                        .standardizedFileURL
                        .path
                    createdLocalAccessRecord = try await services.indexedAttachmentAccessStore.register(
                        attachmentID: registration.record.id,
                        selectedURL: indexedSourceURL,
                        expectedAbsolutePath: canonicalPath
                    )
                }
            } catch {
                if registration.created {
                    do {
                        try await services.controlStore.removeAttachment(
                            registration.record
                        )
                    } catch let cleanupError {
                        throw ImageAttachmentError.preparationCleanupFailed(
                            operation: error.localizedDescription,
                            cleanup: cleanupError.localizedDescription
                        )
                    }
                }
                throw error
            }
        }
        return PreparedSourceAttachment(
            record: registration.record,
            markdownDestination: preparedFile.markdownDestination,
            altText: preparedFile.altText,
            copiedFileFingerprint: preparedFile.copiedFileFingerprint,
            createdCatalogRecord: registration.created,
            createdLocalAccessRecord: createdLocalAccessRecord
        )
    }

    func rollbackSourceAttachment(
        _ preparation: PreparedSourceAttachment
    ) async throws {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }

        if preparation.createdCatalogRecord {
            // Keep Finder bytes when catalog cleanup is uncertain: a remaining
            // portable record must never be made to point at a missing file.
            try await services.controlStore.removeAttachment(preparation.record)
        }
        if preparation.createdLocalAccessRecord {
            try await services.indexedAttachmentAccessStore.removeIfPresent(
                attachmentID: preparation.record.id
            )
        }
        if let fingerprint = preparation.copiedFileFingerprint {
            guard case .vaultRelative(let relativePath) = preparation.record.location else {
                throw ImageAttachmentError.cleanupRefused(
                    preparation.record.location.filename
                )
            }
            let repository = try repository(vaultID: preparation.record.vaultID)
            let fileStore = VaultAttachmentStore(vaultURL: await repository.vaultURL)
            try await fileStore.removeCopiedImageIfExact(
                relativePath: relativePath,
                expectedFingerprint: fingerprint
            )
        }
    }

    func unavailableIndexedImagePaths(
        in markdownSource: String
    ) async throws -> [String] {
        let referencedPaths = IndexedImageReferences.absolutePaths(
            in: markdownSource
        )
        guard !referencedPaths.isEmpty else { return [] }
        let records = try await services.controlStore.attachmentRecords()
        var unavailable: [String] = []
        for path in referencedPaths {
            let filename = URL(fileURLWithPath: path).lastPathComponent
            guard let reference = try? ExternalAttachmentReference(filename: filename) else {
                unavailable.append(path)
                continue
            }
            guard
                let attachmentID = try await services.indexedAttachmentAccessStore
                    .attachmentID(forAbsolutePath: path),
                let record = records.first(where: {
                    $0.id == attachmentID
                        && $0.location == .external(reference)
                })
            else {
                unavailable.append(path)
                continue
            }
            if try await services.indexedAttachmentAccessStore.isAvailable(
                attachmentID: record.id,
                expectedFilename: filename
            ) == false {
                unavailable.append(path)
            }
        }
        return unavailable.sorted()
    }

    func sourceAttachment(for destination: String, target: SourceAttachmentTarget) async throws -> DocumentAttachmentSnapshot? {
        guard let reference = SourceResourceReferences.file(destination: destination, noteRelativePath: target.relativePath),
            let path = reference.absolutePath,
            let id = try await services.indexedAttachmentAccessStore.attachmentID(forAbsolutePath: path)
        else { return nil }
        return try await documentAttachments(for: target).first { $0.record.id == id }
    }

    func documentAttachments(for target: SourceAttachmentTarget) async throws -> [DocumentAttachmentSnapshot] {
        let listing = try await agentAttachments(noteID: target.noteID)
        _ = try await verifiedDocumentAttachmentTarget(target)
        return listing.attachments.map {
            DocumentAttachmentSnapshot(
                record: PortableAttachmentRecord(id: $0.id, vaultID: target.vaultID, location: $0.location),
                availability: $0.available ? .available : .unavailable)
        }
    }

    func prepareDocumentAttachment(
        at sourceURL: URL, to target: SourceAttachmentTarget,
        management: DocumentAttachmentManagement
    ) async throws -> PreparedSourceAttachment {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer { if secured { sourceURL.stopAccessingSecurityScopedResource() } }
        let mutationLease = try await beginSourceMutation()
        defer { endSourceMutation(mutationLease) }
        let repository = try await verifiedDocumentAttachmentTarget(target)
        let store = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let id = UUID()
        let file = try await store.prepareDocument(at: sourceURL, attachmentID: id, management: management)
        let destination: String
        switch file.location {
        case .vaultRelative(let path):
            destination = VaultAttachmentStore.markdownDestination(from: target.relativePath, to: path)
        case .external:
            destination = VaultAttachmentStore.absoluteMarkdownDestination(sourceURL.resolvingSymlinksInPath().standardizedFileURL.path)
        }
        return try await registerPreparedAttachmentFile(
            PreparedVaultAttachmentFile(
                location: file.location, markdownDestination: destination, altText: file.location.filename,
                copiedFileFingerprint: file.copiedFileFingerprint, copiedRelativePath: file.copiedRelativePath),
            attachmentID: id, vaultID: target.vaultID, fileStore: store,
            indexedSourceURL: management == .referenceOriginal ? sourceURL : nil)
    }

    func prepareDocumentAttachmentPreview(
        attachmentID: UUID,
        for target: SourceAttachmentTarget
    ) async throws -> DocumentAttachmentPreviewLease {
        try requireActive()
        _ = try await verifiedDocumentAttachmentTarget(target)
        guard
            let record = try await documentAttachments(for: target)
                .first(where: { $0.record.id == attachmentID })?.record
        else {
            throw DocumentAttachmentError.unavailable(attachmentID.uuidString)
        }
        switch record.location {
        case .vaultRelative(let path):
            let repository = try repository(vaultID: record.vaultID)
            let store = VaultAttachmentStore(vaultURL: await repository.vaultURL)
            guard
                let url = try await store.documentURLIfAvailable(
                    relativePath: path
                )
            else {
                throw DocumentAttachmentError.unavailable(record.filename)
            }
            return DocumentAttachmentPreviewLease(
                accessToken: UUID(),
                attachmentID: record.id,
                filename: record.filename,
                fileURL: url
            )
        case .external(let reference):
            let access = try await services.indexedAttachmentAccessStore.beginAccess(
                attachmentID: record.id,
                expectedFilename: reference.filename
            )
            return DocumentAttachmentPreviewLease(
                accessToken: access.token,
                attachmentID: record.id,
                filename: record.filename,
                fileURL: access.url
            )
        }
    }

    func releaseDocumentAttachmentPreview(accessToken: UUID) async {
        await services.indexedAttachmentAccessStore.endAccess(accessToken)
    }

    private func verifiedDocumentAttachmentTarget(
        _ target: SourceAttachmentTarget
    ) async throws -> VaultRepository {
        let repository = try repository(vaultID: target.vaultID)
        let document = try await repository.load(relativePath: target.relativePath)
        guard
            let identity = try await services.controlStore.identity(
                forVaultID: target.vaultID,
                relativePath: target.relativePath,
                fingerprint: document.fingerprint,
                createIfMissing: false
            ), identity.id == target.noteID
        else {
            throw DocumentAttachmentError.noteIdentityChanged(target.relativePath)
        }
        return repository
    }
}
