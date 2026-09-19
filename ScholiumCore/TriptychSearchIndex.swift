import CryptoKit
import Darwin
import Foundation
import SQLite3
import ScholiumContracts
import os

struct SearchSynchronizationTimings: Sendable {
    let documentCount: Int
    let changedCount: Int
    let hashMissCount: Int
    let preparationMilliseconds: Double
    let publicationMilliseconds: Double
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
    let upserts: [SearchIndexDocument]
    /// Prepared comparison hashes reused by the writer; source generations and
    /// exact document fingerprints remain publication authority.
    let indexedProjectionHashes: [String: String]
    let deletions: [VaultQualifiedNoteID]
}

public actor TriptychSearchIndex {
    private static let logger = Logger(subsystem: "com.scholium.app", category: "SearchIndex")
    private(set) var lastSynchronizationTimings: SearchSynchronizationTimings?
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
    private var latestWorkspaceGeneration: UInt64 = 0
    // Pure derived hashes, keyed by every immutable input to the existing hash.
    // Replaced with each desired inventory; never used as publication authority.
    private var projectionHashes: [String: (input: ProjectionHashInput, hash: String)] = [:]
    private var relatedPassageMemo = RelatedContentSourceProjectionMemo()

    private struct ProjectionHashInput: Equatable {
        // Swift String equality is canonical-equivalence, while JSON hashing is
        // byte-sensitive. Bind the memo to exact source bytes as well.
        let fingerprint: DocumentFingerprint
        let sourceHash: String
        let properties: SearchPropertyProjection
        let paragraphs: [SearchParagraphProjection]
    }

    private struct ActiveSynchronization {
        let id: UUID
        let previous: SearchGenerationID?
        let task: Task<TriptychSearchIndexSyncResult, Error>
        let progress: ProgressDelivery?
    }

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

    /// Standalone index test support. Workspace production must provide the
    /// coordinator-owned generation explicitly.
    func synchronize(
        _ documents: [SearchIndexDocument]
    ) async throws -> TriptychSearchIndexSyncResult {
        let latest = try workspaceGeneration()
        guard latest < UInt64(Int.max) else {
            throw SearchIndexError.invalidDocuments(
                "Search workspace generation IDs were exhausted."
            )
        }
        let workspaceGeneration = latest + 1
        return try await synchronize(
            documents,
            workspaceGeneration: workspaceGeneration
        )
    }

    public func synchronize(
        _ documents: [SearchIndexDocument],
        workspaceGeneration: UInt64
    ) async throws -> TriptychSearchIndexSyncResult {
        try Task.checkCancellation()
        // Finish the one older writer before validating the new request. This
        // lets the recursive retry compare against the generation that writer
        // actually committed instead of the pre-wait watermark.
        if let active = activeSynchronization {
            do {
                _ = try await finishSynchronization(active)
            } catch is CancellationError {
                if Task.isCancelled { throw CancellationError() }
            } catch {
                // A later requested source generation is still allowed to
                // repair a failed earlier refresh.
            }
            try Task.checkCancellation()
            return try await synchronize(
                documents,
                workspaceGeneration: workspaceGeneration
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
        relatedPassageMemo.retain(Array(desired.values))
        let manifestHash = Self.manifestHash(for: Array(desired.values))
        let previous = try generation()
        let stored = try Self.indexedProjectionState(in: database)
        var desiredState: [String: IndexedProjectionState] = [:]
        var nextProjectionHashes: [String: (input: ProjectionHashInput, hash: String)] = [:]
        var hashMissCount = 0
        for (key, value) in desired {
            let fingerprint = value.document.fingerprint
            let input = ProjectionHashInput(
                fingerprint: fingerprint,
                sourceHash: value.projection.projectionHash,
                properties: value.propertyProjection, paragraphs: value.projection.paragraphs)
            let hash: String
            if let cached = projectionHashes[key], cached.input == input {
                hash = cached.hash
            } else {
                hashMissCount += 1
                hash = try Self.indexedProjectionHash(value)
            }
            nextProjectionHashes[key] = (input, hash)
            desiredState[key] = IndexedProjectionState(
                fingerprint: fingerprint,
                projectionHash: hash,
                vaultName: value.vaultName,
                vaultRole: value.vaultRole,
                stableNoteID: value.stableNoteID,
                evidentialLayer: value.evidentialLayer
            )
        }
        projectionHashes = nextProjectionHashes
        let changedKeys = desired.keys.filter { stored[$0] != desiredState[$0] }
        let removedKeys = Set(stored.keys).subtracting(desired.keys)
        let delta = SearchIndexDelta(
            workspaceGeneration: workspaceGeneration,
            upserts: changedKeys.compactMap { desired[$0] },
            indexedProjectionHashes: desiredState.mapValues(\.projectionHash),
            deletions: try removedKeys.map {
                try Self.noteReference(documentKey: $0)
            }
        )
        let preparationMilliseconds = Self.milliseconds(since: preparationStarted)
        let publicationStarted = ContinuousClock.now
        if previous?.sourceManifestHash == manifestHash, stored == desiredState,
            let previous
        {
            try writerDatabase.transaction {
                try Self.requireNewerWorkspaceGeneration(
                    workspaceGeneration,
                    in: writerDatabase
                )
                try writerDatabase.execute(
                    "UPDATE search_index_state SET workspace_generation = ? WHERE singleton = 1;",
                    bindings: [.int(Int(workspaceGeneration))]
                )
            }
            currentAvailability = .current(previous)
            recordSynchronizationTimings(
                documentCount: desired.count, changedCount: changedKeys.count,
                hashMissCount: hashMissCount, preparationMilliseconds: preparationMilliseconds,
                publicationStarted: publicationStarted)
            return TriptychSearchIndexSyncResult(
                generation: previous,
                disposition: .unchanged
            )
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
            try Self.publish(
                delta: delta,
                desired: desired,
                manifestHash: manifestHash,
                previous: previous,
                recoveredGeneratedDatabase: recovered,
                configuredVaults: configuredVaults,
                triptychID: triptychID,
                database: writer,
                progress: progressReporter
            )
        }
        let active = ActiveSynchronization(
            id: identifier,
            previous: previous,
            task: task,
            progress: progress
        )
        activeSynchronization = active
        let result = try await finishSynchronization(active)
        recordSynchronizationTimings(
            documentCount: desired.count, changedCount: changedKeys.count,
            hashMissCount: hashMissCount, preparationMilliseconds: preparationMilliseconds,
            publicationStarted: publicationStarted)
        return result
    }

    private nonisolated static func milliseconds(since started: ContinuousClock.Instant) -> Double {
        let parts = started.duration(to: .now).components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }

    private func recordSynchronizationTimings(
        documentCount: Int, changedCount: Int, hashMissCount: Int,
        preparationMilliseconds: Double, publicationStarted: ContinuousClock.Instant
    ) {
        let publicationMilliseconds = Self.milliseconds(since: publicationStarted)
        lastSynchronizationTimings = SearchSynchronizationTimings(
            documentCount: documentCount, changedCount: changedCount, hashMissCount: hashMissCount,
            preparationMilliseconds: preparationMilliseconds,
            publicationMilliseconds: publicationMilliseconds)
        Self.logger.info(
            "sync documents=\(documentCount, privacy: .public) changed=\(changedCount, privacy: .public) hash_misses=\(hashMissCount, privacy: .public) preparation_ms=\(preparationMilliseconds, privacy: .public) publication_ms=\(publicationMilliseconds, privacy: .public)"
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
        _ synchronization: ActiveSynchronization
    ) async throws -> TriptychSearchIndexSyncResult {
        do {
            let result = try await withTaskCancellationHandler {
                try await synchronization.task.value
            } onCancel: {
                synchronization.task.cancel()
            }
            await finishProgress(synchronization)
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                recoveredGeneratedDatabase = false
                currentAvailability = .current(result.generation)
            }
            return result
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
        desired: [String: SearchIndexDocument],
        manifestHash: String,
        previous: SearchGenerationID?,
        recoveredGeneratedDatabase: Bool,
        configuredVaults: [UUID: (String, VaultRole)],
        triptychID: UUID,
        database: SearchSQLiteDatabase,
        progress: (@Sendable (Int) -> Void)?
    ) throws -> TriptychSearchIndexSyncResult {
        try database.transaction {
            try Task.checkCancellation()
            try requireNewerWorkspaceGeneration(
                delta.workspaceGeneration,
                in: database
            )
            for deletion in delta.deletions.sorted(by: {
                if $0.vaultID != $1.vaultID {
                    return $0.vaultID.uuidString < $1.vaultID.uuidString
                }
                return $0.relativePath < $1.relativePath
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
                documentKey(vaultID: $0.vaultID, path: $0.relativePath)
                    < documentKey(vaultID: $1.vaultID, path: $1.relativePath)
            }
            for (offset, document) in orderedUpserts.enumerated() {
                try Task.checkCancellation()
                let key = documentKey(
                    vaultID: document.vaultID,
                    path: document.relativePath
                )
                guard let projectionHash = delta.indexedProjectionHashes[key] else {
                    throw SearchIndexError.invalidDocuments("Search delta is missing its prepared projection hash.")
                }
                try deleteDocument(key: key, from: database)
                try insert(document, projectionHash: projectionHash, into: database)
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
            try Task.checkCancellation()
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
        return TriptychSearchIndexSyncResult(
            generation: published,
            disposition: disposition
        )
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
                            code: .notApplicable,
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

    /// Enumerates every eligible lexical source from one complete generation.
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
            let material = RelatedContentSeedMaterial(
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

            let identity = try relatedIdentityCandidates(
                material: material,
                excluding: request.seed.noteID,
                candidateRoles: request.candidateRoles,
                limit: request.identityLimit
            )
            let focusedTerms = material.termGroups.filter { $0.kind != .sourceNote }.flatMap(\.terms)
            let scoringTerms = focusedTerms.isEmpty ? material.combinedTerms : focusedTerms
            let lexicalPool = try relatedContentCandidates(
                terms: scoringTerms,
                excluding: request.seed.noteID,
                candidateRoles: request.candidateRoles
            )
            let scores = try RelatedContentBM25F.scores(
                documents: lexicalPool.map { $0.document.relatedLexical!.scoringDocument }, terms: scoringTerms,
                roles: lexicalPool.map { $0.document.vaultRole })
            let lexical = zip(lexicalPool, scores).compactMap { candidate, score -> RelatedLexicalCandidate? in
                let reason = material.lexicalReason(for: candidate)
                guard score > 0, !reason.seedMatches.isEmpty else { return nil }
                return RelatedLexicalCandidate(
                    candidate: candidate,
                    reason: reason,
                    score: score
                )
            }.sorted(by: RelatedLexicalCandidate.precedes)
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
                !identity.candidates.isEmpty
                || !lexicalResults.isEmpty
            return RelatedContentResponse(
                requestID: request.id,
                seedFingerprint: request.seed.fingerprint,
                freshnessToken: freshness,
                availability: availability,
                state: hasCandidates ? .current : .empty,
                identityCandidates: identity.candidates,
                lexicalCandidates: Array(lexicalResults),
                identityHasMore: identity.hasMore,
                lexicalHasMore: lexicalHasMore
            )
        }
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
        let ranks = try lexicalRanks(for: ast)
        let normalizedNeedles = SearchMatcher.normalizedNeedles(for: ast.expression)
        let admission = Self.candidateAdmission(ast.expression)
        var sql = "SELECT d.id FROM search_documents d WHERE " + admission.sql
        var bindings = admission.bindings
        if let vaultID {
            sql += " AND d.vault_id = ?"
            bindings.append(.text(vaultID.uuidString.lowercased()))
        }
        if let included = request.includedVaultIDs {
            guard !included.isEmpty else {
                return SearchResponse(
                    requestID: request.id, scope: request.presentationScope, explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness, availability: availability, results: [], hasMore: false)
            }
            sql += " AND d.vault_id IN (" + Array(repeating: "?", count: included.count).joined(separator: ",") + ")"
            bindings.append(contentsOf: included.sorted { $0.uuidString < $1.uuidString }.map { .text($0.uuidString.lowercased()) })
        }
        var rowIDs: [Int] = []
        try database.query(sql, bindings: bindings) { rowIDs.append($0.int(at: 0)) }
        let includesParagraphs = ast.clauses.contains {
            if case .paragraph = $0 { true } else { false }
        }
        let includesLexicalSegments = ast.clauses.contains {
            if case .lexical = $0 { true } else { false }
        }
        let includesProperties = ast.hasPropertyClause
        var accepted: [(candidate: SearchCandidate, evaluation: SearchEvaluation)] = []
        var total = 0
        var indeterminate = 0
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
            if evaluation.truth == .unknown { indeterminate += 1 }
            guard evaluation.truth == .yes else { continue }
            total += 1
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
            if accepted.count == required, let last = accepted.last,
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
            if lower < required {
                accepted.insert((candidate, evaluation), at: lower)
                if accepted.count > required { accepted.removeLast() }
            }
        }
        // Counting and ranking need exact predicate values, but only this page needs
        // source offset maps and snippet material. Hydrate within the same read
        // transaction so the match, fingerprint and source locator cannot diverge.
        let hits = try accepted.dropFirst(min(request.resultOffset, accepted.count)).prefix(limit).map { item in
            try Task.checkCancellation()
            guard
                let document = try loadDocument(
                    rowID: item.candidate.document.rowID,
                    includingProperties: includesProperties,
                    includingParagraphs: includesParagraphs
                )
            else { throw SearchIndexError.corruptDatabase }
            let candidate = SearchCandidate(
                document: document, identityPriority: item.candidate.identityPriority,
                lexicalRank: item.candidate.lexicalRank)
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
        limit: Int
    ) throws -> (candidates: [RelatedContentCandidate], hasMore: Bool) {
        guard limit > 0 else { return ([], false) }
        let rolePlaceholders = candidateRoles.map { _ in "?" }
            .joined(separator: ", ")
        var matches: [RelatedIdentityCandidate] = []
        try database.query(
            """
            SELECT d.id
            FROM search_documents d
            WHERE d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY d.normalized_title, d.role_order, d.path_key,
                     d.relative_path;
            """,
            bindings: candidateRoles.map {
                .text($0.vaultRole.rawValue)
            } + [
                .text(seed.vaultID.uuidString.lowercased()),
                .text(seed.relativePath),
            ]
        ) { row in
            try Task.checkCancellation()
            guard
                let document = try self.loadDocument(
                    rowID: row.int(at: 0), includingSegments: false, includingSourceEvidence: false),
                let reason = material.identityMentionReason(for: document)
            else { return }
            matches.append(
                RelatedIdentityCandidate(
                    document: document,
                    reason: reason
                ))
        }
        matches.sort(by: RelatedIdentityCandidate.precedes)
        return (
            matches.prefix(limit).map { item in
                RelatedContentCandidate(
                    note: item.document.noteID,
                    vaultRole: item.document.vaultRole,
                    title: item.document.title,
                    fingerprint: item.document.fingerprint,
                    reason: .identityMention(item.reason)
                )
            },
            matches.count > limit
        )
    }

    private func relatedContentCandidates(
        terms: [String],
        excluding seed: VaultQualifiedNoteID,
        candidateRoles: [RelatedContentCandidateRole]
    ) throws -> [SearchCandidate] {
        let expression = terms.map { term in
            let escaped = term.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }.joined(separator: " OR ")
        let rolePlaceholders = candidateRoles.map { _ in "?" }
            .joined(separator: ", ")
        var result: [SearchCandidate] = []
        try database.query(
            """
            SELECT d.id
            FROM search_fts
            JOIN search_documents d ON d.id = search_fts.document_id
            WHERE search_fts MATCH ?
              AND d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY d.normalized_title, d.role_order, d.path_key, d.relative_path;
            """,
            bindings: [
                .text(expression)
            ]
                + candidateRoles.map {
                    .text($0.vaultRole.rawValue)
                } + [
                    .text(seed.vaultID.uuidString.lowercased()),
                    .text(seed.relativePath),
                ]
        ) { row in
            try Task.checkCancellation()
            guard
                let document = try self.loadDocument(
                    rowID: row.int(at: 0), includingAliases: false,
                    includingSourceEvidence: false, includingRelatedRankingText: true)
            else { return }
            result.append(
                SearchCandidate(
                    document: document,
                    identityPriority: 10,
                    lexicalRank: 0
                ))
        }
        return result
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
        SearchLexicalClause(field: clause.field, value: clause.value, sourceRange: 0..<0)
    }

    private func lexicalRanks(for ast: SearchQueryAST) throws -> [SearchLexicalClause: [Int: Double]] {
        var ranks: [SearchLexicalClause: [Int: Double]] = [:]
        for clause in ast.rankingLexicalClauses {
            try Task.checkCancellation()
            let key = Self.rankingKey(clause)
            guard ranks[key] == nil else { continue }
            var values: [Int: Double] = [:]
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
                bindings: [.text(SearchMatcher.ftsExpression(for: [clause]))]
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
    private static func candidateAdmission(_ expression: SearchExpression, negated: Bool = false) -> (sql: String, bindings: [SearchSQLiteBinding]) {
        switch expression {
        case .clause(let clause):
            if !negated, case .paragraph(let query) = clause {
                let inner = candidateAdmission(query.expression)
                return ("(d.paragraphs_complete = 0 OR " + inner.sql + ")", inner.bindings)
            }
            if !negated, case .lexical(let value) = clause {
                return ("d.id IN (SELECT document_id FROM search_fts WHERE search_fts MATCH ?)", [.text(SearchMatcher.ftsExpression(for: [value]))])
            }
            return ("1 = 1", [])
        case .not(let child): return candidateAdmission(child, negated: !negated)
        case .and(let children), .or(let children):
            let conjunction: Bool
            if case .and = expression { conjunction = !negated } else { conjunction = negated }
            guard !children.isEmpty else { return (conjunction ? "1 = 1" : "0 = 1", []) }
            let pieces = children.map { candidateAdmission($0, negated: negated) }
            return ("(" + pieces.map(\.sql).joined(separator: conjunction ? " AND " : " OR ") + ")", pieces.flatMap(\.bindings))
        }
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
            SELECT vault_id, vault_name, role, relative_path, stable_note_id, title,
                   normalized_title, title_key, filename_key, path_key, callout_roles,
                   has_broken_link, fingerprint_sha256, fingerprint_byte_count,
                   evidential_layer, role_order, \(includingSourceEvidence ? "line_starts" : "NULL"), source_utf16_count,
                   \(includingProperties ? "property_issues" : "NULL"), \(includingParagraphs ? "paragraphs" : "NULL"), paragraphs_complete,
                   \(includingRelatedRankingText ? "related_lexical" : "NULL"), \(includingRelatedRankingText ? "related_lexical_hash" : "NULL")
            FROM search_documents WHERE id = ?;
            """,
            bindings: [.int(rowID)]
        ) { row in
            guard let vaultText = row.text(at: 0), let vaultID = UUID(uuidString: vaultText),
                let vaultName = row.text(at: 1), let roleText = row.text(at: 2),
                let role = VaultRole(rawValue: roleText), let path = row.text(at: 3),
                let title = row.text(at: 5), let normalizedTitle = row.text(at: 6),
                row.text(at: 7) != nil, let filenameKey = row.text(at: 8),
                let pathKey = row.text(at: 9), let sha = row.text(at: 12),
                let layerText = row.text(at: 14),
                let layer = EvidentialLayer(rawValue: layerText)
            else { return }
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
            let aliases = includingAliases ? try self.aliases(documentID: rowID) : []
            let segments: [SearchTextSegment]
            if includingSegments && !includingRelatedRankingText {
                segments = try self.segments(
                    documentID: rowID, sourceUTF16Count: sourceUTF16Count,
                    includingSourceEvidence: includingSourceEvidence,
                    includingRelatedRankingText: includingRelatedRankingText)
            } else {
                segments = []
            }
            let properties =
                includingProperties
                ? try self.properties(documentID: rowID)
                : []
            document = StoredSearchDocument(
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
                fingerprint: DocumentFingerprint(
                    sha256: sha,
                    byteCount: row.int(at: 13)
                ),
                evidentialLayer: layer,
                roleOrder: row.int(at: 15),
                sourceLineStarts: lineStarts,
                segments: segments,
                paragraphs: includingParagraphs ? try Self.decodeParagraphs(row.text(at: 19), sourceUTF16Count: sourceUTF16Count) : [],
                paragraphsAreComplete: row.int(at: 20) == 1,
                properties: properties,
                propertyIssues: includingProperties ? try Self.decodeGeneratedJSON([SearchPropertyProjection.Issue].self, from: row.text(at: 18)) : [],
                relatedLexical: includingRelatedRankingText ? try RelatedContentLexicalProjection.decode(row.data(at: 21), checksum: row.text(at: 22)) : nil
            )
        }
        return document
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
        let projectionHash: String
        let vaultName: String
        let vaultRole: VaultRole
        let stableNoteID: String?
        let evidentialLayer: EvidentialLayer
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

    /// Binds source-derived text, authored-property entries and issues, and
    /// complete paragraph projections to each indexed Note comparison.
    private nonisolated static func indexedProjectionHash(
        _ document: SearchIndexDocument
    ) throws -> String {
        let propertyData = try JSONEncoder.searchIndex.encode(
            document.propertyProjection.entries
        )
        var material = Data(document.projection.projectionHash.utf8)
        material.append(0)
        material.append(propertyData)
        material.append(try JSONEncoder.searchIndex.encode(document.propertyProjection.issues))
        material.append(try encodedParagraphs(document.projection.paragraphs))
        return SHA256.hash(data: material)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private nonisolated static func indexedProjectionState(
        in database: SearchSQLiteDatabase
    ) throws -> [String: IndexedProjectionState] {
        var result: [String: IndexedProjectionState] = [:]
        try database.query(
            """
            SELECT vault_id, relative_path, fingerprint_sha256, fingerprint_byte_count,
                   projection_hash, vault_name, role, stable_note_id, evidential_layer
            FROM search_documents ORDER BY vault_id, relative_path;
            """
        ) { row in
            guard let vault = row.text(at: 0), let path = row.text(at: 1),
                let sha = row.text(at: 2), let hash = row.text(at: 4),
                let vaultName = row.text(at: 5), let roleText = row.text(at: 6),
                let vaultRole = VaultRole(rawValue: roleText),
                let layerText = row.text(at: 8),
                let evidentialLayer = EvidentialLayer(rawValue: layerText)
            else { return }
            result["\(vault)/\(path)"] = IndexedProjectionState(
                fingerprint: DocumentFingerprint(sha256: sha, byteCount: row.int(at: 3)),
                projectionHash: hash,
                vaultName: vaultName,
                vaultRole: vaultRole,
                stableNoteID: row.text(at: 7),
                evidentialLayer: evidentialLayer
            )
        }
        return result
    }

    private static func validatedDocuments(
        _ documents: [SearchIndexDocument]
    ) throws -> [String: SearchIndexDocument] {
        var result: [String: SearchIndexDocument] = [:]
        for document in documents {
            let key = documentKey(vaultID: document.vaultID, path: document.relativePath)
            guard result.updateValue(document, forKey: key) == nil else {
                throw SearchIndexError.invalidDocuments(
                    "duplicate Search document \(document.vaultID)/\(document.relativePath)"
                )
            }
        }
        return result
    }

    private static func manifestHash(for documents: [SearchIndexDocument]) -> String {
        SearchSourceManifest.hash(
            documents.map {
                SearchSourceManifestEntry(
                    vaultID: $0.vaultID,
                    relativePath: $0.relativePath,
                    fingerprint: $0.document.fingerprint
                )
            })
    }

    private static func insert(
        _ item: SearchIndexDocument,
        projectionHash: String,
        into database: SearchSQLiteDatabase
    ) throws {
        let projection = item.projection
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
                callout_roles, has_broken_link, projection_hash, line_starts,
                source_utf16_count, property_issues, paragraphs, paragraphs_complete,
                related_projection, related_projection_hash, related_lexical, related_lexical_hash
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                .text(projectionHash),
                .text(lineStarts),
                .int(item.document.rawContent.utf16.count),
                .text(String(decoding: try JSONEncoder.searchIndex.encode(item.propertyProjection.issues), as: UTF8.self)),
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
        for property in item.propertyProjection.entries {
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
                projection_hash TEXT NOT NULL,
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
                tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3'
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
