import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore
import Synchronization

struct RelatedContentRetrievalMeasurement: Sendable {
    let requestID: UUID
    let candidateCount: Int
    let sourceCount: Int
    let omittedSourceCount: Int
    let graphUsed: Bool
    let graphCandidateCount: Int
    let graphContextCount: Int
    /// Admission and index recall; the remaining stages partition the rest of totalDuration.
    let indexDuration: Duration
    /// Graph eligibility, construction and attachment, excluding current-source reads.
    let graphDuration: Duration
    /// Current-source loading and validation only; older measurements included graph work here.
    let readDuration: Duration
    let passageDuration: Duration
    /// Final availability/generation checks and response construction, including a stale return.
    let finalizationDuration: Duration
    /// Backend handle entry to return, excluding caller scheduling and native presentation.
    let totalDuration: Duration
}

private func currentNoteCompletionTerms(
    _ projection: SearchDocumentProjection,
    lookup: SearchCompletionLookup,
    limit: Int
) -> [SearchCompletionTerm] {
    struct Accumulator {
        var text: String
        var fields: Set<SearchLexicalField>
        var occurrenceCount: Int
    }

    let values: [(SearchLexicalField, String)] = [
        (.title, projection.title),
        (.alias, projection.aliases.joined(separator: "\n")),
        (.heading, projection.headings.joined(separator: "\n")),
        (.summary, projection.summary ?? ""),
        (.body, projection.body),
        (.author, projection.authors.joined(separator: "\n")),
        (.publicationDate, projection.publicationDate ?? ""),
        (.tag, projection.tags.joined(separator: "\n")),
        (.footnote, projection.footnotes),
        (.linkAnnotation, projection.linkAnnotations),
        (.path, projection.path),
    ]
    let normalizedPartial = lookup.normalizedPartial
    guard !normalizedPartial.isEmpty, limit > 0 else { return [] }
    var terms: [String: Accumulator] = [:]
    for (field, value) in values where lookup.field == nil || lookup.field == field {
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
        .prefix(limit)
        .map { $0 }
}

enum RelatedContentRefreshOwner: Hashable {
    case sourceCommit, liveInventory
}

struct RelatedContentRefreshWaiter {
    var owners: Set<RelatedContentRefreshOwner>
    let completion: AsyncStream<Void>.Continuation
}

extension WorkspaceHandle {
    /// Derived reads bind admission and delivery to the activation's current
    /// source access. Root invalidation remains latched until replacement.
    private func withDiscoveryAccess<Value: Sendable>(
        _ operation: () async throws -> Value
    ) async throws -> Value {
        try requireActive()
        try requireRootAuthoritiesAvailable()
        try Task.checkCancellation()
        let value = try await operation()
        #if DEBUG
            await discoveryResultDeliveryBarrierForTesting?()
        #endif
        try Task.checkCancellation()
        try requireActive()
        try requireRootAuthoritiesAvailable()
        return value
    }

    func links(for note: VaultQualifiedNoteID, direction: WorkspaceLinkDirection) async throws -> [LinkGraphEdge] {
        try await withDiscoveryAccess {
            try WorkspaceGraphQueries(catalog: currentSnapshot.discovery.catalog).links(for: note, direction: direction)
        }
    }

    func linkDiagnostics() async throws -> [LinkGraphDiagnostic] {
        try await withDiscoveryAccess {
            try WorkspaceGraphQueries(catalog: currentSnapshot.discovery.catalog).diagnostics()
        }
    }

    /// Observes only work already admitted by the owning refresh pumps. Each
    /// waiter ends at the captured batch boundary, not pump quiescence. Stream
    /// cancellation removes the query without cancelling shared source work.
    private func observeAdmittedRelatedRefreshWork() async throws -> Bool {
        try Task.checkCancellation()
        try requireActive()
        let observedMutation = try await observeAdmittedSourceMutation()
        try requireActive()
        var owners = Set<RelatedContentRefreshOwner>()
        if sourceCommitRefreshTask != nil { owners.insert(.sourceCommit) }
        if liveIndexRefreshTask != nil { owners.insert(.liveInventory) }
        guard !owners.isEmpty else { return observedMutation }
        let id = UUID()
        let signal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        relatedContentRefreshWaiters[id] = .init(owners: owners, completion: signal.continuation)
        defer { relatedContentRefreshWaiters[id] = nil }
        var iterator = signal.stream.makeAsyncIterator()
        _ = await iterator.next()
        try Task.checkCancellation()
        try requireActive()
        return true
    }

    func completeRelatedRefreshObservation(_ owner: RelatedContentRefreshOwner) {
        for id in Array(relatedContentRefreshWaiters.keys) {
            guard var waiter = relatedContentRefreshWaiters[id], waiter.owners.remove(owner) != nil else { continue }
            if waiter.owners.isEmpty {
                relatedContentRefreshWaiters[id] = nil
                waiter.completion.yield(())
                waiter.completion.finish()
            } else {
                relatedContentRefreshWaiters[id] = waiter
            }
        }
    }

    /// Recommendation projections depend on exact Markdown only. Keep these
    /// fresh, authorized source reads separate from managed-document hydration.
    private func loadRelatedContentSource(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try requireActive()
        #if DEBUG
            relatedContentSourceLoadAttemptsForTesting += 1
        #endif
        let repository = try repository(vaultID: id.vaultID)
        return try await repository.load(relativePath: id.relativePath)
    }

    struct RelatedContentPreparationMeasurement: Sendable {
        var sourceCount = 0
        var peakBufferedSourceCount = 0
        /// Exact freshly read source Data held by the batch, excluding parsed
        /// fields, Core memos and allocator overhead; not a process footprint.
        var peakBufferedSourceBytes = 0
        /// This call did no source I/O; only best-effort warmup was skipped.
        var reusedCompletedPreparation = false
        /// Another caller owns the producer's source-read measurement.
        var joinedRunningPreparation = false
    }

    struct RelatedContentPreparationKey: Hashable, Sendable {
        let note: VaultQualifiedNoteID
        let pathUTF8: Data
        let fingerprint: DocumentFingerprint
        let generation: SearchGenerationID
        let roles: [RelatedContentCandidateRole]
        let cohort: [WorkspaceCatalogNote]
        let sourceAuthority: UUID
    }

    struct RelatedContentPreparationWaiter: Sendable {
        let completion: AsyncStream<Result<RelatedContentPreparationMeasurement?, Error>>.Continuation
        let cancellation: RelatedContentPreparationCancellation
        let joined: Bool
    }

    /// The cancellation callback must make its one-way signal visible before
    /// its actor cleanup can run. The flight and its membership stay actor owned.
    final class RelatedContentPreparationCancellation: Sendable {
        private let cancelled = Mutex(false)
        var isCancelled: Bool { cancelled.withLock { $0 } }
        func cancel() { cancelled.withLock { $0 = true } }
    }

    struct RelatedContentPreparationFlight: Sendable {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: RelatedContentPreparationWaiter]
    }

    /// Best-effort preparation uses the same registered scope, source reads and
    /// Core projections as foreground retrieval. It publishes no workspace or
    /// result state, and never replaces the foreground's current-source checks.
    @discardableResult
    func prepareRelatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentPreparationMeasurement? {
        try await withDiscoveryAccess { try await prepareAuthorizedRelatedContent(request) }
    }

    private func prepareAuthorizedRelatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentPreparationMeasurement? {
        try requireActive()
        try Task.checkCancellation()
        guard currentSnapshot.phase.isComplete else { throw ScholiumApplicationError.workspaceStillLoading(id) }
        guard
            currentSnapshot.discovery.catalog.notes.contains(where: {
                $0.reference.vaultID == request.seed.noteID.vaultID && $0.reference.relativePath == request.seed.noteID.relativePath
            })
        else { throw CocoaError(.fileReadNoSuchFile) }
        guard let generation = currentSnapshot.discovery.searchGeneration, !hasPendingRelatedContentRefreshWork else { return nil }
        let key = RelatedContentPreparationKey(
            note: request.seed.noteID, pathUTF8: Data(request.seed.noteID.relativePath.utf8),
            fingerprint: request.seed.fingerprint, generation: generation,
            roles: RelatedContentCandidateRole.allCases.filter { request.candidateRoles.contains($0) },
            cohort: currentSnapshot.discovery.catalog.notes, sourceAuthority: sourceAuthorityToken)
        relatedContentCompletedPreparations.removeAll { !relatedPreparationIsCurrent($0) }
        for (obsolete, flight) in relatedContentPreparationFlights where !relatedPreparationIsCurrent(obsolete) {
            flight.task.cancel()
        }
        if let index = relatedContentCompletedPreparations.firstIndex(of: key) {
            relatedContentCompletedPreparations.remove(at: index)
            relatedContentCompletedPreparations.append(key)
            return .init(reusedCompletedPreparation: true)
        }
        let waiter = UUID()
        let cancellation = RelatedContentPreparationCancellation()
        let signal = AsyncStream<Result<RelatedContentPreparationMeasurement?, Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let flightID: UUID
        if var flight = relatedContentPreparationFlights[key] {
            guard !flight.task.isCancelled else { return nil }
            flightID = flight.id
            flight.waiters[waiter] = .init(completion: signal.continuation, cancellation: cancellation, joined: true)
            relatedContentPreparationFlights[key] = flight
        } else {
            // Preparation is best effort: bound active source batches as well
            // as completed metadata instead of queueing arbitrary seed keys.
            guard relatedContentPreparationFlights.count < 2 else { return nil }
            flightID = UUID()
            let background = RelatedContentRequest(
                id: request.id, seed: .init(noteID: request.seed.noteID, source: request.seed.source), candidateRoles: key.roles)
            let task = Task { [self] in
                let result: Result<RelatedContentPreparationMeasurement?, Error>
                do { result = .success(try await performRelatedContentPreparation(background, key: key)) } catch { result = .failure(error) }
                finishRelatedContentPreparation(key: key, id: flightID, result: result)
            }
            relatedContentPreparationFlights[key] = .init(
                id: flightID, task: task,
                waiters: [waiter: .init(completion: signal.continuation, cancellation: cancellation, joined: false)])
        }
        return try await withTaskCancellationHandler {
            defer { removeRelatedContentPreparationWaiter(key: key, flightID: flightID, waiter: waiter) }
            var iterator = signal.stream.makeAsyncIterator()
            let result = await iterator.next()
            try requireActive()
            try Task.checkCancellation()
            guard let result else { throw CancellationError() }
            return try result.get()
        } onCancel: {
            cancellation.cancel()
            Task { await self.removeRelatedContentPreparationWaiter(key: key, flightID: flightID, waiter: waiter) }
        }
    }

    private func relatedPreparationIsCurrent(_ key: RelatedContentPreparationKey) -> Bool {
        !isShutDown && unavailableRootVaultIDs.isEmpty && currentSnapshot.phase.isComplete
            && !hasPendingRelatedContentRefreshWork && sourceAuthorityToken == key.sourceAuthority
            && currentSnapshot.discovery.searchGeneration == key.generation
            && currentSnapshot.discovery.catalog.notes == key.cohort
    }

    private func removeRelatedContentPreparationWaiter(key: RelatedContentPreparationKey, flightID: UUID, waiter: UUID) {
        guard var flight = relatedContentPreparationFlights[key], flight.id == flightID else { return }
        flight.waiters.removeValue(forKey: waiter)?.completion.finish()
        if flight.waiters.isEmpty { flight.task.cancel() }
        relatedContentPreparationFlights[key] = flight
    }

    private func finishRelatedContentPreparation(
        key: RelatedContentPreparationKey, id: UUID, result: Result<RelatedContentPreparationMeasurement?, Error>
    ) {
        guard let flight = relatedContentPreparationFlights[key], flight.id == id else { return }
        relatedContentPreparationFlights[key] = nil
        if case .success(.some) = result, !flight.task.isCancelled,
            flight.waiters.values.contains(where: { !$0.cancellation.isCancelled }), relatedPreparationIsCurrent(key)
        {
            relatedContentCompletedPreparations.removeAll { $0 == key }
            relatedContentCompletedPreparations.append(key)
            if relatedContentCompletedPreparations.count > 2 { relatedContentCompletedPreparations.removeFirst() }
        }
        for waiter in flight.waiters.values {
            let delivered: Result<RelatedContentPreparationMeasurement?, Error>
            if waiter.joined, case .success(.some) = result {
                delivered = .success(.init(joinedRunningPreparation: true))
            } else {
                delivered = result
            }
            waiter.completion.yield(delivered)
            waiter.completion.finish()
        }
    }

    private func performRelatedContentPreparation(
        _ background: RelatedContentRequest, key: RelatedContentPreparationKey
    ) async throws -> RelatedContentPreparationMeasurement? {
        #if DEBUG
            await relatedContentPreparationStartedBarrierForTesting?()
        #endif
        try requireActive()
        try Task.checkCancellation()
        guard relatedPreparationIsCurrent(key) else { throw CancellationError() }
        let response = try await services.searchIndex.relatedMaterialSourceCandidates(background)
        try requireActive()
        try Task.checkCancellation()
        guard [.current, .empty].contains(response.state),
            case .current(let generation) = response.availability,
            generation == key.generation, relatedPreparationIsCurrent(key)
        else { return nil }
        let preparation = try await services.searchIndex.beginRelatedPassagePreparation(
            background, candidates: response.identityCandidates + response.lexicalCandidates, generation: generation)
        func requireCurrentPreparation() throws {
            try requireActive()
            try Task.checkCancellation()
            try requireRootAuthoritiesAvailable()
            guard relatedPreparationIsCurrent(key)
            else { throw CancellationError() }
        }
        try requireCurrentPreparation()
        var sources: [RelatedContentSource] = []
        sources.reserveCapacity(16)
        var measurement = RelatedContentPreparationMeasurement()
        var allSourcesPrepared = true
        var bufferedSourceBytes = 0
        var seen = Set<VaultQualifiedNoteID>()
        for candidate in response.identityCandidates + response.lexicalCandidates where seen.insert(candidate.note).inserted {
            try Task.checkCancellation()
            let document: NoteDocument
            do {
                document = try await loadRelatedContentSource(candidate.note)
            } catch is CancellationError { throw CancellationError() } catch {
                allSourcesPrepared = false
                continue
            }
            try Task.checkCancellation()
            guard document.fingerprint == candidate.fingerprint,
                document.rawContent.utf16.count <= RelatedContentContract.maximumSeedUTF16Count
            else {
                allSourcesPrepared = false
                continue
            }
            sources.append(.init(candidate: candidate, document: document))
            measurement.sourceCount += 1
            bufferedSourceBytes += document.sourceBytes.count
            measurement.peakBufferedSourceCount = max(measurement.peakBufferedSourceCount, sources.count)
            measurement.peakBufferedSourceBytes = max(measurement.peakBufferedSourceBytes, bufferedSourceBytes)
            // Flush at either bound. A single large permitted Note may cross
            // the byte bound, but cannot cause the following Notes to accumulate.
            if sources.count == 16 || bufferedSourceBytes >= 1_024 * 1_024 {
                try requireCurrentPreparation()
                try await services.searchIndex.prepareRelatedPassages(preparation, sources: sources)
                sources.removeAll(keepingCapacity: true)
                bufferedSourceBytes = 0
                try requireCurrentPreparation()
                await Task.yield()
            }
        }
        try requireCurrentPreparation()
        if !sources.isEmpty {
            try await services.searchIndex.prepareRelatedPassages(preparation, sources: sources)
        }
        try requireCurrentPreparation()
        guard try await services.searchIndex.availability() == .current(generation) else { return nil }
        try requireCurrentPreparation()
        return allSourcesPrepared ? measurement : nil
    }

    func writingCompletions(matching query: String) async throws -> [String] {
        try await withDiscoveryAccess { try await authorizedWritingCompletions(matching: query) }
    }

    private func authorizedWritingCompletions(matching query: String) async throws -> [String] {
        try requireActive()
        try Task.checkCancellation()
        guard currentSnapshot.phase.isComplete else { throw WritingCompletionLookupError.indexNotCurrent }
        let availability = try await services.searchIndex.availability()
        try requireActive()
        try Task.checkCancellation()
        guard currentSnapshot.phase.isComplete,
            let generation = currentSnapshot.discovery.searchGeneration,
            availability == .current(generation),
            !derivedStateRequiresRefresh, pendingSourceCommitRefreshes.isEmpty,
            sourceCommitRefreshTask == nil, pendingLiveEvents.isEmpty, liveIndexRefreshTask == nil
        else { throw WritingCompletionLookupError.indexNotCurrent }
        let captured = currentSnapshot
        let fingerprints = Dictionary(captured.vaults.flatMap(\.documents).map { ($0.id, $0.fingerprint) }, uniquingKeysWith: { first, _ in first })
        writingCompletionMemo.retain(fingerprints)
        var measurement = WritingCompletionLookupMeasurement()
        defer {
            if !isShutDown {
                lastWritingCompletionMeasurement = measurement
            }
        }
        let candidates = try await services.searchIndex.writingCompletionSources(matching: query)
        var terms = Set<String>()
        for candidate in candidates {
            try requireActive()
            try Task.checkCancellation()
            guard fingerprints[candidate.note] == candidate.fingerprint else {
                throw WritingCompletionLookupError.indexNotCurrent
            }
            do {
                let document = try await loadRelatedContentSource(candidate.note)
                if let barrier = writingCompletionPostSourceReadBarrierForTesting { await barrier() }
                try requireActive()
                try Task.checkCancellation()
                guard document.fingerprint == candidate.fingerprint else {
                    throw WritingCompletionLookupError.indexNotCurrent
                }
                measurement.sourceReads += 1
                let prepared = try writingCompletionMemo.vocabulary(for: candidate.note, document: document)
                if prepared.reused { measurement.projectionReuses += 1 } else { measurement.projectionBuilds += 1 }
                terms.formUnion(try prepared.value.terms(matching: query))
                if terms.count >= 32 { break }
            } catch is CancellationError { throw CancellationError() } catch {
                writingCompletionMemo.remove(candidate.note)
                throw WritingCompletionLookupError.sourceUnavailable
            }
        }
        try requireActive()
        try Task.checkCancellation()
        let finalAvailability = try await services.searchIndex.availability()
        try requireActive()
        try Task.checkCancellation()
        guard currentSnapshot.phase.isComplete,
            currentSnapshot.discovery.searchGeneration == generation,
            currentSnapshot.discovery.catalog.notes == captured.discovery.catalog.notes,
            finalAvailability == .current(generation),
            !derivedStateRequiresRefresh, pendingSourceCommitRefreshes.isEmpty,
            sourceCommitRefreshTask == nil, pendingLiveEvents.isEmpty, liveIndexRefreshTask == nil
        else { throw WritingCompletionLookupError.indexNotCurrent }
        return terms.sorted {
            let lhs = WritingCompletionPrefix.matchingCount($0, query: query)
            let rhs = WritingCompletionPrefix.matchingCount($1, query: query)
            if lhs != rhs { return lhs > rhs }
            if $0.utf16.count != $1.utf16.count { return $0.utf16.count < $1.utf16.count }
            return $0 < $1
        }.prefix(32).map { $0 }
    }

    func relatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentResponse {
        try await withDiscoveryAccess { try await authorizedRelatedContent(request) }
    }

    private func authorizedRelatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentResponse {
        lastRelatedContentMeasurement = nil
        let started = ContinuousClock.now
        try requireActive()
        guard currentSnapshot.phase.isComplete else {
            throw ScholiumApplicationError.workspaceStillLoading(id)
        }
        // Current registered membership, not index presence, authorizes the seed.
        guard
            currentSnapshot.discovery.catalog.notes.contains(where: {
                $0.reference.vaultID == request.seed.noteID.vaultID && $0.reference.relativePath == request.seed.noteID.relativePath
            })
        else { throw CocoaError(.fileReadNoSuchFile) }
        let capturedSnapshot = currentSnapshot
        let response = try await services.searchIndex.relatedMaterialSourceCandidates(request)
        let indexed = ContinuousClock.now
        try requireActive()
        try Task.checkCancellation()
        guard response.state == .current || response.state == .empty else { return response }
        guard case .current(let generation) = response.availability,
            capturedSnapshot.discovery.searchGeneration == generation,
            response.freshnessToken == .triptych(generation)
        else {
            return RelatedContentResponse(
                requestID: request.id, seedFingerprint: request.seed.fingerprint,
                freshnessToken: response.freshnessToken, availability: response.availability,
                state: .stale, identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
        }
        let canUseGraph = !hasPendingRelatedContentRefreshWork
        var graphResult: RelatedContentGraphCandidates.Result?
        if canUseGraph, let graph = capturedSnapshot.discovery.catalog.graph {
            let authorizedVaults = Set(assignment.vaults.values.map(\.id))
            let catalog = capturedSnapshot.discovery.catalog.notes.filter { authorizedVaults.contains($0.reference.vaultID) }
            let notes = capturedSnapshot.vaults.filter { authorizedVaults.contains($0.vault.id) }.flatMap(\.documents)
            let exactNotes = Dictionary(notes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if notes.count == catalog.count,
                catalog.allSatisfy({ note in
                    exactNotes[.init(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)]?.fingerprint == note.fingerprint
                })
            {
                graphResult = try await RelatedContentGraphCandidates.build(
                    request: request, graph: graph, searchGeneration: generation, catalog: catalog,
                    linkCatalog: notes.map(\.linkCatalog),
                    existingCandidates: response.identityCandidates + response.lexicalCandidates)
                #if DEBUG
                    await relatedContentGraphPreparedBarrierForTesting?()
                #endif
                try requireActive()
                try Task.checkCancellation()
                let indexedAvailability = try await services.searchIndex.availability()
                let availability = try await relatedContentAvailabilityAfterAdmittedRefresh(
                    indexedAvailability, capturedSnapshot: capturedSnapshot,
                    generation: generation, usesGraph: graphResult != nil)
                // The pure walk leaves this actor. Observe any admitted batch,
                // then reject a changed cohort before reading candidate sources.
                guard
                    relatedContentCohortIsCurrent(
                        capturedSnapshot, generation: generation, availability: availability,
                        usesGraph: graphResult != nil)
                else {
                    return staleRelatedContentResponse(request, original: response, availability: availability)
                }
            }
        }
        let identityCandidates = response.identityCandidates.map {
            RelatedContentGraphCandidates.attaching(graphResult?.contexts[$0.note], to: $0)
        }
        let lexicalCandidates = response.lexicalCandidates.map {
            RelatedContentGraphCandidates.attaching(graphResult?.contexts[$0.note], to: $0)
        }
        let graphCandidates = graphResult?.candidates ?? []
        var sources: [RelatedContentSource] = []
        var seen = Set<VaultQualifiedNoteID>()
        var omitted = 0
        let graphPrepared = ContinuousClock.now
        for candidate in identityCandidates + lexicalCandidates + graphCandidates where seen.insert(candidate.note).inserted {
            try Task.checkCancellation()
            do {
                let document = try await loadRelatedContentSource(candidate.note)
                guard document.fingerprint == candidate.fingerprint,
                    document.rawContent.utf16.count <= RelatedContentContract.maximumSeedUTF16Count
                else {
                    omitted += 1
                    continue
                }
                sources.append(.init(candidate: candidate, document: document))
            } catch is CancellationError { throw CancellationError() } catch { omitted += 1 }
        }
        let read = ContinuousClock.now
        let passages = try await services.searchIndex.relatedPassages(request, sources: sources)
        let ranked = ContinuousClock.now
        #if DEBUG
            await relatedContentFinalValidationBarrierForTesting?()
        #endif
        // Publish after final validation, without another suspension. Measurements
        // carry no source content and do not authorize publication of a response.
        defer {
            let finished = ContinuousClock.now
            lastRelatedContentMeasurement = RelatedContentRetrievalMeasurement(
                requestID: request.id, candidateCount: seen.count,
                sourceCount: sources.count, omittedSourceCount: omitted,
                graphUsed: graphResult != nil, graphCandidateCount: graphCandidates.count,
                graphContextCount: graphResult?.contexts.count ?? 0,
                indexDuration: started.duration(to: indexed),
                graphDuration: indexed.duration(to: graphPrepared),
                readDuration: graphPrepared.duration(to: read), passageDuration: read.duration(to: ranked),
                finalizationDuration: ranked.duration(to: finished), totalDuration: started.duration(to: finished))
        }
        try requireActive()
        try Task.checkCancellation()
        let indexedAvailability = try await services.searchIndex.availability()
        let finalAvailability = try await relatedContentAvailabilityAfterAdmittedRefresh(
            indexedAvailability, capturedSnapshot: capturedSnapshot,
            generation: generation, usesGraph: graphResult != nil)
        guard
            relatedContentCohortIsCurrent(
                capturedSnapshot, generation: generation, availability: finalAvailability,
                usesGraph: graphResult != nil)
        else {
            // A source read/ranking suspension may straddle refresh. Never publish
            // an old path boost, locator or candidate with a newer generation.
            return staleRelatedContentResponse(request, original: response, availability: finalAvailability)
        }
        return RelatedContentResponse(
            requestID: response.requestID, seedFingerprint: response.seedFingerprint,
            freshnessToken: response.freshnessToken, availability: response.availability,
            state: omitted > 0 ? .partial : (passages.isEmpty ? .empty : .current),
            identityCandidates: identityCandidates, lexicalCandidates: Array(lexicalCandidates.prefix(request.lexicalLimit)),
            identityHasMore: response.identityHasMore, lexicalHasMore: response.lexicalHasMore,
            graphCandidates: graphCandidates, graphHasMore: graphResult?.hasMore ?? false,
            passages: passages, omittedSourceCount: omitted)
    }

    private var hasPendingRelatedContentRefreshWork: Bool {
        derivedStateRequiresRefresh || !pendingSourceCommitRefreshes.isEmpty
            || sourceCommitRefreshTask != nil || !pendingLiveEvents.isEmpty || liveIndexRefreshTask != nil
    }

    private func relatedContentAvailabilityAfterAdmittedRefresh(
        _ availability: SearchAvailability, capturedSnapshot: WorkspaceSnapshot,
        generation: SearchGenerationID, usesGraph: Bool
    ) async throws -> SearchAvailability {
        try requireActive()
        try Task.checkCancellation()
        var availability = availability
        // An admitted batch may finish without a publication (for example a
        // harmless watcher hint). Observe its actual completion rather than
        // asking Search to refresh or waiting for an invented next generation.
        // A finite follow-on backlog can be observed at its next batch boundary;
        // candidates, source reads and ranking remain this one request pass.
        while usesGraph,
            !derivedStateRequiresRefresh,
            availability == .current(generation),
            currentSnapshot.discovery.searchGeneration == generation,
            currentSnapshot.discovery.catalog.notes == capturedSnapshot.discovery.catalog.notes,
            try await observeAdmittedRelatedRefreshWork()
        {
            availability = try await services.searchIndex.availability()
        }
        try requireActive()
        try Task.checkCancellation()
        return try await relatedContentAvailabilityAfterRefreshFailure(availability)
    }

    private func relatedContentCohortIsCurrent(
        _ capturedSnapshot: WorkspaceSnapshot, generation: SearchGenerationID,
        availability: SearchAvailability, usesGraph: Bool
    ) -> Bool {
        let currentGraph = currentSnapshot.discovery.catalog.graph
        let capturedGraph = capturedSnapshot.discovery.catalog.graph
        let graphIsCurrent =
            !usesGraph
            || (currentGraph?.contractVersion == GraphSnapshot.currentContractVersion
                && currentGraph?.contractVersion == capturedGraph?.contractVersion
                && !generation.sourceManifestHash.isEmpty
                && currentGraph?.sourceManifestHash == generation.sourceManifestHash
                && currentGraph?.outgoing == capturedGraph?.outgoing
                && !hasPendingRelatedContentRefreshWork)
        return currentSnapshot.phase.isComplete
            && currentSnapshot.discovery.searchGeneration == generation
            && currentSnapshot.discovery.catalog.notes == capturedSnapshot.discovery.catalog.notes
            && availability == .current(generation) && graphIsCurrent
    }

    private func relatedContentAvailabilityAfterRefreshFailure(_ availability: SearchAvailability) async throws -> SearchAvailability {
        var finalAvailability = availability
        if derivedStateRequiresRefresh {
            let failureSnapshot = currentSnapshot
            let failureSourceToken = sourceAuthorityToken
            let failureRoots = unavailableRootVaultIDs
            let publishedStatus = await events.derivedRefreshStatus
            finalAvailability = try await services.searchIndex.availability()
            try requireActive()
            try Task.checkCancellation()
            if derivedStateRequiresRefresh {
                // A failed catalog preparation may retain a healthy index.
                // Its published provider failure is actionable; current(G)
                // would incorrectly promise a future generation to wait for.
                switch finalAvailability {
                case .current, .refreshing:
                    let sameFailureContext =
                        sourceAuthorityToken == failureSourceToken
                        && unavailableRootVaultIDs == failureRoots
                        && currentSnapshot.phase == failureSnapshot.phase
                        && currentSnapshot.sourceInventoryRevision == failureSnapshot.sourceInventoryRevision
                        && currentSnapshot.discovery.searchGeneration == failureSnapshot.discovery.searchGeneration
                        && currentSnapshot.discovery.catalog.notes == failureSnapshot.discovery.catalog.notes
                    if sameFailureContext {
                        switch publishedStatus {
                        case .failed(let issue):
                            finalAvailability = .failed(lastGood: issue.lastKnownGood.searchGeneration, reason: issue.reason)
                        case .stale(let issue):
                            if let lastGood = issue.lastKnownGood.searchGeneration {
                                finalAvailability = .stale(lastGood: lastGood, reason: issue.reason)
                            } else {
                                finalAvailability = .failed(lastGood: nil, reason: issue.reason)
                            }
                        case .opening, .current:
                            finalAvailability = .unavailable
                        }
                    } else {
                        // A newer failed context cannot borrow an older reason.
                        finalAvailability = .unavailable
                    }
                default: break  // Keep an existing index failure's own reason.
                }
            }
        }
        return finalAvailability
    }

    private func staleRelatedContentResponse(
        _ request: RelatedContentRequest, original: RelatedContentResponse, availability: SearchAvailability
    ) -> RelatedContentResponse {
        RelatedContentResponse(
            requestID: request.id, seedFingerprint: request.seed.fingerprint,
            freshnessToken: availability.lastGoodGeneration.map(SearchFreshnessToken.triptych) ?? original.freshnessToken,
            availability: availability, state: .stale,
            identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try await withDiscoveryAccess { try await authorizedSearch(request) }
    }

    private func authorizedSearch(_ request: SearchRequest) async throws -> SearchResponse {
        try requireActive()
        if let diagnostic = searchScopeDiagnostic(request) {
            return await searchDiagnosticResponse(
                request: request,
                parsed: SearchQueryParseResult(
                    ast: nil,
                    diagnostics: [diagnostic]
                )
            )
        }

        let parsed = SearchQueryParser.parse(request.query)
        guard let ast = parsed.ast, parsed.diagnostics.isEmpty else {
            return await searchDiagnosticResponse(request: request, parsed: parsed)
        }
        if !currentSnapshot.phase.isComplete {
            guard ast.provider == .note else {
                throw ScholiumApplicationError.workspaceStillLoading(id)
            }
            switch request.executionScope {
            case .currentNote:
                break
            case .currentVault:
                guard
                    ast.clauses.allSatisfy({ clause in
                        if case .lexical = clause { return true }
                        return false
                    })
                else {
                    return await searchDiagnosticResponse(
                        request: request,
                        parsed: SearchQueryParseResult(
                            provider: .note,
                            providerWasExplicit: ast.providerWasExplicit,
                            ast: ast,
                            diagnostics: [
                                SearchQueryDiagnostic(
                                    reason: .openingVaultLexicalOnly,
                                    message: "While this Triptych is opening, This Vault Search supports words, phrases, and lexical fields only.",
                                    utf16LowerBound: 0,
                                    utf16UpperBound: request.query.utf16.count
                                )
                            ]
                        )
                    )
                }
            case .triptych:
                throw ScholiumApplicationError.workspaceStillLoading(id)
            }
        }
        if let diagnostic = ast.scopeDiagnostic(scope: request.presentationScope, queryUTF16Count: request.query.utf16.count) {
            return await searchDiagnosticResponse(
                request: request,
                parsed: SearchQueryParseResult(provider: .note, providerWasExplicit: ast.providerWasExplicit, ast: ast, diagnostics: [diagnostic]))
        }
        let link = NoteLinkSearchResolver.resolve(
            ast: ast,
            scope: request.executionScope,
            catalog: currentSnapshot.discovery.catalog,
            searchGeneration: currentSnapshot.discovery.searchGeneration,
            includedVaultIDs: request.includedVaultIDs
        )
        if let diagnostic = link.diagnostic {
            return await searchDiagnosticResponse(
                request: request,
                parsed: SearchQueryParseResult(
                    provider: .note,
                    providerWasExplicit: ast.providerWasExplicit,
                    ast: ast,
                    diagnostics: [diagnostic]
                )
            )
        }
        let response: SearchResponse
        if !currentSnapshot.phase.isComplete,
            case .currentNote(let source) = request.executionScope,
            let vault = assignment.vaults.values.first(where: { $0.id == source.noteID.vaultID })
        {
            let authorizedSource = SearchSourceSnapshot(
                noteID: source.noteID,
                stableNoteID: source.stableNoteID
                    ?? currentSnapshot.document(id: source.noteID)?.stableIdentity.resolvedID,
                editorSessionID: source.editorSessionID, source: source.source,
                editorRevision: source.editorRevision)
            let sourceRequest = SearchRequest(
                id: request.id, query: request.query,
                presentationScope: request.presentationScope,
                executionScope: .currentNote(authorizedSource),
                limit: request.limit, offset: request.resultOffset)
            response = try TriptychSearchIndex.searchCurrentSource(
                sourceRequest, ast: ast, vault: vault,
                availability: await sourceSearchAvailabilityWithoutIndex(),
                linkMatches: link.matches)
        } else if let index = await services.searchIndexOwner.readyIndex() {
            response = try await index.search(
                request, ast: ast, linkMatches: link.matches,
                eligibleDocuments: openingSearchEligibility(for: request))
        } else {
            response = SearchResponse(
                requestID: request.id, scope: request.presentationScope,
                explanation: ast.explanation(scope: request.presentationScope),
                freshnessToken: SearchFreshnessToken("triptych:\(id.uuidString.lowercased()):unavailable"),
                availability: await searchAvailabilityWithoutAdmission(),
                results: [], hasMore: false)
        }
        return openingVaultSearchResponse(response, request: request)
    }

    func searchCompletions(
        _ request: SearchCompletionRequest
    ) async throws -> SearchCompletionResponse {
        try await withDiscoveryAccess { try await authorizedSearchCompletions(request) }
    }

    private func authorizedSearchCompletions(
        _ request: SearchCompletionRequest
    ) async throws -> SearchCompletionResponse {
        try requireActive()
        let usesOpeningSource: Bool
        if !currentSnapshot.phase.isComplete, case .currentNote = request.executionScope {
            usesOpeningSource = true
        } else {
            usesOpeningSource = false
        }
        let index = usesOpeningSource ? nil : await services.searchIndexOwner.readyIndex()
        let availability =
            usesOpeningSource
            ? await sourceSearchAvailabilityWithoutIndex()
            : await searchAvailabilityWithoutAdmission()
        let generation = try await index?.generation()
        let freshness: SearchFreshnessToken =
            switch request.executionScope {
            case .currentNote(let source):
                .currentNote(source)
            case .currentVault, .triptych:
                generation.map(SearchFreshnessToken.triptych)
                    ?? SearchFreshnessToken(
                        "triptych:\(id.uuidString.lowercased()):unavailable"
                    )
            }
        guard request.hasConsistentScopes,
            request.limit > 0,
            searchScopeDiagnostic(
                SearchRequest(
                    id: request.id,
                    query: "completion",
                    presentationScope: request.presentationScope,
                    executionScope: request.executionScope,
                    limit: 1
                )
            ) == nil
        else {
            return SearchCompletionResponse(
                requestID: request.id,
                scope: request.presentationScope,
                freshnessToken: freshness,
                availability: availability,
                terms: []
            )
        }

        let terms: [SearchCompletionTerm]
        switch request.executionScope {
        case .currentNote(let source):
            let descriptor = assignment.vaults.values.first { $0.id == source.noteID.vaultID }
            let document = NoteDocument(
                relativePath: source.noteID.relativePath,
                rawContent: source.source
            )
            let projection = SearchDocumentProjection(
                document: document,
                profile: WorkflowProfileResolver.resolve(
                    vaultRole: descriptor?.role ?? .other
                )
            )
            terms = currentNoteCompletionTerms(
                projection,
                lookup: request.lookup,
                limit: request.limit
            )
        case .currentVault(let vaultID):
            guard let index else {
                return SearchCompletionResponse(
                    requestID: request.id, scope: request.presentationScope,
                    freshnessToken: freshness, availability: availability, terms: [])
            }
            terms = try await index.completionTerms(
                for: request.lookup,
                vaultID: vaultID,
                eligibleDocuments: openingSearchEligibility(
                    for: SearchRequest(
                        id: request.id,
                        query: "completion",
                        presentationScope: request.presentationScope,
                        executionScope: request.executionScope,
                        limit: 1
                    )
                ),
                limit: request.limit
            )
        case .triptych:
            guard currentSnapshot.phase.isComplete, let index else {
                return SearchCompletionResponse(
                    requestID: request.id, scope: request.presentationScope,
                    freshnessToken: freshness, availability: availability, terms: [])
            }
            terms = try await index.completionTerms(
                for: request.lookup,
                limit: request.limit
            )
        }
        return SearchCompletionResponse(
            requestID: request.id,
            scope: request.presentationScope,
            freshnessToken: freshness,
            availability: availability,
            terms: terms
        )
    }

    private func searchScopeDiagnostic(
        _ request: SearchRequest
    ) -> SearchQueryDiagnostic? {
        guard request.hasConsistentScopes else {
            return SearchQueryDiagnostic(
                reason: .inconsistentScopes,
                message: "Search presentation and execution scopes do not match.",
                utf16LowerBound: 0,
                utf16UpperBound: 0
            )
        }
        let authorizedVaultIDs = Set(assignment.vaults.values.map(\.id))
        if let includedVaultIDs = request.includedVaultIDs,
            includedVaultIDs.isEmpty
                || !Set(includedVaultIDs).isSubset(of: authorizedVaultIDs)
        {
            return SearchQueryDiagnostic(
                reason: .invalidVaultSubset,
                message: "The selected Search vault subset is empty or outside this Triptych.",
                utf16LowerBound: 0,
                utf16UpperBound: 0
            )
        }
        switch request.executionScope {
        case .triptych:
            return nil
        case .currentVault(let vaultID):
            guard authorizedVaultIDs.contains(vaultID) else {
                return SearchQueryDiagnostic(
                    reason: .vaultOutsideTriptych,
                    message: "The selected Search vault is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
            if case .opening = currentSnapshot.phase,
                currentSnapshot.vault(id: vaultID) == nil
            {
                return SearchQueryDiagnostic(
                    reason: .openingVaultUnavailable,
                    message: "This vault is not available yet while this Triptych finishes opening.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
        case .currentNote(let source):
            guard authorizedVaultIDs.contains(source.noteID.vaultID),
                currentSnapshot.discovery.catalog.notes.contains(where: {
                    $0.reference.vaultID == source.noteID.vaultID
                        && $0.reference.relativePath == source.noteID.relativePath
                })
            else {
                return SearchQueryDiagnostic(
                    reason: .noteOutsideTriptych,
                    message: "The selected Search Note is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
        }
        return nil
    }

    /// Source Find remains independent even after admission while the derived
    /// actor is busy converging. This grade never claims an unchecked generation.
    private func sourceSearchAvailabilityWithoutIndex() async -> SearchAvailability {
        if case .failed(let error) = await services.searchIndexOwner.admissionState() {
            return .failed(lastGood: nil, reason: error.localizedDescription)
        }
        return .unavailable
    }

    /// Diagnostics and source-buffer queries must never start generated-index
    /// admission or hide a failed admission behind an indefinite Building state.
    private func searchAvailabilityWithoutAdmission() async -> SearchAvailability {
        switch await services.searchIndexOwner.admissionState() {
        case .ready(let index):
            return await index.availability()
        case .failed(let error):
            return .failed(lastGood: nil, reason: error.localizedDescription)
        case .pending, .shutDown:
            return .unavailable
        }
    }

    private func searchDiagnosticResponse(
        request: SearchRequest,
        parsed: SearchQueryParseResult
    ) async -> SearchResponse {
        let noteAvailability: SearchAvailability
        if !currentSnapshot.phase.isComplete, case .currentNote = request.executionScope {
            noteAvailability = await sourceSearchAvailabilityWithoutIndex()
        } else {
            noteAvailability = await searchAvailabilityWithoutAdmission()
        }
        let availability = noteAvailability
        let freshness: SearchFreshnessToken
        switch request.executionScope {
        case .currentNote(let source):
            freshness = .currentNote(source)
        case .currentVault, .triptych:
            if let generation = noteAvailability.lastGoodGeneration {
                freshness = .triptych(generation)
            } else {
                freshness = SearchFreshnessToken(
                    "triptych:\(id.uuidString.lowercased()):unavailable"
                )
            }
        }
        let response = SearchResponse(
            requestID: request.id,
            scope: request.presentationScope,
            explanation: parsed.explanation(scope: request.presentationScope),
            freshnessToken: freshness,
            availability: availability,
            results: [],
            hasMore: false,
            diagnostics: parsed.diagnostics
        )
        return openingVaultSearchResponse(response, request: request)
    }

    /// Supplies exact opening authority to the index so rejected prior-
    /// generation candidates do not consume the visible limit or distort
    /// `hasMore`. The index remains the sole ranking and pagination owner.
    private func openingSearchEligibility(
        for request: SearchRequest
    ) -> [VaultQualifiedNoteID: SearchIndexDocumentEligibility]? {
        guard case .opening = currentSnapshot.phase,
            case .currentVault(let vaultID) = request.executionScope
        else {
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: currentSnapshot.vaults
                .filter { $0.vault.id == vaultID }
                .flatMap(\.documents)
                .map { note in
                    (
                        note.id,
                        SearchIndexDocumentEligibility(
                            fingerprint: note.fingerprint,
                            resolvedStableNoteID: note.stableIdentity.resolvedID
                        )
                    )
                })
    }

    /// Opening never publishes a partial generation. The index has already
    /// filtered the last complete generation against exact opening authority;
    /// this adapter changes only the visible availability grade.
    private func openingVaultSearchResponse(
        _ response: SearchResponse,
        request: SearchRequest
    ) -> SearchResponse {
        guard case .opening = currentSnapshot.phase,
            case .currentVault = request.executionScope
        else {
            return response
        }
        let availability = response.availability
        let openingAvailability: SearchAvailability =
            switch availability {
            case .current(let generation), .refreshing(let generation):
                .limited(lastGood: generation)
            case .unavailable:
                .building(SearchBuildProgress(completed: 0, total: 0))
            case .limited, .building, .stale, .failed:
                availability
            }
        return SearchResponse(
            contractVersion: response.contractVersion,
            requestID: response.requestID,
            scope: response.scope,
            explanation: response.explanation,
            freshnessToken: response.freshnessToken,
            availability: openingAvailability,
            results: response.results,
            hasMore: response.hasMore,
            totalResultCount: response.totalResultCount,
            indeterminateDocumentCount: response.indeterminateDocumentCount,
            diagnostics: response.diagnostics
        )
    }

}

private enum WritingCompletionLookupError: Error {
    case indexNotCurrent, sourceUnavailable
}

/// Counts only; no source, query, or result content is logged.
struct WritingCompletionLookupMeasurement: Sendable {
    var sourceReads = 0
    var projectionBuilds = 0
    var projectionReuses = 0
}

/// Runtime-owned, bounded memo of query-independent parsing work. A hit never
/// bypasses the fresh authorized source read or generation/publication guards.
struct WritingCompletionProjectionMemo: Sendable {
    private struct Entry: Sendable {
        let fingerprint: DocumentFingerprint
        let value: WritingCompletionVocabulary
        var lastAccess: UInt64
    }
    private var entries: [VaultQualifiedNoteID: Entry] = [:]
    private var access: UInt64 = 0
    private let maximumEntries: Int
    private let maximumEstimatedBytes: Int
    private(set) var estimatedByteCount = 0
    var entryCount: Int { entries.count }

    init(maximumEntries: Int = 64, maximumEstimatedBytes: Int = 4 * 1_024 * 1_024) {
        self.maximumEntries = max(0, maximumEntries)
        self.maximumEstimatedBytes = max(0, maximumEstimatedBytes)
    }

    mutating func vocabulary(for note: VaultQualifiedNoteID, document: NoteDocument) throws -> (value: WritingCompletionVocabulary, reused: Bool) {
        try Task.checkCancellation()
        access &+= 1
        if var entry = entries[note], entry.fingerprint == document.fingerprint {
            entry.lastAccess = access
            entries[note] = entry
            return (entry.value, true)
        }
        remove(note)
        let value = try WritingCompletionVocabulary(document: document)
        let cost = value.estimatedByteCount
        guard maximumEntries > 0, cost <= maximumEstimatedBytes else { return (value, false) }
        while entries.count >= maximumEntries || estimatedByteCount + cost > maximumEstimatedBytes {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(oldest)
        }
        entries[note] = .init(fingerprint: document.fingerprint, value: value, lastAccess: access)
        estimatedByteCount += cost
        return (value, false)
    }

    mutating func retain(_ fingerprints: [VaultQualifiedNoteID: DocumentFingerprint]) {
        for note in entries.keys.filter({ fingerprints[$0] != entries[$0]?.fingerprint }) { remove(note) }
    }

    mutating func remove(_ note: VaultQualifiedNoteID) {
        if let old = entries.removeValue(forKey: note) { estimatedByteCount -= old.value.estimatedByteCount }
    }

    mutating func clear() {
        entries.removeAll()
        estimatedByteCount = 0
    }
}
