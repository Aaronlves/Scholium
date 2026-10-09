import Darwin
import Foundation
import SQLite3
import ScholiumContracts
import os

package struct SearchSynchronizationTimings: Sendable {
    package let documentCount: Int
    package let changedCount: Int
    package let projectedDocuments: Int
    package let restoredSearchProjections: Int
    package let projectionDuration: Duration
    package let cacheReadDuration: Duration
    package let cacheWriteDuration: Duration
    package let preparationMilliseconds: Double
    package let publicationMilliseconds: Double
}

public struct TriptychSearchIndexOpenResult: Sendable {
    public let index: TriptychSearchIndex
    public let recoveredCorruption: Bool

    public init(index: TriptychSearchIndex, recoveredCorruption: Bool) {
        self.index = index
        self.recoveredCorruption = recoveredCorruption
    }
}

/// Exact source authority supplied for a bounded query against a previously
/// complete disposable generation. Candidate filtering happens inside the
/// index before result limits and `hasMore` are computed.
public struct SearchIndexDocumentEligibility: Hashable, Sendable {
    public let fingerprint: DocumentFingerprint
    public let resolvedStableNoteID: UUID?

    public init(
        fingerprint: DocumentFingerprint,
        resolvedStableNoteID: UUID?
    ) {
        self.fingerprint = fingerprint
        self.resolvedStableNoteID = resolvedStableNoteID
    }
}

/// One transaction-bound change set for a disposable Triptych search index.
/// The workspace generation is persisted in the same transaction and prevents
/// an older refresh from publishing after a newer source generation.
struct SearchIndexDelta: Sendable {
    let workspaceGeneration: UInt64
    let upserts: [SearchIndexManifestEntry]
    let deletions: [VaultQualifiedNoteID]
}

public actor TriptychSearchIndex {
    #if DEBUG
        private(set) var rankedSearchExecutionCountsForTesting = (rankingPasses: 0, candidateScans: 0)

        enum RelatedLexicalPoolPhase: Sendable { case begin, row, end }

        struct RelatedLexicalPoolObservation: Sendable {
            let phase: RelatedLexicalPoolPhase
            let candidateCount: Int
            let retainedProjectionCount: Int
            /// Cost of the complete pool seen so far, even after its full
            /// projections have been released on crossing the cache budget.
            let completePoolEstimatedBytes: Int
        }

        private var relatedLexicalPoolObserverForTesting: (@Sendable (RelatedLexicalPoolObservation) -> Void)?

        func setRelatedLexicalPoolObserverForTesting(
            _ observer: (@Sendable (RelatedLexicalPoolObservation) -> Void)?
        ) {
            relatedLexicalPoolObserverForTesting = observer
        }

        func setRelatedBackgroundPreparationBudgetForTesting(_ bytes: Int) {
            relatedBackgroundPreparation = RelatedContentBackgroundPreparation(maximumByteCount: bytes)
        }
    #endif

    private static let logger = Logger(subsystem: "com.scholium.app", category: "SearchIndex")
    package private(set) var lastSynchronizationTimings: SearchSynchronizationTimings?
    private let triptychID: UUID
    private let databaseURL: URL
    private let configuredVaults: [UUID: RegisteredVault]
    /// Actor-serialized reader. Every indexed query opens a fixed read
    /// transaction so a concurrent WAL publication cannot mix generations.
    private let database: SearchSQLiteDatabase
    /// A separate connection may publish while the actor serves last-good
    /// reads from `database`.
    private let writerDatabase: SearchSQLiteDatabase
    private var currentAvailability: SearchAvailability
    private var recoveredGeneratedDatabase: Bool
    private var activeSynchronization: ActiveSynchronization?
    private var synchronizationQueuedForTesting: (@Sendable (UInt64) async -> Void)?
    private var joinedSynchronizationWaitForTesting: (@Sendable () async -> Void)?
    private var latestWorkspaceGeneration: UInt64 = 0
    private var relatedPassageMemo = RelatedContentSourceProjectionMemo()
    private var relatedBackgroundPreparation = RelatedContentBackgroundPreparation()
    var relatedBackgroundPreparationStatistics: RelatedContentBackgroundPreparation.Statistics {
        relatedBackgroundPreparation.statistics
    }
    var relatedBackgroundPreparationRetention: (entries: Int, estimatedBytes: Int) {
        (relatedBackgroundPreparation.entryCount, relatedBackgroundPreparation.estimatedByteCount)
    }
    var relatedPassagePreparationStatistics: RelatedContentSourceProjectionMemo.Statistics {
        relatedPassageMemo.statistics
    }
    var relatedPassagePreparationRetention: (entries: Int, estimatedBytes: Int) {
        (relatedPassageMemo.entryCount, relatedPassageMemo.estimatedByteCount)
    }
    /// The writer connection may be running an async transaction outside this
    /// actor. Sample its SQLite status only after that task has finished.
    var sqlitePageCacheRetention: (readerBytes: Int, writerBytes: Int)? {
        guard activeSynchronization == nil else { return nil }
        return (database.cacheUsedBytes, writerDatabase.cacheUsedBytes)
    }
    /// Query-local derived state is valid only for one complete Search
    /// generation. Each query retains at most the maximum public result window
    /// plus one `hasMore` probe; a small LRU also bounds distinct completed
    /// queries. Larger offsets use the canonical scan.
    private var rankedSearchCache: [RankedSearchCacheKey: RankedSearchCacheValue] = [:]
    private var rankedSearchAccessClock: UInt64 = 0

    var rankedSearchCacheRetention: (queries: Int, results: Int) {
        (rankedSearchCache.count, rankedSearchCache.values.reduce(0) { $0 + $1.items.count })
    }

    private struct SearchPublication: Sendable {
        let result: TriptychSearchIndexSyncResult
        let preparation: SearchProjectionPreparation
    }

    private struct ActiveSynchronization {
        let id: UUID
        let previous: SearchGenerationID?
        let task: Task<SearchPublication, Error>
        let progress: ProgressDelivery?
    }

    private struct RankedSearchCacheKey: Hashable {
        let generation: SearchGenerationID
        let ast: SearchQueryAST
        let vaultID: UUID?
        let includedVaultIDs: [UUID]
    }

    private struct RankedSearchItem {
        let rowID: Int
        let identityPriority: Int
        let lexicalRank: Double
        let evaluation: SearchEvaluation
    }

    private struct RankedSearchCacheValue {
        let items: [RankedSearchItem]
        let total: Int
        let indeterminate: Int
        var lastAccess: UInt64
    }

    private static let maximumCachedRankedQueries = 8
    private static let maximumCachedRankedResults = SearchContract.maximumNoteResults + 1

    private struct ProgressDelivery {
        let continuation: AsyncStream<Int>.Continuation
        let task: Task<Void, Never>
    }

    public init(
        databaseURL: URL,
        triptychID: UUID,
        vaults: [RegisteredVault] = [],
        recoveredCorruption: Bool = false
    ) throws {
        self.triptychID = triptychID
        self.databaseURL = databaseURL
        configuredVaults = Dictionary(
            vaults.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        recoveredGeneratedDatabase = recoveredCorruption
        let manager = FileManager.default
        try manager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existed = manager.fileExists(atPath: databaseURL.path)
        database = try SearchSQLiteDatabase(path: databaseURL.path)
        if existed {
            try Self.validateSchema(in: database, triptychID: triptychID)
        } else {
            try Self.createSchema(in: database, triptychID: triptychID)
            try Self.validateSchema(in: database, triptychID: triptychID)
        }
        try database.execute("PRAGMA journal_mode=WAL;")
        try database.execute("PRAGMA synchronous=NORMAL;")
        writerDatabase = try SearchSQLiteDatabase(path: databaseURL.path)
        try writerDatabase.execute("PRAGMA journal_mode=WAL;")
        try writerDatabase.execute("PRAGMA synchronous=NORMAL;")
        try database.execute("PRAGMA query_only=ON;")
        latestWorkspaceGeneration = try Self.readWorkspaceGeneration(
            in: database
        )
        if let generation = try Self.readGeneration(in: database, triptychID: triptychID),
            generation.sequence > 0
        {
            currentAvailability = .current(generation)
        } else {
            currentAvailability = .unavailable
        }
    }

    public nonisolated static func databaseURL(
        applicationSupportURL: URL,
        triptychID: UUID
    ) -> URL {
        applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("search-v10.sqlite", isDirectory: false)
    }

    /// Replaces only a disposable generated database. The v1 files and all
    /// research Markdown remain untouched.
    public nonisolated static func openRecovering(
        databaseURL: URL,
        triptychID: UUID,
        vaults: [RegisteredVault] = []
    ) throws -> TriptychSearchIndexOpenResult {
        do {
            return TriptychSearchIndexOpenResult(
                index: try TriptychSearchIndex(
                    databaseURL: databaseURL,
                    triptychID: triptychID,
                    vaults: vaults
                ),
                recoveredCorruption: false
            )
        } catch let error as SearchIndexError where error.permitsSearchRecovery {
            let manager = FileManager.default
            try manager.createDirectory(
                at: databaseURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stagingURL = databaseURL.deletingLastPathComponent()
                .appendingPathComponent(".search-v10-staging-\(UUID().uuidString).sqlite")
            do {
                do {
                    let staged = try SearchSQLiteDatabase(path: stagingURL.path)
                    try createSchema(in: staged, triptychID: triptychID)
                    try validateSchema(in: staged, triptychID: triptychID)
                    try staged.execute("PRAGMA wal_checkpoint(TRUNCATE);")
                    try staged.execute("PRAGMA journal_mode=DELETE;")
                }
                guard Darwin.rename(stagingURL.path, databaseURL.path) == 0 else {
                    throw SearchIndexError.sqlite(
                        "could not atomically publish a rebuilt Search v10 database"
                    )
                }
                for suffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
                    if manager.fileExists(atPath: sidecar.path) {
                        try? manager.removeItem(at: sidecar)
                    }
                }
                return TriptychSearchIndexOpenResult(
                    index: try TriptychSearchIndex(
                        databaseURL: databaseURL,
                        triptychID: triptychID,
                        vaults: vaults,
                        recoveredCorruption: true
                    ),
                    recoveredCorruption: true
                )
            } catch {
                for suffix in ["", "-wal", "-shm"] {
                    let candidate = URL(fileURLWithPath: stagingURL.path + suffix)
                    if manager.fileExists(atPath: candidate.path) {
                        try? manager.removeItem(at: candidate)
                    }
                }
                throw error
            }
        }
    }

    public func availability() -> SearchAvailability {
        currentAvailability
    }

    public func generation() throws -> SearchGenerationID? {
        try Self.readGeneration(in: database, triptychID: triptychID)
    }

    public func workspaceGeneration() throws -> UInt64 {
        let stored = try Self.readWorkspaceGeneration(in: database)
        latestWorkspaceGeneration = max(latestWorkspaceGeneration, stored)
        return latestWorkspaceGeneration
    }

    func setSynchronizationQueuedForTesting(
        _ callback: (@Sendable (UInt64) async -> Void)?
    ) {
        synchronizationQueuedForTesting = callback
    }

    func setJoinedSynchronizationWaitForTesting(
        _ callback: (@Sendable () async -> Void)?
    ) {
        joinedSynchronizationWaitForTesting = callback
    }

    /// Production path: compare a compact complete manifest and descriptor-load
    /// one changed row at a time on the sole writer task. The validation closure
    /// checks every captured SourceVersion immediately before commit.
    public func synchronizeManifest(
        _ documents: [SearchIndexManifestEntry],
        sourceProjectionCaches: [UUID: SourceSearchProjectionCache] = [:],
        workspaceGeneration: UInt64,
        loadChanged: @escaping @Sendable (SearchIndexManifestEntry) async throws -> SearchIndexDocument,
        validateManifest: @escaping @Sendable () async throws -> Void
    ) async throws -> TriptychSearchIndexSyncResult {
        try Task.checkCancellation()
        // Finish the one older writer before validating the new request. This
        // lets the recursive retry compare against the generation that writer
        // actually committed instead of the pre-wait watermark.
        if let active = activeSynchronization {
            if let callback = synchronizationQueuedForTesting {
                await callback(workspaceGeneration)
            }
            do {
                _ = try await finishSynchronization(active, joinedWaiter: true)
            } catch is CancellationError {
                if Task.isCancelled { throw CancellationError() }
            } catch {
                // A later requested source generation is still allowed to
                // repair a failed earlier refresh.
            }
            try Task.checkCancellation()
            return try await synchronizeManifest(
                documents,
                sourceProjectionCaches: sourceProjectionCaches,
                workspaceGeneration: workspaceGeneration,
                loadChanged: loadChanged,
                validateManifest: validateManifest
            )
        }

        guard workspaceGeneration <= UInt64(Int.max) else {
            throw SearchIndexError.invalidDocuments(
                "Search workspace generation cannot be represented by SQLite."
            )
        }
        let storedWorkspaceGeneration = try Self.readWorkspaceGeneration(
            in: database
        )
        latestWorkspaceGeneration = max(
            latestWorkspaceGeneration,
            storedWorkspaceGeneration
        )
        guard workspaceGeneration > latestWorkspaceGeneration else {
            throw SearchIndexError.invalidDocuments(
                "Refused stale workspace generation \(workspaceGeneration); latest requested generation is \(latestWorkspaceGeneration)."
            )
        }
        latestWorkspaceGeneration = workspaceGeneration

        let preparationStarted = ContinuousClock.now
        let desired = try Self.validatedDocuments(documents)
        relatedPassageMemo.retainManifest(Array(desired.values))
        let manifestHash = Self.manifestHash(for: Array(desired.values))
        let previous = try generation()
        let stored = try Self.indexedProjectionState(in: database)
        let desiredState = desired.mapValues(IndexedProjectionState.init)
        let changedKeys = desired.keys.filter { stored[$0] != desiredState[$0] }
        let removedKeys = Set(stored.keys).subtracting(desired.keys)
        let delta = SearchIndexDelta(
            workspaceGeneration: workspaceGeneration,
            upserts: changedKeys.compactMap { desired[$0] },
            deletions: try removedKeys.map {
                try Self.noteReference(documentKey: String(decoding: $0, as: UTF8.self))
            }
        )
        let preparationMilliseconds = Self.milliseconds(since: preparationStarted)
        let publicationStarted = ContinuousClock.now
        if previous?.sourceManifestHash == manifestHash, stored == desiredState,
            let previous
        {
            let identifier = UUID()
            let writer = writerDatabase
            let task = Task.detached(priority: .utility) {
                try await writer.asyncTransaction {
                    try await validateManifest()
                    try Self.requireNewerWorkspaceGeneration(
                        workspaceGeneration, in: writer)
                    try writer.execute(
                        "UPDATE search_index_state SET workspace_generation = ? WHERE singleton = 1;",
                        bindings: [.int(Int(workspaceGeneration))])
                }
                return SearchPublication(
                    result: TriptychSearchIndexSyncResult(
                        generation: previous, disposition: .unchanged),
                    preparation: .init())
            }
            let active = ActiveSynchronization(
                id: identifier, previous: previous, task: task, progress: nil)
            activeSynchronization = active
            let publication = try await finishSynchronization(active)
            recordSynchronizationTimings(
                documentCount: desired.count, changedCount: changedKeys.count,
                preparation: .init(), preparationMilliseconds: preparationMilliseconds,
                publicationStarted: publicationStarted)
            return publication.result
        }

        if let previous, previous.sequence > 0 {
            currentAvailability = .refreshing(lastGood: previous)
        } else {
            currentAvailability = .building(
                SearchBuildProgress(
                    completed: 0,
                    total: desired.count
                ))
        }

        let identifier = UUID()
        let writer = writerDatabase
        let triptychID = triptychID
        let recovered = recoveredGeneratedDatabase
        let configuredVaults = Dictionary(
            configuredVaults.map { ($0.key, ($0.value.name, $0.value.role)) },
            uniquingKeysWith: { first, _ in first }
        )
        let progress: ProgressDelivery?
        let progressReporter: (@Sendable (Int) -> Void)?
        if previous == nil {
            let expectedTotal = desired.count
            let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
            let task = Task { [weak self] in
                for await completed in stream {
                    guard let self else { return }
                    await self.recordInitialBuildProgress(
                        synchronizationID: identifier,
                        completed: completed,
                        total: expectedTotal
                    )
                }
            }
            progress = ProgressDelivery(continuation: continuation, task: task)
            progressReporter = { completed in
                _ = continuation.yield(completed)
            }
        } else {
            progress = nil
            progressReporter = nil
        }
        let task = Task.detached(priority: .utility) {
            try await Self.publish(
                delta: delta,
                desired: desired,
                sourceProjectionCaches: sourceProjectionCaches,
                manifestHash: manifestHash,
                previous: previous,
                recoveredGeneratedDatabase: recovered,
                configuredVaults: configuredVaults,
                triptychID: triptychID,
                database: writer,
                progress: progressReporter,
                loadChanged: loadChanged,
                validateManifest: validateManifest
            )
        }
        let active = ActiveSynchronization(
            id: identifier,
            previous: previous,
            task: task,
            progress: progress
        )
        activeSynchronization = active
        let publication = try await finishSynchronization(active)
        recordSynchronizationTimings(
            documentCount: desired.count, changedCount: changedKeys.count,
            preparation: publication.preparation, preparationMilliseconds: preparationMilliseconds,
            publicationStarted: publicationStarted)
        return publication.result
    }

    private nonisolated static func milliseconds(since started: ContinuousClock.Instant) -> Double {
        let parts = started.duration(to: .now).components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    private func recordSynchronizationTimings(
        documentCount: Int, changedCount: Int, preparation: SearchProjectionPreparation,
        preparationMilliseconds: Double, publicationStarted: ContinuousClock.Instant
    ) {
        let publicationMilliseconds = Self.milliseconds(since: publicationStarted)
        lastSynchronizationTimings = SearchSynchronizationTimings(
            documentCount: documentCount, changedCount: changedCount,
            projectedDocuments: preparation.projectedDocuments,
            restoredSearchProjections: preparation.restoredSearchProjections,
            projectionDuration: preparation.projectionDuration,
            cacheReadDuration: preparation.cacheReadDuration,
            cacheWriteDuration: preparation.cacheWriteDuration,
            preparationMilliseconds: preparationMilliseconds,
            publicationMilliseconds: publicationMilliseconds)
        Self.logger.info(
            "sync documents=\(documentCount, privacy: .public) changed=\(changedCount, privacy: .public) projected=\(preparation.projectedDocuments, privacy: .public) restored=\(preparation.restoredSearchProjections, privacy: .public) preparation_ms=\(preparationMilliseconds, privacy: .public) publication_ms=\(publicationMilliseconds, privacy: .public)"
        )
    }

    private func recordInitialBuildProgress(
        synchronizationID: UUID,
        completed: Int,
        total: Int
    ) {
        guard activeSynchronization?.id == synchronizationID,
            case .building = currentAvailability
        else { return }
        currentAvailability = .building(
            SearchBuildProgress(
                completed: completed,
                total: total
            ))
    }

    private func finishSynchronization(
        _ synchronization: ActiveSynchronization,
        joinedWaiter: Bool = false
    ) async throws -> SearchPublication {
        do {
            let publication = try await withTaskCancellationHandler {
                if joinedWaiter, let callback = joinedSynchronizationWaitForTesting {
                    await callback()
                }
                return try await synchronization.task.value
            } onCancel: {
                // A superseding caller may stop waiting without cancelling
                // the older request's sole transaction owner.
                if !joinedWaiter { synchronization.task.cancel() }
            }
            await finishProgress(synchronization)
            let result = publication.result
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                recoveredGeneratedDatabase = false
                currentAvailability = .current(result.generation)
                relatedBackgroundPreparation.retain(generation: result.generation)
                rankedSearchCache.removeAll(keepingCapacity: true)
                rankedSearchAccessClock = 0
            }
            return publication
        } catch is CancellationError {
            await finishProgress(synchronization)
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                currentAvailability =
                    synchronization.previous.map(SearchAvailability.current)
                    ?? .unavailable
            }
            throw CancellationError()
        } catch {
            await finishProgress(synchronization)
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                if let previous = synchronization.previous {
                    currentAvailability = .stale(
                        lastGood: previous,
                        reason: error.localizedDescription
                    )
                } else {
                    currentAvailability = .failed(
                        lastGood: nil,
                        reason: error.localizedDescription
                    )
                }
            }
            throw error
        }
    }

    private func finishProgress(_ synchronization: ActiveSynchronization) async {
        guard let progress = synchronization.progress else { return }
        progress.continuation.finish()
        await progress.task.value
    }

    private nonisolated static func publish(
        delta: SearchIndexDelta,
        desired: [Data: SearchIndexManifestEntry],
        sourceProjectionCaches: [UUID: SourceSearchProjectionCache],
        manifestHash: String,
        previous: SearchGenerationID?,
        recoveredGeneratedDatabase: Bool,
        configuredVaults: [UUID: (String, VaultRole)],
        triptychID: UUID,
        database: SearchSQLiteDatabase,
        progress: (@Sendable (Int) -> Void)?,
        loadChanged: @escaping @Sendable (SearchIndexManifestEntry) async throws -> SearchIndexDocument,
        validateManifest: @escaping @Sendable () async throws -> Void
    ) async throws -> SearchPublication {
        let preparation = try await database.asyncTransaction {
            var preparation = SearchProjectionPreparation()
            try Task.checkCancellation()
            try requireNewerWorkspaceGeneration(
                delta.workspaceGeneration,
                in: database
            )
            for deletion in delta.deletions.sorted(by: {
                if $0.vaultID != $1.vaultID {
                    return $0.vaultID.uuidString < $1.vaultID.uuidString
                }
                return $0.relativePath.utf8.lexicographicallyPrecedes($1.relativePath.utf8)
            }) {
                try deleteDocument(
                    key: documentKey(
                        vaultID: deletion.vaultID,
                        path: deletion.relativePath
                    ),
                    from: database
                )
            }
            let orderedUpserts = delta.upserts.sorted {
                documentKey(vaultID: $0.vaultID, path: $0.relativePath).utf8
                    .lexicographicallyPrecedes(documentKey(vaultID: $1.vaultID, path: $1.relativePath).utf8)
            }
            for (offset, entry) in orderedUpserts.enumerated() {
                try Task.checkCancellation()
                let document = try await loadChanged(entry)
                guard document.vaultID == entry.vaultID,
                    document.vaultName == entry.vaultName,
                    document.vaultRole == entry.vaultRole,
                    document.relativePath.utf8.elementsEqual(entry.relativePath.utf8),
                    document.stableNoteID == entry.stableNoteID,
                    document.document.fingerprint == entry.fingerprint,
                    document.hasBrokenLink == entry.hasBrokenLink,
                    document.evidentialLayer == entry.evidentialLayer
                else {
                    throw SearchIndexError.invalidDocuments(
                        "Changed Search source no longer matches its captured manifest"
                    )
                }
                let key = documentKey(
                    vaultID: document.vaultID,
                    path: document.relativePath
                )
                // Hydrate only this changed Note on the existing writer task.
                // Last-good readers remain available and each iteration releases
                // its complete text/coordinate projection after insertion.
                let prepared = PreparedSearchIndexDocument(
                    source: document, cache: sourceProjectionCaches[document.vaultID])
                preparation.add(prepared.preparation)
                try deleteDocument(key: key, from: database)
                try insert(prepared, into: database)
                let completed = offset + 1
                if completed == orderedUpserts.count || completed.isMultiple(of: 32) {
                    progress?(completed)
                }
            }
            try database.execute("DELETE FROM search_vaults;")
            let vaults = configuredVaults.merging(
                Dictionary(
                    desired.values.map { ($0.vaultID, ($0.vaultName, $0.vaultRole)) },
                    uniquingKeysWith: { first, _ in first }
                ),
                uniquingKeysWith: { _, documentDescriptor in documentDescriptor }
            )
            for vaultID in vaults.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let descriptor = vaults[vaultID] else { continue }
                try database.execute(
                    "INSERT INTO search_vaults(vault_id, vault_name, role) VALUES(?, ?, ?);",
                    bindings: [
                        .text(vaultID.uuidString.lowercased()),
                        .text(descriptor.0),
                        .text(descriptor.1.rawValue),
                    ]
                )
            }
            try database.execute(
                "UPDATE search_index_state SET sequence = sequence + 1, workspace_generation = ?, source_manifest_hash = ? WHERE singleton = 1;",
                bindings: [
                    .int(Int(delta.workspaceGeneration)),
                    .text(manifestHash),
                ]
            )
            try await validateManifest()
            try Task.checkCancellation()
            return preparation
        }
        guard let published = try readGeneration(in: database, triptychID: triptychID) else {
            throw SearchIndexError.invalidDocuments("Search v10 did not publish a generation")
        }
        let disposition: SearchIndexSyncDisposition
        if recoveredGeneratedDatabase {
            disposition = .recoveredAndRebuilt
        } else if previous == nil || previous?.sequence == 0 {
            disposition = .rebuilt
        } else {
            disposition = .incrementallyUpdated
        }
        return SearchPublication(
            result: TriptychSearchIndexSyncResult(generation: published, disposition: disposition),
            preparation: preparation)
    }

    public func search(
        _ request: SearchRequest,
        ast: SearchQueryAST,
        linkMatches: [SearchLinkQuery: SearchLinkResolution] = [:],
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]? = nil
    ) throws -> SearchResponse {
        try database.readTransaction {
            try Task.checkCancellation()
            let readGeneration = try generation()
            let availability = responseAvailability(for: readGeneration)
            let freshness: SearchFreshnessToken =
                switch request.executionScope {
                case .currentNote(let source): .currentNote(source)
                case .currentVault, .triptych:
                    readGeneration.map(SearchFreshnessToken.triptych)
                        ?? SearchFreshnessToken(
                            "triptych:\(triptychID.uuidString.lowercased()):unavailable"
                        )
                }
            guard request.hasConsistentScopes else {
                return SearchResponse(
                    requestID: request.id,
                    scope: request.presentationScope,
                    explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness,
                    availability: availability,
                    results: [],
                    hasMore: false,
                    diagnostics: [
                        SearchQueryDiagnostic(
                            reason: .inconsistentScopes,
                            message: "Search presentation and execution scopes do not match.",
                            utf16LowerBound: 0,
                            utf16UpperBound: 0
                        )
                    ]
                )
            }
            if let diagnostic = ast.scopeDiagnostic(scope: request.presentationScope, queryUTF16Count: request.query.utf16.count) {
                return SearchResponse(
                    requestID: request.id, scope: request.presentationScope, explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness, availability: availability, results: [], hasMore: false, diagnostics: [diagnostic])
            }
            guard request.limit > 0 else {
                return SearchResponse(
                    requestID: request.id,
                    scope: request.presentationScope,
                    explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness,
                    availability: availability,
                    results: [],
                    hasMore: false
                )
            }
            let boundedLimit = min(max(1, request.limit), SearchContract.maximumNoteResults)
            switch request.executionScope {
            case .currentNote(let source):
                return try searchCurrentNote(
                    source,
                    request: request,
                    ast: ast,
                    limit: boundedLimit,
                    freshness: freshness,
                    availability: availability,
                    linkMatches: linkMatches
                )
            case .currentVault(let vaultID):
                return try searchIndex(
                    request: request,
                    ast: ast,
                    vaultID: vaultID,
                    limit: boundedLimit,
                    freshness: freshness,
                    generation: readGeneration,
                    availability: availability,
                    linkMatches: linkMatches,
                    eligibleDocuments: eligibleDocuments
                )
            case .triptych:
                return try searchIndex(
                    request: request,
                    ast: ast,
                    vaultID: nil,
                    limit: boundedLimit,
                    freshness: freshness,
                    generation: readGeneration,
                    availability: availability,
                    linkMatches: linkMatches,
                    eligibleDocuments: eligibleDocuments
                )
            }
        }
    }

    /// Returns lexical completion terms from the same committed FTS
    /// generation used by Search. The caller supplies already-authorized scope
    /// and, during progressive opening, the exact source/fingerprint subset.
    /// No source document is reopened and no completion state is persisted.
    public func completionTerms(
        for lookup: SearchCompletionLookup,
        vaultID: UUID? = nil,
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]? = nil,
        limit: Int = SearchContract.maximumCompletionTerms
    ) throws -> [SearchCompletionTerm] {
        let normalizedPartial = lookup.normalizedPartial
        let boundedLimit = min(max(0, limit), SearchContract.maximumCompletionTerms)
        guard !normalizedPartial.isEmpty, boundedLimit > 0 else { return [] }
        let clause = SearchLexicalClause(
            field: lookup.field,
            value: .prefix(lookup.partial),
            sourceRange: 0..<0
        )
        guard let expression = try database.ftsExpression(for: [clause]) else { return [] }
        struct Accumulator {
            var text: String
            var fields: Set<SearchLexicalField>
            var occurrenceCount: Int
        }

        return try database.readTransaction {
            var predicates = ["search_fts MATCH ?"]
            var bindings: [SearchSQLiteBinding] = [.text(expression)]
            if let vaultID {
                predicates.append("d.vault_id = ?")
                bindings.append(.text(vaultID.uuidString.lowercased()))
            }
            if let eligibleDocuments {
                guard !eligibleDocuments.isEmpty else { return [] }
                let ordered = eligibleDocuments.sorted {
                    if $0.key.vaultID != $1.key.vaultID {
                        return $0.key.vaultID.uuidString < $1.key.vaultID.uuidString
                    }
                    return $0.key.relativePath < $1.key.relativePath
                }
                let eligibility = ordered.map { entry -> String in
                    bindings.append(.text(entry.key.vaultID.uuidString.lowercased()))
                    bindings.append(.text(entry.key.relativePath))
                    bindings.append(.text(entry.value.fingerprint.sha256))
                    bindings.append(.int(entry.value.fingerprint.byteCount))
                    return "(d.vault_id = ? AND d.relative_path = ? AND d.fingerprint_sha256 = ? AND d.fingerprint_byte_count = ?)"
                }
                predicates.append("(" + eligibility.joined(separator: " OR ") + ")")
            }

            var terms: [String: Accumulator] = [:]
            try database.query(
                """
                SELECT s.field, s.text
                FROM search_fts
                JOIN search_documents d ON d.id = search_fts.document_id
                JOIN search_segments s ON s.document_id = d.id
                WHERE \(predicates.joined(separator: " AND "))
                ORDER BY d.path_key, d.relative_path, s.ordinal;
                """,
                bindings: bindings
            ) { row in
                try Task.checkCancellation()
                // FTS owns candidate admission, never displayed vocabulary.
                // Original semantic segments preserve authored lexical spelling.
                if let rawField = row.text(at: 0), let field = SearchLexicalField(rawValue: rawField),
                    lookup.field == nil || lookup.field == field, let value = row.text(at: 1)
                {
                    for term in SearchTokenization.vocabularyTerms(in: value) {
                        let key = SearchTextNormalization.lexicalNormalize(term)
                        guard !key.isEmpty,
                            key.hasPrefix(normalizedPartial),
                            !["and", "or", "not"].contains(key)
                        else { continue }
                        if var existing = terms[key] {
                            existing.fields.insert(field)
                            existing.occurrenceCount += 1
                            terms[key] = existing
                        } else {
                            terms[key] = Accumulator(
                                text: term,
                                fields: [field],
                                occurrenceCount: 1
                            )
                        }
                    }
                }
            }
            return terms.values
                .map {
                    SearchCompletionTerm(
                        text: $0.text,
                        fields: Array($0.fields),
                        occurrenceCount: $0.occurrenceCount
                    )
                }
                .sorted { lhs, rhs in
                    let lhsNormalized = SearchTextNormalization.lexicalNormalize(lhs.text)
                    let rhsNormalized = SearchTextNormalization.lexicalNormalize(rhs.text)
                    let lhsExact = lhsNormalized == normalizedPartial
                    let rhsExact = rhsNormalized == normalizedPartial
                    if lhsExact != rhsExact { return lhsExact }
                    if lhs.occurrenceCount != rhs.occurrenceCount {
                        return lhs.occurrenceCount > rhs.occurrenceCount
                    }
                    if lhsNormalized.utf16.count != rhsNormalized.utf16.count {
                        return lhsNormalized.utf16.count < rhsNormalized.utf16.count
                    }
                    return lhsNormalized < rhsNormalized
                }
                .prefix(boundedLimit)
                .map { $0 }
        }
    }

    /// Prepares whole-Note candidates when unfocused. A focus independently
    /// retrieves all of its candidates, reusing only prepared row decoding.
    /// Workspace verifies current bytes before material scoring and limiting.
    public func relatedMaterialSourceCandidates(
        _ request: RelatedContentRequest
    ) throws -> RelatedContentResponse {
        try database.readTransaction {
            try Task.checkCancellation()
            let readGeneration = try generation()
            let availability = responseAvailability(for: readGeneration)
            let freshness =
                readGeneration.map(SearchFreshnessToken.triptych)
                ?? SearchFreshnessToken(
                    "triptych:\(triptychID.uuidString.lowercased()):unavailable"
                )

            guard case .current(let currentGeneration) = availability,
                currentGeneration.sequence > 0
            else {
                return RelatedContentResponse(
                    requestID: request.id,
                    seedFingerprint: request.seed.fingerprint,
                    freshnessToken: freshness,
                    availability: availability,
                    state: availability.lastGoodGeneration == nil
                        ? .unavailable
                        : .stale,
                    identityCandidates: [],
                    lexicalCandidates: [],
                    identityHasMore: false,
                    lexicalHasMore: false
                )
            }
            guard request.identityLimit > 0 || request.lexicalLimit > 0,
                !request.candidateRoles.isEmpty,
                !request.seed.source.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                request.seed.source.utf16.count
                    <= RelatedContentContract.maximumSeedUTF16Count,
                request.seed.focuses.allSatisfy({ focus in
                    focus.kind != .sourceNote
                        && !focus.text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                        && focus.text.utf16.count
                            <= RelatedContentContract.maximumFocusUTF16Count
                        && (focus.literalAlternatives.isEmpty
                            || (focus.kind == .researchRequest && focus.literalAlternatives.count <= 24
                                && focus.literalAlternatives.allSatisfy {
                                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        && $0.utf16.count <= 512 && !$0.contains(where: \.isNewline)
                                }))
                }),
                let descriptor = try vaultDescriptor(
                    request.seed.noteID.vaultID
                ),
                [.sourceCorpus, .topicKnowledge, .draftProject]
                    .contains(descriptor.role)
            else {
                return RelatedContentResponse(
                    requestID: request.id,
                    seedFingerprint: request.seed.fingerprint,
                    freshnessToken: freshness,
                    availability: availability,
                    state: .invalidSeed,
                    identityCandidates: [],
                    lexicalCandidates: [],
                    identityHasMore: false,
                    lexicalHasMore: false
                )
            }

            let document = NoteDocument(
                relativePath: request.seed.noteID.relativePath,
                rawContent: request.seed.source
            )
            let profile = WorkflowProfileResolver.resolve(
                vaultRole: descriptor.role
            )
            let projection = SearchDocumentProjection(
                document: document,
                profile: profile
            )
            var material = RelatedContentSeedMaterial(
                projection: projection,
                focuses: request.seed.focuses
            )
            guard !material.combinedTerms.isEmpty else {
                return RelatedContentResponse(
                    requestID: request.id,
                    seedFingerprint: request.seed.fingerprint,
                    freshnessToken: freshness,
                    availability: availability,
                    state: .invalidSeed,
                    identityCandidates: [],
                    lexicalCandidates: [],
                    identityHasMore: false,
                    lexicalHasMore: false
                )
            }

            let focused = !request.seed.focuses.isEmpty
            let identity = try relatedIdentityCandidates(
                material: material,
                excluding: request.seed.noteID,
                candidateRoles: request.candidateRoles,
                scan: focused || request.identityLimit > 0
            )
            material.includeUnsampledFocusedIdentities(identity.flatMap { $0.reason.mentions })
            let identityResults = identity.prefix(request.identityLimit).map { item in
                RelatedContentCandidate(
                    note: item.document.noteID, vaultRole: item.document.vaultRole, title: item.document.title,
                    fingerprint: item.document.fingerprint, reason: .identityMention(item.reason))
            }
            let focusedTerms = material.termGroups.filter { $0.kind != .sourceNote }.flatMap(\.terms)
            let scoringTerms = focused ? focusedTerms : material.combinedTerms
            let preparationKey = RelatedContentBackgroundPreparation.Key(
                seed: request.seed, generation: currentGeneration, roles: request.candidateRoles)
            let prepared = try relatedBackgroundPreparation.prepared(for: preparationKey) ?? .init()
            // A foreground cache miss performs only the ordinary focus scan;
            // it never synchronously rebuilds the whole-Note background pool.
            // Both paths use the same complete FTS pool and current payload checks.
            let pool = try relatedContentCandidates(
                terms: scoringTerms, material: material, preparationKey: preparationKey,
                prepareBackgroundPool: !focused,
                excluding: request.seed.noteID,
                candidateRoles: request.candidateRoles,
                reusing: prepared
            )
            let lexical = try Self.relatedLexicalResults(pool)
            if !focused, let preparation = pool.preparation {
                // Only a complete background scan publishes preparation. A
                // focused subset cannot overwrite a previously prepared Note.
                switch preparation {
                case .complete(let value):
                    try relatedBackgroundPreparation.store(value, for: preparationKey)
                case .oversized:
                    try relatedBackgroundPreparation.rejectOversizedCompletePool(for: preparationKey)
                }
            }
            try Task.checkCancellation()
            let lexicalHasMore = lexical.count > request.lexicalLimit
            let lexicalResults = lexical.map { item in
                RelatedContentCandidate(
                    note: item.candidate.document.noteID,
                    vaultRole: item.candidate.document.vaultRole,
                    title: item.candidate.document.title,
                    fingerprint: item.candidate.document.fingerprint,
                    reason: .lexicalOverlap(item.reason)
                )
            }
            let hasCandidates =
                !identityResults.isEmpty
                || !lexicalResults.isEmpty
            return RelatedContentResponse(
                requestID: request.id,
                seedFingerprint: request.seed.fingerprint,
                freshnessToken: freshness,
                availability: availability,
                state: hasCandidates ? .current : .empty,
                identityCandidates: identityResults,
                lexicalCandidates: Array(lexicalResults),
                identityHasMore: request.identityLimit > 0 && identity.count > request.identityLimit,
                lexicalHasMore: lexicalHasMore
            )
        }
    }

    private struct RelatedLexicalInput {
        let candidate: SearchCandidate
        let reason: RelatedContentLexicalReason
    }

    private enum RelatedPoolPreparation {
        case complete(RelatedContentBackgroundPreparation.Value)
        case oversized
    }

    private struct RelatedCandidatePool {
        let candidates: [RelatedLexicalInput]
        let scoring: RelatedContentBM25F.PreparedCorpus
        let preparation: RelatedPoolPreparation?
    }

    private nonisolated static func relatedLexicalResults(_ pool: RelatedCandidatePool) throws -> [RelatedLexicalCandidate] {
        let evaluation = try RelatedContentBM25F.evaluate(
            prepared: pool.scoring, roles: pool.candidates.map { $0.candidate.document.vaultRole })
        var results: [RelatedLexicalCandidate] = []
        for (input, score) in zip(pool.candidates, evaluation.scores) {
            try Task.checkCancellation()
            guard score > 0 else { continue }
            guard !input.reason.seedMatches.isEmpty else { continue }
            results.append(.init(candidate: input.candidate, reason: input.reason, score: score))
        }
        return results.sorted(by: RelatedLexicalCandidate.precedes)
    }

    private func searchIndex(
        request: SearchRequest,
        ast: SearchQueryAST,
        vaultID: UUID?,
        limit: Int,
        freshness: SearchFreshnessToken,
        generation: SearchGenerationID?,
        availability: SearchAvailability,
        linkMatches: [SearchLinkQuery: SearchLinkResolution],
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]?
    ) throws -> SearchResponse {
        guard let generation, generation.sequence > 0 else {
            return SearchResponse(
                requestID: request.id,
                scope: request.presentationScope,
                explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: freshness,
                availability: availability,
                results: [],
                hasMore: false
            )
        }
        let required = Self.requiredResultCount(offset: request.resultOffset, limit: limit)
        if request.includedVaultIDs?.isEmpty == true {
            return SearchResponse(
                requestID: request.id, scope: request.presentationScope, explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: freshness, availability: availability, results: [], hasMore: false)
        }
        let includesParagraphs = ast.clauses.contains {
            if case .paragraph = $0 { true } else { false }
        }
        let includesLexicalSegments = ast.clauses.contains {
            if case .lexical = $0 { true } else { false }
        }
        let includesProperties = ast.hasPropertyClause
        let cacheKey: RankedSearchCacheKey? = {
            guard eligibleDocuments == nil,
                linkMatches.isEmpty,
                ast.linkQueries.isEmpty,
                required <= Self.maximumCachedRankedResults
            else { return nil }
            return RankedSearchCacheKey(
                generation: generation,
                ast: ast,
                vaultID: vaultID,
                includedVaultIDs: request.includedVaultIDs ?? [])
        }()

        let rankedItems: [RankedSearchItem]
        let total: Int
        let indeterminate: Int
        // A complete result set also satisfies requests beyond its final row,
        // including empty results, without another corpus scan.
        if let cacheKey, var cached = rankedSearchCache[cacheKey],
            required <= cached.items.count || cached.total <= cached.items.count
        {
            rankedSearchAccessClock &+= 1
            cached.lastAccess = rankedSearchAccessClock
            rankedSearchCache[cacheKey] = cached
            rankedItems = cached.items
            total = cached.total
            indeterminate = cached.indeterminate
        } else {
            #if DEBUG
                rankedSearchExecutionCountsForTesting.candidateScans += 1
            #endif
            let ranks = try lexicalRanks(for: ast)
            let normalizedNeedles = SearchMatcher.normalizedNeedles(for: ast.expression)
            let admission = try candidateAdmission(ast.expression)
            var sql = "SELECT d.id FROM search_documents d WHERE " + admission.sql
            var bindings = admission.bindings
            if let vaultID {
                sql += " AND d.vault_id = ?"
                bindings.append(.text(vaultID.uuidString.lowercased()))
            }
            if let included = request.includedVaultIDs {
                sql += " AND d.vault_id IN (" + Array(repeating: "?", count: included.count).joined(separator: ",") + ")"
                bindings.append(contentsOf: included.sorted { $0.uuidString < $1.uuidString }.map { .text($0.uuidString.lowercased()) })
            }
            var rowIDs: [Int] = []
            try database.query(sql, bindings: bindings) { rowIDs.append($0.int(at: 0)) }
            let rankingLimit = cacheKey == nil ? required : Self.maximumCachedRankedResults
            var accepted: [(candidate: SearchCandidate, evaluation: SearchEvaluation)] = []
            var evaluatedTotal = 0
            var evaluatedIndeterminate = 0
            for rowID in rowIDs {
                try Task.checkCancellation()
                guard
                    let document = try loadDocument(
                        rowID: rowID, includingProperties: includesProperties,
                        includingParagraphs: includesParagraphs,
                        includingAliases: ast.identityNeedle != nil,
                        includingSegments: includesLexicalSegments || includesParagraphs,
                        includingSourceEvidence: includesParagraphs),
                    Self.isEligible(document, in: eligibleDocuments)
                else { continue }
                let evaluation = SearchMatcher.evaluate(
                    ast, document: document, linkMatches: linkMatches,
                    normalizedNeedles: normalizedNeedles)
                if evaluation.truth == .unknown { evaluatedIndeterminate += 1 }
                guard evaluation.truth == .yes else { continue }
                evaluatedTotal += 1
                var keys = Set(
                    evaluation.matches.compactMap { predicate -> SearchLexicalClause? in
                        guard !predicate.excluded, case .lexical(let clause) = predicate.clause else { return nil }
                        return Self.rankingKey(clause)
                    })
                if includesParagraphs {
                    let matched = ast.matched(by: evaluation)
                    keys.formUnion(
                        SearchMatcher.paragraphWitnesses(matched, document: document)
                            .flatMap { $0.ast.positiveLexicalClauses }.map(Self.rankingKey))
                }
                let rank = keys.reduce(0.0) { $0 + (ranks[$1]?[rowID] ?? 0) }
                let candidate = SearchCandidate(
                    document: document,
                    identityPriority: SearchMatcher.identityPriority(identityNeedle: ast.identityNeedle, document: document), lexicalRank: rank)
                if accepted.count == rankingLimit, let last = accepted.last,
                    !SearchCandidate.precedes(candidate, last.candidate)
                {
                    continue
                }
                var lower = 0
                var upper = accepted.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    if SearchCandidate.precedes(candidate, accepted[middle].candidate) {
                        upper = middle
                    } else {
                        lower = middle + 1
                    }
                }
                if lower < rankingLimit {
                    accepted.insert((candidate, evaluation), at: lower)
                    if accepted.count > rankingLimit { accepted.removeLast() }
                }
            }
            rankedItems = accepted.map { item in
                RankedSearchItem(
                    rowID: item.candidate.document.rowID,
                    identityPriority: item.candidate.identityPriority,
                    lexicalRank: item.candidate.lexicalRank,
                    evaluation: item.evaluation)
            }
            total = evaluatedTotal
            indeterminate = evaluatedIndeterminate
            if let cacheKey {
                if rankedSearchCache[cacheKey] == nil,
                    rankedSearchCache.count >= Self.maximumCachedRankedQueries,
                    let oldest = rankedSearchCache.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key
                {
                    rankedSearchCache.removeValue(forKey: oldest)
                }
                rankedSearchAccessClock &+= 1
                rankedSearchCache[cacheKey] = RankedSearchCacheValue(
                    items: rankedItems,
                    total: total,
                    indeterminate: indeterminate,
                    lastAccess: rankedSearchAccessClock)
            }
        }
        // Counting and ranking need exact predicate values, but only this page needs
        // source offset maps and snippet material. Hydrate within the same read
        // transaction so the match, fingerprint and source locator cannot diverge.
        let hits = try rankedItems.dropFirst(min(request.resultOffset, rankedItems.count)).prefix(limit).map { item in
            try Task.checkCancellation()
            guard
                let document = try loadDocument(
                    rowID: item.rowID,
                    includingProperties: includesProperties,
                    includingParagraphs: includesParagraphs
                )
            else { throw SearchIndexError.corruptDatabase }
            let candidate = SearchCandidate(
                document: document, identityPriority: item.identityPriority,
                lexicalRank: item.lexicalRank)
            return NoteSearchResultBuilder.hit(
                candidate: candidate, ast: ast.matched(by: item.evaluation), freshness: freshness, linkMatches: linkMatches)
        }
        return SearchResponse(
            requestID: request.id, scope: request.presentationScope, explanation: ast.explanation(scope: request.presentationScope),
            freshnessToken: freshness, availability: availability, results: hits.map(SearchResult.note),
            hasMore: request.resultOffset < total && hits.count < total - request.resultOffset, totalResultCount: total,
            indeterminateDocumentCount: indeterminate)
    }

    private nonisolated static func isEligible(
        _ document: StoredSearchDocument,
        in eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]?
    ) -> Bool {
        guard let eligibleDocuments else { return true }
        guard let eligibility = eligibleDocuments[document.noteID],
            eligibility.fingerprint == document.fingerprint
        else {
            return false
        }
        guard let storedStableNoteID = document.stableNoteID else { return true }
        guard let indexedStableNoteID = UUID(uuidString: storedStableNoteID) else {
            return false
        }
        return eligibility.resolvedStableNoteID == indexedStableNoteID
    }

    private nonisolated static func requiredResultCount(
        offset: Int,
        limit: Int
    ) -> Int {
        let requestedUpperBound = offset.addingReportingOverflow(limit)
        let probedUpperBound = requestedUpperBound.partialValue
            .addingReportingOverflow(1)
        return requestedUpperBound.overflow || probedUpperBound.overflow
            ? Int.max
            : probedUpperBound.partialValue
    }

    private func relatedIdentityCandidates(
        material: RelatedContentSeedMaterial,
        excluding seed: VaultQualifiedNoteID,
        candidateRoles: [RelatedContentCandidateRole],
        scan: Bool
    ) throws -> [RelatedIdentityCandidate] {
        guard scan else { return [] }
        let rolePlaceholders = candidateRoles.map { _ in "?" }
            .joined(separator: ", ")
        let bindings =
            candidateRoles.map {
                SearchSQLiteBinding.text($0.vaultRole.rawValue)
            } + [
                .text(seed.vaultID.uuidString.lowercased()),
                .text(seed.relativePath),
            ]
        // Both reads belong to the caller's fixed-generation transaction. Keep
        // aliases in authored ordinal order without multiplying document rows.
        var aliasesByDocument: [Int: [String]] = [:]
        try database.query(
            """
            SELECT a.document_id, a.alias
            FROM search_aliases a
            JOIN search_documents d ON d.id = a.document_id
            WHERE d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY a.document_id, a.ordinal;
            """,
            bindings: bindings
        ) { row in
            try Task.checkCancellation()
            if let alias = row.text(at: 1) {
                aliasesByDocument[row.int(at: 0), default: []].append(alias)
            }
        }
        var matches: [RelatedIdentityCandidate] = []
        try database.query(
            """
            SELECT \(Self.documentColumns(includingSourceEvidence: false)), d.id
            FROM search_documents d
            WHERE d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY d.normalized_title, d.role_order, d.path_key,
                     d.relative_path;
            """,
            bindings: bindings
        ) { row in
            try Task.checkCancellation()
            guard
                let document = try self.decodeDocument(
                    row, rowID: row.int(at: 23), includingSegments: false, includingSourceEvidence: false,
                    preparedAliases: aliasesByDocument[row.int(at: 23)] ?? []),
                let reason = material.identityMentionReason(for: document)
            else { return }
            matches.append(
                RelatedIdentityCandidate(
                    document: document,
                    reason: reason
                ))
        }
        matches.sort(by: RelatedIdentityCandidate.precedes)
        return matches
    }

    private func relatedContentCandidates(
        terms: [String], material: RelatedContentSeedMaterial,
        preparationKey: RelatedContentBackgroundPreparation.Key,
        prepareBackgroundPool: Bool,
        excluding seed: VaultQualifiedNoteID,
        candidateRoles: [RelatedContentCandidateRole],
        reusing prepared: RelatedContentBackgroundPreparation.Value
    ) throws -> RelatedCandidatePool {
        var scoring = RelatedContentBM25F.PreparedCorpus(terms: terms)
        guard !terms.isEmpty else {
            return .init(
                candidates: [], scoring: scoring,
                preparation: prepareBackgroundPool ? .complete(.init()) : nil)
        }
        let constraints = try terms.map { term in
            try database.ftsExpression(for: [.init(field: nil, value: .term(term), sourceRange: 0..<0)])
        }
        // OR recall must retain even terms that this native tokenizer cannot
        // represent. Role/seed scope and exact lexical verification still apply.
        let unrestricted = constraints.contains { $0 == nil }
        let expression = constraints.compactMap { $0 }.joined(separator: " OR ")
        let rolePlaceholders = candidateRoles.map { _ in "?" }
            .joined(separator: ", ")
        var result: [RelatedLexicalInput] = []
        var preparation = RelatedContentBackgroundPreparation.Value()
        var preparationEstimatedBytes = preparation.estimatedByteCount
        var preparationOversized = false
        #if DEBUG
            relatedLexicalPoolObserverForTesting?(
                .init(
                    phase: .begin, candidateCount: 0, retainedProjectionCount: 0,
                    completePoolEstimatedBytes: preparationEstimatedBytes))
        #endif
        try database.query(
            """
            SELECT \(Self.documentColumns(includingSourceEvidence: false, includingRelatedRankingText: true)), d.id
            FROM search_fts
            JOIN search_documents d ON d.id = search_fts.document_id
            WHERE \(unrestricted ? "1 = 1" : "search_fts MATCH ?")
              AND d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY d.normalized_title, d.role_order, d.path_key, d.relative_path;
            """,
            bindings: (unrestricted ? [] : [.text(expression)])
                + candidateRoles.map {
                    .text($0.vaultRole.rawValue)
                } + [
                    .text(seed.vaultID.uuidString.lowercased()),
                    .text(seed.relativePath),
                ]
        ) { row in
            try Task.checkCancellation()
            guard
                let document = try self.decodeDocument(
                    row, rowID: row.int(at: 23), includingAliases: false,
                    includingSourceEvidence: false, includingRelatedRankingText: true,
                    preparedRelatedLexical: prepared.documents[row.int(at: 23)])
            else { return }
            let projection = document.relatedLexical!
            try scoring.append(projection.scoringDocument)
            try Task.checkCancellation()
            let reason = material.lexicalReason(for: projection)
            var compactDocument = document
            compactDocument.relatedLexical = nil
            result.append(
                .init(
                    candidate: .init(document: compactDocument, identityPriority: 10, lexicalRank: 0),
                    reason: reason))
            if prepareBackgroundPool {
                let cacheDocument = RelatedContentBackgroundPreparation.LexicalDocument(
                    fingerprint: document.fingerprint, checksum: row.text(at: 22)!, projection: projection)
                let (nextEstimate, overflow) = preparationEstimatedBytes.addingReportingOverflow(
                    64 + cacheDocument.estimatedByteCount)
                preparationEstimatedBytes = overflow ? Int.max : nextEstimate
                if !preparationOversized {
                    if overflow
                        || !self.relatedBackgroundPreparation.fitsBudget(
                            valueEstimatedByteCount: nextEstimate, for: preparationKey)
                    {
                        // A partial pool cannot be a cache hit. Release the
                        // entire candidate before scoring compact records.
                        preparation.documents.removeAll(keepingCapacity: false)
                        preparationOversized = true
                    } else {
                        preparation.documents[document.rowID] = cacheDocument
                    }
                }
            }
            #if DEBUG
                self.relatedLexicalPoolObserverForTesting?(
                    .init(
                        phase: .row, candidateCount: result.count,
                        retainedProjectionCount: preparation.documents.count,
                        completePoolEstimatedBytes: preparationEstimatedBytes))
            #endif
        }
        #if DEBUG
            relatedLexicalPoolObserverForTesting?(
                .init(
                    phase: .end, candidateCount: result.count,
                    retainedProjectionCount: preparation.documents.count,
                    completePoolEstimatedBytes: preparationEstimatedBytes))
        #endif
        let cacheCandidate: RelatedPoolPreparation? =
            prepareBackgroundPool ? (preparationOversized ? .oversized : .complete(preparation)) : nil
        return .init(candidates: result, scoring: scoring, preparation: cacheCandidate)
    }

    private func searchCurrentNote(
        _ source: SearchSourceSnapshot,
        request: SearchRequest,
        ast: SearchQueryAST,
        limit: Int,
        freshness: SearchFreshnessToken,
        availability: SearchAvailability,
        linkMatches: [SearchLinkQuery: SearchLinkResolution]
    ) throws -> SearchResponse {
        let descriptor = try vaultDescriptor(source.noteID.vaultID)
        let indexed = try indexedDocumentMetadata(source.noteID)
        let note = NoteDocument(
            relativePath: source.noteID.relativePath,
            rawContent: source.source
        )
        let exactIndexedRevision = indexed?.fingerprint == note.fingerprint
        let role = descriptor?.role ?? .other
        let profile = WorkflowProfileResolver.resolve(vaultRole: role)
        let projection = SearchDocumentProjection(
            document: note,
            profile: profile,
            hasBrokenLink: exactIndexedRevision ? (indexed?.hasBrokenLink ?? false) : false
        )
        // One Yams compose per note; entries and issues come from the same parse.
        let noteProperties = SearchPropertyProjection(document: note, profile: profile)
        let document = StoredSearchDocument(
            rowID: indexed?.rowID ?? -1,
            vaultID: source.noteID.vaultID,
            vaultName: descriptor?.name ?? source.noteID.vaultID.uuidString,
            vaultRole: role,
            relativePath: source.noteID.relativePath,
            stableNoteID: source.stableNoteID?.uuidString.lowercased()
                ?? indexed?.stableNoteID,
            title: projection.title,
            normalizedTitle: SearchTextNormalization.normalize(projection.title),
            filenameKey: SearchTextNormalization.normalize(
                ((source.noteID.relativePath as NSString).lastPathComponent as NSString)
                    .deletingPathExtension
            ),
            pathKey: SearchTextNormalization.normalize(source.noteID.relativePath),
            aliases: projection.aliases,
            calloutRoles: projection.calloutRoles,
            hasBrokenLink: projection.hasBrokenLink,
            fingerprint: note.fingerprint,
            evidentialLayer: Self.evidentialLayer(for: role),
            roleOrder: Self.roleOrder(role),
            sourceLineStarts: projection.sourceLineStartsUTF16,
            segments: projection.segments,
            paragraphs: projection.paragraphs,
            paragraphsAreComplete: note.hasProvableBodyBoundary,
            properties: noteProperties.entries,
            propertyIssues: noteProperties.issues
        )
        let evaluation = SearchMatcher.evaluate(ast, document: document, linkMatches: linkMatches)
        guard evaluation.truth == .yes else {
            return SearchResponse(
                requestID: request.id,
                scope: request.presentationScope,
                explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: freshness,
                availability: availability,
                results: [],
                hasMore: false
            )
        }

        let matchedAST = ast.matched(by: evaluation)
        let candidate = SearchCandidate(
            document: document,
            identityPriority: SearchMatcher.identityPriority(
                identityNeedle: ast.identityNeedle,
                document: document
            ),
            lexicalRank: 0
        )
        let resultOffset = request.resultOffset
        let requiredHitCount = Self.requiredResultCount(
            offset: resultOffset,
            limit: limit
        )
        let candidates: [NoteSearchResult]
        if !matchedAST.isFilterOnly {
            candidates = NoteSearchResultBuilder.occurrenceHits(
                candidate: candidate,
                ast: matchedAST,
                freshness: freshness,
                limit: requiredHitCount,
                linkMatches: linkMatches
            )
        } else {
            candidates = [
                NoteSearchResultBuilder.hit(
                    candidate: candidate,
                    ast: matchedAST,
                    freshness: freshness,
                    linkMatches: linkMatches
                )
            ]
        }
        let page = candidates.dropFirst(min(resultOffset, candidates.count))
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: ast.explanation(scope: request.presentationScope),
            freshnessToken: freshness,
            availability: availability,
            results: page.prefix(limit).map(SearchResult.note),
            hasMore: page.count > limit
        )
    }

    private func responseAvailability(
        for generation: SearchGenerationID?
    ) -> SearchAvailability {
        if let generation,
            case .refreshing(let lastGood) = currentAvailability,
            generation != lastGood
        {
            // The writer committed before its awaiting continuation resumed.
            // This read transaction has already captured the complete new
            // generation, so expose it as current rather than mislabelling it.
            currentAvailability = .current(generation)
        }
        return currentAvailability
    }

    private static func rankingKey(_ clause: SearchLexicalClause) -> SearchLexicalClause {
        let text = SearchTextNormalization.lexicalNormalize(clause.value.text)
        let value: SearchLexicalValue =
            switch clause.value {
            case .term: .term(text)
            case .phrase: .phrase(text)
            case .prefix: .prefix(text)
            }
        return SearchLexicalClause(field: clause.field, value: value, sourceRange: 0..<0)
    }

    private func lexicalRanks(for ast: SearchQueryAST) throws -> [SearchLexicalClause: [Int: Double]] {
        #if DEBUG
            rankedSearchExecutionCountsForTesting.rankingPasses += 1
        #endif
        var ranks: [SearchLexicalClause: [Int: Double]] = [:]
        for clause in ast.rankingLexicalClauses {
            try Task.checkCancellation()
            let key = Self.rankingKey(clause)
            guard ranks[key] == nil else { continue }
            var values: [Int: Double] = [:]
            guard let expression = try database.ftsExpression(for: [clause]) else {
                ranks[key] = values
                continue
            }
            // All roles retain one corpus for statistics and admission. Role
            // changes field salience only; exact identity is ordered separately.
            try database.query(
                """
                SELECT search_fts.document_id,
                       CASE d.role
                         WHEN 'source_corpus' THEN bm25(search_fts, 0.0, 3.0, 9.0, 7.0, 6.0, 7.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.0)
                         WHEN 'topic_knowledge' THEN bm25(search_fts, 0.0, 3.0, 9.0, 9.0, 7.0, 5.0, 6.0, 4.0, 7.0, 2.0, 2.0, 3.0, 1.0)
                         WHEN 'draft_project' THEN bm25(search_fts, 0.0, 3.0, 8.0, 7.0, 8.0, 5.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.5)
                         ELSE bm25(search_fts, 0.0, 3.0, 8.0, 7.0, 6.0, 5.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.0)
                       END
                FROM search_fts JOIN search_documents d ON d.id = search_fts.document_id
                WHERE search_fts MATCH ?;
                """,
                bindings: [.text(expression)]
            ) { row in
                try Task.checkCancellation()
                values[row.int(at: 0)] = row.double(at: 1)
            }
            ranks[key] = values
        }
        return ranks
    }

    /// FTS is a candidate superset, not proof of a phrase or exclusion. Negated predicates
    /// and property/link uncertainty must not be discarded before exact evaluation.
    private func candidateAdmission(_ expression: SearchExpression, negated: Bool = false) throws -> (sql: String, bindings: [SearchSQLiteBinding]) {
        switch expression {
        case .clause(let clause):
            if !negated, case .paragraph(let query) = clause {
                let inner = try candidateAdmission(query.expression)
                return ("(d.paragraphs_complete = 0 OR " + inner.sql + ")", inner.bindings)
            }
            if !negated, case .lexical(let value) = clause {
                guard let constraint = try database.ftsExpression(for: [value]) else { return ("1 = 1", []) }
                return ("d.id IN (SELECT document_id FROM search_fts WHERE search_fts MATCH ?)", [.text(constraint)])
            }
            return ("1 = 1", [])
        case .not(let child): return try candidateAdmission(child, negated: !negated)
        case .and(let children), .or(let children):
            let conjunction: Bool
            if case .and = expression { conjunction = !negated } else { conjunction = negated }
            guard !children.isEmpty else { return (conjunction ? "1 = 1" : "0 = 1", []) }
            let pieces = try children.map { try candidateAdmission($0, negated: negated) }
            return ("(" + pieces.map(\.sql).joined(separator: conjunction ? " AND " : " OR ") + ")", pieces.flatMap(\.bindings))
        }
    }

    // One column layout and decoder serve single-row Search loads and batched
    // Related-Content reads. Batched callers append d.id at column 23.
    private nonisolated static func documentColumns(
        includingProperties: Bool = false, includingParagraphs: Bool = false,
        includingSourceEvidence: Bool = true, includingRelatedRankingText: Bool = false
    ) -> String {
        """
        d.vault_id, d.vault_name, d.role, d.relative_path, d.stable_note_id, d.title,
        d.normalized_title, d.title_key, d.filename_key, d.path_key, d.callout_roles,
        d.has_broken_link, d.fingerprint_sha256, d.fingerprint_byte_count,
        d.evidential_layer, d.role_order, \(includingSourceEvidence ? "d.line_starts" : "NULL"), d.source_utf16_count,
        \(includingProperties ? "d.property_issues" : "NULL"), \(includingParagraphs ? "d.paragraphs" : "NULL"), d.paragraphs_complete,
        \(includingRelatedRankingText ? "d.related_lexical" : "NULL"), \(includingRelatedRankingText ? "d.related_lexical_hash" : "NULL")
        """
    }

    private func loadDocument(
        rowID: Int,
        includingProperties: Bool = false, includingParagraphs: Bool = false,
        includingAliases: Bool = true, includingSegments: Bool = true, includingSourceEvidence: Bool = true,
        includingRelatedRankingText: Bool = false
    ) throws -> StoredSearchDocument? {
        var document: StoredSearchDocument?
        try database.query(
            """
            SELECT \(Self.documentColumns(
                includingProperties: includingProperties, includingParagraphs: includingParagraphs,
                includingSourceEvidence: includingSourceEvidence, includingRelatedRankingText: includingRelatedRankingText))
            FROM search_documents d WHERE d.id = ?;
            """,
            bindings: [.int(rowID)]
        ) { row in
            document = try self.decodeDocument(
                row, rowID: rowID, includingProperties: includingProperties, includingParagraphs: includingParagraphs,
                includingAliases: includingAliases, includingSegments: includingSegments,
                includingSourceEvidence: includingSourceEvidence, includingRelatedRankingText: includingRelatedRankingText)
        }
        return document
    }

    private func decodeDocument(
        _ row: SearchSQLiteStatement, rowID: Int,
        includingProperties: Bool = false, includingParagraphs: Bool = false,
        includingAliases: Bool = true, includingSegments: Bool = true, includingSourceEvidence: Bool = true,
        includingRelatedRankingText: Bool = false, preparedAliases: [String]? = nil,
        preparedRelatedLexical: RelatedContentBackgroundPreparation.LexicalDocument? = nil
    ) throws -> StoredSearchDocument? {
        guard let vaultText = row.text(at: 0), let vaultID = UUID(uuidString: vaultText),
            let vaultName = row.text(at: 1), let roleText = row.text(at: 2),
            let role = VaultRole(rawValue: roleText), let path = row.text(at: 3),
            let title = row.text(at: 5), let normalizedTitle = row.text(at: 6),
            row.text(at: 7) != nil, let filenameKey = row.text(at: 8),
            let pathKey = row.text(at: 9), let sha = row.text(at: 12),
            let layerText = row.text(at: 14),
            let layer = EvidentialLayer(rawValue: layerText)
        else { return nil }
        let sourceUTF16Count = row.int(at: 17)
        guard sourceUTF16Count >= 0 else { throw SearchIndexError.corruptDatabase }
        let lineStarts: [Int]
        if includingSourceEvidence {
            lineStarts = try Self.decodeGeneratedJSON([Int].self, from: row.text(at: 16))
            guard sourceUTF16Count >= 0,
                lineStarts.first == 0,
                lineStarts.last.map({ $0 <= sourceUTF16Count }) == true,
                zip(lineStarts, lineStarts.dropFirst()).allSatisfy({ previous, next in previous < next })
            else { throw SearchIndexError.corruptDatabase }
        } else {
            lineStarts = []
        }
        let aliases = includingAliases ? try (preparedAliases ?? self.aliases(documentID: rowID)) : []
        let segments: [SearchTextSegment]
        if includingSegments && !includingRelatedRankingText {
            segments = try self.segments(
                documentID: rowID, sourceUTF16Count: sourceUTF16Count,
                includingSourceEvidence: includingSourceEvidence,
                includingRelatedRankingText: includingRelatedRankingText)
        } else {
            segments = []
        }
        let properties = includingProperties ? try self.properties(documentID: rowID) : []
        let fingerprint = DocumentFingerprint(sha256: sha, byteCount: row.int(at: 13))
        let relatedLexical: RelatedContentLexicalProjection?
        if includingRelatedRankingText {
            let payload = row.data(at: 21)
            let checksum = row.text(at: 22)
            if let preparedRelatedLexical,
                preparedRelatedLexical.matches(payload, checksum: checksum, fingerprint: fingerprint)
            {
                relatedLexical = preparedRelatedLexical.projection
            } else {
                relatedLexical = try RelatedContentLexicalProjection.decode(payload, checksum: checksum)
            }
        } else {
            relatedLexical = nil
        }
        return StoredSearchDocument(
            rowID: rowID,
            vaultID: vaultID,
            vaultName: vaultName,
            vaultRole: role,
            relativePath: path,
            stableNoteID: row.text(at: 4),
            title: title,
            normalizedTitle: normalizedTitle,
            filenameKey: filenameKey,
            pathKey: pathKey,
            aliases: aliases,
            calloutRoles: Set((row.text(at: 10) ?? "").split(separator: " ").map(String.init)),
            hasBrokenLink: row.int(at: 11) == 1,
            fingerprint: fingerprint,
            evidentialLayer: layer,
            roleOrder: row.int(at: 15),
            sourceLineStarts: lineStarts,
            segments: segments,
            paragraphs: includingParagraphs ? try Self.decodeParagraphs(row.text(at: 19), sourceUTF16Count: sourceUTF16Count) : [],
            paragraphsAreComplete: row.int(at: 20) == 1,
            properties: properties,
            propertyIssues: includingProperties ? try Self.decodeGeneratedJSON([SearchPropertyProjection.Issue].self, from: row.text(at: 18)) : [],
            relatedLexical: relatedLexical)
    }

    private func aliases(documentID: Int) throws -> [String] {
        var result: [String] = []
        try database.query(
            "SELECT alias FROM search_aliases WHERE document_id = ? ORDER BY ordinal;",
            bindings: [.int(documentID)]
        ) { if let value = $0.text(at: 0) { result.append(value) } }
        return result
    }

    private func segments(
        documentID: Int,
        sourceUTF16Count: Int,
        includingSourceEvidence: Bool = true,
        includingRelatedRankingText: Bool = false
    ) throws -> [SearchTextSegment] {
        // Predicate evaluation consumes only field and normalized text. Avoid
        // decoding and validating every candidate's source maps for a short page.
        if !includingSourceEvidence {
            var segments: [SearchTextSegment] = []
            try database.query(
                "SELECT field, ordinal, normalized_text, \(includingRelatedRankingText ? "related_ranking_text" : "NULL") FROM search_segments WHERE document_id = ? ORDER BY ordinal;",
                bindings: [.int(documentID)]
            ) { row in
                guard let fieldText = row.text(at: 0),
                    let field = SearchMatchedField(rawValue: fieldText),
                    let normalized = row.text(at: 2)
                else { throw SearchIndexError.corruptDatabase }
                segments.append(
                    SearchTextSegment(
                        field: field, ordinal: row.int(at: 1), text: "",
                        normalizedText: normalized, sourceRange: nil, offsetMap: [],
                        relatedRankingText: includingRelatedRankingText
                            ? try Self.decodeGeneratedJSON([String: String].self, from: row.text(at: 3))
                            : [:]))
            }
            return segments
        }
        var result: [SearchTextSegment] = []
        try database.query(
            """
            SELECT field, ordinal, text, normalized_text, source_lower, source_upper,
                   source_line, source_column, source_end_line, source_end_column, offset_map, related_ranking_text
            FROM search_segments WHERE document_id = ? ORDER BY ordinal;
            """,
            bindings: [.int(documentID)]
        ) { row in
            guard let fieldText = row.text(at: 0),
                let field = SearchMatchedField(rawValue: fieldText),
                let text = row.text(at: 2), let normalized = row.text(at: 3)
            else { return }
            let sourceRange: SearchSourceRange?
            if row.isNull(at: 4) {
                sourceRange = nil
            } else {
                sourceRange = SearchSourceRange(
                    utf16LowerBound: row.int(at: 4),
                    utf16UpperBound: row.int(at: 5),
                    line: row.int(at: 6),
                    column: row.int(at: 7),
                    endLine: row.int(at: 8),
                    endColumn: row.int(at: 9)
                )
            }
            let offsets = try SearchOffsetMapCodec.decode(row.data(at: 10))
            guard
                SearchProjectionValidation.valid(
                    offsets: offsets,
                    normalizedUTF16Count: normalized.utf16.count,
                    sourceUTF16Bounds: sourceRange.map {
                        (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound)
                    },
                    sourceUTF16Count: sourceUTF16Count
                )
            else {
                throw SearchIndexError.corruptDatabase
            }
            result.append(
                SearchTextSegment(
                    field: field,
                    ordinal: row.int(at: 1),
                    text: text,
                    normalizedText: normalized,
                    sourceRange: sourceRange,
                    offsetMap: offsets,
                    relatedRankingText: try Self.decodeGeneratedJSON([String: String].self, from: row.text(at: 11))
                ))
        }
        return result
    }

    private func properties(
        documentID: Int
    ) throws -> [SearchPropertyProjection.Entry] {
        struct Accumulator {
            let key: String
            let keyRange: SearchSourceRange?
            let valueKind: SearchPropertyProjection.ValueKind
            let isEmpty: Bool
            var members: [SearchPropertyProjection.StringMember]
        }
        var values: [String: Accumulator] = [:]
        try database.query(
            """
            SELECT property_key, value_kind, is_empty, ordinal, raw_value, normalized_value,
                   key_lower, key_upper, key_line, key_column, key_end_line,
                   key_end_column, value_lower, value_upper, value_line,
                   value_column, value_end_line, value_end_column
            FROM search_properties
            WHERE document_id = ?
            ORDER BY property_key, ordinal;
            """,
            bindings: [.int(documentID)]
        ) { row in
            guard let key = row.text(at: 0),
                let kindText = row.text(at: 1),
                let kind = SearchPropertyProjection.ValueKind(rawValue: kindText)
            else { return }
            let keyRange =
                row.isNull(at: 6)
                ? nil
                : SearchSourceRange(
                    utf16LowerBound: row.int(at: 6),
                    utf16UpperBound: row.int(at: 7),
                    line: row.int(at: 8),
                    column: row.int(at: 9),
                    endLine: row.int(at: 10),
                    endColumn: row.int(at: 11)
                )
            let storageKey = key
            var accumulator =
                values[storageKey]
                ?? Accumulator(
                    key: key,
                    keyRange: keyRange,
                    valueKind: kind,
                    isEmpty: row.int(at: 2) == 1,
                    members: []
                )
            if let rawValue = row.text(at: 4),
                let normalizedValue = row.text(at: 5)
            {
                accumulator.members.append(
                    SearchPropertyProjection.StringMember(
                        value: rawValue,
                        normalizedValue: normalizedValue,
                        sourceRange: row.isNull(at: 12)
                            ? nil
                            : SearchSourceRange(
                                utf16LowerBound: row.int(at: 12),
                                utf16UpperBound: row.int(at: 13),
                                line: row.int(at: 14),
                                column: row.int(at: 15),
                                endLine: row.int(at: 16),
                                endColumn: row.int(at: 17)
                            )
                    ))
            }
            values[storageKey] = accumulator
        }
        return values.values.map {
            SearchPropertyProjection.Entry(
                key: $0.key,
                keySourceRange: $0.keyRange,
                valueKind: $0.valueKind,
                isEmpty: $0.isEmpty,
                stringMembers: $0.members
            )
        }.sorted {
            if $0.key != $1.key { return $0.key < $1.key }
            return $0.keySourceRange != nil && $1.keySourceRange == nil
        }
    }

    private struct IndexedMetadata {
        let rowID: Int
        let fingerprint: DocumentFingerprint
        let hasBrokenLink: Bool
        let stableNoteID: String?
    }

    private func indexedDocumentMetadata(_ id: VaultQualifiedNoteID) throws -> IndexedMetadata? {
        var result: IndexedMetadata?
        try database.query(
            """
            SELECT id, fingerprint_sha256, fingerprint_byte_count, has_broken_link,
                   stable_note_id
            FROM search_documents WHERE vault_id = ? AND relative_path = ?;
            """,
            bindings: [.text(id.vaultID.uuidString.lowercased()), .text(id.relativePath)]
        ) { row in
            guard let sha = row.text(at: 1) else { return }
            result = IndexedMetadata(
                rowID: row.int(at: 0),
                fingerprint: DocumentFingerprint(sha256: sha, byteCount: row.int(at: 2)),
                hasBrokenLink: row.int(at: 3) == 1,
                stableNoteID: row.text(at: 4)
            )
        }
        return result
    }

    private func vaultDescriptor(_ id: UUID) throws -> (name: String, role: VaultRole)? {
        if let configured = configuredVaults[id] {
            return (configured.name, configured.role)
        }
        var result: (String, VaultRole)?
        try database.query(
            "SELECT vault_name, role FROM search_vaults WHERE vault_id = ?;",
            bindings: [.text(id.uuidString.lowercased())]
        ) { row in
            if let name = row.text(at: 0), let roleText = row.text(at: 1),
                let role = VaultRole(rawValue: roleText)
            {
                result = (name, role)
            }
        }
        return result
    }

    private struct IndexedProjectionState: Equatable, Sendable {
        let fingerprint: DocumentFingerprint
        let vaultNameUTF8: Data
        let vaultRole: VaultRole
        let stableNoteIDUTF8: Data?
        let evidentialLayer: EvidentialLayer
        let hasBrokenLink: Bool

        init(_ source: SearchIndexManifestEntry) {
            self.init(
                fingerprint: source.fingerprint,
                vaultNameUTF8: Data(source.vaultName.utf8), vaultRole: source.vaultRole,
                stableNoteIDUTF8: source.stableNoteID.map { Data($0.utf8) },
                evidentialLayer: source.evidentialLayer, hasBrokenLink: source.hasBrokenLink)
        }

        init(
            fingerprint: DocumentFingerprint, vaultNameUTF8: Data, vaultRole: VaultRole,
            stableNoteIDUTF8: Data?, evidentialLayer: EvidentialLayer, hasBrokenLink: Bool
        ) {
            self.fingerprint = fingerprint
            self.vaultNameUTF8 = vaultNameUTF8
            self.vaultRole = vaultRole
            self.stableNoteIDUTF8 = stableNoteIDUTF8
            self.evidentialLayer = evidentialLayer
            self.hasBrokenLink = hasBrokenLink
        }
    }

    nonisolated static func encodedParagraphs(_ paragraphs: [SearchParagraphProjection]) throws
        -> Data
    {
        try JSONEncoder.searchIndex.encode(paragraphs.map(StoredParagraph.init))
    }

    nonisolated static func decodedStoredParagraphs(from json: String?) throws
        -> [SearchParagraphProjection]
    {
        try decodeGeneratedJSON([StoredParagraph].self, from: json).map { try $0.projection() }
    }

    private nonisolated static func indexedProjectionState(
        in database: SearchSQLiteDatabase
    ) throws -> [Data: IndexedProjectionState] {
        var result: [Data: IndexedProjectionState] = [:]
        try database.query(
            """
            SELECT vault_id, relative_path, fingerprint_sha256, fingerprint_byte_count,
                   has_broken_link, vault_name, role, stable_note_id, evidential_layer
            FROM search_documents ORDER BY vault_id, relative_path;
            """
        ) { row in
            guard let vault = row.text(at: 0), let path = row.text(at: 1),
                let sha = row.text(at: 2),
                let vaultName = row.text(at: 5), let roleText = row.text(at: 6),
                let vaultRole = VaultRole(rawValue: roleText),
                let layerText = row.text(at: 8),
                let evidentialLayer = EvidentialLayer(rawValue: layerText)
            else { return }
            result[Data("\(vault)/\(path)".utf8)] = IndexedProjectionState(
                fingerprint: DocumentFingerprint(sha256: sha, byteCount: row.int(at: 3)),
                vaultNameUTF8: Data(vaultName.utf8), vaultRole: vaultRole,
                stableNoteIDUTF8: row.text(at: 7).map { Data($0.utf8) },
                evidentialLayer: evidentialLayer, hasBrokenLink: row.int(at: 4) == 1)

        }
        return result
    }

    private static func validatedDocuments(
        _ documents: [SearchIndexManifestEntry]
    ) throws -> [Data: SearchIndexManifestEntry] {
        var result: [Data: SearchIndexManifestEntry] = [:]
        var canonicalKeys = Set<String>()
        for document in documents {
            let key = documentKey(vaultID: document.vaultID, path: document.relativePath)
            // Keep the established Note identity domain: two simultaneous
            // canonically equivalent paths are ambiguous, even when their bytes
            // differ. Data keys below still detect a single exact-path rename.
            guard canonicalKeys.insert(key).inserted else {
                throw SearchIndexError.invalidDocuments(
                    "duplicate Search document \(document.vaultID)/\(document.relativePath)"
                )
            }
            result[Data(key.utf8)] = document
        }
        return result
    }

    private static func manifestHash(for documents: [SearchIndexManifestEntry]) -> String {
        SearchSourceManifest.hash(
            documents.map {
                SearchSourceManifestEntry(
                    vaultID: $0.vaultID,
                    relativePath: $0.relativePath,
                    fingerprint: $0.fingerprint
                )
            })
    }

    private static func insert(
        _ prepared: PreparedSearchIndexDocument,
        into database: SearchSQLiteDatabase
    ) throws {
        let item = prepared.source
        let projection = prepared.projection
        // Prepared in the same publication transaction as the exact source
        // fingerprint. Queries never trigger first-use paragraph parsing for
        // an indexed revision, including after application restart.
        let relatedProjection = try RelatedContentSourceProjection(document: item.document).encoded()
        let relatedLexical = try RelatedContentLexicalProjection(projection: projection).encoded()
        let lineStarts =
            String(
                data: try JSONEncoder.searchIndex.encode(projection.sourceLineStartsUTF16),
                encoding: .utf8
            ) ?? "[0]"
        try database.execute(
            """
            INSERT INTO search_documents(
                document_key, vault_id, vault_name, role, role_order, relative_path,
                stable_note_id, title, normalized_title, title_key, filename_key, path_key,
                fingerprint_sha256, fingerprint_byte_count, evidential_layer,
                callout_roles, has_broken_link, line_starts,
                source_utf16_count, property_issues, paragraphs, paragraphs_complete,
                related_projection, related_projection_hash, related_lexical, related_lexical_hash
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(documentKey(vaultID: item.vaultID, path: item.relativePath)),
                .text(item.vaultID.uuidString.lowercased()), .text(item.vaultName),
                .text(item.vaultRole.rawValue), .int(roleOrder(item.vaultRole)),
                .text(item.relativePath), .optionalText(item.stableNoteID), .text(projection.title),
                .text(SearchTextNormalization.normalize(projection.title)),
                .text(SearchTextNormalization.normalize(projection.title)),
                .text(
                    SearchTextNormalization.normalize(
                        ((item.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
                    )),
                .text(SearchTextNormalization.normalize(item.relativePath)),
                .text(item.document.fingerprint.sha256), .int(item.document.fingerprint.byteCount),
                .text(item.evidentialLayer.rawValue),
                .text(" " + projection.calloutRoles.sorted().joined(separator: " ") + " "),
                .int(projection.hasBrokenLink ? 1 : 0),
                .text(lineStarts),
                .int(item.document.rawContent.utf16.count),
                .text(String(decoding: try JSONEncoder.searchIndex.encode(prepared.properties.issues), as: UTF8.self)),
                .text(String(decoding: try encodedParagraphs(projection.paragraphs), as: UTF8.self)),
                .int(item.document.hasProvableBodyBoundary ? 1 : 0),
                .blob(relatedProjection),
                .text(RelatedContentSourceProjection.checksum(relatedProjection)),
                .blob(relatedLexical), .text(RelatedContentSourceProjection.checksum(relatedLexical)),
            ]
        )
        let documentID = database.lastInsertRowID
        for (ordinal, alias) in projection.aliases.enumerated() {
            try database.execute(
                "INSERT INTO search_aliases(document_id, ordinal, alias, exact_key) VALUES(?, ?, ?, ?);",
                bindings: [
                    .int(documentID), .int(ordinal), .text(alias),
                    .text(SearchTextNormalization.normalize(alias)),
                ]
            )
        }
        for segment in projection.segments {
            guard
                SearchProjectionValidation.valid(
                    offsets: segment.offsetMap,
                    normalizedUTF16Count: segment.normalizedText.utf16.count,
                    sourceUTF16Bounds: segment.sourceRange.map {
                        (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound)
                    },
                    sourceUTF16Count: item.document.rawContent.utf16.count
                )
            else {
                throw SearchIndexError.invalidDocuments(
                    "Search projection contains an invalid generated offset map."
                )
            }
            let offsets = try SearchOffsetMapCodec.encode(segment.offsetMap)
            try database.execute(
                """
                INSERT INTO search_segments(
                    document_id, field, ordinal, text, normalized_text,
                    source_lower, source_upper, source_line, source_column,
                    source_end_line, source_end_column, offset_map, related_ranking_text
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    .int(documentID), .text(segment.field.rawValue), .int(segment.ordinal),
                    .text(segment.text), .text(segment.normalizedText),
                    .optionalInt(segment.sourceRange?.utf16LowerBound),
                    .optionalInt(segment.sourceRange?.utf16UpperBound),
                    .optionalInt(segment.sourceRange?.line),
                    .optionalInt(segment.sourceRange?.column),
                    .optionalInt(segment.sourceRange?.endLine),
                    .optionalInt(segment.sourceRange?.endColumn),
                    .blob(offsets),
                    .text(String(decoding: try JSONEncoder().encode(segment.relatedRankingText), as: UTF8.self)),
                ]
            )
        }
        for property in prepared.properties.entries {
            let members: [SearchPropertyProjection.StringMember?] =
                property.stringMembers.isEmpty
                ? [nil]
                : property.stringMembers.map(Optional.some)
            for (ordinal, member) in members.enumerated() {
                try database.execute(
                    """
                    INSERT INTO search_properties(
                        document_id, property_key, value_kind, is_empty, ordinal,
                        raw_value, normalized_value, key_lower, key_upper,
                        key_line, key_column, key_end_line, key_end_column,
                        value_lower, value_upper, value_line, value_column,
                        value_end_line, value_end_column
                    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """,
                    bindings: [
                        .int(documentID), .text(property.key),
                        .text(property.valueKind.rawValue), .int(property.isEmpty ? 1 : 0),
                        .int(ordinal),
                        .optionalText(member?.value),
                        .optionalText(member?.normalizedValue),
                        .optionalInt(property.keySourceRange?.utf16LowerBound),
                        .optionalInt(property.keySourceRange?.utf16UpperBound),
                        .optionalInt(property.keySourceRange?.line),
                        .optionalInt(property.keySourceRange?.column),
                        .optionalInt(property.keySourceRange?.endLine),
                        .optionalInt(property.keySourceRange?.endColumn),
                        .optionalInt(member?.sourceRange?.utf16LowerBound),
                        .optionalInt(member?.sourceRange?.utf16UpperBound),
                        .optionalInt(member?.sourceRange?.line),
                        .optionalInt(member?.sourceRange?.column),
                        .optionalInt(member?.sourceRange?.endLine),
                        .optionalInt(member?.sourceRange?.endColumn),
                    ]
                )
            }
        }
        try database.execute(
            """
            INSERT INTO search_fts(
                document_id, path, title, aliases, headings, summary, authors, publication_date, tags,
                callouts, footnotes, link_annotations, body
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .int(documentID), .text(SearchTokenization.indexText(projection.path)),
                .text(
                    SearchTokenization.indexText(
                        projection.segments
                            .filter { $0.field == .title }
                            .map(\.text)
                            .joined(separator: " ")
                    )),
                .text(SearchTokenization.indexText(projection.aliases.joined(separator: " "))),
                .text(SearchTokenization.indexText(projection.headings.joined(separator: " "))),
                .text(SearchTokenization.indexText(projection.summary ?? "")),
                .text(SearchTokenization.indexText(projection.authors.joined(separator: " "))),
                .text(SearchTokenization.indexText(projection.publicationDate ?? "")),
                .text(SearchTokenization.indexText(projection.tags.joined(separator: " "))),
                .text(SearchTokenization.indexText(projection.callouts)),
                .text(SearchTokenization.indexText(projection.footnotes)),
                .text(SearchTokenization.indexText(projection.linkAnnotations)),
                .text(SearchTokenization.indexText(projection.body)),
            ]
        )
    }

    private static func deleteDocument(
        key: String,
        from database: SearchSQLiteDatabase
    ) throws {
        var rowID: Int?
        try database.query(
            "SELECT id FROM search_documents WHERE document_key = ?;",
            bindings: [.text(key)]
        ) { rowID = $0.int(at: 0) }
        guard let rowID else { return }
        try database.execute("DELETE FROM search_fts WHERE document_id = ?;", bindings: [.int(rowID)])
        try database.execute("DELETE FROM search_segments WHERE document_id = ?;", bindings: [.int(rowID)])
        try database.execute("DELETE FROM search_aliases WHERE document_id = ?;", bindings: [.int(rowID)])
        try database.execute("DELETE FROM search_properties WHERE document_id = ?;", bindings: [.int(rowID)])
        try database.execute("DELETE FROM search_documents WHERE id = ?;", bindings: [.int(rowID)])
    }

    private static func createSchema(
        in database: SearchSQLiteDatabase,
        triptychID: UUID
    ) throws {
        try database.execute(
            """
            CREATE TABLE search_index_state(
                singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                triptych_id TEXT NOT NULL,
                sequence INTEGER NOT NULL,
                workspace_generation INTEGER NOT NULL,
                schema_version INTEGER NOT NULL,
                query_contract_version INTEGER NOT NULL,
                tokenizer_policy_version INTEGER NOT NULL,
                ranking_policy_version INTEGER NOT NULL,
                source_manifest_hash TEXT NOT NULL
            );
            INSERT INTO search_index_state VALUES(
                1, '\(triptychID.uuidString.lowercased())', 0, 0,
                \(SearchContract.schemaVersion), \(SearchContract.currentVersion),
                \(SearchContract.tokenizerPolicyVersion), \(SearchContract.rankingPolicyVersion), ''
            );
            CREATE TABLE search_vaults(
                vault_id TEXT PRIMARY KEY,
                vault_name TEXT NOT NULL,
                role TEXT NOT NULL
            );
            CREATE TABLE search_documents(
                id INTEGER PRIMARY KEY,
                document_key TEXT NOT NULL UNIQUE,
                vault_id TEXT NOT NULL,
                vault_name TEXT NOT NULL,
                role TEXT NOT NULL,
                role_order INTEGER NOT NULL,
                relative_path TEXT NOT NULL,
                stable_note_id TEXT,
                title TEXT NOT NULL,
                normalized_title TEXT NOT NULL,
                title_key TEXT NOT NULL,
                filename_key TEXT NOT NULL,
                path_key TEXT NOT NULL,
                fingerprint_sha256 TEXT NOT NULL,
                fingerprint_byte_count INTEGER NOT NULL,
                evidential_layer TEXT NOT NULL,
                callout_roles TEXT NOT NULL,
                has_broken_link INTEGER NOT NULL,
                line_starts TEXT NOT NULL,
                source_utf16_count INTEGER NOT NULL,
                property_issues TEXT NOT NULL,
                paragraphs TEXT NOT NULL,
                paragraphs_complete INTEGER NOT NULL,
                related_projection BLOB NOT NULL,
                related_projection_hash TEXT NOT NULL,
                related_lexical BLOB NOT NULL,
                related_lexical_hash TEXT NOT NULL
            );
            CREATE INDEX search_documents_vault ON search_documents(vault_id);
            CREATE INDEX search_documents_title_key ON search_documents(title_key);
            CREATE INDEX search_documents_filename_key ON search_documents(filename_key);
            CREATE INDEX search_documents_path_key ON search_documents(path_key);
            CREATE TABLE search_aliases(
                document_id INTEGER NOT NULL,
                ordinal INTEGER NOT NULL,
                alias TEXT NOT NULL,
                exact_key TEXT NOT NULL,
                PRIMARY KEY(document_id, ordinal),
                FOREIGN KEY(document_id) REFERENCES search_documents(id) ON DELETE CASCADE
            );
            CREATE INDEX search_aliases_exact_key ON search_aliases(exact_key);
            CREATE TABLE search_properties(
                document_id INTEGER NOT NULL,
                property_key TEXT NOT NULL,
                value_kind TEXT NOT NULL,
                is_empty INTEGER NOT NULL,
                ordinal INTEGER NOT NULL,
                raw_value TEXT,
                normalized_value TEXT,
                key_lower INTEGER,
                key_upper INTEGER,
                key_line INTEGER,
                key_column INTEGER,
                key_end_line INTEGER,
                key_end_column INTEGER,
                value_lower INTEGER,
                value_upper INTEGER,
                value_line INTEGER,
                value_column INTEGER,
                value_end_line INTEGER,
                value_end_column INTEGER,
                PRIMARY KEY(document_id, property_key, ordinal),
                FOREIGN KEY(document_id) REFERENCES search_documents(id) ON DELETE CASCADE
            );
            CREATE INDEX search_properties_key_value
                ON search_properties(property_key, normalized_value);
            CREATE TABLE search_segments(
                document_id INTEGER NOT NULL,
                field TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                text TEXT NOT NULL,
                normalized_text TEXT NOT NULL,
                source_lower INTEGER,
                source_upper INTEGER,
                source_line INTEGER,
                source_column INTEGER,
                source_end_line INTEGER,
                source_end_column INTEGER,
                offset_map BLOB NOT NULL,
                related_ranking_text TEXT NOT NULL,
                PRIMARY KEY(document_id, ordinal),
                FOREIGN KEY(document_id) REFERENCES search_documents(id) ON DELETE CASCADE
            );
            CREATE VIRTUAL TABLE search_fts USING fts5(
                document_id UNINDEXED, path, title, aliases, headings, summary, authors, publication_date,
                tags, callouts, footnotes, link_annotations, body,
                tokenize = '\(SearchSQLiteTokenizer.configuration)', prefix = '2 3'
            );
            """)
    }

    private static func validateSchema(
        in database: SearchSQLiteDatabase,
        triptychID: UUID
    ) throws {
        guard try database.scalarText("PRAGMA quick_check;") == "ok" else {
            throw SearchIndexError.corruptDatabase
        }
        var values: (String, Int, Int, Int, Int)?
        do {
            try database.query(
                """
                SELECT triptych_id, schema_version, query_contract_version,
                       tokenizer_policy_version, ranking_policy_version
                FROM search_index_state WHERE singleton = 1;
                """
            ) { row in
                if let id = row.text(at: 0) {
                    values = (id, row.int(at: 1), row.int(at: 2), row.int(at: 3), row.int(at: 4))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SearchIndexError.incompatibleSchema
        }
        guard let values,
            values.0 == triptychID.uuidString.lowercased(),
            values.1 == SearchContract.schemaVersion,
            values.2 == SearchContract.currentVersion,
            values.3 == SearchContract.tokenizerPolicyVersion,
            values.4 == SearchContract.rankingPolicyVersion
        else {
            throw SearchIndexError.incompatibleSchema
        }
        let definition = try database.scalarText(
            "SELECT sql FROM sqlite_master WHERE name = 'search_fts';"
        )?.uppercased()
        guard definition?.contains("USING FTS5") == true,
            definition?.contains("CONTENT=") == false
        else {
            throw SearchIndexError.incompatibleSchema
        }
        do {
            try validateGeneratedJSON(in: database)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SearchIndexError {
            switch error {
            case .corruptDatabase:
                throw error
            case .incompatibleSchema, .invalidDocuments, .sqlite:
                throw SearchIndexError.incompatibleSchema
            }
        } catch {
            throw SearchIndexError.incompatibleSchema
        }
    }

    private static func decodeParagraphs(_ json: String?, sourceUTF16Count: Int) throws -> [SearchParagraphProjection] {
        let paragraphs = try decodedStoredParagraphs(from: json)
        for paragraph in paragraphs {
            let range = paragraph.range
            guard SearchProjectionValidation.valid(paragraphRange: range, sourceUTF16Count: sourceUTF16Count)
            else { throw SearchIndexError.corruptDatabase }
            for segment in paragraph.segments {
                guard
                    SearchProjectionValidation.valid(
                        offsets: segment.offsetMap, normalizedUTF16Count: segment.normalizedText.utf16.count,
                        sourceUTF16Bounds: segment.sourceRange.map { (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound) },
                        sourceUTF16Count: sourceUTF16Count)
                else { throw SearchIndexError.corruptDatabase }
            }
        }
        return paragraphs
    }

    private static func validateGeneratedJSON(
        in database: SearchSQLiteDatabase
    ) throws {
        try Task.checkCancellation()
        try database.query(
            "SELECT line_starts, source_utf16_count, paragraphs, paragraphs_complete, related_projection, related_projection_hash, related_lexical, related_lexical_hash FROM search_documents;"
        ) { row in
            try Task.checkCancellation()
            let lineStarts = try decodeGeneratedJSON(
                [Int].self,
                from: row.text(at: 0)
            )
            let sourceUTF16Count = row.int(at: 1)
            _ = try RelatedContentSourceProjection.decode(
                row.data(at: 4), checksum: row.text(at: 5), sourceUTF16Count: sourceUTF16Count)
            _ = try RelatedContentLexicalProjection.decode(row.data(at: 6), checksum: row.text(at: 7))
            let paragraphs = try decodeGeneratedJSON([StoredParagraph].self, from: row.text(at: 2))
            for paragraph in paragraphs { try paragraph.validate(sourceUTF16Count: sourceUTF16Count) }
            guard [0, 1].contains(row.int(at: 3)) else { throw SearchIndexError.corruptDatabase }
            guard sourceUTF16Count >= 0,
                lineStarts.first == 0,
                lineStarts.last.map({ $0 <= sourceUTF16Count }) == true,
                zip(lineStarts, lineStarts.dropFirst()).allSatisfy({ previous, next in
                    previous < next
                })
            else {
                throw SearchIndexError.corruptDatabase
            }
        }
        try database.query(
            """
            SELECT s.normalized_text, s.source_lower, s.source_upper, s.offset_map,
                   d.source_utf16_count
            FROM search_segments s
            JOIN search_documents d ON d.id = s.document_id;
            """
        ) { row in
            try Task.checkCancellation()
            let normalized = row.text(at: 0) ?? ""
            let sourceBounds: (lower: Int, upper: Int)?
            if row.isNull(at: 1) {
                guard row.isNull(at: 2) else {
                    throw SearchIndexError.corruptDatabase
                }
                sourceBounds = nil
            } else {
                guard !row.isNull(at: 2) else {
                    throw SearchIndexError.corruptDatabase
                }
                sourceBounds = (lower: row.int(at: 1), upper: row.int(at: 2))
            }
            try SearchOffsetMapCodec.validate(
                row.data(at: 3), normalizedUTF16Count: normalized.utf16.count,
                sourceUTF16Bounds: sourceBounds, sourceUTF16Count: row.int(at: 4))
        }
    }

    private static func decodeGeneratedJSON<Value: Decodable>(
        _ type: Value.Type,
        from text: String?
    ) throws -> Value {
        guard let text, let data = text.data(using: .utf8) else {
            throw SearchIndexError.corruptDatabase
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SearchIndexError.corruptDatabase
        }
    }

    private static func readGeneration(
        in database: SearchSQLiteDatabase,
        triptychID: UUID
    ) throws -> SearchGenerationID? {
        var result: SearchGenerationID?
        try database.query(
            """
            SELECT sequence, schema_version, query_contract_version,
                   tokenizer_policy_version, ranking_policy_version, source_manifest_hash
            FROM search_index_state WHERE singleton = 1;
            """
        ) { row in
            let sequence = row.int(at: 0)
            guard sequence > 0 else { return }
            result = SearchGenerationID(
                triptychID: triptychID,
                sequence: sequence,
                schemaVersion: row.int(at: 1),
                queryContractVersion: row.int(at: 2),
                tokenizerPolicyVersion: row.int(at: 3),
                rankingPolicyVersion: row.int(at: 4),
                sourceManifestHash: row.text(at: 5) ?? ""
            )
        }
        return result
    }

    private static func readWorkspaceGeneration(
        in database: SearchSQLiteDatabase
    ) throws -> UInt64 {
        var result = 0
        try database.query(
            "SELECT workspace_generation FROM search_index_state WHERE singleton = 1;"
        ) { row in
            result = row.int(at: 0)
        }
        guard result >= 0 else { throw SearchIndexError.incompatibleSchema }
        return UInt64(result)
    }

    private static func requireNewerWorkspaceGeneration(
        _ requested: UInt64,
        in database: SearchSQLiteDatabase
    ) throws {
        let current = try readWorkspaceGeneration(in: database)
        guard requested > current else {
            throw SearchIndexError.invalidDocuments(
                "Refused stale workspace generation \(requested); persisted generation is \(current)."
            )
        }
    }

    private static func documentKey(vaultID: UUID, path: String) -> String {
        "\(vaultID.uuidString.lowercased())/\(path)"
    }

    private static func noteReference(
        documentKey: String
    ) throws -> VaultQualifiedNoteID {
        guard let separator = documentKey.firstIndex(of: "/"),
            let vaultID = UUID(uuidString: String(documentKey[..<separator]))
        else {
            throw SearchIndexError.invalidDocuments(
                "Stored Search document key is malformed."
            )
        }
        let path = String(documentKey[documentKey.index(after: separator)...])
        guard !path.isEmpty else {
            throw SearchIndexError.invalidDocuments(
                "Stored Search document path is empty."
            )
        }
        return VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
    }

    private static func roleOrder(_ role: VaultRole) -> Int {
        switch role {
        case .sourceCorpus: 0
        case .topicKnowledge: 1
        case .draftProject: 2
        case .other: 3
        }
    }

    private static func evidentialLayer(for role: VaultRole) -> EvidentialLayer {
        switch role {
        case .sourceCorpus: .paperAnalysis
        case .topicKnowledge, .other: .topicNote
        case .draftProject: .draftProse
        }
    }
}

extension TriptychSearchIndex {
    /// A complete candidate scan's cache protection, not source authority. It
    /// holds no source documents or projections and expires with its generation.
    public struct RelatedPassagePreparation: Sendable {
        fileprivate let generation: SearchGenerationID
        fileprivate let seedNoteID: VaultQualifiedNoteID
        fileprivate let roles: [RelatedContentCandidateRole]
        fileprivate let protection: RelatedContentSourceProjectionMemo.ScanProtection
    }

    public func beginRelatedPassagePreparation(
        _ request: RelatedContentRequest, candidates: [RelatedContentCandidate], generation: SearchGenerationID
    ) throws -> RelatedPassagePreparation {
        try Task.checkCancellation()
        return try database.readTransaction {
            guard currentAvailability == .current(generation),
                try Self.readGeneration(in: database, triptychID: triptychID) == generation
            else { throw CancellationError() }
            let protection = relatedPassageMemo.scanProtection(
                for: candidates.lazy.filter { candidate in
                    candidate.note != request.seed.noteID
                        && request.candidateRoles.contains { $0.vaultRole == candidate.vaultRole }
                })
            return .init(generation: generation, seedNoteID: request.seed.noteID, roles: request.candidateRoles, protection: protection)
        }
    }

    /// Warm one bounded batch without scoring or selecting results. Reuse the
    /// same protection across every batch so early misses cannot evict the
    /// resident tail of an over-budget scan. No transaction spans actor calls.
    public func prepareRelatedPassages(
        _ preparation: RelatedPassagePreparation, sources: [RelatedContentSource]
    ) throws {
        try Task.checkCancellation()
        try database.readTransaction {
            guard currentAvailability == .current(preparation.generation),
                try Self.readGeneration(in: database, triptychID: triptychID) == preparation.generation
            else { throw CancellationError() }
            var seen = Set<VaultQualifiedNoteID>()
            for source in sources {
                try Task.checkCancellation()
                guard source.candidate.note != preparation.seedNoteID,
                    preparation.roles.contains(where: { $0.vaultRole == source.candidate.vaultRole }),
                    source.document.fingerprint == source.candidate.fingerprint,
                    Data(source.document.relativePath.utf8) == Data(source.candidate.note.relativePath.utf8),
                    seen.insert(source.candidate.note).inserted
                else { continue }
                _ = try relatedSourceProjection(for: source, protection: preparation.protection)
            }
            try Task.checkCancellation()
        }
    }

    public func relatedPassages(
        _ request: RelatedContentRequest, sources: [RelatedContentSource]
    ) throws -> [RelatedContentPassage] {
        let protection = relatedPassageMemo.scanProtection(
            for: sources.filter { source in
                source.candidate.note != request.seed.noteID
                    && request.candidateRoles.contains { $0.vaultRole == source.candidate.vaultRole }
            })
        return try database.readTransaction {
            try Self.rankRelatedPassages(request, sources: sources) { source in
                try relatedSourceProjection(for: source, protection: protection)
            }
        }
    }

    private func relatedSourceProjection(
        for source: RelatedContentSource, protection: RelatedContentSourceProjectionMemo.ScanProtection
    ) throws -> RelatedContentSourceProjection? {
        // Capture the database, not self, while mutating actor-owned memo.
        let database = self.database
        return try relatedPassageMemo.projection(for: source, protection: protection) { document in
            var projection: RelatedContentSourceProjection?
            try database.query(
                """
                SELECT related_projection, related_projection_hash, source_utf16_count
                FROM search_documents WHERE document_key = ?
                    AND fingerprint_sha256 = ? AND fingerprint_byte_count = ?;
                """,
                bindings: [
                    .text(Self.documentKey(vaultID: source.candidate.note.vaultID, path: document.relativePath)),
                    .text(document.fingerprint.sha256), .int(document.fingerprint.byteCount),
                ]
            ) { row in
                projection = try RelatedContentSourceProjection.decode(
                    row.data(at: 0), checksum: row.text(at: 1), sourceUTF16Count: row.int(at: 2))
            }
            // A source read may straddle an index publication. Its exact
            // verified bytes still permit preparation; never reuse a
            // projection from a different indexed revision.
            return try projection ?? RelatedContentSourceProjection(document: document)
        }
    }
}

private extension SearchIndexError {
    var permitsSearchRecovery: Bool {
        switch self {
        case .corruptDatabase, .incompatibleSchema: true
        default: false
        }
    }
}

private extension JSONEncoder {
    static var searchIndex: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
