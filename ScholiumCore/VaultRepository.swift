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
        self.identity = identity
        self.vaultRole = vaultRole
        self.vaultURL = vaultURL.standardizedFileURL
        self.canonicalRoot = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        let pathResolver = try VaultPathResolver(rootURL: vaultURL)
        self.pathResolver = pathResolver
        self.descriptorAccess = VaultDescriptorAccess(rootURL: pathResolver.canonicalRoot)
        self.mutationCoordinator = VaultMutationCoordinator(resolver: pathResolver)
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
        fileMetadata: WorkspaceFileMetadata
    ) {
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
            Self.fileMetadata(status: loaded.1)
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

    /// Returns ordinary active Markdown paths. Set Aside and Trash are excluded
    /// unless the caller is explicitly presenting recovery content.
    public func markdownRelativePaths(includeLifecycle: Bool = false) throws -> [String] {
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
            if !includeLifecycle,
               relativePath.hasPrefix("Set Aside/") || relativePath.hasPrefix("Trash/") {
                if values.isDirectory == true { enumerator.skipDescendants() }
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
    public func folderRelativePaths(includeLifecycle: Bool = false) throws
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
            if !includeLifecycle,
               relativePath == "Set Aside" || relativePath.hasPrefix("Set Aside/")
                || relativePath == "Trash" || relativePath.hasPrefix("Trash/") {
                enumerator.skipDescendants()
                continue
            }
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
        _ = try existingFileURL(relativePath: relativePath)
        let currentData = try readSource(relativePath: relativePath)
        let currentFingerprint = DocumentFingerprint(data: currentData)
        guard currentFingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: currentFingerprint)
        }
        guard let currentContent = NoteDocument.decodeUTF8PreservingBOM(currentData) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        let current = NoteDocument(relativePath: relativePath, rawContent: currentContent)
        let updatedContent = try current.applying(changeSet, timestampKey: nil)
        let updated = NoteDocument(relativePath: relativePath, rawContent: updatedContent)
        if !updated.validationWarnings.isEmpty, updated.rawFrontmatter != nil {
            throw VaultRepositoryError.invalidFrontmatter(updated.validationWarnings.joined(separator: "\n"))
        }

        let candidateData = Data(updatedContent.utf8)
        let snapshot = try prepareSnapshot(relativePath: relativePath, data: currentData)
        let mutation: PrewriteRecoveryLedger.MutationTransaction
        do {
            mutation = try recoveryLedger.beginMutation(
                relativePath: relativePath,
                expected: currentData,
                candidate: candidateData
            )
        } catch {
            try? discardPreparedSnapshot(snapshot)
            throw error
        }
        do {
            let recheckedData = try readSource(relativePath: relativePath)
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: recheckedFingerprint)
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
                try commitPreparedSnapshot(snapshot)
                throw VaultRepositoryError.readbackMismatch(
                    expected: expectedFingerprint,
                    current: readbackFingerprint
                )
            }
            try commitPreparedSnapshot(snapshot)
            try? recoveryLedger.completeMutation(mutation)
        } catch {
            if case VaultRepositoryError.commitUncertain = error {
                try? commitPreparedSnapshot(snapshot)
                try? recoveryLedger.retainMutation(mutation, reason: error.localizedDescription)
            } else {
                let observed = try? readSource(relativePath: relativePath)
                if observed.map(DocumentFingerprint.init(data:)) == currentFingerprint {
                    try? discardPreparedSnapshot(snapshot)
                    try? recoveryLedger.completeMutation(mutation)
                } else {
                    try? commitPreparedSnapshot(snapshot)
                    try? recoveryLedger.retainMutation(mutation, reason: error.localizedDescription)
                }
            }
            throw error
        }
        return SaveResult(document: updated)
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
        let snapshot = try prepareSnapshot(relativePath: relativePath, data: currentData)
        do {
            let recheckedData = try readSource(relativePath: relativePath)
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: recheckedFingerprint)
            }
            guard try filePresence(relativePath: destinationRelativePath) == .absent else {
                try discardPreparedSnapshot(snapshot)
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
                try commitPreparedSnapshot(snapshot)
                throw VaultRepositoryError.readbackMismatch(
                    expected: currentFingerprint,
                    current: readbackFingerprint
                )
            }
            try commitPreparedSnapshot(snapshot)
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
            if (try? filePresence(relativePath: relativePath)) == .present {
                try? discardPreparedSnapshot(snapshot)
            } else {
                try? commitPreparedSnapshot(snapshot)
            }
            throw error
        }
    }

    public func setAside(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteMoveResult {
        try move(
            relativePath: relativePath,
            to: Self.lifecycleDestination(folder: "Set Aside", relativePath: relativePath),
            expectedRevision: expectedRevision
        )
    }

    public func moveToTrash(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteMoveResult {
        try move(
            relativePath: relativePath,
            to: Self.lifecycleDestination(folder: "Trash", relativePath: relativePath),
            expectedRevision: expectedRevision
        )
    }

    /// Permanently removes a note and every repository-owned recovery entry
    /// for that path. A provisional entry protects the mutation only while it
    /// is in flight and is never exposed as a delivery-facing history item.
    public func deletePermanently(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteDeletionResult {
        let fileURL = try existingFileURL(relativePath: relativePath)
        let data = try readSource(relativePath: relativePath)
        let current = DocumentFingerprint(data: data)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        let snapshot = try prepareSnapshot(relativePath: relativePath, data: data)
        var sourceWasDeleted = false
        do {
            let recheckedData = try readSource(relativePath: relativePath)
            let rechecked = DocumentFingerprint(data: recheckedData)
            guard rechecked == expectedRevision else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: rechecked)
            }
            try mutationCoordinator.delete(
                path: markdownRelativePath(relativePath),
                expected: data
            )
            sourceWasDeleted = true
            try purgeRecoveryEntries(relativePath: relativePath)
            try discardPreparedSnapshot(snapshot)
            removeEmptyParentDirectories(startingAt: fileURL.deletingLastPathComponent())
            return NoteDeletionResult(
                relativePath: relativePath,
                fingerprint: current
            )
        } catch {
            if !sourceWasDeleted {
                try? discardPreparedSnapshot(snapshot)
            } else {
                // Permanent deletion must never publish a new recovery copy.
                // Retry cleanup best-effort before surfacing the failure.
                try? purgeRecoveryEntries(relativePath: relativePath)
                try? discardPreparedSnapshot(snapshot)
            }
            throw error
        }
    }

    /// Creates a committed recovery entry before a higher-level multi-file
    /// deletion starts. The source remains untouched until `apply` repeats the
    /// path and revision checks. A durable coordinator journal owns the token.
    func preparePermanentDeletion(
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) throws -> PreparedPermanentDeletion {
        _ = try existingFileURL(relativePath: relativePath)
        let data = try readSource(relativePath: relativePath)
        let current = DocumentFingerprint(data: data)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        let version = try prepareSnapshot(relativePath: relativePath, data: data)
        do {
            try commitPreparedSnapshot(version)
            return PreparedPermanentDeletion(
                relativePath: relativePath,
                fingerprint: current,
                recoveryReference: version
            )
        } catch {
            try? discardPreparedSnapshot(version)
            throw error
        }
    }

    /// Removes the prepared source only after a fresh authorization and
    /// fingerprint check. The recovery entry remains committed until the
    /// enclosing transaction either rolls back or finalizes.
    func applyPreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        let fileURL = try existingFileURL(relativePath: prepared.relativePath)
        let current = DocumentFingerprint(data: try readSource(
            relativePath: prepared.relativePath
        ))
        guard current == prepared.fingerprint else {
            throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
        }
        try mutationCoordinator.delete(
            path: markdownRelativePath(prepared.relativePath),
            expected: try recoveryLedger.content(entryID: prepared.recoveryReference.id)
        )
        removeEmptyParentDirectories(startingAt: fileURL.deletingLastPathComponent())
    }

    /// Restores exact prepared bytes without replacing a concurrently recreated
    /// path. This is idempotent when the original bytes already exist.
    func rollbackPreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        switch try filePresence(relativePath: prepared.relativePath) {
        case .present:
            let existing = try load(relativePath: prepared.relativePath)
            let current = existing.fingerprint
            guard current == prepared.fingerprint else {
                throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
            }
            try discardCommittedSnapshot(prepared.recoveryReference)
            return
        case .absent:
            break
        case .inaccessible(let code):
            throw VaultRepositoryError.commitUncertain(
                "Rollback destination presence could not be verified (errno \(code))."
            )
        }

        let candidate = try prospectiveNewFileURL(relativePath: prepared.relativePath)
        let data = try recoveryLedger.content(entryID: prepared.recoveryReference.id)
        guard DocumentFingerprint(data: data) == prepared.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(
                expected: prepared.fingerprint,
                current: DocumentFingerprint(data: data)
            )
        }
        try ensureSafeDirectory(candidate.deletingLastPathComponent())
        try mutationCoordinator.create(
            path: markdownRelativePath(prepared.relativePath),
            data: data
        )
        let observed = DocumentFingerprint(data: try readSource(
            relativePath: prepared.relativePath
        ))
        guard observed == prepared.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(expected: prepared.fingerprint, current: observed)
        }
        try discardCommittedSnapshot(prepared.recoveryReference)
    }

    /// Makes a prepared deletion permanent by removing all path-keyed recovery
    /// evidence, including the temporary entry. Repeating it is safe.
    func finalizePreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        switch try filePresence(relativePath: prepared.relativePath) {
        case .present:
            let current = DocumentFingerprint(data: try readSource(
                relativePath: prepared.relativePath
            ))
            throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
        case .absent:
            break
        case .inaccessible(let code):
            throw VaultRepositoryError.commitUncertain(
                "Deletion finalization presence could not be verified (errno \(code))."
            )
        }
        try purgeRecoveryEntries(relativePath: prepared.relativePath)
    }

    /// Removes a file created by the same higher-level transaction when that
    /// transaction must roll back. It is intentionally module-internal and is
    /// bound to the exact fingerprint returned by `create`; ordinary deletion
    /// continues to use `deletePermanently` and its recovery snapshot.
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

    package func recoveryEntries(relativePath: String) -> [PrewriteRecoveryReference] {
        (try? recoveryLedger.entries(relativePath: relativePath)) ?? []
    }

    /// Remaps machine-local pre-write evidence after a stable-identity move.
    public func migrateRecoveryLedger(
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) throws {
        try validateMarkdownRelativePath(sourceRelativePath)
        try validateMarkdownRelativePath(destinationRelativePath)
        guard sourceRelativePath != destinationRelativePath else { return }
        let sourceEntries = try recoveryLedger.entries(relativePath: sourceRelativePath)
        guard !sourceEntries.isEmpty else { return }
        let destinationEntries = try recoveryLedger.entries(relativePath: destinationRelativePath)
        guard destinationEntries.isEmpty else {
            throw VaultRepositoryError.recoveryPathConflict(destinationRelativePath)
        }
        try recoveryLedger.remap(from: sourceRelativePath, to: destinationRelativePath)
    }

    func recoveryContent(entryID: UUID) throws -> String {
        let data = try recoveryLedger.content(entryID: entryID)
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return content
    }

    package func recoveryData(entryID: UUID) throws -> Data {
        try recoveryLedger.content(entryID: entryID)
    }

    package func pinSettledSnapshot(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) throws -> SettledRevisionSnapshotPinOutcome {
        guard note.vaultID == identity.id else {
            throw VaultRepositoryError.invalidRelativePath(note.relativePath)
        }
        _ = try existingFileURL(relativePath: note.relativePath)
        let data = try readSource(relativePath: note.relativePath)
        let observed = DocumentFingerprint(data: data)
        guard observed == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: observed
            )
        }
        let pinned = try recoveryLedger.pinSettled(
            relativePath: note.relativePath,
            noteID: noteID,
            data: data
        )
        return SettledRevisionSnapshotPinOutcome(
            snapshot: settledSnapshot(pinned.pin),
            wasCreated: pinned.wasCreated
        )
    }

    public func settledSnapshots(noteID: UUID? = nil) throws -> [SettledRevisionSnapshot] {
        try recoveryLedger.settledPins(noteID: noteID).map(settledSnapshot)
    }

    package func settledSnapshotIDsToRemove(maximumCount: Int?) throws -> Set<UUID> {
        try recoveryLedger.settledSnapshotIDsToRemove(maximumCount: maximumCount)
    }

    @discardableResult
    package func removeSettledSnapshots(_ ids: Set<UUID>) throws -> Int {
        try recoveryLedger.removeSettledPins(ids)
    }

    private func settledSnapshot(
        _ pin: PrewriteRecoveryLedger.SettledPin
    ) -> SettledRevisionSnapshot {
        SettledRevisionSnapshot(
            id: pin.id,
            noteID: pin.noteID,
            note: VaultQualifiedNoteID(
                vaultID: identity.id,
                relativePath: pin.entry.relativePath
            ),
            sequence: pin.entry.sequence,
            createdAt: pin.createdAt,
            fingerprint: pin.entry.fingerprint
        )
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
        let currentPaths = try markdownRelativePaths(includeLifecycle: true)
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

    private func prepareSnapshot(relativePath: String, data: Data) throws -> PrewriteRecoveryReference {
        try recoveryLedger.prepare(relativePath: relativePath, data: data)
    }

    private func commitPreparedSnapshot(_ version: PrewriteRecoveryReference) throws {
        try recoveryLedger.commit(version)
    }

    private func discardPreparedSnapshot(_ version: PrewriteRecoveryReference) throws {
        try recoveryLedger.discard(version)
    }

    private func discardCommittedSnapshot(_ version: PrewriteRecoveryReference) throws {
        try recoveryLedger.discard(version)
    }

    private func purgeRecoveryEntries(relativePath: String) throws {
        try recoveryLedger.tombstoneAndPurge(relativePath: relativePath)
    }

    private func removeEmptyParentDirectories(startingAt directory: URL) {
        var current = directory.standardizedFileURL
        while current.path != canonicalRoot.path {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current.path), contents.isEmpty else { return }
            try? fileManager.removeItem(at: current)
            current.deleteLastPathComponent()
        }
    }

    private static func lifecycleDestination(folder: String, relativePath: String) -> String {
        let components = relativePath.split(separator: "/")
        if components.first.map(String.init) == folder {
            return relativePath
        }
        return folder + "/" + relativePath
    }
}
