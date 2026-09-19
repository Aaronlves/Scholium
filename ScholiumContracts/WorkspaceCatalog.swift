import Foundation

public struct WorkspaceCatalogNote: Codable, Hashable, Identifiable, Sendable {
    public var id: String { reference.id }
    public let reference: VaultNoteReference
    public let title: String
    public let aliases: [String]
    public let authors: [String]
    public let publicationDate: String?
    public let fingerprint: DocumentFingerprint
    public let validationWarnings: [String]

    public init(
        reference: VaultNoteReference,
        title: String,
        aliases: [String] = [],
        authors: [String] = [],
        publicationDate: String? = nil,
        fingerprint: DocumentFingerprint,
        validationWarnings: [String]
    ) {
        self.reference = reference
        self.title = title
        self.aliases = aliases
        self.authors = authors
        self.publicationDate = publicationDate
        self.fingerprint = fingerprint
        self.validationWarnings = validationWarnings
    }

    private enum CodingKeys: String, CodingKey {
        case reference, title, aliases, authors, publicationDate
        case fingerprint, validationWarnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reference = try container.decode(VaultNoteReference.self, forKey: .reference)
        title = try container.decode(String.self, forKey: .title)
        aliases = try container.decode([String].self, forKey: .aliases)
        authors = try container.decode([String].self, forKey: .authors)
        publicationDate = try container.decodeIfPresent(String.self, forKey: .publicationDate)
        fingerprint = try container.decode(DocumentFingerprint.self, forKey: .fingerprint)
        validationWarnings = try container.decode([String].self, forKey: .validationWarnings)
    }
}

public enum AttentionQueueKind: String, Codable, CaseIterable, Sendable {
    case possibleOrphan = "possible_orphan"
    case malformedMetadata = "malformed_metadata"
    case brokenConnection = "broken_connection"
    case ambiguousConnection = "ambiguous_connection"
    case unresolvedIdentity = "unresolved_identity"

    public var displayName: String {
        switch self {
        case .possibleOrphan: "Possible Orphan"
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
    public var query: String

    public init(query: String = "") {
        self.query = query
    }

    public func apply(to items: [AttentionQueueItem]) -> [AttentionQueueItem] {
        let normalizedQuery =
            query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return items.filter { item in
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

    public init(
        dismissedUntilByItemID: [String: Date] = [:]
    ) {
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
        dismissedUntilByItemID[item.id] =
            calendar.date(byAdding: .day, value: clampedDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(clampedDays * 86_400))
    }

    public mutating func removeExpired(at date: Date = Date()) {
        dismissedUntilByItemID = dismissedUntilByItemID.filter { $0.value > date }
    }

    public mutating func removeAll() {
        dismissedUntilByItemID.removeAll()
    }

    private enum CodingKeys: String, CodingKey {
        case dismissedUntilByItemID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dismissedUntilByItemID: try container.decodeIfPresent(
                [String: Date].self,
                forKey: .dismissedUntilByItemID
            ) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dismissedUntilByItemID, forKey: .dismissedUntilByItemID)
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
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:]
    ) -> WorkspaceCatalogSnapshot {
        build(
            vaults: vaults,
            documents: documents,
            semanticDocuments: [:],
            additionalAttention: additionalAttention,
            graph: graph,
            identityAmbiguitiesByVault: identityAmbiguitiesByVault,
            stableNoteIDs: stableNoteIDs,
        )
    }

    package static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:]
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
                let yaml = SearchPropertyProjection(document: document)
                let reference = VaultNoteReference(
                    vaultID: vault.id,
                    vaultName: vault.name,
                    vaultRole: vault.role,
                    relativePath: document.relativePath,
                    stableNoteID: stableNoteID?.uuidString.lowercased()
                )
                references[reference.id] = reference
                notes.append(
                    WorkspaceCatalogNote(
                        reference: reference,
                        title: ResearchNoteTitleResolver.resolve(document: document),
                        aliases: yaml.textValues(forExactKey: "aliases"),
                        authors: yaml.textValues(forExactKey: "authors") + yaml.textValues(forExactKey: "author"),
                        publicationDate: yaml.textValues(forExactKey: "publication_date").first,
                        fingerprint: document.fingerprint,
                        validationWarnings: document.validationWarnings
                    ))

                if !document.validationWarnings.isEmpty {
                    attention.append(
                        AttentionQueueItem(
                            kind: .malformedMetadata,
                            severity: .warning,
                            note: reference,
                            message: "Invalid YAML",
                            locator: SourceLocator(file: document.relativePath, line: 1, column: 1)
                        ))
                }

                // Link resolution reads the body only, so `[[…]]` authored
                // inside a property makes no link and no backlink. The bytes
                // look like a connection and are silently none; report the
                // exact occurrence instead of leaving the author to discover
                // the absence from a missing backlink.
                for occurrence in inertPropertyWikilinks(in: yaml) {
                    attention.append(
                        AttentionQueueItem(
                            kind: .brokenConnection,
                            severity: .warning,
                            note: reference,
                            message: "Wikilink in property",
                            locator: SourceLocator(
                                file: document.relativePath,
                                line: occurrence.line,
                                column: occurrence.column
                            )
                        ))
                }
            }
        }

        let relianceGraph =
            graph
            ?? LinkGraphBuilder.build(
                generation: 1,
                catalog: vaults.flatMap { vault in
                    (documents[vault.id] ?? []).map { document in
                        let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                        return LinkCatalogNote(
                            vaultID: vault.id,
                            document: document,
                            profile: WorkflowProfileResolver.resolve(vaultRole: vault.role),
                            semantic: resolvedSemanticDocuments[id]
                        )
                    }
                },
                documents: resolvedSemanticDocuments,
                resolutionScope: .workspace
            )
        let notesByQualifiedID = Dictionary(
            uniqueKeysWithValues: notes.map { note in
                (
                    VaultQualifiedNoteID(
                        vaultID: note.reference.vaultID,
                        relativePath: note.reference.relativePath
                    ),
                    note
                )
            })

        // Possible Orphan reports only complete observable disconnection. A
        // same-vault or unresolved authored link still integrates
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
                attention.append(
                    AttentionQueueItem(
                        kind: .possibleOrphan,
                        severity: .information,
                        note: note.reference,
                        message: "No incoming or outgoing links"
                    ))
            }
        }

        for vaultID in identityAmbiguitiesByVault.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            for ambiguity in identityAmbiguitiesByVault[vaultID, default: []]
                .sorted(by: { $0.relativePath < $1.relativePath })
            {
                let noteID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: ambiguity.relativePath)
                guard let note = notesByQualifiedID[noteID] else { continue }
                attention.append(
                    AttentionQueueItem(
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
                case .ambiguous, .ambiguousHeading, .ambiguousBlock:
                    queueKind = .ambiguousConnection
                case .broken, .missingHeading, .missingBlock:
                    queueKind = .brokenConnection
                }
                attention.append(
                    AttentionQueueItem(
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
        switch severity {
        case .information: 0
        case .warning: 1
        }
    }

    /// Wikilink bytes authored inside a YAML property value.
    ///
    /// Only decoded string members are examined, so `matrix: [[1, 2], [3, 4]]`
    /// stays the nested flow sequence it parses as rather than being misread as
    /// two links. Nested mappings carry no string projection and are therefore
    /// not covered here.
    private static func inertPropertyWikilinks(
        in projection: SearchPropertyProjection
    ) -> [SearchSourceRange] {
        projection.entries.flatMap { entry in
            entry.stringMembers.compactMap { member in
                containsWikilink(member.value) ? member.sourceRange : nil
            }
        }
    }

    private static func containsWikilink(_ value: String) -> Bool {
        guard let open = value.range(of: "[["),
            let close = value.range(of: "]]", range: open.upperBound..<value.endIndex)
        else { return false }
        let target = value[open.upperBound..<close.lowerBound]
        return !target.trimmingCharacters(in: .whitespaces).isEmpty
            && !target.contains(where: \.isNewline)
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
        case .ambiguousBlock:
            "Multiple matching paragraphs"
        }
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
