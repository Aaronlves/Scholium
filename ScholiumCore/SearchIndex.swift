import ScholiumContracts
import Foundation
import SQLite3

public struct SearchIndexOpenResult: Sendable {
    public let index: SQLiteSearchIndex
    public let recoveredCorruption: Bool

    public init(index: SQLiteSearchIndex, recoveredCorruption: Bool) {
        self.index = index
        self.recoveredCorruption = recoveredCorruption
    }
}

private extension SearchIndexError {
    var permitsGeneratedDatabaseRecovery: Bool {
        switch self {
        case .corruptDatabase, .incompatibleSchema: true
        default: false
        }
    }
}

public actor SQLiteSearchIndex {
    private static let schemaVersion = IndexGeneration.contractVersion
    private let vaultID: UUID
    private let database: SQLiteDatabase

    public init(databaseURL: URL, vaultID: UUID) throws {
        self.vaultID = vaultID
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        database = try SQLiteDatabase(path: databaseURL.path)
        try database.execute("PRAGMA journal_mode=WAL;")
        try database.execute("PRAGMA synchronous=NORMAL;")
        try Self.createSchema(in: database)
        try Self.validateSchema(in: database)
    }

    /// Opens a disposable index and recovers a missing or corrupt database by
    /// replacing only the generated SQLite file and its sidecars. Research
    /// files are never involved in this recovery path.
    public nonisolated static func openRecovering(
        databaseURL: URL,
        vaultID: UUID
    ) throws -> SearchIndexOpenResult {
        do {
            return SearchIndexOpenResult(
                index: try SQLiteSearchIndex(databaseURL: databaseURL, vaultID: vaultID),
                recoveredCorruption: false
            )
        } catch let error as SearchIndexError where error.permitsGeneratedDatabaseRecovery {
            let manager = FileManager.default
            for url in [
                databaseURL,
                URL(fileURLWithPath: databaseURL.path + "-wal"),
                URL(fileURLWithPath: databaseURL.path + "-shm"),
            ] where manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
            }
            return SearchIndexOpenResult(
                index: try SQLiteSearchIndex(databaseURL: databaseURL, vaultID: vaultID),
                recoveredCorruption: true
            )
        }
    }

    public static func databaseURL(applicationSupportURL: URL, vaultID: UUID) -> URL {
        applicationSupportURL
            .appendingPathComponent("Vaults", isDirectory: true)
            .appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("search-v1.sqlite", isDirectory: false)
    }

    public func rebuild(_ documents: [SearchIndexDocument]) throws -> IndexGeneration {
        let descriptor = documents.first.map { (name: $0.vaultName, role: $0.vaultRole) }
        return try rebuild(
            documents,
            vaultName: descriptor?.name,
            vaultRole: descriptor?.role
        )
    }

    private func rebuild(
        _ documents: [SearchIndexDocument],
        vaultName: String?,
        vaultRole: VaultRole?
    ) throws -> IndexGeneration {
        try database.transaction {
            try database.execute("DELETE FROM search_index;")
            try database.execute("DELETE FROM file_fingerprints;")
            try database.execute("DELETE FROM index_metadata;")
            for document in documents.sorted(by: { $0.relativePath < $1.relativePath }) {
                try Self.insert(document, into: database)
            }
            if let vaultName, let vaultRole {
                try database.execute(
                    "INSERT INTO index_metadata(key, value) VALUES('vault_name', ?);",
                    bindings: [.text(vaultName)]
                )
                try database.execute(
                    "INSERT INTO index_metadata(key, value) VALUES('vault_role', ?);",
                    bindings: [.text(vaultRole.rawValue)]
                )
            }
            try Self.advanceGeneration(in: database)
        }
        return try generation()
    }

    public func apply(_ mutations: [SearchIndexMutation]) throws -> IndexGeneration {
        guard !mutations.isEmpty else { return try generation() }
        try database.transaction {
            for mutation in mutations {
                switch mutation {
                case .delete(let relativePath):
                    try Self.delete(relativePath: relativePath, from: database)
                case .upsert(let document):
                    try Self.delete(relativePath: document.relativePath, from: database)
                    try Self.insert(document, into: database)
                }
            }
            try Self.advanceGeneration(in: database)
        }
        return try generation()
    }

    /// Makes the persisted rows exactly equal to the supplied complete vault
    /// projection. Only changed fingerprints, deleted paths, and rows whose
    /// derived broken-link bit changed are mutated. The resulting generation
    /// is therefore equivalent to a clean rebuild over the same documents.
    public func synchronize(
        _ documents: [SearchIndexDocument],
        vaultName: String,
        vaultRole: VaultRole,
        forceRebuild: Bool = false,
        recoveredCorruption: Bool = false
    ) throws -> SearchIndexSyncResult {
        var desired: [String: SearchIndexDocument] = [:]
        for document in documents {
            guard document.vaultID == vaultID else {
                throw SearchIndexError.invalidDocuments("a document belongs to another vault")
            }
            guard desired.updateValue(document, forKey: document.relativePath) == nil else {
                throw SearchIndexError.invalidDocuments("duplicate relative path \(document.relativePath)")
            }
        }

        let existing = try generation()
        let descriptor = try indexedVaultDescriptor()
        let descriptorChanged = descriptor?.name != vaultName || descriptor?.role != vaultRole
        if forceRebuild || recoveredCorruption || existing.sequence == 0 || descriptorChanged {
            let generation = try rebuild(
                documents,
                vaultName: vaultName,
                vaultRole: vaultRole
            )
            return SearchIndexSyncResult(
                generation: generation,
                disposition: recoveredCorruption ? .recoveredAndRebuilt : .rebuilt
            )
        }

        let desiredPaths = Set(desired.keys)
        let storedPaths = Set(existing.fingerprints.keys)
        let storedBroken = try indexedBrokenLinkPaths()
        let storedReviews = try indexedReviewStates()
        var mutations = storedPaths.subtracting(desiredPaths)
            .sorted()
            .map(SearchIndexMutation.delete(relativePath:))
        for path in desiredPaths.sorted() {
            guard let document = desired[path] else { continue }
            let fingerprintChanged = existing.fingerprints[path] != document.document.fingerprint
            let brokenChanged = storedBroken.contains(path) != document.hasBrokenLink
            let reviewChanged = (storedReviews[path] ?? "") != (document.review ?? "")
            if fingerprintChanged || brokenChanged || reviewChanged {
                mutations.append(.upsert(document))
            }
        }
        guard !mutations.isEmpty else {
            return SearchIndexSyncResult(generation: existing, disposition: .unchanged)
        }
        let generation = try apply(mutations)
        return SearchIndexSyncResult(generation: generation, disposition: .incrementallyUpdated)
    }

    public func generation() throws -> IndexGeneration {
        let sequence = try database.scalarInt("SELECT value FROM index_state WHERE key = 'generation';") ?? 0
        var fingerprints: [String: DocumentFingerprint] = [:]
        try database.query("SELECT relative_path, sha256, byte_count FROM file_fingerprints ORDER BY relative_path;") { statement in
            guard let path = statement.text(at: 0), let sha = statement.text(at: 1) else { return }
            fingerprints[path] = DocumentFingerprint(sha256: sha, byteCount: statement.int(at: 2))
        }
        return IndexGeneration(
            vaultID: vaultID,
            sequence: sequence,
            contractVersion: Self.schemaVersion,
            fingerprints: fingerprints
        )
    }

    /// Returns whether the persisted lexical projection already represents
    /// this complete vault inventory and its current registry descriptor.
    /// Callers can use this inexpensive check before constructing Markdown
    /// semantics and relationship diagnostics for an unchanged vault.
    public func matches(
        fingerprints: [String: DocumentFingerprint],
        vaultName: String,
        vaultRole: VaultRole
    ) throws -> Bool {
        let current = try generation()
        guard current.sequence > 0, current.fingerprints == fingerprints else {
            return false
        }
        let descriptor = try indexedVaultDescriptor()
        return descriptor?.name == vaultName && descriptor?.role == vaultRole
    }

    public func indexedBrokenLinkPaths() throws -> Set<String> {
        var paths = Set<String>()
        try database.query("SELECT relative_path FROM search_index WHERE broken_link = '1' ORDER BY relative_path;") {
            if let path = $0.text(at: 0) { paths.insert(path) }
        }
        return paths
    }

    private func indexedReviewStates() throws -> [String: String] {
        var states: [String: String] = [:]
        try database.query("SELECT relative_path, review FROM search_index ORDER BY relative_path;") {
            if let path = $0.text(at: 0) { states[path] = $0.text(at: 1) ?? "" }
        }
        return states
    }

    public func search(
        _ query: SearchQuery,
        filter explicitFilter: SearchFilter = SearchFilter(),
        limit: Int = 50
    ) throws -> [SearchHit] {
        let parsed = try ParsedSearchQuery(query.rawValue, explicitFilter: explicitFilter)
        guard !parsed.matchExpression.isEmpty, limit > 0 else { return [] }
        let generation = try generation().sequence
        var sql = """
        -- Field weights keep high-signal document identity ahead of ordinary prose:
        -- title > alias > heading/bibliographic fields > body.
        SELECT vault_id, vault_name, role, relative_path, stable_note_id, title,
               aliases, headings, author, year, tags, status, review, body,
               callouts, footnotes, metadata, fingerprint, layer, broken_link,
               source,
               bm25(search_index, 0.0, 0.0, 0.0, 3.0, 0.0, 8.0, 7.0, 6.0, 6.0, 4.0, 5.0, 4.0, 3.0, 1.0, 2.0, 2.0, 2.0, 0.0, 0.0, 0.0, 0.0) AS rank
        FROM search_index WHERE search_index MATCH ?
        """
        var bindings: [SQLiteBinding] = [.text(parsed.matchExpression)]
        for predicate in parsed.sqlPredicates {
            sql += " AND \(predicate.column) = ?"
            bindings.append(.text(predicate.value))
        }
        sql += " ORDER BY rank ASC, title COLLATE NOCASE ASC, relative_path ASC LIMIT ?;"
        bindings.append(.int(max(1, min(limit, 500))))

        var hits: [SearchHit] = []
        try database.query(sql, bindings: bindings) { statement in
            guard let vaultText = statement.text(at: 0),
                  let resultVaultID = UUID(uuidString: vaultText),
                  let vaultName = statement.text(at: 1),
                  let roleText = statement.text(at: 2),
                  let role = VaultRole(rawValue: roleText),
                  let relativePath = statement.text(at: 3),
                  let title = statement.text(at: 5),
                  let fingerprint = statement.text(at: 17),
                  let layerText = statement.text(at: 18),
                  let layer = EvidentialLayer(rawValue: layerText),
                  let source = statement.text(at: 20) else { return }

            let fields: [(SearchMatchedField, String)] = [
                (.title, title), (.alias, statement.text(at: 6) ?? ""),
                (.heading, statement.text(at: 7) ?? ""), (.author, statement.text(at: 8) ?? ""),
                (.tag, statement.text(at: 10) ?? ""), (.year, statement.text(at: 9) ?? ""),
                (.status, statement.text(at: 11) ?? ""), (.metadata, statement.text(at: 16) ?? ""),
                (.callout, statement.text(at: 14) ?? ""), (.footnote, statement.text(at: 15) ?? ""),
                (.body, statement.text(at: 13) ?? ""), (.path, relativePath)
            ]
            let best = parsed.bestMatch(in: fields)
            let document = NoteDocument(relativePath: relativePath, rawContent: source)
            let displayTitle = document.parsedFrontmatter["title"]?.searchStrings.first
                ?? (relativePath as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
            let presentation = Self.presentation(
                for: best.0,
                parsed: parsed,
                document: document,
                relativePath: relativePath
            )
            hits.append(SearchHit(
                vaultID: resultVaultID,
                vaultName: vaultName,
                vaultRole: role,
                relativePath: relativePath,
                stableNoteID: statement.text(at: 4),
                title: displayTitle,
                matchedField: best.0,
                context: Self.contextLabel(for: best.0),
                sourceLine: presentation.sourceLine,
                snippet: presentation.snippet.text,
                highlights: presentation.snippet.highlights,
                score: -statement.double(at: 21),
                fingerprint: DocumentFingerprint(sha256: fingerprint, byteCount: source.utf8.count),
                indexGeneration: generation,
                evidentialLayer: layer,
                classification: .retrievalLead
            ))
        }
        return hits
    }

    private static func createSchema(in database: SQLiteDatabase) throws {
        try database.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
            vault_id UNINDEXED, vault_name UNINDEXED, role UNINDEXED, relative_path,
            stable_note_id UNINDEXED, title, aliases, headings, author, year, tags,
            status, review, body, callouts, footnotes, metadata, fingerprint UNINDEXED,
            layer UNINDEXED, broken_link UNINDEXED, source UNINDEXED,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        CREATE TABLE IF NOT EXISTS index_state(key TEXT PRIMARY KEY, value INTEGER NOT NULL);
        INSERT OR IGNORE INTO index_state(key, value) VALUES('generation', 0);
        INSERT OR IGNORE INTO index_state(key, value) VALUES('contract_version', \(schemaVersion));
        CREATE TABLE IF NOT EXISTS index_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS file_fingerprints(
            relative_path TEXT PRIMARY KEY, sha256 TEXT NOT NULL, byte_count INTEGER NOT NULL
        );
        """)
    }

    private static func validateSchema(in database: SQLiteDatabase) throws {
        guard try database.scalarText("PRAGMA quick_check;") == "ok" else {
            throw SearchIndexError.corruptDatabase
        }
        guard try database.scalarInt(
            "SELECT value FROM index_state WHERE key = 'contract_version';"
        ) == schemaVersion else {
            throw SearchIndexError.incompatibleSchema
        }
        let definition = try database.scalarText(
            "SELECT sql FROM sqlite_master WHERE name = 'search_index';"
        )?.uppercased()
        guard definition?.contains("VIRTUAL TABLE") == true,
              definition?.contains("USING FTS5") == true else {
            throw SearchIndexError.incompatibleSchema
        }
    }

    private func indexedVaultDescriptor() throws -> (name: String, role: VaultRole)? {
        guard let name = try database.scalarText(
            "SELECT value FROM index_metadata WHERE key = 'vault_name';"
        ), let roleText = try database.scalarText(
            "SELECT value FROM index_metadata WHERE key = 'vault_role';"
        ), let role = VaultRole(rawValue: roleText) else { return nil }
        return (name, role)
    }

    private static func insert(_ item: SearchIndexDocument, into database: SQLiteDatabase) throws {
        let headings = item.semantic.headings.map(\.text).joined(separator: "\n")
        let callouts = item.semantic.callouts.map {
            "\($0.kind) \($0.rawKind) \($0.role.displayLabel) \($0.title ?? "") \($0.bodySource)"
        }.joined(separator: "\n")
        let footnotes = item.semantic.footnoteDefinitions.map { $0.content }.joined(separator: "\n")
        let metadata = item.document.parsedFrontmatter.keys.sorted().compactMap { key in
            item.document.parsedFrontmatter[key].map { "\(key) \($0.displayScalar)" }
        }.joined(separator: "\n")
        try database.execute(
            """
            INSERT INTO search_index(
                vault_id, vault_name, role, relative_path, stable_note_id, title, aliases,
                headings, author, year, tags, status, review, body, callouts, footnotes,
                metadata, fingerprint, layer, broken_link, source
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text(item.vaultID.uuidString), .text(item.vaultName), .text(item.vaultRole.rawValue),
                .text(item.relativePath), .optionalText(item.stableNoteID), .text(Self.indexable(item.title)),
                .text(Self.indexable(item.aliases.joined(separator: " "))), .text(Self.indexable(headings)),
                .text(Self.indexable(item.authors.joined(separator: " "))), .optionalText(item.year.map(Self.indexable)),
                .text(Self.indexable(item.tags.joined(separator: " "))), .optionalText(item.status.map(Self.indexable)),
                .optionalText(item.review.map(Self.indexable)), .text(Self.indexable(item.document.body)),
                .text(Self.indexable(callouts)), .text(Self.indexable(footnotes)), .text(Self.indexable(metadata)),
                .text(item.document.fingerprint.sha256), .text(item.evidentialLayer.rawValue),
                .text(item.hasBrokenLink ? "1" : "0"), .text(item.document.rawContent)
            ]
        )
        try database.execute(
            "INSERT INTO file_fingerprints(relative_path, sha256, byte_count) VALUES(?, ?, ?);",
            bindings: [.text(item.relativePath), .text(item.document.fingerprint.sha256), .int(item.document.fingerprint.byteCount)]
        )
    }

    private static func delete(relativePath: String, from database: SQLiteDatabase) throws {
        try database.execute("DELETE FROM search_index WHERE relative_path = ?;", bindings: [.text(relativePath)])
        try database.execute("DELETE FROM file_fingerprints WHERE relative_path = ?;", bindings: [.text(relativePath)])
    }

    private static func advanceGeneration(in database: SQLiteDatabase) throws {
        try database.execute("UPDATE index_state SET value = value + 1 WHERE key = 'generation';")
    }

    private static func indexable(_ value: String) -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
        var additions: [String] = []
        let characters = Array(normalized)
        for character in characters where character.unicodeScalars.contains(where: isCJK) {
            additions.append(String(character))
        }
        if characters.count > 1 {
            for index in 0..<(characters.count - 1) where
                characters[index].unicodeScalars.contains(where: isCJK)
                    || characters[index + 1].unicodeScalars.contains(where: isCJK) {
                additions.append(String(characters[index...index + 1]))
            }
        }
        return additions.isEmpty ? normalized : normalized + " " + additions.joined(separator: " ")
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xAC00...0xD7AF: true
        default: false
        }
    }

    private static func lineNumber(in source: String, before index: String.Index?) -> Int {
        guard let index else { return 1 }
        return source[..<index].reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
    }

    private static func presentation(
        for field: SearchMatchedField,
        parsed: ParsedSearchQuery,
        document: NoteDocument,
        relativePath: String
    ) -> (snippet: (text: String, highlights: [SearchHighlight]), sourceLine: Int) {
        let bodyMatch = parsed.firstSourceMatch(in: document.body)
        if [.body, .callout, .footnote].contains(field) {
            let visibleBody = MarkdownVisibleText.render(document.body)
            let visibleMatch = parsed.firstSourceMatch(in: visibleBody)
            let matchedSourceIndex: String.Index?
            if let bodyMatch {
                matchedSourceIndex = sourceIndex(
                    for: bodyMatch.lowerBound,
                    inBodyOf: document
                )
            } else {
                matchedSourceIndex = nil
            }
            return (
                snippet(source: visibleBody, match: visibleMatch),
                lineNumber(in: document.rawContent, before: matchedSourceIndex)
            )
        }

        let preview = fieldPreview(
            for: field,
            parsed: parsed,
            document: document,
            relativePath: relativePath
        )
        let previewMatch = parsed.firstSourceMatch(in: preview)
        let sourceMatch = parsed.firstSourceMatch(in: document.rawContent)
        return (
            snippet(source: preview, match: previewMatch),
            lineNumber(in: document.rawContent, before: sourceMatch?.lowerBound)
        )
    }

    private static func fieldPreview(
        for field: SearchMatchedField,
        parsed: ParsedSearchQuery,
        document: NoteDocument,
        relativePath: String
    ) -> String {
        let values: [String]
        switch field {
        case .title:
            values = document.parsedFrontmatter["title"]?.searchStrings ?? []
        case .alias:
            values = document.parsedFrontmatter["aliases"]?.searchStrings
                ?? document.parsedFrontmatter["alias"]?.searchStrings
                ?? []
        case .heading:
            values = MarkdownSemanticDocument(parsing: document).headings.map(\.text)
        case .author:
            values = document.parsedFrontmatter["authors"]?.searchStrings
                ?? document.parsedFrontmatter["author"]?.searchStrings
                ?? []
        case .year:
            values = document.parsedFrontmatter["year"]?.searchStrings ?? []
        case .tag:
            values = document.parsedFrontmatter["tags"]?.searchStrings ?? []
        case .status:
            values = ["status", "analysis_status", "lifecycle_status"]
                .flatMap { document.parsedFrontmatter[$0]?.searchStrings ?? [] }
        case .metadata:
            for key in document.parsedFrontmatter.keys.sorted() {
                let candidates = document.parsedFrontmatter[key]?.searchStrings ?? []
                if let value = parsed.firstMatchingValue(in: candidates) {
                    return "\(key): \(value)"
                }
            }
            values = []
        case .path:
            values = [relativePath]
        case .body, .callout, .footnote:
            values = []
        }
        return parsed.firstMatchingValue(in: values)
            ?? values.first
            ?? String(document.body.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sourceIndex(
        for bodyIndex: String.Index,
        inBodyOf document: NoteDocument
    ) -> String.Index? {
        guard let bodyUTF8Index = bodyIndex.samePosition(in: document.body.utf8) else { return nil }
        let bodyOffset = document.body.utf8.distance(from: document.body.utf8.startIndex, to: bodyUTF8Index)
        let sourceOffset = document.bodyByteRange.lowerBound + bodyOffset
        guard let sourceUTF8Index = document.rawContent.utf8.index(
            document.rawContent.utf8.startIndex,
            offsetBy: sourceOffset,
            limitedBy: document.rawContent.utf8.endIndex
        ) else { return nil }
        return sourceUTF8Index.samePosition(in: document.rawContent)
    }

    private static func contextLabel(for field: SearchMatchedField) -> String {
        switch field {
        case .title: "Title"
        case .alias: "Alias"
        case .heading: "Heading"
        case .author: "Author"
        case .year: "Year"
        case .tag: "Tag"
        case .status: "Status"
        case .body: "Body"
        case .callout: "Callout"
        case .footnote: "Footnote"
        case .metadata: "Metadata"
        case .path: "Path"
        }
    }

    private static func snippet(source: String, match: Range<String.Index>?) -> (text: String, highlights: [SearchHighlight]) {
        guard let match else {
            let text = String(source.prefix(220)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (text, [])
        }
        let lower = source.index(match.lowerBound, offsetBy: -80, limitedBy: source.startIndex) ?? source.startIndex
        let upper = source.index(match.upperBound, offsetBy: 140, limitedBy: source.endIndex) ?? source.endIndex
        let core = String(source[lower..<upper]).replacingOccurrences(of: "\n", with: " ")
        let prefix = lower == source.startIndex ? "" : "…"
        let suffix = upper == source.endIndex ? "" : "…"
        let before = String(source[lower..<match.lowerBound]).replacingOccurrences(of: "\n", with: " ")
        let selected = String(source[match]).replacingOccurrences(of: "\n", with: " ")
        let start = (prefix + before).utf16.count
        return (prefix + core + suffix, [SearchHighlight(utf16LowerBound: start, utf16UpperBound: start + selected.utf16.count)])
    }
}

public enum FederatedSearchEngine {
    public static func search(
        _ query: SearchQuery,
        indexes: [(vault: RegisteredVault, index: SQLiteSearchIndex)],
        limit: Int = 50
    ) async throws -> [SearchHit] {
        var hits: [SearchHit] = []
        for item in indexes {
            hits.append(contentsOf: try await item.index.search(query, limit: limit))
        }
        return hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if $0.vaultID != $1.vaultID { return $0.vaultID.uuidString < $1.vaultID.uuidString }
            return $0.relativePath < $1.relativePath
        }.prefix(limit).map { $0 }
    }
}

private struct ParsedSearchQuery {
    struct SQLPredicate { let column: String; let value: String }
    let matchExpression: String
    let sqlPredicates: [SQLPredicate]
    let positiveTerms: [String]

    init(_ raw: String, explicitFilter: SearchFilter) throws {
        let tokens = try Self.tokens(raw)
        var positiveExpressions: [String] = []
        var negativeExpressions: [String] = []
        var positives: [String] = []
        var sql: [SQLPredicate] = []
        var queryFilter = explicitFilter

        for token in tokens {
            let excluded = token.hasPrefix("-")
            let value = excluded ? String(token.dropFirst()) : token
            guard !value.isEmpty else {
                throw SearchIndexError.invalidQuery("a minus sign must be followed by a search term")
            }
            if let colon = value.firstIndex(of: ":") {
                let field = String(value[..<colon]).lowercased()
                let fieldValue = String(value[value.index(after: colon)...])
                guard !fieldValue.isEmpty else {
                    throw SearchIndexError.invalidQuery("filter \(field) requires a value")
                }
                switch field {
                case "vault": queryFilter.vault = fieldValue
                case "role":
                    guard let role = VaultRole(commandLineValue: fieldValue) else {
                        throw SearchIndexError.invalidQuery("unknown role \(fieldValue)")
                    }
                    queryFilter.role = role
                case "status": queryFilter.status = fieldValue
                case "review": queryFilter.review = fieldValue
                case "callout": queryFilter.callout = fieldValue
                case "has" where fieldValue == "broken-link": queryFilter.hasBrokenLink = true
                case "title", "alias", "heading", "author", "year", "tag", "path", "metadata":
                    let column = switch field {
                    case "alias": "aliases"
                    case "heading": "headings"
                    case "tag": "tags"
                    default: field
                    }
                    let expression = Self.expression(fieldValue, column: column)
                    if excluded { negativeExpressions.append(expression) } else { positiveExpressions.append(expression) }
                    if !excluded { positives.append(Self.matchTerm(fieldValue)) }
                default:
                    throw SearchIndexError.invalidQuery("unknown filter \(field)")
                }
            } else {
                let expression = Self.expression(value, column: nil)
                if excluded { negativeExpressions.append(expression) } else { positiveExpressions.append(expression) }
                if !excluded { positives.append(Self.matchTerm(value)) }
            }
        }
        if let vault = queryFilter.vault { sql.append(SQLPredicate(column: "vault_name", value: vault)) }
        if let role = queryFilter.role { sql.append(SQLPredicate(column: "role", value: role.rawValue)) }
        if let relativePath = queryFilter.relativePath {
            sql.append(SQLPredicate(column: "relative_path", value: relativePath))
        }
        if let status = queryFilter.status { sql.append(SQLPredicate(column: "status", value: status)) }
        if let review = queryFilter.review { sql.append(SQLPredicate(column: "review", value: review)) }
        if let broken = queryFilter.hasBrokenLink { sql.append(SQLPredicate(column: "broken_link", value: broken ? "1" : "0")) }
        if let callout = queryFilter.callout {
            positiveExpressions.append(Self.expression(callout, column: "callouts"))
            positives.append(Self.matchTerm(callout))
        }
        guard !positiveExpressions.isEmpty else {
            throw SearchIndexError.invalidQuery("at least one positive search term is required")
        }
        matchExpression = positiveExpressions.joined(separator: " AND ")
            + negativeExpressions.map { " NOT \($0)" }.joined()
        sqlPredicates = sql
        positiveTerms = positives.filter { !$0.isEmpty }
    }

    func bestMatch(in fields: [(SearchMatchedField, String)]) -> (SearchMatchedField, String) {
        for field in fields {
            if positiveTerms.contains(where: { field.1.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
                return field
            }
        }
        return fields.last ?? (.body, "")
    }

    func firstSourceMatch(in source: String) -> Range<String.Index>? {
        for term in positiveTerms {
            if let range = source.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) { return range }
        }
        return nil
    }

    func firstMatchingValue(in values: [String]) -> String? {
        values.first { value in
            positiveTerms.contains {
                value.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private static func tokens(_ raw: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in raw {
            if character == "\"" {
                quoted.toggle()
                current.append(character)
            } else if character.isWhitespace, !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        guard !quoted else {
            throw SearchIndexError.invalidQuery("a quoted phrase is missing its closing quotation mark")
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func expression(_ raw: String, column: String?) -> String {
        let plain = plain(raw)
        let isPhrase = raw.hasPrefix("\"") && raw.hasSuffix("\"")
        let isPrefix = !isPhrase && plain.hasSuffix("*")
        let core = isPrefix ? String(plain.dropLast()) : plain
        let escaped = core.replacingOccurrences(of: "\"", with: "\"\"")
        let term = "\"\(escaped)\"" + (isPrefix ? "*" : "")
        return column.map { "\($0):\(term)" } ?? term
    }

    private static func plain(_ raw: String) -> String {
        var value = raw
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst(); value.removeLast()
        }
        return value.precomposedStringWithCanonicalMapping
    }

    private static func matchTerm(_ raw: String) -> String {
        let value = plain(raw)
        return value.hasSuffix("*") ? String(value.dropLast()) : value
    }
}

private enum SQLiteBinding {
    case text(String)
    case optionalText(String?)
    case int(Int)
}

private final class SQLiteDatabase: @unchecked Sendable {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "could not open database"
            let code = handle.map { sqlite3_extended_errcode($0) }
            if let handle { sqlite3_close(handle) }
            if code.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
                throw SearchIndexError.corruptDatabase
            }
            throw SearchIndexError.sqlite(message)
        }
        sqlite3_busy_timeout(handle, 3_000)
    }

    deinit { if let handle { sqlite3_close(handle) } }

    func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        if bindings.isEmpty {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? lastError
                sqlite3_free(error)
                throw sqliteError(message: message)
            }
            return
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        try statement.bind(bindings)
        guard sqlite3_step(statement.handle) == SQLITE_DONE else { throw sqliteError() }
    }

    func query(_ sql: String, bindings: [SQLiteBinding] = [], row: (SQLiteStatement) throws -> Void) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement.handle) }
        try statement.bind(bindings)
        while true {
            switch sqlite3_step(statement.handle) {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw sqliteError()
            }
        }
    }

    func scalarInt(_ sql: String) throws -> Int? {
        var result: Int?
        try query(sql) { result = $0.int(at: 0) }
        return result
    }

    func scalarText(_ sql: String) throws -> String? {
        var result: String?
        try query(sql) { result = $0.text(at: 0) }
        return result
    }

    func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try operation()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw sqliteError()
        }
        return SQLiteStatement(handle: statement)
    }

    private var lastError: String { handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error" }

    private func sqliteError(message: String? = nil) -> SearchIndexError {
        let code = handle.map { sqlite3_extended_errcode($0) }
        if code.map({ ($0 & 0xFF) == SQLITE_CORRUPT || ($0 & 0xFF) == SQLITE_NOTADB }) == true {
            return .corruptDatabase
        }
        return .sqlite(message ?? lastError)
    }
}

private struct SQLiteStatement {
    let handle: OpaquePointer

    func bind(_ values: [SQLiteBinding]) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch value {
            case .text(let text): text.withCString { sqlite3_bind_text(handle, index, $0, -1, SQLITE_TRANSIENT) }
            case .optionalText(let text):
                if let text { text.withCString { sqlite3_bind_text(handle, index, $0, -1, SQLITE_TRANSIENT) } }
                else { sqlite3_bind_null(handle, index) }
            case .int(let value): sqlite3_bind_int64(handle, index, sqlite3_int64(value))
            }
            guard result == SQLITE_OK else { throw SearchIndexError.sqlite("could not bind search parameter") }
        }
    }

    func text(at column: Int32) -> String? {
        guard let value = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: value)
    }

    func int(at column: Int32) -> Int { Int(sqlite3_column_int64(handle, column)) }
    func double(at column: Int32) -> Double { sqlite3_column_double(handle, column) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
