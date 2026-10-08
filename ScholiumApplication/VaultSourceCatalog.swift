import Foundation
import ScholiumContracts
import ScholiumCore

private enum VaultSourceCatalogError: Error {
    case generationExhausted
    case incompleteAuthorization(String)
}

struct VaultSourceCatalogMeasurement: Equatable, Sendable {
    let enumeratedFiles: Int
    let readFiles: Int
    let parsedDocuments: Int
    let enumerationDuration: Duration
    let readDuration: Duration
    let parseDuration: Duration
}

struct VaultSourceCatalogSnapshot: Sendable {
    let generation: UInt64
    let projections: [WorkspaceSourceProjection]
    let sourceVersions: [String: SourceVersion]
    let fileMetadata: [String: WorkspaceFileMetadata]
    /// Storage capability only; decoded Search material is prepared by the index on demand.
    let searchProjectionCache: SourceSearchProjectionCache?
    let folders: [VaultRelativeFolderPath]
    let measurement: VaultSourceCatalogMeasurement
}

/// Rebuildable, descriptor-backed source projection for one pooled vault.
/// Markdown remains authority; only exact-revision compact projections remain
/// resident after each authorized source read and semantic parse.
actor VaultSourceCatalog {
    private struct Record: Sendable {
        let projection: WorkspaceSourceProjection
        let version: SourceVersion
        let fileMetadata: WorkspaceFileMetadata
    }

    private struct AuthorizedRecord: Sendable {
        let record: Record?
        let didRead: Bool
        let didParse: Bool
        let readDuration: Duration
        let parseDuration: Duration
    }

    private struct CandidateAuthorization: Sendable {
        let relativePath: String
        let authorizedRecord: AuthorizedRecord
    }

    private let repository: VaultRepository
    private let searchProjectionCache: SourceSearchProjectionCache?
    private let processingBudget: VaultSourceProcessingBudget
    private var records: [String: Record] = [:]
    private var folders: [VaultRelativeFolderPath] = []
    private var generation: UInt64 = 0
    private var isInitialized = false
    private var needsFullReconcile = true
    private static let emptyMeasurement = VaultSourceCatalogMeasurement(
        enumeratedFiles: 0,
        readFiles: 0,
        parsedDocuments: 0,
        enumerationDuration: .zero,
        readDuration: .zero,
        parseDuration: .zero
    )
    private var lastMeasurement = VaultSourceCatalog.emptyMeasurement
    private var pendingMeasurement = VaultSourceCatalog.emptyMeasurement

    init(
        repository: VaultRepository,
        searchProjectionCache: SourceSearchProjectionCache? = nil,
        processingBudget: VaultSourceProcessingBudget = .shared
    ) {
        self.repository = repository
        self.searchProjectionCache = searchProjectionCache
        self.processingBudget = processingBudget
    }

    init(
        repository: VaultRepository, vaultRole: VaultRole,
        applicationSupportURL: URL, vaultID: UUID
    ) {
        self.repository = repository
        self.processingBudget = .shared
        self.searchProjectionCache = SourceSearchProjectionCache(
            applicationSupportURL: applicationSupportURL, vaultID: vaultID, role: vaultRole
        )
    }

    func snapshot(
        refreshFolders: Bool = true,
        consumePendingMeasurement: Bool = false
    ) async throws -> VaultSourceCatalogSnapshot {
        try await prepareSnapshot(refreshFolders: refreshFolders)
        let measurement =
            consumePendingMeasurement
            ? pendingMeasurement
            : lastMeasurement
        if consumePendingMeasurement {
            pendingMeasurement = Self.emptyMeasurement
        }
        return makeSnapshot(measurement: measurement)
    }

    /// The live-source checks only need path and exact revision. Keep their
    /// projection inside the catalog so they do not construct a full snapshot
    /// (ordered documents, source versions, file metadata, and semantics).
    func sourceInventory(
        refreshFolders: Bool = true
    ) async throws -> [String: DocumentFingerprint] {
        try await prepareSnapshot(refreshFolders: refreshFolders)
        return records.mapValues { $0.projection.fingerprint }
    }

    func sourceVersion(
        relativePath: String,
        fingerprint: DocumentFingerprint
    ) -> SourceVersion? {
        guard let record = records[relativePath],
            record.projection.fingerprint == fingerprint
        else { return nil }
        return record.version
    }

    private func prepareSnapshot(refreshFolders: Bool) async throws {
        if !isInitialized || needsFullReconcile {
            try await reconcile()
        } else {
            if refreshFolders {
                let observedFolders = try await repository.folderRelativePaths()
                if observedFolders != folders {
                    try advanceGeneration()
                    folders = observedFolders
                }
            }
        }
    }

    func reconcile() async throws {
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
        var readDuration = Duration.zero
        var parseDuration = Duration.zero

        let candidates = pathSet.union(nextRecords.keys).sorted()
        let authorizations = try await authorizeCandidates(
            candidates,
            existingRecords: nextRecords
        )
        for path in candidates {
            try Task.checkCancellation()
            let existing = nextRecords[path]
            guard let authorized = authorizations[path] else {
                throw VaultSourceCatalogError.incompleteAuthorization(path)
            }
            readDuration += authorized.readDuration
            parseDuration += authorized.parseDuration
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
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
        searchProjectionCache?.prune(currentPaths: Set(nextRecords.keys))
        record(
            VaultSourceCatalogMeasurement(
                enumeratedFiles: paths.count,
                readFiles: readFiles,
                parsedDocuments: parsedDocuments,
                enumerationDuration: enumerationDuration,
                readDuration: readDuration,
                parseDuration: parseDuration
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
        let clock = ContinuousClock()
        var enumerationDuration = Duration.zero
        var readDuration = Duration.zero
        var parseDuration = Duration.zero
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
            if authorized.didRead { readFiles += 1 }
            if authorized.didParse { parsedDocuments += 1 }
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
            nextFolders = try await repository.folderRelativePaths()
            enumerationDuration = folderStart.duration(to: clock.now)
            if nextFolders != folders { changed = true }
        }
        if changed { try advanceGeneration() }
        records = nextRecords
        folders = nextFolders
        for path in deletions.union(upserts) where nextRecords[path] == nil {
            searchProjectionCache?.invalidate(path: path)
        }
        record(
            VaultSourceCatalogMeasurement(
                enumeratedFiles: 0,
                readFiles: readFiles,
                parsedDocuments: parsedDocuments,
                enumerationDuration: enumerationDuration,
                readDuration: readDuration,
                parseDuration: parseDuration
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
        existingRecords: [String: Record]
    ) async throws -> [String: AuthorizedRecord] {
        guard !candidates.isEmpty else { return [:] }
        let repository = repository
        let processingBudget = processingBudget
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
                            processingBudget: processingBudget,
                            relativePath: path,
                            existing: existing
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
                                processingBudget: processingBudget,
                                relativePath: path,
                                existing: existing
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
        existing: Record?
    ) async throws -> AuthorizedRecord {
        try await Self.authorizedRecord(
            repository: repository,
            processingBudget: processingBudget,
            relativePath: relativePath,
            existing: existing
        )
    }

    private static func authorizedRecord(
        repository: VaultRepository,
        processingBudget: VaultSourceProcessingBudget,
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
                        readDuration: .zero,
                        parseDuration: .zero
                    )
                }
            } catch VaultRepositoryError.fileDoesNotExist {
                return AuthorizedRecord(
                    record: nil,
                    didRead: false,
                    didParse: false,
                    readDuration: .zero,
                    parseDuration: .zero
                )
            }
        }

        let clock = ContinuousClock()
        do {
            return try await processingBudget.withReservation {
                let loaded = try await repository.loadCatalogSource(
                    relativePath: relativePath
                )
                let vaultID = await repository.identity.id
                let parseStart = clock.now
                let semantic = MarkdownSemanticDocument(parsing: loaded.document)
                let projection = WorkspaceSourceProjection(
                    vaultID: vaultID,
                    document: loaded.document,
                    semantic: semantic
                )
                let parseDuration = parseStart.duration(to: clock.now)
                return AuthorizedRecord(
                    record: Record(
                        projection: projection,
                        version: loaded.version,
                        fileMetadata: loaded.fileMetadata
                    ),
                    didRead: true,
                    didParse: true,
                    readDuration: loaded.readDuration,
                    parseDuration: parseDuration
                )
            }
        } catch VaultRepositoryError.fileDoesNotExist {
            return AuthorizedRecord(
                record: nil,
                didRead: false,
                didParse: false,
                readDuration: .zero,
                parseDuration: .zero
            )
        }
    }

    private func record(_ measurement: VaultSourceCatalogMeasurement) {
        lastMeasurement = measurement
        pendingMeasurement = VaultSourceCatalogMeasurement(
            enumeratedFiles: pendingMeasurement.enumeratedFiles + measurement.enumeratedFiles,
            readFiles: pendingMeasurement.readFiles + measurement.readFiles,
            parsedDocuments: pendingMeasurement.parsedDocuments + measurement.parsedDocuments,
            enumerationDuration: pendingMeasurement.enumerationDuration + measurement.enumerationDuration,
            readDuration: pendingMeasurement.readDuration + measurement.readDuration,
            parseDuration: pendingMeasurement.parseDuration + measurement.parseDuration
        )
    }

    private func makeSnapshot(
        measurement: VaultSourceCatalogMeasurement
    ) -> VaultSourceCatalogSnapshot {
        let ordered = records.values.map(\.projection).sorted {
            $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return VaultSourceCatalogSnapshot(
            generation: generation,
            projections: ordered,
            sourceVersions: records.mapValues(\.version),
            fileMetadata: records.mapValues(\.fileMetadata),
            searchProjectionCache: searchProjectionCache,
            folders: folders,
            measurement: measurement
        )
    }
}
