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

public struct WorkspaceCatalogSnapshot: Codable, Sendable {
    public let generatedAt: Date
    public let notes: [WorkspaceCatalogNote]
    public let attention: [AttentionQueueItem]
    public let graph: GraphSnapshot?

    package init(
        generatedAt: Date,
        notes: [WorkspaceCatalogNote],
        attention: [AttentionQueueItem],
        graph: GraphSnapshot?
    ) {
        self.generatedAt = generatedAt
        self.notes = notes
        self.attention = attention
        self.graph = graph
    }
}

/// Exact-revision catalog material produced while one descriptor-authorized
/// source is in scope. Every retained string is an owned value, not a slice of
/// the Markdown buffer; the complete semantic tree is discarded after parsing.
package struct WorkspaceSourceProjection: Codable, Hashable, Sendable {
    package let relativePath: String
    package let fingerprint: DocumentFingerprint
    package let title: String
    package let validationWarnings: [String]
    package let propertyTextValues: [String: [String]]
    package let canonicalAliases: [String]
    package let canonicalKeywords: [String]
    package let linkCatalog: LinkCatalogNote
    package let authoredLinks: [LinkOccurrence]
    package let inertPropertyWikilinks: [SearchSourceRange]

    package init(vaultID: UUID, document: NoteDocument, semantic: MarkdownSemanticDocument) {
        let properties = SearchPropertyProjection(document: document)
        relativePath = document.relativePath
        fingerprint = document.fingerprint
        title = ResearchNoteTitleResolver.resolve(document: document)
        validationWarnings = document.validationWarnings
        propertyTextValues = Self.textValues(properties)
        canonicalAliases = document.parsedFrontmatter["aliases"]?.canonicalStringList ?? []
        canonicalKeywords = document.parsedFrontmatter["keywords"]?.canonicalStringList ?? []
        linkCatalog = LinkCatalogNote(vaultID: vaultID, document: document, semantic: semantic)
        authoredLinks = semantic.links
        inertPropertyWikilinks = Self.inertWikilinks(properties)
    }

    /// A disposable record may provide syntax and coordinates, never source,
    /// file facts or identity authority. Recheck its cheap source properties and
    /// every persisted coordinate against the freshly descriptor-loaded Note.
    package func isValid(for document: NoteDocument, vaultID: UUID) -> Bool {
        let properties = SearchPropertyProjection(document: document)
        let expectedTitle = ResearchNoteTitleResolver.resolve(document: document)
        guard Data(relativePath.utf8) == Data(document.relativePath.utf8),
            fingerprint == document.fingerprint,
            title == expectedTitle, validationWarnings == document.validationWarnings,
            propertyTextValues == Self.textValues(properties),
            canonicalAliases == (document.parsedFrontmatter["aliases"]?.canonicalStringList ?? []),
            canonicalKeywords == (document.parsedFrontmatter["keywords"]?.canonicalStringList ?? []),
            linkCatalog.id.vaultID == vaultID,
            Data(linkCatalog.id.relativePath.utf8) == Data(document.relativePath.utf8),
            linkCatalog.title == expectedTitle,
            linkCatalog.aliases == properties.textValues(forExactKey: "aliases"),
            inertPropertyWikilinks == Self.inertWikilinks(properties),
            linkCatalog.ambiguousBlockAnchors.isDisjoint(with: linkCatalog.blockAnchors.keys),
            linkCatalog.headings.allSatisfy({ (1...6).contains($0.level) }),
            authoredLinks.allSatisfy({ $0.resolution == .unresolved }),
            zip(authoredLinks, authoredLinks.dropFirst()).allSatisfy({ $0.span.utf16LowerBound <= $1.span.utf16LowerBound })
        else { return false }

        let spans =
            linkCatalog.headings.map(\.span) + Array(linkCatalog.blockAnchors.values)
            + authoredLinks.flatMap { occurrence in
                [occurrence.span, occurrence.linkSpan]
                    + (occurrence.annotation.map { [$0.span, $0.contentSpan] } ?? [])
            }
        let coordinates = CatalogSourceCoordinates(
            source: document.rawContent,
            offsets: Set(
                spans.flatMap { [$0.utf16LowerBound, $0.utf16UpperBound] }
                    + inertPropertyWikilinks.flatMap { [$0.utf16LowerBound, $0.utf16UpperBound] }))
        guard spans.allSatisfy(coordinates.valid), inertPropertyWikilinks.allSatisfy(coordinates.valid),
            authoredLinks.allSatisfy({ occurrence in
                guard occurrence.span.utf16LowerBound <= occurrence.linkSpan.utf16LowerBound,
                    occurrence.linkSpan.utf16LowerBound < occurrence.linkSpan.utf16UpperBound,
                    occurrence.linkSpan.utf16UpperBound <= occurrence.span.utf16UpperBound
                else { return false }
                guard let annotation = occurrence.annotation else { return occurrence.span == occurrence.linkSpan }
                guard occurrence.syntax == .wikilink,
                    occurrence.span.utf16LowerBound == occurrence.linkSpan.utf16LowerBound,
                    annotation.span.utf16LowerBound == occurrence.linkSpan.utf16UpperBound,
                    annotation.span.utf16UpperBound == occurrence.span.utf16UpperBound,
                    annotation.contentSpan.utf16LowerBound - annotation.span.utf16LowerBound == 2,
                    annotation.span.utf16UpperBound - annotation.contentSpan.utf16UpperBound == 2,
                    annotation.contentSpan.utf16LowerBound <= annotation.contentSpan.utf16UpperBound
                else { return false }
                return (document.rawContent as NSString).substring(with: annotation.contentSpan.nsRange) == annotation.markdown
            })
        else { return false }
        return true
    }

    private static func textValues(_ properties: SearchPropertyProjection) -> [String: [String]] {
        Dictionary(
            uniqueKeysWithValues: properties.entries.map {
                ($0.key, $0.stringMembers.map { String(decoding: $0.value.utf8, as: UTF8.self) })
            })
    }

    private static func inertWikilinks(_ properties: SearchPropertyProjection) -> [SearchSourceRange] {
        properties.entries.flatMap { entry in
            entry.stringMembers.compactMap { member in
                guard let open = member.value.range(of: "[["),
                    let close = member.value.range(of: "]]", range: open.upperBound..<member.value.endIndex)
                else { return nil }
                let target = member.value[open.upperBound..<close.lowerBound]
                return !target.trimmingCharacters(in: .whitespaces).isEmpty
                    && !target.contains(where: \.isNewline)
                    ? member.sourceRange : nil
            }
        }
    }
}

/// Checks just the requested boundaries in one scalar pass. No retained table
/// proportional to every source character and no semantic reparsing is needed.
private struct CatalogSourceCoordinates {
    private let positions: [Int: (utf8: Int, position: SourcePosition)]

    init(source: String, offsets: Set<Int>) {
        guard !offsets.isEmpty else {
            positions = [:]
            return
        }
        let requested = offsets.filter { $0 >= 0 }.sorted()
        var requestedIndex = 0
        var result: [Int: (utf8: Int, position: SourcePosition)] = [:]
        var utf8 = 0
        var utf16 = 0
        var line = 1
        var lineStartUTF8 = 0
        var lineStartUTF16 = 0
        var scalars = source.unicodeScalars.makeIterator()
        var current = scalars.next()
        while let scalar = current {
            while requestedIndex < requested.count, requested[requestedIndex] <= utf16 {
                if requested[requestedIndex] == utf16 {
                    result[utf16] = (utf8, SourcePosition(line: line, utf8Column: utf8 - lineStartUTF8 + 1, utf16Column: utf16 - lineStartUTF16 + 1))
                }
                requestedIndex += 1
            }
            utf8 += scalar.utf8.count
            utf16 += scalar.utf16.count
            let next = scalars.next()
            if scalar == "\n" || (scalar == "\r" && next != "\n") {
                line += 1
                lineStartUTF8 = utf8
                lineStartUTF16 = utf16
            }
            current = next
        }
        if requestedIndex < requested.count, requested[requestedIndex] == utf16 {
            result[utf16] = (utf8, SourcePosition(line: line, utf8Column: utf8 - lineStartUTF8 + 1, utf16Column: utf16 - lineStartUTF16 + 1))
        }
        positions = result
    }

    func valid(_ span: SourceSpan) -> Bool {
        guard span.utf8LowerBound >= 0, span.utf8LowerBound <= span.utf8UpperBound,
            span.utf16LowerBound >= 0, span.utf16LowerBound <= span.utf16UpperBound,
            let lower = positions[span.utf16LowerBound], let upper = positions[span.utf16UpperBound]
        else { return false }
        return lower.utf8 == span.utf8LowerBound && upper.utf8 == span.utf8UpperBound
            && lower.position == span.start && upper.position == span.end
    }

    func valid(_ range: SearchSourceRange) -> Bool {
        guard range.utf16LowerBound >= 0, range.utf16LowerBound <= range.utf16UpperBound,
            let lower = positions[range.utf16LowerBound], let upper = positions[range.utf16UpperBound]
        else { return false }
        return lower.position.line == range.line && lower.position.utf16Column == range.column
            && upper.position.line == range.endLine && upper.position.utf16Column == range.endColumn
    }
}

public enum WorkspaceCatalogBuilder {
    package static func build(
        vaults: [RegisteredVault],
        projections: [UUID: [WorkspaceSourceProjection]],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:]
    ) -> WorkspaceCatalogSnapshot {
        let vaultsByID = Dictionary(uniqueKeysWithValues: vaults.map { ($0.id, $0) })
        var notes: [WorkspaceCatalogNote] = []
        var references: [String: VaultNoteReference] = [:]
        var attention: [AttentionQueueItem] = []
        for vaultID in projections.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let vault = vaultsByID[vaultID] else { continue }
            for projection in (projections[vaultID] ?? []).sorted(by: { $0.relativePath < $1.relativePath }) {
                let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: projection.relativePath)
                let reference = VaultNoteReference(
                    vaultID: vaultID, vaultName: vault.name, vaultRole: vault.role,
                    relativePath: projection.relativePath,
                    stableNoteID: stableNoteIDs[id]?.uuidString.lowercased()
                )
                references[reference.id] = reference
                notes.append(
                    WorkspaceCatalogNote(
                        reference: reference, title: projection.title,
                        aliases: projection.propertyTextValues["aliases"] ?? [],
                        authors: (projection.propertyTextValues["authors"] ?? [])
                            + (projection.propertyTextValues["author"] ?? []),
                        publicationDate: projection.propertyTextValues["publication_date"]?.first,
                        fingerprint: projection.fingerprint,
                        validationWarnings: projection.validationWarnings
                    ))
                if !projection.validationWarnings.isEmpty {
                    attention.append(
                        AttentionQueueItem(
                            kind: .malformedMetadata, severity: .warning,
                            note: reference, message: "Invalid YAML",
                            locator: SourceLocator(file: projection.relativePath, line: 1, column: 1)
                        ))
                }
                for occurrence in projection.inertPropertyWikilinks {
                    attention.append(
                        AttentionQueueItem(
                            kind: .brokenConnection, severity: .warning,
                            note: reference, message: "Wikilink in property",
                            locator: SourceLocator(
                                file: projection.relativePath,
                                line: occurrence.line, column: occurrence.column)
                        ))
                }
            }
        }

        let allProjections = vaults.flatMap { projections[$0.id] ?? [] }
        let relianceGraph =
            graph
            ?? LinkGraphBuilder.build(
                generation: 1,
                catalog: allProjections.map(\.linkCatalog),
                authoredLinks: Dictionary(
                    uniqueKeysWithValues: allProjections.map {
                        ($0.linkCatalog.id, $0.authoredLinks)
                    }),
                resolutionScope: .workspace
            )
        let notesByID = Dictionary(
            uniqueKeysWithValues: notes.map {
                (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0)
            })
        for note in notes where note.reference.vaultRole != .other {
            let id = VaultQualifiedNoteID(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)
            let outgoing = (relianceGraph.outgoing[id] ?? []).filter { $0.destination != nil }
            if outgoing.isEmpty && (relianceGraph.incoming[id] ?? []).isEmpty {
                attention.append(
                    AttentionQueueItem(
                        kind: .possibleOrphan, severity: .information,
                        note: note.reference, message: "No incoming or outgoing links"
                    ))
            }
        }
        for vaultID in identityAmbiguitiesByVault.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            for ambiguity in identityAmbiguitiesByVault[vaultID, default: []].sorted(by: { $0.relativePath < $1.relativePath }) {
                let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: ambiguity.relativePath)
                guard let note = notesByID[id] else { continue }
                attention.append(
                    AttentionQueueItem(
                        kind: .unresolvedIdentity, severity: .warning,
                        note: note.reference,
                        message: ambiguity.candidates.isEmpty ? "Identity not confirmed" : "Multiple candidates"
                    ))
            }
        }
        for diagnostic in relianceGraph.diagnostics {
            guard let note = references["\(diagnostic.source.vaultID.uuidString):\(diagnostic.source.relativePath)"] else { continue }
            let kind: AttentionQueueKind =
                switch diagnostic.code {
                case .ambiguous, .ambiguousHeading, .ambiguousBlock: .ambiguousConnection
                case .broken, .missingHeading, .missingBlock: .brokenConnection
                }
            attention.append(
                AttentionQueueItem(
                    kind: kind, severity: .warning, note: note,
                    message: attentionReason(for: diagnostic),
                    locator: SourceLocator(
                        file: note.relativePath,
                        line: diagnostic.span.start.line,
                        column: diagnostic.span.start.utf16Column)
                ))
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

    /// Bounded standalone construction for direct callers and fixtures. Live
    /// Workspace generations use the compact projection overload above.
    public static func build(
        vaults: [RegisteredVault],
        documents: [UUID: [NoteDocument]],
        additionalAttention: [AttentionQueueItem] = [],
        graph: GraphSnapshot? = nil,
        identityAmbiguitiesByVault: [UUID: [NoteIdentityAmbiguity]] = [:],
        stableNoteIDs: [VaultQualifiedNoteID: UUID] = [:]
    ) -> WorkspaceCatalogSnapshot {
        build(
            vaults: vaults, documents: documents, semanticDocuments: [:],
            additionalAttention: additionalAttention, graph: graph,
            identityAmbiguitiesByVault: identityAmbiguitiesByVault,
            stableNoteIDs: stableNoteIDs)
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
        let projections = Dictionary(
            uniqueKeysWithValues: vaults.map { vault in
                (
                    vault.id,
                    (documents[vault.id] ?? []).map { document in
                        let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                        let semantic =
                            semanticDocuments[id].flatMap {
                                $0.fingerprint == document.fingerprint ? $0 : nil
                            } ?? MarkdownSemanticDocument(parsing: document)
                        return WorkspaceSourceProjection(
                            vaultID: vault.id, document: document, semantic: semantic)
                    }
                )
            })
        return build(
            vaults: vaults, projections: projections,
            additionalAttention: additionalAttention, graph: graph,
            identityAmbiguitiesByVault: identityAmbiguitiesByVault,
            stableNoteIDs: stableNoteIDs)
    }

    private static func severityRank(_ severity: AttentionSeverity) -> Int {
        switch severity {
        case .information: 0
        case .warning: 1
        }
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
