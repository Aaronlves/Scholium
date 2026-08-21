import Darwin
import Foundation
import ScholiumContracts

public actor VaultRepository {
    public let identity: VaultIdentity
    public let vaultRole: VaultRole
    public let vaultURL: URL
    public let storageURL: URL

    private let canonicalRoot: URL
    private let pathResolver: VaultPathResolver
    private let descriptorAccess: VaultDescriptorAccess
    private let mutationCoordinator: VaultMutationCoordinator
    private let recoveryLedger: PrewriteRecoveryLedger
    private let fileManager = FileManager.default

    public init(
        vaultURL: URL,
        identity: VaultIdentity,
        applicationSupportURL: URL,
        vaultRole: VaultRole = .other
    ) throws {
        try self.init(
            vaultURL: vaultURL,
            identity: identity,
            applicationSupportURL: applicationSupportURL,
            vaultRole: vaultRole,
            mutationHooks: .none
        )
    }

    /// Internal deterministic seam for subprocess and coordination fixtures.
    /// Production construction always uses `.none` through the public
    /// initializer above; the authoritative transaction remains unchanged.
    init(
        vaultURL: URL,
        identity: VaultIdentity,
        applicationSupportURL: URL,
        vaultRole: VaultRole = .other,
        mutationHooks: VaultMutationHooks
    ) throws {
        self.identity = identity
        self.vaultRole = vaultRole
        self.vaultURL = vaultURL.standardizedFileURL
        self.canonicalRoot = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        let pathResolver = try VaultPathResolver(rootURL: vaultURL)
        self.pathResolver = pathResolver
        self.descriptorAccess = VaultDescriptorAccess(rootURL: pathResolver.canonicalRoot)
        self.mutationCoordinator = VaultMutationCoordinator(
            resolver: pathResolver,
            hooks: mutationHooks
        )
        self.storageURL = applicationSupportURL
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
        self.recoveryLedger = try PrewriteRecoveryLedger(
            storageURL: storageURL,
            vaultURL: self.vaultURL
        )
    }

    public func recoveryLedgerHealthDiagnostic() -> String? {
        recoveryLedger.healthDiagnostic
    }

    /// Read-only filename comparison facts for this exact mounted vault root.
    /// Mutation methods still repeat collision and containment checks against
    /// current filesystem state before committing.
    public func pathComparisonPolicy() -> VaultPathComparisonPolicy {
        pathResolver.comparisonPolicy
    }

    public func load(relativePath: String) throws -> NoteDocument {
        try loadVersioned(relativePath: relativePath).document
    }

    public func loadVersioned(
        relativePath: String
    ) throws -> (document: NoteDocument, version: SourceVersion) {
        let loaded = try loadCatalogSource(relativePath: relativePath)
        return (loaded.document, loaded.version)
    }

    package func loadCatalogSource(
        relativePath: String
    ) throws -> (
        document: NoteDocument,
        version: SourceVersion,
        fileMetadata: WorkspaceFileMetadata,
        readDuration: Duration
    ) {
        let clock = ContinuousClock()
        let readStart = clock.now
        let path = try markdownRelativePath(relativePath)
        let loaded = try descriptorAccess.withOpenRegularFile(path) {
            descriptor, parentDescriptor, name, initialStatus in
            let data = try VaultDescriptorAccess.readAll(from: descriptor)
            var finalStatus = stat()
            guard fstat(descriptor, &finalStatus) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard Self.sameFileState(initialStatus, finalStatus),
                  Int(finalStatus.st_size) == data.count else {
                throw VaultRepositoryError.commitUncertain(
                    "The source changed while its exact bytes were being read."
                )
            }
            let openedIdentity = VaultDescriptorAccess.FileIdentity(
                initialStatus
            )
            let currentIdentity: VaultDescriptorAccess.FileIdentity
            do {
                currentIdentity = try VaultDescriptorAccess.identity(
                    name: name,
                    parentDescriptor: parentDescriptor
                )
            } catch let error as POSIXError where error.code == .ENOENT {
                throw VaultRepositoryError.fileDoesNotExist(relativePath)
            }
            guard currentIdentity == openedIdentity else {
                throw VaultRepositoryError.commitUncertain(
                    "The source path changed identity while its exact bytes were being read."
                )
            }
            try descriptorAccess.verifyCurrentParent(
                path,
                retainedDescriptor: parentDescriptor
            )
            return (data, finalStatus)
        }
        let data = loaded.0
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let document = NoteDocument(relativePath: relativePath, rawContent: content)
        return (
            document,
            Self.sourceVersion(status: loaded.1, fingerprint: document.fingerprint),
            Self.fileMetadata(status: loaded.1),
            readStart.duration(to: clock.now)
        )
    }

    public func sourceVersionIsCurrent(
        relativePath: String,
        version: SourceVersion
    ) throws -> Bool {
        let path = try markdownRelativePath(relativePath)
        return try descriptorAccess.withOpenRegularFile(path) {
            _, parentDescriptor, name, status in
            let openedIdentity = VaultDescriptorAccess.FileIdentity(status)
            let currentIdentity: VaultDescriptorAccess.FileIdentity
            do {
                currentIdentity = try VaultDescriptorAccess.identity(
                    name: name,
                    parentDescriptor: parentDescriptor
                )
            } catch let error as POSIXError where error.code == .ENOENT {
                throw VaultRepositoryError.fileDoesNotExist(relativePath)
            }
            guard currentIdentity == openedIdentity else {
                throw VaultRepositoryError.commitUncertain(
                    "The source path changed identity during version validation."
                )
            }
            try descriptorAccess.verifyCurrentParent(
                path,
                retainedDescriptor: parentDescriptor
            )
            return Self.matches(status: status, version: version)
        }
    }

    /// A side-effect-free authorization and revision check used by a
    /// multi-file coordinator before it starts any mutation. The repository
    /// repeats the check in the eventual operation because the filesystem can
    /// change after this preflight returns.
    func preflightExisting(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteDocument {
        let document = try load(relativePath: relativePath)
        guard document.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: document.fingerprint
            )
        }
        return document
    }

    /// Validates a prospective Markdown destination without creating folders
    /// or files. The actual create/move repeats containment checks immediately
    /// before mutation.
    func preflightNewFile(relativePath: String) throws {
        _ = try prospectiveNewFileURL(relativePath: relativePath)
    }

    /// Returns every ordinary Markdown path in the selected vault. Folder names
    /// have no hidden-location meaning and are never filtered by repository policy.
    public func markdownRelativePaths() throws -> [String] {
        var enumerationError: (any Error)?
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw VaultRepositoryError.commitUncertain(
                "The vault Markdown inventory could not be enumerated."
            )
        }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard let relativePath = VaultPath.relativePath(for: url, in: canonicalRoot) else {
                continue
            }
            guard values.isRegularFile == true,
                  url.pathExtension.caseInsensitiveCompare("md") == .orderedSame else { continue }
            paths.append(relativePath)
        }
        if let enumerationError { throw enumerationError }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Returns real directory paths, including empty folders. Directories are
    /// classifications only; callers must continue to track notes by their
    /// stable identities rather than treating these paths as durable IDs.
    public func folderRelativePaths() throws
        -> [VaultRelativeFolderPath]
    {
        var enumerationError: (any Error)?
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw VaultRepositoryError.commitUncertain(
                "The vault folder inventory could not be enumerated."
            )
        }
        var paths: [VaultRelativeFolderPath] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory == true,
                  let relativePath = VaultPath.relativePath(for: url, in: canonicalRoot),
                  let path = try? VaultRelativeFolderPath(relativePath) else { continue }
            paths.append(path)
        }
        if let enumerationError { throw enumerationError }
        return paths.sorted {
            $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending
        }
    }

    /// Creates one exact empty folder without inventing a stable identity.
    public func createFolder(relativePath: String) throws -> VaultRelativeFolderPath {
        let path = try folderRelativePath(relativePath)
        _ = try prospectiveNewFolderURL(path: path, ignoring: nil, createMissingParents: false)
        try mutationCoordinator.createDirectory(path: path)
        _ = try existingFolderURL(path: path)
        return path
    }

    func folderExists(_ path: VaultRelativeFolderPath) -> Bool {
        (try? existingFolderURL(path: path)) != nil
    }

    /// Moves one directory entry after proving that every descendant Markdown
    /// note still matches the caller's complete path-and-revision inventory.
    /// Non-Markdown descendants travel with the same directory inode and are
    /// never parsed or rewritten.
    func moveFolder(
        from source: VaultRelativeFolderPath,
        to destination: VaultRelativeFolderPath,
        expectedDocuments: [String: DocumentFingerprint],
        createMissingParents: Bool = false
    ) throws -> FolderRepositoryMoveResult {
        let sourcePrefix = source.rawValue + "/"
        guard destination.rawValue != source.rawValue,
              !destination.rawValue.hasPrefix(sourcePrefix) else {
            throw VaultRepositoryError.invalidRelativePath(destination.rawValue)
        }
        _ = try existingFolderURL(path: source)
        _ = try prospectiveNewFolderURL(
            path: destination,
            ignoring: source,
            createMissingParents: createMissingParents
        )

        let before = try preflightFolderDocuments(
            in: source,
            expectedDocuments: expectedDocuments
        )
        try mutationCoordinator.moveDirectory(source: source, destination: destination)

        let destinationPrefix = destination.rawValue + "/"
        var movedDocuments: [NoteDocument] = []
        for document in before {
            let suffix = document.relativePath.dropFirst(sourcePrefix.count)
            let movedPath = destinationPrefix + suffix
            let observed = try load(relativePath: movedPath)
            guard observed.fingerprint == document.fingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: document.fingerprint,
                    current: observed.fingerprint
                )
            }
            movedDocuments.append(observed)
        }
        _ = try existingFolderURL(path: destination)
        return FolderRepositoryMoveResult(
            sourceFolder: source,
            destinationFolder: destination,
            documents: movedDocuments.sorted { $0.relativePath < $1.relativePath }
        )
    }

    func preflightFolderMove(
        from source: VaultRelativeFolderPath,
        to destination: VaultRelativeFolderPath,
        expectedDocuments: [String: DocumentFingerprint],
        createMissingParents: Bool = false
    ) throws -> [NoteDocument] {
        let sourcePrefix = source.rawValue + "/"
        guard destination.rawValue != source.rawValue,
              !destination.rawValue.hasPrefix(sourcePrefix) else {
            throw VaultRepositoryError.invalidRelativePath(destination.rawValue)
        }
        _ = try existingFolderURL(path: source)
        _ = try prospectiveNewFolderURL(
            path: destination,
            ignoring: source,
            createMissingParents: createMissingParents
        )
        return try preflightFolderDocuments(
            in: source,
            expectedDocuments: expectedDocuments
        )
    }

    public func save(
        relativePath: String,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) throws -> SaveResult {
        switch try saveOutcome(
            relativePath: relativePath,
            changeSet: changeSet,
            expectedRevision: expectedRevision
        ) {
        case .committed(let result):
            return result
        case .notWritten(let reason):
            throw legacySaveError(for: reason, expectedRevision: expectedRevision)
        case .recoveryRequired(let recovery):
            throw VaultRepositoryError.recoveryRequired(recovery)
        }
    }

    /// Executes one exact-byte save and reports only a Core-observed outcome.
    /// Callers must not infer an unknown post-transaction result from a thrown
    /// repository error. Core first uses exact canonical readback to prove a
    /// commit; only a still-unknown result enters retained recovery.
    public func saveOutcome(
        relativePath: String,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) throws -> VaultSaveOutcome {
        _ = try existingFileURL(relativePath: relativePath)
        let currentData = try readSource(relativePath: relativePath)
        let currentFingerprint = DocumentFingerprint(data: currentData)
        guard currentFingerprint == expectedRevision else {
            return .notWritten(.conflict(currentFingerprint))
        }
        guard let currentContent = NoteDocument.decodeUTF8PreservingBOM(currentData) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        let current = NoteDocument(relativePath: relativePath, rawContent: currentContent)
        let updatedContent = try current.applying(changeSet, timestampKey: nil)
        let updated = NoteDocument(relativePath: relativePath, rawContent: updatedContent)
        if !updated.validationWarnings.isEmpty, updated.rawFrontmatter != nil {
            return .notWritten(.invalidFrontmatter(
                updated.validationWarnings.joined(separator: "\n")
            ))
        }

        let candidateData = Data(updatedContent.utf8)
        let mutation = try recoveryLedger.beginMutation(
            relativePath: relativePath,
            expected: currentData,
            candidate: candidateData
        )
        do {
            let recheckedData = try readSource(relativePath: relativePath)
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                try recoveryLedger.completeMutation(mutation)
                return .notWritten(.conflict(recheckedFingerprint))
            }
            try mutationCoordinator.updateExisting(
                path: markdownRelativePath(relativePath),
                expected: currentData,
                candidate: candidateData
            )
            let readback = try readSource(relativePath: relativePath)
            let expectedFingerprint = DocumentFingerprint(content: updatedContent)
            let readbackFingerprint = DocumentFingerprint(data: readback)
            guard readbackFingerprint == expectedFingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: expectedFingerprint,
                    current: readbackFingerprint
                )
            }
            // The canonical source commit is already proven. Removing the
            // now-redundant transaction is invisible housekeeping;
            // if it fails, startup can observe the candidate revision and
            // retry without changing Document state.
            try? recoveryLedger.completeMutation(mutation)
            return .committed(SaveResult(document: updated))
        } catch {
            if let knownOutcome = knownNotWrittenOutcome(for: error) {
                try? recoveryLedger.completeMutation(mutation)
                return knownOutcome
            }

            // File Provider and coordinated replacement APIs can finish the
            // replacement and still report an error. Exact canonical bytes,
            // not that advisory error, determine the user-visible save state.
            if let canonical = try? readSource(relativePath: relativePath),
               canonical == candidateData {
                try? recoveryLedger.completeMutation(mutation)
                return .committed(SaveResult(document: updated))
            }

            // An unchanged canonical source proves that this attempt wrote
            // nothing. Remove its redundant local transaction and preserve
            // the original error rather than presenting a recovery candidate.
            if let canonical = try? readSource(relativePath: relativePath),
               canonical == currentData {
                try? recoveryLedger.completeMutation(mutation)
                throw VaultRepositoryError.writeFailed(error.localizedDescription)
            }

            // A replacement failure, failed readback, or otherwise unprovable
            // transaction is never softened into Saved. Keep the exact
            // preimage and candidate for reconciliation.
            do {
                try recoveryLedger.retainMutation(
                    mutation,
                    reason: error.localizedDescription
                )
                return .recoveryRequired(try interruptedSaveRecovery(
                    for: mutation
                ))
            } catch {
                throw VaultRepositoryError.recoveryLedgerUnavailable(
                    "The exact interrupted-save transaction could not be retained: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Creates a new Markdown note without replacing an existing path.
    public func create(relativePath: String, content: String) throws -> NoteDocument {
        let proposed = NoteDocument(relativePath: relativePath, rawContent: content)
        if proposed.rawFrontmatter != nil, !proposed.validationWarnings.isEmpty {
            throw VaultRepositoryError.invalidFrontmatter(proposed.validationWarnings.joined(separator: "\n"))
        }
        _ = try newFileURL(relativePath: relativePath)
        do {
            try mutationCoordinator.create(
                path: markdownRelativePath(relativePath),
                data: Data(content.utf8)
            )
            let readback = try readSource(relativePath: relativePath)
            let readbackFingerprint = DocumentFingerprint(data: readback)
            guard readbackFingerprint == proposed.fingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: proposed.fingerprint,
                    current: readbackFingerprint
                )
            }
            return NoteDocument(relativePath: relativePath, rawContent: content)
        } catch { throw error }
    }

    /// Copies exact UTF-8 Markdown bytes into the vault root without replacing
    /// an existing note. Imported frontmatter remains source material and is
    /// not normalized through the new-note creation contract.
    public func importMarkdown(
        preferredFilename: String,
        sourceData: Data
    ) throws -> NoteDocument {
        let filename = URL(fileURLWithPath: preferredFilename).lastPathComponent
        guard filename == preferredFilename,
              filename.caseInsensitiveCompare(".md") != .orderedSame,
              URL(fileURLWithPath: filename).pathExtension
                .caseInsensitiveCompare("md") == .orderedSame,
              let content = NoteDocument.decodeUTF8PreservingBOM(sourceData) else {
            throw DocumentImportError.unsupportedSource(preferredFilename)
        }

        let requested = URL(fileURLWithPath: filename)
        let base = requested.deletingPathExtension().lastPathComponent
        let ext = requested.pathExtension
        var ordinal = 1
        while true {
            let relativePath = ordinal == 1
                ? filename
                : "\(base) \(ordinal).\(ext)"
            do {
                _ = try newFileURL(relativePath: relativePath)
                try mutationCoordinator.create(
                    path: markdownRelativePath(relativePath),
                    data: sourceData
                )
                let readback = try readSource(relativePath: relativePath)
                let expected = DocumentFingerprint(data: sourceData)
                let observed = DocumentFingerprint(data: readback)
                guard observed == expected else {
                    throw VaultRepositoryError.readbackMismatch(
                        expected: expected,
                        current: observed
                    )
                }
                return NoteDocument(relativePath: relativePath, rawContent: content)
            } catch VaultRepositoryError.fileAlreadyExists {
                ordinal += 1
            } catch VaultRepositoryError.pathCollision {
                ordinal += 1
            }
        }
    }

    /// Duplicates exact source bytes into a new note path.
    public func duplicate(
        relativePath: String,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteDocument {
        let data = try readSource(relativePath: relativePath)
        let current = DocumentFingerprint(data: data)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return try create(relativePath: destinationRelativePath, content: content)
    }

    /// Moves a note while preserving its exact bytes and returning the new document.
    public func move(
        relativePath: String,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteMoveResult {
        let sourceURL = try existingFileURL(relativePath: relativePath)
        let currentData = try readSource(relativePath: relativePath)
        let currentFingerprint = DocumentFingerprint(data: currentData)
        guard currentFingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: currentFingerprint)
        }
        _ = try newFileURL(relativePath: destinationRelativePath)
        do {
            let recheckedData = try readSource(relativePath: relativePath)
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: recheckedFingerprint)
            }
            guard try filePresence(relativePath: destinationRelativePath) == .absent else {
                throw VaultRepositoryError.fileAlreadyExists(destinationRelativePath)
            }
            try mutationCoordinator.move(
                source: markdownRelativePath(relativePath),
                destination: markdownRelativePath(destinationRelativePath),
                expected: currentData
            )
            let readback = try readSource(relativePath: destinationRelativePath)
            let readbackFingerprint = DocumentFingerprint(data: readback)
            guard readbackFingerprint == currentFingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: currentFingerprint,
                    current: readbackFingerprint
                )
            }
            guard let content = NoteDocument.decodeUTF8PreservingBOM(readback) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            removeEmptyParentDirectories(startingAt: sourceURL.deletingLastPathComponent())
            return NoteMoveResult(
                document: NoteDocument(relativePath: destinationRelativePath, rawContent: content),
                previousRelativePath: relativePath,
                relativePath: destinationRelativePath
            )
        } catch {
            // A coordinated rename can commit and still report an advisory
            // error. Exact path presence and destination readback settle the
            // result without creating a source-history copy.
            if (try? filePresence(relativePath: relativePath)) == .absent,
               let destinationData = try? readSource(relativePath: destinationRelativePath),
               destinationData == currentData,
               let content = NoteDocument.decodeUTF8PreservingBOM(destinationData) {
                removeEmptyParentDirectories(startingAt: sourceURL.deletingLastPathComponent())
                return NoteMoveResult(
                    document: NoteDocument(
                        relativePath: destinationRelativePath,
                        rawContent: content
                    ),
                    previousRelativePath: relativePath,
                    relativePath: destinationRelativePath
                )
            }
            throw error
        }
    }

    public func moveToSystemTrash(
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        bindingID: UUID
    ) throws -> URL? {
        return try mutationCoordinator.moveToSystemTrash(
            path: markdownRelativePath(relativePath),
            expectedRevision: expectedRevision,
            bindingID: bindingID
        )
    }

    func preflightSystemTrashNote(
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        bindingID: UUID
    ) throws {
        do {
            _ = try preflightExisting(
                relativePath: relativePath,
                expectedRevision: expectedRevision
            )
            return
        } catch VaultRepositoryError.fileDoesNotExist {
            // A process interruption may leave the exact source in the
            // transaction-owned binding named by the already durable plan.
        }
        let boundPath = SystemTrashBindingPath.itemRelativePath(
            original: relativePath,
            id: bindingID
        )
        let data = try descriptorAccess.read(markdownRelativePath(boundPath))
        let current = DocumentFingerprint(data: data)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: current
            )
        }
    }

    func moveFolderToSystemTrash(
        relativePath: String,
        expectedDirectoryManifest: DocumentFingerprint,
        bindingID: UUID
    ) throws -> URL? {
        let folder = try folderRelativePath(relativePath)
        return try mutationCoordinator.moveDirectoryToSystemTrash(
            path: folder,
            bindingID: bindingID
        ) { candidateURL in
            guard try self.systemTrashDirectoryManifest(at: candidateURL)
                    == expectedDirectoryManifest else {
                throw VaultRepositoryError.commitUncertain(
                    "The folder inventory changed during the coordinated system-Trash operation."
                )
            }
        }
    }

    func moveFolderToSystemTrashPreflight(
        relativePath: String,
        expectedDocuments: [String: DocumentFingerprint],
        expectedDirectoryManifest: DocumentFingerprint,
        bindingID: UUID
    ) throws -> VaultRelativeFolderPath {
        let folder = try VaultRelativeFolderPath(relativePath)
        let originalURL = try pathResolver.unresolvedURL(for: folder)
        let candidateURL: URL
        if fileManager.fileExists(atPath: originalURL.path) {
            _ = try preflightFolderDocuments(
                in: folder,
                expectedDocuments: expectedDocuments
            )
            candidateURL = originalURL
        } else {
            candidateURL = SystemTrashBindingPath.itemURL(
                targetURL: originalURL,
                id: bindingID,
                isDirectory: true
            )
        }
        guard try systemTrashDirectoryManifest(at: candidateURL)
                == expectedDirectoryManifest else {
            throw VaultRepositoryError.commitUncertain(
                "The folder inventory changed after confirmation."
            )
        }
        return folder
    }

    /// Hashes the complete descendant inventory, including hidden and
    /// non-Markdown files, so a Folder confirmation cannot silently absorb a
    /// later Finder or sync-tool change. Symbolic links and special files are
    /// rejected rather than traversed or omitted.
    func systemTrashDirectoryManifest(
        relativePath: String
    ) throws -> DocumentFingerprint {
        let folder = try folderRelativePath(relativePath)
        let folderURL = try existingFolderURL(path: folder)
        return try systemTrashDirectoryManifest(at: folderURL)
    }

    private func systemTrashDirectoryManifest(
        at folderURL: URL
    ) throws -> DocumentFingerprint {
        let rootValues = try folderURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true else {
            throw VaultRepositoryError.commitUncertain(
                "The system-Trash folder candidate is missing or is not a contained directory."
            )
        }
        var enumerationError: (any Error)?
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw VaultRepositoryError.commitUncertain(
                "The complete folder inventory could not be enumerated."
            )
        }
        var entries: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isSymbolicLink != true,
                  let path = VaultPath.relativePath(for: url, in: folderURL) else {
                throw VaultRepositoryError.commitUncertain(
                    "The folder contains an unsupported symbolic link."
                )
            }
            if values.isDirectory == true {
                entries.append("D\0\(path)")
            } else if values.isRegularFile == true {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                entries.append(
                    "F\0\(path)\0\(DocumentFingerprint(data: data).sha256)"
                )
            } else {
                throw VaultRepositoryError.commitUncertain(
                    "The folder contains an unsupported filesystem object at \(path)."
                )
            }
        }
        if let enumerationError { throw enumerationError }
        let canonical = entries.sorted().joined(separator: "\n")
        return DocumentFingerprint(data: Data(canonical.utf8))
    }

    func systemTrashBindingExists(
        relativePath: String,
        kind: SystemTrashDeletionSourceKind,
        bindingID: UUID
    ) throws -> Bool {
        switch kind {
        case .note:
            return try mutationCoordinator.systemTrashBindingContains(
                path: markdownRelativePath(relativePath),
                bindingID: bindingID
            )
        case .folder:
            return try mutationCoordinator.systemTrashBindingContains(
                path: folderRelativePath(relativePath),
                bindingID: bindingID
            )
        }
    }

    func folderExistsForDeletion(relativePath: String) -> Bool {
        guard let folder = try? VaultRelativeFolderPath(relativePath) else {
            return false
        }
        return folderExists(folder)
    }

    /// Removes a file created by the same higher-level transaction when that
    /// transaction must roll back. It is intentionally module-internal and is
    /// bound to the exact fingerprint returned by `create`; ordinary deletion
    /// remains unavailable through ordinary researcher deletion.
    public func removeCreatedFileForRollback(
        relativePath: String,
        createdRevision: DocumentFingerprint
    ) throws {
        _ = try existingFileURL(relativePath: relativePath)
        let data = try readSource(relativePath: relativePath)
        let current = DocumentFingerprint(data: data)
        guard current == createdRevision else {
            throw VaultRepositoryError.conflict(expected: createdRevision, current: current)
        }
        let recheckedURL = try existingFileURL(relativePath: relativePath)
        let recheckedData = try readSource(relativePath: relativePath)
        let rechecked = DocumentFingerprint(data: recheckedData)
        guard rechecked == createdRevision else {
            throw VaultRepositoryError.conflict(expected: createdRevision, current: rechecked)
        }
        try mutationCoordinator.delete(
            path: markdownRelativePath(relativePath),
            expected: recheckedData
        )
        removeEmptyParentDirectories(startingAt: recheckedURL.deletingLastPathComponent())
    }

    /// Lists only exact, startup-retained save candidates. The source state is
    /// an observation for presentation; every consequential operation below
    /// revalidates the durable manifest and canonical revision independently.
    public func interruptedSaveRecoveries() throws -> [InterruptedSaveRecovery] {
        try recoveryLedger.retainedMutations().map { transaction in
            let candidateData = try recoveryLedger.candidateData(for: transaction)
            guard NoteDocument.decodeUTF8PreservingBOM(candidateData) != nil else {
                throw VaultRepositoryError.recoveryLedgerUnavailable(
                    "An interrupted save candidate is not valid UTF-8 Markdown."
                )
            }
            return InterruptedSaveRecovery(
                id: InterruptedSaveRecoveryID(
                    vaultID: identity.id,
                    transactionID: transaction.id
                ),
                relativePath: transaction.relativePath,
                expectedRevision: transaction.expected,
                candidateRevision: transaction.candidate,
                createdAt: transaction.createdAt,
                retainedReason: transaction.retainedReason ?? "The interrupted save remains retained.",
                sourceState: interruptedSaveSourceState(transaction)
            )
        }
    }

    public func interruptedSaveRecoveryContent(
        _ recovery: InterruptedSaveRecovery
    ) throws -> InterruptedSaveRecoveryContent {
        let transaction = try retainedMutation(matching: recovery)
        let candidateData = try recoveryLedger.candidateData(for: transaction)
        guard let exactSource = NoteDocument.decodeUTF8PreservingBOM(candidateData) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save candidate is not valid UTF-8 Markdown."
            )
        }
        return InterruptedSaveRecoveryContent(
            recoveryID: recovery.id,
            exactSource: exactSource,
            fingerprint: transaction.candidate
        )
    }

    public func prepareInterruptedSaveRecoveryLocation(
        _ recovery: InterruptedSaveRecovery
    ) throws -> URL {
        let transaction = try retainedMutation(matching: recovery)
        return try recoveryLedger.retainedMutationDirectory(for: transaction)
            .appendingPathComponent("candidate.md", isDirectory: false)
    }

    public func restoreInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) throws -> InterruptedSaveRecoveryRestoreCommit {
        let transaction = try retainedMutation(matching: recovery)
        let candidateData = try recoveryLedger.candidateData(for: transaction)
        guard let candidateContent = NoteDocument.decodeUTF8PreservingBOM(candidateData) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save candidate is not valid UTF-8 Markdown."
            )
        }
        let currentData = try readSource(relativePath: transaction.relativePath)
        let current = DocumentFingerprint(data: currentData)
        if current == transaction.candidate {
            let document = NoteDocument(
                relativePath: transaction.relativePath,
                rawContent: candidateContent
            )
            completeInterruptedSaveRecovery(transaction)
            return InterruptedSaveRecoveryRestoreCommit(
                document: document,
                didReplaceSource: false
            )
        }
        guard current == transaction.expected else {
            throw VaultRepositoryError.conflict(
                expected: transaction.expected,
                current: current
            )
        }

        let result = try save(
            relativePath: transaction.relativePath,
            changeSet: .exactContent(candidateContent),
            expectedRevision: transaction.expected
        )
        completeInterruptedSaveRecovery(transaction)
        return InterruptedSaveRecoveryRestoreCommit(
            document: result.document,
            didReplaceSource: true
        )
    }

    /// Completes retained transaction evidence only after Core rechecks that
    /// the canonical source is still the exact pre-write revision. This is the
    /// no-write branch of recovery reconciliation; it never applies candidate
    /// bytes or accepts a third-party revision.
    public func abandonInterruptedSaveRecovery(
        _ recovery: InterruptedSaveRecovery
    ) throws {
        let transaction = try retainedMutation(matching: recovery)
        let current = DocumentFingerprint(data: try readSource(
            relativePath: transaction.relativePath
        ))
        guard current == transaction.expected else {
            throw VaultRepositoryError.conflict(
                expected: transaction.expected,
                current: current
            )
        }
        try recoveryLedger.completeMutation(transaction)
    }

    /// Remaps machine-local pre-write evidence after a stable-identity move.
    public func migrateRecoveryLedger(
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) throws {
        try validateMarkdownRelativePath(sourceRelativePath)
        try validateMarkdownRelativePath(destinationRelativePath)
        guard sourceRelativePath != destinationRelativePath else { return }
        try recoveryLedger.remapRetainedTransactions(
            from: sourceRelativePath,
            to: destinationRelativePath
        )
    }

    private func retainedMutation(
        matching recovery: InterruptedSaveRecovery
    ) throws -> PrewriteRecoveryLedger.MutationTransaction {
        guard recovery.id.vaultID == identity.id else {
            throw VaultRepositoryError.recoveryEntryNotFound(recovery.id.transactionID)
        }
        let transaction = try recoveryLedger.retainedMutation(
            id: recovery.id.transactionID
        )
        guard transaction.relativePath == recovery.relativePath,
              transaction.expected == recovery.expectedRevision,
              transaction.candidate == recovery.candidateRevision,
              transaction.createdAt == recovery.createdAt,
              transaction.retainedReason == recovery.retainedReason else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The interrupted save record changed after it was presented. Refresh Recovery before continuing."
            )
        }
        return transaction
    }

    private func interruptedSaveRecovery(
        for transaction: PrewriteRecoveryLedger.MutationTransaction
    ) throws -> InterruptedSaveRecovery {
        guard let recovery = try interruptedSaveRecoveries().first(where: {
            $0.id.transactionID == transaction.id
        }) else {
            throw VaultRepositoryError.recoveryLedgerUnavailable(
                "The retained interrupted-save transaction could not be read back."
            )
        }
        return recovery
    }

    private func knownNotWrittenOutcome(for error: Error) -> VaultSaveOutcome? {
        guard let repositoryError = error as? VaultRepositoryError else {
            return nil
        }
        switch repositoryError {
        case .conflict(_, let current):
            return .notWritten(.conflict(current))
        case .atomicCommitUnsupported(let reason):
            return .notWritten(.atomicCommitUnsupported(reason))
        case .invalidFrontmatter(let reason):
            return .notWritten(.invalidFrontmatter(reason))
        case .invalidRelativePath,
             .outsideVault,
             .fileDoesNotExist,
             .fileAlreadyExists,
             .notRegularFile,
             .markdownRequired,
             .readbackMismatch,
             .recoveryEntryNotFound,
             .recoveryPathConflict,
             .recoveryLedgerUnavailable,
             .pathCollision,
             .writeFailed,
             .commitUncertain,
             .recoveryRequired:
            return nil
        }
    }

    private func legacySaveError(
        for reason: VaultSaveNotWrittenReason,
        expectedRevision: DocumentFingerprint
    ) -> VaultRepositoryError {
        switch reason {
        case .conflict(let current):
            .conflict(expected: expectedRevision, current: current)
        case .targetIdentityChanged:
            .notRegularFile("The path no longer belongs to the authorized portable Note identity.")
        case .invalidFrontmatter(let message):
            .invalidFrontmatter(message)
        case .atomicCommitUnsupported(let message):
            .atomicCommitUnsupported(message)
        }
    }

    private func interruptedSaveSourceState(
        _ transaction: PrewriteRecoveryLedger.MutationTransaction
    ) -> InterruptedSaveRecoverySourceState {
        do {
            let observed = DocumentFingerprint(
                data: try readSource(relativePath: transaction.relativePath)
            )
            if observed == transaction.expected { return .expectedRevision }
            if observed == transaction.candidate { return .candidateRevision }
            return .changed(observed)
        } catch VaultRepositoryError.fileDoesNotExist {
            return .missing
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// Redundant machine-local bookkeeping is never a Document state after a
    /// proven source commit.
    private func completeInterruptedSaveRecovery(
        _ transaction: PrewriteRecoveryLedger.MutationTransaction
    ) {
        try? recoveryLedger.completeMutation(transaction)
    }

    private func readSource(relativePath: String) throws -> Data {
        try descriptorAccess.read(markdownRelativePath(relativePath))
    }

    private static func sourceVersion(
        status: stat,
        fingerprint: DocumentFingerprint
    ) -> SourceVersion {
        SourceVersion(
            fingerprint: fingerprint,
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            byteCount: Int(status.st_size),
            modificationNanoseconds: nanoseconds(status.st_mtimespec),
            statusChangeNanoseconds: nanoseconds(status.st_ctimespec)
        )
    }

    private static func fileMetadata(status: stat) -> WorkspaceFileMetadata {
        WorkspaceFileMetadata(
            byteCount: Int(status.st_size),
            creationDate: date(status.st_birthtimespec),
            modificationDate: date(status.st_mtimespec)
        )
    }

    private static func date(_ value: timespec) -> Date? {
        guard value.tv_sec > 0 || value.tv_nsec > 0 else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(value.tv_sec)
                + TimeInterval(value.tv_nsec) / 1_000_000_000
        )
    }

    private static func matches(status: stat, version: SourceVersion) -> Bool {
        UInt64(status.st_dev) == version.device
            && UInt64(status.st_ino) == version.inode
            && Int(status.st_size) == version.byteCount
            && nanoseconds(status.st_mtimespec) == version.modificationNanoseconds
            && nanoseconds(status.st_ctimespec) == version.statusChangeNanoseconds
    }

    private static func sameFileState(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }

    private static func nanoseconds(_ time: timespec) -> Int64 {
        Int64(time.tv_sec) * 1_000_000_000 + Int64(time.tv_nsec)
    }

    private func filePresence(relativePath: String) throws -> FilePresence {
        try descriptorAccess.presence(markdownRelativePath(relativePath))
    }

    private func existingFileURL(relativePath: String) throws -> URL {
        try validateMarkdownRelativePath(relativePath)
        let candidate = canonicalRoot.appendingPathComponent(relativePath).standardizedFileURL
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw VaultRepositoryError.fileDoesNotExist(relativePath)
        }
        let candidateValues = try candidate.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard candidateValues.isSymbolicLink != true else {
            throw VaultRepositoryError.notRegularFile(relativePath)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard resolved.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw VaultRepositoryError.notRegularFile(relativePath)
        }
        return resolved
    }

    private func existingFolderURL(path: VaultRelativeFolderPath) throws -> URL {
        let candidate = try pathResolver.unresolvedURL(for: path)
        guard fileManager.fileExists(atPath: candidate.path) else {
            throw VaultRepositoryError.fileDoesNotExist(path.rawValue)
        }
        let directValues = try candidate.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isDirectoryKey,
        ])
        guard directValues.isSymbolicLink != true,
              directValues.isDirectory == true else {
            throw VaultRepositoryError.notRegularFile(path.rawValue)
        }
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard resolved.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(path.rawValue)
        }
        return candidate
    }

    private func prospectiveNewFolderURL(
        path: VaultRelativeFolderPath,
        ignoring source: VaultRelativeFolderPath?,
        createMissingParents: Bool
    ) throws -> URL {
        let candidate = try pathResolver.unresolvedURL(for: path)
        let sourceURL = try source.map(pathResolver.unresolvedURL(for:))
        if fileManager.fileExists(atPath: candidate.path) {
            let candidateValues = try candidate.resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .isSymbolicLinkKey,
            ])
            let sourceValues = try sourceURL?.resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .isSymbolicLinkKey,
            ])
            guard source != nil,
                  candidateValues.isSymbolicLink != true,
                  sourceValues?.isSymbolicLink != true,
                  candidateValues.fileResourceIdentifier as? AnyHashable
                    == sourceValues?.fileResourceIdentifier as? AnyHashable else {
                throw VaultRepositoryError.fileAlreadyExists(path.rawValue)
            }
        }
        try pathResolver.validateNoCollision(
            for: path,
            ignoring: source,
            fileManager: fileManager
        )

        let parent = candidate.deletingLastPathComponent()
        if createMissingParents {
            try ensureSafeDirectory(parent)
        }
        guard fileManager.fileExists(atPath: parent.path) else {
            throw VaultRepositoryError.fileDoesNotExist(
                VaultPath.relativePath(for: parent, in: canonicalRoot) ?? parent.path
            )
        }
        let directValues = try parent.resourceValues(forKeys: [
            .isSymbolicLinkKey,
            .isDirectoryKey,
        ])
        guard directValues.isSymbolicLink != true,
              directValues.isDirectory == true else {
            throw VaultRepositoryError.outsideVault(path.rawValue)
        }
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard resolvedParent.path == canonicalRoot.path
                || resolvedParent.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(path.rawValue)
        }
        return candidate
    }

    private func preflightFolderDocuments(
        in folder: VaultRelativeFolderPath,
        expectedDocuments: [String: DocumentFingerprint]
    ) throws -> [NoteDocument] {
        let prefix = folder.rawValue + "/"
        let currentPaths = try markdownRelativePaths()
            .filter { $0.hasPrefix(prefix) }
        guard Set(currentPaths) == Set(expectedDocuments.keys) else {
            throw VaultRepositoryError.commitUncertain(
                "The folder's Markdown inventory changed before the move."
            )
        }
        return try currentPaths.map { relativePath in
            let document = try load(relativePath: relativePath)
            guard let expected = expectedDocuments[relativePath],
                  document.fingerprint == expected else {
                throw VaultRepositoryError.conflict(
                    expected: expectedDocuments[relativePath] ?? document.fingerprint,
                    current: document.fingerprint
                )
            }
            return document
        }
    }

    private func newFileURL(relativePath: String) throws -> URL {
        let candidate = try prospectiveNewFileURL(relativePath: relativePath)

        let parent = candidate.deletingLastPathComponent()
        try ensureSafeDirectory(parent)
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard resolvedParent.path == canonicalRoot.path || resolvedParent.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        return candidate
    }

    private func prospectiveNewFileURL(relativePath: String) throws -> URL {
        let typedPath = try markdownRelativePath(relativePath)
        let candidate = try pathResolver.unresolvedURL(for: typedPath)
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        guard !fileManager.fileExists(atPath: candidate.path) else {
            throw VaultRepositoryError.fileAlreadyExists(relativePath)
        }
        try pathResolver.validateNoCollision(for: typedPath, fileManager: fileManager)

        // Find the nearest existing ancestor without creating the missing
        // suffix. A symlinked ancestor is never an authorized destination.
        var ancestor = candidate.deletingLastPathComponent()
        while ancestor.path != canonicalRoot.path,
              !fileManager.fileExists(atPath: ancestor.path) {
            ancestor.deleteLastPathComponent()
        }
        guard fileManager.fileExists(atPath: ancestor.path) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        let directValues = try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard directValues.isSymbolicLink != true else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        let resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == canonicalRoot.path || resolved.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else {
            throw VaultRepositoryError.notRegularFile(relativePath)
        }
        return candidate
    }

    private func validateMarkdownRelativePath(_ relativePath: String) throws {
        _ = try markdownRelativePath(relativePath)
    }

    private func markdownRelativePath(_ relativePath: String) throws -> MarkdownRelativePath {
        do {
            return try MarkdownRelativePath(relativePath)
        } catch MarkdownRelativePathError.markdownRequired {
            throw VaultRepositoryError.markdownRequired(relativePath)
        } catch {
            throw VaultRepositoryError.invalidRelativePath(relativePath)
        }
    }

    private func folderRelativePath(_ relativePath: String) throws -> VaultRelativeFolderPath {
        do {
            return try VaultRelativeFolderPath(relativePath)
        } catch {
            throw VaultRepositoryError.invalidRelativePath(relativePath)
        }
    }

    private func ensureSafeDirectory(_ directory: URL) throws {
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        let standardized = directory.standardizedFileURL
        guard standardized.path == canonicalRoot.path || standardized.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(directory.path)
        }
        if fileManager.fileExists(atPath: standardized.path) {
            let directValues = try standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard directValues.isSymbolicLink != true else {
                throw VaultRepositoryError.outsideVault(directory.path)
            }
            let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path == canonicalRoot.path || resolved.path.hasPrefix(rootPath) else {
                throw VaultRepositoryError.outsideVault(directory.path)
            }
            let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                throw VaultRepositoryError.notRegularFile(directory.path)
            }
            return
        }
        try ensureSafeDirectory(standardized.deletingLastPathComponent())
        try fileManager.createDirectory(at: standardized, withIntermediateDirectories: false)
    }

    private func removeEmptyParentDirectories(startingAt directory: URL) {
        var current = directory.standardizedFileURL
        while current.path != canonicalRoot.path {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current.path), contents.isEmpty else { return }
            try? fileManager.removeItem(at: current)
            current.deleteLastPathComponent()
        }
    }

}
