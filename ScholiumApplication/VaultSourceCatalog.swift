import Foundation
import ScholiumContracts
import ScholiumCore

private enum VaultSourceCatalogError: Error {
    case generationExhausted
    case incompleteAuthorization(String)
}

enum VaultSourceCatalogProjectionRequirement: Equatable, Sendable {
    /// Authoritative source plus the semantic projection needed by Library and
    /// Document presentation. Search-specific visible text and offset maps may
    /// be completed later by the same catalog actor.
    case library
    /// The complete source-bound Search projection required by a Triptych
    /// generation.
    case search
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

    private struct CandidateAuthorization: Sendable {
        let relativePath: String
        let authorizedRecord: AuthorizedRecord
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
        consumePendingMeasurement: Bool = false,
        projectionRequirement: VaultSourceCatalogProjectionRequirement = .search
    ) async throws -> VaultSourceCatalogSnapshot {
        if !isInitialized || needsFullReconcile {
            try await reconcile(projectionRequirement: projectionRequirement)
        } else {
            if projectionRequirement == .search,
               records.contains(where: { $0.value.searchProjection == nil }) {
                try completeSearchProjections()
            }
            if refreshFolders {
                let observedFolders = try await repository.folderRelativePaths()
                if observedFolders != folders {
                    try advanceGeneration()
                    folders = observedFolders
                }
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

    func reconcile(
        projectionRequirement: VaultSourceCatalogProjectionRequirement = .search
    ) async throws {
        let clock = ContinuousClock()
        let enumerationStart = clock.now
        let paths = try await repository.markdownRelativePaths()
        let observedFolders = try await repository.folderRelativePaths()
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
        let authorizations = try await authorizeCandidates(
            candidates,
            existingRecords: nextRecords,
            projectionRequirement: projectionRequirement
        )
        for path in candidates {
            try Task.checkCancellation()
            let existing = nextRecords[path]
            guard let authorized = authorizations[path] else {
                throw VaultSourceCatalogError.incompleteAuthorization(path)
            }
            readDuration += authorized.readDuration
            parseDuration += authorized.parseDuration
            projectionDuration += authorized.projectionDuration
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
            if authorized.didProject { projectedDocuments += 1 }
            if let record = authorized.record {
                nextRecords[path] = record
                if authorized.didRead || authorized.didProject { changed = true }
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
                existing: existing,
                projectionRequirement: .search
            )
            readDuration += authorized.readDuration
            parseDuration += authorized.parseDuration
            projectionDuration += authorized.projectionDuration
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
            if authorized.didProject { projectedDocuments += 1 }
            if let record = authorized.record {
                nextRecords[path] = record
                if authorized.didRead || authorized.didProject { changed = true }
            } else {
                nextRecords[path] = nil
                if existing != nil { changed = true }
            }
        }
        var nextFolders = folders
        if refreshFolders {
            let folderStart = clock.now
            nextFolders = try await repository.folderRelativePaths()
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

    /// Keeps descriptor-authorized repository reads serialized by their actor,
    /// while allowing pure semantic parsing from an earlier read to overlap a
    /// later read. Results remain local until every candidate succeeds, so a
    /// failed reconcile cannot partially replace the retained catalog.
    private func authorizeCandidates(
        _ candidates: [String],
        existingRecords: [String: Record],
        projectionRequirement: VaultSourceCatalogProjectionRequirement
    ) async throws -> [String: AuthorizedRecord] {
        guard !candidates.isEmpty else { return [:] }
        let repository = repository
        let vaultRole = vaultRole
        let workerCount = min(
            candidates.count,
            max(2, ProcessInfo.processInfo.activeProcessorCount)
        )
        return try await withThrowingTaskGroup(
            of: CandidateAuthorization.self,
            returning: [String: AuthorizedRecord].self
        ) { group in
            for index in 0..<workerCount {
                let path = candidates[index]
                let existing = existingRecords[path]
                group.addTask {
                    CandidateAuthorization(
                        relativePath: path,
                        authorizedRecord: try await Self.authorizedRecord(
                            repository: repository,
                            vaultRole: vaultRole,
                            relativePath: path,
                            existing: existing,
                            projectionRequirement: projectionRequirement
                        )
                    )
                }
            }

            var nextIndex = workerCount
            var results: [String: AuthorizedRecord] = [:]
            results.reserveCapacity(candidates.count)
            while let candidate = try await group.next() {
                results[candidate.relativePath] = candidate.authorizedRecord
                if nextIndex < candidates.count {
                    let path = candidates[nextIndex]
                    let existing = existingRecords[path]
                    nextIndex += 1
                    group.addTask {
                        CandidateAuthorization(
                            relativePath: path,
                            authorizedRecord: try await Self.authorizedRecord(
                                repository: repository,
                                vaultRole: vaultRole,
                                relativePath: path,
                                existing: existing,
                                projectionRequirement: projectionRequirement
                            )
                        )
                    }
                }
            }
            return results
        }
    }

    private func authorizedRecord(
        relativePath: String,
        existing: Record?,
        projectionRequirement: VaultSourceCatalogProjectionRequirement
    ) async throws -> AuthorizedRecord {
        try await Self.authorizedRecord(
            repository: repository,
            vaultRole: vaultRole,
            relativePath: relativePath,
            existing: existing,
            projectionRequirement: projectionRequirement
        )
    }

    private static func authorizedRecord(
        repository: VaultRepository,
        vaultRole: VaultRole,
        relativePath: String,
        existing: Record?,
        projectionRequirement: VaultSourceCatalogProjectionRequirement
    ) async throws -> AuthorizedRecord {
        if let existing {
            do {
                if try await repository.sourceVersionIsCurrent(
                    relativePath: relativePath,
                    version: existing.version
                ) {
                    if projectionRequirement == .search,
                       existing.semantic != nil,
                       existing.searchProjection == nil {
                        let projectionStart = ContinuousClock().now
                        let completed = recordByCompletingSearchProjection(
                            existing,
                            vaultRole: vaultRole
                        )
                        return AuthorizedRecord(
                            record: completed,
                            didRead: false,
                            didParse: false,
                            didProject: true,
                            readDuration: .zero,
                            parseDuration: .zero,
                            projectionDuration: projectionStart.duration(
                                to: ContinuousClock().now
                            )
                        )
                    }
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
        do {
            let loaded = try await repository.loadCatalogSource(
                relativePath: relativePath
            )
            let parseStart = clock.now
            let semantic = MarkdownSemanticDocument(parsing: loaded.document)
            let parseDuration = parseStart.duration(to: clock.now)
            let projectionStart = clock.now
            let searchProjection: SearchDocumentProjection?
            if projectionRequirement == .search {
                searchProjection = SearchDocumentProjection(
                    document: loaded.document,
                    profile: WorkflowProfileResolver.resolve(vaultRole: vaultRole),
                    semantic: semantic
                )
            } else {
                searchProjection = nil
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
                didParse: true,
                didProject: searchProjection != nil,
                readDuration: loaded.readDuration,
                parseDuration: parseDuration,
                projectionDuration: projectionStart.duration(to: clock.now)
            )
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

    private func completeSearchProjections() throws {
        let clock = ContinuousClock()
        let projectionStart = clock.now
        var nextRecords = records
        var projectedDocuments = 0
        for (path, record) in records where record.semantic != nil
            && record.searchProjection == nil {
            try Task.checkCancellation()
            nextRecords[path] = Self.recordByCompletingSearchProjection(
                record,
                vaultRole: vaultRole
            )
            projectedDocuments += 1
        }
        guard projectedDocuments > 0 else { return }
        try advanceGeneration()
        records = nextRecords
        record(VaultSourceCatalogMeasurement(
            enumeratedFiles: 0,
            readFiles: 0,
            parsedDocuments: 0,
            projectedDocuments: projectedDocuments,
            enumerationDuration: .zero,
            readDuration: .zero,
            parseDuration: .zero,
            projectionDuration: projectionStart.duration(to: clock.now)
        ))
    }

    private static func recordByCompletingSearchProjection(
        _ record: Record,
        vaultRole: VaultRole
    ) -> Record {
        Record(
            document: record.document,
            version: record.version,
            fileMetadata: record.fileMetadata,
            semantic: record.semantic,
            searchProjection: record.semantic.map { semantic in
                SearchDocumentProjection(
                    document: record.document,
                    profile: WorkflowProfileResolver.resolve(vaultRole: vaultRole),
                    semantic: semantic
                )
            }
        )
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
