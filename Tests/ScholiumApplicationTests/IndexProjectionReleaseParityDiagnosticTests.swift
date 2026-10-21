import CryptoKit
import Foundation
import SQLite3
import ScholiumApplication
import ScholiumContracts

#if !INDEX_PROJECTION_PARITY_EXECUTABLE
    import Testing

    @Suite(
        "Captured Release index parity", .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_INDEX_RELEASE_PARITY"] == "1"))
    struct IndexProjectionReleaseParityDiagnosticTests {
        @Test("An actual Release index agrees with a clean rebuild of its exact sources")
        @MainActor func capturedIndex() async throws {
            try await IndexProjectionReleaseParityDiagnostic.run(ProcessInfo.processInfo.environment)
        }
    }
#else
    @main struct IndexProjectionReleaseParityMain {
        @MainActor static func main() async throws {
            try await IndexProjectionReleaseParityDiagnostic.run(ProcessInfo.processInfo.environment)
        }
    }
#endif

/// Public Application APIs only: the task-local executable compiles this same
/// source in Release without compiling the repository's App test targets.
@MainActor private enum IndexProjectionReleaseParityDiagnostic {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static let manager = FileManager.default
    private static let slots = ["01-analyses", "02-topics", "03-works"]
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func encode(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func digest(_ bytes: Data) -> String { DocumentFingerprint(data: bytes).sha256 }

    private static func object<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let result = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] else {
            throw Failure(description: "Expected an encoded object")
        }
        return result
    }

    private static func write(_ value: Any, to url: URL) throws {
        try encode(value).write(to: url, options: .atomic)
    }

    #if INDEX_PROJECTION_PARITY_EXECUTABLE
        private static func backendBuildReceipt(inside build: URL) throws -> [String: Any] {
            let bytes = Data(IndexProjectionParityBuildReceipt.json.utf8)
            guard var receipt = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                let expected = receipt["expected_resolved_pins"] as? [[String: Any]],
                let rawPath = receipt["harness_resolved_path"] as? String
            else {
                throw Failure(description: "The Release harness has no App dependency-lock receipt")
            }
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL
            try require(
                path.path.hasPrefix(build.path + "/") && path == path.resolvingSymlinksInPath(),
                "Harness dependency lock must remain inside the disposable build tree")
            guard let lock = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any],
                let actual = lock["pins"] as? [[String: Any]], !actual.isEmpty
            else {
                throw Failure(description: "Built harness has no resolved dependency lock")
            }
            var observed = Set<String>()
            for pin in actual {
                guard let identity = pin["identity"] as? String,
                    let original = expected.first(where: { $0["identity"] as? String == identity })
                else {
                    throw Failure(description: "Harness resolved a dependency absent from the App lock")
                }
                try require(
                    observed.insert(identity).inserted && encode(pin) == encode(original),
                    "Harness dependency revision/version drifted from the actual App: \(identity)")
            }
            try require(
                observed.isSuperset(of: ["yams", "swift-markdown", "swift-subprocess"]),
                "Harness lock omits a required public-library dependency")
            receipt["resolved_pins_verified"] = true
            return receipt
        }
    #endif

    private static func directory(_ raw: String?, inside build: URL) throws -> URL {
        guard let raw else { throw Failure(description: "Missing diagnostic directory environment variable") }
        let value = URL(fileURLWithPath: raw).standardizedFileURL
        try require(
            value.path.hasPrefix(build.path + "/") && value == value.resolvingSymlinksInPath(),
            "Diagnostic paths must be nonsymlink descendants of this repository's .build")
        return value
    }

    private static func inspectTree(_ root: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let values = try root.resourceValues(forKeys: Set(keys))
        try require(values.isDirectory == true && values.isSymbolicLink != true, "Expected an ordinary diagnostic directory")
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw Failure(description: "Cannot enumerate diagnostic directory")
        }
        for case let url as URL in files {
            let entry = try url.resourceValues(forKeys: Set(keys))
            try require(
                entry.isSymbolicLink != true && (entry.isRegularFile == true || entry.isDirectory == true),
                "Diagnostic trees may contain only ordinary files and directories")
            // A fully stopped store may retain WAL/PERSIST journals. The
            // complete family is copied; only our work copy may recover it.
        }
    }

    private static func sources(_ root: URL) throws -> [String: DocumentFingerprint] {
        var result: [String: DocumentFingerprint] = [:]
        for (slot, expected) in zip(slots, [160, 220, 120]) {
            let directory = root.appendingPathComponent(slot)
            guard let files = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
                throw Failure(description: "Missing fixture role")
            }
            var count = 0
            for case let url as URL in files where url.pathExtension.lowercased() == "md" {
                let bytes = try Data(contentsOf: url)
                let source = String(decoding: bytes, as: UTF8.self)
                try require(Data(source.utf8) == bytes, "The source oracle must preserve every UTF-8 byte, including BOM and CRLF")
                result[String(url.path.dropFirst(root.path.count + 1))] = DocumentFingerprint(data: bytes)
                count += 1
            }
            try require(count == expected, "Expected the complete standard 500-note Triptych")
        }
        return result
    }

    private static func sourceRecords(_ oracle: [String: DocumentFingerprint]) throws -> [[String: Any]] {
        try oracle.keys.sorted().map { path in
            ["path": path, "fingerprint": try object(oracle[path]!)]
        }
    }

    /// Match the lifecycle wrapper's whole-fixture signature. Portable control
    /// is generated state; every other captured file remains byte-authoritative.
    private static func fixtureSignature(_ root: URL) throws -> [String: Any] {
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw Failure(description: "Cannot enumerate captured source files")
        }
        let files = enumerator.compactMap { $0 as? URL }.filter {
            !$0.path.dropFirst(root.path.count + 1).split(separator: "/").contains(".scholium")
                && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        var hasher = SHA256()
        var bytes = 0
        for file in files {
            let data = try Data(contentsOf: file)
            hasher.update(data: Data(String(file.path.dropFirst(root.path.count + 1)).utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            bytes += data.count
        }
        return ["sha256": hasher.finalize().map { String(format: "%02x", $0) }.joined(), "files": files.count, "bytes": bytes]
    }

    private static func source(_ path: String, root: URL) throws -> String {
        let bytes = try Data(contentsOf: root.appendingPathComponent(path))
        let result = String(decoding: bytes, as: UTF8.self)
        try require(Data(result.utf8) == bytes, "Source decoding changed bytes")
        return result
    }

    private static func path(_ id: VaultQualifiedNoteID, assignment: TriptychAssignment) throws -> String {
        guard let index = WorkspaceVaultSlot.allCases.firstIndex(where: { assignment.vault(for: $0)?.id == id.vaultID }) else {
            throw Failure(description: "Result belongs to an unauthorized vault")
        }
        return slots[index] + "/" + id.relativePath
    }

    private static func noteID(_ path: String, assignment: TriptychAssignment) throws -> VaultQualifiedNoteID {
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let slot = slots.firstIndex(of: parts[0]),
            let vault = assignment.vault(for: WorkspaceVaultSlot.allCases[slot])
        else {
            throw Failure(description: "Invalid fixture source identity")
        }
        return .init(vaultID: vault.id, relativePath: parts[1])
    }

    /// Independent coordinate oracle. A CRLF is one newline; offsets/columns
    /// count UTF-16 code units and include an authored BOM.
    private static func coordinate(_ offset: Int, in source: String) throws -> (Int, Int) {
        let units = Array(source.utf16)
        try require((0...units.count).contains(offset), "Source coordinate is outside its exact source")
        var index = 0
        var line = 1
        var column = 1
        while index < offset {
            if units[index] == 13 {
                index += 1
                if index < units.count && units[index] == 10 {
                    try require(index < offset, "A source coordinate splits CRLF")
                    index += 1
                }
                line += 1
                column = 1
            } else if units[index] == 10 {
                line += 1
                column = 1
                index += 1
            } else {
                column += 1
                index += 1
            }
        }
        return (line, column)
    }

    private static func validate(_ locator: SearchSourceRange, source: String) throws -> Data {
        try require(
            locator.utf16LowerBound >= 0 && locator.utf16UpperBound >= locator.utf16LowerBound,
            "Invalid source range")
        guard
            let range = Range(
                NSRange(
                    location: locator.utf16LowerBound,
                    length: locator.utf16UpperBound - locator.utf16LowerBound), in: source)
        else {
            throw Failure(description: "Source range splits Unicode or exceeds the source")
        }
        let lower = try coordinate(locator.utf16LowerBound, in: source)
        let upper = try coordinate(locator.utf16UpperBound, in: source)
        try require(
            lower == (locator.line, locator.column) && upper == (locator.endLine, locator.endColumn),
            "Source line/column disagrees with the exact UTF-16 range")
        return Data(source[range].utf8)
    }

    @MainActor private final class Database {
        private let handle: OpaquePointer
        init(_ url: URL) throws {
            var opened: OpaquePointer?
            let status = sqlite3_open_v2(
                url.path, &opened,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
            guard status == SQLITE_OK, let opened else {
                if let opened { sqlite3_close(opened) }
                throw Failure(description: "Cannot open copied SQLite database for journal recovery/audit")
            }
            handle = opened
        }
        isolated deinit { sqlite3_close(handle) }

        func rows(_ sql: String) throws -> [[String]] {
            var result: [[String]] = []
            try each(sql) { statement in
                result.append(
                    (0..<sqlite3_column_count(statement)).map { column in
                        String(decoding: Self.bytes(statement, column: column), as: UTF8.self)
                    })
            }
            return result
        }

        func audit() throws -> [String: Any] {
            let tables = try rows("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'search_%' ORDER BY name;")
                .map { $0[0] }.filter { $0 != "search_fts" }
            try require(tables.contains("search_documents") && tables.contains("search_segments"), "Missing Search payload tables")
            var report: [String: Any] = [:]
            for table in tables {
                try require(table.utf8.allSatisfy { (97...122).contains($0) || $0 == 95 }, "Unexpected SQLite table name")
                var hashes: [String] = []
                try each("SELECT * FROM \(table);") { statement in
                    var fields: [[String: Any]] = []
                    for column in 0..<sqlite3_column_count(statement) {
                        let name = String(cString: sqlite3_column_name(statement, column))
                        // An unchanged source refresh may advance only this
                        // runtime-local admission counter, without a new index.
                        if table == "search_index_state" && name == "workspace_generation" { continue }
                        let type = Int(sqlite3_column_type(statement, column))
                        let bytes = Self.bytes(statement, column: column)
                        fields.append([
                            "column": name, "type": type,
                            "bytes": bytes.count, "sha256": digest(bytes),
                        ])
                    }
                    hashes.append(digest(try encode(fields)))
                }
                report[table] = [
                    "rows": hashes.count, "ordered_row_hashes": hashes.sorted(),
                    "sha256": digest(Data(hashes.sorted().joined(separator: "\n").utf8)),
                ]
            }
            return report
        }

        private func each(_ sql: String, body: (OpaquePointer) throws -> Void) throws {
            var prepared: OpaquePointer?
            try require(sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, "Cannot prepare captured-index audit")
            guard let statement = prepared else { throw Failure(description: "Missing SQLite statement") }
            defer { sqlite3_finalize(statement) }
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                try require(status == SQLITE_ROW, "Captured-index audit failed")
                try body(statement)
            }
        }

        private static func bytes(_ statement: OpaquePointer, column: Int32) -> Data {
            if sqlite3_column_type(statement, column) == SQLITE_BLOB {
                let count = Int(sqlite3_column_bytes(statement, column))
                guard count > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
                return Data(bytes: pointer, count: count)
            }
            guard let pointer = sqlite3_column_text(statement, column) else { return Data() }
            return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
        }
    }

    private static func generation(_ database: Database) throws -> SearchGenerationID {
        let rows = try database.rows(
            """
            SELECT triptych_id, sequence, schema_version, query_contract_version,
                tokenizer_policy_version, ranking_policy_version, source_manifest_hash
            FROM search_index_state WHERE singleton = 1;
            """)
        guard rows.count == 1, let row = rows.first, let id = UUID(uuidString: row[0]),
            let sequence = Int(row[1]), sequence > 0, let schema = Int(row[2]),
            let query = Int(row[3]), let tokenizer = Int(row[4]), let ranking = Int(row[5])
        else {
            throw Failure(description: "Captured index has no complete generation")
        }
        return .init(
            triptychID: id, sequence: sequence, schemaVersion: schema, queryContractVersion: query,
            tokenizerPolicyVersion: tokenizer, rankingPolicyVersion: ranking, sourceManifestHash: row[6])
    }

    private static func validateSnapshot(
        _ snapshot: WorkspaceSnapshot, assignment: TriptychAssignment,
        oracle: [String: DocumentFingerprint]
    ) throws -> SearchGenerationID {
        try require(snapshot.phase.isComplete && snapshot.vaults.count == 3, "Workspace must publish a complete Triptych")
        let notes = snapshot.vaults.flatMap(\.documents)
        try require(notes.count == oracle.count, "Snapshot omitted source Notes")
        for note in notes {
            try require(note.fingerprint == oracle[try path(note.id, assignment: assignment)], "Snapshot has a different source revision")
            try require(note.stableIdentity.resolvedID != nil, "Missing portable stable Note identity")
        }
        let manifest = SearchSourceManifest.hash(
            notes.map {
                .init(vaultID: $0.id.vaultID, relativePath: $0.id.relativePath, fingerprint: $0.fingerprint)
            })
        guard let generation = snapshot.discovery.searchGeneration else { throw Failure(description: "No Search generation") }
        try require(
            generation.sourceManifestHash == manifest && snapshot.discovery.catalog.graph?.sourceManifestHash == manifest,
            "Search/Graph publication is not bound to the exact source manifest")
        try require(snapshot.research.healthIssues.isEmpty, "Unexpected workspace health issues")
        return generation
    }

    private static func responses(
        _ handle: WorkspaceHandle, root: URL,
        oracle: [String: DocumentFingerprint], partialOutput: URL
    ) async throws -> [String: Any] {
        let snapshot = try await handle.snapshot()
        let generation = try validateSnapshot(snapshot, assignment: handle.assignment, oracle: oracle)
        let queryCases: [(String, String, Set<String>?)] = [
            (
                "three_roles", "title:\"QA Autosave A\" OR title:\"QA Topic\" OR title:\"QA Work\"",
                ["01-analyses/QA Autosave A.md", "02-topics/QA Topic.md", "03-works/QA Work.md"]
            ),
            ("chinese", "晨光样本", ["02-topics/QA Topic.md"]),
            ("english", "\"aurora-fixture\"", ["02-topics/QA Topic.md"]),
            ("property", "property:qa_stage=draft", ["02-topics/QA Topic.md"]),
            ("unicode", "café", nil), ("unicode_decomposed", "cafe\u{301}", nil),
            ("fidelity", "BOM", ["02-topics/源码保真.md"]), ("paged_common", "测试", nil),
        ]
        var searches: [String: Any] = [:]
        for (label, query, expectedPaths) in queryCases {
            var pages: [[String: Any]] = []
            var seen = Set<VaultQualifiedNoteID>()
            var paths = Set<String>()
            var offset = 0
            var total: Int?
            while true {
                let response = try await handle.discovery.search(
                    .init(
                        query: query, presentationScope: .triptych,
                        executionScope: .triptych, limit: 17, offset: offset))
                try require(
                    response.availability == .current(generation) && response.freshnessToken == .triptych(generation),
                    "Search returned a stale or mixed generation")
                try require(response.diagnostics.isEmpty && response.indeterminateDocumentCount == 0, "Search is incomplete")
                guard let count = response.totalResultCount else { throw Failure(description: "Search omitted its complete result count") }
                if let total { try require(total == count, "Search pagination changed its total") } else { total = count }
                var results: [[String: Any]] = []
                let notes = response.results.map { result in
                    switch result {
                    case .note(let note): note
                    }
                }
                for result in notes {
                    try require(seen.insert(result.noteReference).inserted, "Search pagination repeated a Note")
                    let path = try path(result.noteReference, assignment: handle.assignment)
                    paths.insert(path)
                    try require(
                        result.fingerprint == oracle[path] && result.freshnessToken == response.freshnessToken,
                        "Search hit is not bound to the exact current source")
                    let original = try source(path, root: root)
                    try require(
                        snapshot.document(id: result.noteReference)?.stableIdentity.resolvedID?.uuidString.lowercased()
                            == result.stableNoteID, "Search changed the portable stable Note identity")
                    var spans: [String] = []
                    var locators = result.paragraphRanges + (result.sourceRange.map { [$0] } ?? [])
                    for reason in result.matchReasons {
                        if case .property(let property) = reason {
                            locators += property.valueSourceRanges + (property.keySourceRange.map { [$0] } ?? [])
                        }
                    }
                    for range in locators {
                        spans.append(digest(try validate(range, source: original)))
                    }
                    for highlight in result.highlights {
                        try require(
                            highlight.utf16LowerBound >= 0 && highlight.utf16UpperBound >= highlight.utf16LowerBound
                                && Range(
                                    NSRange(
                                        location: highlight.utf16LowerBound,
                                        length: highlight.utf16UpperBound - highlight.utf16LowerBound), in: result.snippet) != nil,
                            "Snippet highlight is outside the readable snippet")
                    }
                    if label == "fidelity" {
                        guard let range = result.sourceRange else {
                            throw Failure(description: "The frozen fidelity body hit must have a source locator")
                        }
                        try require(
                            String(decoding: validate(range, source: original), as: UTF8.self).contains("BOM"),
                            "Frozen fidelity query does not locate the original literal")
                    }
                    var record = try object(result)
                    record.removeValue(forKey: "freshnessToken")
                    record["exact_source_slice_sha256"] = spans
                    results.append(record)
                }
                try require(response.results.count == results.count, "Unexpected non-Note Search result")
                var page = try object(response)
                for key in ["requestID", "freshnessToken", "availability"] { page.removeValue(forKey: key) }
                page["results"] = results
                pages.append(page)
                offset += results.count
                try require(offset <= oracle.count, "Search pagination exceeded the source set")
                if !response.hasMore { break }
                try require(!results.isEmpty && offset < count, "Search pagination cannot make progress")
            }
            try require(offset == total, "Search pagination omitted results")
            if let expectedPaths { try require(paths == expectedPaths, "Frozen Search result set changed: \(label)") }
            if label == "paged_common" { try require(pages.count > 1, "The pagination oracle must exercise more than one page") }
            searches[label] = ["query": query, "pages": pages]
            try write(["search": searches, "related": [:]], to: partialOutput)
        }

        let seedPath = "02-topics/QA Topic.md"
        let seedSource = try source(seedPath, root: root)
        let seedID = try noteID(seedPath, assignment: handle.assignment)
        let focus = "中文检索标记：晨光样本。English marker: aurora-fixture."
        try require(seedSource.contains(focus), "Frozen Related focus is absent")
        let relatedCases: [(String, [RelatedContentSeedFocus])] = [
            ("whole_note", []), ("selected_passage", [.init(kind: .selectedPassage, text: focus)]),
            ("identity_and_annotation", [.init(kind: .researchRequest, text: "示例材料 QA Work 注释定位")]),
        ]
        var related: [String: Any] = [:]
        for (label, focuses) in relatedCases {
            let request = RelatedContentRequest(seed: .init(noteID: seedID, source: seedSource, focuses: focuses))
            var first: RelatedContentResponse?
            for _ in 0..<2 {
                let response = try await handle.discovery.relatedContent(request)
                try require(
                    response.requestID == request.id && response.seedFingerprint == request.seed.fingerprint,
                    "Related changed the frozen request or source")
                try require(
                    response.availability == .current(generation) && response.freshnessToken == .triptych(generation),
                    "Related returned a stale or mixed generation")
                try require(
                    response.omittedSourceCount == 0 && response.state == (response.passages.isEmpty ? .empty : .current),
                    "Related omitted a source or returned incomplete results")
                if label == "identity_and_annotation" {
                    let identities = try Set(response.identityCandidates.map { try path($0.note, assignment: handle.assignment) })
                    try require(
                        identities.isSuperset(of: ["01-analyses/示例材料.md", "03-works/QA Work.md"]),
                        "Frozen authored Note identities disappeared from Related")
                }
                if label == "whole_note" { try require(!response.passages.isEmpty, "The frozen linked seed must return Related passages") }
                for candidate in response.identityCandidates + response.lexicalCandidates + response.graphCandidates + response.passages.map(\.candidate) {
                    let path = try path(candidate.note, assignment: handle.assignment)
                    try require(
                        candidate.note != seedID && candidate.fingerprint == oracle[path]
                            && handle.assignment.vaults.values.contains { $0.id == candidate.note.vaultID && $0.role == candidate.vaultRole },
                        "Related candidate has stale source identity or role")
                }
                for passage in response.passages {
                    let path = try path(passage.candidate.note, assignment: handle.assignment)
                    let original = try source(path, root: root)
                    try require(Data(passage.source.utf8) == validate(passage.range, source: original), "Related passage changed original source bytes")
                    for match in passage.excerptMatches {
                        try require(
                            match.lowerBound >= 0 && match.upperBound >= match.lowerBound
                                && Range(NSRange(location: match.lowerBound, length: match.count), in: passage.excerpt) != nil,
                            "Related excerpt highlight is outside its readable excerpt")
                    }
                }
                if let first { try require(first == response, "An identical Related repeat changed ordered results") } else { first = response }
            }
            var record = try object(first!)
            for key in ["requestID", "freshnessToken", "availability"] { record.removeValue(forKey: key) }
            related[label] = record
            try write(["search": searches, "related": related], to: partialOutput)
        }
        try require(try await handle.snapshot().discovery.searchGeneration == generation, "Generation changed during the complete oracle")
        return ["search": searches, "related": related]
    }

    static func run(_ environment: [String: String]) async throws {
        guard environment["SCHOLIUM_INDEX_RELEASE_PARITY"] == "1",
            let repositoryPath = environment["SCHOLIUM_INDEX_PARITY_REPOSITORY"]
        else {
            throw Failure(description: "Opt in with SCHOLIUM_INDEX_RELEASE_PARITY=1 and an explicit repository")
        }
        let repository = URL(fileURLWithPath: repositoryPath).standardizedFileURL.resolvingSymlinksInPath()
        try require(manager.fileExists(atPath: repository.appendingPathComponent("Package.swift").path), "Missing Scholium package")
        let build = repository.appendingPathComponent(".build").resolvingSymlinksInPath()
        #if INDEX_PROJECTION_PARITY_EXECUTABLE
            let backendBuild = try backendBuildReceipt(inside: build)
        #else
            let backendBuild: [String: Any] = ["kind": "repository_test_target; build provenance recorded by caller"]
        #endif
        let capture = try directory(environment["SCHOLIUM_INDEX_PARITY_CAPTURE"], inside: build)
        let output = try directory(environment["SCHOLIUM_INDEX_PARITY_OUTPUT"], inside: build)
        try require(!output.path.hasPrefix(capture.path + "/") && output != capture, "Output must not modify its capture")
        try require(!manager.fileExists(atPath: output.path), "Diagnostic output must be new")
        try inspectTree(capture)
        let captureBytes = try Data(contentsOf: capture.appendingPathComponent("capture.json"))
        guard let provenance = try JSONSerialization.jsonObject(with: captureBytes) as? [String: Any] else {
            throw Failure(description: "Missing capture provenance")
        }
        try require(
            provenance["schema"] as? String == "scholium-index-release-capture-v1"
                && provenance["synthetic_nonprivate"] as? Bool == true && provenance["closed_original_state_verified"] as? Bool == true,
            "Only a closed actual-Release synthetic capture is admitted")
        let artifactHash = provenance["artifact_executable_sha256"] as? String ?? ""
        try require(
            artifactHash.utf8.count == 64 && artifactHash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) },
            "Capture must identify the actual Release executable")
        let fixture = capture.appendingPathComponent("fixture")
        let signature = try fixtureSignature(fixture)
        guard let expectedSignature = provenance["source"] as? [String: Any] else {
            throw Failure(description: "Capture has no source signature")
        }
        try require(encode(signature) == encode(expectedSignature), "Capture source files differ from its lifecycle receipt")
        let oracle = try sources(fixture)
        let originalRecords = try sourceRecords(oracle)
        let work = build.appendingPathComponent("index-projection-release-20261021/oracle-work/\(UUID().uuidString.lowercased())")
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: work) }
        let workingFixture = work.appendingPathComponent("fixture")
        let state = work.appendingPathComponent("state")
        try manager.copyItem(at: fixture, to: workingFixture)
        try manager.copyItem(at: capture.appendingPathComponent("state"), to: state)
        let support = state.appendingPathComponent("ApplicationSupport")
        let registry = state.appendingPathComponent("Registry")
        let registrationReader = try await WorkspaceRuntime.snapshot(applicationSupportURL: support, workspaceRegistryStorageURL: registry)
        let assignments: [TriptychAssignment]
        do { assignments = try await registrationReader.availableWorkspaces() } catch {
            await registrationReader.shutdown()
            throw error
        }
        await registrationReader.shutdown()
        try require(assignments.count == 1, "Expected exactly one captured Triptych")
        let previous = assignments[0]
        var vaults: [WorkspaceVaultSlot: RegisteredVault] = [:]
        for (slot, folder) in zip(WorkspaceVaultSlot.allCases, slots) {
            guard let old = previous.vault(for: slot) else { throw Failure(description: "Missing captured role") }
            let url = workingFixture.appendingPathComponent(folder)
            vaults[slot] = .init(
                id: old.id, name: old.name, role: old.role, canonicalPath: url.path,
                bookmarkData: try url.bookmarkData(options: [.withSecurityScope]), registeredAt: old.registeredAt)
        }
        var triptych = previous.triptych
        triptych.portableControlAccess = .init(
            canonicalContainerPath: workingFixture.path,
            bookmarkData: try workingFixture.bookmarkData(options: [.withSecurityScope]))
        let assignment = TriptychAssignment(triptych: triptych, vaults: vaults, hasCommonParent: previous.hasCommonParent)
        let suffix = "Triptychs/\(assignment.id.uuidString.lowercased())/indexes/search-v10.sqlite"
        let databaseURL = support.appendingPathComponent(suffix)
        let (capturedGeneration, beforeAudit) = try {
            let before = try Database(databaseURL)
            let rows = try before.rows("SELECT vault_id, relative_path, fingerprint_sha256, fingerprint_byte_count, source_utf16_count FROM search_documents;")
            try require(rows.count == oracle.count, "Captured index does not cover all source Notes")
            var seen = Set<String>()
            for row in rows {
                guard let vaultID = UUID(uuidString: row[0]), let byteCount = Int(row[3]), let utf16Count = Int(row[4]) else {
                    throw Failure(description: "Invalid source binding in captured index")
                }
                let path = try path(.init(vaultID: vaultID, relativePath: row[1]), assignment: assignment)
                try require(
                    seen.insert(path).inserted && oracle[path] == DocumentFingerprint(sha256: row[2], byteCount: byteCount),
                    "Captured index source binding differs from the exact fixture bytes")
                try require(try source(path, root: workingFixture).utf16.count == utf16Count, "Captured source coordinate capacity changed")
            }
            return (try generation(before), try before.audit())
        }()
        try require(capturedGeneration.triptychID == assignment.id, "Captured index identity differs from the registration")
        let manifest = SearchSourceManifest.hash(
            try oracle.keys.map { path in
                let id = try noteID(path, assignment: assignment)
                return .init(vaultID: id.vaultID, relativePath: id.relativePath, fingerprint: oracle[path]!)
            })
        try require(capturedGeneration.sourceManifestHash == manifest, "Actual Release index does not identify these source bytes")
        let identity = try databaseURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier.map { String(describing: $0) }
        try require(identity != nil, "Cannot bind the captured database file identity")
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        try write(originalRecords, to: output.appendingPathComponent("sources.json"))
        try write(beforeAudit, to: output.appendingPathComponent("captured-index-audit.json"))
        var responseMaterial: [[String: Any]] = []
        for (label, applicationSupport, registryStorage) in [
            ("captured", support, registry),
            ("rebuilt", work.appendingPathComponent("rebuilt/ApplicationSupport"), work.appendingPathComponent("rebuilt/Registry")),
        ] {
            let runtime = WorkspaceRuntime(
                configuration: .snapshot(
                    .init(
                        applicationSupportURL: applicationSupport,
                        workspaceRegistryStorageURL: registryStorage, assignments: [assignment])))
            do {
                let handle = try await runtime.openWorkspace(id: assignment.id)
                let snapshot = try await handle.snapshot()
                let actualGeneration = try validateSnapshot(snapshot, assignment: assignment, oracle: oracle)
                if label == "captured" { try require(actualGeneration == capturedGeneration, "Opening replaced the captured generation") }
                let material = try await responses(
                    handle, root: workingFixture, oracle: oracle,
                    partialOutput: output.appendingPathComponent("\(label)-responses.incomplete.json"))
                try write(material, to: output.appendingPathComponent("\(label)-responses.json"))
                responseMaterial.append(material)
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
            try require(try sources(workingFixture) == oracle, "Oracle mutated its copied source bytes")
            if label == "captured" {
                let afterAudit = try Database(databaseURL).audit()
                try write(afterAudit, to: output.appendingPathComponent("captured-index-after-audit.json"))
                try require(encode(beforeAudit) == encode(afterAudit), "Opening/querying changed the original index's logical payload")
                let afterIdentity = try databaseURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier.map { String(describing: $0) }
                try require(identity == afterIdentity, "Opening recovered/replaced the actual Release database")
            }
        }
        try require(
            try encode(responseMaterial[0]) == encode(responseMaterial[1]), "Captured index and clean rebuild differ; inspect both complete response files")
        try require(
            try sources(fixture) == oracle && Data(contentsOf: capture.appendingPathComponent("capture.json")) == captureBytes,
            "The retained source capture changed")
        try require(encode(fixtureSignature(fixture)) == encode(signature), "The retained fixture files changed")
        let identities: [[String: Any]] = try WorkspaceVaultSlot.allCases.map { slot in
            guard let vault = assignment.vault(for: slot) else { throw Failure(description: "Missing role identity") }
            return ["slot": slot.rawValue, "vault_id": vault.id.uuidString.lowercased()]
        }
        #if DEBUG
            let configuration = "debug_backend_reading_actual_release_capture"
        #else
            let configuration = "release_backend_reading_actual_release_capture"
        #endif
        try write(
            [
                "schema": "scholium-index-release-parity-v1", "status": "passed", "configuration": configuration,
                "producer": provenance, "triptych_id": assignment.id.uuidString.lowercased(), "vault_identities": identities,
                "fixture_signature": signature, "backend_build": backendBuild,
                "source_count": oracle.count, "source_sha256": digest(try encode(originalRecords)),
                "captured_generation": try object(capturedGeneration), "ordered_response_sha256": digest(try encode(responseMaterial[0])),
                "proof":
                    "Actual Release index logical payload and file identity survive public snapshot-runtime opening/querying; complete ordered Search pages and Related responses equal a clean rebuild. Search result/paragraph/Property and Related passage ranges have independent UTF-16/line/column checks; Related source slices match exact UTF-8. Graph/link occurrence structures are compared in full but their coordinates are not independently rederived. Not native query latency or a release gate.",
            ], to: output.appendingPathComponent("report.json"))
        print("INDEX_RELEASE_PARITY passed notes=\(oracle.count) ordered_response_sha256=\(digest(try encode(responseMaterial[0]))) output=\(output.path)")
    }
}
