import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

struct RelatedContentRetrievalMeasurement: Sendable {
    let candidateCount: Int
    let indexDuration: Duration
    let readDuration: Duration
    let passageDuration: Duration
}

extension WorkspaceHandle {
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
        lastRelatedContentMeasurement = RelatedContentRetrievalMeasurement(
            candidateCount: seen.count, indexDuration: started.duration(to: indexed),
            readDuration: indexed.duration(to: read), passageDuration: read.duration(to: .now))
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
