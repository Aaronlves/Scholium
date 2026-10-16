import Foundation
import ScholiumContracts
import ScholiumCore

enum VaultSourceCatalogError: Error, Equatable {
    case generationExhausted
    case incompleteAuthorization(String)
    case preparationRequired
    case rootUnavailable
    case shutDown
    case foreignPreparation
}

enum VaultSourceCatalogPreparation: Sendable {
    case fullReconcile
    case delta(upserts: Set<String>, deletions: Set<String>, refreshFolders: Bool)
    case ifNeeded
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
    fileprivate let catalogID: UUID
    fileprivate let stateToken: UUID
    let generation: UInt64
    let projections: [WorkspaceSourceProjection]
    let sourceVersions: [String: SourceVersion]
    let fileMetadata: [String: WorkspaceFileMetadata]
    /// Storage capability only; decoded Search material is prepared by the index on demand.
    let searchProjectionCache: SourceSearchProjectionCache?
    let folders: [VaultRelativeFolderPath]
    let measurement: VaultSourceCatalogMeasurement
}

/// The cached inputs that can change a published Vault inventory. This omits
/// ordered semantic projections and source-version maps used by a full build.
struct VaultSourceCatalogPublicationInventory: Sendable {
    let fingerprints: [String: DocumentFingerprint]
    let fileMetadata: [String: WorkspaceFileMetadata]
    let folders: [VaultRelativeFolderPath]
}

/// Rebuildable, descriptor-backed source projection for one pooled vault.
/// Markdown remains authority; only exact-revision compact projections remain
/// resident after each authorized source read and semantic parse.
actor VaultSourceCatalog {
    fileprivate struct Record: Sendable {
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

    struct PreparedUpdate: Sendable {
        fileprivate let catalogID: UUID
        fileprivate let stateToken: UUID
        fileprivate let records: [String: Record]
        fileprivate let folders: [VaultRelativeFolderPath]
        fileprivate let changed: Bool
        fileprivate let measurement: VaultSourceCatalogMeasurement
        fileprivate let cacheCleanup: CacheCleanup
    }

    fileprivate enum CacheCleanup: Sendable {
        case prune
        case invalidate(Set<String>)
        case none
    }

    enum Installation: Sendable {
        case installed(VaultSourceCatalogSnapshot)
        case superseded
    }

    enum Validation: Equatable, Sendable {
        case current
        case superseded
    }

    private enum Lifecycle {
        case active, rootUnavailable, shutDown
    }

    private let repository: VaultRepository
    private let searchProjectionCache: SourceSearchProjectionCache?
    private let processingBudget: VaultSourceProcessingBudget
    private let catalogID = UUID()
    private var stateToken = UUID()
    private var lifecycle = Lifecycle.active
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
    #if DEBUG
        private var validationBarrierForTesting: (@Sendable () async -> Void)?

        func setValidationBarrierForTesting(_ barrier: (@Sendable () async -> Void)?) {
            validationBarrierForTesting = barrier
        }
    #endif

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

    /// Reads only the installed complete catalog. Preparation is always an
    /// explicit caller-owned operation and never begins behind a read API.
    func snapshot(consumePendingMeasurement: Bool = false) throws -> VaultSourceCatalogSnapshot {
        try requirePrepared()
        let measurement = consumePendingMeasurement ? pendingMeasurement : lastMeasurement
        if consumePendingMeasurement { pendingMeasurement = Self.emptyMeasurement }
        return makeSnapshot(measurement: measurement)
    }

    func sourceInventory() throws -> [String: DocumentFingerprint] {
        try requirePrepared()
        return records.mapValues { $0.projection.fingerprint }
    }

    func publicationInventory() throws -> VaultSourceCatalogPublicationInventory {
        try requirePrepared()
        return VaultSourceCatalogPublicationInventory(
            fingerprints: records.mapValues { $0.projection.fingerprint },
            fileMetadata: records.mapValues(\.fileMetadata),
            folders: folders)
    }

    func sourceVersion(relativePath: String, fingerprint: DocumentFingerprint) -> SourceVersion? {
        guard case .active = lifecycle, isInitialized, !needsFullReconcile,
            let record = records[relativePath], record.projection.fingerprint == fingerprint
        else { return nil }
        return record.version
    }

    /// Captures the actor's base state before its first suspension. Descriptor
    /// reads and semantic parsing produce a local immutable candidate; they
    /// neither replace the catalog nor acquire Application source authority.
    func prepare(_ preparation: VaultSourceCatalogPreparation) async throws -> PreparedUpdate {
        do {
            try requireActive()
            let baseToken = stateToken
            let existingRecords = records
            let existingFolders = folders
            let initialized = isInitialized
            let requiresReconcile = needsFullReconcile
            let request: VaultSourceCatalogPreparation =
                !initialized || requiresReconcile ? .fullReconcile : preparation
            let clock = ContinuousClock()
            let enumerationStart = clock.now
            let candidates: [String]
            let observedFolders: [VaultRelativeFolderPath]
            let enumeratedFiles: Int
            let cacheCleanup: CacheCleanup
            switch request {
            case .fullReconcile:
                let paths = try await repository.markdownRelativePaths()
                observedFolders = try await repository.folderRelativePaths()
                candidates = Set(paths).union(existingRecords.keys).sorted()
                enumeratedFiles = paths.count
                cacheCleanup = .prune
            case .delta(let upserts, let deletions, let refreshFolders):
                candidates = deletions.union(upserts).filter { (try? MarkdownRelativePath($0)) != nil }.sorted()
                if refreshFolders {
                    observedFolders = try await repository.folderRelativePaths()
                } else {
                    observedFolders = existingFolders
                }
                enumeratedFiles = 0
                cacheCleanup = .invalidate(Set(candidates))
            case .ifNeeded:
                candidates = []
                observedFolders = existingFolders
                enumeratedFiles = 0
                cacheCleanup = .none
            }
            let enumerationDuration = enumerationStart.duration(to: clock.now)
            let authorizations = try await authorizeCandidates(candidates, existingRecords: existingRecords)
            var nextRecords = existingRecords
            var changed = !initialized || observedFolders != existingFolders
            var readFiles = 0
            var parsedDocuments = 0
            var readDuration = Duration.zero
            var parseDuration = Duration.zero
            for path in candidates {
                try Task.checkCancellation()
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
                    if existingRecords[path] != nil { changed = true }
                }
            }
            try requireActive()
            return PreparedUpdate(
                catalogID: catalogID, stateToken: baseToken,
                records: nextRecords, folders: observedFolders, changed: changed,
                measurement: VaultSourceCatalogMeasurement(
                    enumeratedFiles: enumeratedFiles, readFiles: readFiles,
                    parsedDocuments: parsedDocuments, enumerationDuration: enumerationDuration,
                    readDuration: readDuration, parseDuration: parseDuration),
                cacheCleanup: cacheCleanup)
        } catch let error as VaultRepositoryError {
            if case .rootUnavailable = error { invalidateRootAuthority() }
            throw error
        }
    }

    /// Installation is the only catalog writer. The caller owns any broader
    /// source/identity lease; this actor validates its own source cohort and
    /// repeats the token check after every possible reentrant mutation.
    /// Complete-cohort capture consumes measurement with this same installed
    /// snapshot; watcher and bootstrap installations leave it for their reader.
    func install(_ prepared: PreparedUpdate, consumePendingMeasurement: Bool = false) async throws -> Installation {
        try requireActive()
        guard prepared.catalogID == catalogID else { throw VaultSourceCatalogError.foreignPreparation }
        guard prepared.stateToken == stateToken else { return .superseded }
        let validation = try await validateContents(
            expectedToken: prepared.stateToken,
            versions: prepared.records.mapValues(\.version), folders: prepared.folders)
        guard validation == .current else { return .superseded }
        try requireActive()
        guard prepared.stateToken == stateToken else { return .superseded }
        if prepared.changed { try advanceGeneration() }
        records = prepared.records
        folders = prepared.folders
        isInitialized = true
        needsFullReconcile = false
        stateToken = UUID()
        switch prepared.cacheCleanup {
        case .prune:
            searchProjectionCache?.prune(currentPaths: Set(records.keys))
        case .invalidate(let paths):
            for path in paths where records[path] == nil {
                searchProjectionCache?.invalidate(path: path)
            }
        case .none: break
        }
        record(prepared.measurement)
        let measurement = consumePendingMeasurement ? pendingMeasurement : lastMeasurement
        if consumePendingMeasurement { pendingMeasurement = Self.emptyMeasurement }
        return .installed(makeSnapshot(measurement: measurement))
    }

    /// Validates the exact immutable installed cohort before Application
    /// captures portable identities or publishes derived completeness.
    func validate(_ snapshot: VaultSourceCatalogSnapshot) async throws -> Validation {
        try requireActive()
        guard snapshot.catalogID == catalogID else { throw VaultSourceCatalogError.foreignPreparation }
        guard snapshot.stateToken == stateToken, isInitialized, !needsFullReconcile else { return .superseded }
        return try await validateContents(
            expectedToken: snapshot.stateToken, versions: snapshot.sourceVersions, folders: snapshot.folders)
    }

    func requireFullReconcile() {
        guard case .active = lifecycle else { return }
        needsFullReconcile = true
        stateToken = UUID()
    }

    func invalidateRootAuthority() {
        guard case .active = lifecycle else { return }
        lifecycle = .rootUnavailable
        needsFullReconcile = true
        stateToken = UUID()
    }

    func shutdown() {
        lifecycle = .shutDown
        needsFullReconcile = true
        stateToken = UUID()
    }

    func discardPendingMeasurement() {
        pendingMeasurement = Self.emptyMeasurement
    }

    private func requireActive() throws {
        switch lifecycle {
        case .active: break
        case .rootUnavailable: throw VaultSourceCatalogError.rootUnavailable
        case .shutDown: throw VaultSourceCatalogError.shutDown
        }
        try Task.checkCancellation()
    }

    private func requirePrepared() throws {
        try requireActive()
        guard isInitialized, !needsFullReconcile else { throw VaultSourceCatalogError.preparationRequired }
    }

    private func validateContents(
        expectedToken: UUID,
        versions: [String: SourceVersion],
        folders expectedFolders: [VaultRelativeFolderPath]
    ) async throws -> Validation {
        do {
            try requireActive()
            if await repository.rootAuthorityIsInvalid {
                invalidateRootAuthority()
                throw VaultSourceCatalogError.rootUnavailable
            }
            let paths = try await repository.markdownRelativePaths()
            let observedFolders = try await repository.folderRelativePaths()
            var current = Set(paths) == Set(versions.keys) && observedFolders == expectedFolders
            if current {
                for path in versions.keys.sorted() {
                    try Task.checkCancellation()
                    do {
                        guard let version = versions[path],
                            try await repository.sourceVersionIsCurrent(relativePath: path, version: version)
                        else {
                            current = false
                            break
                        }
                    } catch VaultRepositoryError.fileDoesNotExist {
                        current = false
                        break
                    }
                }
            }
            #if DEBUG
                if let validationBarrierForTesting { await validationBarrierForTesting() }
            #endif
            try requireActive()
            guard stateToken == expectedToken else { return .superseded }
            guard current else {
                // Invalidation must be visible to an if-needed retry, otherwise
                // it could repeatedly offer the same stale installed records.
                requireFullReconcile()
                return .superseded
            }
            return .current
        } catch let error as VaultRepositoryError {
            if case .rootUnavailable = error { invalidateRootAuthority() }
            throw error
        }
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
            catalogID: catalogID,
            stateToken: stateToken,
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
