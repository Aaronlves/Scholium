import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func runVault(_ arguments: [String], context: CLIContext) async throws {
        guard let subcommand = arguments.first else {
            throw commandUsageError("vault list")
        }
        switch subcommand {
        case "list":
            let triptychs = try await context.assignments()
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Vault list supports --format text or json.")
            }
            if format == "json" {
                let payload = triptychs.map { assignment -> [String: Any] in
                    let vaults = WorkspaceVaultSlot.allCases.compactMap { slot -> [String: Any]? in
                        guard let vault = assignment.vault(for: slot) else { return nil }
                        return [
                            "role": slot.rawValue,
                            "id": vault.id.uuidString.lowercased(),
                            "name": vault.name,
                            "path": vault.canonicalPath,
                        ]
                    }
                    return [
                        "id": assignment.id.uuidString.lowercased(),
                        "name": assignment.triptych.name,
                        "vaults": vaults,
                    ]
                }
                let data = try JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
                write(String(decoding: data, as: UTF8.self) + "\n")
            } else if triptychs.isEmpty {
                write("No Scholium Triptychs are configured. Use Scholium onboarding or Manage Triptychs.\n")
            } else {
                for assignment in triptychs {
                    write("\(assignment.id.uuidString)  \(assignment.triptych.name)\n")
                    for slot in WorkspaceVaultSlot.allCases {
                        guard let vault = assignment.vault(for: slot) else { continue }
                        write("  \(slot.displayName): \(vault.id.uuidString)\n    \(vault.canonicalPath)\n")
                    }
                }
            }
        default:
            throw CLIError.usage(
                "Unknown vault command '\(subcommand)'. Configure complete Triptychs in Scholium; use 'scholium vault list' for CLI discovery."
            )
        }
    }

    static func runSearch(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let first = arguments.first else {
            throw commandUsageError("search")
        }
        let query: String
        let assignment: TriptychAssignment
        let executionScope: SearchExecutionScope
        let presentationScope: SearchPresentationScope
        if let selector = option("--vault", in: arguments) {
            query = first
            let vault = try await context.resolveVault(selector)
            if let triptychSelector = option("--triptych", in: arguments) {
                assignment = try await context.selectedTriptych(selector: triptychSelector)
                guard assignment.vaults.values.contains(where: { $0.id == vault.id }) else {
                    throw CLIError.usage("The selected vault is not a member of the selected Triptych.")
                }
            } else {
                assignment = try await context.triptych(containing: [vault.id])
            }
            executionScope = .currentVault(vault.id)
            presentationScope = .currentVault
        } else if let selector = option("--triptych", in: arguments) {
            query = first
            assignment = try await context.selectedTriptych(selector: selector)
            executionScope = .triptych
            presentationScope = .triptych
        } else {
            throw CLIError.usage("Choose --vault <selector> or --triptych <uuid-or-unique-name>.")
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { throw CLIError.usage("Search query cannot be empty.") }
        let limitText = option("--limit", in: arguments) ?? "20"
        guard let limit = Int(limitText), (1 ... 500).contains(limit) else {
            throw CLIError.usage("--limit must be a whole number from 1 through 500.")
        }
        let handle = try await context.handle(for: assignment)
        let response = try await handle.discovery.search(SearchRequest(
            query: trimmedQuery,
            presentationScope: presentationScope,
            executionScope: executionScope,
            limit: limit
        ))
        if let diagnostic = response.diagnostics.first {
            throw CLIError.searchDiagnostic(diagnostic)
        }
        let format = option("--format", in: arguments) ?? "text"
        switch format {
        case "jsonl":
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let summary = SearchSummaryRecord(response: response)
            write(String(decoding: try encoder.encode(summary), as: UTF8.self) + "\n")
            for result in response.results {
                write(String(
                    decoding: try encoder.encode(SearchResultJSONRecord(
                        result: result,
                        contractVersion: response.contractVersion,
                        scope: response.scope
                    )),
                    as: UTF8.self
                ) + "\n")
            }
        case "text":
            let availability = SearchAvailabilityRecord(response.availability)
            write(
                "Search contract=\(response.contractVersion) provider=\(response.provider.rawValue) "
                    + "scope=\(response.scope.rawValue) availability=\(availability.textDescription) "
                    + "freshness=\(response.freshnessToken.rawValue)\n"
            )
            write("Explain: \(SearchExplanationRecord(response.explanation).textDescription)\n")
            if response.results.isEmpty { write("No matches.\n") }
            for result in response.results {
                switch result {
                case .note(let hit):
                    let line = hit.sourceRange?.line ?? hit.sourceLine
                    let column = hit.sourceRange?.column ?? 1
                    let reasons = hit.matchReasons
                        .map(SearchMatchReasonRecord.init)
                        .map(\.textDescription)
                        .joined(separator: ", ")
                    write(
                        "note \(hit.vaultName):\(hit.relativePath):\(line):\(column) "
                            + "[\(hit.classification.rawValue); \(hit.rankReason.rawValue); \(reasons)] "
                            + "fingerprint=\(hit.fingerprint.sha256):\(hit.fingerprint.byteCount) "
                            + "freshness=\(hit.freshnessToken.rawValue)\n  \(hit.snippet)\n"
                    )
                case .record(let hit):
                    let statement = hit.statementID?.uuidString.lowercased() ?? "none"
                    let author = hit.statementAuthor?.rawValue ?? "none"
                    let fields = hit.matchedFields.map(\.rawValue).joined(separator: ",")
                    write(
                        "record \(hit.recordID.uuidString.lowercased()) "
                            + "statement=\(statement) author=\(author) "
                            + "[\(hit.classification.rawValue); \(hit.matchedReason); fields=\(fields)] "
                            + "fingerprint=\(hit.fingerprint.sha256):\(hit.fingerprint.byteCount) "
                            + "freshness=\(hit.freshnessToken.rawValue)\n  \(hit.snippet)\n"
                    )
                }
            }
        default:
            throw CLIError.usage("--format must be text or jsonl.")
        }
    }

    private struct SearchSummaryRecord: Encodable {
        let type = "search_summary"
        let contractVersion: Int
        let requestID: UUID
        let provider: SearchProvider
        let scope: String
        let availability: SearchAvailabilityRecord
        let freshnessToken: SearchFreshnessToken
        let explanation: SearchExplanationRecord
        let resultCount: Int
        let hasMore: Bool

        init(response: SearchResponse) {
            contractVersion = response.contractVersion
            requestID = response.requestID
            provider = response.provider
            scope = response.scope.rawValue
            availability = SearchAvailabilityRecord(response.availability)
            freshnessToken = response.freshnessToken
            explanation = SearchExplanationRecord(response.explanation)
            resultCount = response.results.count
            hasMore = response.hasMore
        }
    }

    private struct SearchAvailabilityRecord: Encodable {
        let provider: SearchProvider
        let status: String
        let noteGeneration: SearchGenerationID?
        let recordGeneration: RecordSearchGenerationID?
        let progress: SearchBuildProgress?
        let reason: String?

        init(_ availability: SearchProviderAvailability) {
            switch availability {
            case .note(let value):
                provider = .note
                recordGeneration = nil
                switch value {
                case .unavailable:
                    status = "unavailable"
                    noteGeneration = nil
                    progress = nil
                    reason = nil
                case .building(let value):
                    status = "building"
                    noteGeneration = nil
                    progress = value
                    reason = nil
                case .current(let generation):
                    status = "current"
                    noteGeneration = generation
                    progress = nil
                    reason = nil
                case .refreshing(let generation):
                    status = "refreshing"
                    noteGeneration = generation
                    progress = nil
                    reason = nil
                case .stale(let generation, let value):
                    status = "stale"
                    noteGeneration = generation
                    progress = nil
                    reason = value
                case .failed(let generation, let value):
                    status = "failed"
                    noteGeneration = generation
                    progress = nil
                    reason = value
                }
            case .record(let value):
                provider = .record
                noteGeneration = nil
                switch value {
                case .unavailable:
                    status = "unavailable"
                    recordGeneration = nil
                    progress = nil
                    reason = nil
                case .building(let value):
                    status = "building"
                    recordGeneration = nil
                    progress = value
                    reason = nil
                case .current(let generation):
                    status = "current"
                    recordGeneration = generation
                    progress = nil
                    reason = nil
                case .refreshing(let generation):
                    status = "refreshing"
                    recordGeneration = generation
                    progress = nil
                    reason = nil
                case .stale(let generation, let value):
                    status = "stale"
                    recordGeneration = generation
                    progress = nil
                    reason = value
                case .failed(let generation, let value):
                    status = "failed"
                    recordGeneration = generation
                    progress = nil
                    reason = value
                }
            }
        }

        var textDescription: String {
            guard let reason, !reason.isEmpty else { return status }
            return "\(status)(\(reason.replacingOccurrences(of: "\n", with: " ")))"
        }
    }

    private struct SearchQuerySourceRangeRecord: Encodable {
        let utf16LowerBound: Int
        let utf16UpperBound: Int

        init(_ range: Range<Int>) {
            utf16LowerBound = range.lowerBound
            utf16UpperBound = range.upperBound
        }
    }

    private struct SearchExplanationClauseRecord: Encodable {
        let kind: String
        let field: String?
        let value: String?
        let propertyKey: String?
        let matchKind: SearchLexicalMatchKind?
        let excluded: Bool
        let relation: SearchRelation?
        let relationDirection: SearchRelationDirection?
        let symmetric: Bool?
        let sourceRange: SearchQuerySourceRangeRecord

        init(_ clause: SearchExplanationClause) {
            sourceRange = SearchQuerySourceRangeRecord(clause.sourceRange)
            switch clause.kind {
            case .lexical(let lexicalField, let lexicalValue, let lexicalKind, let isExcluded):
                kind = "lexical"
                field = lexicalField?.rawValue
                value = lexicalValue
                propertyKey = nil
                matchKind = lexicalKind
                excluded = isExcluded
                relation = nil
                relationDirection = nil
                symmetric = nil
            case .structured(let structuredField, let structuredValue, let isExcluded):
                kind = "structured"
                field = structuredField.rawValue
                value = structuredValue
                propertyKey = nil
                matchKind = nil
                excluded = isExcluded
                relation = nil
                relationDirection = nil
                symmetric = nil
            case .property(let key, let exactValue):
                kind = "property"
                field = "property"
                value = exactValue
                propertyKey = key
                matchKind = nil
                excluded = false
                relation = nil
                relationDirection = nil
                symmetric = nil
            case .relation(let direction, let identity, let relationValue, let isSymmetric):
                kind = "relationship"
                field = direction.rawValue
                value = identity
                propertyKey = nil
                matchKind = nil
                excluded = false
                relation = relationValue
                relationDirection = direction
                symmetric = isSymmetric
            case .record(let recordField, let recordValue, let lexicalKind, let isExcluded):
                kind = "record"
                field = recordField?.rawValue
                value = recordValue
                propertyKey = nil
                matchKind = lexicalKind
                excluded = isExcluded
                relation = nil
                relationDirection = nil
                symmetric = nil
            }
        }

        var textDescription: String {
            let prefix = excluded ? "NOT " : ""
            switch kind {
            case "property":
                let key = propertyKey ?? "unknown"
                if let value { return "property \(key)=\"\(value)\"" }
                return "property \(key) present"
            case "relationship":
                return "\(relationDirection?.rawValue ?? field ?? "relation") \"\(value ?? "")\" "
                    + "relation \(relation?.rawValue ?? "unknown")"
                    + (symmetric == true ? " (symmetric)" : "")
            default:
                let fieldPrefix = field.map { "\($0):" } ?? ""
                let renderedValue = matchKind == .phrase ? "\"\(value ?? "")\"" : (value ?? "")
                let suffix = matchKind == .prefix ? "*" : ""
                return "\(prefix)\(fieldPrefix)\(renderedValue)\(suffix)"
            }
        }
    }

    private struct SearchExplanationRecord: Encodable {
        let provider: SearchProvider
        let providerWasExplicit: Bool
        let scope: SearchPresentationScope
        let `operator`: SearchExplanationOperator
        let clauses: [SearchExplanationClauseRecord]
        let normalization: [SearchExplanationNormalization]
        let ordering: SearchExplanationOrdering
        let limitations: [SearchExplanationLimitation]

        init(_ explanation: SearchExplanation) {
            provider = explanation.provider
            providerWasExplicit = explanation.providerWasExplicit
            scope = explanation.scope
            `operator` = explanation.operator
            clauses = explanation.clauses.map(SearchExplanationClauseRecord.init)
            normalization = explanation.normalization
            ordering = explanation.ordering
            limitations = explanation.limitations
        }

        var textDescription: String {
            let providerSource = providerWasExplicit ? "explicit" : "default"
            let clauseText = clauses.map(\.textDescription).joined(separator: " AND ")
            let query = clauseText.isEmpty
                ? "provider=\(provider.rawValue) (\(providerSource)); no clauses"
                : "provider=\(provider.rawValue) (\(providerSource)); \(clauseText)"
            let normalizationText = normalization.map(\.rawValue).joined(separator: ",")
            let limitationText = limitations.map(\.rawValue).joined(separator: ",")
            return "\(query); scope=\(scope.rawValue); normalization=\(normalizationText); "
                + "ordering=\(ordering.rawValue); limitations=\(limitationText)"
        }
    }

    private struct NoteSearchLocatorRecord: Encodable {
        let sourceRange: SearchSourceRange?
        let fallbackLine: Int
        let fallbackColumn: Int

        init(_ result: NoteSearchResult) {
            sourceRange = result.sourceRange
            fallbackLine = result.sourceLine
            fallbackColumn = 1
        }
    }

    private struct RecordSearchLocatorRecord: Encodable {
        let recordID: UUID
        let statementID: UUID?
        let statementAuthor: PortableResearchStatementAuthor?
        let sourceRange: SearchSourceRange?

        init(_ result: RecordSearchResult) {
            recordID = result.recordID
            statementID = result.statementID
            statementAuthor = result.statementAuthor
            sourceRange = result.sourceRange
        }
    }

    private struct SearchMatchReasonRecord: Encodable {
        let kind: String
        let structured: SearchStructuredMatch?
        let property: SearchPropertyMatch?
        let relationship: SearchRelationshipMatch?

        init(_ reason: NoteSearchMatchReason) {
            switch reason {
            case .lexical:
                kind = "lexical"
                structured = nil
                property = nil
                relationship = nil
            case .structured(let value):
                kind = "structured"
                structured = value
                property = nil
                relationship = nil
            case .property(let value):
                kind = "property"
                structured = nil
                property = value
                relationship = nil
            case .relationship(let value):
                kind = "relationship"
                structured = nil
                property = nil
                relationship = value
            }
        }

        var textDescription: String {
            switch kind {
            case "structured":
                guard let structured else { return kind }
                let exclusion = structured.excluded ? "-" : ""
                return "\(exclusion)\(structured.field.rawValue):\(structured.value)"
            case "property":
                guard let property else { return kind }
                if let value = property.normalizedValue {
                    return "property:\(property.key)=\(value)"
                }
                return property.isEmpty
                    ? "property:\(property.key) (present-empty)"
                    : "property:\(property.key) (\(property.valueKind.rawValue))"
            case "relationship":
                guard let relationship else { return kind }
                let source = relationship.occurrences.first.map {
                    " source=\($0.sourceNote.vaultID.uuidString.lowercased())/"
                        + "\($0.sourceNote.relativePath):\($0.locator.line):\($0.locator.column)"
                } ?? ""
                return "\(relationship.direction.rawValue):\(relationship.anchorIdentity) "
                    + "relation:\(relationship.relation.rawValue)"
                    + source
            default:
                return kind
            }
        }
    }

    private struct NoteSearchResultJSONRecord: Encodable {
        let type = "search_result"
        let contractVersion: Int
        let provider = SearchProvider.note
        let scope: SearchPresentationScope
        let resultID: String
        let vaultID: UUID
        let vaultName: String
        let vaultRole: VaultRole
        let relativePath: String
        let stableNoteID: String?
        let title: String
        let evidentialLayer: EvidentialLayer
        let matchedField: SearchMatchedField
        let matchedFields: [SearchMatchedField]
        let rankReason: SearchRankReason
        let matchReasons: [SearchMatchReasonRecord]
        let context: String?
        let snippet: String
        let highlights: [SearchHighlight]
        let locator: NoteSearchLocatorRecord
        let fingerprint: DocumentFingerprint
        let freshnessToken: SearchFreshnessToken
        let classification: SearchResultClassification

        init(hit: NoteSearchResult, contractVersion: Int, scope: SearchPresentationScope) {
            self.contractVersion = contractVersion
            self.scope = scope
            resultID = hit.resultID
            vaultID = hit.vaultID
            vaultName = hit.vaultName
            vaultRole = hit.vaultRole
            relativePath = hit.relativePath
            stableNoteID = hit.stableNoteID
            title = hit.title
            evidentialLayer = hit.evidentialLayer
            matchedField = hit.matchedField
            matchedFields = hit.matchedFields
            rankReason = hit.rankReason
            matchReasons = hit.matchReasons.map(SearchMatchReasonRecord.init)
            context = hit.context
            snippet = hit.snippet
            highlights = hit.highlights
            locator = NoteSearchLocatorRecord(hit)
            fingerprint = hit.fingerprint
            freshnessToken = hit.freshnessToken
            classification = hit.classification
        }
    }

    private struct RecordSearchResultJSONRecord: Encodable {
        let type = "search_result"
        let contractVersion: Int
        let provider = SearchProvider.record
        let scope: SearchPresentationScope
        let resultID: String
        let recordID: UUID
        let statementID: UUID?
        let statementAuthor: PortableResearchStatementAuthor?
        let matchedField: RecordSearchMatchedField
        let matchedFields: [RecordSearchMatchedField]
        let matchedReason: String
        let context: String
        let actionID: String?
        let methodName: String?
        let sourceDisplayName: String?
        let finishedAt: Date
        let participatingNotes: [VaultQualifiedNoteID]
        let snippet: String
        let highlights: [SearchHighlight]
        let locator: RecordSearchLocatorRecord
        let fingerprint: DocumentFingerprint
        let freshnessToken: SearchFreshnessToken
        let classification: SearchResultClassification

        init(hit: RecordSearchResult, contractVersion: Int, scope: SearchPresentationScope) {
            self.contractVersion = contractVersion
            self.scope = scope
            resultID = hit.resultID
            recordID = hit.recordID
            statementID = hit.statementID
            statementAuthor = hit.statementAuthor
            matchedField = hit.matchedField
            matchedFields = hit.matchedFields
            matchedReason = hit.matchedReason
            context = hit.context
            actionID = hit.actionID
            methodName = hit.methodName
            sourceDisplayName = hit.sourceDisplayName
            finishedAt = hit.finishedAt
            participatingNotes = hit.participatingNotes
            snippet = hit.snippet
            highlights = hit.highlights
            locator = RecordSearchLocatorRecord(hit)
            fingerprint = hit.fingerprint
            freshnessToken = hit.freshnessToken
            classification = hit.classification
        }
    }

    private enum SearchResultJSONRecord: Encodable {
        case note(NoteSearchResultJSONRecord)
        case record(RecordSearchResultJSONRecord)

        init(
            result: SearchResult,
            contractVersion: Int,
            scope: SearchPresentationScope
        ) {
            switch result {
            case .note(let hit):
                self = .note(NoteSearchResultJSONRecord(
                    hit: hit,
                    contractVersion: contractVersion,
                    scope: scope
                ))
            case .record(let hit):
                self = .record(RecordSearchResultJSONRecord(
                    hit: hit,
                    contractVersion: contractVersion,
                    scope: scope
                ))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .note(let record): try record.encode(to: encoder)
            case .record(let record): try record.encode(to: encoder)
            }
        }
    }

    static func runLinks(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw commandUsageError("links")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Links commands support --format json.")
        }
        switch subcommand {
        case "incoming", "outgoing":
            guard arguments.count >= 2 else {
                throw commandUsageError("links \(subcommand)")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let direction: WorkspaceLinkDirection = subcommand == "incoming"
                ? .incoming
                : .outgoing
            let edges = try await handle.discovery.links(for: id, direction: direction)
            write(String(decoding: try encoder.encode(edges), as: UTF8.self) + "\n")
        case "relationships":
            guard arguments.count >= 2 else {
                throw commandUsageError("links relationships")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let relationships = try await handle.discovery.relationships(for: id)
            write(String(decoding: try encoder.encode(relationships), as: UTF8.self) + "\n")
        case "diagnostics":
            guard arguments.contains("--workspace") else {
                throw commandUsageError("links diagnostics")
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let diagnostics = try await handle.discovery.linkDiagnostics()
            write(String(decoding: try encoder.encode(diagnostics), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("Unknown links command '\(subcommand)'.")
        }
    }

    static func runGraph(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard ["trace", "relation-trace"].contains(arguments.first ?? ""), arguments.count >= 3 else {
            throw commandUsageError("graph")
        }
        let (sourceVault, sourcePath) = try await context.resolveTarget(arguments[1])
        let (targetVault, targetPath) = try await context.resolveTarget(arguments[2])
        let assignment = try await context.triptych(containing: [sourceVault.id, targetVault.id])
        let maximumDepthText = option("--max-depth", in: arguments) ?? "3"
        guard let maximumDepth = Int(maximumDepthText),
              (1 ... 10).contains(maximumDepth) else {
            throw CLIError.usage("--max-depth must be a whole number from 1 through 10.")
        }
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Graph commands support --format json.")
        }
        let handle = try await context.handle(for: assignment)
        let source = VaultQualifiedNoteID(vaultID: sourceVault.id, relativePath: sourcePath)
        let target = VaultQualifiedNoteID(vaultID: targetVault.id, relativePath: targetPath)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if arguments.first == "relation-trace" {
            let paths = try await handle.discovery.traceRelationships(
                from: source,
                to: target,
                maximumDepth: maximumDepth
            )
            write(String(decoding: try encoder.encode(paths), as: UTF8.self) + "\n")
        } else {
            let paths = try await handle.discovery.traceLinks(
                from: source,
                to: target,
                maximumDepth: maximumDepth
            )
            write(String(decoding: try encoder.encode(paths), as: UTF8.self) + "\n")
        }
    }

    static func runWorkspace(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw commandUsageError("workspace")
        }
        if subcommand == "bootstrap" {
            try await runWorkspaceBootstrap(Array(arguments.dropFirst()), context: context)
            return
        }
        let assignment = try await context.selectedTriptych(
            selector: option("--triptych", in: arguments)
        )
        if subcommand == "skill-sources" {
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Workspace Skill sources supports --format json.")
            }
            let manifest = try await context.runtime.skillDiscoverySourceManifest(
                workspaceID: assignment.id
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            write(String(decoding: try encoder.encode(manifest), as: UTF8.self) + "\n")
            return
        }
        let handle = try await context.handle(for: assignment)
        let snapshot = try await handle.discovery.snapshot().catalog
        guard (option("--format", in: arguments) ?? "json") == "json" else {
            throw CLIError.usage("Workspace catalog and attention support --format json.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        switch subcommand {
        case "catalog":
            write(String(decoding: try encoder.encode(snapshot), as: UTF8.self) + "\n")
        case "attention":
            let items: [AttentionQueueItem]
            if let kindText = option("--kind", in: arguments) {
                guard let kind = AttentionQueueKind(rawValue: kindText) else {
                    throw CLIError.usage("Unknown attention queue '\(kindText)'.")
                }
                items = snapshot.attention.filter { $0.kind == kind }
            } else {
                items = snapshot.attention
            }
            write(String(decoding: try encoder.encode(items), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("Unknown workspace command '\(subcommand)'.")
        }
    }

    private static func runWorkspaceBootstrap(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let selector = option("--triptych", in: arguments),
              let targetPath = option("--target", in: arguments) else {
            throw commandUsageError("workspace bootstrap")
        }
        let assignment = try await context.triptych(selector: selector)
        let targetURL = URL(
            fileURLWithPath: (targetPath as NSString).expandingTildeInPath,
            isDirectory: true
        )
        let conventions: String
        if let conventionsPath = option("--conventions-file", in: arguments) {
            let url = URL(
                fileURLWithPath: (conventionsPath as NSString).expandingTildeInPath,
                isDirectory: false
            )
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw CLIError.invalidUTF8(url.path)
            }
            conventions = content
        } else {
            conventions = "None recorded."
        }
        let request = WorkspaceBootstrapRequest(
            triptychSelector: assignment.workspace.id.uuidString,
            triptychName: assignment.triptych.name,
            targetURL: targetURL,
            researcherConventions: conventions
        )
        let candidate = try context.runtime.bootstrapCandidate(for: request)
        let format = option("--format", in: arguments) ?? "markdown"
        switch format {
        case "markdown":
            // This command is deliberately candidate-only. An external agent
            // must promote the output after its own final target verification.
            write(candidate.content)
        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            write(String(decoding: try encoder.encode(candidate), as: UTF8.self) + "\n")
        default:
            throw CLIError.usage("--format must be markdown or json.")
        }
    }


    static func runDiscuss(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw commandUsageError("discuss")
        }
        let assignment = try await context.selectedTriptych(
            selector: option("--triptych", in: arguments)
        )
        let handle = try await context.handle(for: assignment)
        let research = handle.research
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        switch subcommand {
        case "list":
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Discuss list supports --format text or json.")
            }
            let entries = try await research.activeDiscussions(noteID: nil)
            if format == "json" {
                write(String(decoding: try encoder.encode(entries), as: UTF8.self) + "\n")
            } else if entries.isEmpty {
                write("No active Discussions.\n")
            } else {
                for entry in entries {
                    let noteNames = entry.participatingNotes.map(\.title).joined(separator: ", ")
                    write("\(entry.id.uuidString)  \(entry.createdAt.formatted(.iso8601))\n")
                    write("  Notes: \(noteNames)\n")
                    write("  Latest: \(entry.statements.last?.text ?? "")\n")
                }
            }
        case "show":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw commandUsageError("discuss show")
            }
            let entry = try await research.activeDiscussion(id: id)
            let format = option("--format", in: arguments) ?? "text"
            guard format == "text" || format == "json" else {
                throw CLIError.usage("Discuss show supports --format text or json.")
            }
            if format == "json" {
                write(String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n")
            } else {
                write("Discussion: \(entry.id.uuidString)\n")
                write("Notes: \(entry.participatingNotes.map(\.title).joined(separator: ", "))\n\n")
                for statement in entry.statements {
                    write("- \(statement.attribution): \(statement.text)\n")
                }
            }
        case "reply":
            guard arguments.count >= 2, let id = UUID(uuidString: arguments[1]) else {
                throw commandUsageError("discuss reply")
            }
            let agentName = option("--agent", in: arguments)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let agentName, !agentName.isEmpty else {
                throw CLIError.usage("Discuss replies require --agent <name>. External Agents must use authenticated scholium agent discuss-reply.")
            }
            let replyText: String
            if let text = option("--text", in: arguments) {
                replyText = text
            } else if let file = option("--from", in: arguments) {
                let data = file == "-"
                    ? FileHandle.standardInput.readDataToEndOfFile()
                    : try Data(contentsOf: URL(
                        fileURLWithPath: (file as NSString).expandingTildeInPath
                    ))
                guard let decoded = String(data: data, encoding: .utf8) else {
                    throw CLIError.invalidUTF8(file)
                }
                replyText = decoded
            } else {
                throw CLIError.usage("Discuss replies require --text <reply> or --from <file|->.")
            }
            guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Discuss reply text cannot be empty.")
            }
            let statementID = UUID()
            let record = try await research.replyToDiscussionAndFinish(
                discussionID: id,
                statementID: statementID,
                attribution: agentName,
                text: replyText
            )
            guard record.statements.contains(where: {
                $0.id == statementID && $0.author == .agent
            }) else {
                throw CLIError.unavailable("The Discuss reply was not available after persistence.")
            }
            write("Recorded reply \(statementID.uuidString) and formed Research Record \(id.uuidString).\n")
        default:
            throw CLIError.usage("Unknown Discuss command '\(subcommand)'.")
        }
    }

}
