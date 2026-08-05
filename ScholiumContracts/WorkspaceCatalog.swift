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

public enum AttentionQueueKind: String, Codable, CaseIterable, Sendable {
    case possibleOrphan = "possible_orphan"
    case changedSinceSettled = "changed_since_settled"
    case materialChangedSinceUse = "material_changed_since_use"
    case changeAttributionNeeded = "change_attribution_needed"
    case malformedMetadata = "malformed_metadata"
    case brokenConnection = "broken_connection"
    case ambiguousConnection = "ambiguous_connection"
    case unresolvedIdentity = "unresolved_identity"

    public var displayName: String {
        switch self {
        case .possibleOrphan: "Possible Orphan"
        case .changedSinceSettled: "Changed Since Settled"
        case .materialChangedSinceUse: "Material Changed Since Use"
        case .changeAttributionNeeded: "Change Attribution Needed"
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
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:]
    ) -> WorkspaceCatalogSnapshot {
        build(
            vaults: vaults,
            documents: documents,
            semanticDocuments: [:],
            settlementStates: settlementStates,
            additionalAttention: additionalAttention,
            graph: graph,
            identityAmbiguitiesByVault: identityAmbiguitiesByVault
        )
    }

    package static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        settlementStates: [String: WorkspaceSettlementState] = [:],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:]
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
                let settlement = settlementStates[reference.id]
                let zoteroItemKey = vault.role == .sourceCorpus
                    ? document.parsedFrontmatter["zotero_item_key"]?.catalogScalar
                    : nil
                let zoteroSourceIdentity = vault.role == .sourceCorpus
                    ? ZoteroSourceIdentity(
                        itemKey: zoteroItemKey,
                        title: document.parsedFrontmatter["title"]?.catalogScalar,
                        authors: document.parsedFrontmatter["authors"]?.catalogStrings ?? [],
                        year: document.parsedFrontmatter["year"]?.catalogInteger
                    )
                    : nil
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
                if isActiveResearchPath(document.relativePath),
                   settlement?.changedSinceSettled == true {
                    attention.append(AttentionQueueItem(
                        kind: .changedSinceSettled,
                        severity: .warning,
                        note: reference,
                        message: "The committed source has changed since this revision was settled."
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
                reasons.append("no explicit support, opposition, or question relation")
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

        let diagnosticGraphs = graph.map { [$0] } ?? [relianceGraph]
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

    private static func isActiveResearchPath(_ relativePath: String) -> Bool {
        !relativePath.hasPrefix("Set Aside/") && !relativePath.hasPrefix("Trash/")
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
