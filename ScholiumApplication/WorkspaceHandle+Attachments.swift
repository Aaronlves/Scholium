import Foundation
import ImageIO
import ScholiumContracts
import ScholiumCore
import UniformTypeIdentifiers

extension WorkspaceHandle {
    func exportImages(
        for note: VaultQualifiedNoteID,
        markdownSource: String
    ) async throws -> [String: RenderedMarkdownImage] {
        try requireActive()
        let repository = try repository(vaultID: note.vaultID)
        // The caller may have an unsaved editor buffer. Parse that exact source,
        // while checking that the selected Note still belongs to this vault.
        _ = try await repository.load(relativePath: note.relativePath)
        let body = NoteDocument(relativePath: note.relativePath, rawContent: markdownSource).body
        let references = SourceResourceReferences.files(
            in: body, noteRelativePath: note.relativePath
        ).filter(\.isImage)
        guard !references.isEmpty else { return [:] }

        let store = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        let records = try await services.controlStore.attachmentRecords()
            .filter { $0.vaultID == note.vaultID }
        var resolved: [String: RenderedMarkdownImage] = [:]
        var totalBytes = 0
        for reference in references {
            try Task.checkCancellation()
            let destination =
                reference.destination.removingPercentEncoding
                ?? reference.destination
            if resolved[destination] != nil { continue }
            let bytes: Data
            do {
                if let path = reference.relativePath {
                    bytes = try await store.readContent(
                        relativePath: path,
                        maximumByteCount: RenderedMarkdownImage.maximumByteCount
                    )
                } else if let path = reference.absolutePath {
                    let filename = URL(fileURLWithPath: path).lastPathComponent
                    let location = AttachmentLocation.external(
                        try ExternalAttachmentReference(filename: filename)
                    )
                    guard
                        let id = try await services.indexedAttachmentAccessStore
                            .attachmentID(forAbsolutePath: path),
                        records.contains(where: { $0.id == id && $0.location == location })
                    else { throw DocumentExportImageError.unavailable(destination) }
                    let access = try await services.indexedAttachmentAccessStore.beginAccess(
                        attachmentID: id, expectedFilename: filename
                    )
                    do {
                        bytes = try await VaultAttachmentStore(vaultURL: URL(fileURLWithPath: "/"))
                            .readContent(
                                relativePath: AttachmentRelativePath(
                                    String(access.url.path.dropFirst())
                                ),
                                maximumByteCount: RenderedMarkdownImage.maximumByteCount
                            )
                        await services.indexedAttachmentAccessStore.endAccess(access.token)
                    } catch {
                        await services.indexedAttachmentAccessStore.endAccess(access.token)
                        throw error
                    }
                } else {
                    throw DocumentExportImageError.unavailable(destination)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as CocoaError where error.code == .fileReadTooLarge {
                throw DocumentExportImageError.unsupported(destination)
            } catch {
                throw DocumentExportImageError.unavailable(destination)
            }
            guard bytes.count <= 80 * 1_024 * 1_024 - totalBytes else {
                throw DocumentExportImageError.totalSizeExceeded
            }
            resolved[destination] = try ExportImageDataValidator.validate(
                bytes, destination: destination
            )
            totalBytes += bytes.count
        }
        return resolved
    }

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

/// ImageIO checks dimensions and a full first-frame decode before trusted bytes
/// enter HTML/PDF data URLs. The renderer separately enforces MIME and headers.
enum ExportImageDataValidator {
    static let maximumPixelCount = 25_000_000

    static func validate(_ data: Data, destination: String) throws -> RenderedMarkdownImage {
        guard data.count <= RenderedMarkdownImage.maximumByteCount,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetCount(source) > 0,
            let identifier = CGImageSourceGetType(source),
            let mimeType = UTType(identifier as String)?.preferredMIMEType,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0, height > 0,
            width <= maximumPixelCount / height,
            CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) != nil
        else { throw DocumentExportImageError.unsupported(destination) }
        do {
            return try RenderedMarkdownImage(data: data, mimeType: mimeType)
        } catch {
            throw DocumentExportImageError.unsupported(destination)
        }
    }
}
