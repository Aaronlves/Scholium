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

    /// Compatibility initializer for the former single-vault planner.
    public init(
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        updatedSource: String,
        rewrittenOccurrences: Int
    ) {
        self.init(
            source: VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath),
            expectedRevision: expectedRevision,
            updatedSource: updatedSource,
            rewrittenOccurrences: rewrittenOccurrences
        )
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
        var blocked: [IncomingLinkRewriteBlock] = []
        let safelyRewritable = incoming.filter { edge in
            let futureSource = edge.source == source ? destination : edge.source
            let resolution = LinkGraphBuilder.resolve(
                destination.relativePath,
                from: futureSource,
                catalog: futureCatalog,
                scope: .workspace
            )
            guard resolution == .resolved(destination) else {
                blocked.append(IncomingLinkRewriteBlock(
                    source: edge.source,
                    span: edge.occurrence.span,
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

    /// Compatibility planner for a standalone vault. New Triptych callers
    /// must pass the workspace graph so cross-vault incoming links participate.
    public static func plan(
        vaultID: UUID,
        documents: [NoteDocument],
        moving oldRelativePath: String,
        to newRelativePath: String
    ) -> [IncomingLinkRewrite] {
        let qualified = Dictionary(uniqueKeysWithValues: documents.map { document in
            (VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath), document)
        })
        let semantics = qualified.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = qualified.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
        }
        let graph = LinkGraphBuilder.build(
            generation: 0,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .sourceVault
        )
        return plan(
            documents: qualified,
            graph: graph,
            moving: VaultQualifiedNoteID(vaultID: vaultID, relativePath: oldRelativePath),
            to: VaultQualifiedNoteID(vaultID: vaultID, relativePath: newRelativePath)
        ).rewrites
    }

    private struct Replacement {
        let range: NSRange
        let text: String
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
            span: edge.occurrence.span
        )
    }

    private static func replacement(
        for occurrence: LinkOccurrence,
        in source: String,
        newRelativePath: String
    ) -> Replacement? {
        let nsSource = source as NSString
        let occurrenceRange = occurrence.span.nsRange
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
