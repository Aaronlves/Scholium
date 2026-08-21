import Foundation

/// Current applicability of a researcher Settlement. It is not a scholarly
/// qualification and never contributes to Search.
public struct WorkspaceSettlementState: Codable, Hashable, Sendable {
    public let settledFingerprint: DocumentFingerprint
    public let changedSinceSettled: Bool

    public init(
        settledFingerprint: DocumentFingerprint,
        changedSinceSettled: Bool
    ) {
        self.settledFingerprint = settledFingerprint
        self.changedSinceSettled = changedSinceSettled
    }
}

public struct WorkspaceCatalogNote: Codable, Hashable, Identifiable, Sendable {
    public var id: String { reference.id }
    public let reference: VaultNoteReference
    public let title: String
    public let aliases: [String]
    public let authors: [String]
    public let publicationDate: String?
    public let zoteroBinding: AnalysisZoteroBinding?
    public let fingerprint: DocumentFingerprint
    public let validationWarnings: [String]

    public init(
        reference: VaultNoteReference,
        title: String,
        aliases: [String] = [],
        authors: [String] = [],
        publicationDate: String? = nil,
        zoteroBinding: AnalysisZoteroBinding? = nil,
        fingerprint: DocumentFingerprint,
        validationWarnings: [String]
    ) {
        self.reference = reference
        self.title = title
        self.aliases = aliases
        self.authors = authors
        self.publicationDate = publicationDate
        self.zoteroBinding = zoteroBinding
        self.fingerprint = fingerprint
        self.validationWarnings = validationWarnings
    }

    private enum CodingKeys: String, CodingKey {
        case reference, title, aliases, authors, publicationDate, zoteroBinding
        case fingerprint, validationWarnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(VaultNoteReference.self, forKey: .reference)
        title = try container.decode(String.self, forKey: .title)
        aliases = try container.decode([String].self, forKey: .aliases)
        authors = try container.decode([String].self, forKey: .authors)
        publicationDate = try container.decodeIfPresent(String.self, forKey: .publicationDate)
        zoteroBinding = try container.decodeIfPresent(
            AnalysisZoteroBinding.self,
            forKey: .zoteroBinding
        )
        fingerprint = try container.decode(DocumentFingerprint.self, forKey: .fingerprint)
        validationWarnings = try container.decode([String].self, forKey: .validationWarnings)
    }
}

public enum AttentionQueueKind: String, Codable, CaseIterable, Sendable {
    case possibleOrphan = "possible_orphan"
    case changedSinceSettled = "changed_since_settled"
    case materialChangedSinceUse = "material_changed_since_use"
    case malformedMetadata = "malformed_metadata"
    case brokenConnection = "broken_connection"
    case ambiguousConnection = "ambiguous_connection"
    case unresolvedIdentity = "unresolved_identity"

    public var displayName: String {
        switch self {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceSettled: "Changed Since Settled"
        case .materialChangedSinceUse: "Material Changed Since Use"
        case .malformedMetadata: "Malformed Metadata"
        case .brokenConnection: "Broken Connection"
        case .ambiguousConnection: "Ambiguous Connection"
        case .unresolvedIdentity: "Unresolved Identity"
        }
    }
}

public enum AttentionSeverity: String, Codable, Sendable {
    case information, warning
}

/// Exact derived evidence for one Topic/Material revision relationship.
///
/// The record identity locates the completed Synthesize evidence used to
/// prepare a possible child phase. Item identity distinguishes affected
/// Topics, while dismissal identity deliberately omits both Topic and record
/// so the researcher decision binds only the Material and revision pair.
public struct MaterialChangedSinceUseAttentionContext: Codable, Hashable, Sendable {
    public let triptychID: UUID
    public let recordID: UUID
    public let topicNoteID: UUID
    public let materialNoteID: UUID
    public let material: VaultNoteReference
    public let recordedRevision: DocumentFingerprint
    public let currentRevision: DocumentFingerprint

    public init(
        triptychID: UUID,
        recordID: UUID,
        topicNoteID: UUID,
        materialNoteID: UUID,
        material: VaultNoteReference,
        recordedRevision: DocumentFingerprint,
        currentRevision: DocumentFingerprint
    ) {
        self.triptychID = triptychID
        self.recordID = recordID
        self.topicNoteID = topicNoteID
        self.materialNoteID = materialNoteID
        self.material = material
        self.recordedRevision = recordedRevision
        self.currentRevision = currentRevision
    }

    fileprivate var itemID: String {
        [
            AttentionQueueKind.materialChangedSinceUse.rawValue,
            triptychID.uuidString.lowercased(),
            topicNoteID.uuidString.lowercased(),
            materialNoteID.uuidString.lowercased(),
            recordedRevision.sha256,
            String(recordedRevision.byteCount),
            currentRevision.sha256,
            String(currentRevision.byteCount),
        ].joined(separator: ":")
    }

    fileprivate var dismissalID: String {
        [
            AttentionQueueKind.materialChangedSinceUse.rawValue,
            triptychID.uuidString.lowercased(),
            materialNoteID.uuidString.lowercased(),
            recordedRevision.sha256,
            String(recordedRevision.byteCount),
            currentRevision.sha256,
            String(currentRevision.byteCount),
        ].joined(separator: ":")
    }
}

public struct AttentionQueueItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let kind: AttentionQueueKind
    public let severity: AttentionSeverity
    public let note: VaultNoteReference
    public let message: String
    public let locator: SourceLocator?
    public let materialChangedSinceUse: MaterialChangedSinceUseAttentionContext?

    public init(
        kind: AttentionQueueKind,
        severity: AttentionSeverity,
        note: VaultNoteReference,
        message: String,
        locator: SourceLocator? = nil,
        materialChangedSinceUse: MaterialChangedSinceUseAttentionContext? = nil
    ) {
        id = materialChangedSinceUse?.itemID
            ?? "\(kind.rawValue):\(note.id):\(locator?.line ?? 0):\(message)"
        self.kind = kind
        self.severity = severity
        self.note = note
        self.message = message
        self.locator = locator
        self.materialChangedSinceUse = materialChangedSinceUse
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
    public private(set) var revisionBoundItemIDs: [String]

    public init(
        dismissedUntilByItemID: [String: Date] = [:],
        revisionBoundItemIDs: [String] = []
    ) {
        self.dismissedUntilByItemID = dismissedUntilByItemID
        self.revisionBoundItemIDs = Array(Set(revisionBoundItemIDs)).sorted()
    }

    public func isDismissed(_ item: AttentionQueueItem, at date: Date = Date()) -> Bool {
        if let dismissalID = item.materialChangedSinceUse?.dismissalID,
           revisionBoundItemIDs.contains(dismissalID) {
            return true
        }
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

    /// Records the researcher's deliberate decision for only this exact
    /// Material revision pair. A later current revision changes the dismissal
    /// identity and therefore becomes visible without mutating this ledger or
    /// the portable Research Record.
    public mutating func leaveUnchanged(_ item: AttentionQueueItem) {
        guard item.kind == .materialChangedSinceUse,
              let dismissalID = item.materialChangedSinceUse?.dismissalID else { return }
        revisionBoundItemIDs = Array(
            Set(revisionBoundItemIDs + [dismissalID])
        ).sorted()
        dismissedUntilByItemID[item.id] = nil
    }

    public mutating func removeAll() {
        dismissedUntilByItemID.removeAll()
        revisionBoundItemIDs.removeAll()
    }

    private enum CodingKeys: String, CodingKey {
        case dismissedUntilByItemID
        case revisionBoundItemIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dismissedUntilByItemID: try container.decodeIfPresent(
                [String: Date].self,
                forKey: .dismissedUntilByItemID
            ) ?? [:],
            revisionBoundItemIDs: try container.decodeIfPresent(
                [String].self,
                forKey: .revisionBoundItemIDs
            ) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dismissedUntilByItemID, forKey: .dismissedUntilByItemID)
        if !revisionBoundItemIDs.isEmpty {
            try container.encode(revisionBoundItemIDs, forKey: .revisionBoundItemIDs)
        }
    }
}

public struct WorkspaceCatalogSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let notes: [WorkspaceCatalogNote]
    public let attention: [AttentionQueueItem]
    public let graph: GraphSnapshot?

}

public enum WorkspaceCatalogBuilder {
    public static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        settlementStates: [String: WorkspaceSettlementState] = [:],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:],
        zoteroBindingsByNoteID: [UUID: AnalysisZoteroBinding] = [:]
    ) -> WorkspaceCatalogSnapshot {
        build(
            vaults: vaults,
            documents: documents,
            semanticDocuments: [:],
            settlementStates: settlementStates,
            additionalAttention: additionalAttention,
            graph: graph,
            identityAmbiguitiesByVault: identityAmbiguitiesByVault,
            stableNoteIDs: stableNoteIDs,
            zoteroBindingsByNoteID: zoteroBindingsByNoteID
        )
    }

    package static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        settlementStates: [String: WorkspaceSettlementState] = [:],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:],
        zoteroBindingsByNoteID: [UUID: AnalysisZoteroBinding] = [:]
    ) -> WorkspaceCatalogSnapshot {
        let vaultsByID = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        var resolvedSemanticDocuments = semanticDocuments
        for vault in vaults {
            for document in documents[vault.id] ?? [] {
                let id = VaultQualifiedNoteID(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                if resolvedSemanticDocuments[id]?.fingerprint != document.fingerprint {
                    resolvedSemanticDocuments[id] = MarkdownSemanticDocument(
                        parsing: document
                    )
                }
            }
        }
        var notes: [WorkspaceCatalogNote] = []
        var references: [String: VaultNoteReference] = [:]
        var attention: [AttentionQueueItem] = []

        for vaultID in documents.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let vault = vaultsByID[vaultID] else { continue }
            for document in (documents[vaultID] ?? []).sorted(by: { $0.relativePath < $1.relativePath }) {
                let qualifiedID = VaultQualifiedNoteID(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                let stableNoteID = stableNoteIDs[qualifiedID]
                let reference = VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: document.relativePath,
                    stableNoteID: stableNoteID?.uuidString.lowercased()
                )
                references[reference.id] = reference
                let settlement = settlementStates[reference.id]
                notes.append(WorkspaceCatalogNote(
                    reference: reference,
                    title: ResearchNoteTitleResolver.resolve(
                        document: document,
                        vaultRole: vault.role,
                        semantic: resolvedSemanticDocuments[
                            VaultQualifiedNoteID(
                                vaultID: vault.id,
                                relativePath: document.relativePath
                            )
                        ]
                    ).title,
                    aliases: (vault.role == .topicKnowledge
                        ? document.parsedFrontmatter["aliases"]?.canonicalStringList ?? []
                        : [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                    authors: vault.role == .sourceCorpus
                        ? document.parsedFrontmatter["authors"]
                            .flatMap { PropertyContractCatalog.creatorNames(from: $0) }?
                            .map(\.displayName) ?? []
                        : [],
                    publicationDate: vault.role == .sourceCorpus
                        ? document.parsedFrontmatter["publication_date"]?.canonicalSearchText
                        : nil,
                    zoteroBinding: vault.role == .sourceCorpus
                        ? stableNoteID.flatMap { zoteroBindingsByNoteID[$0] }
                        : nil,
                    fingerprint: document.fingerprint,
                    validationWarnings: document.validationWarnings
                ))

                if !document.validationWarnings.isEmpty {
                    attention.append(AttentionQueueItem(
                        kind: .malformedMetadata,
                        severity: .warning,
                        note: reference,
                        message: "Invalid YAML",
                        locator: SourceLocator(file: document.relativePath, line: 1, column: 1)
                    ))
                }
                if settlement?.changedSinceSettled == true {
                    attention.append(AttentionQueueItem(
                        kind: .changedSinceSettled,
                        severity: .warning,
                        note: reference,
                        message: "Changed after this revision was settled"
                    ))
                }
            }
        }

        let relianceGraph = graph ?? LinkGraphBuilder.build(
            generation: 1,
            catalog: vaults.flatMap { vault in
                (documents[vault.id] ?? []).map { document in
                    let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                    return LinkCatalogNote(
                        vaultID: vault.id,
                        document: document,
                        profile: WorkflowProfileResolver.resolve(
                            vaultRole: vault.role,
                            frontmatter: document.parsedFrontmatter,
                            relativePath: document.relativePath
                        ),
                        semantic: resolvedSemanticDocuments[id]
                    )
                }
            },
            documents: resolvedSemanticDocuments,
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

        // Possible Orphan reports only complete observable disconnection. A
        // neutral, same-vault, or otherwise non-vector link still integrates
        // the Note and must not be promoted into a warning.
        for note in notes where note.reference.vaultRole != .other {
            let noteID = VaultQualifiedNoteID(
                vaultID: note.reference.vaultID,
                relativePath: note.reference.relativePath
            )
            let outgoing = (relianceGraph.outgoing[noteID] ?? []).filter {
                $0.destination != nil
            }
            let incoming = relianceGraph.incoming[noteID] ?? []
            if outgoing.isEmpty && incoming.isEmpty {
                attention.append(AttentionQueueItem(
                    kind: .possibleOrphan,
                    severity: .information,
                    note: note.reference,
                    message: "No incoming or outgoing links"
                ))
            }
        }

        for vaultID in identityAmbiguitiesByVault.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            for ambiguity in identityAmbiguitiesByVault[vaultID, default: []]
                .sorted(by: { $0.relativePath < $1.relativePath }) {
                let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: ambiguity.relativePath)
                guard let note = notesByQualifiedID[noteID] else { continue }
                attention.append(AttentionQueueItem(
                    kind: .unresolvedIdentity,
                    severity: .warning,
                    note: note.reference,
                    message: ambiguity.candidates.isEmpty
                        ? "Identity not confirmed"
                        : "Multiple candidates"
                ))
            }
        }

        let diagnosticGraphs = graph.map { [$0] } ?? [relianceGraph]
        for diagnosticGraph in diagnosticGraphs {
            for diagnostic in diagnosticGraph.diagnostics {
                guard let note = references["\(diagnostic.source.vaultID.uuidString):\(diagnostic.source.relativePath)"] else { continue }
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
                    message: attentionReason(for: diagnostic),
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
            attention: Array(Set(attention + additionalAttention)).sorted {
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

    private static func attentionReason(for diagnostic: LinkGraphDiagnostic) -> String {
        switch diagnostic.code {
        case .ambiguous:
            "Multiple matching Notes"
        case .ambiguousHeading:
            "Multiple matching headings"
        case .broken:
            "Missing Note"
        case .missingHeading:
            "Missing heading"
        case .missingBlock:
            "Missing block"
        case .invalidRelationshipEndpoint:
            "Invalid relationship endpoint"
        case .duplicateRelationship:
            diagnostic.message
        }
    }

    private static func scholarlyRelianceDescription(
        for occurrence: LinkOccurrence,
        analysisTitle: String,
        semantic: MarkdownSemanticDocument
    ) -> String? {
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
