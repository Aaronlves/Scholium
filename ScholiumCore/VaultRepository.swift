import Foundation
import ScholiumContracts

public actor VaultRepository {
    public let identity: VaultIdentity
    public let vaultRole: VaultRole
    public let vaultURL: URL
    public let storageURL: URL

    private let canonicalRoot: URL
    private let pathResolver: VaultPathResolver
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
        self.pathResolver = try VaultPathResolver(rootURL: vaultURL)
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
        let fileURL = try existingFileURL(relativePath: relativePath)
        let data = try Data(contentsOf: fileURL)
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return NoteDocument(relativePath: relativePath, rawContent: content)
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
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in false }
        ) else { return [] }
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
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func save(
        relativePath: String,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) throws -> SaveResult {
        let fileURL = try existingFileURL(relativePath: relativePath)
        let currentData = try Data(contentsOf: fileURL)
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
            let recheckedData = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
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
            let readback = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
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
                let observed = try? Data(contentsOf: fileURL)
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
            let readback = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
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
        let sourceURL = try existingFileURL(relativePath: relativePath)
        let data = try Data(contentsOf: sourceURL)
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
        let currentData = try Data(contentsOf: sourceURL)
        let currentFingerprint = DocumentFingerprint(data: currentData)
        guard currentFingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: currentFingerprint)
        }
        let destinationURL = try newFileURL(relativePath: destinationRelativePath)
        let snapshot = try prepareSnapshot(relativePath: relativePath, data: currentData)
        do {
            let recheckedData = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: recheckedFingerprint)
            }
            guard !fileManager.fileExists(atPath: destinationURL.path) else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.fileAlreadyExists(destinationRelativePath)
            }
            try mutationCoordinator.move(
                source: markdownRelativePath(relativePath),
                destination: markdownRelativePath(destinationRelativePath),
                expected: currentData
            )
            let readback = try Data(contentsOf: try existingFileURL(relativePath: destinationRelativePath))
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
            if fileManager.fileExists(atPath: sourceURL.path) {
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
        let data = try Data(contentsOf: fileURL)
        let current = DocumentFingerprint(data: data)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        let snapshot = try prepareSnapshot(relativePath: relativePath, data: data)
        var sourceWasDeleted = false
        do {
            let recheckedData = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
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
        let fileURL = try existingFileURL(relativePath: relativePath)
        let data = try Data(contentsOf: fileURL)
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
        let current = DocumentFingerprint(data: try Data(contentsOf: fileURL))
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
        if let existing = try? load(relativePath: prepared.relativePath) {
            let current = existing.fingerprint
            guard current == prepared.fingerprint else {
                throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
            }
            try discardCommittedSnapshot(prepared.recoveryReference)
            return
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
        let observed = DocumentFingerprint(data: try Data(contentsOf: try existingFileURL(
            relativePath: prepared.relativePath
        )))
        guard observed == prepared.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(expected: prepared.fingerprint, current: observed)
        }
        try discardCommittedSnapshot(prepared.recoveryReference)
    }

    /// Makes a prepared deletion permanent by removing all path-keyed recovery
    /// evidence, including the temporary entry. Repeating it is safe.
    func finalizePreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        let candidate = try prospectiveNewFileURL(relativePath: prepared.relativePath)
        if fileManager.fileExists(atPath: candidate.path) {
            let current = DocumentFingerprint(data: try Data(contentsOf: try existingFileURL(
                relativePath: prepared.relativePath
            )))
            throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
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
        let fileURL = try existingFileURL(relativePath: relativePath)
        let data = try Data(contentsOf: fileURL)
        let current = DocumentFingerprint(data: data)
        guard current == createdRevision else {
            throw VaultRepositoryError.conflict(expected: createdRevision, current: current)
        }
        let recheckedURL = try existingFileURL(relativePath: relativePath)
        let recheckedData = try Data(contentsOf: recheckedURL)
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

    func recoveryEntries(relativePath: String) -> [PrewriteRecoveryReference] {
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
