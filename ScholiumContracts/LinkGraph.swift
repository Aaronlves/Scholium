import Foundation

public struct LinkCatalogNote: Codable, Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let title: String?
    public let aliases: [String]
    public let noteType: String?
    public let headings: [HeadingNode]
    public let blockAnchors: [String: SourceSpan]

    public init(
        id: VaultQualifiedNoteID,
        title: String? = nil,
        aliases: [String] = [],
        noteType: String? = nil,
        headings: [HeadingNode] = [],
        blockAnchors: [String: SourceSpan] = [:]
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.noteType = noteType
        self.headings = headings
        self.blockAnchors = blockAnchors
    }

    public init(vaultID: UUID, document: NoteDocument, semantic: MarkdownSemanticDocument? = nil) {
        let semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
        title = document.parsedFrontmatter["title"]?.nonemptyString
        aliases = Self.aliases(from: document.parsedFrontmatter["aliases"])
        noteType = document.parsedFrontmatter["note_type"]?.nonemptyString
        headings = semantic.headings
        blockAnchors = Self.blockAnchors(in: document, blocks: semantic.blocks)
    }

    private static func aliases(from value: YAMLValue?) -> [String] {
        switch value {
        case .string(let alias): [alias].filter { !$0.isEmpty }
        case .array(let aliases): aliases.compactMap(\.nonemptyString)
        default: []
        }
    }

    private static func blockAnchors(in document: NoteDocument, blocks: [MarkdownBlock]) -> [String: SourceSpan] {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?:^|\s)\^([A-Za-z0-9][A-Za-z0-9_-]*)\s*$"#,
            options: [.anchorsMatchLines]
        ) else { return [:] }
        let body = document.body as NSString
        var anchors: [String: SourceSpan] = [:]
        for match in regex.matches(in: document.body, range: NSRange(location: 0, length: body.length)) where match.numberOfRanges > 1 {
            let identifier = body.substring(with: match.range(at: 1))
            let lineRange = (body as String).lineRange(containingUTF16Offset: match.range.location)
            let fullFileLine = document.rawContent.prefixUTF16Length(beforeBodyUTF8Offset: document.bodyByteRange.lowerBound)
                .map { offset in
                    (document.rawContent as NSString).substring(to: offset + lineRange.location)
                        .reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
                } ?? 1
            guard let block = blocks.first(where: { $0.span.start.line <= fullFileLine && $0.span.end.line >= fullFileLine }) else { continue }
            if anchors[identifier] == nil { anchors[identifier] = block.span }
        }
        return anchors
    }
}

private extension YAMLValue {
    var nonemptyString: String? {
        guard case .string(let value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    func prefixUTF16Length(beforeBodyUTF8Offset byteOffset: Int) -> Int? {
        guard let utf8Index = utf8.index(utf8.startIndex, offsetBy: byteOffset, limitedBy: utf8.endIndex),
              let index = String.Index(utf8Index, within: self) else { return nil }
        return self[..<index].utf16.count
    }

    func lineRange(containingUTF16Offset offset: Int) -> NSRange {
        let nsString = self as NSString
        return nsString.lineRange(for: NSRange(location: min(max(0, offset), nsString.length), length: 0))
    }
}

public enum LinkDestinationKind: String, Codable, Hashable, Sendable {
    case note
    case heading
    case block
}

public struct LinkDestination: Codable, Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let kind: LinkDestinationKind
    public let fragment: String?
    public let span: SourceSpan?
}

public struct LinkGraphEdge: Codable, Hashable, Sendable {
    public let source: VaultQualifiedNoteID
    public let occurrence: LinkOccurrence
    public let destination: LinkDestination?
}

public enum LinkGraphDiagnosticCode: String, Codable, Hashable, Sendable {
    case broken
    case ambiguous
    case missingHeading
    case ambiguousHeading
    case missingBlock
    case invalidRelationshipEndpoint
    case duplicateRelationship
}

public struct LinkGraphDiagnostic: Codable, Hashable, Sendable {
    public let code: LinkGraphDiagnosticCode
    public let source: VaultQualifiedNoteID
    public let target: String
    public let message: String
    public let span: SourceSpan
}

public struct GraphSnapshot: Codable, Sendable {
    public static let currentContractVersion = 3
    public let contractVersion: Int
    public let generation: Int
    /// Hash of the complete source manifest from which this graph was built.
    /// Related is compatible only with a Search generation carrying this hash.
    public let sourceManifestHash: String
    public let outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]]
    public let incoming: [VaultQualifiedNoteID: [LinkGraphEdge]]
    public let diagnostics: [LinkGraphDiagnostic]
    public let relationships: [RelationshipEdge]

    public init(
        contractVersion: Int,
        generation: Int,
        sourceManifestHash: String = "",
        outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]],
        incoming: [VaultQualifiedNoteID: [LinkGraphEdge]],
        diagnostics: [LinkGraphDiagnostic],
        relationships: [RelationshipEdge]
    ) {
        self.contractVersion = contractVersion
        self.generation = generation
        self.sourceManifestHash = sourceManifestHash
        self.outgoing = outgoing
        self.incoming = incoming
        self.diagnostics = diagnostics
        self.relationships = relationships
    }

    private enum CodingKeys: String, CodingKey {
        case contractVersion, generation, sourceManifestHash
        case outgoing, incoming, diagnostics, relationships
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decode(Int.self, forKey: .contractVersion)
        generation = try container.decode(Int.self, forKey: .generation)
        sourceManifestHash = try container.decodeIfPresent(
            String.self,
            forKey: .sourceManifestHash
        ) ?? ""
        outgoing = try container.decode(
            [VaultQualifiedNoteID: [LinkGraphEdge]].self,
            forKey: .outgoing
        )
        incoming = try container.decode(
            [VaultQualifiedNoteID: [LinkGraphEdge]].self,
            forKey: .incoming
        )
        diagnostics = try container.decode([LinkGraphDiagnostic].self, forKey: .diagnostics)
        relationships = try container.decode([RelationshipEdge].self, forKey: .relationships)
    }
}

public enum LinkResolutionScope: String, Codable, Hashable, Sendable {
    /// Resolve only inside the source vault. Use this for a standalone vault
    /// projection.
    case sourceVault

    /// Prefer the source vault, then resolve only a unique match elsewhere in
    /// the configured Triptych. Scholium never guesses between vaults.
    case workspace
}

public enum LinkGraphBuilder {
    public static func build(
        generation: Int,
        catalog: [LinkCatalogNote],
        documents: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        resolutionScope: LinkResolutionScope = .sourceVault,
        sourceManifestHash: String = ""
    ) -> GraphSnapshot {
        build(
            generation: generation,
            catalog: catalog,
            documents: documents,
            resolutionScope: resolutionScope,
            sourceManifestHash: sourceManifestHash,
            cancellationCheck: {}
        )
    }

    /// Builds the same deterministic graph as ``build``, while allowing an
    /// asynchronous workspace activation to stop superseded derived work.
    public static func buildCancellable(
        generation: Int,
        catalog: [LinkCatalogNote],
        documents: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        resolutionScope: LinkResolutionScope = .sourceVault,
        sourceManifestHash: String = ""
    ) throws -> GraphSnapshot {
        try build(
            generation: generation,
            catalog: catalog,
            documents: documents,
            resolutionScope: resolutionScope,
            sourceManifestHash: sourceManifestHash,
            cancellationCheck: { try Task.checkCancellation() }
        )
    }

    private static func build(
        generation: Int,
        catalog: [LinkCatalogNote],
        documents: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        resolutionScope: LinkResolutionScope,
        sourceManifestHash: String,
        cancellationCheck: () throws -> Void
    ) rethrows -> GraphSnapshot {
        let notesByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let resolutionIndex = ResolutionIndex(catalog: catalog)
        var outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]] = [:]
        var incoming: [VaultQualifiedNoteID: [LinkGraphEdge]] = [:]
        var diagnostics: [LinkGraphDiagnostic] = []
        var relationships: [RelationshipEdge] = []
        var vectorSources: [UUID: [(VaultQualifiedNoteID, LinkOccurrence)]] = [:]
        var processedLinkCount = 0

        for source in documents.keys.sorted() {
            try cancellationCheck()
            guard let semantic = documents[source] else { continue }
            var edges: [LinkGraphEdge] = []
            for original in semantic.links where !original.isExternal {
                if processedLinkCount.isMultiple(of: 256) {
                    try cancellationCheck()
                }
                processedLinkCount += 1
                var occurrence = original
                let resolution = resolutionIndex.resolve(
                    original.target,
                    from: source,
                    scope: resolutionScope
                )
                occurrence.resolution = resolution
                let destinationResult = destination(
                    for: occurrence,
                    resolution: resolution,
                    notesByID: notesByID,
                    source: source
                )
                diagnostics.append(contentsOf: destinationResult.diagnostics)
                let edge = LinkGraphEdge(source: source, occurrence: occurrence, destination: destinationResult.destination)
                edges.append(edge)
                if let destination = destinationResult.destination {
                    incoming[destination.note, default: []].append(edge)
                }
                if case .ambiguous = resolution {
                    diagnostics.append(LinkGraphDiagnostic(
                        code: .ambiguous,
                        source: source,
                        target: occurrence.target,
                        message: "The link matches more than one note; Scholium did not choose one.",
                        span: occurrence.span
                    ))
                } else if case .broken(let target) = resolution {
                    diagnostics.append(LinkGraphDiagnostic(
                        code: .broken,
                        source: source,
                        target: target,
                        message: resolutionScope == .workspace
                            ? "The link target does not exist in this Triptych."
                            : "The link target does not exist in this vault.",
                        span: occurrence.span
                    ))
                }
                if occurrence.syntax != .embed {
                    let normalizedRelationship = relationship(from: source, occurrence: occurrence)
                    relationships.append(normalizedRelationship)
                    if normalizedRelationship.vectorKind != nil {
                        vectorSources[normalizedRelationship.id, default: []].append((source, occurrence))
                    }
                }
            }
            outgoing[source] = edges
        }

        var normalizedRelationships: [RelationshipEdge] = []
        var vectorIndexByID: [UUID: Int] = [:]
        for edge in relationships {
            guard edge.vectorKind != nil else {
                normalizedRelationships.append(edge)
                continue
            }
            if let index = vectorIndexByID[edge.id] {
                normalizedRelationships[index] = normalizedRelationships[index].mergingOccurrences(from: edge)
            } else {
                vectorIndexByID[edge.id] = normalizedRelationships.count
                normalizedRelationships.append(edge)
            }
        }
        for edge in normalizedRelationships where edge.vectorKind != nil
            && edge.vectorKind != .neutral && edge.occurrences.count > 1 {
            for (source, occurrence) in vectorSources[edge.id, default: []].dropFirst() {
                diagnostics.append(LinkGraphDiagnostic(
                    code: .duplicateRelationship,
                    source: source,
                    target: occurrence.target,
                    message: "This vector relation is declared more than once; Scholium normalized all occurrences to one edge.",
                    span: occurrence.span
                ))
            }
        }

        return GraphSnapshot(
            contractVersion: GraphSnapshot.currentContractVersion,
            generation: generation,
            sourceManifestHash: sourceManifestHash,
            outgoing: outgoing,
            incoming: incoming,
            diagnostics: diagnostics.sorted(by: diagnosticOrder),
            relationships: normalizedRelationships
        )
    }

    public static func resolve(
        _ rawTarget: String,
        from source: VaultQualifiedNoteID,
        catalog: [LinkCatalogNote],
        scope: LinkResolutionScope = .sourceVault
    ) -> LinkOccurrenceResolution {
        ResolutionIndex(catalog: catalog).resolve(
            rawTarget,
            from: source,
            scope: scope
        )
    }

    struct ResolutionIndex {
        private struct FolderStem: Hashable {
            let folder: String
            let stem: String
        }

        private let noteIDs: Set<VaultQualifiedNoteID>
        private let exactPathsByVault: [UUID: [String: [VaultQualifiedNoteID]]]
        private let folderStemsByVault: [UUID: [FolderStem: [VaultQualifiedNoteID]]]
        private let stemsByVault: [UUID: [String: [VaultQualifiedNoteID]]]
        private let declaredNamesByVault: [UUID: [String: [VaultQualifiedNoteID]]]
        private let workspaceExactPaths: [String: [VaultQualifiedNoteID]]
        private let workspaceStems: [String: [VaultQualifiedNoteID]]
        private let workspaceDeclaredNames: [String: [VaultQualifiedNoteID]]

        init(catalog: [LinkCatalogNote]) {
            var exactPathsByVault: [UUID: [String: [VaultQualifiedNoteID]]] = [:]
            var folderStemsByVault: [UUID: [FolderStem: [VaultQualifiedNoteID]]] = [:]
            var stemsByVault: [UUID: [String: [VaultQualifiedNoteID]]] = [:]
            var declaredNamesByVault: [UUID: [String: [VaultQualifiedNoteID]]] = [:]
            var workspaceExactPaths: [String: [VaultQualifiedNoteID]] = [:]
            var workspaceStems: [String: [VaultQualifiedNoteID]] = [:]
            var workspaceDeclaredNames: [String: [VaultQualifiedNoteID]] = [:]

            for note in catalog {
                let id = note.id
                let path = id.relativePath as NSString
                let normalizedPath = LinkGraphBuilder.normalizedMarkdownPath(id.relativePath)
                let folder = path.deletingLastPathComponent
                let stem = (path.lastPathComponent as NSString).deletingPathExtension
                let folderStem = FolderStem(folder: folder, stem: stem)

                exactPathsByVault[id.vaultID, default: [:]][normalizedPath, default: []].append(id)
                folderStemsByVault[id.vaultID, default: [:]][folderStem, default: []].append(id)
                stemsByVault[id.vaultID, default: [:]][stem, default: []].append(id)
                workspaceExactPaths[normalizedPath, default: []].append(id)
                workspaceStems[stem, default: []].append(id)

                var declaredNames: Set<String> = []
                if let title = note.title {
                    declaredNames.insert(LinkGraphBuilder.normalizedLookupName(title))
                }
                for alias in note.aliases {
                    declaredNames.insert(LinkGraphBuilder.normalizedLookupName(alias))
                }
                for declaredName in declaredNames {
                    declaredNamesByVault[id.vaultID, default: [:]][declaredName, default: []].append(id)
                    workspaceDeclaredNames[declaredName, default: []].append(id)
                }
            }

            noteIDs = Set(catalog.map(\.id))
            self.exactPathsByVault = exactPathsByVault
            self.folderStemsByVault = folderStemsByVault
            self.stemsByVault = stemsByVault
            self.declaredNamesByVault = declaredNamesByVault
            self.workspaceExactPaths = workspaceExactPaths
            self.workspaceStems = workspaceStems
            self.workspaceDeclaredNames = workspaceDeclaredNames
        }

        func resolve(
            _ rawTarget: String,
            from source: VaultQualifiedNoteID,
            scope: LinkResolutionScope
        ) -> LinkOccurrenceResolution {
            let target = normalizedMarkdownPath(rawTarget)
            // Markdown and Obsidian both permit a fragment-only link such as
            // `[section](#Argument)` or `[[#Argument]]`. Its note destination is
            // the containing note; the fragment is resolved separately below.
            if rawTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return noteIDs.contains(source)
                    ? .resolved(source)
                    : .broken(rawTarget)
            }
            guard !target.isEmpty else { return .broken(rawTarget) }

            if let result = resolution(exactPathsByVault[source.vaultID]?[target]) {
                return result
            }

            let sourceFolder = (source.relativePath as NSString).deletingLastPathComponent
            let relative = normalizedMarkdownPath((sourceFolder as NSString).appendingPathComponent(rawTarget))
            if !relative.hasPrefix("../") {
                if let result = resolution(exactPathsByVault[source.vaultID]?[relative]) {
                    return result
                }
            }

            let stem = ((target as NSString).lastPathComponent as NSString).deletingPathExtension
            if let result = resolution(
                folderStemsByVault[source.vaultID]?[FolderStem(folder: sourceFolder, stem: stem)]
            ) {
                return result
            }

            if let result = resolution(stemsByVault[source.vaultID]?[stem]) {
                return result
            }

            let normalizedName = normalizedLookupName(stem)
            if let result = resolution(declaredNamesByVault[source.vaultID]?[normalizedName]) {
                return result
            }

            guard scope == .workspace else { return .broken(rawTarget) }

            // Cross-vault lookup is intentionally narrower than same-vault lookup.
            // A unique exact path wins, followed by a unique stem, then a unique
            // declared title or alias. Any collision remains ambiguous.
            if let result = resolution(
                workspaceExactPaths[target]?.filter { $0.vaultID != source.vaultID }
            ) {
                return result
            }

            if let result = resolution(
                workspaceStems[stem]?.filter { $0.vaultID != source.vaultID }
            ) {
                return result
            }

            if let result = resolution(
                workspaceDeclaredNames[normalizedName]?.filter { $0.vaultID != source.vaultID }
            ) {
                return result
            }
            return .broken(rawTarget)
        }

        private func resolution(
            _ candidates: [VaultQualifiedNoteID]?
        ) -> LinkOccurrenceResolution? {
            guard let candidates, !candidates.isEmpty else { return nil }
            if candidates.count == 1, let candidate = candidates.first {
                return .resolved(candidate)
            }
            return .ambiguous(candidates.sorted())
        }
    }

    private static func destination(
        for occurrence: LinkOccurrence,
        resolution: LinkOccurrenceResolution,
        notesByID: [VaultQualifiedNoteID: LinkCatalogNote],
        source: VaultQualifiedNoteID
    ) -> (destination: LinkDestination?, diagnostics: [LinkGraphDiagnostic]) {
        guard case .resolved(let id) = resolution, let note = notesByID[id] else { return (nil, []) }
        guard let fragment = occurrence.fragment, !fragment.isEmpty else {
            return (LinkDestination(note: id, kind: .note, fragment: nil, span: nil), [])
        }
        if fragment.hasPrefix("^") {
            let key = String(fragment.dropFirst())
            if let span = note.blockAnchors[key] {
                return (LinkDestination(note: id, kind: .block, fragment: fragment, span: span), [])
            }
            return (nil, [LinkGraphDiagnostic(
                code: .missingBlock,
                source: source,
                target: occurrence.target,
                message: "The target note has no block anchor ^\(key).",
                span: occurrence.span
            )])
        }

        let sought = normalizedHeading(fragment)
        let matches = note.headings.filter { normalizedHeading($0.text) == sought }
        if matches.count == 1 {
            return (LinkDestination(note: id, kind: .heading, fragment: fragment, span: matches[0].span), [])
        }
        let code: LinkGraphDiagnosticCode = matches.isEmpty ? .missingHeading : .ambiguousHeading
        let message = matches.isEmpty
            ? "The target note has no heading named \(fragment)."
            : "The target note has more than one heading named \(fragment)."
        return (nil, [LinkGraphDiagnostic(code: code, source: source, target: occurrence.target, message: message, span: occurrence.span)])
    }

    private static func relationship(from source: VaultQualifiedNoteID, occurrence: LinkOccurrence) -> RelationshipEdge {
        let targetPath: String
        let targetNote: VaultQualifiedNoteID?
        let relationshipResolution: RelationshipResolution
        switch occurrence.resolution {
        case .resolved(let destination):
            targetPath = destination.relativePath
            targetNote = destination
            relationshipResolution = .resolved(destination.relativePath)
        case .ambiguous(let destinations):
            targetPath = occurrence.target
            targetNote = nil
            relationshipResolution = .ambiguous(destinations.map(\.relativePath))
        case .broken:
            targetPath = occurrence.target
            targetNote = nil
            relationshipResolution = .broken(occurrence.target)
        case .unresolved:
            targetPath = occurrence.target
            targetNote = nil
            relationshipResolution = .broken(occurrence.target)
        }
        let locator = SourceLocator(
            file: source.relativePath,
            line: occurrence.span.start.line,
            column: occurrence.span.start.utf16Column,
            headingOrBlock: occurrence.fragment
        )
        if let vectorKind = occurrence.vectorKind {
            return .vector(
                containing: source,
                target: targetNote,
                targetPath: targetPath,
                kind: vectorKind,
                locator: locator,
                syntax: occurrence.syntax,
                resolution: relationshipResolution
            )
        }
        // Vector-Link is the only source syntax that may create an explicit
        // philosophical relationship. Any predicate retained in older decoded
        // semantic data is deliberately ignored and remains a neutral link.
        return .explicit(
            containingPath: source.relativePath,
            targetPath: targetPath,
            predicate: .connected,
            locator: locator,
            resolution: relationshipResolution
        )
    }

    private static func normalizedMarkdownPath(_ raw: String) -> String {
        var value = raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("/") { value.removeFirst() }
        if !value.lowercased().hasSuffix(".md") { value += ".md" }
        return (value as NSString).standardizingPath
    }

    private static func normalizedLookupName(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHeading(_ value: String) -> String {
        normalizedLookupName(value.removingPercentEncoding ?? value)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func diagnosticOrder(_ lhs: LinkGraphDiagnostic, _ rhs: LinkGraphDiagnostic) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        return lhs.span.utf16LowerBound < rhs.span.utf16LowerBound
    }
}
