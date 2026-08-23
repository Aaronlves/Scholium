import Foundation
import ScholiumContracts

/// The Application-owned, rebuildable query projection over authoritative
/// portable Research Records. It owns no JSON and never reconstructs source.
struct ResearchRecordSearchIndex: Sendable {
    struct Execution: Sendable {
        let generation: RecordSearchGenerationID
        let availability: RecordSearchAvailability
        let results: [RecordSearchResult]
        let hasMore: Bool
        let totalResultCount: Int?
        let diagnostics: [SearchQueryDiagnostic]
    }

    private struct Segment: Sendable {
        let field: RecordSearchMatchedField
        let text: String
        let normalized: String
        let statementID: UUID?
        let statementAuthor: PortableResearchStatementAuthor?
        let noteID: UUID?
    }

    private struct NoteIdentityCandidate: Sendable {
        let noteID: UUID
        var identities: Set<String>
        var displays: Set<String>
    }

    private struct Entry: Sendable {
        let record: PortableResearchRecord
        let fingerprint: DocumentFingerprint
        let context: String
        let actionID: String
        let methodName: String?
        let segments: [Segment]
    }

    private let generation: RecordSearchGenerationID
    private let entries: [Entry]
    private let catalogNotes: [WorkspaceCatalogNote]
    private let isComplete: Bool

    init(
        triptychID: UUID,
        research: WorkspaceResearchSnapshot,
        catalog: WorkspaceCatalogSnapshot
    ) {
        self.init(
            triptychID: triptychID,
            research: research,
            catalogNotes: catalog.notes
        )
    }

    init(
        triptychID: UUID,
        research: WorkspaceResearchSnapshot,
        catalogNotes: [WorkspaceCatalogNote]
    ) {
        generation = RecordSearchGenerationID(
            triptychID: triptychID,
            sourceManifestHash: research.finishedResearchRecordSourceManifestHash
        )
        self.catalogNotes = catalogNotes
        let recordIDs = research.finishedResearchRecords.map(\.id)
        isComplete = research.finishedResearchRecordProjectionIsComplete
            && Set(recordIDs).count == recordIDs.count
            && research.finishedResearchRecords.allSatisfy {
                $0.triptychID == triptychID
            }
            && research.finishedResearchRecords.allSatisfy {
                research.finishedResearchRecordFingerprints[$0.id] != nil
            }
        entries = research.finishedResearchRecords.compactMap { record in
            guard let fingerprint = research.finishedResearchRecordFingerprints[record.id]
            else { return nil }
            return Self.makeEntry(record: record, fingerprint: fingerprint)
        }.sorted(by: Self.ordersEntries)
    }

    func search(
        ast: SearchQueryAST,
        scope: SearchExecutionScope,
        limit: Int,
        offset: Int = 0,
        sort: RecordSearchSortOrder = .finishedAtDescending,
        topLevelOnly: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Execution {
        precondition(ast.provider == .record)
        guard isComplete else {
            return Execution(
                generation: generation,
                availability: .failed(
                    lastGood: nil,
                    reason: "The portable Research Record corpus could not be read completely."
                ),
                results: [],
                hasMore: false,
                totalResultCount: nil,
                diagnostics: [SearchQueryDiagnostic(
                    code: .notApplicable,
                    message: "Research Record Search is unavailable because the portable Record corpus could not be read completely.",
                    utf16LowerBound: 0,
                    utf16UpperBound: 0
                )]
            )
        }

        let noteResolutions = try resolvedNoteClauses(ast.recordClauses, scope: scope)
        if let diagnostic = noteResolutions.diagnostic {
            return Execution(
                generation: generation,
                availability: .current(generation),
                results: [],
                hasMore: false,
                totalResultCount: 0,
                diagnostics: [diagnostic]
            )
        }

        let boundedLimit = min(max(0, limit), SearchContract.maximumCLIResults)
        let freshness = SearchFreshnessToken.record(generation)
        var matchingEntries: [Entry] = []
        for entry in entries {
            try Task.checkCancellation()
            guard (!topLevelOnly
                    || entry.record.continuationLineage?.kind != .continueResearch),
                  includes(entry.record, in: scope),
                  satisfies(
                    entry,
                    clauses: ast.recordClauses,
                    resolvedNotes: noteResolutions.identities,
                    now: now,
                    calendar: calendar
                  ) else { continue }
            matchingEntries.append(entry)
        }
        matchingEntries.sort { Self.ordersEntries($0, $1, by: sort) }
        let totalResultCount = matchingEntries.count
        let lowerBound = min(max(0, offset), totalResultCount)
        let upperBound = min(lowerBound + boundedLimit, totalResultCount)
        let results = matchingEntries[lowerBound..<upperBound].map {
            makeResult(
                $0,
                clauses: ast.recordClauses,
                resolvedNotes: noteResolutions.identities,
                freshness: freshness
            )
        }
        return Execution(
            generation: generation,
            availability: .current(generation),
            results: results,
            hasMore: upperBound < totalResultCount,
            totalResultCount: totalResultCount,
            diagnostics: []
        )
    }

    private func resolvedNoteClauses(
        _ clauses: [SearchRecordClause],
        scope: SearchExecutionScope
    ) throws -> (identities: [Range<Int>: Set<UUID>], diagnostic: SearchQueryDiagnostic?) {
        let candidates = noteIdentityCandidates(in: scope)
        var result: [Range<Int>: Set<UUID>] = [:]
        for clause in clauses where clause.field == .note {
            try Task.checkCancellation()
            let needle = SearchTextNormalization.normalize(clause.value.text)
            let matches = candidates.filter { candidate in
                candidate.identities.contains {
                    SearchTextNormalization.normalize($0) == needle
                }
            }
            guard matches.count == 1, let candidate = matches.first else {
                let code: SearchQueryDiagnosticCode = matches.isEmpty
                    ? .notApplicable
                    : .ambiguousIdentity
                let detail = matches
                    .flatMap(\.displays)
                    .sorted()
                    .joined(separator: ", ")
                return ([:], SearchQueryDiagnostic(
                    code: code,
                    message: matches.isEmpty
                        ? "No authorized Note has the exact identity ‘\(clause.value.text)’ for this Record query."
                        : "The Note identity ‘\(clause.value.text)’ is ambiguous: \(detail).",
                    utf16LowerBound: clause.sourceRange.lowerBound,
                    utf16UpperBound: clause.sourceRange.upperBound
                ))
            }
            result[clause.sourceRange] = [candidate.noteID]
        }
        return (result, nil)
    }

    /// Record-participant UUIDs are the stable authority. The current catalog
    /// contributes only searchable names and aliases for identities already
    /// present in the scope-first Record corpus.
    private func noteIdentityCandidates(
        in scope: SearchExecutionScope
    ) -> [NoteIdentityCandidate] {
        let scopedEntries = entries.filter { includes($0.record, in: scope) }
        var byID: [UUID: NoteIdentityCandidate] = [:]
        var noteIDsByLocation: [VaultQualifiedNoteID: Set<UUID>] = [:]
        for participant in scopedEntries.flatMap(\.record.participatingNotes) {
            var candidate = byID[participant.noteID] ?? NoteIdentityCandidate(
                noteID: participant.noteID,
                identities: [],
                displays: []
            )
            candidate.identities.formUnion(Self.noteIdentities(
                stableNoteID: participant.noteID.uuidString,
                relativePath: participant.note.relativePath,
                title: participant.title,
                aliases: []
            ))
            candidate.displays.insert(
                "\(participant.note.vaultID.uuidString.lowercased())/\(participant.note.relativePath)"
            )
            byID[participant.noteID] = candidate
            noteIDsByLocation[participant.note, default: []].insert(participant.noteID)
        }

        for note in catalogNotes {
            let stableID = note.reference.stableNoteID.flatMap(UUID.init(uuidString:))
            let pathMatches = noteIDsByLocation[VaultQualifiedNoteID(
                vaultID: note.reference.vaultID,
                relativePath: note.reference.relativePath
            ), default: []]
            let candidateID = stableID.flatMap { byID[$0] == nil ? nil : $0 }
                ?? (pathMatches.count == 1 ? pathMatches.first : nil)
            guard let candidateID, var candidate = byID[candidateID] else { continue }
            candidate.identities.formUnion(Self.noteIdentities(
                stableNoteID: note.reference.stableNoteID,
                relativePath: note.reference.relativePath,
                title: note.title,
                aliases: note.aliases
            ))
            candidate.displays.insert(
                "\(note.reference.vaultName)/\(note.reference.relativePath)"
            )
            byID[candidateID] = candidate
        }
        return byID.values.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
    }

    private static func noteIdentities(
        stableNoteID: String?,
        relativePath: String,
        title: String,
        aliases: [String]
    ) -> Set<String> {
        let filename = (relativePath as NSString).lastPathComponent
        let stem = (filename as NSString).deletingPathExtension
        return Set(([stableNoteID, relativePath, filename, stem, title]
            .compactMap { $0 }) + aliases)
    }

    private func includes(
        _ record: PortableResearchRecord,
        in scope: SearchExecutionScope
    ) -> Bool {
        switch scope {
        case .currentNote(let snapshot):
            let currentStableID = catalogNotes.first(where: {
                $0.reference.vaultID == snapshot.noteID.vaultID
                    && $0.reference.relativePath == snapshot.noteID.relativePath
            })?.reference.stableNoteID.flatMap(UUID.init(uuidString:))
            return record.participatingNotes.contains {
                if let currentStableID { return $0.noteID == currentStableID }
                return $0.note == snapshot.noteID
            }
        case .currentVault(let vaultID):
            return record.participatingNotes.contains {
                $0.note.vaultID == vaultID
            }
        case .triptych:
            return true
        }
    }

    private func satisfies(
        _ entry: Entry,
        clauses: [SearchRecordClause],
        resolvedNotes: [Range<Int>: Set<UUID>],
        now: Date,
        calendar: Calendar
    ) -> Bool {
        clauses.allSatisfy { clause in
            let matched: Bool
            switch clause.field {
            case nil:
                matched = entry.segments.contains {
                    Self.matches(clause.value, normalizedText: $0.normalized)
                }
            case .note:
                guard let notes = resolvedNotes[clause.sourceRange] else { return false }
                matched = entry.record.participatingNotes.contains {
                    notes.contains($0.noteID)
                }
            case .action:
                matched = Self.exact(clause.value.text, entry.actionID)
            case .skill:
                matched = entry.methodName.map {
                    Self.exact(clause.value.text, $0)
                } ?? false
            case .participant:
                guard let author = PortableResearchStatementAuthor(
                    rawValue: clause.value.text
                ) else { return false }
                matched = entry.record.statements.contains { $0.author == author }
            case .date:
                matched = Self.includes(
                    entry.record.finishedAt,
                    in: clause.value.text,
                    now: now,
                    calendar: calendar
                )
            }
            return clause.excluded ? !matched : matched
        }
    }

    private func makeResult(
        _ entry: Entry,
        clauses: [SearchRecordClause],
        resolvedNotes: [Range<Int>: Set<UUID>],
        freshness: SearchFreshnessToken
    ) -> RecordSearchResult {
        var matches: [Segment] = []
        for clause in clauses where !clause.excluded {
            switch clause.field {
            case nil:
                matches.append(contentsOf: entry.segments.filter {
                    Self.matches(clause.value, normalizedText: $0.normalized)
                })
            case .action:
                if let segment = entry.segments.first(where: { $0.field == .action }) {
                    matches.append(segment)
                }
            case .skill:
                if let segment = entry.segments.first(where: { $0.field == .skill }) {
                    matches.append(segment)
                }
            case .note:
                let resolved = resolvedNotes[clause.sourceRange]
                if let segment = entry.segments.first(where: {
                    $0.field == .participant
                        && $0.noteID.map { resolved?.contains($0) == true } == true
                }) {
                    matches.append(segment)
                }
            case .participant:
                let author = PortableResearchStatementAuthor(rawValue: clause.value.text)
                if let segment = entry.segments.first(where: {
                    $0.statementAuthor == author
                }) {
                    matches.append(segment)
                }
            case .date:
                break
            }
        }
        if matches.isEmpty {
            matches = entry.segments.filter { $0.field == .context }.prefix(1).map { $0 }
        }
        let primary = matches.first ?? Segment(
            field: .context,
            text: entry.context,
            normalized: Self.normalize(entry.context),
            statementID: nil,
            statementAuthor: nil,
            noteID: nil
        )
        var fields: [RecordSearchMatchedField] = []
        for match in matches where !fields.contains(match.field) { fields.append(match.field) }
        if fields.isEmpty { fields = [.context] }
        let presentation = Self.snippet(primary.text, clauses: clauses)
        return RecordSearchResult(
            resultID: "record:\(entry.record.id.uuidString.lowercased())",
            recordID: entry.record.id,
            statementID: primary.statementID,
            statementAuthor: primary.statementAuthor,
            matchedField: fields[0],
            additionalMatchedFields: Array(fields.dropFirst()),
            matchedReason: Self.reason(for: primary.field),
            context: entry.context,
            actionID: entry.actionID,
            methodName: entry.methodName,
            sourceDisplayName: entry.record.sourceReference?.displayName,
            finishedAt: entry.record.finishedAt,
            participatingNotes: entry.record.participatingNotes.map(\.note),
            snippet: presentation.text,
            highlights: presentation.highlights,
            freshnessToken: freshness,
            fingerprint: entry.fingerprint
        )
    }

    private static func makeEntry(
        record: PortableResearchRecord,
        fingerprint: DocumentFingerprint
    ) -> Entry {
        let actionID = record.kind == .discussion
            ? ResearchActionID.discuss.rawValue
            : record.action?.actionID.rawValue ?? ResearchActionID.discuss.rawValue
        let context = record.title.value
        var segments: [Segment] = [segment(.context, context), segment(.action, actionID)]
        if let method = record.method {
            segments.append(segment(.skill, method.displayName))
        }
        if let source = record.sourceReference {
            segments.append(segment(.sourceReference, source.displayName))
        }
        segments.append(contentsOf: record.participatingNotes.flatMap {
            [
                segment(.participant, $0.title, noteID: $0.noteID),
                segment(.participant, $0.role.rawValue, noteID: $0.noteID),
            ]
        })
        segments.append(contentsOf: record.statements.flatMap { statement in
            let field: RecordSearchMatchedField = statement.author == .researcher
                ? .researcherStatement
                : .agentStatement
            return [statement.attribution, statement.kind.rawValue, statement.text].map {
                segment(
                    field,
                    $0,
                    statementID: statement.id,
                    statementAuthor: statement.author
                )
            }
        })
        segments.append(contentsOf: record.actuallyUsedMaterials.flatMap {
            [segment(.material, $0.title), segment(.material, $0.role.rawValue)]
        })
        return Entry(
            record: record,
            fingerprint: fingerprint,
            context: context,
            actionID: actionID,
            methodName: record.method?.displayName,
            segments: segments
        )
    }

    private static func segment(
        _ field: RecordSearchMatchedField,
        _ text: String,
        statementID: UUID? = nil,
        statementAuthor: PortableResearchStatementAuthor? = nil,
        noteID: UUID? = nil
    ) -> Segment {
        Segment(
            field: field,
            text: text,
            normalized: normalize(text),
            statementID: statementID,
            statementAuthor: statementAuthor,
            noteID: noteID
        )
    }

    private static func normalize(_ value: String) -> String {
        SearchTextNormalization.lexicalNormalize(value)
    }

    private static func exact(_ query: String, _ value: String) -> Bool {
        SearchTextNormalization.normalize(query)
            == SearchTextNormalization.normalize(value)
    }

    private static func matches(
        _ value: SearchLexicalValue,
        normalizedText: String
    ) -> Bool {
        let needle = normalize(value.text)
        guard !needle.isEmpty else { return false }
        switch value {
        case .term, .phrase:
            return normalizedText.contains(needle)
        case .prefix:
            return normalizedText.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .contains { $0.hasPrefix(needle) }
        }
    }

    private static func includes(
        _ date: Date,
        in window: String,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let startOfToday = calendar.startOfDay(for: now)
        let lowerBound: Date? = switch window {
        case "today": startOfToday
        case "7d": calendar.date(byAdding: .day, value: -6, to: startOfToday)
        case "30d": calendar.date(byAdding: .day, value: -29, to: startOfToday)
        default: nil
        }
        guard let lowerBound else { return false }
        guard let upperBound = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else { return false }
        return date >= lowerBound && date < upperBound
    }

    private static func ordersEntries(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.record.finishedAt != rhs.record.finishedAt {
            return lhs.record.finishedAt > rhs.record.finishedAt
        }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
    }

    private static func ordersEntries(
        _ lhs: Entry,
        _ rhs: Entry,
        by sort: RecordSearchSortOrder
    ) -> Bool {
        switch sort {
        case .finishedAtDescending:
            return ordersEntries(lhs, rhs)
        case .finishedAtAscending:
            if lhs.record.finishedAt != rhs.record.finishedAt {
                return lhs.record.finishedAt < rhs.record.finishedAt
            }
        case .titleAscending, .titleDescending:
            let comparison = lhs.record.title.value.localizedStandardCompare(rhs.record.title.value)
            if comparison != .orderedSame {
                return sort == .titleAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
        case .actionAscending, .actionDescending:
            let comparison = lhs.actionID.localizedStandardCompare(rhs.actionID)
            if comparison != .orderedSame {
                return sort == .actionAscending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
        }
        if lhs.record.finishedAt != rhs.record.finishedAt {
            return lhs.record.finishedAt > rhs.record.finishedAt
        }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
    }

    private static func snippet(
        _ text: String,
        clauses: [SearchRecordClause]
    ) -> (text: String, highlights: [SearchHighlight]) {
        let bounded = String(text.prefix(240))
        guard let query = clauses.first(where: {
            $0.field == nil && !$0.excluded
        })?.value.text else { return (bounded, []) }
        let normalized = normalize(bounded)
        let needle = normalize(query)
        guard let range = normalized.range(of: needle) else { return (bounded, []) }
        let lower = range.lowerBound.utf16Offset(in: normalized)
        let upper = range.upperBound.utf16Offset(in: normalized)
        let normalizedRange = lower..<upper
        guard let original = SearchTextNormalization.originalUTF16RangeForLexicalNormalization(
            in: bounded,
            requestedRange: normalizedRange
        ) else { return (bounded, []) }
        return (bounded, [SearchHighlight(
            utf16LowerBound: original.lowerBound,
            utf16UpperBound: original.upperBound
        )])
    }

    private static func reason(for field: RecordSearchMatchedField) -> String {
        switch field {
        case .context: "Matched Record context"
        case .action: "Matched Research Action identity"
        case .skill: "Matched Method Skill identity"
        case .participant: "Matched participating Note"
        case .researcherStatement: "Matched an attributed researcher statement"
        case .agentStatement: "Matched an attributed Agent statement"
        case .material: "Matched an actually-used Material"
        case .sourceReference: "Matched the recorded source reference"
        }
    }
}
