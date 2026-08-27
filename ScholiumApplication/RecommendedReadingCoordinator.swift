import Foundation
import ScholiumContracts

/// Application policy for Agent Recommended Reading. Search owns identity and
/// lexical retrieval; Graph owns direct Connections. This coordinator owns
/// Action eligibility, fixed channel precedence, deduplication, and the
/// delivery-neutral Agent directory shape.
struct RecommendedReadingCoordinator: Sendable {
    typealias Retrieve = @Sendable (
        RelatedContentRequest
    ) async throws -> RelatedContentResponse

    private struct DirectChannel {
        let isAvailable: Bool
        let candidates: [ResearchRecommendedReadingCandidate]
        let hasMore: Bool
    }

    private let retrieve: Retrieve

    init(retrieve: @escaping Retrieve) {
        self.retrieve = retrieve
    }

    func directory(
        for action: ResearchActionSnapshot,
        request: ResearchActionRunRequest,
        source: NoteDocument,
        workspace: WorkspaceSnapshot,
        requestID: UUID
    ) async throws -> ResearchRecommendedReadingDirectory? {
        guard let candidateRoles = Self.initialCandidateRoles(for: action) else {
            return nil
        }
        let focuses = Self.focuses(
            action: action,
            scope: request.scope,
            sourceFingerprint: source.fingerprint
        )
        return try await directory(
            target: action.target.note,
            source: source,
            focuses: focuses,
            selection: request.scope?.selection,
            candidateRoles: candidateRoles,
            workspace: workspace,
            requestID: requestID
        )
    }

    func relatedNotes(
        named noteNames: [String],
        limit: Int,
        workspace: WorkspaceSnapshot,
        requestID: UUID
    ) async throws -> ResearchRelatedNotesResult {
        let resolution = try Self.resolveSeeds(
            named: noteNames,
            workspace: workspace
        )
        guard !resolution.seeds.isEmpty else {
            return try ResearchRelatedNotesResult(
                state: .invalidSeed,
                resolvedSeeds: [],
                unresolvedNames: resolution.unresolved,
                candidates: [],
                hasMore: false,
                limitation: "No supplied Note name resolved to one exact current Triptych Note. Use an exact title, alias, relative path, filename, or stable Note identity."
            )
        }

        struct Accumulator {
            let candidate: ResearchRecommendedReadingCandidate
            var matches: [ResearchRelatedNotesSeedMatch]
            var bestTier: Int
            var directCount: Int
            var identityCount: Int
            var rankTotal: Int
        }

        let seedNotes = Set(resolution.seeds.map(\.note))
        var accumulators: [VaultQualifiedNoteID: Accumulator] = [:]
        var states: [RelatedContentResultState] = []
        var sourceHasMore = false
        for (seedIndex, seed) in resolution.seeds.enumerated() {
            guard let snapshot = workspace.document(id: seed.note),
                  snapshot.fingerprint == seed.fingerprint else {
                states.append(.stale)
                continue
            }
            let directory = try await directory(
                target: seed.note,
                source: snapshot.document,
                focuses: [],
                selection: nil,
                candidateRoles: RelatedContentCandidateRole.allCases,
                workspace: workspace,
                requestID: Self.relatedRequestID(
                    requestID,
                    seedIndex: seedIndex
                )
            )
            states.append(directory.state)
            sourceHasMore = sourceHasMore || directory.hasMore
            for (rank, candidate) in directory.candidates.enumerated()
                where !seedNotes.contains(candidate.note) {
                let match = try ResearchRelatedNotesSeedMatch(
                    seed: seed,
                    reasons: candidate.reasons
                )
                let tier = Self.bestTier(in: candidate.reasons)
                let directCount = candidate.reasons.filter {
                    if case .directConnection = $0 { return true }
                    return false
                }.count
                let identityCount = candidate.reasons.filter {
                    if case .identityMention = $0 { return true }
                    return false
                }.count
                if var current = accumulators[candidate.note] {
                    guard current.candidate.role == candidate.role,
                          current.candidate.title == candidate.title,
                          current.candidate.fingerprint == candidate.fingerprint else {
                        throw ResearchAgentConnectionContractError.invalidHandoff
                    }
                    current.matches.append(match)
                    current.bestTier = min(current.bestTier, tier)
                    current.directCount += directCount
                    current.identityCount += identityCount
                    current.rankTotal += rank
                    accumulators[candidate.note] = current
                } else {
                    accumulators[candidate.note] = Accumulator(
                        candidate: candidate,
                        matches: [match],
                        bestTier: tier,
                        directCount: directCount,
                        identityCount: identityCount,
                        rankTotal: rank
                    )
                }
            }
        }

        let ordered = accumulators.values.sorted { lhs, rhs in
            if lhs.matches.count != rhs.matches.count {
                return lhs.matches.count > rhs.matches.count
            }
            if lhs.bestTier != rhs.bestTier { return lhs.bestTier < rhs.bestTier }
            if lhs.directCount != rhs.directCount {
                return lhs.directCount > rhs.directCount
            }
            if lhs.identityCount != rhs.identityCount {
                return lhs.identityCount > rhs.identityCount
            }
            if lhs.rankTotal != rhs.rankTotal { return lhs.rankTotal < rhs.rankTotal }
            if lhs.candidate.title != rhs.candidate.title {
                return lhs.candidate.title < rhs.candidate.title
            }
            if lhs.candidate.role != rhs.candidate.role {
                return lhs.candidate.role.rawValue < rhs.candidate.role.rawValue
            }
            return lhs.candidate.note < rhs.candidate.note
        }
        let boundedLimit = min(max(1, limit), RelatedContentContract.maximumCandidates)
        let candidates = try ordered.prefix(boundedLimit).map { item in
            try ResearchRelatedNotesCandidate(
                note: item.candidate.note,
                role: item.candidate.role,
                title: item.candidate.title,
                fingerprint: item.candidate.fingerprint,
                matches: item.matches
            )
        }
        let hasMore = sourceHasMore || ordered.count > boundedLimit
        let allCurrent = states.allSatisfy { $0 == .current || $0 == .empty }
        let state: RelatedContentResultState
        if allCurrent && resolution.unresolved.isEmpty {
            if candidates.isEmpty {
                state = hasMore ? .partial : .empty
            } else {
                state = .current
            }
        } else if !candidates.isEmpty || !resolution.seeds.isEmpty {
            state = .partial
        } else {
            state = .unavailable
        }
        let limitation: String? = state == .partial
            ? "Some supplied Note names or retrieval channels were unavailable. Results are dynamically ranked only from exact current seeds that resolved successfully."
            : (state == .unavailable
                ? "Related Notes are unavailable for the resolved seeds."
                : nil)
        return try ResearchRelatedNotesResult(
            state: state,
            resolvedSeeds: resolution.seeds,
            unresolvedNames: resolution.unresolved,
            candidates: candidates,
            hasMore: hasMore,
            limitation: limitation
        )
    }

    private func directory(
        target: VaultQualifiedNoteID,
        source: NoteDocument,
        focuses: [RelatedContentSeedFocus],
        selection: CommentAnchor?,
        candidateRoles: [RelatedContentCandidateRole],
        workspace: WorkspaceSnapshot,
        requestID: UUID
    ) async throws -> ResearchRecommendedReadingDirectory {
        let seed = RelatedContentSeedSnapshot(
            noteID: target,
            source: source.rawContent,
            focuses: focuses,
            metadata: workspace.document(id: target)?.metadata,
            metadataCatalog: workspace.metadataCatalog
        )
        let direct = try directChannel(
            target: target,
            selection: selection,
            sourceFingerprint: source.fingerprint,
            candidateRoles: candidateRoles,
            catalog: workspace.discovery.catalog,
            searchGeneration: workspace.discovery.searchGeneration
        )
        do {
            let response = try await retrieve(RelatedContentRequest(
                id: requestID,
                seed: seed,
                candidateRoles: candidateRoles
            ))
            let identity = try response.identityCandidates.map(
                Self.agentCandidate
            )
            let lexical = try response.lexicalCandidates.map(
                Self.agentCandidate
            )
            let merged = try Self.merge(
                channels: [direct.candidates, identity, lexical]
            )
            let searchAvailable = response.state == .current
                || response.state == .empty
            let allChannelsAvailable = direct.isAvailable && searchAvailable
            let state: RelatedContentResultState
            if allChannelsAvailable {
                state = merged.candidates.isEmpty ? .empty : .current
            } else if direct.isAvailable || searchAvailable
                || !merged.candidates.isEmpty {
                state = .partial
            } else {
                state = response.state
            }
            let limitation = Self.limitation(
                state: state,
                directAvailable: direct.isAvailable,
                searchState: response.state
            )
            return try ResearchRecommendedReadingDirectory(
                retrievalContractVersion: response.contractVersion,
                rankingPolicyVersion: response.rankingPolicyVersion,
                seedFingerprint: response.seedFingerprint,
                freshnessToken: response.freshnessToken,
                state: state,
                candidates: merged.candidates,
                hasMore: direct.hasMore || response.identityHasMore
                    || response.lexicalHasMore || merged.didTruncate,
                limitation: limitation
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if direct.isAvailable {
                return try ResearchRecommendedReadingDirectory(
                    seedFingerprint: seed.fingerprint,
                    freshnessToken: SearchFreshnessToken(
                        "related-content:unavailable"
                    ),
                    state: .partial,
                    candidates: direct.candidates,
                    hasMore: direct.hasMore,
                    limitation: "Identity and lexical Recommended Reading are unavailable. Current direct Connections remain available; the Agent can also use bounded Search."
                )
            }
            return try ResearchRecommendedReadingDirectory(
                seedFingerprint: seed.fingerprint,
                freshnessToken: SearchFreshnessToken(
                    "related-content:unavailable"
                ),
                state: .unavailable,
                candidates: [],
                hasMore: false,
                limitation: "Recommended Reading is unavailable. The Agent can still use the current bounded Search action."
            )
        }
    }

    private static func initialCandidateRoles(
        for action: ResearchActionSnapshot
    ) -> [RelatedContentCandidateRole]? {
        if action.target.role == .work,
           action.actionID == .write || action.actionID == .critique {
            return RelatedContentCandidateRole.allCases
        }
        if action.target.role == .topic, action.actionID == .synthesize {
            return [.analysis]
        }
        return nil
    }

    private struct SeedResolution {
        let seeds: [ResearchRelatedNotesResolvedSeed]
        let unresolved: [String]
    }

    private static func resolveSeeds(
        named noteNames: [String],
        workspace: WorkspaceSnapshot
    ) throws -> SeedResolution {
        var seeds: [ResearchRelatedNotesResolvedSeed] = []
        var unresolved: [String] = []
        var seenNotes = Set<VaultQualifiedNoteID>()
        for name in noteNames {
            let normalized = SearchTextNormalization.normalize(name)
            let matches = workspace.discovery.catalog.notes.filter { note in
                Self.catalogIdentities(note).contains {
                    SearchTextNormalization.normalize($0) == normalized
                }
            }
            guard matches.count == 1, let match = matches.first else {
                unresolved.append(name)
                continue
            }
            let note = VaultQualifiedNoteID(
                vaultID: match.reference.vaultID,
                relativePath: match.reference.relativePath
            )
            guard seenNotes.insert(note).inserted,
                  let role = ResearchActionTargetRole(
                    vaultRole: match.reference.vaultRole
                  ) else {
                unresolved.append(name)
                continue
            }
            seeds.append(try ResearchRelatedNotesResolvedSeed(
                inputName: name,
                note: note,
                role: role,
                title: match.title,
                fingerprint: match.fingerprint
            ))
        }
        return SeedResolution(seeds: seeds, unresolved: unresolved)
    }

    private static func catalogIdentities(
        _ note: WorkspaceCatalogNote
    ) -> [String] {
        let basename = ((note.reference.relativePath as NSString)
            .lastPathComponent as NSString).deletingPathExtension
        return [
            note.reference.stableNoteID,
            note.reference.relativePath,
            basename,
            note.title,
        ].compactMap { $0 } + note.aliases
    }

    private static func relatedRequestID(
        _ requestID: UUID,
        seedIndex: Int
    ) -> UUID {
        let fingerprint = DocumentFingerprint(
            content: requestID.uuidString.lowercased()
                + "\u{001F}related-note-seed:\(seedIndex)"
        ).sha256
        return UUID(uuidString: [
            String(fingerprint.prefix(8)),
            String(fingerprint.dropFirst(8).prefix(4)),
            String(fingerprint.dropFirst(12).prefix(4)),
            String(fingerprint.dropFirst(16).prefix(4)),
            String(fingerprint.dropFirst(20).prefix(12)),
        ].joined(separator: "-"))!
    }

    private static func bestTier(
        in reasons: [ResearchRecommendedReadingReason]
    ) -> Int {
        reasons.map { reason in
            switch reason {
            case .directConnection: 0
            case .identityMention: 1
            case .lexicalOverlap: 2
            }
        }.min() ?? Int.max
    }

    private static func focuses(
        action: ResearchActionSnapshot,
        scope: ResearchActionScope?,
        sourceFingerprint: DocumentFingerprint
    ) -> [RelatedContentSeedFocus] {
        var result: [RelatedContentSeedFocus] = []
        if let selection = scope?.selection,
           selection.state == .attached,
           selection.fingerprint == sourceFingerprint {
            let text = selection.selectedText?.isEmpty == false
                ? selection.selectedText!
                : selection.quotation
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(RelatedContentSeedFocus(
                    kind: .selectedPassage,
                    text: text
                ))
            }
        }
        if case .freeText(let text)? =
            action.academicInputs.values["research-request"],
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(RelatedContentSeedFocus(
                kind: .researchRequest,
                text: text
            ))
        }
        return result
    }

    private func directChannel(
        target seedNote: VaultQualifiedNoteID,
        selection: CommentAnchor?,
        sourceFingerprint: DocumentFingerprint,
        candidateRoles: [RelatedContentCandidateRole],
        catalog: WorkspaceCatalogSnapshot,
        searchGeneration: SearchGenerationID?
    ) throws -> DirectChannel {
        guard let graph = catalog.graph,
              let searchGeneration,
              graph.sourceManifestHash == searchGeneration.sourceManifestHash
        else {
            return DirectChannel(
                isAvailable: false,
                candidates: [],
                hasMore: false
            )
        }
        let notes = Dictionary(uniqueKeysWithValues: catalog.notes.map {
            (VaultQualifiedNoteID(
                vaultID: $0.reference.vaultID,
                relativePath: $0.reference.relativePath
            ), $0)
        })
        var reasonsByNote: [
            VaultQualifiedNoteID: [ResearchRecommendedReadingConnectionReason]
        ] = [:]
        let allowedVaultRoles = Set(candidateRoles.map(\.vaultRole))
        for edge in graph.outgoing[seedNote] ?? []
            where edge.occurrence.syntax != .embed {
            guard let candidate = edge.destination?.note,
                  candidate != seedNote,
                  let candidateNote = notes[candidate],
                  allowedVaultRoles.contains(candidateNote.reference.vaultRole)
            else { continue }
            reasonsByNote[candidate, default: []].append(
                try Self.connectionReason(
                    edge: edge,
                    target: seedNote,
                    direction: Self.direction(for: edge, outgoing: true),
                    selection: selection,
                    sourceFingerprint: sourceFingerprint
                )
            )
        }
        for edge in graph.incoming[seedNote] ?? []
            where edge.occurrence.syntax != .embed {
            let candidate = edge.source
            guard candidate != seedNote,
                  let candidateNote = notes[candidate],
                  allowedVaultRoles.contains(candidateNote.reference.vaultRole)
            else { continue }
            reasonsByNote[candidate, default: []].append(
                try Self.connectionReason(
                    edge: edge,
                    target: seedNote,
                    direction: Self.direction(for: edge, outgoing: false),
                    selection: selection,
                    sourceFingerprint: sourceFingerprint
                )
            )
        }

        let candidates = try reasonsByNote.compactMap {
            note, reasons -> ResearchRecommendedReadingCandidate? in
            guard let catalogNote = notes[note],
                  let role = ResearchActionTargetRole(
                    vaultRole: catalogNote.reference.vaultRole
                  ) else { return nil }
            return try ResearchRecommendedReadingCandidate(
                note: note,
                role: role,
                title: catalogNote.title,
                fingerprint: catalogNote.fingerprint,
                reasons: reasons.map(
                    ResearchRecommendedReadingReason.directConnection
                )
            )
        }.sorted(by: Self.directCandidatePrecedes)
        return DirectChannel(
            isAvailable: true,
            candidates: Array(candidates.prefix(
                RelatedContentContract.maximumDirectConnectionCandidates
            )),
            hasMore: candidates.count
                > RelatedContentContract.maximumDirectConnectionCandidates
        )
    }

    private static func connectionReason(
        edge: LinkGraphEdge,
        target: VaultQualifiedNoteID,
        direction: ResearchRecommendedReadingConnectionDirection,
        selection: CommentAnchor?,
        sourceFingerprint: DocumentFingerprint
    ) throws -> ResearchRecommendedReadingConnectionReason {
        let span = edge.occurrence.span
        let insideSelectedPassage = edge.source == target
            && selection?.fingerprint == sourceFingerprint
            && selection?.state == .attached
            && selection?.utf16Range.overlaps(span.utf16Range) == true
        return try ResearchRecommendedReadingConnectionReason(
            direction: direction,
            predicate: Self.predicate(for: edge.occurrence.vectorKind),
            sourceNote: edge.source,
            locator: SourceLocator(
                file: edge.source.relativePath,
                line: span.start.line,
                column: span.start.utf16Column,
                headingOrBlock: edge.occurrence.fragment
            ),
            vectorKind: edge.occurrence.vectorKind,
            insideSelectedPassage: insideSelectedPassage
        )
    }

    private static func direction(
        for edge: LinkGraphEdge,
        outgoing: Bool
    ) -> ResearchRecommendedReadingConnectionDirection {
        switch edge.occurrence.vectorKind {
        case nil, .neutral, .incompatible:
            .undirected
        case .supports, .opposes:
            outgoing ? .fromTarget : .toTarget
        }
    }

    private static func predicate(
        for kind: VectorLinkKind?
    ) -> RelationshipPredicate {
        switch kind {
        case nil, .neutral: .connected
        case .supports: .supports
        case .opposes: .opposes
        case .incompatible: .incompatibleWith
        }
    }

    private static func directCandidatePrecedes(
        _ lhs: ResearchRecommendedReadingCandidate,
        _ rhs: ResearchRecommendedReadingCandidate
    ) -> Bool {
        let leftFocused = lhs.reasons.contains { reason in
            guard case .directConnection(let value) = reason else { return false }
            return value.insideSelectedPassage
        }
        let rightFocused = rhs.reasons.contains { reason in
            guard case .directConnection(let value) = reason else { return false }
            return value.insideSelectedPassage
        }
        if leftFocused != rightFocused { return leftFocused }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        if lhs.role != rhs.role { return lhs.role.rawValue < rhs.role.rawValue }
        return lhs.note < rhs.note
    }

    private static func agentCandidate(
        _ candidate: RelatedContentCandidate
    ) throws -> ResearchRecommendedReadingCandidate {
        guard let role = ResearchActionTargetRole(
            vaultRole: candidate.vaultRole
        ), role == .analysis || role == .topic else {
            throw ResearchAgentConnectionContractError.invalidHandoff
        }
        let reason: ResearchRecommendedReadingReason = switch candidate.reason {
        case .identityMention(let value): .identityMention(value)
        case .lexicalOverlap(let value): .lexicalOverlap(value)
        }
        return try ResearchRecommendedReadingCandidate(
            note: candidate.note,
            role: role,
            title: candidate.title,
            fingerprint: candidate.fingerprint,
            reasons: [reason]
        )
    }

    private static func merge(
        channels: [[ResearchRecommendedReadingCandidate]]
    ) throws -> (
        candidates: [ResearchRecommendedReadingCandidate],
        didTruncate: Bool
    ) {
        var candidates: [ResearchRecommendedReadingCandidate] = []
        var indexByNote: [VaultQualifiedNoteID: Int] = [:]
        var didTruncate = false
        for channel in channels {
            for candidate in channel {
                if let index = indexByNote[candidate.note] {
                    let current = candidates[index]
                    guard current.role == candidate.role,
                          current.title == candidate.title,
                          current.fingerprint == candidate.fingerprint else {
                        throw ResearchAgentConnectionContractError.invalidHandoff
                    }
                    candidates[index] = try ResearchRecommendedReadingCandidate(
                        note: current.note,
                        role: current.role,
                        title: current.title,
                        fingerprint: current.fingerprint,
                        reasons: current.reasons + candidate.reasons.filter {
                            !current.reasons.contains($0)
                        }
                    )
                } else if candidates.count
                    < RelatedContentContract.maximumCandidates {
                    indexByNote[candidate.note] = candidates.count
                    candidates.append(candidate)
                } else {
                    didTruncate = true
                }
            }
        }
        return (candidates, didTruncate)
    }

    private static func limitation(
        state: RelatedContentResultState,
        directAvailable: Bool,
        searchState: RelatedContentResultState
    ) -> String? {
        guard state == .partial || state == .stale
            || state == .unavailable || state == .invalidSeed else { return nil }
        var limitations: [String] = []
        if !directAvailable {
            limitations.append(
                "Direct Connections are unavailable until Graph and Search share one complete source generation."
            )
        }
        switch searchState {
        case .current, .empty:
            break
        case .partial:
            limitations.append("Identity or lexical retrieval is partial.")
        case .stale:
            limitations.append("Identity and lexical retrieval has no current Search generation.")
        case .unavailable:
            limitations.append("Identity and lexical retrieval is unavailable.")
        case .invalidSeed:
            limitations.append("The frozen Work task does not provide a valid bounded retrieval seed.")
        }
        limitations.append("The Agent can still use bounded Search.")
        return limitations.joined(separator: " ")
    }
}
