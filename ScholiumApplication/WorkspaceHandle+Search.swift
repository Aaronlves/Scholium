import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

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

extension WorkspaceHandle {
    struct RelatedContentPreparationMeasurement: Sendable {
        var sourceCount = 0
        var peakBufferedSourceCount = 0
        /// Exact freshly read source Data held by the batch, excluding parsed
        /// fields, Core memos and allocator overhead; not a process footprint.
        var peakBufferedSourceBytes = 0
    }

    /// Best-effort preparation uses the same registered scope, source reads and
    /// Core projections as foreground retrieval. It publishes no workspace or
    /// result state, and never replaces the foreground's current-source checks.
    @discardableResult
    func prepareRelatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentPreparationMeasurement? {
        try requireActive()
        try Task.checkCancellation()
        guard currentSnapshot.phase.isComplete else { throw ScholiumApplicationError.workspaceStillLoading(id) }
        guard
            currentSnapshot.discovery.catalog.notes.contains(where: {
                $0.reference.vaultID == request.seed.noteID.vaultID && $0.reference.relativePath == request.seed.noteID.relativePath
            })
        else { throw CocoaError(.fileReadNoSuchFile) }
        let captured = currentSnapshot
        let background = RelatedContentRequest(
            id: request.id, seed: .init(noteID: request.seed.noteID, source: request.seed.source),
            candidateRoles: request.candidateRoles)
        let response = try await services.searchIndex.relatedMaterialSourceCandidates(background)
        try requireActive()
        try Task.checkCancellation()
        guard [.current, .empty].contains(response.state),
            case .current(let generation) = response.availability,
            captured.discovery.searchGeneration == generation,
            currentSnapshot.discovery.searchGeneration == generation,
            currentSnapshot.discovery.catalog.notes == captured.discovery.catalog.notes
        else { return nil }
        let preparation = try await services.searchIndex.beginRelatedPassagePreparation(
            background, candidates: response.identityCandidates + response.lexicalCandidates, generation: generation)
        func requireCurrentPreparation() throws {
            try requireActive()
            try Task.checkCancellation()
            guard currentSnapshot.discovery.searchGeneration == generation,
                currentSnapshot.discovery.catalog.notes == captured.discovery.catalog.notes
            else { throw CancellationError() }
        }
        try requireCurrentPreparation()
        var sources: [RelatedContentSource] = []
        sources.reserveCapacity(16)
        var measurement = RelatedContentPreparationMeasurement()
        var bufferedSourceBytes = 0
        var seen = Set<VaultQualifiedNoteID>()
        for candidate in response.identityCandidates + response.lexicalCandidates where seen.insert(candidate.note).inserted {
            try Task.checkCancellation()
            let document: NoteDocument
            do {
                document = try await loadDocument(candidate.note)
            } catch is CancellationError { throw CancellationError() } catch { continue }
            try Task.checkCancellation()
            guard document.fingerprint == candidate.fingerprint,
                document.rawContent.utf16.count <= RelatedContentContract.maximumSeedUTF16Count
            else { continue }
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
        return measurement
    }

    func relatedContent(_ request: RelatedContentRequest) async throws -> RelatedContentResponse {
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
        let canUseGraph =
            !derivedStateRequiresRefresh && pendingSourceCommitRefreshes.isEmpty
            && sourceCommitRefreshTask == nil && pendingLiveEvents.isEmpty && liveIndexRefreshTask == nil
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
                graphResult = try RelatedContentGraphCandidates.build(
                    request: request, graph: graph, searchGeneration: generation, catalog: catalog,
                    linkCatalog: notes.map {
                        LinkCatalogNote(
                            vaultID: $0.id.vaultID, document: $0.document, profile: $0.schemaProfile,
                            semantic: $0.cachedSemanticDocument)
                    }, existingCandidates: response.identityCandidates + response.lexicalCandidates)
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
                let document = try await loadDocument(candidate.note)
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
        let finalAvailability = await services.searchIndex.availability()
        try requireActive()
        try Task.checkCancellation()
        let graphIsCurrent =
            graphResult == nil
            || (currentSnapshot.discovery.catalog.graph?.generation == capturedSnapshot.discovery.catalog.graph?.generation
                && currentSnapshot.discovery.catalog.graph?.sourceManifestHash == generation.sourceManifestHash
                && !derivedStateRequiresRefresh && pendingSourceCommitRefreshes.isEmpty
                && sourceCommitRefreshTask == nil && pendingLiveEvents.isEmpty && liveIndexRefreshTask == nil)
        guard currentSnapshot.phase.isComplete,
            currentSnapshot.discovery.searchGeneration == generation,
            currentSnapshot.discovery.catalog.notes == capturedSnapshot.discovery.catalog.notes,
            finalAvailability == .current(generation), graphIsCurrent
        else {
            // A source read/ranking suspension may straddle refresh. Never publish
            // an old path boost, locator or candidate with a newer generation.
            return RelatedContentResponse(
                requestID: request.id, seedFingerprint: request.seed.fingerprint,
                freshnessToken: finalAvailability.lastGoodGeneration.map(SearchFreshnessToken.triptych) ?? response.freshnessToken,
                availability: finalAvailability, state: .stale,
                identityCandidates: [], lexicalCandidates: [], identityHasMore: false, lexicalHasMore: false)
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

    func search(_ request: SearchRequest) async throws -> SearchResponse {
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
                                    code: .notApplicable,
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
        let response = try await services.searchIndex.search(
            request,
            ast: ast,
            linkMatches: link.matches,
            eligibleDocuments: openingSearchEligibility(for: request)
        )
        return openingVaultSearchResponse(response, request: request)
    }

    func searchCompletions(
        _ request: SearchCompletionRequest
    ) async throws -> SearchCompletionResponse {
        try requireActive()
        let availability = await services.searchIndex.availability()
        let generation = try await services.searchIndex.generation()
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
            terms = try await services.searchIndex.completionTerms(
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
            terms = try await services.searchIndex.completionTerms(
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
                code: .notApplicable,
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
                code: .notApplicable,
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
                    code: .notApplicable,
                    message: "The selected Search vault is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
            if case .opening(let availableSlot) = currentSnapshot.phase,
                assignment.vault(for: availableSlot)?.id != vaultID
            {
                return SearchQueryDiagnostic(
                    code: .notApplicable,
                    message: "Only the currently open vault can be searched while this Triptych finishes opening.",
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
                    code: .notApplicable,
                    message: "The selected Search Note is not part of this Triptych.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )
            }
        }
        return nil
    }

    private func searchDiagnosticResponse(
        request: SearchRequest,
        parsed: SearchQueryParseResult
    ) async -> SearchResponse {
        let noteAvailability = await services.searchIndex.availability()
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
