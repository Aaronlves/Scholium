import Foundation

public struct WorkspaceReviewState: Codable, Hashable, Sendable {
    public let qualification: String?
    public let reviewedFingerprint: DocumentFingerprint?
    public let changedSinceReview: Bool

    public init(
        qualification: String? = nil,
        reviewedFingerprint: DocumentFingerprint? = nil,
        changedSinceReview: Bool = false
    ) {
        self.qualification = qualification
        self.reviewedFingerprint = reviewedFingerprint
        self.changedSinceReview = changedSinceReview
    }
}

public struct WorkspaceCatalogNote: Codable, Hashable, Identifiable, Sendable {
    public var id: String { reference.id }
    public let reference: VaultNoteReference
    public let title: String
    public let aliases: [String]
    public let zoteroItemKey: String?
    public let zoteroSourceIdentity: ZoteroSourceIdentity?
    public let fingerprint: DocumentFingerprint
    public let validationWarnings: [String]

    public init(
        reference: VaultNoteReference,
        title: String,
        aliases: [String] = [],
        zoteroItemKey: String?,
        zoteroSourceIdentity: ZoteroSourceIdentity?,
        fingerprint: DocumentFingerprint,
        validationWarnings: [String]
    ) {
        self.reference = reference
        self.title = title
        self.aliases = aliases
        self.zoteroItemKey = zoteroItemKey
        self.zoteroSourceIdentity = zoteroSourceIdentity
        self.fingerprint = fingerprint
        self.validationWarnings = validationWarnings
    }

    private enum CodingKeys: String, CodingKey {
        case reference, title, aliases, zoteroItemKey, zoteroSourceIdentity
        case fingerprint, validationWarnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(VaultNoteReference.self, forKey: .reference)
        title = try container.decode(String.self, forKey: .title)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        zoteroItemKey = try container.decodeIfPresent(String.self, forKey: .zoteroItemKey)
        zoteroSourceIdentity = try container.decodeIfPresent(
            ZoteroSourceIdentity.self,
            forKey: .zoteroSourceIdentity
        )
        fingerprint = try container.decode(DocumentFingerprint.self, forKey: .fingerprint)
        validationWarnings = try container.decode([String].self, forKey: .validationWarnings)
    }
}

/// A direct, resolved graph connection shown separately from lexical Search.
///
/// Related items never participate in FTS ranking and never imply evidential
/// sufficiency. The relationship is stated relative to the uniquely resolved
/// Topic that matched the query.
public struct RelatedSearchItem: Hashable, Identifiable, Sendable {
    public enum Relationship: String, Hashable, Sendable {
        case conceptLinksToItem = "concept_links_to_item"
        case itemLinksToConcept = "item_links_to_concept"
        case conceptSupportsItem = "concept_supports_item"
        case itemSupportsConcept = "item_supports_concept"
        case incompatible
    }

    public var id: String {
        "\(concept.id):\(note.id):\(relationship.rawValue)"
    }

    public let note: WorkspaceCatalogNote
    public let concept: WorkspaceCatalogNote
    public let relationship: Relationship
    /// Present only when the link is written in the related item itself.
    public let sourceLine: Int?

    public init(
        note: WorkspaceCatalogNote,
        concept: WorkspaceCatalogNote,
        relationship: Relationship,
        sourceLine: Int? = nil
    ) {
        self.note = note
        self.concept = concept
        self.relationship = relationship
        self.sourceLine = sourceLine
    }

    public var explanation: String {
        switch relationship {
        case .conceptLinksToItem:
            "Linked from \(concept.title)"
        case .itemLinksToConcept:
            "Links to \(concept.title)"
        case .conceptSupportsItem:
            "Supported by \(concept.title)"
        case .itemSupportsConcept:
            "Supports \(concept.title)"
        case .incompatible:
            "Incompatible with \(concept.title)"
        }
    }
}

public enum AttentionQueueKind: String, Codable, CaseIterable, Sendable {
    case possibleOrphan = "possible_orphan"
    case changedSinceReview = "changed_since_review"
    case malformedMetadata = "malformed_metadata"
    case brokenConnection = "broken_connection"
    case ambiguousConnection = "ambiguous_connection"
    case unqualifiedAnalysisReliance = "unqualified_analysis_reliance"
    case unresolvedIdentity = "unresolved_identity"

    public var displayName: String {
        switch self {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceReview: "Changed Since Review"
        case .malformedMetadata: "Malformed Metadata"
        case .brokenConnection: "Broken Connection"
        case .ambiguousConnection: "Ambiguous Connection"
        case .unqualifiedAnalysisReliance: "Unqualified Analysis Reliance"
        case .unresolvedIdentity: "Unresolved Identity"
        }
    }
}

public enum AttentionSeverity: String, Codable, Sendable {
    case information, warning
}

public struct AttentionQueueItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: AttentionQueueKind
    public let severity: AttentionSeverity
    public let note: VaultNoteReference
    public let message: String
    public let locator: SourceLocator?

    public init(
        kind: AttentionQueueKind,
        severity: AttentionSeverity,
        note: VaultNoteReference,
        message: String,
        locator: SourceLocator? = nil
    ) {
        id = "\(kind.rawValue):\(note.id):\(locator?.line ?? 0):\(message)"
        self.kind = kind
        self.severity = severity
        self.note = note
        self.message = message
        self.locator = locator
    }
}

/// The one declarative filter used by every Attention presentation.
///
/// Attention searches derived issue descriptions and note identities. It does
/// not search or rank authoritative note content, and therefore remains
/// distinct from full-text search while sharing its plain query interaction.
public struct AttentionQueueFilter: Codable, Hashable, Sendable {
    public var kind: AttentionQueueKind?
    public var query: String

    public init(kind: AttentionQueueKind? = nil, query: String = "") {
        self.kind = kind
        self.query = query
    }

    public func apply(to items: [AttentionQueueItem]) -> [AttentionQueueItem] {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter { item in
            guard kind == nil || item.kind == kind else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            let searchable = [
                item.kind.displayName,
                item.message,
                item.note.vaultName,
                item.note.relativePath,
                item.locator.map { "line \($0.line)" } ?? "",
            ]
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return searchable.contains(normalizedQuery)
        }
    }
}

/// Persistent, machine-local dismissal state. The caller chooses the duration;
/// every warning is dismissible and automatically returns after its deadline.
public struct AttentionDismissalLedger: Codable, Hashable, Sendable {
    public private(set) var dismissedUntilByItemID: [String: Date]

    public init(dismissedUntilByItemID: [String: Date] = [:]) {
        self.dismissedUntilByItemID = dismissedUntilByItemID
    }

    public func isDismissed(_ item: AttentionQueueItem, at date: Date = Date()) -> Bool {
        guard let deadline = dismissedUntilByItemID[item.id] else { return false }
        return deadline > date
    }

    public func visible(_ items: [AttentionQueueItem], at date: Date = Date()) -> [AttentionQueueItem] {
        items.filter { !isDismissed($0, at: date) }
    }

    public mutating func dismiss(
        _ item: AttentionQueueItem,
        forDays days: Int,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) {
        let clampedDays = min(max(days, 1), 365)
        dismissedUntilByItemID[item.id] = calendar.date(byAdding: .day, value: clampedDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(clampedDays * 86_400))
    }

    public mutating func removeExpired(at date: Date = Date()) {
        dismissedUntilByItemID = dismissedUntilByItemID.filter { $0.value > date }
    }

    public mutating func removeAll() {
        dismissedUntilByItemID.removeAll()
    }
}

public struct WorkspaceCatalogSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let notes: [WorkspaceCatalogNote]
    public let attention: [AttentionQueueItem]
    public let graph: GraphSnapshot?

    /// Expands an exact Topic title or alias through direct resolved links.
    ///
    /// This is deliberately not semantic search: ambiguous concepts, fielded
    /// queries, transitive paths, unresolved links, and the current-note scope
    /// produce no expansion. Lexical hits are excluded so Search and Related
    /// remain visibly separate systems.
    public func relatedSearchResults(
        for query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding excludedNotes: Set<VaultQualifiedNoteID> = [],
        limit: Int = 12
    ) -> [RelatedSearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = SearchQueryParser.parse(trimmed)
        guard limit > 0,
              !trimmed.isEmpty,
              let ast = parsed.ast,
              parsed.diagnostics.isEmpty,
              let relatedIdentityNeedle = ast.relatedIdentityNeedle,
              let graph,
              let searchGeneration,
              graph.sourceManifestHash == searchGeneration.sourceManifestHash else { return [] }

        let needle = Self.searchIdentityComparable(relatedIdentityNeedle)
        let matchingConcepts = notes.filter { note in
            guard note.reference.vaultRole == .topicKnowledge else { return false }
            return ([note.title] + note.aliases).contains {
                Self.searchIdentityComparable($0) == needle
            }
        }
        // Scholium does not guess which concept the researcher intended.
        guard matchingConcepts.count == 1, let concept = matchingConcepts.first else { return [] }

        let conceptID = VaultQualifiedNoteID(
            vaultID: concept.reference.vaultID,
            relativePath: concept.reference.relativePath
        )
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                note
            )
        })
        var related: [RelatedSearchItem] = []

        for edge in graph.outgoing[conceptID, default: []] {
            guard let destination = edge.destination?.note,
                  destination != conceptID,
                  !excludedNotes.contains(destination),
                  let note = notesByID[destination],
                  Self.includes(note, in: scope) else { continue }
            let relationship: RelatedSearchItem.Relationship = switch edge.occurrence.vectorKind {
            case .supportsTarget: .conceptSupportsItem
            case .supportedByTarget: .itemSupportsConcept
            case .incompatible: .incompatible
            case .neutral, nil: .conceptLinksToItem
            }
            related.append(RelatedSearchItem(
                note: note,
                concept: concept,
                relationship: relationship
            ))
        }

        for edge in graph.incoming[conceptID, default: []] {
            let source = edge.source
            guard source != conceptID,
                  !excludedNotes.contains(source),
                  let note = notesByID[source],
                  Self.includes(note, in: scope) else { continue }
            let relationship: RelatedSearchItem.Relationship = switch edge.occurrence.vectorKind {
            case .supportsTarget: .itemSupportsConcept
            case .supportedByTarget: .conceptSupportsItem
            case .incompatible: .incompatible
            case .neutral, nil: .itemLinksToConcept
            }
            related.append(RelatedSearchItem(
                note: note,
                concept: concept,
                relationship: relationship,
                sourceLine: edge.occurrence.span.start.line
            ))
        }

        var seen: Set<VaultQualifiedNoteID> = []
        return related
            .sorted(by: Self.relatedSearchOrder)
            .filter { item in
                seen.insert(VaultQualifiedNoteID(
                    vaultID: item.note.reference.vaultID,
                    relativePath: item.note.reference.relativePath
                )).inserted
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Returns only Analysis notes named by resolved links written in the
    /// opened Topic or Work. Incoming backlinks, bibliography citations,
    /// and transitive paths are intentionally excluded.
    public func zoteroSourceAnalyses(
        linkedFrom reference: VaultNoteReference,
        analysesVaultID: UUID
    ) -> [WorkspaceCatalogNote] {
        guard [.topicKnowledge, .draftProject].contains(reference.vaultRole),
              let graph else { return [] }
        let current = VaultQualifiedNoteID(
            vaultID: reference.vaultID,
            relativePath: reference.relativePath
        )
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                note
            )
        })
        var seenZoteroKeys: Set<String> = []
        return (graph.outgoing[current] ?? []).compactMap { edge in
            guard let destination = edge.destination?.note,
                  let note = notesByID[destination],
                  note.reference.vaultRole == .sourceCorpus,
                  note.reference.vaultID == analysesVaultID,
                  let key = note.zoteroItemKey?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased(),
                  !key.isEmpty,
                  seenZoteroKeys.insert(key).inserted else { return nil }
            return note
        }
    }

    private static func searchIdentityComparable(_ value: String) -> String {
        SearchTextNormalization.normalize(value)
    }

    private static func includes(
        _ note: WorkspaceCatalogNote,
        in scope: SearchExecutionScope
    ) -> Bool {
        switch scope {
        case .currentNote:
            false
        case .currentVault(let vaultID):
            note.reference.vaultID == vaultID
        case .triptych:
            true
        }
    }

    private static func relatedSearchOrder(_ lhs: RelatedSearchItem, _ rhs: RelatedSearchItem) -> Bool {
        let lhsTitle = searchIdentityComparable(lhs.note.title)
        let rhsTitle = searchIdentityComparable(rhs.note.title)
        if lhsTitle != rhsTitle { return lhsTitle < rhsTitle }
        let lhsRole = catalogRoleRank(lhs.note.reference.vaultRole)
        let rhsRole = catalogRoleRank(rhs.note.reference.vaultRole)
        if lhsRole != rhsRole { return lhsRole < rhsRole }
        let lhsPath = searchIdentityComparable(lhs.note.reference.relativePath)
        let rhsPath = searchIdentityComparable(rhs.note.reference.relativePath)
        if lhsPath != rhsPath { return lhsPath < rhsPath }
        return lhs.note.reference.vaultID.uuidString < rhs.note.reference.vaultID.uuidString
    }

    private static func catalogRoleRank(_ role: VaultRole) -> Int {
        switch role {
        case .sourceCorpus: 0
        case .topicKnowledge: 1
        case .draftProject: 2
        case .other: 3
        }
    }

}

public enum WorkspaceCatalogBuilder {
    public static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        reviewStates: [String: WorkspaceReviewState] = [:],
        graph: GraphSnapshot? = nil,
        graphs: [UUID: GraphSnapshot] = [:],
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:]
    ) -> WorkspaceCatalogSnapshot {
        let vaultsByID = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        var notes: [WorkspaceCatalogNote] = []
        var references: [String: VaultNoteReference] = [:]
        var attention: [AttentionQueueItem] = []

        for vaultID in documents.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let vault = vaultsByID[vaultID] else { continue }
            for document in (documents[vaultID] ?? []).sorted(by: { $0.relativePath < $1.relativePath }) {
                let stableID = ["note_id", "paper_id", "topic_id", "output_id"]
                    .compactMap { document.parsedFrontmatter[$0]?.catalogScalar }
                    .first
                let reference = VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: document.relativePath,
                    stableNoteID: stableID
                )
                references[reference.id] = reference
                let review = reviewStates[reference.id]
                let zoteroItemKey = document.parsedFrontmatter["zotero_item_key"]?.catalogScalar
                    ?? document.parsedFrontmatter["zoteroKey"]?.catalogScalar
                    ?? document.parsedFrontmatter["zotero-key"]?.catalogScalar
                let zoteroSourceIdentity = vault.role == .sourceCorpus
                    ? ZoteroSourceIdentity(
                        itemKey: zoteroItemKey,
                        doi: document.parsedFrontmatter["doi"]?.catalogScalar
                            ?? document.parsedFrontmatter["DOI"]?.catalogScalar,
                        isbn: document.parsedFrontmatter["isbn"]?.catalogScalar
                            ?? document.parsedFrontmatter["ISBN"]?.catalogScalar,
                        citationKey: document.parsedFrontmatter["zotero_citation_key"]?.catalogScalar
                            ?? document.parsedFrontmatter["citation_key"]?.catalogScalar
                            ?? document.parsedFrontmatter["citationKey"]?.catalogScalar
                            ?? document.parsedFrontmatter["citekey"]?.catalogScalar,
                        title: document.parsedFrontmatter["title"]?.catalogScalar,
                        authors: document.parsedFrontmatter["authors"]?.catalogStrings ?? [],
                        year: document.parsedFrontmatter["year"]?.catalogInteger
                    )
                    : nil
                notes.append(WorkspaceCatalogNote(
                    reference: reference,
                    title: document.parsedFrontmatter["title"]?.catalogScalar
                        ?? URL(fileURLWithPath: document.relativePath)
                            .deletingPathExtension()
                            .lastPathComponent,
                    aliases: (
                        document.parsedFrontmatter["aliases"]?.catalogStrings
                            ?? document.parsedFrontmatter["alias"]?.catalogStrings
                            ?? []
                    )
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                    zoteroItemKey: zoteroItemKey,
                    zoteroSourceIdentity: zoteroSourceIdentity,
                    fingerprint: document.fingerprint,
                    validationWarnings: document.validationWarnings
                ))

                if isActiveResearchPath(document.relativePath), !document.validationWarnings.isEmpty {
                    attention.append(AttentionQueueItem(
                        kind: .malformedMetadata,
                        severity: .warning,
                        note: reference,
                        message: document.validationWarnings.joined(separator: " "),
                        locator: SourceLocator(file: document.relativePath, line: 1, column: 1)
                    ))
                }
                if isActiveResearchPath(document.relativePath), review?.changedSinceReview == true {
                    attention.append(AttentionQueueItem(
                        kind: .changedSinceReview,
                        severity: .warning,
                        note: reference,
                        message: "The committed source has changed since the recorded human review."
                    ))
                }
            }
        }

        // Unqualified Analyses remain usable. Attention is limited to a
        // source-located scholarly reliance: target-to-containing support, a
        // citation context, or another explicitly source-bearing context.
        // Neutral Connections, incompatibility, and containing-to-target
        // support do not acquire evidential force merely by resolving to an
        // Analysis.
        let semanticDocuments = Dictionary(uniqueKeysWithValues: vaults.flatMap { vault in
            (documents[vault.id] ?? []).map { document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return (id, MarkdownSemanticDocument(parsing: document))
            }
        })
        let relianceGraph = graph ?? LinkGraphBuilder.build(
            generation: 1,
            catalog: vaults.flatMap { vault in
                (documents[vault.id] ?? []).map { document in
                    let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                    return LinkCatalogNote(
                        vaultID: vault.id,
                        document: document,
                        semantic: semanticDocuments[id]
                    )
                }
            },
            documents: semanticDocuments,
            resolutionScope: .workspace
        )
        let notesByQualifiedID = Dictionary(uniqueKeysWithValues: notes.map { note in
            (
                VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                note
            )
        })

        // Possible-orphan warnings are deliberately descriptive heuristics.
        // They report only observable absence and never conclude that a note
        // lacks scholarly value, evidence, or permission for use.
        for note in notes where isActiveResearchPath(note.reference.relativePath)
            && note.reference.vaultRole != .other {
            let noteID = VaultQualifiedNoteID(
                vaultID: note.reference.vaultID,
                relativePath: note.reference.relativePath
            )
            let outgoing = relianceGraph.outgoing[noteID] ?? []
            let incoming = relianceGraph.incoming[noteID] ?? []
            var reasons: [String] = []
            if outgoing.isEmpty && incoming.isEmpty {
                reasons.append("no incoming or outgoing links")
            }
            let hasExplicitRelation = (outgoing + incoming).contains { edge in
                guard let kind = edge.occurrence.vectorKind else { return false }
                return kind != .neutral
            }
            if !hasExplicitRelation {
                reasons.append("no explicit support or incompatibility relation")
            }
            let hasCrossVaultConnection = outgoing.contains { edge in
                guard let destination = edge.destination?.note else { return false }
                return destination.vaultID != noteID.vaultID
            } || incoming.contains { edge in
                edge.source.vaultID != noteID.vaultID
            }
            if !hasCrossVaultConnection {
                reasons.append("no resolved cross-vault integration")
            }
            if !reasons.isEmpty {
                attention.append(AttentionQueueItem(
                    kind: .possibleOrphan,
                    severity: .information,
                    note: note.reference,
                    message: "Possible orphan: \(reasons.joined(separator: "; ")). This is a structural reminder, not a judgment of the note's scholarly value."
                ))
            }
        }

        for vaultID in identityAmbiguitiesByVault.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            for ambiguity in identityAmbiguitiesByVault[vaultID, default: []]
                .sorted(by: { $0.relativePath < $1.relativePath }) {
                let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: ambiguity.relativePath)
                guard let note = notesByQualifiedID[noteID],
                      isActiveResearchPath(note.reference.relativePath) else { continue }
                let candidatePaths = ambiguity.candidates.map(\.relativePath).joined(separator: ", ")
                attention.append(AttentionQueueItem(
                    kind: .unresolvedIdentity,
                    severity: .warning,
                    note: note.reference,
                    message: candidatePaths.isEmpty
                        ? "Scholium cannot confirm this note's stable identity after an external file change."
                        : "Scholium cannot confirm this note's stable identity after an external file change. Possible previous locations: \(candidatePaths)."
                ))
            }
        }

        let unqualifiedAnalysisIDs = Set(notes.compactMap { note -> VaultQualifiedNoteID? in
            guard note.reference.vaultRole == .sourceCorpus,
                  isActiveResearchPath(note.reference.relativePath),
                  reviewStates[note.reference.id]?.qualification?.lowercased() == "unqualified" else {
                return nil
            }
            return VaultQualifiedNoteID(
                vaultID: note.reference.vaultID,
                relativePath: note.reference.relativePath
            )
        })
        for note in notes where [.topicKnowledge, .draftProject].contains(note.reference.vaultRole)
            && isActiveResearchPath(note.reference.relativePath) {
            let sourceID = VaultQualifiedNoteID(
                vaultID: note.reference.vaultID,
                relativePath: note.reference.relativePath
            )
            guard let semantic = semanticDocuments[sourceID] else { continue }
            for edge in relianceGraph.outgoing[sourceID] ?? [] {
                guard let destination = edge.destination?.note,
                      unqualifiedAnalysisIDs.contains(destination),
                      let analysis = notesByQualifiedID[destination],
                      let reliance = scholarlyRelianceDescription(
                        for: edge.occurrence,
                        analysisTitle: analysis.title,
                        semantic: semantic
                      ) else { continue }
                attention.append(AttentionQueueItem(
                    kind: .unqualifiedAnalysisReliance,
                    severity: .warning,
                    note: note.reference,
                    message: reliance + " Its use is permitted but should remain visible.",
                    locator: SourceLocator(
                        file: note.reference.relativePath,
                        line: edge.occurrence.span.start.line,
                        column: edge.occurrence.span.start.utf16Column
                    )
                ))
            }
        }

        let diagnosticGraphs = graph.map { [$0] }
            ?? (graphs.isEmpty ? [relianceGraph] : Array(graphs.values))
        for diagnosticGraph in diagnosticGraphs {
            for diagnostic in diagnosticGraph.diagnostics {
                guard let note = references["\(diagnostic.source.vaultID.uuidString):\(diagnostic.source.relativePath)"] else { continue }
                guard isActiveResearchPath(note.relativePath) else { continue }
                let queueKind: AttentionQueueKind
                switch diagnostic.code {
                case .ambiguous, .ambiguousHeading:
                    queueKind = .ambiguousConnection
                case .broken, .missingHeading, .missingBlock, .invalidRelationshipEndpoint:
                    queueKind = .brokenConnection
                case .duplicateRelationship:
                    continue
                }
                attention.append(AttentionQueueItem(
                    kind: queueKind,
                    severity: .warning,
                    note: note,
                    message: diagnostic.message,
                    locator: SourceLocator(
                        file: note.relativePath,
                        line: diagnostic.span.start.line,
                        column: diagnostic.span.start.utf16Column
                    )
                ))
            }
        }

        return WorkspaceCatalogSnapshot(
            generatedAt: Date(),
            notes: notes.sorted { $0.reference.id < $1.reference.id },
            attention: Array(Set(attention)).sorted {
                if $0.severity != $1.severity { return severityRank($0.severity) > severityRank($1.severity) }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.note.id < $1.note.id
            },
            graph: graph
        )
    }

    private static func severityRank(_ severity: AttentionSeverity) -> Int {
        switch severity { case .information: 0; case .warning: 1 }
    }

    private static func isActiveResearchPath(_ relativePath: String) -> Bool {
        !relativePath.hasPrefix("Set Aside/") && !relativePath.hasPrefix("Trash/")
    }

    private static func scholarlyRelianceDescription(
        for occurrence: LinkOccurrence,
        analysisTitle: String,
        semantic: MarkdownSemanticDocument
    ) -> String? {
        if occurrence.vectorKind == .supportedByTarget {
            return "This note is explicitly supported by the Unqualified Analysis ‘\(analysisTitle)’."
        }
        if semantic.callouts.contains(where: {
            $0.role == .cite && $0.span.contains(occurrence.span)
        }) {
            return "This note cites the Unqualified Analysis ‘\(analysisTitle)’ in a Source callout."
        }
        if semantic.footnoteDefinitions.contains(where: {
            $0.span.contains(occurrence.span)
        }) {
            return "This note cites the Unqualified Analysis ‘\(analysisTitle)’ in a footnote."
        }
        if semantic.callouts.contains(where: {
            $0.role == .quote && $0.span.contains(occurrence.span)
        }) {
            return "This note uses the Unqualified Analysis ‘\(analysisTitle)’ as the source anchor for a quotation."
        }
        return nil
    }
}

private extension SourceSpan {
    func contains(_ other: SourceSpan) -> Bool {
        utf16LowerBound <= other.utf16LowerBound
            && utf16UpperBound >= other.utf16UpperBound
    }
}

private extension YAMLValue {
    var catalogScalar: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .double(let value): String(value)
        case .boolean(let value): value ? "true" : "false"
        default: nil
        }
    }

    var catalogStrings: [String]? {
        switch self {
        case .array(let values):
            return values.compactMap(\.catalogScalar)
        case .string(let value):
            return [value]
        default:
            return nil
        }
    }

    var catalogInteger: Int? {
        switch self {
        case .integer(let value): value
        case .string(let value): Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: nil
        }
    }
}
