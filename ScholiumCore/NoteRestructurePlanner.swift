import Foundation
import ScholiumContracts

/// Plans against complete exact sources. No derived representation reconstructs writable Markdown.
public enum NoteRestructurePlanner {
    public static func prepare(_ request: NoteRestructureRequest, documents: [VaultQualifiedNoteID: NoteDocument], graph: GraphSnapshot) throws
        -> NoteRestructurePreview
    {
        let sourceID = request.source.documentID
        guard let source = documents[sourceID], source.fingerprint == request.source.revision else {
            throw unavailable("The source note changed. Reopen the operation from its current revision.")
        }
        let destination: VaultQualifiedNoteID
        let target: NoteDocument
        switch request.destination {
        case .existing(let identity):
            destination = identity.documentID
            guard let existing = documents[destination], existing.fingerprint == identity.revision else {
                throw unavailable("The destination note changed. Select its current revision.")
            }
            target = existing
        case .newNote(let path):
            destination = VaultQualifiedNoteID(vaultID: sourceID.vaultID, relativePath: path)
            guard documents[destination] == nil, request.operation != .merge else {
                throw unavailable("Choose an unoccupied new note path, or an existing note for a merge.")
            }
            target = NoteDocument(relativePath: path, rawContent: "")
        }
        guard sourceID != destination, sourceID.vaultID == destination.vaultID else {
            throw unavailable("Choose a different note in the same vault.")
        }
        guard source.hasProvableBodyBoundary, target.hasProvableBodyBoundary else {
            throw unavailable("Close the YAML frontmatter before reorganizing body content.")
        }
        let semantic = MarkdownSemanticDocument(parsing: source)
        let range: Range<Int>
        if request.operation == .merge {
            // The UTF-8 BOM belongs to the original file encoding, not to the body inserted into another file.
            let bodyStart =
                source.rawFrontmatter != nil ? source.bodyByteRange.lowerBound : source.rawContent.hasPrefix("\u{FEFF}") ? 3 : source.bodyByteRange.lowerBound
            range = bodyStart..<source.bodyByteRange.upperBound
        } else {
            guard let selection = request.selectionUTF8, !selection.isEmpty,
                selection.lowerBound >= source.bodyByteRange.lowerBound,
                selection.upperBound <= source.bodyByteRange.upperBound
            else { throw unavailable("Select complete body paragraphs before reorganizing them.") }
            range = selection
            guard
                semantic.mathExpressions.filter({ $0.kind == .display }).allSatisfy({
                    !range.overlaps($0.span.utf8Range) || NoteRestructureDependencies.contains(range, $0.span.utf8Range)
                })
            else { throw unavailable("Select the complete display mathematics block.") }
            let touched = semantic.blocks.filter { $0.span.utf8Range.overlaps(range) }
            guard !touched.isEmpty,
                touched.allSatisfy({
                    range.lowerBound <= $0.span.utf8LowerBound && range.upperBound >= $0.span.utf8UpperBound

                })
            else { throw unavailable("Select complete Markdown blocks. A selection cannot split a list, quotation, or protected construct.") }
        }
        let originalFragment = try slice(source.rawContent, range)
        guard request.operation == .merge || !originalFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw unavailable("There is no body content to reorganize.")
        }
        let dependencies = try NoteRestructureDependencies.prepare(source: source, target: target, selection: range, operation: request.operation)
        let transferRanges = dependencies.ranges
        let transferSource = try dependencies.fragment(source: source.rawContent)
        func transferred(_ span: Range<Int>) -> Bool { transferRanges.contains { NoteRestructureDependencies.contains($0, span) } }
        let sourceMarkdown = try NoteRestructureMarkdownLinks(source)
        guard !sourceMarkdown.unsupportedDefinitions.contains(where: { span in transferRanges.contains { $0.overlaps(span) } }) else {
            throw unavailable("A selected nested or multiline reference definition needs source reconciliation before reorganization.")
        }
        // A definition is declaration source, not visible paragraph content. Converted occurrences
        // become self-contained inline links, preventing destination shortcuts from changing meaning.
        var removedReferenceDefinitions: [Range<Int>] = []
        for definition in sourceMarkdown.definitions where transferRanges.contains(where: { $0.overlaps(definition) }) {
            guard transferred(definition) else { throw unavailable("Select the complete reference-link definition, including its line ending.") }
            removedReferenceDefinitions.append(definition)
        }

        let allAnchors = ParagraphAnchorPlanner.anchors(in: source)
        let anchors = allAnchors.filter { range.overlaps($0.paragraphSpan.utf8Range) }
        let targetAnchors = ParagraphAnchorPlanner.anchors(in: target)
        let anchorIDs = anchors.map(\.id)
        guard
            anchors.allSatisfy({ anchor in
                allAnchors.filter { $0.id == anchor.id }.count == 1
                    && range.lowerBound <= anchor.paragraphSpan.utf8LowerBound && range.upperBound >= anchor.paragraphSpan.utf8UpperBound
            }),
            Set(anchorIDs).count == anchorIDs.count,
            request.operation == .copy || Set(anchorIDs).isDisjoint(with: targetAnchors.map(\.id))
        else {
            throw unavailable("A paragraph identifier is repeated in the source or destination. Resolve the duplicate identifiers before moving content.")
        }
        var replacements: [VaultQualifiedNoteID: [AgentSourceEdit]] = [:]
        if request.operation == .merge {
            replacements[destination] = try NoteRestructureFrontmatterPlanner.edits(source: source, target: target, resolutions: request.propertyResolutions)
        }
        replacements[sourceID, default: []].append(contentsOf: dependencies.sourceEdits)
        var fragmentEdits = try dependencies.edits.map { try dependencies.mapped($0) }
        for definition in removedReferenceDefinitions {
            fragmentEdits.append(try dependencies.mapped(NoteRestructureDependencies.edit(source.rawContent, definition, "")))
        }
        var resultingIDs = anchorIDs
        var copiedIDs: [String: String] = [:]
        if request.operation == .copy {
            for anchor in anchors {
                let newID = "p-" + String(DocumentFingerprint(data: Data((request.id.uuidString + anchor.id).utf8)).sha256.prefix(16))
                guard !targetAnchors.contains(where: { $0.id == newID }) else {
                    throw unavailable("The copied paragraph identifier is already present. Start a new copy operation.")
                }
                copiedIDs[anchor.id] = newID
                fragmentEdits.append(try dependencies.mapped(NoteRestructureDependencies.edit(source.rawContent, anchor.markerSpan.utf8Range, "^" + newID)))
            }
            resultingIDs = anchorIDs.compactMap { copiedIDs[$0] }
        }
        let movedIDs = Set(anchorIDs)
        let navigation = LinkResolutionCatalog(catalog: documents.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) })
        func fragmentMoves(_ fragment: String) -> Bool {
            if fragment.hasPrefix("^") { return movedIDs.contains(String(fragment.dropFirst())) }
            if case .resolved(let resolved) = navigation.resolveNavigation(target: sourceID.relativePath, fragment: fragment, from: sourceID, scope: .workspace),
                let span = resolved.span
            {
                return semantic.blocks.contains { $0.kind == .heading && $0.span.utf8LowerBound == span.utf8LowerBound && transferred($0.span.utf8Range) }
            }
            return false
        }
        // Build future locations solely to prove resolution of each replacement destination.
        var futureCatalog = documents.filter { request.operation != .merge || $0.key != sourceID }.map {
            LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value)
        }
        if documents[destination] == nil { futureCatalog.append(LinkCatalogNote(vaultID: destination.vaultID, document: target)) }
        for edges in graph.outgoing.values {
            for edge in edges {
                let occurrence = edge.occurrence
                if let owner = documents[edge.source],
                    NoteRestructureDependencies.literalRanges(in: owner, semantic: MarkdownSemanticDocument(parsing: owner))
                        .contains(where: { $0.overlaps(occurrence.span.utf8Range) })
                {
                    continue
                }
                // Markdown occurrences use the parser-backed path below, including reference syntax.
                let authored = try documents[edge.source].map { try slice($0.rawContent, occurrence.linkSpan.utf8Range) } ?? ""
                guard authored.hasPrefix("[[") || authored.hasPrefix("![[") else { continue }
                let inFragment = edge.source == sourceID && transferred(occurrence.span.utf8Range)
                guard !occurrence.isExternal else { continue }
                guard case .resolved(let resolved) = occurrence.resolution else {
                    if inFragment { throw unavailable("A selected note link is unresolved or ambiguous. Resolve it before moving the content.") }
                    continue
                }
                let movedReference =
                    resolved == sourceID
                    && (request.operation == .merge || occurrence.fragment.map { fragmentMoves($0) } == true)
                let followsMovedTarget = movedReference && (request.operation != .copy || inFragment)
                guard inFragment || followsMovedTarget else { continue }
                // A removed source is not separately rewritten; its fragment receives the edit.
                let intendedTarget = followsMovedTarget ? destination : resolved
                let futureSource = inFragment ? destination : edge.source
                guard
                    LinkGraphBuilder.resolve(intendedTarget.relativePath, from: futureSource, catalog: futureCatalog, scope: .workspace)
                        == .resolved(intendedTarget)
                else {
                    throw unavailable("A link cannot identify its destination unambiguously after reorganization.")
                }
                var fragment = occurrence.fragment
                if inFragment, request.operation == .copy, resolved == sourceID,
                    let old = fragment, old.hasPrefix("^"), let new = copiedIDs[String(old.dropFirst())]
                {
                    fragment = "^" + new
                }
                guard let owner = documents[edge.source] else { throw unavailable("A link source is no longer available.") }
                let edit = try linkEdit(occurrence, source: owner.rawContent, target: intendedTarget.relativePath, fragment: fragment)
                if inFragment {
                    fragmentEdits.append(try dependencies.mapped(edit))
                } else if !(request.operation == .merge && edge.source == sourceID) {
                    replacements[edge.source, default: []].append(edit)
                }
            }
        }
        let catalog = documents.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) }
        for (ownerID, owner) in documents {
            let markdown = ownerID == sourceID ? sourceMarkdown : try NoteRestructureMarkdownLinks(owner)
            for link in markdown.occurrences {
                let inFragment = ownerID == sourceID && transferred(link.range)
                if inFragment, !link.isImage, link.raw.contains("!["),
                    (sourceID.relativePath as NSString).deletingLastPathComponent != (destination.relativePath as NSString).deletingLastPathComponent
                {
                    throw unavailable("A linked image needs separate source reconciliation before moving it between folders.")
                }
                if removedReferenceDefinitions.contains(where: { ownerID == sourceID && $0.overlaps(link.range) }) { continue }
                if link.raw.hasPrefix("[^") { continue }
                let components = link.destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                let path = String(components[0])
                var suffix = components.count > 1 ? String(components[1]) : nil
                let isExternal = URLComponents(string: path)?.scheme != nil || path.hasPrefix("//") || path.hasPrefix("/")
                var newDestination = link.destination
                var needsRewrite = inFragment && link.isReference
                if !isExternal, let file = SourceResourceReferences.file(destination: path, noteRelativePath: ownerID.relativePath, isImage: link.isImage),
                    let relative = file.relativePath, inFragment
                {
                    let relocatedPath = relativeResourcePath(relative.rawValue, from: destination.relativePath)
                    var pathCharacters = CharacterSet.urlPathAllowed
                    pathCharacters.remove(charactersIn: "#%? \"<>\\\r\n()")
                    guard let relocated = relocatedPath.addingPercentEncoding(withAllowedCharacters: pathCharacters),
                        SourceResourceReferences.file(destination: relocated, noteRelativePath: destination.relativePath, isImage: link.isImage)?.relativePath
                            == relative
                    else { throw unavailable("A relative resource link cannot retain its exact file target after reorganization.") }
                    newDestination = relocated + (suffix.map { "#" + $0 } ?? "")
                    needsRewrite = needsRewrite || newDestination != link.destination
                } else if !isExternal {
                    let resolution = LinkGraphBuilder.resolve(path.removingPercentEncoding ?? path, from: ownerID, catalog: catalog, scope: .workspace)
                    guard case .resolved(let resolved) = resolution else {
                        if inFragment { throw unavailable("A selected link is unresolved or ambiguous. Resolve it before reorganizing the content.") }
                        continue
                    }
                    let follows =
                        resolved == sourceID && (request.operation == .merge || suffix.map(fragmentMoves) == true)
                        && (request.operation != .copy || inFragment)
                    guard inFragment || follows else { continue }
                    let intended = follows ? destination : resolved
                    let futureSource = inFragment ? destination : ownerID
                    guard LinkGraphBuilder.resolve(intended.relativePath, from: futureSource, catalog: futureCatalog, scope: .workspace) == .resolved(intended)
                    else {
                        throw unavailable("A Markdown link cannot identify its intended destination after reorganization.")
                    }
                    if inFragment, request.operation == .copy, resolved == sourceID, let old = suffix, old.hasPrefix("^"),
                        let fresh = copiedIDs[String(old.dropFirst())]
                    {
                        suffix = "^" + fresh
                    }
                    newDestination = intended.relativePath + (suffix.map { "#" + $0 } ?? "")
                    needsRewrite = true
                }
                guard needsRewrite else { continue }
                if !link.isImage && link.raw.contains("![") { throw unavailable("A linked image needs separate source reconciliation before reorganization.") }
                let edit = try NoteRestructureDependencies.edit(owner.rawContent, link.range, link.replacingDestination(newDestination))
                if inFragment {
                    fragmentEdits.append(try dependencies.mapped(edit))
                } else if !(request.operation == .merge && ownerID == sourceID) {
                    replacements[ownerID, default: []].append(edit)
                }
            }
        }
        var fragment = fragmentEdits.isEmpty ? transferSource : try AgentSourceEdit.applying(fragmentEdits, to: Data(transferSource.utf8))
        if request.operation == .move && anchors.isEmpty {
            let identifier = "p-" + String(request.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))
            let temporary = NoteDocument(relativePath: source.relativePath, rawContent: fragment)
            let temporarySemantic = MarkdownSemanticDocument(parsing: temporary)
            let eligible = temporarySemantic.blocks.first { candidate in
                candidate.kind == .paragraph
                    && !temporarySemantic.footnoteDefinitions.contains { $0.span.utf8Range.overlaps(candidate.span.utf8Range) }
                    && !temporarySemantic.mathExpressions.contains { $0.kind == .display && $0.span.utf8Range.overlaps(candidate.span.utf8Range) }
                    && !temporarySemantic.blocks.contains {
                        $0.kind != .paragraph && $0.span.utf8Range.overlaps(candidate.span.utf8Range)
                    }
            }
            if let firstParagraph = eligible {
                let plan = try ParagraphAnchorPlanner.ensureAnchor(in: temporary, atUTF16: firstParagraph.span.utf16LowerBound, id: identifier)
                fragment = plan.candidateSource
                resultingIDs.insert(plan.anchorID, at: 0)
            }
        }
        let newline = target.rawContent.contains("\r\n") ? "\r\n" : "\n"
        let separator =
            target.rawContent.isEmpty || target.rawContent.hasSuffix(newline + newline)
            ? "" : target.rawContent.hasSuffix(newline) ? newline : newline + newline
        if !fragment.isEmpty {
            let pending = replacements[destination] ?? []
            let destinationBeforeAppend = pending.isEmpty ? target.rawContent : try AgentSourceEdit.applying(pending, to: Data(target.rawContent.utf8))
            fragment = try NoteRestructureMarkdownLinks.isolatingReferences(
                in: fragment, after: destinationBeforeAppend + separator, path: destination.relativePath)
            let insertion = separator + fragment
            replacements[destination, default: []].append(
                AgentSourceEdit(startUTF8: target.rawContent.utf8.count, endUTF8: target.rawContent.utf8.count, expectedText: "", replacement: insertion))
        }
        if request.operation == .move {
            let targetPath = (destination.relativePath as NSString).deletingPathExtension
            guard !targetPath.contains(where: { "[]|#\r\n".contains($0) }) else {
                throw unavailable("Choose a destination filename that can be represented in a note link.")
            }
            let fragmentSuffix = resultingIDs.first.map { "#^" + $0 } ?? ""
            var replacement = "[[" + targetPath + fragmentSuffix + "]]"
            var retained = dependencies.retainedDefinitions
            for definition in removedReferenceDefinitions {
                let raw = try slice(source.rawContent, definition)
                if !retained.isEmpty { retained += newline + newline }
                retained += raw
            }
            if !retained.isEmpty { replacement += newline + newline + retained }
            replacements[sourceID, default: []].append(
                AgentSourceEdit(startUTF8: range.lowerBound, endUTF8: range.upperBound, expectedText: originalFragment, replacement: replacement))
        }
        var edits: [NoteRestructureFileEdit] = []
        for (id, sourceEdits) in replacements where !sourceEdits.isEmpty {
            let before = documents[id]?.rawContent
            var combined: [AgentSourceEdit] = []
            for edit in sourceEdits {
                if edit.startUTF8 == edit.endUTF8,
                    let index = combined.firstIndex(where: { $0.startUTF8 == edit.startUTF8 && $0.endUTF8 == edit.endUTF8 })
                {
                    let previous = combined[index]
                    combined[index] = AgentSourceEdit(
                        startUTF8: edit.startUTF8, endUTF8: edit.endUTF8, expectedText: "", replacement: previous.replacement + edit.replacement)
                } else {
                    combined.append(edit)
                }
            }
            let updated = try AgentSourceEdit.applying(combined, to: Data((before ?? "").utf8))
            if before != updated { edits.append(NoteRestructureFileEdit(note: id, before: before, after: updated)) }
        }
        if request.operation == .merge { edits.append(NoteRestructureFileEdit(note: sourceID, before: source.rawContent, after: nil)) }
        var finalDocuments = documents
        for edit in edits {
            finalDocuments[edit.note] = edit.after.map { NoteDocument(relativePath: edit.note.relativePath, rawContent: $0) }
        }
        if !fragment.isEmpty, let combined = finalDocuments[destination] {
            let boundary = combined.rawContent.utf8.count - fragment.utf8.count
            let literals = NoteRestructureDependencies.literalRanges(in: combined, semantic: MarkdownSemanticDocument(parsing: combined))
            guard !literals.contains(where: { $0.lowerBound < boundary && $0.upperBound > boundary }) else {
                throw unavailable("Close the destination's code, HTML, comment, or mathematics block before appending note content.")
            }
        }
        let finalGraph = LinkGraphBuilder.build(
            generation: graph.generation + 1, catalog: finalDocuments.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) },
            documents: finalDocuments.mapValues(MarkdownSemanticDocument.init(parsing:)), resolutionScope: .workspace)
        // Fragment validity is checked against the final combined source, including duplicate headings.
        // Existing unrelated diagnostics are not silently repaired or used to authorize a rewrite.
        let finalCatalog = finalDocuments.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) }
        let finalNavigation = LinkResolutionCatalog(catalog: finalCatalog)
        let finalMarkdown = try finalDocuments.mapValues { try NoteRestructureMarkdownLinks($0) }
        // The legacy graph's lexical Markdown matcher does not parse titles/reference forms.
        // A parser-proven occurrence is checked with its actual destination instead.
        for diagnostic in finalGraph.diagnostics {
            if let owner = finalDocuments[diagnostic.source],
                NoteRestructureDependencies.literalRanges(in: owner, semantic: MarkdownSemanticDocument(parsing: owner))
                    .contains(where: { $0.overlaps(diagnostic.span.utf8Range) })
            {
                continue
            }
            if let link = finalMarkdown[diagnostic.source]?.occurrences.first(where: { $0.range.overlaps(diagnostic.span.utf8Range) }),
                markdownDestinationValid(link, owner: diagnostic.source, navigation: finalNavigation)
            {
                continue
            }
            let priorCount = graph.diagnostics.filter { $0.source == diagnostic.source && $0.code == diagnostic.code && $0.target == diagnostic.target }.count
            let finalCount = finalGraph.diagnostics.filter { $0.source == diagnostic.source && $0.code == diagnostic.code && $0.target == diagnostic.target }
                .count
            if finalCount > priorCount {
                throw unavailable(
                    "Reorganization would introduce a missing or ambiguous reference in \(diagnostic.source.relativePath). Reconcile that reference or duplicate target first."
                )
            }
        }
        for (id, markdown) in finalMarkdown {
            let prior = try documents[id].map { try NoteRestructureMarkdownLinks($0) }
            let failures = markdown.occurrences.filter { !markdownDestinationValid($0, owner: id, navigation: finalNavigation) }
            for link in failures {
                let beforeCount =
                    prior?.occurrences.filter { $0.destination == link.destination && !markdownDestinationValid($0, owner: id, navigation: navigation) }.count
                    ?? 0
                guard failures.filter({ $0.destination == link.destination }).count <= beforeCount else {
                    throw unavailable("Reorganization would leave a missing or ambiguous Markdown reference in \(id.relativePath).")
                }
            }
        }
        edits.sort { lhs, rhs in
            if (lhs.after == nil) != (rhs.after == nil) { return lhs.after != nil }
            if (lhs.note == destination) != (rhs.note == destination) { return lhs.note == destination }
            return lhs.note < rhs.note
        }
        return NoteRestructurePreview(
            request: request, destination: destination, edits: edits, movedAnchorIDs: resultingIDs, observedRevisions: documents.mapValues(\.fingerprint))
    }

    private static func markdownDestinationValid(
        _ link: NoteRestructureMarkdownLinks.Occurrence, owner: VaultQualifiedNoteID, navigation: LinkResolutionCatalog
    ) -> Bool {
        if link.raw.hasPrefix("[^") { return true }
        let parts = link.destination.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        if URLComponents(string: path)?.scheme != nil || path.hasPrefix("//") || path.hasPrefix("/") { return true }
        if SourceResourceReferences.file(destination: path, noteRelativePath: owner.relativePath, isImage: link.isImage) != nil { return true }
        if case .resolved = navigation.resolveNavigation(
            target: path.removingPercentEncoding ?? path, fragment: parts.count > 1 ? String(parts[1]) : nil, from: owner, scope: .workspace)
        {
            return true
        }
        return false
    }

    private static func relativeResourcePath(_ path: String, from note: String) -> String {
        let target = path.split(separator: "/").map(String.init)
        let directory = note.split(separator: "/").dropLast().map(String.init)
        var shared = 0
        while shared < min(target.count, directory.count), target[shared] == directory[shared] { shared += 1 }
        return (Array(repeating: "..", count: directory.count - shared) + target.dropFirst(shared)).joined(separator: "/")
    }

    private static func slice(_ source: String, _ range: Range<Int>) throws -> String {
        let bytes = Array(source.utf8)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count,
            let text = String(bytes: bytes[range], encoding: .utf8)
        else { throw unavailable("The selected source range is no longer valid UTF-8.") }
        return text
    }

    private static func linkEdit(_ occurrence: LinkOccurrence, source: String, target: String, fragment: String?) throws -> AgentSourceEdit {
        let raw = try slice(source, occurrence.linkSpan.utf8Range)
        let replacement: String
        if raw.contains("[["), let start = raw.range(of: "[["), let close = raw.range(of: "]]", options: .backwards) {
            let middle = raw[start.upperBound..<close.lowerBound]
            let alias = middle.firstIndex(of: "|").map { String(middle[$0...]) } ?? ""
            let path = (target as NSString).deletingPathExtension
            guard !path.contains(where: { "[]|#\r\n".contains($0) }) else { throw unavailable("A note path cannot be represented safely as a Wikilink.") }
            replacement = String(raw[..<start.upperBound]) + path + (fragment.map { "#" + $0 } ?? "") + alias + String(raw[close.lowerBound...])
        } else {
            throw unavailable("A link occurrence cannot be safely rewritten in its authored syntax.")
        }
        return AgentSourceEdit(
            startUTF8: occurrence.linkSpan.utf8LowerBound, endUTF8: occurrence.linkSpan.utf8UpperBound, expectedText: raw, replacement: replacement)
    }

    private static func unavailable(_ detail: String) -> NoteRestructureError { .unavailable(detail) }
}
