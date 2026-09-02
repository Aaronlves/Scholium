import CryptoKit
import Darwin
import Foundation
import ScholiumContracts
import SQLite3

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
    let deletions: [VaultQualifiedNoteID]
}

public actor TriptychSearchIndex {
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

    private struct ActiveSynchronization {
        let id: UUID
        let previous: SearchGenerationID?
        let task: Task<TriptychSearchIndexSyncResult, Error>
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
           generation.sequence > 0 {
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

        let desired = try Self.validatedDocuments(documents)
        let manifestHash = Self.manifestHash(for: Array(desired.values))
        let previous = try generation()
        let stored = try Self.indexedProjectionState(in: database)
        var desiredState: [String: IndexedProjectionState] = [:]
        for (key, value) in desired {
            desiredState[key] = IndexedProjectionState(
                fingerprint: value.document.fingerprint,
                projectionHash: try Self.indexedProjectionHash(value),
                vaultName: value.vaultName,
                vaultRole: value.vaultRole,
                stableNoteID: value.stableNoteID,
                evidentialLayer: value.evidentialLayer
            )
        }
        let changedKeys = desired.keys.filter { stored[$0] != desiredState[$0] }
        let removedKeys = Set(stored.keys).subtracting(desired.keys)
        let delta = SearchIndexDelta(
            workspaceGeneration: workspaceGeneration,
            upserts: changedKeys.compactMap { desired[$0] },
            deletions: try removedKeys.map {
                try Self.noteReference(documentKey: $0)
            }
        )
        if previous?.sourceManifestHash == manifestHash, stored == desiredState,
           let previous {
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
            return TriptychSearchIndexSyncResult(
                generation: previous,
                disposition: .unchanged
            )
        }

        if let previous, previous.sequence > 0 {
            currentAvailability = .refreshing(lastGood: previous)
        } else {
            currentAvailability = .building(SearchBuildProgress(
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
        let progressReporter: (@Sendable (Int) -> Void)?
        if previous == nil {
            let expectedTotal = desired.count
            progressReporter = { [weak self] completed -> Void in
                guard let self else { return }
                _ = Task {
                    await self.recordInitialBuildProgress(
                        synchronizationID: identifier,
                        completed: completed,
                        total: expectedTotal
                    )
                }
            }
        } else {
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
            task: task
        )
        activeSynchronization = active
        return try await finishSynchronization(active)
    }

    private func recordInitialBuildProgress(
        synchronizationID: UUID,
        completed: Int,
        total: Int
    ) {
        guard activeSynchronization?.id == synchronizationID,
              case .building = currentAvailability else { return }
        currentAvailability = .building(SearchBuildProgress(
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
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                recoveredGeneratedDatabase = false
                currentAvailability = .current(result.generation)
            }
            return result
        } catch is CancellationError {
            if activeSynchronization?.id == synchronization.id {
                activeSynchronization = nil
                currentAvailability = synchronization.previous.map(SearchAvailability.current)
                    ?? .unavailable
            }
            throw CancellationError()
        } catch {
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
                try deleteDocument(key: key, from: database)
                try insert(document, into: database)
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
        linkMatches: [VaultQualifiedNoteID: SearchLinkMatch] = [:],
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]? = nil
    ) throws -> SearchResponse {
        try database.readTransaction {
            try Task.checkCancellation()
            let readGeneration = try generation()
            let availability = responseAvailability(for: readGeneration)
            let freshness: SearchFreshnessToken = switch request.executionScope {
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
                    availability: .note(availability),
                    results: [],
                    hasMore: false,
                    diagnostics: [SearchQueryDiagnostic(
                        code: .notApplicable,
                        message: "Search presentation and execution scopes do not match.",
                        utf16LowerBound: 0,
                        utf16UpperBound: 0
                    )]
                )
            }
            guard ast.provider == .note else {
                return SearchResponse(
                    requestID: request.id,
                    scope: request.presentationScope,
                    explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness,
                    availability: .note(availability),
                    results: [],
                    hasMore: false,
                    diagnostics: [SearchQueryDiagnostic(
                        code: .providerMismatch,
                        message: "The Note index cannot execute a non-Note provider plan.",
                        utf16LowerBound: 0,
                        utf16UpperBound: request.query.utf16.count
                    )]
                )
            }
            guard request.limit > 0 else {
                return SearchResponse(
                    requestID: request.id,
                    scope: request.presentationScope,
                    explanation: ast.explanation(scope: request.presentationScope),
                    freshnessToken: freshness,
                    availability: .note(availability),
                    results: [],
                    hasMore: false
                )
            }
            let boundedLimit = min(max(1, request.limit), SearchContract.maximumCLIResults)
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

    /// Retrieves explanatory Analysis/Topic related Notes from one ephemeral
    /// source Note snapshot. This is not query parsing: it reuses the current
    /// Note FTS generation and its BM25 field weights without creating a Saved
    /// Search, second index, or durable seed.
    public func relatedContent(
        _ request: RelatedContentRequest
    ) throws -> RelatedContentResponse {
        try database.readTransaction {
            try Task.checkCancellation()
            let readGeneration = try generation()
            let availability = responseAvailability(for: readGeneration)
            let freshness = readGeneration.map(SearchFreshnessToken.triptych)
                ?? SearchFreshnessToken(
                    "triptych:\(triptychID.uuidString.lowercased()):unavailable"
                )

            guard case .current(let currentGeneration) = availability,
                  currentGeneration.sequence > 0 else {
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
                    .contains(descriptor.role) else {
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
            ).applyingNoteMetadata(
                request.seed.metadata,
                profile: profile,
                source: document.rawContent
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
            let lexicalPool = try relatedContentCandidates(
                terms: material.combinedTerms,
                excluding: request.seed.noteID,
                candidateRoles: request.candidateRoles,
                limit: RelatedContentContract.maximumLexicalCandidatePool
            )
            let lexical = lexicalPool.compactMap { candidate -> RelatedLexicalCandidate? in
                let reason = material.lexicalReason(for: candidate)
                guard !reason.seedMatches.isEmpty else { return nil }
                return RelatedLexicalCandidate(
                    candidate: candidate,
                    reason: reason
                )
            }.sorted(by: RelatedLexicalCandidate.precedes)
            let lexicalHasMore = lexical.count > request.lexicalLimit
            let lexicalResults = lexical.prefix(request.lexicalLimit).map { item in
                RelatedContentCandidate(
                    note: item.candidate.document.noteID,
                    vaultRole: item.candidate.document.vaultRole,
                    title: item.candidate.document.title,
                    fingerprint: item.candidate.document.fingerprint,
                    reason: .lexicalOverlap(item.reason)
                )
            }
            let hasCandidates = !identity.candidates.isEmpty
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
        linkMatches: [VaultQualifiedNoteID: SearchLinkMatch],
        eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]?
    ) throws -> SearchResponse {
        guard let generation, generation.sequence > 0 else {
            return SearchResponse(
                requestID: request.id,
                scope: request.presentationScope,
                explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: freshness,
                availability: .note(availability),
                results: [],
                hasMore: false
            )
        }
        var accepted: [SearchCandidate] = []
        var seen = Set<Int>()

        if let identity = ast.identityNeedle {
            var exactOffset = 0
            let exactPageSize = min(256, max(32, limit + 1))
            while accepted.count < limit + 1 {
                let exact = try exactCandidates(
                    ast: ast,
                    identityKey: identity,
                    vaultID: vaultID,
                    limit: exactPageSize,
                    offset: exactOffset
                )
                guard !exact.isEmpty else { break }
                exactOffset += exact.count
                for candidate in exact {
                    try Task.checkCancellation()
                    guard Self.isIncluded(
                            candidate.document,
                            in: request.includedVaultIDs
                          ),
                          Self.isEligible(candidate.document, in: eligibleDocuments),
                          seen.insert(candidate.document.rowID).inserted,
                          SearchMatcher.satisfies(
                            ast,
                            document: candidate.document,
                            linkMatches: linkMatches
                          ) else { continue }
                    accepted.append(candidate)
                    if accepted.count >= limit + 1 { break }
                }
                if exact.count < exactPageSize { break }
            }
        }

        if accepted.count < limit + 1 {
            var offset = 0
            // Candidate materialization loads exact aliases and source
            // segments. Bound the first page to the number a response can
            // actually consume; structured filters can request further pages
            // without paying for 256 full documents on every ordinary query.
            let pageSize = min(256, max(32, limit + 1))
            while accepted.count < limit + 1 {
                try Task.checkCancellation()
                let page: [SearchCandidate]
                if ast.positiveLexicalClauses.isEmpty {
                    page = try documentCandidates(
                        ast: ast,
                        vaultID: vaultID,
                        limit: pageSize,
                        offset: offset
                    )
                } else {
                    page = try lexicalCandidates(
                        ast: ast,
                        vaultID: vaultID,
                        limit: pageSize,
                        offset: offset
                    )
                }
                guard !page.isEmpty else { break }
                offset += page.count
                for candidate in page {
                    try Task.checkCancellation()
                    guard Self.isIncluded(
                            candidate.document,
                            in: request.includedVaultIDs
                          ),
                          Self.isEligible(candidate.document, in: eligibleDocuments),
                          seen.insert(candidate.document.rowID).inserted,
                          SearchMatcher.satisfies(
                            ast,
                            document: candidate.document,
                            linkMatches: linkMatches
                          ) else { continue }
                    accepted.append(candidate)
                    if accepted.count >= limit + 1 { break }
                }
                if page.count < pageSize { break }
            }
        }

        accepted.sort(by: SearchCandidate.precedes)
        let hasMore = accepted.count > limit
        let hits = accepted.prefix(limit).map {
            NoteSearchResultBuilder.hit(
                candidate: $0,
                ast: ast,
                freshness: freshness,
                linkMatch: linkMatches[$0.document.noteID]
            )
        }
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: ast.explanation(scope: request.presentationScope),
            freshnessToken: freshness,
            availability: .note(availability),
            results: hits.map(SearchResult.note),
            hasMore: hasMore
        )
    }

    private nonisolated static func isEligible(
        _ document: StoredSearchDocument,
        in eligibleDocuments: [VaultQualifiedNoteID: SearchIndexDocumentEligibility]?
    ) -> Bool {
        guard let eligibleDocuments else { return true }
        guard let eligibility = eligibleDocuments[document.noteID],
              eligibility.fingerprint == document.fingerprint else {
            return false
        }
        guard let storedStableNoteID = document.stableNoteID else { return true }
        guard let indexedStableNoteID = UUID(uuidString: storedStableNoteID) else {
            return false
        }
        return eligibility.resolvedStableNoteID == indexedStableNoteID
    }

    private nonisolated static func isIncluded(
        _ document: StoredSearchDocument,
        in includedVaultIDs: [UUID]?
    ) -> Bool {
        guard let includedVaultIDs else { return true }
        return includedVaultIDs.contains(document.vaultID)
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
            guard let document = try self.loadDocument(rowID: row.int(at: 0)),
                  let reason = material.identityMentionReason(for: document)
            else { return }
            matches.append(RelatedIdentityCandidate(
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
        candidateRoles: [RelatedContentCandidateRole],
        limit: Int
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
            SELECT d.id,
                   bm25(search_fts, 0.0, 3.0, 8.0, 7.0, 6.0, 5.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.0) AS lexical_rank
            FROM search_fts
            JOIN search_documents d ON d.id = search_fts.document_id
            WHERE search_fts MATCH ?
              AND d.role IN (\(rolePlaceholders))
              AND NOT (d.vault_id = ? AND d.relative_path = ?)
            ORDER BY lexical_rank, d.normalized_title, d.role_order,
                     d.path_key, d.relative_path
            LIMIT ?;
            """,
            bindings: [
                .text(expression),
            ] + candidateRoles.map {
                .text($0.vaultRole.rawValue)
            } + [
                .text(seed.vaultID.uuidString.lowercased()),
                .text(seed.relativePath),
                .int(limit),
            ]
        ) { row in
            try Task.checkCancellation()
            guard let document = try self.loadDocument(rowID: row.int(at: 0))
            else { return }
            result.append(SearchCandidate(
                document: document,
                identityPriority: 10,
                lexicalRank: row.double(at: 1)
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
        linkMatches: [VaultQualifiedNoteID: SearchLinkMatch]
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
        ).applyingNoteMetadata(
            source.metadata,
            profile: profile,
            source: note.rawContent
        )
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
            titleUsesFilenameFallback: projection.titleUsesFilenameFallback,
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
            properties: SearchPropertyProjection(
                document: note,
                profile: profile,
                metadata: source.metadata,
                metadataCatalog: source.metadataCatalog
            ).entries
        )
        guard SearchMatcher.satisfies(
            ast,
            document: document,
            linkMatches: linkMatches
        ) else {
            return SearchResponse(
                requestID: request.id,
                scope: request.presentationScope,
                explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: freshness,
                availability: .note(availability),
                results: [],
                hasMore: false
            )
        }

        let candidate = SearchCandidate(
            document: document,
            identityPriority: SearchMatcher.identityPriority(
                identityNeedle: ast.identityNeedle,
                document: document
            ),
            lexicalRank: 0
        )
        let hits: [NoteSearchResult]
        if let lead = ast.firstPositiveLexicalClause {
            hits = NoteSearchResultBuilder.occurrenceHits(
                candidate: candidate,
                ast: ast,
                lead: lead,
                freshness: freshness,
                limit: limit,
                linkMatch: linkMatches[document.noteID]
            )
        } else {
            hits = [NoteSearchResultBuilder.hit(
                candidate: candidate,
                ast: ast,
                freshness: freshness,
                linkMatch: linkMatches[document.noteID]
            )]
        }
        return SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: ast.explanation(scope: request.presentationScope),
            freshnessToken: freshness,
            availability: .note(availability),
            results: hits.map(SearchResult.note),
            hasMore: hits.count >= limit
                && SearchMatcher.occurrenceCount(of: ast.firstPositiveLexicalClause, in: document) > limit
        )
    }

    private func responseAvailability(
        for generation: SearchGenerationID?
    ) -> SearchAvailability {
        if let generation,
           case .refreshing(let lastGood) = currentAvailability,
           generation != lastGood {
            // The writer committed before its awaiting continuation resumed.
            // This read transaction has already captured the complete new
            // generation, so expose it as current rather than mislabelling it.
            currentAvailability = .current(generation)
        }
        return currentAvailability
    }

    private func exactCandidates(
        ast: SearchQueryAST,
        identityKey: String,
        vaultID: UUID?,
        limit: Int,
        offset: Int
    ) throws -> [SearchCandidate] {
        let lexicalExpression = ast.positiveLexicalClauses.isEmpty
            ? nil
            : SearchMatcher.ftsExpression(for: ast.positiveLexicalClauses)
        var sql = """
        SELECT d.id,
               CASE
                 WHEN d.title_key = ? THEN 0
                 WHEN EXISTS(SELECT 1 FROM search_aliases a WHERE a.document_id = d.id AND a.exact_key = ?) THEN 1
                 WHEN d.filename_key = ? THEN 2
                 WHEN d.path_key = ? THEN 3
                 ELSE 10
               END AS identity_priority,
        """
        if lexicalExpression != nil {
            sql += "\n"
            sql += """
               bm25(search_fts, 0.0, 3.0, 8.0, 7.0, 6.0, 5.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.0) AS lexical_rank
            FROM search_fts
            JOIN search_documents d ON d.id = search_fts.document_id
            """
        } else {
            sql += "\n"
            sql += """
               0.0 AS lexical_rank
            FROM search_documents d
            """
        }
        sql += "\n"
        sql += """
        WHERE (d.title_key = ?
           OR EXISTS(SELECT 1 FROM search_aliases a WHERE a.document_id = d.id AND a.exact_key = ?)
           OR d.filename_key = ? OR d.path_key = ?)
        """
        var bindings = Array(repeating: SearchSQLiteBinding.text(identityKey), count: 8)
        if let lexicalExpression {
            sql += " AND search_fts MATCH ?"
            bindings.append(.text(lexicalExpression))
        }
        let filters = Self.candidateFilters(for: ast)
        sql += filters.sql
        bindings.append(contentsOf: filters.bindings)
        if let vaultID {
            sql += " AND d.vault_id = ?"
            bindings.append(.text(vaultID.uuidString.lowercased()))
        }
        sql += " ORDER BY identity_priority, lexical_rank, d.normalized_title, d.role_order, d.path_key, d.relative_path LIMIT ? OFFSET ?;"
        bindings.append(.int(limit))
        bindings.append(.int(offset))
        var result: [SearchCandidate] = []
        try database.query(sql, bindings: bindings) { row in
            guard let document = try self.loadDocument(
                rowID: row.int(at: 0),
                includingProperties: ast.hasPropertyClause
            ) else { return }
            result.append(SearchCandidate(
                document: document,
                identityPriority: row.int(at: 1),
                lexicalRank: row.double(at: 2)
            ))
        }
        return result
    }

    private func lexicalCandidates(
        ast: SearchQueryAST,
        vaultID: UUID?,
        limit: Int,
        offset: Int
    ) throws -> [SearchCandidate] {
        let expression = SearchMatcher.ftsExpression(for: ast.positiveLexicalClauses)
        var sql = """
        SELECT d.id,
               bm25(search_fts, 0.0, 3.0, 8.0, 7.0, 6.0, 5.0, 6.0, 4.0, 5.0, 2.0, 2.0, 3.0, 1.0) AS lexical_rank
        FROM search_fts
        JOIN search_documents d ON d.id = search_fts.document_id
        WHERE search_fts MATCH ?
        """
        var bindings: [SearchSQLiteBinding] = [.text(expression)]
        let filters = Self.candidateFilters(for: ast)
        sql += filters.sql
        bindings.append(contentsOf: filters.bindings)
        if let vaultID {
            sql += " AND d.vault_id = ?"
            bindings.append(.text(vaultID.uuidString.lowercased()))
        }
        sql += " ORDER BY lexical_rank, d.normalized_title, d.role_order, d.path_key, d.relative_path LIMIT ? OFFSET ?;"
        bindings.append(.int(limit))
        bindings.append(.int(offset))
        var result: [SearchCandidate] = []
        try database.query(sql, bindings: bindings) { row in
            guard let document = try self.loadDocument(
                rowID: row.int(at: 0),
                includingProperties: ast.hasPropertyClause
            ) else { return }
            result.append(SearchCandidate(
                document: document,
                identityPriority: 10,
                lexicalRank: row.double(at: 1)
            ))
        }
        return result
    }

    private func documentCandidates(
        ast: SearchQueryAST,
        vaultID: UUID?,
        limit: Int,
        offset: Int
    ) throws -> [SearchCandidate] {
        var sql = "SELECT d.id FROM search_documents d WHERE 1 = 1"
        let filters = Self.candidateFilters(for: ast)
        sql += filters.sql
        var bindings = filters.bindings
        if let vaultID {
            sql += " AND d.vault_id = ?"
            bindings.append(.text(vaultID.uuidString.lowercased()))
        }
        sql += " ORDER BY d.normalized_title, d.role_order, d.path_key, d.relative_path LIMIT ? OFFSET ?;"
        bindings.append(.int(limit))
        bindings.append(.int(offset))
        var result: [SearchCandidate] = []
        try database.query(sql, bindings: bindings) { row in
            guard let document = try self.loadDocument(
                rowID: row.int(at: 0),
                includingProperties: ast.hasPropertyClause
            ) else { return }
            result.append(SearchCandidate(
                document: document,
                identityPriority: 10,
                lexicalRank: 0
            ))
        }
        return result
    }

    private static func candidateFilters(
        for ast: SearchQueryAST
    ) -> (sql: String, bindings: [SearchSQLiteBinding]) {
        var sql = ""
        var bindings: [SearchSQLiteBinding] = []
        for clause in ast.clauses {
            switch clause {
            case .property(let property):
                sql += " AND EXISTS(SELECT 1 FROM search_properties p WHERE p.document_id = d.id AND p.property_key = ?"
                bindings.append(.text(property.key))
                if let value = property.value {
                    sql += " AND p.normalized_value = ?"
                    bindings.append(.text(value))
                }
                sql += ")"
            case .structured(let structured):
                let condition: String
                switch structured.field {
                case .callout:
                    condition = "instr(d.callout_roles, ?) > 0"
                    bindings.append(.text(" \(structured.value) "))
                case .has:
                    guard structured.value == "broken-link" else { continue }
                    condition = "d.has_broken_link = 1"
                }
                sql += structured.excluded
                    ? " AND NOT (\(condition))"
                    : " AND \(condition)"
            case .lexical, .link:
                break
            }
        }
        return (sql, bindings)
    }

    private func loadDocument(
        rowID: Int,
        includingProperties: Bool = false
    ) throws -> StoredSearchDocument? {
        var document: StoredSearchDocument?
        try database.query(
            """
            SELECT vault_id, vault_name, role, relative_path, stable_note_id, title,
                   normalized_title, title_key, filename_key, path_key, callout_roles,
                   has_broken_link, fingerprint_sha256, fingerprint_byte_count,
                   evidential_layer, role_order, line_starts, source_utf16_count
            FROM search_documents WHERE id = ?;
            """,
            bindings: [.int(rowID)]
        ) { row in
            guard let vaultText = row.text(at: 0), let vaultID = UUID(uuidString: vaultText),
                  let vaultName = row.text(at: 1), let roleText = row.text(at: 2),
                  let role = VaultRole(rawValue: roleText), let path = row.text(at: 3),
                  let title = row.text(at: 5), let normalizedTitle = row.text(at: 6),
                  let titleKey = row.text(at: 7), let filenameKey = row.text(at: 8),
                  let pathKey = row.text(at: 9), let sha = row.text(at: 12),
                  let layerText = row.text(at: 14),
                  let layer = EvidentialLayer(rawValue: layerText) else { return }
            let sourceUTF16Count = row.int(at: 17)
            let lineStarts = try Self.decodeGeneratedJSON(
                [Int].self,
                from: row.text(at: 16)
            )
            guard sourceUTF16Count >= 0,
                  lineStarts.first == 0,
                  lineStarts.last.map({ $0 <= sourceUTF16Count }) == true,
                  zip(lineStarts, lineStarts.dropFirst()).allSatisfy({ previous, next in
                      previous < next
                  }) else {
                throw SearchIndexError.corruptDatabase
            }
            let aliases = try self.aliases(documentID: rowID)
            let segments = try self.segments(
                documentID: rowID,
                sourceUTF16Count: sourceUTF16Count
            )
            let properties = includingProperties
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
                titleUsesFilenameFallback: titleKey.isEmpty,
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
                properties: properties
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
        sourceUTF16Count: Int
    ) throws -> [SearchTextSegment] {
        var result: [SearchTextSegment] = []
        try database.query(
            """
            SELECT field, ordinal, text, normalized_text, source_lower, source_upper,
                   source_line, source_column, source_end_line, source_end_column, offset_map
            FROM search_segments WHERE document_id = ? ORDER BY ordinal;
            """,
            bindings: [.int(documentID)]
        ) { row in
            guard let fieldText = row.text(at: 0),
                  let field = SearchMatchedField(rawValue: fieldText),
                  let text = row.text(at: 2), let normalized = row.text(at: 3) else { return }
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
            guard Self.valid(
                offsets: offsets,
                normalizedUTF16Count: normalized.utf16.count,
                sourceUTF16Bounds: sourceRange.map {
                    (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound)
                },
                sourceUTF16Count: sourceUTF16Count
            ) else {
                throw SearchIndexError.corruptDatabase
            }
            result.append(SearchTextSegment(
                field: field,
                ordinal: row.int(at: 1),
                text: text,
                normalizedText: normalized,
                sourceRange: sourceRange,
                offsetMap: offsets
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
            let keyRange = row.isNull(at: 6) ? nil : SearchSourceRange(
                utf16LowerBound: row.int(at: 6),
                utf16UpperBound: row.int(at: 7),
                line: row.int(at: 8),
                column: row.int(at: 9),
                endLine: row.int(at: 10),
                endColumn: row.int(at: 11)
            )
            var accumulator = values[key] ?? Accumulator(
                key: key,
                keyRange: keyRange,
                valueKind: kind,
                isEmpty: row.int(at: 2) == 1,
                members: []
            )
            if let rawValue = row.text(at: 4),
               let normalizedValue = row.text(at: 5) {
                accumulator.members.append(SearchPropertyProjection.StringMember(
                    value: rawValue,
                    normalizedValue: normalizedValue,
                    sourceRange: row.isNull(at: 12) ? nil : SearchSourceRange(
                        utf16LowerBound: row.int(at: 12),
                        utf16UpperBound: row.int(at: 13),
                        line: row.int(at: 14),
                        column: row.int(at: 15),
                        endLine: row.int(at: 16),
                        endColumn: row.int(at: 17)
                    )
                ))
            }
            values[key] = accumulator
        }
        return values.values.map {
            SearchPropertyProjection.Entry(
                key: $0.key,
                keySourceRange: $0.keyRange,
                valueKind: $0.valueKind,
                isEmpty: $0.isEmpty,
                stringMembers: $0.members
            )
        }.sorted { $0.key < $1.key }
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
               let role = VaultRole(rawValue: roleText) {
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

    /// Covers every value persisted for one indexed Note. The source-derived
    /// projection hash alone cannot detect a managed-Metadata-only property
    /// change because those fields deliberately have no Markdown range.
    private nonisolated static func indexedProjectionHash(
        _ document: SearchIndexDocument
    ) throws -> String {
        let propertyData = try JSONEncoder.searchIndex.encode(
            document.propertyProjection.entries
        )
        var material = Data(document.projection.projectionHash.utf8)
        material.append(0)
        material.append(propertyData)
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
                  let evidentialLayer = EvidentialLayer(rawValue: layerText) else { return }
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
        SearchSourceManifest.hash(documents.map {
            SearchSourceManifestEntry(
                vaultID: $0.vaultID,
                relativePath: $0.relativePath,
                fingerprint: $0.document.fingerprint
            )
        })
    }

    private static func insert(
        _ item: SearchIndexDocument,
        into database: SearchSQLiteDatabase
    ) throws {
        let projection = item.projection
        let lineStarts = String(
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
                source_utf16_count
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(documentKey(vaultID: item.vaultID, path: item.relativePath)),
                .text(item.vaultID.uuidString.lowercased()), .text(item.vaultName),
                .text(item.vaultRole.rawValue), .int(roleOrder(item.vaultRole)),
                .text(item.relativePath), .optionalText(item.stableNoteID), .text(projection.title),
                .text(SearchTextNormalization.normalize(projection.title)),
                .text(projection.titleUsesFilenameFallback
                    ? ""
                    : SearchTextNormalization.normalize(projection.title)),
                .text(SearchTextNormalization.normalize(
                    ((item.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
                )),
                .text(SearchTextNormalization.normalize(item.relativePath)),
                .text(item.document.fingerprint.sha256), .int(item.document.fingerprint.byteCount),
                .text(item.evidentialLayer.rawValue),
                .text(" " + projection.calloutRoles.sorted().joined(separator: " ") + " "),
                .int(projection.hasBrokenLink ? 1 : 0),
                .text(try indexedProjectionHash(item)),
                .text(lineStarts),
                .int(item.document.rawContent.utf16.count),
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
            guard valid(
                offsets: segment.offsetMap,
                normalizedUTF16Count: segment.normalizedText.utf16.count,
                sourceUTF16Bounds: segment.sourceRange.map {
                    (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound)
                },
                sourceUTF16Count: item.document.rawContent.utf16.count
            ) else {
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
                    source_end_line, source_end_column, offset_map
                ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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
                .text(SearchTokenization.indexText(projection.title)),
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
        try database.execute("""
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
            source_utf16_count INTEGER NOT NULL
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
              values.4 == SearchContract.rankingPolicyVersion else {
            throw SearchIndexError.incompatibleSchema
        }
        let definition = try database.scalarText(
            "SELECT sql FROM sqlite_master WHERE name = 'search_fts';"
        )?.uppercased()
        guard definition?.contains("USING FTS5") == true,
              definition?.contains("CONTENT=") == false else {
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

    private static func validateGeneratedJSON(
        in database: SearchSQLiteDatabase
    ) throws {
        try Task.checkCancellation()
        try database.query(
            "SELECT line_starts, source_utf16_count FROM search_documents;"
        ) { row in
            try Task.checkCancellation()
            let lineStarts = try decodeGeneratedJSON(
                [Int].self,
                from: row.text(at: 0)
            )
            let sourceUTF16Count = row.int(at: 1)
            guard sourceUTF16Count >= 0,
                  lineStarts.first == 0,
                  lineStarts.last.map({ $0 <= sourceUTF16Count }) == true,
                  zip(lineStarts, lineStarts.dropFirst()).allSatisfy({ previous, next in
                      previous < next
                  }) else {
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
            let offsets = try SearchOffsetMapCodec.decode(row.data(at: 3))
            guard valid(
                offsets: offsets,
                normalizedUTF16Count: normalized.utf16.count,
                sourceUTF16Bounds: sourceBounds,
                sourceUTF16Count: row.int(at: 4)
            ) else {
                throw SearchIndexError.corruptDatabase
            }
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

    private static func valid(
        offsets: [SearchSegmentOffset],
        normalizedUTF16Count: Int,
        sourceUTF16Bounds: (lower: Int, upper: Int)?,
        sourceUTF16Count: Int? = nil
    ) -> Bool {
        guard normalizedUTF16Count >= 0 else { return false }
        guard let sourceUTF16Bounds else { return offsets.isEmpty }
        guard sourceUTF16Bounds.lower >= 0,
              sourceUTF16Bounds.upper >= sourceUTF16Bounds.lower,
              sourceUTF16Count.map({ sourceUTF16Bounds.upper <= $0 }) ?? true else {
            return false
        }
        guard offsets.allSatisfy({ offset in
            offset.normalizedUTF16LowerBound >= 0
                && offset.normalizedUTF16UpperBound >= offset.normalizedUTF16LowerBound
                && offset.normalizedUTF16UpperBound <= normalizedUTF16Count
                && offset.sourceUTF16LowerBound >= 0
                && offset.sourceUTF16UpperBound >= offset.sourceUTF16LowerBound
                && offset.sourceUTF16LowerBound >= sourceUTF16Bounds.lower
                && offset.sourceUTF16UpperBound <= sourceUTF16Bounds.upper
        }) else { return false }
        return zip(offsets, offsets.dropFirst()).allSatisfy { previous, next in
            previous.normalizedUTF16LowerBound <= next.normalizedUTF16LowerBound
                && previous.sourceUTF16LowerBound <= next.sourceUTF16LowerBound
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
              let vaultID = UUID(uuidString: String(documentKey[..<separator])) else {
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

private extension SearchIndexError {
    var permitsSearchRecovery: Bool {
        switch self {
        case .corruptDatabase, .incompatibleSchema: true
        default: false
        }
    }
}

private struct StoredSearchDocument {
    let rowID: Int
    let vaultID: UUID
    let vaultName: String
    let vaultRole: VaultRole
    let relativePath: String
    let stableNoteID: String?
    let title: String
    let normalizedTitle: String
    let titleUsesFilenameFallback: Bool
    let filenameKey: String
    let pathKey: String
    let aliases: [String]
    let calloutRoles: Set<String>
    let hasBrokenLink: Bool
    let fingerprint: DocumentFingerprint
    let evidentialLayer: EvidentialLayer
    let roleOrder: Int
    let sourceLineStarts: [Int]
    let segments: [SearchTextSegment]
    let properties: [SearchPropertyProjection.Entry]

    var noteID: VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath)
    }
}

private struct SearchCandidate {
    let document: StoredSearchDocument
    let identityPriority: Int
    let lexicalRank: Double

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.identityPriority != rhs.identityPriority {
            return lhs.identityPriority < rhs.identityPriority
        }
        if lhs.lexicalRank != rhs.lexicalRank { return lhs.lexicalRank < rhs.lexicalRank }
        if lhs.document.normalizedTitle != rhs.document.normalizedTitle {
            return lhs.document.normalizedTitle < rhs.document.normalizedTitle
        }
        if lhs.document.roleOrder != rhs.document.roleOrder {
            return lhs.document.roleOrder < rhs.document.roleOrder
        }
        if lhs.document.pathKey != rhs.document.pathKey {
            return lhs.document.pathKey < rhs.document.pathKey
        }
        return lhs.document.relativePath < rhs.document.relativePath
    }
}

private struct RelatedIdentityCandidate {
    let document: StoredSearchDocument
    let reason: RelatedContentIdentityMentionReason

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        let left = minimumMentionOrder(lhs.reason.mentions)
        let right = minimumMentionOrder(rhs.reason.mentions)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        return documentPrecedes(lhs.document, rhs.document)
    }

    private static func minimumMentionOrder(
        _ mentions: [RelatedContentIdentityMention]
    ) -> (Int, Int) {
        mentions.map(mentionOrder).reduce((Int.max, Int.max)) { current, next in
            if next.0 != current.0 { return next.0 < current.0 ? next : current }
            return next.1 < current.1 ? next : current
        }
    }

    private static func mentionOrder(
        _ mention: RelatedContentIdentityMention
    ) -> (Int, Int) {
        (
            RelatedContentSeedKind.rankingOrder.firstIndex(
                of: mention.seedKind
            ) ?? Int.max,
            mention.identityKind == .title ? 0 : 1
        )
    }

    private static func documentPrecedes(
        _ lhs: StoredSearchDocument,
        _ rhs: StoredSearchDocument
    ) -> Bool {
        if lhs.normalizedTitle != rhs.normalizedTitle {
            return lhs.normalizedTitle < rhs.normalizedTitle
        }
        if lhs.roleOrder != rhs.roleOrder { return lhs.roleOrder < rhs.roleOrder }
        if lhs.pathKey != rhs.pathKey { return lhs.pathKey < rhs.pathKey }
        return lhs.relativePath < rhs.relativePath
    }
}

private struct RelatedLexicalCandidate {
    let candidate: SearchCandidate
    let reason: RelatedContentLexicalReason

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        for kind in RelatedContentSeedKind.rankingOrder {
            let left = lhs.matchCount(kind)
            let right = rhs.matchCount(kind)
            if left != right { return left > right }
        }
        return SearchCandidate.precedes(lhs.candidate, rhs.candidate)
    }

    private func matchCount(_ kind: RelatedContentSeedKind) -> Int {
        reason.seedMatches.first { $0.seedKind == kind }?.terms.count ?? 0
    }
}

private struct RelatedContentSeedSegment {
    let kind: RelatedContentSeedKind
    let field: SearchMatchedField?
    let normalizedText: String
}

private struct RelatedContentSeedTermGroup {
    let kind: RelatedContentSeedKind
    let terms: [String]
}

private struct RelatedContentSeedMaterial {
    let segments: [RelatedContentSeedSegment]
    let termGroups: [RelatedContentSeedTermGroup]
    let combinedTerms: [String]

    init(
        projection: SearchDocumentProjection,
        focuses: [RelatedContentSeedFocus]
    ) {
        let sourceFields: Set<SearchMatchedField> = [
            .title, .heading, .summary, .body, .callout, .footnote, .linkAnnotation, .tag,
        ]
        var segments = focuses.map {
            RelatedContentSeedSegment(
                kind: $0.kind,
                field: nil,
                normalizedText: SearchTextNormalization.normalize($0.text)
            )
        }
        segments.append(contentsOf: projection.segments.compactMap { segment in
            guard sourceFields.contains(segment.field) else { return nil }
            return RelatedContentSeedSegment(
                kind: .sourceNote,
                field: segment.field,
                normalizedText: segment.normalizedText
            )
        })
        self.segments = segments

        var groups: [RelatedContentSeedTermGroup] = focuses.map {
            RelatedContentSeedTermGroup(
                kind: $0.kind,
                terms: RelatedContentSeedTermExtractor.terms(
                    in: $0.text,
                    limit: RelatedContentContract.maximumFocusSeedTerms
                )
            )
        }
        groups.append(RelatedContentSeedTermGroup(
            kind: .sourceNote,
            terms: RelatedContentSeedTermExtractor.terms(
                in: projection,
                limit: RelatedContentContract.maximumSourceSeedTerms
            )
        ))
        termGroups = groups

        var terms: [String] = []
        var seen = Set<String>()
        for kind in RelatedContentSeedKind.rankingOrder {
            for term in groups.first(where: { $0.kind == kind })?.terms ?? []
                where terms.count
                    < RelatedContentContract.maximumCombinedSeedTerms {
                if seen.insert(term).inserted { terms.append(term) }
            }
        }
        combinedTerms = terms
    }

    func identityMentionReason(
        for document: StoredSearchDocument
    ) -> RelatedContentIdentityMentionReason? {
        var identities: [(RelatedContentIdentityKind, String)] = []
        if !document.titleUsesFilenameFallback {
            identities.append((.title, document.title))
        }
        identities.append(contentsOf: document.aliases.map { (.alias, $0) })
        var mentions: [RelatedContentIdentityMention] = []
        var seen = Set<RelatedContentIdentityMention>()
        for (identityKind, identity) in identities {
            let value = SearchLexicalValue.phrase(identity)
            for segment in segments where !SearchMatcher.occurrences(
                of: value,
                in: segment.normalizedText
            ).isEmpty {
                let mention = RelatedContentIdentityMention(
                    seedKind: segment.kind,
                    identityKind: identityKind,
                    matchedIdentity: identity,
                    seedField: segment.field
                )
                if seen.insert(mention).inserted { mentions.append(mention) }
            }
        }
        mentions.sort { lhs, rhs in
            let leftKind = RelatedContentSeedKind.rankingOrder.firstIndex(
                of: lhs.seedKind
            ) ?? Int.max
            let rightKind = RelatedContentSeedKind.rankingOrder.firstIndex(
                of: rhs.seedKind
            ) ?? Int.max
            if leftKind != rightKind { return leftKind < rightKind }
            if lhs.identityKind != rhs.identityKind {
                return lhs.identityKind == .title
            }
            return (lhs.seedField?.rawValue ?? "", lhs.matchedIdentity)
                < (rhs.seedField?.rawValue ?? "", rhs.matchedIdentity)
        }
        return mentions.isEmpty
            ? nil
            : RelatedContentIdentityMentionReason(mentions: mentions)
    }

    func lexicalReason(
        for candidate: SearchCandidate
    ) -> RelatedContentLexicalReason {
        var fields: [SearchMatchedField] = []
        var seedMatches: [RelatedContentSeedTermMatch] = []
        for group in termGroups {
            var matches: [String] = []
            for term in group.terms {
                let value = SearchLexicalValue.term(term)
                let matchingSegments = candidate.document.segments.filter {
                    !SearchMatcher.occurrences(
                        of: value,
                        in: $0.normalizedText
                    ).isEmpty
                }
                guard !matchingSegments.isEmpty else { continue }
                if matches.count < 8 { matches.append(term) }
                for segment in matchingSegments where !fields.contains(segment.field) {
                    fields.append(segment.field)
                }
            }
            if !matches.isEmpty {
                seedMatches.append(RelatedContentSeedTermMatch(
                    seedKind: group.kind,
                    terms: matches
                ))
            }
        }
        return RelatedContentLexicalReason(
            matchedFields: fields,
            seedMatches: seedMatches
        )
    }
}

private enum RelatedContentSeedTermExtractor {
    private static let ignoredLatinTerms: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "being", "but",
        "by", "for", "from", "had", "has", "have", "if", "in", "is", "it",
        "its", "not", "of", "on", "or", "that", "the", "these", "this",
        "those", "to", "was", "we", "were", "with",
    ]

    static func terms(
        in projection: SearchDocumentProjection,
        limit: Int
    ) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var seen = Set<String>()

        func appendDistinct(_ values: [String], maximum: Int) {
            var inserted = 0
            for value in values where result.count < limit && inserted < maximum {
                guard seen.insert(value).inserted else { continue }
                result.append(value)
                inserted += 1
            }
        }

        appendDistinct(tokens(in: projection.title), maximum: 12)
        appendDistinct(tokens(in: projection.summary ?? ""), maximum: 16)
        appendDistinct(
            projection.tags.flatMap(tokens(in:)),
            maximum: 12
        )
        appendDistinct(
            projection.headings.flatMap(tokens(in:)),
            maximum: 16
        )

        var bodyCounts: [String: (count: Int, first: Int)] = [:]
        for (index, token) in tokens(in: projection.body).enumerated() {
            let existing = bodyCounts[token]
            bodyCounts[token] = (
                count: min(8, (existing?.count ?? 0) + 1),
                first: existing?.first ?? index
            )
        }
        let orderedBody = bodyCounts.sorted { left, right in
            if left.value.count != right.value.count {
                return left.value.count > right.value.count
            }
            if left.value.first != right.value.first {
                return left.value.first < right.value.first
            }
            return left.key < right.key
        }.map(\.key)
        appendDistinct(orderedBody, maximum: limit)
        return result
    }

    static func terms(in value: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        var seen = Set<String>()
        for token in tokens(in: value) where result.count < limit {
            if seen.insert(token).inserted { result.append(token) }
        }
        return result
    }

    private static func tokens(in value: String) -> [String] {
        let normalized = SearchTextNormalization.normalize(value)
        var result: [String] = []
        var current = ""
        var currentIsCJK: Bool?

        func finish() {
            guard !current.isEmpty else { return }
            let candidates = currentIsCJK == true
                ? SearchTokenization.queryTokens(for: current)
                : [current]
            for candidate in candidates {
                let token = SearchTextNormalization.normalize(candidate)
                let containsCJK = SearchTokenization.containsCJK(token)
                guard !token.isEmpty,
                      token.utf8.count <= 128,
                      containsCJK || token.count > 1,
                      containsCJK || !ignoredLatinTerms.contains(token) else {
                    continue
                }
                result.append(token)
            }
            current = ""
            currentIsCJK = nil
        }

        for scalar in normalized.unicodeScalars {
            let isCJK = SearchTokenization.isCJK(scalar)
            let isToken = CharacterSet.alphanumerics.contains(scalar)
            guard isCJK || isToken else {
                finish()
                continue
            }
            if let currentIsCJK, currentIsCJK != isCJK { finish() }
            currentIsCJK = isCJK
            current.unicodeScalars.append(scalar)
        }
        finish()
        return result
    }
}

private enum SearchMatcher {
    static func satisfies(
        _ ast: SearchQueryAST,
        document: StoredSearchDocument,
        linkMatches: [VaultQualifiedNoteID: SearchLinkMatch]
    ) -> Bool {
        ast.clauses.allSatisfy { clause in
            switch clause {
            case .lexical(let lexical):
                let matched = matchingSegments(for: lexical, in: document).contains {
                    !occurrences(of: lexical.value, in: $0.normalizedText).isEmpty
                }
                return lexical.excluded ? !matched : matched
            case .structured(let structured):
                let matched: Bool = switch structured.field {
                case .callout: document.calloutRoles.contains(structured.value)
                case .has: structured.value == "broken-link" && document.hasBrokenLink
                }
                return structured.excluded ? !matched : matched
            case .property(let property):
                return propertyMatch(property, in: document) != nil
            case .link:
                return linkMatches[document.noteID] != nil
            }
        }
    }

    static func propertyMatch(
        _ clause: SearchPropertyClause,
        in document: StoredSearchDocument
    ) -> SearchPropertyMatch? {
        guard let entry = document.properties.first(where: {
            $0.key == clause.key
        }) else { return nil }
        guard let value = clause.value else {
            return SearchPropertyMatch(
                key: entry.key,
                mode: .presence,
                normalizedValue: nil,
                valueKind: entry.valueKind,
                isEmpty: entry.isEmpty,
                keySourceRange: entry.keySourceRange
            )
        }
        let matchingMembers = entry.stringMembers.filter {
            $0.normalizedValue == value
        }
        guard !matchingMembers.isEmpty else { return nil }
        let ranges = matchingMembers.compactMap(\.sourceRange)
        return SearchPropertyMatch(
            key: entry.key,
            mode: .exactStringValue,
            normalizedValue: value,
            valueKind: entry.valueKind,
            isEmpty: entry.isEmpty,
            keySourceRange: entry.keySourceRange,
            valueSourceRanges: ranges
        )
    }

    static func identityPriority(
        identityNeedle: String?,
        document: StoredSearchDocument
    ) -> Int {
        guard let identityNeedle else { return 10 }
        if !document.titleUsesFilenameFallback,
           document.normalizedTitle == identityNeedle { return 0 }
        if document.aliases.contains(where: {
            SearchTextNormalization.normalize($0) == identityNeedle
        }) { return 1 }
        if document.filenameKey == identityNeedle { return 2 }
        if document.pathKey == identityNeedle { return 3 }
        return 10
    }

    static func matchedFields(
        ast: SearchQueryAST,
        document: StoredSearchDocument
    ) -> [SearchMatchedField] {
        var fields: [SearchMatchedField] = []
        for clause in ast.positiveLexicalClauses {
            for segment in matchingSegments(for: clause, in: document)
                where !occurrences(of: clause.value, in: segment.normalizedText).isEmpty {
                if !fields.contains(segment.field) { fields.append(segment.field) }
            }
        }
        if fields.isEmpty, ast.isFilterOnly {
            for clause in ast.clauses {
                let field: SearchMatchedField?
                switch clause {
                case .structured(let structured):
                    field = switch structured.field {
                    case .callout: .callout
                    case .has: .brokenLink
                    }
                case .property, .link:
                    field = .title
                case .lexical:
                    field = nil
                }
                if let field, !fields.contains(field) { fields.append(field) }
            }
        }
        return fields
    }

    static func matchingSegments(
        for clause: SearchLexicalClause,
        in document: StoredSearchDocument
    ) -> [SearchTextSegment] {
        guard let field = clause.field else {
            return document.segments
        }
        let matched: SearchMatchedField = switch field {
        case .title: .title
        case .alias: .alias
        case .heading: .heading
        case .summary: .summary
        case .body: .body
        case .author: .author
        case .publicationDate: .publicationDate
        case .tag: .tag
        case .footnote: .footnote
        case .linkAnnotation: .linkAnnotation
        case .path: .path
        }
        return document.segments.filter { $0.field == matched }
    }

    static func occurrences(
        of value: SearchLexicalValue,
        in normalizedText: String
    ) -> [Range<Int>] {
        let needle = SearchTextNormalization.lexicalNormalize(value.text)
        guard !needle.isEmpty, !normalizedText.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var cursor = normalizedText.startIndex
        while cursor < normalizedText.endIndex,
              let range = normalizedText.range(of: needle, range: cursor..<normalizedText.endIndex) {
            let leadingBoundary = beginsWithCJK(value.text)
                || isTokenBoundary(before: range.lowerBound, in: normalizedText)
            let trailingBoundary: Bool
            switch value {
            case .prefix: trailingBoundary = true
            case .phrase, .term:
                trailingBoundary = endsWithCJK(value.text)
                    || isTokenBoundary(after: range.upperBound, in: normalizedText)
            }
            if leadingBoundary && trailingBoundary {
                let lowerBound = range.lowerBound.utf16Offset(in: normalizedText)
                let upperBound = range.upperBound.utf16Offset(in: normalizedText)
                result.append(lowerBound..<upperBound)
            }
            cursor = range.upperBound
        }
        return result
    }

    static func occurrenceCount(
        of clause: SearchLexicalClause?,
        in document: StoredSearchDocument
    ) -> Int {
        guard let clause else { return 0 }
        return matchingSegments(for: clause, in: document).reduce(into: 0) {
            $0 += occurrences(of: clause.value, in: $1.normalizedText).count
        }
    }

    static func ftsExpression(for clauses: [SearchLexicalClause]) -> String {
        clauses.map { clause in
            let tokens = SearchTokenization.queryTokens(for: clause.value.text)
            let terms: [String]
            if tokens.isEmpty {
                terms = [clause.value.text]
            } else {
                terms = tokens
            }
            let expression = terms.map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"" + (clause.value.isPrefix ? "*" : "")
            }.joined(separator: " AND ")
            let grouped = terms.count > 1 ? "(\(expression))" : expression
            guard let field = clause.field else { return grouped }
            let column: String = switch field {
            case .title: "title"
            case .alias: "aliases"
            case .heading: "headings"
            case .summary: "summary"
            case .body: "body"
            case .author: "authors"
            case .publicationDate: "publication_date"
            case .tag: "tags"
            case .footnote: "footnotes"
            case .linkAnnotation: "link_annotations"
            case .path: "path"
            }
            return "\(column):\(grouped)"
        }.joined(separator: " AND ")
    }

    private static func isTokenBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !isTokenCharacter(text[text.index(before: index)])
    }

    private static func beginsWithCJK(_ value: String) -> Bool {
        value.unicodeScalars.first.map(SearchTokenization.isCJK) ?? false
    }

    private static func endsWithCJK(_ value: String) -> Bool {
        value.unicodeScalars.last.map(SearchTokenization.isCJK) ?? false
    }

    private static func isTokenBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !isTokenCharacter(text[index])
    }

    private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}

private enum NoteSearchResultBuilder {
    static func hit(
        candidate: SearchCandidate,
        ast: SearchQueryAST,
        freshness: SearchFreshnessToken,
        linkMatch: SearchLinkMatch?
    ) -> NoteSearchResult {
        let document = candidate.document
        let matchedFields = SearchMatcher.matchedFields(ast: ast, document: document)
        let primary = matchedFields.first ?? .title
        let matched = firstMatch(ast: ast, document: document, preferredField: primary)
        let reasons = matchReasons(
            ast: ast,
            document: document,
            linkMatch: linkMatch
        )
        let property = reasons.compactMap { reason -> SearchPropertyMatch? in
            guard case .property(let value) = reason else { return nil }
            return value
        }.first
        let presentation: (text: String, highlights: [SearchHighlight])
        if let matched {
            presentation = snippet(
                segment: matched.segment,
                normalizedRange: matched.range,
                positiveClauses: ast.positiveLexicalClauses
            )
        } else if let property,
                  let entry = document.properties.first(where: { $0.key == property.key }) {
            let value = entry.stringMembers.first(where: {
                $0.normalizedValue == property.normalizedValue
            })?.value
            presentation = (value.map { "\(entry.key): \($0)" } ?? entry.key, [])
        } else {
            presentation = snippet(
                segment: document.segments.first { $0.field == .title },
                normalizedRange: nil,
                positiveClauses: ast.positiveLexicalClauses
            )
        }
        let lexicalSourceRange = matched.flatMap {
            sourceRange(for: $0.range, segment: $0.segment, lineStarts: document.sourceLineStarts)
        }
        let sourceRange = lexicalSourceRange
            ?? property?.valueSourceRanges.first
            ?? property?.keySourceRange
        let reason = rankReason(candidate.identityPriority, filterOnly: ast.isFilterOnly)
        return NoteSearchResult(
            resultID: "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(sourceRange?.utf16LowerBound ?? -1)",
            vaultID: document.vaultID,
            vaultName: document.vaultName,
            vaultRole: document.vaultRole,
            relativePath: document.relativePath,
            stableNoteID: document.stableNoteID,
            title: document.title,
            matchedField: primary,
            context: context(for: primary),
            sourceLine: sourceRange?.line ?? 1,
            snippet: presentation.text,
            highlights: presentation.highlights,
            matchedFields: matchedFields,
            rankReason: reason,
            primaryMatchReason: reasons.first ?? .lexical,
            additionalMatchReasons: Array(reasons.dropFirst()),
            sourceRange: sourceRange,
            freshnessToken: freshness,
            fingerprint: document.fingerprint,
            evidentialLayer: document.evidentialLayer,
            classification: .retrievalLead
        )
    }

    static func occurrenceHits(
        candidate: SearchCandidate,
        ast: SearchQueryAST,
        lead: SearchLexicalClause,
        freshness: SearchFreshnessToken,
        limit: Int,
        linkMatch: SearchLinkMatch?
    ) -> [NoteSearchResult] {
        let document = candidate.document
        let matchedFields = SearchMatcher.matchedFields(ast: ast, document: document)
        let reasons = matchReasons(
            ast: ast,
            document: document,
            linkMatch: linkMatch
        )
        var hits: [NoteSearchResult] = []
        for segment in SearchMatcher.matchingSegments(for: lead, in: document) {
            for range in SearchMatcher.occurrences(of: lead.value, in: segment.normalizedText) {
                guard hits.count < limit else { return hits }
                let sourceRange = sourceRange(
                    for: range,
                    segment: segment,
                    lineStarts: document.sourceLineStarts
                )
                let presentation = snippet(
                    segment: segment,
                    normalizedRange: range,
                    positiveClauses: ast.positiveLexicalClauses
                )
                hits.append(NoteSearchResult(
                    resultID: "\(document.vaultID.uuidString.lowercased()):\(document.relativePath):\(sourceRange?.utf16LowerBound ?? segment.ordinal)",
                    vaultID: document.vaultID,
                    vaultName: document.vaultName,
                    vaultRole: document.vaultRole,
                    relativePath: document.relativePath,
                    stableNoteID: document.stableNoteID,
                    title: document.title,
                    matchedField: segment.field,
                    context: context(for: segment.field),
                    sourceLine: sourceRange?.line ?? 1,
                    snippet: presentation.text,
                    highlights: presentation.highlights,
                    matchedFields: matchedFields,
                    rankReason: rankReason(candidate.identityPriority, filterOnly: ast.isFilterOnly),
                    primaryMatchReason: reasons.first ?? .lexical,
                    additionalMatchReasons: Array(reasons.dropFirst()),
                    sourceRange: sourceRange,
                    freshnessToken: freshness,
                    fingerprint: document.fingerprint,
                    evidentialLayer: document.evidentialLayer,
                    classification: .retrievalLead
                ))
            }
        }
        return hits
    }

    private static func matchReasons(
        ast: SearchQueryAST,
        document: StoredSearchDocument,
        linkMatch: SearchLinkMatch?
    ) -> [NoteSearchMatchReason] {
        var reasons: [NoteSearchMatchReason] = []
        if !ast.positiveLexicalClauses.isEmpty { reasons.append(.lexical) }
        for clause in ast.clauses {
            switch clause {
            case .structured(let value):
                reasons.append(.structured(SearchStructuredMatch(
                    field: value.field,
                    value: value.value,
                    excluded: value.excluded
                )))
            case .property(let value):
                if let match = SearchMatcher.propertyMatch(value, in: document) {
                    reasons.append(.property(match))
                }
            case .link:
                if let linkMatch {
                    reasons.append(.link(linkMatch))
                }
            case .lexical:
                continue
            }
        }
        if reasons.isEmpty { reasons.append(.lexical) }
        return reasons
    }

    private static func firstMatch(
        ast: SearchQueryAST,
        document: StoredSearchDocument,
        preferredField: SearchMatchedField
    ) -> (segment: SearchTextSegment, range: Range<Int>)? {
        for clause in ast.positiveLexicalClauses {
            let segments = SearchMatcher.matchingSegments(for: clause, in: document)
                .sorted { ($0.field == preferredField ? 0 : 1) < ($1.field == preferredField ? 0 : 1) }
            for segment in segments {
                if let range = SearchMatcher.occurrences(
                    of: clause.value,
                    in: segment.normalizedText
                ).first {
                    return (segment, range)
                }
            }
        }
        return nil
    }

    private static func sourceRange(
        for normalizedRange: Range<Int>,
        segment: SearchTextSegment,
        lineStarts: [Int]
    ) -> SearchSourceRange? {
        guard let range = segment.sourceUTF16Range(forNormalizedUTF16Range: normalizedRange) else {
            return segment.sourceRange
        }
        let start = position(range.lowerBound, lineStarts: lineStarts)
        let end = position(range.upperBound, lineStarts: lineStarts)
        return SearchSourceRange(
            utf16LowerBound: range.lowerBound,
            utf16UpperBound: range.upperBound,
            line: start.line,
            column: start.column,
            endLine: end.line,
            endColumn: end.column
        )
    }

    private static func position(
        _ offset: Int,
        lineStarts: [Int]
    ) -> (line: Int, column: Int) {
        guard !lineStarts.isEmpty else { return (1, offset + 1) }
        var low = 0
        var high = lineStarts.count
        while low + 1 < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle } else { high = middle }
        }
        return (low + 1, offset - lineStarts[low] + 1)
    }

    private static func snippet(
        segment: SearchTextSegment?,
        normalizedRange: Range<Int>?,
        positiveClauses: [SearchLexicalClause]
    ) -> (text: String, highlights: [SearchHighlight]) {
        guard let segment else { return ("", []) }
        let source = segment.text
        let targetUTF16 = normalizedRange.flatMap {
            SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                in: source,
                requestedRange: $0
            )
        } ?? 0..<0
        let boundedLower = min(max(0, targetUTF16.lowerBound), source.utf16.count)
        let boundedUpper = min(max(boundedLower, targetUTF16.upperBound), source.utf16.count)
        let boundedTarget = boundedLower..<boundedUpper
        let targetLower = String.Index(utf16Offset: boundedTarget.lowerBound, in: source)
        let targetUpper = String.Index(utf16Offset: boundedTarget.upperBound, in: source)
        let totalCharacters = source.count
        let targetStart = source.distance(from: source.startIndex, to: targetLower)
        let targetEnd = source.distance(from: source.startIndex, to: targetUpper)
        var lowerPosition = max(0, targetStart - 80)
        var upperPosition = min(totalCharacters, max(targetEnd, targetStart) + 160)
        for _ in 0..<3 {
            let decorations = (lowerPosition > 0 ? 1 : 0)
                + (upperPosition < totalCharacters ? 1 : 0)
            let allowed = max(1, 240 - decorations)
            guard upperPosition - lowerPosition > allowed else { break }
            upperPosition = lowerPosition + allowed
            if upperPosition < targetEnd {
                upperPosition = min(totalCharacters, targetEnd)
                lowerPosition = max(0, upperPosition - allowed)
            }
        }
        let lower = source.index(source.startIndex, offsetBy: lowerPosition)
        let upper = source.index(source.startIndex, offsetBy: upperPosition)
        let prefix = lowerPosition == 0 ? "" : "…"
        let suffix = upperPosition == totalCharacters ? "" : "…"
        let coreSource = String(source[lower..<upper])

        var core = ""
        var displayOffsets: [(original: Range<Int>, displayed: Range<Int>)] = []
        var originalCursor = 0
        for character in coreSource {
            let originalLength = String(character).utf16.count
            let displayed = character.isWhitespace ? " " : String(character)
            let displayedLower = core.utf16.count
            core += displayed
            displayOffsets.append((
                originalCursor..<(originalCursor + originalLength),
                displayedLower..<core.utf16.count
            ))
            originalCursor += originalLength
        }
        let text = prefix + core + suffix
        let contextLowerUTF16 = lower.utf16Offset(in: source)
        let contextUpperUTF16 = upper.utf16Offset(in: source)
        let prefixUTF16 = prefix.utf16.count
        var highlights: [SearchHighlight] = []
        for (clauseIndex, clause) in positiveClauses.enumerated() {
            let occurrences = clauseIndex == 0 && normalizedRange != nil
                ? [normalizedRange!]
                : SearchMatcher.occurrences(
                    of: clause.value,
                    in: segment.normalizedText
                )
            for normalizedOccurrence in occurrences {
                guard let original = SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
                    in: source,
                    requestedRange: normalizedOccurrence
                ), original.lowerBound >= contextLowerUTF16,
                   original.upperBound <= contextUpperUTF16 else { continue }
                let relativeLower = original.lowerBound - contextLowerUTF16
                let relativeUpper = original.upperBound - contextLowerUTF16
                let relative = relativeLower..<relativeUpper
                let overlapping = displayOffsets.filter {
                    $0.original.lowerBound < relative.upperBound
                        && $0.original.upperBound > relative.lowerBound
                }
                guard let first = overlapping.first, let last = overlapping.last else { continue }
                highlights.append(SearchHighlight(
                    utf16LowerBound: prefixUTF16 + first.displayed.lowerBound,
                    utf16UpperBound: prefixUTF16 + last.displayed.upperBound
                ))
            }
        }
        let uniqueHighlights = Array(Set(highlights)).sorted {
            if $0.utf16LowerBound != $1.utf16LowerBound {
                return $0.utf16LowerBound < $1.utf16LowerBound
            }
            return $0.utf16UpperBound < $1.utf16UpperBound
        }
        return (text, uniqueHighlights)
    }

    private static func rankReason(
        _ identityPriority: Int,
        filterOnly: Bool
    ) -> SearchRankReason {
        switch identityPriority {
        case 0: .exactTitle
        case 1: .exactAlias
        case 2: .exactFilename
        case 3: .exactPath
        default: filterOnly ? .structuredFilter : .lexicalRelevance
        }
    }

    private static func context(for field: SearchMatchedField) -> String {
        switch field {
        case .title: "Title"
        case .alias: "Alias"
        case .heading: "Heading"
        case .summary: "Summary"
        case .author: "Author"
        case .publicationDate: "Publication Date"
        case .tag: "Keyword"
        case .body: "Body"
        case .callout: "Callout"
        case .footnote: "Footnote"
        case .linkAnnotation: "Link Annotation"
        case .brokenLink: "Broken link"
        case .path: "Path"
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

/// A compact, private representation of exact normalized-to-source UTF-16
/// spans. Search schema changes rebuild this disposable state instead of
/// retaining a second decoder for older encodings.
private enum SearchOffsetMapCodec {
    private static let magic = Data([0x53, 0x4f, 0x4d, 0x31]) // SOM1
    private static let headerByteCount = 8
    private static let entryByteCount = 32

    static func encode(_ offsets: [SearchSegmentOffset]) throws -> Data {
        guard let count = UInt32(exactly: offsets.count),
              offsets.allSatisfy({ offset in
                  offset.normalizedUTF16LowerBound >= 0
                      && offset.normalizedUTF16UpperBound >= 0
                      && offset.sourceUTF16LowerBound >= 0
                      && offset.sourceUTF16UpperBound >= 0
              }) else {
            throw SearchIndexError.invalidDocuments(
                "Search offset map contains an invalid generated range."
            )
        }
        var data = Data(capacity: headerByteCount + offsets.count * entryByteCount)
        data.append(magic)
        append(count, to: &data)
        for offset in offsets {
            append(UInt64(offset.normalizedUTF16LowerBound), to: &data)
            append(UInt64(offset.normalizedUTF16UpperBound), to: &data)
            append(UInt64(offset.sourceUTF16LowerBound), to: &data)
            append(UInt64(offset.sourceUTF16UpperBound), to: &data)
        }
        return data
    }

    static func decode(_ data: Data?) throws -> [SearchSegmentOffset] {
        guard let data,
              data.count >= headerByteCount,
              data.prefix(magic.count) == magic else {
            throw SearchIndexError.corruptDatabase
        }
        return try data.withUnsafeBytes { bytes in
            let count = Int(UInt32(littleEndian: bytes.loadUnaligned(
                fromByteOffset: 4,
                as: UInt32.self
            )))
            guard count <= (data.count - headerByteCount) / entryByteCount,
                  data.count == headerByteCount + count * entryByteCount else {
                throw SearchIndexError.corruptDatabase
            }
            var offsets: [SearchSegmentOffset] = []
            offsets.reserveCapacity(count)
            var cursor = headerByteCount
            for _ in 0..<count {
                func value(_ component: Int) -> UInt64 {
                    UInt64(littleEndian: bytes.loadUnaligned(
                        fromByteOffset: cursor + component * 8,
                        as: UInt64.self
                    ))
                }
                let normalizedLower = value(0)
                let normalizedUpper = value(1)
                let sourceLower = value(2)
                let sourceUpper = value(3)
                let maximum = max(
                    max(normalizedLower, normalizedUpper),
                    max(sourceLower, sourceUpper)
                )
                guard maximum <= UInt64(Int.max) else {
                    throw SearchIndexError.corruptDatabase
                }
                offsets.append(SearchSegmentOffset(
                    normalizedUTF16LowerBound: Int(normalizedLower),
                    normalizedUTF16UpperBound: Int(normalizedUpper),
                    sourceUTF16LowerBound: Int(sourceLower),
                    sourceUTF16UpperBound: Int(sourceUpper)
                ))
                cursor += entryByteCount
            }
            return offsets
        }
    }

    private static func append<Value: FixedWidthInteger>(
        _ value: Value,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private enum SearchSQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int)
    case optionalInt(Int?)
    case blob(Data)
}

private final class SearchSQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "could not open Search v10 database"
            let code = handle.map { sqlite3_extended_errcode($0) }
            if let handle { sqlite3_close(handle) }
            if code.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
                throw SearchIndexError.corruptDatabase
            }
            throw SearchIndexError.sqlite(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
        sqlite3_progress_handler(
            handle,
            1_000,
            { _ in Task<Never, Never>.isCancelled ? 1 : 0 },
            nil
        )
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        if let handle {
            sqlite3_progress_handler(handle, 0, nil, nil)
            sqlite3_close(handle)
        }
    }

    var lastInsertRowID: Int { Int(sqlite3_last_insert_rowid(handle)) }

    func execute(_ sql: String, bindings: [SearchSQLiteBinding] = []) throws {
        if bindings.isEmpty {
            var error: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(handle, sql, nil, nil, &error)
            guard result == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? lastError
                sqlite3_free(error)
                throw sqliteError(code: result, message: message)
            }
            return
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        try statement.bind(bindings)
        let result = sqlite3_step(statement.handle)
        guard result == SQLITE_DONE else { throw sqliteError(code: result) }
    }

    func query(
        _ sql: String,
        bindings: [SearchSQLiteBinding] = [],
        row: (SearchSQLiteStatement) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        try statement.bind(bindings)
        while true {
            let result = sqlite3_step(statement.handle)
            switch result {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw sqliteError(code: result)
            }
        }
    }

    func scalarText(_ sql: String) throws -> String? {
        var value: String?
        try query(sql) { value = $0.text(at: 0) }
        return value
    }

    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    func readTransaction<Result>(_ operation: () throws -> Result) throws -> Result {
        try execute("BEGIN DEFERRED;")
        do {
            let result = try operation()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> SearchSQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw sqliteError(code: result)
        }
        return SearchSQLiteStatement(handle: statement)
    }

    private var lastError: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }

    private func sqliteError(code: Int32, message: String? = nil) -> Error {
        if code == SQLITE_INTERRUPT || Task<Never, Never>.isCancelled {
            return CancellationError()
        }
        let extended = handle.map { sqlite3_extended_errcode($0) }
        if extended.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
            return SearchIndexError.corruptDatabase
        }
        return SearchIndexError.sqlite(message ?? lastError)
    }
}

private struct SearchSQLiteStatement {
    let handle: OpaquePointer

    func bind(_ values: [SearchSQLiteBinding]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch value {
            case .text(let text):
                text.withCString { sqlite3_bind_text(handle, index, $0, -1, searchSQLiteTransient) }
            case .optionalText(let text):
                if let text {
                    text.withCString { sqlite3_bind_text(handle, index, $0, -1, searchSQLiteTransient) }
                } else {
                    sqlite3_bind_null(handle, index)
                }
            case .int(let value):
                sqlite3_bind_int64(handle, index, sqlite3_int64(value))
            case .optionalInt(let value):
                if let value {
                    sqlite3_bind_int64(handle, index, sqlite3_int64(value))
                } else {
                    sqlite3_bind_null(handle, index)
                }
            case .blob(let data):
                data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob64(
                        handle,
                        index,
                        bytes.baseAddress,
                        sqlite3_uint64(data.count),
                        searchSQLiteTransient
                    )
                }
            }
            guard result == SQLITE_OK else {
                throw SearchIndexError.sqlite("could not bind a Search v10 parameter")
            }
        }
    }

    func text(at column: Int32) -> String? {
        guard let value = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: value)
    }

    func data(at column: Int32) -> Data? {
        guard sqlite3_column_type(handle, column) != SQLITE_NULL else { return nil }
        let count = Int(sqlite3_column_bytes(handle, column))
        guard count > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(handle, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }

    func int(at column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
    func double(at column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func isNull(at column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
}

private let searchSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
