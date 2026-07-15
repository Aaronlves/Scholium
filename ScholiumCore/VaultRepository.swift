import CryptoKit
import Foundation
import ScholiumContracts

public actor VaultRepository {
    private struct VersionIndex: Codable {
        var entries: [String: [VaultVersion]]
    }

    public let identity: VaultIdentity
    public let vaultRole: VaultRole
    public let vaultURL: URL
    public let storageURL: URL

    private let canonicalRoot: URL
    private let versionsURL: URL
    private let indexURL: URL
    private var versionIndex: VersionIndex
    private let versionIndexLoadFailure: String?
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
        self.storageURL = applicationSupportURL
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(identity.id.uuidString, isDirectory: true)
        self.versionsURL = storageURL.appendingPathComponent("versions", isDirectory: true)
        self.indexURL = versionsURL.appendingPathComponent("index.json")
        try fileManager.createDirectory(at: versionsURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL, options: [.mappedIfSafe])
                let decoded = try JSONDecoder().decode(VersionIndex.self, from: data)
                self.versionIndex = decoded
                self.versionIndexLoadFailure = Self.versionIndexValidationError(decoded)
            } catch {
                self.versionIndex = VersionIndex(entries: [:])
                self.versionIndexLoadFailure = error.localizedDescription
            }
        } else {
            self.versionIndex = VersionIndex(entries: [:])
            self.versionIndexLoadFailure = nil
        }
    }

    public func versionHistoryHealthError() -> String? {
        versionIndexLoadFailure.map {
            VaultRepositoryError.versionHistoryUnavailable($0).localizedDescription
        }
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

        let snapshot = try prepareSnapshot(relativePath: relativePath, data: currentData)
        do {
            let recheckedData = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
            let recheckedFingerprint = DocumentFingerprint(data: recheckedData)
            guard recheckedFingerprint == expectedRevision else {
                try discardPreparedSnapshot(snapshot)
                throw VaultRepositoryError.conflict(expected: expectedRevision, current: recheckedFingerprint)
            }
            try Data(updatedContent.utf8).write(to: fileURL, options: .atomic)
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
        } catch {
            if !(error is VaultRepositoryError) {
                let observed = try? Data(contentsOf: fileURL)
                if observed.map(DocumentFingerprint.init(data:)) == currentFingerprint {
                    try? discardPreparedSnapshot(snapshot)
                } else {
                    try? commitPreparedSnapshot(snapshot)
                }
            }
            throw error
        }
        return SaveResult(document: updated, snapshot: snapshot)
    }

    /// Creates a new Markdown note without replacing an existing path.
    public func create(relativePath: String, content: String) throws -> NoteDocument {
        let proposed = NoteDocument(relativePath: relativePath, rawContent: content)
        if proposed.rawFrontmatter != nil, !proposed.validationWarnings.isEmpty {
            throw VaultRepositoryError.invalidFrontmatter(proposed.validationWarnings.joined(separator: "\n"))
        }
        let destination = try newFileURL(relativePath: relativePath)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".scholium-create-\(UUID().uuidString).tmp")
        do {
            try Data(content.utf8).write(to: temporary, options: .atomic)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw VaultRepositoryError.fileAlreadyExists(relativePath)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            let readback = try Data(contentsOf: try existingFileURL(relativePath: relativePath))
            let readbackFingerprint = DocumentFingerprint(data: readback)
            guard readbackFingerprint == proposed.fingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: proposed.fingerprint,
                    current: readbackFingerprint
                )
            }
            return NoteDocument(relativePath: relativePath, rawContent: content)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
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
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
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
                relativePath: destinationRelativePath,
                snapshot: snapshot
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

    /// Permanently removes a note and every repository-owned recoverable
    /// version of that path. A provisional snapshot protects the mutation
    /// only while it is in flight and is never committed to Note History.
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
            try fileManager.removeItem(at: fileURL)
            sourceWasDeleted = true
            try purgeVersionHistory(relativePath: relativePath)
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
                try? purgeVersionHistory(relativePath: relativePath)
                try? discardPreparedSnapshot(snapshot)
            }
            throw error
        }
    }

    /// Creates a committed recovery version before a higher-level multi-file
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
                recoveryVersion: version
            )
        } catch {
            try? discardPreparedSnapshot(version)
            throw error
        }
    }

    /// Removes the prepared source only after a fresh authorization and
    /// fingerprint check. The recovery version remains committed until the
    /// enclosing transaction either rolls back or finalizes.
    func applyPreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        let fileURL = try existingFileURL(relativePath: prepared.relativePath)
        let current = DocumentFingerprint(data: try Data(contentsOf: fileURL))
        guard current == prepared.fingerprint else {
            throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
        }
        try fileManager.removeItem(at: fileURL)
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
            try discardCommittedSnapshot(prepared.recoveryVersion)
            return
        }

        let candidate = try prospectiveNewFileURL(relativePath: prepared.relativePath)
        let recoveryURL = versionFileURL(prepared.recoveryVersion)
        let data = try Data(contentsOf: recoveryURL)
        guard DocumentFingerprint(data: data) == prepared.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(
                expected: prepared.fingerprint,
                current: DocumentFingerprint(data: data)
            )
        }
        try ensureSafeDirectory(candidate.deletingLastPathComponent())
        try data.write(to: candidate, options: .atomic)
        let observed = DocumentFingerprint(data: try Data(contentsOf: try existingFileURL(
            relativePath: prepared.relativePath
        )))
        guard observed == prepared.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(expected: prepared.fingerprint, current: observed)
        }
        try discardCommittedSnapshot(prepared.recoveryVersion)
    }

    /// Makes a prepared deletion permanent by removing all path-keyed history,
    /// including the temporary recovery version. Repeating it is safe.
    func finalizePreparedPermanentDeletion(_ prepared: PreparedPermanentDeletion) throws {
        let candidate = try prospectiveNewFileURL(relativePath: prepared.relativePath)
        if fileManager.fileExists(atPath: candidate.path) {
            let current = DocumentFingerprint(data: try Data(contentsOf: try existingFileURL(
                relativePath: prepared.relativePath
            )))
            throw VaultRepositoryError.conflict(expected: prepared.fingerprint, current: current)
        }
        try purgeVersionHistory(relativePath: prepared.relativePath)
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
        let rechecked = DocumentFingerprint(data: try Data(contentsOf: recheckedURL))
        guard rechecked == createdRevision else {
            throw VaultRepositoryError.conflict(expected: createdRevision, current: rechecked)
        }
        try fileManager.removeItem(at: recheckedURL)
        removeEmptyParentDirectories(startingAt: recheckedURL.deletingLastPathComponent())
    }

    public func versions(relativePath: String) -> [VaultVersion] {
        (versionIndex.entries[relativePath] ?? []).sorted { $0.sequence > $1.sequence }
    }

    /// Preserves path-keyed Note History after a confirmed identity move.
    ///
    /// Version blobs are copied to their new path-derived directory before the
    /// index is atomically replaced. The original blobs remain in place until
    /// the new index is durable, so interruption before or during the index
    /// write leaves the previous history readable. A destination with unrelated
    /// history is rejected rather than merged into the confirmed note.
    public func migrateVersionHistory(
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) throws {
        try requireVersionHistory()
        try validateMarkdownRelativePath(sourceRelativePath)
        try validateMarkdownRelativePath(destinationRelativePath)
        guard sourceRelativePath != destinationRelativePath else { return }
        let sourceEntries = versionIndex.entries[sourceRelativePath] ?? []
        guard !sourceEntries.isEmpty else { return }
        if let destinationEntries = versionIndex.entries[destinationRelativePath],
           !destinationEntries.isEmpty {
            let sourceIDs = Set(sourceEntries.map(\.id))
            let destinationIDs = Set(destinationEntries.map(\.id))
            if sourceIDs == destinationIDs {
                var updatedIndex = versionIndex
                updatedIndex.entries[sourceRelativePath] = nil
                try persistIndex(updatedIndex)
                versionIndex = updatedIndex
                return
            }
            throw VaultRepositoryError.versionHistoryPathConflict(destinationRelativePath)
        }

        let destinationDirectory = versionsURL.appendingPathComponent(
            Self.pathDigest(destinationRelativePath),
            isDirectory: true
        )
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let migrated = try sourceEntries.map { version -> VaultVersion in
            let sourceURL = versionFileURL(version)
            let destinationURL = destinationDirectory
                .appendingPathComponent(version.id.uuidString + ".md", isDirectory: false)
            let sourceData = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            guard DocumentFingerprint(data: sourceData) == version.fingerprint else {
                throw VaultRepositoryError.readbackMismatch(
                    expected: version.fingerprint,
                    current: DocumentFingerprint(data: sourceData)
                )
            }
            if fileManager.fileExists(atPath: destinationURL.path) {
                let existing = try Data(contentsOf: destinationURL, options: [.mappedIfSafe])
                guard existing == sourceData else {
                    throw VaultRepositoryError.versionHistoryPathConflict(destinationRelativePath)
                }
            } else {
                try sourceData.write(to: destinationURL, options: .atomic)
            }
            return VaultVersion(
                id: version.id,
                relativePath: destinationRelativePath,
                sequence: version.sequence,
                createdAt: version.createdAt,
                fingerprint: version.fingerprint
            )
        }

        var updatedIndex = versionIndex
        updatedIndex.entries[sourceRelativePath] = nil
        updatedIndex.entries[destinationRelativePath] = migrated
        try persistIndex(updatedIndex)
        versionIndex = updatedIndex

        let sourceDirectory = versionsURL.appendingPathComponent(
            Self.pathDigest(sourceRelativePath),
            isDirectory: true
        )
        if sourceDirectory != destinationDirectory,
           fileManager.fileExists(atPath: sourceDirectory.path) {
            try? fileManager.removeItem(at: sourceDirectory)
        }
    }

    public func content(versionID: UUID) throws -> String {
        try requireVersionHistory()
        guard let version = versionIndex.entries.values.joined().first(where: { $0.id == versionID }) else {
            throw VaultRepositoryError.versionNotFound(versionID)
        }
        let data = try Data(contentsOf: versionFileURL(version))
        let observed = DocumentFingerprint(data: data)
        guard observed == version.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(
                expected: version.fingerprint,
                current: observed
            )
        }
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return content
    }

    public func restore(
        versionID: UUID,
        expectedRevision: DocumentFingerprint
    ) throws -> SaveResult {
        guard let version = versionIndex.entries.values.joined().first(where: { $0.id == versionID }) else {
            throw VaultRepositoryError.versionNotFound(versionID)
        }
        let content = try self.content(versionID: versionID)
        return try save(relativePath: version.relativePath, changeSet: .exactContent(content), expectedRevision: expectedRevision)
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
        try validateMarkdownRelativePath(relativePath)
        let candidate = canonicalRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw VaultRepositoryError.outsideVault(relativePath)
        }
        guard !fileManager.fileExists(atPath: candidate.path) else {
            throw VaultRepositoryError.fileAlreadyExists(relativePath)
        }

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
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("") else {
            throw VaultRepositoryError.invalidRelativePath(relativePath)
        }
        guard URL(fileURLWithPath: relativePath).pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw VaultRepositoryError.markdownRequired(relativePath)
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

    private func prepareSnapshot(relativePath: String, data: Data) throws -> VaultVersion {
        try requireVersionHistory()
        let entries = versionIndex.entries[relativePath] ?? []
        let version = VaultVersion(
            id: UUID(),
            relativePath: relativePath,
            sequence: (entries.map(\.sequence).max() ?? 0) + 1,
            createdAt: Date(),
            fingerprint: DocumentFingerprint(data: data)
        )
        let pending = versionsURL.appendingPathComponent("pending", isDirectory: true)
        try fileManager.createDirectory(at: pending, withIntermediateDirectories: true)
        try data.write(to: preparedVersionFileURL(version), options: .atomic)
        return version
    }

    private func commitPreparedSnapshot(_ version: VaultVersion) throws {
        try requireVersionHistory()
        var entries = (versionIndex.entries[version.relativePath] ?? [])
            .filter { $0.id != version.id }
        let directory = versionsURL.appendingPathComponent(Self.pathDigest(version.relativePath), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pendingURL = preparedVersionFileURL(version)
        let committedURL = versionFileURL(version)
        if fileManager.fileExists(atPath: pendingURL.path) {
            try fileManager.moveItem(at: pendingURL, to: committedURL)
        }
        entries.append(version)
        let removed: [VaultVersion]
        if entries.count > 10 {
            removed = Array(entries.prefix(entries.count - 10))
            entries.removeFirst(entries.count - 10)
        } else {
            removed = []
        }
        var updatedIndex = versionIndex
        updatedIndex.entries[version.relativePath] = entries
        try persistIndex(updatedIndex)
        versionIndex = updatedIndex
        for old in removed { try? fileManager.removeItem(at: versionFileURL(old)) }
    }

    private func discardPreparedSnapshot(_ version: VaultVersion) throws {
        let url = preparedVersionFileURL(version)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func discardCommittedSnapshot(_ version: VaultVersion) throws {
        var updatedIndex = versionIndex
        var entries = updatedIndex.entries[version.relativePath] ?? []
        entries.removeAll { $0.id == version.id }
        updatedIndex.entries[version.relativePath] = entries.isEmpty ? nil : entries
        try persistIndex(updatedIndex)
        versionIndex = updatedIndex
        let url = versionFileURL(version)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path),
           (try fileManager.contentsOfDirectory(atPath: directory.path)).isEmpty {
            try fileManager.removeItem(at: directory)
        }
    }

    private func purgeVersionHistory(relativePath: String) throws {
        try requireVersionHistory()
        let entries = versionIndex.entries[relativePath] ?? []
        var updatedIndex = versionIndex
        updatedIndex.entries[relativePath] = nil
        try persistIndex(updatedIndex)
        versionIndex = updatedIndex

        for version in entries {
            let url = versionFileURL(version)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        let directory = versionsURL.appendingPathComponent(
            Self.pathDigest(relativePath),
            isDirectory: true
        )
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func versionFileURL(_ version: VaultVersion) -> URL {
        versionsURL
            .appendingPathComponent(Self.pathDigest(version.relativePath), isDirectory: true)
            .appendingPathComponent(version.id.uuidString + ".md")
    }

    private func preparedVersionFileURL(_ version: VaultVersion) -> URL {
        versionsURL
            .appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent(version.id.uuidString + ".md")
    }

    private func removeEmptyParentDirectories(startingAt directory: URL) {
        var current = directory.standardizedFileURL
        while current.path != canonicalRoot.path {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: current.path), contents.isEmpty else { return }
            try? fileManager.removeItem(at: current)
            current.deleteLastPathComponent()
        }
    }

    private func requireVersionHistory() throws {
        if let versionIndexLoadFailure {
            throw VaultRepositoryError.versionHistoryUnavailable(versionIndexLoadFailure)
        }
    }

    private func persistIndex(_ index: VersionIndex) throws {
        try requireVersionHistory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private static func pathDigest(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func versionIndexValidationError(_ index: VersionIndex) -> String? {
        var ids: Set<UUID> = []
        for (path, entries) in index.entries {
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty,
                  !path.hasPrefix("/"),
                  !components.contains(".."),
                  !components.contains(""),
                  URL(fileURLWithPath: path).pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
                return "The version index contains an invalid note path."
            }
            guard entries.count <= 10 else {
                return "The version index contains more than ten visible versions for \(path)."
            }
            for entry in entries {
                guard entry.relativePath == path else {
                    return "The version index contains a path mismatch for \(path)."
                }
                guard ids.insert(entry.id).inserted else {
                    return "The version index contains a duplicate version identity."
                }
            }
        }
        return nil
    }

    private static func lifecycleDestination(folder: String, relativePath: String) -> String {
        let components = relativePath.split(separator: "/")
        if components.first.map(String.init) == folder {
            return relativePath
        }
        return folder + "/" + relativePath
    }
}
