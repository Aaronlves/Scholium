import Foundation
import ScholiumContracts
import ScholiumCore

private enum VaultSourceCatalogError: Error {
    case generationExhausted
}

struct VaultSourceCatalogMeasurement: Equatable, Sendable {
    let enumeratedFiles: Int
    let readFiles: Int
    let parsedDocuments: Int
    let projectedDocuments: Int
    let enumerationDuration: Duration
    let readDuration: Duration
    let parseDuration: Duration
    let projectionDuration: Duration
}

struct VaultSourceCatalogSnapshot: Sendable {
    let generation: UInt64
    let documents: [NoteDocument]
    let sourceVersions: [String: SourceVersion]
    let fileMetadata: [String: WorkspaceFileMetadata]
    let semantics: [String: MarkdownSemanticDocument]
    let searchProjections: [String: SearchDocumentProjection]
    let folders: [VaultRelativeFolderPath]
    let measurement: VaultSourceCatalogMeasurement
}

/// Rebuildable, descriptor-backed source projection for one pooled vault.
/// Markdown remains authority; cached documents and semantics can be deleted
/// and recreated without changing research data.
actor VaultSourceCatalog {
    private struct Record: Sendable {
        let document: NoteDocument
        let version: SourceVersion
        let fileMetadata: WorkspaceFileMetadata
        let semantic: MarkdownSemanticDocument?
        let searchProjection: SearchDocumentProjection?
    }

    private struct AuthorizedRecord: Sendable {
        let record: Record?
        let didRead: Bool
        let didParse: Bool
        let didProject: Bool
        let readDuration: Duration
        let parseDuration: Duration
        let projectionDuration: Duration
    }

    private let repository: VaultRepository
    private let vaultRole: VaultRole
    private var records: [String: Record] = [:]
    private var folders: [VaultRelativeFolderPath] = []
    private var generation: UInt64 = 0
    private var isInitialized = false
    private var needsFullReconcile = true
    private static let emptyMeasurement = VaultSourceCatalogMeasurement(
        enumeratedFiles: 0,
        readFiles: 0,
        parsedDocuments: 0,
        projectedDocuments: 0,
        enumerationDuration: .zero,
        readDuration: .zero,
        parseDuration: .zero,
        projectionDuration: .zero
    )
    private var lastMeasurement = VaultSourceCatalog.emptyMeasurement
    private var pendingMeasurement = VaultSourceCatalog.emptyMeasurement

    init(repository: VaultRepository, vaultRole: VaultRole) {
        self.repository = repository
        self.vaultRole = vaultRole
    }

    func snapshot(
        refreshFolders: Bool = true,
        consumePendingMeasurement: Bool = false
    ) async throws -> VaultSourceCatalogSnapshot {
        if !isInitialized || needsFullReconcile {
            try await reconcile()
        } else if refreshFolders {
            let observedFolders = try await repository.folderRelativePaths(
                includeLifecycle: true
            )
            if observedFolders != folders {
                try advanceGeneration()
                folders = observedFolders
            }
        }
        let measurement = consumePendingMeasurement
            ? pendingMeasurement
            : lastMeasurement
        if consumePendingMeasurement {
            pendingMeasurement = Self.emptyMeasurement
        }
        return makeSnapshot(measurement: measurement)
    }

    func reconcile() async throws {
        let clock = ContinuousClock()
        let enumerationStart = clock.now
        let paths = try await repository.markdownRelativePaths(includeLifecycle: true)
        let observedFolders = try await repository.folderRelativePaths(
            includeLifecycle: true
        )
        let enumerationDuration = enumerationStart.duration(to: clock.now)
        let pathSet = Set(paths)
        var changed = !isInitialized || observedFolders != folders
        var nextRecords = records
        var readFiles = 0
        var parsedDocuments = 0
        var projectedDocuments = 0
        var readDuration = Duration.zero
        var parseDuration = Duration.zero
        var projectionDuration = Duration.zero

        let candidates = pathSet.union(nextRecords.keys).sorted()
        for path in candidates {
            try Task.checkCancellation()
            let existing = nextRecords[path]
            let authorized = try await authorizedRecord(
                relativePath: path,
                existing: existing
            )
            readDuration += authorized.readDuration
            parseDuration += authorized.parseDuration
            projectionDuration += authorized.projectionDuration
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
            if authorized.didProject { projectedDocuments += 1 }
            if let record = authorized.record {
                nextRecords[path] = record
                if authorized.didRead { changed = true }
            } else {
                nextRecords[path] = nil
                if existing != nil { changed = true }
            }
        }

        if changed { try advanceGeneration() }
        records = nextRecords
        folders = observedFolders
        isInitialized = true
        needsFullReconcile = false
        record(VaultSourceCatalogMeasurement(
            enumeratedFiles: paths.count,
            readFiles: readFiles,
            parsedDocuments: parsedDocuments,
            projectedDocuments: projectedDocuments,
            enumerationDuration: enumerationDuration,
            readDuration: readDuration,
            parseDuration: parseDuration,
            projectionDuration: projectionDuration
        ))
    }

    func apply(
        upserts: Set<String>,
        deletions: Set<String>,
        refreshFolders: Bool
    ) async throws {
        var changed = false
        var nextRecords = records
        var readFiles = 0
        var parsedDocuments = 0
        var projectedDocuments = 0
        let clock = ContinuousClock()
        var enumerationDuration = Duration.zero
        var readDuration = Duration.zero
        var parseDuration = Duration.zero
        var projectionDuration = Duration.zero
        for path in deletions.union(upserts).sorted() {
            try Task.checkCancellation()
            guard (try? MarkdownRelativePath(path)) != nil else { continue }
            let existing = nextRecords[path]
            let authorized = try await authorizedRecord(
                relativePath: path,
                existing: existing
            )
            readDuration += authorized.readDuration
            parseDuration += authorized.parseDuration
            projectionDuration += authorized.projectionDuration
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
            if authorized.didProject { projectedDocuments += 1 }
            if let record = authorized.record {
                nextRecords[path] = record
                if authorized.didRead { changed = true }
            } else {
                nextRecords[path] = nil
                if existing != nil { changed = true }
            }
        }
        var nextFolders = folders
        if refreshFolders {
            let folderStart = clock.now
            nextFolders = try await repository.folderRelativePaths(
                includeLifecycle: true
            )
            enumerationDuration = folderStart.duration(to: clock.now)
            if nextFolders != folders { changed = true }
        }
        if changed { try advanceGeneration() }
        records = nextRecords
        folders = nextFolders
        record(VaultSourceCatalogMeasurement(
            enumeratedFiles: 0,
            readFiles: readFiles,
            parsedDocuments: parsedDocuments,
            projectedDocuments: projectedDocuments,
            enumerationDuration: enumerationDuration,
            readDuration: readDuration,
            parseDuration: parseDuration,
            projectionDuration: projectionDuration
        ))
    }

    func apply(_ event: VaultWatchEvent) async throws {
        guard !event.rootChanged else {
            needsFullReconcile = true
            throw WorkspaceFileEventWatcherError.rootUnavailable(
                await repository.vaultURL.path
            )
        }
        guard isInitialized, !event.requiresFullRescan else {
            try await reconcile()
            return
        }
        do {
            try await apply(
                upserts: Set(event.added).union(event.modified),
                deletions: Set(event.deleted),
                refreshFolders: !event.added.isEmpty || !event.deleted.isEmpty
            )
        } catch {
            // A partial event application is never published. The next
            // attempt must reconcile from authority rather than treating the
            // failed delta as complete.
            needsFullReconcile = true
            throw error
        }
    }

    func requireFullReconcile() {
        needsFullReconcile = true
    }

    func discardPendingMeasurement() {
        pendingMeasurement = Self.emptyMeasurement
    }

    private func advanceGeneration() throws {
        guard generation < UInt64.max else {
            throw VaultSourceCatalogError.generationExhausted
        }
        generation += 1
    }

    private func authorizedRecord(
        relativePath: String,
        existing: Record?
    ) async throws -> AuthorizedRecord {
        if let existing {
            do {
                if try await repository.sourceVersionIsCurrent(
                    relativePath: relativePath,
                    version: existing.version
                ) {
                    return AuthorizedRecord(
                        record: existing,
                        didRead: false,
                        didParse: false,
                        didProject: false,
                        readDuration: .zero,
                        parseDuration: .zero,
                        projectionDuration: .zero
                    )
                }
            } catch VaultRepositoryError.fileDoesNotExist {
                return AuthorizedRecord(
                    record: nil,
                    didRead: false,
                    didParse: false,
                    didProject: false,
                    readDuration: .zero,
                    parseDuration: .zero,
                    projectionDuration: .zero
                )
            }
        }

        let clock = ContinuousClock()
        let readStart = clock.now
        do {
            let loaded = try await repository.loadCatalogSource(
                relativePath: relativePath
            )
            let readDuration = readStart.duration(to: clock.now)
            let parseStart = clock.now
            let semantic: MarkdownSemanticDocument? =
                WorkspaceDocumentLifecycle(relativePath: relativePath) == .active
                    ? MarkdownSemanticDocument(parsing: loaded.document)
                    : nil
            let parseDuration = parseStart.duration(to: clock.now)
            let projectionStart = clock.now
            let searchProjection = semantic.map { semantic in
                SearchDocumentProjection(
                    document: loaded.document,
                    profile: WorkflowProfileResolver.resolve(
                        vaultRole: vaultRole,
                        frontmatter: loaded.document.parsedFrontmatter,
                        relativePath: loaded.document.relativePath
                    ),
                    semantic: semantic
                )
            }
            return AuthorizedRecord(
                record: Record(
                    document: loaded.document,
                    version: loaded.version,
                    fileMetadata: loaded.fileMetadata,
                    semantic: semantic,
                    searchProjection: searchProjection
                ),
                didRead: true,
                didParse: semantic != nil,
                didProject: searchProjection != nil,
                readDuration: readDuration,
                parseDuration: parseDuration,
                projectionDuration: projectionStart.duration(to: clock.now)
            )
        } catch VaultRepositoryError.fileDoesNotExist {
            return AuthorizedRecord(
                record: nil,
                didRead: false,
                didParse: false,
                didProject: false,
                readDuration: readStart.duration(to: clock.now),
                parseDuration: .zero,
                projectionDuration: .zero
            )
        }
    }

    private func record(_ measurement: VaultSourceCatalogMeasurement) {
        lastMeasurement = measurement
        pendingMeasurement = VaultSourceCatalogMeasurement(
            enumeratedFiles: pendingMeasurement.enumeratedFiles
                + measurement.enumeratedFiles,
            readFiles: pendingMeasurement.readFiles + measurement.readFiles,
            parsedDocuments: pendingMeasurement.parsedDocuments
                + measurement.parsedDocuments,
            projectedDocuments: pendingMeasurement.projectedDocuments
                + measurement.projectedDocuments,
            enumerationDuration: pendingMeasurement.enumerationDuration
                + measurement.enumerationDuration,
            readDuration: pendingMeasurement.readDuration
                + measurement.readDuration,
            parseDuration: pendingMeasurement.parseDuration
                + measurement.parseDuration,
            projectionDuration: pendingMeasurement.projectionDuration
                + measurement.projectionDuration
        )
    }

    private func makeSnapshot(
        measurement: VaultSourceCatalogMeasurement
    ) -> VaultSourceCatalogSnapshot {
        let ordered = records.values.map(\.document).sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return VaultSourceCatalogSnapshot(
            generation: generation,
            documents: ordered,
            sourceVersions: records.mapValues(\.version),
            fileMetadata: records.mapValues(\.fileMetadata),
            semantics: Dictionary(uniqueKeysWithValues: records.compactMap {
                path, record in record.semantic.map { (path, $0) }
            }),
            searchProjections: Dictionary(
                uniqueKeysWithValues: records.compactMap { path, record in
                    record.searchProjection.map { (path, $0) }
                }
            ),
            folders: folders,
            measurement: measurement
        )
    }
}
