import Foundation

public struct IncomingLinkRewrite: Hashable, Sendable {
    public let source: VaultQualifiedNoteID
    public let expectedRevision: DocumentFingerprint
    public let updatedSource: String
    public let rewrittenOccurrences: Int

    public var relativePath: String { source.relativePath }

    public init(
        source: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint,
        updatedSource: String,
        rewrittenOccurrences: Int
    ) {
        self.source = source
        self.expectedRevision = expectedRevision
        self.updatedSource = updatedSource
        self.rewrittenOccurrences = rewrittenOccurrences
    }

}

public struct IncomingLinkRewritePlan: Hashable, Sendable {
    public let movedNote: VaultQualifiedNoteID
    public let destination: VaultQualifiedNoteID
    public let graphGeneration: Int
    public let rewrites: [IncomingLinkRewrite]
    public let blockedIncomingLinks: [IncomingLinkRewriteBlock]

    public init(
        movedNote: VaultQualifiedNoteID,
        destination: VaultQualifiedNoteID,
        graphGeneration: Int,
        rewrites: [IncomingLinkRewrite],
        blockedIncomingLinks: [IncomingLinkRewriteBlock] = []
    ) {
        self.movedNote = movedNote
        self.destination = destination
        self.graphGeneration = graphGeneration
        self.rewrites = rewrites
        self.blockedIncomingLinks = blockedIncomingLinks
    }
}

public struct IncomingLinkRewriteBlock: Codable, Hashable, Sendable {
    public let source: VaultQualifiedNoteID
    public let span: SourceSpan
    public let reason: String

    public init(source: VaultQualifiedNoteID, span: SourceSpan, reason: String) {
        self.source = source
        self.span = span
        self.reason = reason
    }
}

/// Plans exact-source incoming-link updates before a confirmed in-app move.
/// Only occurrences already resolved by the supplied workspace graph to the
/// moved vault-qualified note are changed. Broken and ambiguous links are never
/// guessed, and the writable source always comes from the exact NoteDocument.
public enum IncomingLinkRewriter {
    /// Plans link edits for one directory-path change while preserving note
    /// identity as the unit of movement. Every note move is evaluated against
    /// one future graph, so links between two notes in the moved folder are not
    /// rewritten against an intermediate, partly moved inventory.
    public static func folderPlan(
        documents: [VaultQualifiedNoteID: NoteDocument],
        graph: GraphSnapshot,
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        noteMoves: [FolderNoteMovePlan]
    ) -> FolderIncomingLinkRewritePlan {
        let empty = {
            FolderIncomingLinkRewritePlan(
                vaultID: vaultID,
                sourceFolder: sourceFolder,
                destinationFolder: destinationFolder,
                graphGeneration: graph.generation,
                noteMoves: noteMoves,
                rewrites: []
            )
        }
        guard graph.contractVersion == GraphSnapshot.currentContractVersion,
              noteMoves.allSatisfy({
                  $0.source.vaultID == vaultID
                    && $0.destination.vaultID == vaultID
                    && $0.source != $0.destination
              }) else { return empty() }

        var destinations: [VaultQualifiedNoteID: VaultQualifiedNoteID] = [:]
        for move in noteMoves {
            guard destinations.updateValue(move.destination, forKey: move.source) == nil else {
                return empty()
            }
        }
        let currentSemantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let currentCatalog = documents.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: currentSemantics[id])
        }
        let currentGraph = LinkGraphBuilder.build(
            generation: graph.generation,
            catalog: currentCatalog,
            documents: currentSemantics,
            resolutionScope: .workspace
        )

        let suppliedKeys: Set<EligibleOccurrenceKey> = Set(
            graph.outgoing.values.flatMap { $0 }.compactMap { edge in
            guard case .resolved(let target) = edge.occurrence.resolution,
                  destinations[target] != nil else { return nil }
            return EligibleOccurrenceKey(
                source: edge.source,
                syntax: edge.occurrence.syntax,
                target: edge.occurrence.target,
                span: edge.occurrence.linkSpan
            )
        })
        let incoming = currentGraph.outgoing.values.flatMap { $0 }.filter { edge in
            guard case .resolved(let target) = edge.occurrence.resolution,
                  destinations[target] != nil else { return false }
            let key = EligibleOccurrenceKey(
                source: edge.source,
                syntax: edge.occurrence.syntax,
                target: edge.occurrence.target,
                span: edge.occurrence.linkSpan
            )
            return suppliedKeys.contains(key)
        }

        var futureDocuments = documents
        for move in noteMoves {
            guard let moved = futureDocuments.removeValue(forKey: move.source) else { continue }
            futureDocuments[move.destination] = NoteDocument(
                relativePath: move.destination.relativePath,
                rawContent: moved.rawContent
            )
        }
        let futureSemantics = futureDocuments.mapValues(MarkdownSemanticDocument.init(parsing:))
        let futureCatalog = futureDocuments.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: futureSemantics[id])
        }
        let futureResolutionIndex = LinkGraphBuilder.ResolutionIndex(catalog: futureCatalog)

        var blocked: [IncomingLinkRewriteBlock] = []
        var replacementsBySource: [VaultQualifiedNoteID: [Replacement]] = [:]
        for edge in incoming {
            guard case .resolved(let currentTarget) = edge.occurrence.resolution,
                  let destination = destinations[currentTarget],
                  let document = documents[edge.source] else { continue }
            let futureSource = destinations[edge.source] ?? edge.source
            let resolution = futureResolutionIndex.resolve(
                destination.relativePath,
                from: futureSource,
                scope: .workspace
            )
            guard resolution == .resolved(destination) else {
                blocked.append(IncomingLinkRewriteBlock(
                    source: edge.source,
                    span: edge.occurrence.linkSpan,
                    reason: "The destination path would resolve this incoming link to another note or remain ambiguous."
                ))
                continue
            }
            guard let planned = replacement(
                for: edge.occurrence,
                in: document.rawContent,
                newRelativePath: destination.relativePath
            ) else { continue }
            replacementsBySource[edge.source, default: []].append(planned)
        }

        let rewrites = replacementsBySource.compactMap { sourceID, replacements
            -> IncomingLinkRewrite? in
            guard let document = documents[sourceID] else { return nil }
            let sorted = replacements.sorted { $0.range.location > $1.range.location }
            let mutable = NSMutableString(string: document.rawContent)
            var appliedRanges: Set<ReplacementKey> = []
            var applied = 0
            for planned in sorted {
                let key = ReplacementKey(
                    location: planned.range.location,
                    length: planned.range.length
                )
                guard appliedRanges.insert(key).inserted,
                      NSMaxRange(planned.range) <= mutable.length else { continue }
                mutable.replaceCharacters(in: planned.range, with: planned.text)
                applied += 1
            }
            guard applied > 0 else { return nil }
            return IncomingLinkRewrite(
                source: sourceID,
                expectedRevision: document.fingerprint,
                updatedSource: mutable as String,
                rewrittenOccurrences: applied
            )
        }.sorted { $0.source < $1.source }

        return FolderIncomingLinkRewritePlan(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            graphGeneration: graph.generation,
            noteMoves: noteMoves,
            rewrites: rewrites,
            blockedIncomingLinks: blocked.sorted {
                if $0.source != $1.source { return $0.source < $1.source }
                return $0.span.utf16LowerBound < $1.span.utf16LowerBound
            }
        )
    }

    /// Plans one coherent Folder relocation from the accepted Workspace
    /// source cohort without reparsing every note. The graph supplies only
    /// candidate incoming occurrences; exact candidate sources are reparsed
    /// and resolved against both the current and future catalogs. A caller
    /// must use the complete filesystem planner when this returns `nil`.
    public static func folderPlanUsingValidatedSnapshot(
        documents: [VaultQualifiedNoteID: NoteDocument],
        catalog: [LinkCatalogNote],
        graph: GraphSnapshot,
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        noteMoves: [FolderNoteMovePlan]
    ) -> FolderIncomingLinkRewritePlan? {
        let sourceManifestHash = SearchSourceManifest.hash(documents.map {
            id, document in
            SearchSourceManifestEntry(
                vaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            )
        })
        let sourcePrefix = sourceFolder.rawValue + "/"
        let destinationPrefix = destinationFolder.rawValue + "/"
        guard graph.contractVersion == GraphSnapshot.currentContractVersion,
              graph.sourceManifestHash == sourceManifestHash,
              catalog.count == documents.count,
              Set(catalog.map(\.id)) == Set(documents.keys),
              noteMoves.allSatisfy({ move in
                  move.source.vaultID == vaultID
                    && move.destination.vaultID == vaultID
                    && move.source.relativePath.hasPrefix(sourcePrefix)
                    && move.destination.relativePath
                        == destinationPrefix
                            + move.source.relativePath.dropFirst(sourcePrefix.count)
                    && documents[move.source]?.fingerprint == move.expectedRevision
              }),
              Set(noteMoves.map(\.source)).count == noteMoves.count,
              Set(noteMoves.map(\.destination)).count == noteMoves.count else {
            return nil
        }

        let destinations = Dictionary(uniqueKeysWithValues: noteMoves.map {
            ($0.source, $0.destination)
        })
        let suppliedKeys = Set(graph.outgoing.values.flatMap { $0 }.compactMap {
            edge -> EligibleOccurrenceKey? in
            guard case .resolved(let target) = edge.occurrence.resolution,
                  destinations[target] != nil else { return nil }
            return EligibleOccurrenceKey(
                source: edge.source,
                syntax: edge.occurrence.syntax,
                target: edge.occurrence.target,
                span: edge.occurrence.linkSpan
            )
        })
        guard !suppliedKeys.isEmpty else {
            return FolderIncomingLinkRewritePlan(
                vaultID: vaultID,
                sourceFolder: sourceFolder,
                destinationFolder: destinationFolder,
                graphGeneration: graph.generation,
                noteMoves: noteMoves,
                rewrites: []
            )
        }

        let currentResolutionIndex = LinkGraphBuilder.ResolutionIndex(
            catalog: catalog
        )
        var verifiedOccurrences: [VaultQualifiedNoteID: [(LinkOccurrence, VaultQualifiedNoteID)]] = [:]
        for sourceID in Set(suppliedKeys.map(\.source)).sorted() {
            guard let document = documents[sourceID] else { return nil }
            let semantic = MarkdownSemanticDocument(parsing: document)
            for occurrence in semantic.links where !occurrence.isExternal {
                guard case .resolved(let currentTarget) = currentResolutionIndex.resolve(
                    occurrence.target,
                    from: sourceID,
                    scope: .workspace
                ), destinations[currentTarget] != nil else { continue }
                let key = EligibleOccurrenceKey(
                    source: sourceID,
                    syntax: occurrence.syntax,
                    target: occurrence.target,
                    span: occurrence.linkSpan
                )
                guard suppliedKeys.contains(key) else { continue }
                verifiedOccurrences[sourceID, default: []].append((
                    occurrence,
                    currentTarget
                ))
            }
        }

        let futureCatalog = catalog.map { note in
            guard let destination = destinations[note.id] else { return note }
            return LinkCatalogNote(
                id: destination,
                title: note.title,
                aliases: note.aliases,
                headings: note.headings,
                blockAnchors: note.blockAnchors
            )
        }
        let futureResolutionIndex = LinkGraphBuilder.ResolutionIndex(
            catalog: futureCatalog
        )
        var blocked: [IncomingLinkRewriteBlock] = []
        var rewrites: [IncomingLinkRewrite] = []
        for sourceID in verifiedOccurrences.keys.sorted() {
            guard let document = documents[sourceID],
                  let occurrences = verifiedOccurrences[sourceID] else {
                return nil
            }
            let futureSource = destinations[sourceID] ?? sourceID
            var replacements: [Replacement] = []
            for (occurrence, currentTarget) in occurrences {
                guard let destination = destinations[currentTarget] else {
                    return nil
                }
                guard futureResolutionIndex.resolve(
                    destination.relativePath,
                    from: futureSource,
                    scope: .workspace
                ) == .resolved(destination) else {
                    blocked.append(IncomingLinkRewriteBlock(
                        source: sourceID,
                        span: occurrence.linkSpan,
                        reason: "The destination path would resolve this incoming link to another note or remain ambiguous."
                    ))
                    continue
                }
                if let planned = replacement(
                    for: occurrence,
                    in: document.rawContent,
                    newRelativePath: destination.relativePath
                ) {
                    replacements.append(planned)
                }
            }
            replacements.sort { $0.range.location > $1.range.location }
            guard !replacements.isEmpty else { continue }

            let mutable = NSMutableString(string: document.rawContent)
            var appliedRanges: Set<ReplacementKey> = []
            var applied = 0
            for replacement in replacements {
                let key = ReplacementKey(
                    location: replacement.range.location,
                    length: replacement.range.length
                )
                guard appliedRanges.insert(key).inserted,
                      NSMaxRange(replacement.range) <= mutable.length else { continue }
                mutable.replaceCharacters(in: replacement.range, with: replacement.text)
                applied += 1
            }
            guard applied > 0 else { continue }
            rewrites.append(IncomingLinkRewrite(
                source: sourceID,
                expectedRevision: document.fingerprint,
                updatedSource: mutable as String,
                rewrittenOccurrences: applied
            ))
        }

        return FolderIncomingLinkRewritePlan(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            graphGeneration: graph.generation,
            noteMoves: noteMoves,
            rewrites: rewrites.sorted { $0.source < $1.source },
            blockedIncomingLinks: blocked.sorted {
                if $0.source != $1.source { return $0.source < $1.source }
                return $0.span.utf16LowerBound < $1.span.utf16LowerBound
            }
        )
    }

    public static func plan(
        documents: [VaultQualifiedNoteID: NoteDocument],
        graph: GraphSnapshot,
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) -> IncomingLinkRewritePlan {
        guard source.vaultID == destination.vaultID else {
            return IncomingLinkRewritePlan(
                movedNote: source,
                destination: destination,
                graphGeneration: graph.generation,
                rewrites: [],
                blockedIncomingLinks: []
            )
        }

        guard graph.contractVersion == GraphSnapshot.currentContractVersion else {
            return IncomingLinkRewritePlan(
                movedNote: source,
                destination: destination,
                graphGeneration: graph.generation,
                rewrites: [],
                blockedIncomingLinks: []
            )
        }

        // Re-derive resolution from the exact documents supplied to the
        // planner. The persisted graph is a generation-bound input, but a
        // stale span must never be allowed to edit an unrelated current link.
        // An occurrence is eligible only when both graphs resolve the same
        // vault-qualified target at the same exact source span.
        let currentSemantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let currentCatalog = documents.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: currentSemantics[id])
        }
        let currentGraph = LinkGraphBuilder.build(
            generation: graph.generation,
            catalog: currentCatalog,
            documents: currentSemantics,
            resolutionScope: .workspace
        )
        let suppliedKeys = Set(graph.outgoing.values.flatMap { $0 }.compactMap { edge in
            eligibleKey(for: edge, resolvedTo: source)
        })

        // Use resolved occurrences rather than only the graph's `incoming`
        // destination index. A link can resolve to this note while carrying a
        // missing heading/block fragment, in which case the destination index
        // deliberately has no navigable target but the file path is still safe
        // and necessary to rewrite.
        let incoming = currentGraph.outgoing.values.flatMap { $0 }.filter { edge in
            guard let key = eligibleKey(for: edge, resolvedTo: source) else { return false }
            return suppliedKeys.contains(key)
        }

        var futureDocuments = documents
        if let moved = futureDocuments.removeValue(forKey: source) {
            futureDocuments[destination] = NoteDocument(
                relativePath: destination.relativePath,
                rawContent: moved.rawContent
            )
        }
        let futureSemantics = futureDocuments.mapValues(MarkdownSemanticDocument.init(parsing:))
        let futureCatalog = futureDocuments.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: futureSemantics[id])
        }
        let futureResolutionIndex = LinkGraphBuilder.ResolutionIndex(catalog: futureCatalog)
        var blocked: [IncomingLinkRewriteBlock] = []
        let safelyRewritable = incoming.filter { edge in
            let futureSource = edge.source == source ? destination : edge.source
            let resolution = futureResolutionIndex.resolve(
                destination.relativePath,
                from: futureSource,
                scope: .workspace
            )
            guard resolution == .resolved(destination) else {
                blocked.append(IncomingLinkRewriteBlock(
                    source: edge.source,
                    span: edge.occurrence.linkSpan,
                    reason: "The destination path would resolve this incoming link to another note or remain ambiguous."
                ))
                return false
            }
            return true
        }

        let rewrites = Dictionary(grouping: safelyRewritable, by: \.source)
            .compactMap { sourceID, edges -> IncomingLinkRewrite? in
                guard let document = documents[sourceID] else { return nil }
                let replacements = edges.compactMap { edge in
                    replacement(
                        for: edge.occurrence,
                        in: document.rawContent,
                        newRelativePath: destination.relativePath
                    )
                }.sorted { $0.range.location > $1.range.location }
                guard !replacements.isEmpty else { return nil }

                let mutable = NSMutableString(string: document.rawContent)
                var applied = 0
                for replacement in replacements {
                    guard NSMaxRange(replacement.range) <= mutable.length else { continue }
                    mutable.replaceCharacters(in: replacement.range, with: replacement.text)
                    applied += 1
                }
                guard applied > 0 else { return nil }
                return IncomingLinkRewrite(
                    source: sourceID,
                    expectedRevision: document.fingerprint,
                    updatedSource: mutable as String,
                    rewrittenOccurrences: applied
                )
            }
            .sorted { $0.source < $1.source }

        return IncomingLinkRewritePlan(
            movedNote: source,
            destination: destination,
            graphGeneration: graph.generation,
            rewrites: rewrites,
            blockedIncomingLinks: blocked.sorted {
                if $0.source != $1.source { return $0.source < $1.source }
                return $0.span.utf16LowerBound < $1.span.utf16LowerBound
            }
        )
    }

    /// Plans from one coherent Workspace source snapshot without rebuilding
    /// the complete graph. The supplied graph contributes only candidate
    /// occurrences; every candidate source is reparsed from its exact current
    /// NoteDocument and resolved again against the supplied current catalog.
    /// A caller must fall back to the complete planner when this method returns
    /// nil because its snapshot inputs are incomplete or structurally stale.
    public static func planUsingValidatedSnapshot(
        documents: [VaultQualifiedNoteID: NoteDocument],
        catalog: [LinkCatalogNote],
        graph: GraphSnapshot,
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) -> IncomingLinkRewritePlan? {
        let sourceManifestHash = SearchSourceManifest.hash(documents.map { id, document in
            SearchSourceManifestEntry(
                vaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            )
        })
        guard source.vaultID == destination.vaultID,
              graph.contractVersion == GraphSnapshot.currentContractVersion,
              graph.sourceManifestHash == sourceManifestHash,
              documents[source] != nil,
              catalog.count == documents.count,
              Set(catalog.map(\.id)) == Set(documents.keys) else { return nil }

        let suppliedKeys = Set(graph.outgoing.values.flatMap { $0 }.compactMap { edge in
            eligibleKey(for: edge, resolvedTo: source)
        })
        guard !suppliedKeys.isEmpty else {
            return IncomingLinkRewritePlan(
                movedNote: source,
                destination: destination,
                graphGeneration: graph.generation,
                rewrites: []
            )
        }

        let currentResolutionIndex = LinkGraphBuilder.ResolutionIndex(
            catalog: catalog
        )
        let candidateSourceIDs = Set(suppliedKeys.map(\.source))
        var verifiedOccurrences: [VaultQualifiedNoteID: [LinkOccurrence]] = [:]
        for sourceID in candidateSourceIDs.sorted() {
            guard let document = documents[sourceID] else { return nil }
            let semantic = MarkdownSemanticDocument(parsing: document)
            for occurrence in semantic.links where !occurrence.isExternal {
                guard currentResolutionIndex.resolve(
                    occurrence.target,
                    from: sourceID,
                    scope: .workspace
                ) == .resolved(source) else { continue }
                let key = EligibleOccurrenceKey(
                    source: sourceID,
                    syntax: occurrence.syntax,
                    target: occurrence.target,
                    span: occurrence.linkSpan
                )
                guard suppliedKeys.contains(key) else { continue }
                verifiedOccurrences[sourceID, default: []].append(occurrence)
            }
        }

        let futureCatalog = catalog.map { note in
            guard note.id == source else { return note }
            return LinkCatalogNote(
                id: destination,
                title: note.title,
                aliases: note.aliases,
                headings: note.headings,
                blockAnchors: note.blockAnchors
            )
        }
        let futureResolutionIndex = LinkGraphBuilder.ResolutionIndex(
            catalog: futureCatalog
        )
        var blocked: [IncomingLinkRewriteBlock] = []
        var rewrites: [IncomingLinkRewrite] = []
        for sourceID in verifiedOccurrences.keys.sorted() {
            guard let document = documents[sourceID],
                  let occurrences = verifiedOccurrences[sourceID] else {
                return nil
            }
            let futureSource = sourceID == source ? destination : sourceID
            var replacements: [Replacement] = []
            for occurrence in occurrences {
                guard futureResolutionIndex.resolve(
                    destination.relativePath,
                    from: futureSource,
                    scope: .workspace
                ) == .resolved(destination) else {
                    blocked.append(IncomingLinkRewriteBlock(
                        source: sourceID,
                        span: occurrence.linkSpan,
                        reason: "The destination path would resolve this incoming link to another note or remain ambiguous."
                    ))
                    continue
                }
                if let planned = replacement(
                    for: occurrence,
                    in: document.rawContent,
                    newRelativePath: destination.relativePath
                ) {
                    replacements.append(planned)
                }
            }
            replacements.sort { $0.range.location > $1.range.location }
            guard !replacements.isEmpty else { continue }

            let mutable = NSMutableString(string: document.rawContent)
            var applied = 0
            for replacement in replacements {
                guard NSMaxRange(replacement.range) <= mutable.length else { continue }
                mutable.replaceCharacters(in: replacement.range, with: replacement.text)
                applied += 1
            }
            guard applied > 0 else { continue }
            rewrites.append(IncomingLinkRewrite(
                source: sourceID,
                expectedRevision: document.fingerprint,
                updatedSource: mutable as String,
                rewrittenOccurrences: applied
            ))
        }

        return IncomingLinkRewritePlan(
            movedNote: source,
            destination: destination,
            graphGeneration: graph.generation,
            rewrites: rewrites,
            blockedIncomingLinks: blocked.sorted {
                if $0.source != $1.source { return $0.source < $1.source }
                return $0.span.utf16LowerBound < $1.span.utf16LowerBound
            }
        )
    }

    private struct Replacement {
        let range: NSRange
        let text: String
    }

    private struct ReplacementKey: Hashable {
        let location: Int
        let length: Int
    }

    private struct EligibleOccurrenceKey: Hashable {
        let source: VaultQualifiedNoteID
        let syntax: LinkSyntax
        let target: String
        let span: SourceSpan
    }

    private static func eligibleKey(
        for edge: LinkGraphEdge,
        resolvedTo destination: VaultQualifiedNoteID
    ) -> EligibleOccurrenceKey? {
        guard case .resolved(let resolved) = edge.occurrence.resolution,
              resolved == destination else { return nil }
        return EligibleOccurrenceKey(
            source: edge.source,
            syntax: edge.occurrence.syntax,
            target: edge.occurrence.target,
            span: edge.occurrence.linkSpan
        )
    }

    private static func replacement(
        for occurrence: LinkOccurrence,
        in source: String,
        newRelativePath: String
    ) -> Replacement? {
        let nsSource = source as NSString
        let occurrenceRange = occurrence.linkSpan.nsRange
        guard NSMaxRange(occurrenceRange) <= nsSource.length else { return nil }
        let raw = nsSource.substring(with: occurrenceRange) as NSString

        if occurrence.syntax == .markdown || (occurrence.syntax == .embed && raw.range(of: "](").location != NSNotFound) {
            return markdownReplacement(
                rawOccurrence: raw,
                occurrenceRange: occurrenceRange,
                newRelativePath: newRelativePath
            )
        }
        return wikilinkReplacement(
            rawOccurrence: raw,
            occurrenceRange: occurrenceRange,
            newRelativePath: newRelativePath
        )
    }

    private static func wikilinkReplacement(
        rawOccurrence: NSString,
        occurrenceRange: NSRange,
        newRelativePath: String
    ) -> Replacement? {
        let open = rawOccurrence.range(of: "[[")
        guard open.location != NSNotFound else { return nil }
        let targetStart = NSMaxRange(open)
        let tail = NSRange(location: targetStart, length: rawOccurrence.length - targetStart)
        let hash = rawOccurrence.range(of: "#", options: [], range: tail)
        let pipe = rawOccurrence.range(of: "|", options: [], range: tail)
        let close = rawOccurrence.range(of: "]]", options: [], range: tail)
        let candidates = [hash, pipe, close].filter { $0.location != NSNotFound }
        guard let end = candidates.map(\.location).min(), end >= targetStart else { return nil }
        let targetRange = NSRange(location: targetStart, length: end - targetStart)
        guard targetRange.length > 0 else { return nil }
        return Replacement(
            range: NSRange(
                location: occurrenceRange.location + targetRange.location,
                length: targetRange.length
            ),
            text: (newRelativePath as NSString).deletingPathExtension
        )
    }

    private static func markdownReplacement(
        rawOccurrence: NSString,
        occurrenceRange: NSRange,
        newRelativePath: String
    ) -> Replacement? {
        let marker = rawOccurrence.range(of: "](")
        guard marker.location != NSNotFound else { return nil }
        var targetStart = NSMaxRange(marker)
        while targetStart < rawOccurrence.length,
              UnicodeScalar(rawOccurrence.character(at: targetStart)).map(
                CharacterSet.whitespacesAndNewlines.contains
              ) == true {
            targetStart += 1
        }
        let tail = NSRange(location: targetStart, length: rawOccurrence.length - targetStart)
        let close = rawOccurrence.range(of: ")", options: [.backwards], range: tail)
        guard close.location != NSNotFound else { return nil }
        let hash = rawOccurrence.range(
            of: "#",
            options: [],
            range: NSRange(location: targetStart, length: close.location - targetStart)
        )
        let targetEnd = hash.location == NSNotFound ? close.location : hash.location
        guard targetEnd > targetStart else { return nil }

        let originalTarget = rawOccurrence.substring(
            with: NSRange(location: targetStart, length: targetEnd - targetStart)
        )
        let encoded = originalTarget.contains("%")
            ? percentEncodedMarkdownPath(newRelativePath)
            : newRelativePath
        return Replacement(
            range: NSRange(
                location: occurrenceRange.location + targetStart,
                length: targetEnd - targetStart
            ),
            text: encoded
        )
    }

    private static func percentEncodedMarkdownPath(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "#?()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}
