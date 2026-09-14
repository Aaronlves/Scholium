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
        let semantic = MarkdownSemanticDocument(parsing: source)
        let range: Range<Int>
        if request.operation == .merge {
            guard source.rawFrontmatter?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                throw unavailable("This note has YAML properties. Reconcile those properties before merging its complete contents.")
            }
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
            let touched = semantic.blocks.filter { $0.span.utf8Range.overlaps(range) }
            guard !touched.isEmpty,
                touched.allSatisfy({
                    range.lowerBound <= $0.span.utf8LowerBound && range.upperBound >= $0.span.utf8UpperBound
                        && $0.kind == .paragraph
                })
            else { throw unavailable("Select complete ordinary paragraphs. Partial or nested constructs must be reorganized in Source.") }
        }
        let originalFragment = try slice(source.rawContent, range)
        guard !originalFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw unavailable("There is no body content to reorganize.")
        }
        let targetSemantic = MarkdownSemanticDocument(parsing: target)
        let movedDefinitions = semantic.footnoteDefinitions.filter { range.overlaps($0.span.utf8Range) && !$0.isInline }
        let movedReferences = semantic.footnoteReferences.filter { range.overlaps($0.span.utf8Range) && !$0.isInline }
        let definitionIDs = Set(movedDefinitions.map(\.identifier))
        guard movedDefinitions.allSatisfy({ range.lowerBound <= $0.span.utf8LowerBound && range.upperBound >= $0.span.utf8UpperBound }),
            movedReferences.allSatisfy({ definitionIDs.contains($0.identifier) }),
            definitionIDs.isDisjoint(with: targetSemantic.footnoteDefinitions.filter { !$0.isInline }.map(\.identifier)),
            request.operation == .copy
                || semantic.footnoteReferences.allSatisfy({ $0.isInline || range.overlaps($0.span.utf8Range) || !definitionIDs.contains($0.identifier) })
        else {
            throw unavailable(
                "The selection has footnote dependencies or identifiers that conflict with the destination. Move each reference with its definition and reconcile duplicate identifiers first."
            )
        }
        // Reference-style links depend on definitions outside the parsed occurrence. Do not silently strand them.
        if originalFragment.range(of: #"(?m)^ {0,3}\[[^\]^]+\]:|\]\s*\[[^\]]*\]"#, options: .regularExpression) != nil {
            throw unavailable("Reference-style links require their definitions to be reconciled before reorganization.")
        }
        let referenceDefinitions = try NSRegularExpression(pattern: #"(?m)^ {0,3}\[([^\]^]+)\]:"#)
        let nsSource = source.rawContent as NSString
        for match in referenceDefinitions.matches(in: source.rawContent, range: NSRange(location: 0, length: nsSource.length)) {
            let label = nsSource.substring(with: match.range(at: 1))
            if originalFragment.range(of: "[" + label + "]", options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                throw unavailable("The selection depends on a shortcut link definition. Convert that reference to an inline link before reorganizing it.")
            }
        }
        let sourceDirectory = (sourceID.relativePath as NSString).deletingLastPathComponent
        let destinationDirectory = (destination.relativePath as NSString).deletingLastPathComponent
        if sourceDirectory != destinationDirectory,
            SourceResourceReferences.files(in: originalFragment, noteRelativePath: sourceID.relativePath).contains(where: { $0.relativePath != nil })
        {
            throw unavailable(
                "The selected content has relative file or image links. Choose a note in the same folder, or convert those links before moving the content.")
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
        var fragmentEdits: [AgentSourceEdit] = []
        var resultingIDs = anchorIDs
        var copiedIDs: [String: String] = [:]
        if request.operation == .copy {
            for anchor in anchors {
                let newID = "p-" + String(DocumentFingerprint(data: Data((request.id.uuidString + anchor.id).utf8)).sha256.prefix(16))
                guard !targetAnchors.contains(where: { $0.id == newID }) else {
                    throw unavailable("The copied paragraph identifier is already present. Start a new copy operation.")
                }
                copiedIDs[anchor.id] = newID
                fragmentEdits.append(try relativeEdit(source: source.rawContent, span: anchor.markerSpan.utf8Range, fragment: range, replacement: "^" + newID))
            }
            resultingIDs = anchorIDs.compactMap { copiedIDs[$0] }
        }
        let movedIDs = Set(anchorIDs)
        // Build future locations solely to prove resolution of each replacement destination.
        var futureCatalog = documents.filter { request.operation != .merge || $0.key != sourceID }.map {
            LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value)
        }
        if documents[destination] == nil { futureCatalog.append(LinkCatalogNote(vaultID: destination.vaultID, document: target)) }
        for edges in graph.outgoing.values {
            for edge in edges {
                let occurrence = edge.occurrence
                let inFragment = edge.source == sourceID && range.overlaps(occurrence.span.utf8Range)
                if inFragment {
                    let authored = try slice(source.rawContent, occurrence.linkSpan.utf8Range)
                    if authored.hasPrefix("["), !authored.contains("]("), !authored.contains("[[") {
                        throw unavailable(
                            "The selection depends on a reference-style link definition. Convert that reference to an inline link before reorganizing it.")
                    }
                }
                guard !occurrence.isExternal else { continue }
                guard case .resolved(let resolved) = occurrence.resolution else {
                    if inFragment { throw unavailable("A selected note link is unresolved or ambiguous. Resolve it before moving the content.") }
                    continue
                }
                let movedReference =
                    resolved == sourceID
                    && (request.operation == .merge || occurrence.fragment.map { $0.hasPrefix("^") && movedIDs.contains(String($0.dropFirst())) } == true)
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
                    fragmentEdits.append(
                        AgentSourceEdit(
                            startUTF8: edit.startUTF8 - range.lowerBound, endUTF8: edit.endUTF8 - range.lowerBound, expectedText: edit.expectedText,
                            replacement: edit.replacement))
                } else if !(request.operation == .merge && edge.source == sourceID) {
                    replacements[edge.source, default: []].append(edit)
                }
            }
        }
        var fragment = fragmentEdits.isEmpty ? originalFragment : try AgentSourceEdit.applying(fragmentEdits, to: Data(originalFragment.utf8))
        if request.operation == .move
            && (anchors.first?.paragraphSpan.utf8LowerBound != semantic.blocks.first(where: { range.overlaps($0.span.utf8Range) })?.span.utf8LowerBound)
        {
            let identifier = "p-" + String(request.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16))
            let temporary = NoteDocument(relativePath: source.relativePath, rawContent: fragment)
            guard let firstParagraph = MarkdownSemanticDocument(parsing: temporary).blocks.first(where: { $0.kind == .paragraph }) else {
                throw unavailable("The selected content has no ordinary paragraph.")
            }
            let plan = try ParagraphAnchorPlanner.ensureAnchor(in: temporary, atUTF16: firstParagraph.span.utf16LowerBound, id: identifier)
            fragment = plan.candidateSource
            resultingIDs.insert(plan.anchorID, at: 0)
        }
        let newline = target.rawContent.contains("\r\n") ? "\r\n" : "\n"
        let separator =
            target.rawContent.isEmpty || target.rawContent.hasSuffix(newline + newline)
            ? "" : target.rawContent.hasSuffix(newline) ? newline : newline + newline
        let insertion = separator + fragment
        replacements[destination, default: []].append(
            AgentSourceEdit(startUTF8: target.rawContent.utf8.count, endUTF8: target.rawContent.utf8.count, expectedText: "", replacement: insertion))
        if request.operation == .move {
            let targetPath = (destination.relativePath as NSString).deletingPathExtension
            guard !targetPath.contains(where: { "[]|#\r\n".contains($0) }) else {
                throw unavailable("Choose a destination filename that can be represented in a note link.")
            }
            let fragmentSuffix = resultingIDs.first.map { "#^" + $0 } ?? ""
            let replacement = "[[" + targetPath + fragmentSuffix + "]]"
            replacements[sourceID, default: []].append(
                AgentSourceEdit(startUTF8: range.lowerBound, endUTF8: range.upperBound, expectedText: originalFragment, replacement: replacement))
        }
        var edits: [NoteRestructureFileEdit] = []
        for (id, sourceEdits) in replacements {
            let before = documents[id]?.rawContent
            let updated = try AgentSourceEdit.applying(sourceEdits, to: Data((before ?? "").utf8))
            if before != updated { edits.append(NoteRestructureFileEdit(note: id, before: before, after: updated)) }
        }
        if request.operation == .merge { edits.append(NoteRestructureFileEdit(note: sourceID, before: source.rawContent, after: nil)) }
        var finalDocuments = documents
        for edit in edits {
            finalDocuments[edit.note] = edit.after.map { NoteDocument(relativePath: edit.note.relativePath, rawContent: $0) }
        }
        let finalGraph = LinkGraphBuilder.build(
            generation: graph.generation + 1, catalog: finalDocuments.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) },
            documents: finalDocuments.mapValues(MarkdownSemanticDocument.init(parsing:)), resolutionScope: .workspace)
        // Fragment validity is checked against the final combined source, including duplicate headings.
        // Existing unrelated diagnostics are not silently repaired or used to authorize a rewrite.
        for diagnostic in finalGraph.diagnostics {
            let priorCount = graph.diagnostics.filter { $0.source == diagnostic.source && $0.code == diagnostic.code && $0.target == diagnostic.target }.count
            let finalCount = finalGraph.diagnostics.filter { $0.source == diagnostic.source && $0.code == diagnostic.code && $0.target == diagnostic.target }
                .count
            if finalCount > priorCount {
                throw unavailable(
                    "Reorganization would introduce a missing or ambiguous reference in \(diagnostic.source.relativePath). Reconcile that reference or duplicate target first."
                )
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

    private static func slice(_ source: String, _ range: Range<Int>) throws -> String {
        let bytes = Array(source.utf8)
        guard range.lowerBound >= 0, range.upperBound <= bytes.count,
            let text = String(bytes: bytes[range], encoding: .utf8)
        else { throw unavailable("The selected source range is no longer valid UTF-8.") }
        return text
    }

    private static func relativeEdit(source: String, span: Range<Int>, fragment: Range<Int>, replacement: String) throws -> AgentSourceEdit {
        guard span.lowerBound >= fragment.lowerBound, span.upperBound <= fragment.upperBound else {
            throw unavailable("The paragraph identifier lies outside the complete selection.")
        }
        return AgentSourceEdit(
            startUTF8: span.lowerBound - fragment.lowerBound, endUTF8: span.upperBound - fragment.lowerBound, expectedText: try slice(source, span),
            replacement: replacement)
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
        } else if let marker = raw.range(of: "]("), let close = raw.range(of: ")", options: .backwards) {
            // Titles/angle destinations need their exact grammar, not a guessed delimiter replacement.
            let old = raw[marker.upperBound..<close.lowerBound]
            guard !old.contains(where: { "\"'<>\n\r".contains($0) }) else {
                throw unavailable("A selected Markdown link uses a title or angle destination. Reconcile that link before reorganization.")
            }
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "#?() ")
            let path = target.addingPercentEncoding(withAllowedCharacters: allowed) ?? target
            replacement = String(raw[..<marker.upperBound]) + path + (fragment.map { "#" + $0 } ?? "") + String(raw[close.lowerBound...])
        } else {
            throw unavailable("A link occurrence cannot be safely rewritten in its authored syntax.")
        }
        return AgentSourceEdit(
            startUTF8: occurrence.linkSpan.utf8LowerBound, endUTF8: occurrence.linkSpan.utf8UpperBound, expectedText: raw, replacement: replacement)
    }

    private static func unavailable(_ detail: String) -> NoteRestructureError { .unavailable(detail) }
}
