import Foundation
import ScholiumContracts

/// Application-owned owner access. Providers receive already-authorized
/// closures and cannot discover another Workspace or widen Search scope.
struct ResearchContextOwnerAccess: Sendable {
    let search: @Sendable (SearchRequest) async throws -> SearchResponse
    let loadDocument: @Sendable (VaultQualifiedNoteID) async throws -> NoteDocument
}

protocol ResearchContextProviding: Sendable {
    func response(
        for query: ResearchContextQuery,
        action: ResearchActionSnapshot,
        workspace: WorkspaceSnapshot,
        access: ResearchContextOwnerAccess
    ) async throws -> ResearchContextResponse
}

/// Beta baseline: compose the existing Application Search owner, exact
/// document reads, portable Records, and narrow researcher-owned state. It
/// owns no parser, ranker, index, cache, or writable research state.
struct FoundationResearchContextProvider: ResearchContextProviding {
    func response(
        for query: ResearchContextQuery,
        action: ResearchActionSnapshot,
        workspace: WorkspaceSnapshot,
        access: ResearchContextOwnerAccess
    ) async throws -> ResearchContextResponse {
        guard query.triptychID == workspace.triptych.id else {
            throw ResearchContextContractError.invalidAuthorizedScope
        }
        var items: [ResearchContextResponseItem] = []
        var limitations: [String] = []
        var states: [ResearchContextAvailability] = []

        for sourceKind in query.sourceKinds where items.count < query.limit {
            let remaining = query.limit - items.count
            switch sourceKind {
            case .note:
                let outcome = try await noteItems(
                    query: query,
                    limit: remaining,
                    workspace: workspace,
                    access: access
                )
                if outcome.availability == .invalidQuery {
                    return try ResearchContextResponse(
                        query: query,
                        availability: .invalidQuery,
                        items: [],
                        limitations: outcome.limitations
                    )
                }
                items.append(contentsOf: outcome.items)
                states.append(outcome.availability)
                limitations.append(contentsOf: outcome.limitations)
            case .record:
                let outcome = try await recordItems(
                    query: query,
                    limit: remaining,
                    access: access
                )
                if outcome.availability == .invalidQuery {
                    return try ResearchContextResponse(
                        query: query,
                        availability: .invalidQuery,
                        items: [],
                        limitations: outcome.limitations
                    )
                }
                items.append(contentsOf: outcome.items)
                states.append(outcome.availability)
                limitations.append(contentsOf: outcome.limitations)
            case .researcherState:
                let stateItems = try researcherStateItems(
                    query: query,
                    action: action,
                    workspace: workspace,
                    limit: remaining
                )
                items.append(contentsOf: stateItems)
                states.append(.current)
            case .material:
                states.append(.partial)
                limitations.append(
                    "Source-material bytes remain available only through their existing explicit source capability; this Research Context baseline did not return them."
                )
            }
        }

        if query.sourceKinds.contains(.note), query.sourceKinds.contains(.record) {
            limitations.append(
                "Note and Record results were returned as separate owner channels in request order; they were not co-ranked."
            )
        }
        return try ResearchContextResponse(
            query: query,
            availability: combinedAvailability(states),
            items: Array(items.prefix(query.limit)),
            limitations: unique(limitations)
        )
    }

    private func noteItems(
        query: ResearchContextQuery,
        limit: Int,
        workspace: WorkspaceSnapshot,
        access: ResearchContextOwnerAccess
    ) async throws -> ProviderOutcome {
        let request = SearchRequest(
            id: query.id,
            query: query.query,
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: limit
        )
        let response = try await access.search(request)
        guard response.provider == .note,
              response.hasConsistentProviderIdentity else {
            return ProviderOutcome(
                availability: .invalidQuery,
                items: [],
                limitations: [
                    "The query selected the Record provider while the authorized Research Context channel requested Notes."
                ]
            )
        }
        if !response.diagnostics.isEmpty {
            return ProviderOutcome(
                availability: .invalidQuery,
                items: [],
                limitations: response.diagnostics.map(\.message)
            )
        }
        let availability = contextAvailability(response.availability)
        let currentness = contextCurrentness(availability)
        var items: [ResearchContextResponseItem] = []
        var limitations: [String] = []
        for result in response.results.prefix(limit) {
            guard case .note(let note) = result else {
                throw ResearchContextContractError.invalidResponse
            }
            guard let snapshot = workspace.document(id: note.noteReference),
                  snapshot.fingerprint == note.fingerprint,
                  let stableID = snapshot.stableIdentity.resolvedID else {
                limitations.append(
                    "A matched Note did not have one current Application-owned stable identity and was omitted: \(note.relativePath)."
                )
                continue
            }
            let owner = try ResearchContextOwnerReference.note(
                triptychID: query.triptychID,
                note: note.noteReference,
                stableObjectIdentity: stableID.uuidString.lowercased()
            )
            let readsDocument = query.purposes == [.read]
            let document = readsDocument
                ? try await access.loadDocument(note.noteReference)
                : nil
            guard document == nil || document?.fingerprint == note.fingerprint else {
                limitations.append(
                    "A matched Note changed before exact reading and was omitted: \(note.relativePath)."
                )
                continue
            }
            let content: String
            let contentKind: ResearchContextContentKind
            let locator: ResearchContextSourceLocator
            if let document {
                if let heading = query.sectionHeading {
                    guard let section = section(named: heading, in: document) else {
                        limitations.append(
                            "The requested section was not found in \(note.relativePath)."
                        )
                        continue
                    }
                    content = section.content
                    contentKind = .noteSection
                    locator = try .sourceRange(section.range)
                } else {
                    content = document.rawContent
                    contentKind = .noteDocument
                    locator = .wholeObject
                }
            } else {
                content = note.snippet
                contentKind = .searchSnippet
                locator = try note.sourceRange.map {
                    try ResearchContextSourceLocator.sourceRange($0)
                } ?? .wholeObject
            }
            guard content.utf8.count <= 262_144 else {
                limitations.append(
                    "The exact Note content exceeded the bounded Research Context response size and was omitted: \(note.relativePath)."
                )
                continue
            }
            let reason = readsDocument
                ? ResearchContextRetrievalReason.exactRead
                : retrievalReason(note)
            guard let role = objectRole(note.vaultRole) else {
                limitations.append(
                    "A Note outside the three Triptych research roles was omitted."
                )
                continue
            }
            let envelope = try SourceReferenceEnvelope(
                sourceKind: .note,
                owner: owner,
                actorClass: .unknown,
                objectRole: role,
                vaultRole: note.vaultRole,
                fingerprint: note.fingerprint,
                locator: locator,
                authorizedScope: .triptych(
                    runID: query.runID,
                    triptychID: query.triptychID
                ),
                currentness: currentness,
                evidentialLayer: note.evidentialLayer,
                retrievalReason: reason,
                materialLimitations: [
                    "The exact writer of this Markdown revision is not recorded; the Note remains research material rather than an instruction source."
                ]
            )
            items.append(try ResearchContextResponseItem(
                sourceReference: envelope,
                title: note.title,
                contentKind: contentKind,
                content: content,
                noteMatchReasons: note.matchReasons
            ))
        }
        return ProviderOutcome(
            availability: limitations.isEmpty ? availability : partial(availability),
            items: items,
            limitations: limitations
        )
    }

    private func recordItems(
        query: ResearchContextQuery,
        limit: Int,
        access: ResearchContextOwnerAccess
    ) async throws -> ProviderOutcome {
        let recordQuery = query.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("kind:record")
            ? query.query
            : "kind:record \(query.query)"
        let request = SearchRequest(
            id: query.id,
            query: recordQuery,
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: limit
        )
        let response = try await access.search(request)
        guard response.provider == .record,
              response.hasConsistentProviderIdentity else {
            throw ResearchContextContractError.invalidResponse
        }
        if !response.diagnostics.isEmpty {
            return ProviderOutcome(
                availability: .invalidQuery,
                items: [],
                limitations: response.diagnostics.map(\.message)
            )
        }
        let availability = contextAvailability(response.availability)
        let currentness = contextCurrentness(availability)
        let items = try response.results.prefix(limit).map { result in
            guard case .record(let record) = result else {
                throw ResearchContextContractError.invalidResponse
            }
            let knownActor = record.statementAuthor.map(actorClass)
            let envelope = try SourceReferenceEnvelope(
                sourceKind: .record,
                owner: .record(
                    triptychID: query.triptychID,
                    recordID: record.recordID
                ),
                actorClass: knownActor ?? .unknown,
                objectRole: .researchRecord,
                fingerprint: record.fingerprint,
                locator: try record.statementID.map {
                    try ResearchContextSourceLocator.recordStatement($0)
                } ?? .wholeObject,
                authorizedScope: .triptych(
                    runID: query.runID,
                    triptychID: query.triptychID
                ),
                currentness: currentness,
                evidentialLayer: .researchRecord,
                retrievalReason: .recordSearch,
                materialLimitations: knownActor == nil
                    ? ["The matched Record field has no single statement actor; inspect the attributed Record before relying on it."]
                    : []
            )
            return try ResearchContextResponseItem(
                sourceReference: envelope,
                title: record.context,
                contentKind: .recordStatement,
                content: record.snippet
            )
        }
        return ProviderOutcome(
            availability: availability,
            items: items,
            limitations: []
        )
    }

    private func researcherStateItems(
        query: ResearchContextQuery,
        action: ResearchActionSnapshot,
        workspace: WorkspaceSnapshot,
        limit: Int
    ) throws -> [ResearchContextResponseItem] {
        guard query.purposes.contains(.inspectResearcherState), limit > 0 else {
            return []
        }
        var items: [ResearchContextResponseItem] = []
        if let settlement = workspace.research.settlements
            .filter({ $0.noteID == action.target.noteID })
            .max(by: { $0.settledAt < $1.settledAt }) {
            let isCurrent = settlement.fingerprint == action.target.fingerprint
            let content = [
                "The researcher explicitly settled revision \(settlement.fingerprint.sha256.prefix(12)).",
                settlement.rationale.map { "Rationale: \($0)" },
                "This action records current-use stability, not truth, sufficiency, permanence, or automatic acceptance of later revisions.",
            ].compactMap { $0 }.joined(separator: "\n")
            items.append(try researcherStateItem(
                query: query,
                identity: "settlement:\(settlement.id.uuidString.lowercased())",
                title: "Researcher Settle: \(action.target.title)",
                content: content,
                fingerprint: DocumentFingerprint(content: content),
                currentness: isCurrent ? .current : .stale
            ))
        }
        for record in workspace.research.finishedResearchRecords
            .filter({ record in
                record.researcherEvaluation != nil
                    && record.participatingNotes.contains {
                        $0.noteID == action.target.noteID
                    }
            })
            .sorted(by: { lhs, rhs in
                if lhs.finishedAt != rhs.finishedAt {
                    return lhs.finishedAt > rhs.finishedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }) where items.count < limit {
            guard let evaluation = record.researcherEvaluation,
                  let recordFingerprint = workspace.research
                    .finishedResearchRecordFingerprints[record.id] else {
                continue
            }
            let issues = evaluation.observedIssues.isEmpty
                ? "none selected"
                : evaluation.observedIssues.map(\.rawValue).joined(separator: ", ")
            let content = [
                "The researcher explicitly evaluated this exact Research Record.",
                "Observed issues: \(issues).",
                evaluation.noIssuesObserved
                    ? "No issue was marked within this evaluation's stated scope."
                    : nil,
                evaluation.valuableDiscovery
                    ? "The researcher marked a Valuable Discovery."
                    : nil,
                evaluation.note.map { "Researcher note: \($0)" },
                "This is scoped feedback on one Result. It is not Settlement, adoption, a technical root-cause diagnosis, or philosophical truth.",
            ].compactMap { $0 }.joined(separator: "\n")
            items.append(try researcherStateItem(
                query: query,
                identity: "record:\(record.id.uuidString.lowercased()):evaluation:\(evaluation.revision.uuidString.lowercased())",
                title: "Researcher Evaluation: \(record.action?.actionID.rawValue ?? "research_action")",
                content: content,
                fingerprint: recordFingerprint,
                currentness: .current,
                limitations: [
                    "Evaluation reports the researcher's explicit assessment of this exact Record only; missing evaluation would imply nothing."
                ]
            ))
        }
        for record in workspace.research.finishedResearchRecords
            .filter({ record in
                record.isPinned
                    && record.participatingNotes.contains {
                        $0.noteID == action.target.noteID
                    }
            })
            .sorted(by: { lhs, rhs in
                if lhs.finishedAt != rhs.finishedAt {
                    return lhs.finishedAt > rhs.finishedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }) where items.count < limit {
            guard let recordFingerprint = workspace.research
                .finishedResearchRecordFingerprints[record.id] else {
                continue
            }
            let content = """
            The researcher explicitly pinned this exact Research Record for retention and later attention.
            Pinning does not assert that its Agent claims were adopted, verified, sufficient, or philosophically true.
            """
            items.append(try researcherStateItem(
                query: query,
                identity: "record:\(record.id.uuidString.lowercased()):pin",
                title: "Researcher Retention: \(record.action?.actionID.rawValue ?? "research_action")",
                content: content,
                fingerprint: recordFingerprint,
                currentness: .current,
                limitations: [
                    "Pin records only the researcher's explicit retention action over this Record."
                ]
            ))
        }
        for association in workspace.research.critiques
            .filter({ $0.workNoteID == action.target.noteID })
            .sorted(by: { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }) where items.count < limit {
            for round in association.rounds.sorted(by: { lhs, rhs in
                if lhs.requestedAt != rhs.requestedAt {
                    return lhs.requestedAt > rhs.requestedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }) where items.count < limit {
                let findings = Dictionary(
                    uniqueKeysWithValues: round.actionableFindings.map {
                        ($0.id, $0)
                    }
                )
                for disposition in round.findingDispositions.sorted(by: {
                    if $0.disposedAt != $1.disposedAt {
                        return $0.disposedAt > $1.disposedAt
                    }
                    return $0.findingID < $1.findingID
                }) where items.count < limit {
                    let findingTitle = findings[disposition.findingID]?.title
                        ?? disposition.findingID
                    let decisionText = switch disposition.decision {
                    case .accept: "accepted"
                    case .reject: "rejected"
                    case .rebut: "rebutted"
                    }
                    let content = [
                        "The researcher explicitly \(decisionText) the Critique finding ‘\(findingTitle)’.",
                        disposition.rationale.map { "Rationale: \($0)" },
                        disposition.noTextChangeRationale.map {
                            "No-text-change rationale: \($0)"
                        },
                        disposition.acceptedRevision.map {
                            "Accepted against Work revision \($0.sha256.prefix(12))."
                        },
                        "This records the researcher's disposition of that finding in its exact Critique round; it does not establish philosophical truth or general acceptance of the Work.",
                    ].compactMap { $0 }.joined(separator: "\n")
                    let isCurrent = disposition.acceptedRevision.map {
                        $0 == action.target.fingerprint
                    } ?? (round.targetFingerprint == action.target.fingerprint)
                    items.append(try researcherStateItem(
                        query: query,
                        identity: "critique:\(association.id.uuidString.lowercased()):round:\(round.id.uuidString.lowercased()):finding:\(disposition.findingID)",
                        title: "Critique Disposition: \(findingTitle)",
                        content: content,
                        fingerprint: DocumentFingerprint(content: content),
                        currentness: isCurrent ? .current : .stale,
                        limitations: [
                            "Accept, reject, and rebut name only the explicit researcher action recorded for this source-located Critique finding."
                        ]
                    ))
                }
            }
        }
        for discussion in workspace.research.activeDiscussions
            where discussion.participatingNotes.contains(where: {
                $0.noteID == action.target.noteID
            }) {
            for statement in discussion.statements.reversed()
                where statement.author == .researcher && items.count < limit {
                items.append(try researcherStateItem(
                    query: query,
                    identity: "discussion:\(discussion.id.uuidString.lowercased()):statement:\(statement.id.uuidString.lowercased())",
                    title: statement.attribution,
                    content: statement.text
                        + "\n\nThis is an attributed researcher statement in its Discussion context; quotation, question, hypothesis, or contrast is not automatically a settled position.",
                    fingerprint: DocumentFingerprint(content: statement.text),
                    currentness: .current
                ))
            }
        }
        return Array(items.prefix(limit))
    }

    private func researcherStateItem(
        query: ResearchContextQuery,
        identity: String,
        title: String,
        content: String,
        fingerprint: DocumentFingerprint,
        currentness: ResearchContextCurrentness,
        limitations: [String] = []
    ) throws -> ResearchContextResponseItem {
        let envelope = try SourceReferenceEnvelope(
            sourceKind: .researcherState,
            owner: .researcherState(
                triptychID: query.triptychID,
                stableObjectIdentity: identity
            ),
            actorClass: .researcher,
            objectRole: .researcherState,
            fingerprint: fingerprint,
            locator: .wholeObject,
            authorizedScope: .triptych(
                runID: query.runID,
                triptychID: query.triptychID
            ),
            currentness: currentness,
            evidentialLayer: .researcherState,
            retrievalReason: .researcherState,
            materialLimitations: limitations
        )
        return try ResearchContextResponseItem(
            sourceReference: envelope,
            title: title,
            contentKind: .researcherState,
            content: content
        )
    }

    private func contextAvailability(
        _ availability: SearchProviderAvailability
    ) -> ResearchContextAvailability {
        switch availability {
        case .note(let value):
            switch value {
            case .current: .current
            case .refreshing: .partial
            case .stale: .stale
            case .failed(let lastGood, _): lastGood == nil ? .unavailable : .stale
            case .unavailable, .building: .unavailable
            }
        case .record(let value):
            switch value {
            case .current: .current
            case .refreshing: .partial
            case .stale: .stale
            case .failed(let lastGood, _): lastGood == nil ? .unavailable : .stale
            case .unavailable, .building: .unavailable
            }
        }
    }

    private func contextCurrentness(
        _ availability: ResearchContextAvailability
    ) -> ResearchContextCurrentness {
        switch availability {
        case .current, .partial: .current
        case .stale: .stale
        case .unavailable, .invalidQuery: .unknown
        }
    }

    private func combinedAvailability(
        _ states: [ResearchContextAvailability]
    ) -> ResearchContextAvailability {
        guard !states.isEmpty else { return .unavailable }
        if states.contains(.invalidQuery) { return .invalidQuery }
        if states.allSatisfy({ $0 == .current }) { return .current }
        if states.allSatisfy({ $0 == .unavailable }) { return .unavailable }
        if states.contains(.stale) { return .stale }
        return .partial
    }

    private func partial(
        _ availability: ResearchContextAvailability
    ) -> ResearchContextAvailability {
        availability == .current ? .partial : availability
    }

    private func retrievalReason(
        _ result: NoteSearchResult
    ) -> ResearchContextRetrievalReason {
        switch result.primaryMatchReason {
        case .property: .propertyPresence
        case .relationship: .directRelation
        case .lexical:
            result.matchedField == .summary ? .canonicalSummary : .lexical
        }
    }

    private func objectRole(_ role: VaultRole) -> ResearchContextObjectRole? {
        switch role {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topic
        case .draftProject: .work
        case .other: nil
        }
    }

    private func actorClass(
        _ author: PortableResearchStatementAuthor
    ) -> ResearchContextActorClass {
        switch author {
        case .researcher: .researcher
        case .agent: .agent
        }
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func section(named requested: String, in document: NoteDocument) -> Section? {
        let source = document.rawContent
        let semantic = MarkdownSemanticDocument(parsing: document)
        let normalized = normalizeHeading(requested)
        guard let index = semantic.headings.firstIndex(where: {
            normalizeHeading($0.text) == normalized
        }) else { return nil }
        let heading = semantic.headings[index]
        let nextHeading = semantic.headings.dropFirst(index + 1).first(where: {
            $0.level <= heading.level
        })
        let end = nextHeading?.span.start ?? SourcePosition(
            line: source.split(separator: "\n", omittingEmptySubsequences: false).count,
            utf8Column: 1,
            utf16Column: 1
        )
        let lower = heading.span.utf8LowerBound
        let upper = nextHeading?.span.utf8LowerBound ?? source.utf8.count
        guard lower >= 0, upper >= lower, upper <= source.utf8.count else { return nil }
        let bytes = Data(source.utf8)[lower..<upper]
        let range = SearchSourceRange(
            utf16LowerBound: heading.span.utf16LowerBound,
            utf16UpperBound: nextHeading?.span.utf16LowerBound ?? source.utf16.count,
            line: heading.span.start.line,
            column: heading.span.start.utf16Column,
            endLine: end.line,
            endColumn: end.utf16Column
        )
        return Section(content: String(decoding: bytes, as: UTF8.self), range: range)
    }

    private func normalizeHeading(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private struct ProviderOutcome {
        let availability: ResearchContextAvailability
        let items: [ResearchContextResponseItem]
        let limitations: [String]
    }

    private struct Section {
        let content: String
        let range: SearchSourceRange
    }
}
