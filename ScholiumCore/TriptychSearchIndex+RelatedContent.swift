import Foundation
import ScholiumContracts

// Related-content operations remain an extension of the one SearchIndex actor;
// ranking helpers do not become a second retrieval or evidence authority.

extension TriptychSearchIndex {
    /// Rank Notes using their authored context, then choose locally matching
    /// paragraphs within each Note. Metadata is neither an excerpt nor prose.
    nonisolated static func relatedPassages(
        _ request: RelatedContentRequest, sources: [RelatedContentSource],
        record: ((RelatedContentRankingDiagnostic) -> Void)? = nil
    ) throws -> [RelatedContentPassage] {
        try rankRelatedPassages(request, sources: sources, record: record) { source in
            try RelatedContentSourceProjection(document: source.document)
        }
    }

    nonisolated static func rankRelatedPassages(
        _ request: RelatedContentRequest, sources: [RelatedContentSource],
        record: ((RelatedContentRankingDiagnostic) -> Void)? = nil,
        project: (RelatedContentSource) throws -> RelatedContentSourceProjection?
    ) throws -> [RelatedContentPassage] {
        let seedDocument = NoteDocument(relativePath: request.seed.noteID.relativePath, rawContent: request.seed.source)
        let material = RelatedContentSeedMaterial(projection: SearchDocumentProjection(document: seedDocument), focuses: request.seed.focuses)
        let focusedTerms = material.termGroups.filter { $0.kind != .sourceNote }.flatMap(\.terms)
        let distinctFocusTermCount = Set(focusedTerms).count
        let requiredFocusMatches = min(2, distinctFocusTermCount)
        let literalAlternatives = Set(request.seed.focuses.flatMap(\.literalAlternatives))
        let phrases = Array(
            Set(
                request.seed.focuses.flatMap {
                    $0.literalAlternatives.isEmpty ? RelatedContentQueryTerms.quotedPhrases(in: $0.text) : []
                })
        ).sorted()
        let focused = !request.seed.focuses.isEmpty
        var ranked:
            [(
                passage: RelatedContentPassage, normalizedText: String, score: Double, documentIndex: Int, focusCoverage: Int, phraseCoverage: Double,
                localIdentity: Bool
            )] =
                []
        var scoringDocuments: [RelatedContentBM25F.Document] = []
        var scoringRoles: [VaultRole] = []
        var noteDocuments: [RelatedContentBM25F.Document] = []
        var noteRoles: [VaultRole] = []
        var noteIndices: [VaultQualifiedNoteID: Int] = [:]
        var noteRelevance: [VaultQualifiedNoteID: Double] = [:]
        var seenSources = Set<VaultQualifiedNoteID>()
        for source in sources {
            try Task.checkCancellation()
            guard source.document.fingerprint == source.candidate.fingerprint,
                source.candidate.note != request.seed.noteID,
                request.candidateRoles.contains(where: { $0.vaultRole == source.candidate.vaultRole }),
                seenSources.insert(source.candidate.note).inserted
            else {
                record?(.init(note: source.candidate.note, range: nil, stage: .rejectedSource))
                continue
            }
            guard let projection = try project(source) else {
                record?(.init(note: source.candidate.note, range: nil, stage: .unavailableProjection))
                continue
            }
            if projection.paragraphs.isEmpty {
                record?(.init(note: source.candidate.note, range: nil, stage: .noParagraphs))
            }
            if case .graphConnection = source.candidate.reason {
                let terms = Set(focusedTerms.isEmpty ? material.combinedTerms : focusedTerms)
                // Graph-only unrelated Notes must not change the lexical
                // comparison corpus merely because they are connected.
                guard
                    projection.paragraphs.contains(where: { unit in
                        !material.termMatcher.matchingTerms(in: unit.normalizedDisplayText, index: unit.textIndex)
                            .isDisjoint(with: terms)
                    })
                else {
                    record?(.init(note: source.candidate.note, range: nil, stage: .noLocalMatch))
                    continue
                }
            }
            noteIndices[source.candidate.note] = noteDocuments.count
            noteDocuments.append(projection.noteScoringDocument)
            noteRoles.append(source.candidate.vaultRole)
            var focusedIdentities: [String]?
            for unit in projection.paragraphs {
                try Task.checkCancellation()
                guard
                    let sourceRange = Range(
                        NSRange(
                            location: unit.range.utf16LowerBound,
                            length: unit.range.utf16UpperBound - unit.range.utf16LowerBound), in: source.document.rawContent)
                else { continue }
                let documentIndex = scoringDocuments.count
                scoringDocuments.append(unit.scoringDocument)
                scoringRoles.append(source.candidate.vaultRole)
                let normalized = unit.normalizedDisplayText
                let matchingTerms = material.termMatcher.matchingTerms(in: normalized, index: unit.textIndex)
                let matches = material.termGroups.compactMap { group -> RelatedContentSeedTermMatch? in
                    let terms = group.terms.filter { matchingTerms.contains($0) }
                    return terms.isEmpty ? nil : .init(seedKind: group.kind, terms: terms)
                }
                let focusCoverage = Set(matches.filter { $0.seedKind != .sourceNote }.flatMap(\.terms)).count
                guard matches.contains(where: { !focused || $0.seedKind != .sourceNote }) else {
                    record?(.init(note: source.candidate.note, range: unit.range, stage: .noLocalMatch))
                    continue
                }
                record?(.init(note: source.candidate.note, range: unit.range, stage: .localMatch))
                let phraseCoverage: Double
                if phrases.isEmpty {
                    phraseCoverage = 0
                } else {
                    let phraseText = normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    phraseCoverage =
                        Double(
                            phrases.filter {
                                relatedContentOccurrenceCount(term: $0, text: phraseText) > 0
                            }.count) / Double(phrases.count)
                }
                // Excerpts and highlight offset maps do not participate in
                // ranking. Build them only for the bounded displayed passages.
                let passage = RelatedContentPassage(
                    candidate: source.candidate, range: unit.range,
                    source: String(source.document.rawContent[sourceRange]), displayText: unit.displayText,
                    excerpt: "", excerptMatches: [], matches: matches)
                var localIdentity = false
                if focused, focusCoverage < requiredFocusMatches, phraseCoverage == 0 {
                    // Only ambiguous single-term admission needs current-source
                    // names. Prepare them once per Note, not once per paragraph.
                    if focusedIdentities == nil {
                        focusedIdentities = RelatedContentRecommendationPolicy.focusedIdentities(in: source.document, material: material)
                    }
                    localIdentity = RelatedContentRecommendationPolicy.locallyMatchesFocusedIdentity(
                        focusedIdentities!, normalizedText: normalized)
                }
                ranked.append((passage, normalized, 0, documentIndex, focusCoverage, phraseCoverage, localIdentity))
            }
        }
        let evaluation = try RelatedContentBM25F.evaluate(
            documents: scoringDocuments,
            terms: focusedTerms.isEmpty ? material.combinedTerms : focusedTerms, roles: scoringRoles)
        let maximumScore = evaluation.scores.max() ?? 0
        ranked.removeAll { item in
            let rejected =
                focused && item.focusCoverage < requiredFocusMatches && item.phraseCoverage == 0
                && !item.localIdentity
                // An explicitly chosen alternative is an OR input: its complete
                // local occurrence supplies a witness without requiring a translation too.
                && !item.passage.matches.contains(where: {
                    $0.seedKind == .researchRequest && !literalAlternatives.isDisjoint(with: $0.terms)
                })
                && !(distinctFocusTermCount >= 3 && evaluation.coverage[item.documentIndex] >= 0.6
                    && evaluation.hasDistinctiveMatch[item.documentIndex]
                    && item.passage.matches.filter { $0.seedKind != .sourceNote }.flatMap(\.terms).contains {
                        !["not", "no", "never", "cannot", "only"].contains($0)
                    })
            record?(
                .init(
                    note: item.passage.candidate.note, range: item.passage.range,
                    stage: rejected ? .insufficientFocus : .eligible, coverage: evaluation.coverage[item.documentIndex]))
            return rejected
        }
        for index in ranked.indices {
            let item = ranked[index]
            ranked[index].score =
                focused
                ? RelatedContentRecommendationPolicy.relevance(
                    coverage: evaluation.coverage[item.documentIndex], score: evaluation.scores[item.documentIndex],
                    maximumScore: maximumScore, phraseCoverage: item.phraseCoverage)
                : evaluation.scores[item.documentIndex]
            let note = item.passage.candidate.note
            noteRelevance[note] = max(noteRelevance[note, default: 0], ranked[index].score)
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let l = lhs.passage.candidate
            let r = rhs.passage.candidate
            if l.title != r.title { return l.title < r.title }
            if l.note.vaultID != r.note.vaultID { return l.note.vaultID.uuidString < r.note.vaultID.uuidString }
            if l.note.relativePath != r.note.relativePath { return l.note.relativePath < r.note.relativePath }
            return lhs.passage.range.utf16LowerBound < rhs.passage.range.utf16LowerBound
        }
        // Note and paragraph statistics have different units. Keep their
        // rankings separate instead of adding incomparable numeric scores.
        let noteScores = try RelatedContentBM25F.scores(
            documents: noteDocuments,
            terms: focusedTerms.isEmpty ? material.combinedTerms : focusedTerms, roles: noteRoles)
        let passageRelevance = Dictionary(ranked.map { ($0.passage.id, $0.score) }, uniquingKeysWith: max)
        var grouped: [VaultQualifiedNoteID: [RelatedContentPassage]] = [:]
        var seen: [VaultQualifiedNoteID: Set<String>] = [:]
        var duplicatePassages = Set<String>()
        for item in ranked where item.score > 0 {
            let note = item.passage.candidate.note
            let key = item.normalizedText
            guard seen[note, default: []].insert(key).inserted else {
                if record != nil { duplicatePassages.insert(item.passage.id) }
                continue
            }
            grouped[note, default: []].append(item.passage)
        }
        let maximumNoteScore = noteScores.max() ?? 0
        let noteUtilities = Dictionary(
            uniqueKeysWithValues: grouped.keys.map { note in
                let score = noteScores[noteIndices[note]!]
                // Authored Note context can refine paragraph relevance, but cannot
                // independently manufacture relevance or dominate the local focus.
                let value =
                    focused
                    ? noteRelevance[note, default: 0] * (0.85 + 0.15 * (maximumNoteScore > 0 ? score / maximumNoteScore : 0))
                    : score
                let identityFactor: Double
                if case .identityMention(let reason) = grouped[note]![0].candidate.reason,
                    reason.mentions.contains(where: { $0.seedKind != .sourceNote })
                {
                    // A researcher explicitly naming this Note is a query-specific
                    // identity signal, not a universal role or authority bonus.
                    identityFactor = 1.25
                } else {
                    identityFactor = 1
                }
                let graphFactor = RelatedContentRecommendationPolicy.graphFactor(grouped[note]![0].candidate.graphContext)
                return (note, value * identityFactor * graphFactor)
            })
        let rankedNotes = grouped.keys.sorted { lhs, rhs in
            let left = noteUtilities[lhs, default: 0]
            let right = noteUtilities[rhs, default: 0]
            if left != right { return left > right }
            let l = grouped[lhs]![0].candidate
            let r = grouped[rhs]![0].candidate
            if l.title != r.title { return l.title < r.title }
            if lhs.vaultID != rhs.vaultID { return lhs.vaultID.uuidString < rhs.vaultID.uuidString }
            return lhs.relativePath < rhs.relativePath
        }
        var result: [RelatedContentPassage] = []
        var representedRoles = Set<VaultRole>()
        var displayedSignatures: [RelatedContentRecommendationPolicy.TextSignature] = []
        var signatures: [String: RelatedContentRecommendationPolicy.TextSignature] = [:]
        var exactDisplayed = Set<String>()
        let strongest = noteUtilities.values.max() ?? 0
        // A bounded greedy rerank compares redundancy and role representation
        // only among already relevant material. All sources participated in
        // scoring; no retrieval truncation or inferred argumentative role.
        var cursors: [VaultQualifiedNoteID: Int] = [:]
        var displayedCounts: [VaultQualifiedNoteID: Int] = [:]
        while result.count < RelatedContentContract.maximumPassages {
            try Task.checkCancellation()
            var available:
                [(
                    note: VaultQualifiedNoteID, passage: RelatedContentPassage,
                    signature: RelatedContentRecommendationPolicy.TextSignature
                )] = []
            for note in rankedNotes where displayedCounts[note, default: 0] < RelatedContentContract.maximumPassagesPerNote {
                let passages = grouped[note]!
                var cursor = cursors[note, default: 0]
                while cursor < passages.count {
                    let passage = passages[cursor]
                    let signature: RelatedContentRecommendationPolicy.TextSignature
                    if let cached = signatures[passage.id] {
                        signature = cached
                    } else {
                        signature = .init(passage.displayText)
                        signatures[passage.id] = signature
                    }
                    if exactDisplayed.contains(signature.exact) {
                        if record != nil { duplicatePassages.insert(passage.id) }
                        cursor += 1
                        continue
                    }
                    available.append((note, passage, signature))
                    break
                }
                cursors[note] = cursor
            }
            guard let minimumDisplayed = available.map({ displayedCounts[$0.note, default: 0] }).min() else { break }
            var best: Int?
            var bestScore = -Double.infinity
            for (index, item) in available.enumerated() where displayedCounts[item.note, default: 0] == minimumDisplayed {
                let similarity = displayedSignatures.map { item.signature.similarity(to: $0) }.max() ?? 0
                let bestLocal = noteRelevance[item.note, default: 0]
                let localFactor = focused && bestLocal > 0 ? passageRelevance[item.passage.id, default: 0] / bestLocal : 1
                let score = RelatedContentRecommendationPolicy.diverseScore(
                    relevance: noteUtilities[item.note, default: 0] * localFactor, strongest: strongest,
                    roleAlreadyRepresented: representedRoles.contains(item.passage.candidate.vaultRole), similarity: similarity)
                if score > bestScore {
                    bestScore = score
                    best = index
                }
            }
            guard let best else { break }
            let item = available[best]
            let passage = item.passage
            cursors[item.note, default: 0] += 1
            displayedCounts[item.note, default: 0] += 1
            exactDisplayed.insert(item.signature.exact)
            displayedSignatures.append(item.signature)
            representedRoles.insert(passage.candidate.vaultRole)
            let preview = Self.relatedExcerpt(passage.displayText, matches: passage.matches)
            result.append(
                .init(
                    candidate: passage.candidate, range: passage.range,
                    source: passage.source, displayText: passage.displayText,
                    excerpt: preview.text, excerptMatches: preview.ranges, matches: passage.matches))
        }
        if let record {
            let selected = Set(result.map(\.id))
            for item in ranked where item.score > 0 {
                // Terminal outcomes concern the displayed set; exact copies are
                // distinguished from material omitted by Note/overall limits.
                let stage: RelatedContentRankingDiagnostic.Stage =
                    selected.contains(item.passage.id)
                    ? .selected
                    : (duplicatePassages.contains(item.passage.id)
                        || exactDisplayed.contains(RelatedContentRecommendationPolicy.TextSignature(item.passage.displayText).exact)
                        ? .duplicate : .limited)
                record(.init(note: item.passage.candidate.note, range: item.passage.range, stage: stage))
            }
        }
        return result
    }
}

extension TriptychSearchIndex {
    /// Search owns both the bounded readable excerpt and its verified highlight ranges.
    /// Cropping is on Character boundaries; exact paragraph source is kept separately.
    nonisolated static func relatedExcerpt(
        _ text: String, matches: [RelatedContentSeedTermMatch]
    ) -> (text: String, ranges: [Range<Int>]) {
        let focused = matches.filter { $0.seedKind != .sourceNote }
        let terms = (focused.isEmpty ? matches : focused).flatMap(\.terms)
        let normalized = SearchTextNormalization.lexicalNormalize(text)
        let occurrences = terms.flatMap { SearchMatcher.occurrences(of: .term($0), in: normalized) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard let first = occurrences.first,
            let original = SearchTextNormalization.originalUTF16RangeForLexicalNormalization(in: text, requestedRange: first),
            let anchor = Range(NSRange(location: original.lowerBound, length: original.count), in: text)
        else { return (String(text.prefix(240)) + (text.count > 240 ? "…" : ""), []) }
        let start = text.index(anchor.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(start, offsetBy: 240, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start > text.startIndex ? "…" : ""
        let excerpt = prefix + text[start..<end] + (end < text.endIndex ? "…" : "")
        let normalizedExcerpt = SearchTextNormalization.lexicalNormalize(excerpt)
        let ranges = terms.flatMap { SearchMatcher.occurrences(of: .term($0), in: normalizedExcerpt) }
            .prefix(64).compactMap {
                SearchTextNormalization.originalUTF16RangeForLexicalNormalization(in: excerpt, requestedRange: $0)
            }
        return (excerpt, Array(Set(ranges)).sorted { $0.lowerBound < $1.lowerBound })
    }
}

func relatedContentOccurrenceCount(term: String, text: String, normalizedNeedle: String? = nil) -> Int {
    SearchMatcher.occurrenceCount(of: .term(term), in: text, normalizedNeedle: normalizedNeedle)
}
