import Foundation

public struct LinkCatalogNote: Codable, Hashable, Sendable {
    public let id: VaultQualifiedNoteID
    public let title: String?
    public let aliases: [String]
    public let headings: [HeadingNode]
    public let blockAnchors: [String: SourceSpan]

    public init(
        id: VaultQualifiedNoteID,
        title: String? = nil,
        aliases: [String] = [],
        headings: [HeadingNode] = [],
        blockAnchors: [String: SourceSpan] = [:]
    ) {
        self.id = id
        self.title = title
        self.aliases = aliases
        self.headings = headings
        self.blockAnchors = blockAnchors
    }

    public init(
        vaultID: UUID,
        document: NoteDocument,
        profile: SchemaProfileID = .genericMarkdown,
        metadata: NoteMetadataSnapshot? = nil,
        semantic: MarkdownSemanticDocument? = nil
    ) {
        let semantic = semantic ?? MarkdownSemanticDocument(parsing: document)
        id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
        title = ResearchNoteTitleResolver.resolve(document: document)
        aliases = profile == .topicMarkdown
            ? metadata?.record.fields["aliases"]?.canonicalStringList ?? []
            : []
        headings = semantic.headings
        blockAnchors = Self.blockAnchors(in: document, blocks: semantic.blocks)
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

    public init(
        note: VaultQualifiedNoteID,
        kind: LinkDestinationKind,
        fragment: String?,
        span: SourceSpan?
    ) {
        self.note = note
        self.kind = kind
        self.fragment = fragment
        self.span = span
    }
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
}

public struct LinkGraphDiagnostic: Codable, Hashable, Sendable {
    public let code: LinkGraphDiagnosticCode
    public let source: VaultQualifiedNoteID
    public let target: String
    public let message: String
    public let span: SourceSpan
}

public struct GraphSnapshot: Codable, Sendable {
    public static let currentContractVersion = 6
    public let contractVersion: Int
    public let generation: Int
    /// Hash of the complete source manifest from which this graph was built.
    /// Direct-link Search is compatible only with a generation carrying this hash.
    public let sourceManifestHash: String
    public let outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]]
    public let incoming: [VaultQualifiedNoteID: [LinkGraphEdge]]
    public let diagnostics: [LinkGraphDiagnostic]

    public init(
        contractVersion: Int,
        generation: Int,
        sourceManifestHash: String = "",
        outgoing: [VaultQualifiedNoteID: [LinkGraphEdge]],
        incoming: [VaultQualifiedNoteID: [LinkGraphEdge]],
        diagnostics: [LinkGraphDiagnostic]
    ) {
        self.contractVersion = contractVersion
        self.generation = generation
        self.sourceManifestHash = sourceManifestHash
        self.outgoing = outgoing
        self.incoming = incoming
        self.diagnostics = diagnostics
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

/// A navigation-only resolution for one authored link target. It carries no
/// connection meaning and never creates a Graph edge.
public enum LinkNavigationResolution: Hashable, Sendable {
    case resolved(LinkDestination)
    case ambiguous([VaultQualifiedNoteID])
    case missingNote
    case missingHeading
    case ambiguousHeading
    case missingBlock
}

/// Reusable immutable lookup state for consumers that need the same
/// fail-closed Note, heading, and block resolution as the Link Graph without
/// publishing an outgoing or incoming link occurrence.
public struct LinkResolutionCatalog: Sendable {
    private let notesByID: [VaultQualifiedNoteID: LinkCatalogNote]
    private let index: LinkGraphBuilder.ResolutionIndex

    public init(catalog: [LinkCatalogNote]) {
        notesByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        index = LinkGraphBuilder.ResolutionIndex(catalog: catalog)
    }

    public func resolveNavigation(
        target: String,
        fragment: String?,
        from source: VaultQualifiedNoteID,
        scope: LinkResolutionScope = .sourceVault
    ) -> LinkNavigationResolution {
        let resolution = index.resolve(target, from: source, scope: scope)
        switch resolution {
        case .unresolved, .broken:
            return .missingNote
        case .ambiguous(let candidates):
            return .ambiguous(candidates)
        case .resolved(let id):
            guard let note = notesByID[id] else { return .missingNote }
            guard let fragment, !fragment.isEmpty else {
                return .resolved(
                    LinkDestination(note: id, kind: .note, fragment: nil, span: nil)
                )
            }
            if fragment.hasPrefix("^") {
                let key = String(fragment.dropFirst())
                guard let span = note.blockAnchors[key] else { return .missingBlock }
                return .resolved(
                    LinkDestination(note: id, kind: .block, fragment: fragment, span: span)
                )
            }

            let sought = LinkGraphBuilder.normalizedHeading(fragment)
            let matches = note.headings.filter {
                LinkGraphBuilder.normalizedHeading($0.text) == sought
            }
            guard matches.count == 1, let match = matches.first else {
                return matches.isEmpty ? .missingHeading : .ambiguousHeading
            }
            return .resolved(
                LinkDestination(note: id, kind: .heading, fragment: fragment, span: match.span)
            )
        }
    }
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
            }
            outgoing[source] = edges
        }

        return GraphSnapshot(
            contractVersion: GraphSnapshot.currentContractVersion,
            generation: generation,
            sourceManifestHash: sourceManifestHash,
            outgoing: outgoing,
            incoming: incoming,
            diagnostics: diagnostics.sorted(by: diagnosticOrder)
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

    struct ResolutionIndex: Sendable {
        private struct FolderStem: Hashable, Sendable {
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

    fileprivate static func normalizedHeading(_ value: String) -> String {
        normalizedLookupName(value.removingPercentEncoding ?? value)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func diagnosticOrder(_ lhs: LinkGraphDiagnostic, _ rhs: LinkGraphDiagnostic) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        return lhs.span.utf16LowerBound < rhs.span.utf16LowerBound
    }
}
