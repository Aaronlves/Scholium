import Foundation
import ScholiumContracts

/// Request-local walks over actual directed authored occurrences. The lookup
/// supports reverse traversal without adding or persisting reverse edges.
enum RelatedContentGraphCandidates {
    struct Result: Sendable {
        let contexts: [VaultQualifiedNoteID: RelatedContentGraphContext]
        let candidates: [RelatedContentCandidate]
        let hasMore: Bool
    }

    private struct Neighbor {
        let note: VaultQualifiedNoteID
        let step: RelatedContentGraphStep
    }

    static func build(
        request: RelatedContentRequest, graph: GraphSnapshot,
        searchGeneration: SearchGenerationID, catalog: [WorkspaceCatalogNote],
        linkCatalog: [LinkCatalogNote], existingCandidates: [RelatedContentCandidate]
    ) throws -> Result? {
        let manifest = SearchSourceManifest.hash(
            catalog.map {
                SearchSourceManifestEntry(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath, fingerprint: $0.fingerprint)
            })
        guard graph.contractVersion == GraphSnapshot.currentContractVersion,
            !manifest.isEmpty, graph.sourceManifestHash == manifest,
            searchGeneration.sourceManifestHash == manifest
        else { return nil }
        let notes = Dictionary(
            catalog.map {
                (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0)
            }, uniquingKeysWith: { first, _ in first })
        let roles: Set<VaultRole> = [.sourceCorpus, .topicKnowledge, .draftProject]
        let authorized = Set(notes.filter { roles.contains($0.value.reference.vaultRole) }.keys)
        let seed = request.seed.noteID
        guard authorized.contains(seed), Set(linkCatalog.map(\.id)) == Set(notes.keys) else { return nil }
        try Task.checkCancellation()
        let seedDocument = NoteDocument(relativePath: seed.relativePath, rawContent: request.seed.source)
        let seedSemantic = MarkdownSemanticDocument(parsing: seedDocument)
        let seedCatalog = LinkCatalogNote(vaultID: seed.vaultID, document: seedDocument, semantic: seedSemantic)
        let overlay = try LinkGraphBuilder.buildCancellable(
            generation: graph.generation,
            catalog: linkCatalog.map { $0.id == seed ? seedCatalog : $0 },
            documents: [seed: seedSemantic], resolutionScope: .workspace)

        var outgoing = graph.outgoing
        outgoing[seed] = overlay.outgoing[seed] ?? []
        var neighbors: [VaultQualifiedNoteID: [VaultQualifiedNoteID: Neighbor]] = [:]
        var examined = 0
        // Outgoing is the occurrence authority; incoming is only its reverse
        // projection. Rebuilding the walk lookup also removes saved-seed links
        // from reverse traversal when an unsaved edit replaces them.
        for source in outgoing.keys.sorted() where authorized.contains(source) {
            for edge in (outgoing[source] ?? []).sorted(by: edgeOrder) {
                examined += 1
                if examined.isMultiple(of: 256) { try Task.checkCancellation() }
                guard edge.source == source, !edge.occurrence.isExternal,
                    let destination = edge.destination?.note, authorized.contains(destination), destination != source,
                    case .resolved(let resolved) = edge.occurrence.resolution, resolved == destination
                else { continue }
                // Reciprocal and repeated occurrences share one neighbor pair.
                // Stable source/locator order chooses the actual representative.
                guard neighbors[source]?[destination] == nil else { continue }
                neighbors[source, default: [:]][destination] = .init(
                    note: destination, step: .init(source: source, destination: destination, occurrence: edge.occurrence, traversal: .outgoing))
                neighbors[destination, default: [:]][source] = .init(
                    note: source, step: .init(source: source, destination: destination, occurrence: edge.occurrence, traversal: .incoming))
            }
        }
        let seedNeighbors = neighbors[seed] ?? [:]
        let limit = RelatedContentContract.maximumGraphNeighbors
        var expanded = Set<VaultQualifiedNoteID>()
        var truncated = seedNeighbors.count > limit
        for intermediate in seedNeighbors.keys.sorted().prefix(limit) {
            expanded.insert(intermediate)
            let next = neighbors[intermediate] ?? [:]
            truncated = truncated || next.count > limit
            expanded.formUnion(next.keys.sorted().prefix(limit))
        }
        expanded.remove(seed)
        let existing = Set(existingCandidates.map(\.note))
        // Existing lexical/identity sources are already eligible for reads. Their
        // direct lookup/common-neighbor intersection is independent of graph-only
        // expansion bounds, so 12 extra sources never truncate their context.
        let targets = expanded.union(existing).filter { target in
            target != seed && authorized.contains(target)
                && notes[target].map { note in request.candidateRoles.contains { $0.vaultRole == note.reference.vaultRole } } == true
        }
        var contexts: [VaultQualifiedNoteID: RelatedContentGraphContext] = [:]
        for target in targets.sorted() {
            try Task.checkCancellation()
            var paths: [(weight: Double, intermediate: VaultQualifiedNoteID?, path: RelatedContentGraphPath)] = []
            if let direct = seedNeighbors[target] {
                paths.append((1, nil, .init(steps: [direct.step])))
            }
            let targetNeighbors = neighbors[target] ?? [:]
            var proximity = seedNeighbors[target] == nil ? 0.0 : 1.0
            let smaller = seedNeighbors.count <= targetNeighbors.count ? seedNeighbors : targetNeighbors
            let other = seedNeighbors.count <= targetNeighbors.count ? targetNeighbors : seedNeighbors
            var considered = 0
            for intermediate in smaller.keys.sorted() {
                considered += 1
                if considered.isMultiple(of: 256) { try Task.checkCancellation() }
                guard other[intermediate] != nil, intermediate != seed, intermediate != target,
                    let first = seedNeighbors[intermediate], let second = neighbors[intermediate]?[target]
                else { continue }
                // Degree is complete, distinct and access-filtered; truncating
                // expansion must not make a hub look artificially selective.
                let contribution = 0.5 / Double(max(2, neighbors[intermediate]?.count ?? 0))
                proximity += contribution
                // Keep only the strongest explanatory paths while summing every
                // distinct intermediary. A dense intersection never allocates an
                // unbounded list of two-step paths just to discard it afterward.
                let insertion =
                    paths.firstIndex { existing in
                        if contribution != existing.weight { return contribution > existing.weight }
                        guard let existingIntermediate = existing.intermediate else { return false }
                        return intermediate < existingIntermediate
                    } ?? paths.count
                if insertion < RelatedContentContract.maximumGraphPathsPerCandidate {
                    paths.insert((contribution, intermediate, .init(steps: [first.step, second.step])), at: insertion)
                    if paths.count > RelatedContentContract.maximumGraphPathsPerCandidate { paths.removeLast() }
                }
            }
            guard !paths.isEmpty else { continue }
            contexts[target] = .init(
                paths: paths.map(\.path),
                proximity: min(1, proximity))
        }
        let candidates = expanded.compactMap { target -> RelatedContentCandidate? in
            guard !existing.contains(target), let note = notes[target], let context = contexts[target] else { return nil }
            return .init(
                note: target, vaultRole: note.reference.vaultRole, title: note.title,
                fingerprint: note.fingerprint, reason: .graphConnection(context), graphContext: context)
        }.sorted { lhs, rhs in
            let left = lhs.graphContext?.proximity ?? 0
            let right = rhs.graphContext?.proximity ?? 0
            if left != right { return left > right }
            return lhs.note < rhs.note
        }
        return .init(
            contexts: contexts,
            candidates: Array(candidates.prefix(RelatedContentContract.maximumGraphCandidates)),
            hasMore: truncated || candidates.count > RelatedContentContract.maximumGraphCandidates)
    }

    static func attaching(_ context: RelatedContentGraphContext?, to candidate: RelatedContentCandidate) -> RelatedContentCandidate {
        .init(
            note: candidate.note, vaultRole: candidate.vaultRole, title: candidate.title,
            fingerprint: candidate.fingerprint, reason: candidate.reason, graphContext: context)
    }

    private static func edgeOrder(_ lhs: LinkGraphEdge, _ rhs: LinkGraphEdge) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if lhs.destination?.note != rhs.destination?.note {
            guard let left = lhs.destination?.note else { return true }
            guard let right = rhs.destination?.note else { return false }
            return left < right
        }
        if lhs.occurrence.span.utf16LowerBound != rhs.occurrence.span.utf16LowerBound {
            return lhs.occurrence.span.utf16LowerBound < rhs.occurrence.span.utf16LowerBound
        }
        return lhs.occurrence.span.utf16UpperBound < rhs.occurrence.span.utf16UpperBound
    }
}
