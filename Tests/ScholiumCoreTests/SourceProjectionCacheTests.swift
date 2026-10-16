import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Source-bound persistent Catalog and Search projections")
struct SourceProjectionCacheTests {
    @Test("Explicit cache clearing removes checked records while preserving research state and permanent live locks")
    func explicitCacheClear() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Source\n\n[[Target]]\n")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        let expectedBytes = Int64(try Data(contentsOf: fixture.record(document)).count + Data(contentsOf: fixture.catalogRecord(document)).count)
        let protected = fixture.directory.deletingLastPathComponent().appendingPathComponent("retained-recovery.json")
        let protectedBytes = Data("exact recovery sentinel".utf8)
        try protectedBytes.write(to: protected)
        let live = try DerivedStateStorage.vaultCacheLease(applicationSupportURL: fixture.root, vaultID: fixture.vaultID)
        let result = try fixture.cache.clearRecognizedRecords()
        #expect(result.removedFiles == 2 && result.removedBytes == expectedBytes)
        #expect(result.preservedFiles == 0 && result.failedFiles == 0 && result.busyDirectories == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.record(document).path))
        #expect(!FileManager.default.fileExists(atPath: fixture.catalogRecord(document).path))
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(".projection-records.lock").path))
        try live.validateCurrent()
        #expect(try Data(contentsOf: protected) == protectedBytes)
        withExtendedLifetime(live) {}
    }

    @Test("Explicit cache clearing retains future policies, unknown names, links and oversized records")
    func explicitCacheClearPreservesUnowned() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Future.md", rawContent: "# Future\n")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        var frame = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.record(document)), format: nil) as? [String: Any])
        var policy = try #require(frame["policy"] as? [String: Any])
        policy["projectionVersion"] = SourceProjectionCache.Policy.current.projectionVersion + 1
        frame["policy"] = policy
        let futureBytes = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try futureBytes.write(to: fixture.record(document))
        let unknown = fixture.directory.appendingPathComponent("notes.catalog.plist")
        let sentinel = Data("unknown owned by a newer app".utf8)
        try sentinel.write(to: unknown)
        let linked = fixture.directory.appendingPathComponent(SourceProjectionCache.fileName("Linked.md"))
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: unknown)
        let hardLink = fixture.directory.appendingPathComponent(SourceProjectionCache.fileName("Hardlink.md"))
        try FileManager.default.linkItem(at: unknown, to: hardLink)
        let oversized = fixture.directory.appendingPathComponent(SourceProjectionCache.fileName("Oversized.md"))
        #expect(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let output = try FileHandle(forWritingTo: oversized)
        try output.truncate(atOffset: UInt64(SourceProjectionCache.maximumRecordByteCount + 1))
        try output.close()

        let result = try fixture.cache.clearRecognizedRecords()
        #expect(result.removedFiles == 0 && result.removedBytes == 0)
        #expect(result.preservedFiles == 5 && result.failedFiles == 3)
        #expect(try Data(contentsOf: fixture.record(document)) == futureBytes)
        #expect(try Data(contentsOf: unknown) == sentinel)
        #expect(try Data(contentsOf: hardLink) == sentinel)
        #expect(try linked.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(try oversized.resourceValues(forKeys: [.fileSizeKey]).fileSize == SourceProjectionCache.maximumRecordByteCount + 1)
    }

    @Test("Explicit cache clearing does not create a missing cache and cancelled clearing leaves records intact")
    func explicitCacheClearAbsenceAndCancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(try fixture.cache.clearRecognizedRecords() == ScholiumStorageClearResult())
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Current\n")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try Data(contentsOf: fixture.record(document))
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try fixture.cache.clearRecognizedRecords()
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(try Data(contentsOf: fixture.record(document)) == original)
    }

    @Test("Explicit cache clearing reports exclusive maintenance ownership without touching its records")
    func explicitCacheClearDuringMaintenance() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Current\n")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try Data(contentsOf: fixture.record(document))
        let storage = SecureRecordDirectory(
            trustedRootURL: fixture.root,
            components: ["Vaults", fixture.vaultID.uuidString, "source-projections-v1"],
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 0)
        let maintenance = try DerivedStateStorageLease(storage: storage, exclusive: true)
        defer { withExtendedLifetime(maintenance) {} }
        let result = try fixture.cache.clearRecognizedRecords()
        #expect(result == ScholiumStorageClearResult(busyDirectories: 1))
        #expect(try Data(contentsOf: fixture.record(document)) == original)
    }

    @Test("Trusted Application Support aliases reopen both projections without following internal cache symlinks")
    func trustedRootAlias() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alias = fixture.root.appendingPathComponent("Application Support Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.root)
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Émotion 😀\r\n\r\n[[Target]]\r\n")
        let search = SearchDocumentProjection(document: document)
        let catalog = fixture.catalogProjection(document)
        let writer = SourceProjectionCache(applicationSupportURL: alias, vaultID: fixture.vaultID, role: .topicKnowledge)
        writer.store(search, for: document)
        writer.storeCatalog(catalog, for: document)
        #expect(fixture.cache.load(for: document) == search)
        #expect(fixture.cache.loadCatalog(for: document) == catalog)
        let reopened = SourceProjectionCache(applicationSupportURL: alias, vaultID: fixture.vaultID, role: .topicKnowledge)
        #expect(reopened.load(for: document) == search)
        #expect(reopened.loadCatalog(for: document) == catalog)

        let outside = fixture.root.appendingPathComponent("Outside Derived State", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.directory, to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: outside)
        let outsideSearch = outside.appendingPathComponent(fixture.record(document).lastPathComponent)
        let outsideCatalog = outside.appendingPathComponent(fixture.catalogRecord(document).lastPathComponent)
        let searchBytes = try Data(contentsOf: outsideSearch)
        let catalogBytes = try Data(contentsOf: outsideCatalog)
        let substituted = SourceProjectionCache(applicationSupportURL: alias, vaultID: fixture.vaultID, role: .topicKnowledge)
        #expect(substituted.load(for: document) == nil)
        #expect(substituted.loadCatalog(for: document) == nil)
        let changed = NoteDocument(relativePath: document.relativePath, rawContent: "# Changed source\n\n[[Other]]\n")
        substituted.store(SearchDocumentProjection(document: changed), for: changed)
        substituted.storeCatalog(fixture.catalogProjection(changed), for: changed)
        #expect(try Data(contentsOf: outsideSearch) == searchBytes)
        #expect(try Data(contentsOf: outsideCatalog) == catalogBytes)
    }

    @Test("Compact Catalog records reopen losslessly without a Search record or complete semantic tree")
    func catalogLosslessReopen() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sources = [
            "", "Ordinary prose.\n\nSecond paragraph.",
            "\u{FEFF}---\r\naliases: [别名, Alias]\r\nkeywords: [Freedom]\r\nsummary: Résumé\r\n---\r\n# Émotion 😀\r\n\r\n情感 [[Target#Heading|别名]]{{*freedom*}}.\r\n",
            "# Heading\n\n## Heading\n\nParagraph ^anchor\n\nDuplicate ^anchor\n\n[escaped](Other%20Note.md#Section) and ![[Image.png]].\n",
            "---\nsummary: unclosed\nBody 🧑🏽‍🔬\n",
        ]
        for (ordinal, source) in sources.enumerated() {
            let document = NoteDocument(relativePath: "Folder/中文 é \(ordinal).md", rawContent: source)
            let projection = WorkspaceSourceProjection(
                vaultID: fixture.vaultID, document: document, semantic: MarkdownSemanticDocument(parsing: document))
            #expect(projection.isValid(for: document, vaultID: fixture.vaultID))
            fixture.cache.storeCatalog(projection, for: document)
            let reopened = SourceProjectionCache(applicationSupportURL: fixture.root, vaultID: fixture.vaultID, role: .topicKnowledge)
            #expect(reopened.loadCatalog(for: document) == projection)
            #expect(!FileManager.default.fileExists(atPath: fixture.record(document).path))
            let payload = try PropertyListDecoder().decode(SourceProjectionCache.CatalogFrame.self, from: Data(contentsOf: fixture.catalogRecord(document)))
            let keys = try #require(
                PropertyListSerialization.propertyList(from: SearchProjectionBlobCodec.decode(payload.payload), format: nil) as? [String: Any])
            #expect(keys["blocks"] == nil && keys["inlines"] == nil && keys["sourceBytes"] == nil)
        }
    }

    @Test("Catalog cache remains bound to fresh fingerprint, exact path, vault and role")
    func catalogSourceBinding() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "é.md", rawContent: "# Émotion 😀\n\n[[Target]]\n")
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        #expect(fixture.cache.loadCatalog(for: document) != nil)
        #expect(fixture.cache.loadCatalog(for: .init(relativePath: "é.md", rawContent: "# Émotion 😀\n\n[[Edited]]\n")) == nil)
        #expect(fixture.cache.loadCatalog(for: .init(relativePath: "e\u{301}.md", rawContent: document.rawContent)) == nil)
        #expect(SourceProjectionCache(applicationSupportURL: fixture.root, vaultID: fixture.vaultID, role: .sourceCorpus).loadCatalog(for: document) == nil)
        #expect(SourceProjectionCache(applicationSupportURL: fixture.root, vaultID: UUID(), role: .topicKnowledge).loadCatalog(for: document) == nil)
        #expect(fixture.cache.loadCatalog(for: document) != nil)
    }

    @Test("Catalog and Search policy invalidation are independent and reclaim only the rejected record")
    func independentCatalogPolicy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Title\n\n[[Target]]\n")
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        var search = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.record(document)), format: nil) as? [String: Any])
        var searchPolicy = try #require(search["policy"] as? [String: Any])
        searchPolicy["searchVersion"] = -1
        search["policy"] = searchPolicy
        try PropertyListSerialization.data(fromPropertyList: search, format: .binary, options: 0).write(to: fixture.record(document))
        #expect(fixture.cache.load(for: document) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.record(document).path))
        #expect(fixture.cache.loadCatalog(for: document) != nil)
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        var catalog = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: fixture.catalogRecord(document)), format: nil) as? [String: Any])
        var catalogPolicy = try #require(catalog["policy"] as? [String: Any])
        #expect(Set(catalogPolicy.keys) == ["formatVersion", "projectionVersion", "markdownParserVersion", "yamlParserVersion"])
        catalogPolicy["projectionVersion"] = -1
        catalog["policy"] = catalogPolicy
        try PropertyListSerialization.data(fromPropertyList: catalog, format: .binary, options: 0).write(to: fixture.catalogRecord(document))
        #expect(fixture.cache.loadCatalog(for: document) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.catalogRecord(document).path))
        #expect(fixture.cache.load(for: document) != nil)
    }

    @Test("Current filenames expose retirement policy without inflating their payload", arguments: [false, true])
    func currentFilenamePolicyRetirement(catalog: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Title\n\n[[Target]]\n")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        let record = catalog ? fixture.catalogRecord(document) : fixture.record(document)
        let original = try Data(contentsOf: record)
        #expect(SourceProjectionCache.recordPolicy(original, fileName: record.lastPathComponent) == .current)
        var frame = try #require(PropertyListSerialization.propertyList(from: original, format: nil) as? [String: Any])
        var policy = try #require(frame["policy"] as? [String: Any])
        // Deliberately impossible to inflate. Retirement must read policy only,
        // including when a compatible Search DB never demands this cache row.
        frame["payload"] = Data("not a compressed projection".utf8)
        let currentHeader = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        #expect(SourceProjectionCache.recordPolicy(currentHeader, fileName: record.lastPathComponent) == .current)
        policy["projectionVersion"] = 0
        frame["policy"] = policy
        let retired = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try retired.write(to: record)
        #expect(SourceProjectionCache.recordPolicy(retired, fileName: record.lastPathComponent) == .retired)
        #expect(try Data(contentsOf: record) == retired)
        policy["projectionVersion"] = Int.max
        frame["policy"] = policy
        let future = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
        try future.write(to: record)
        #expect(SourceProjectionCache.recordPolicy(future, fileName: record.lastPathComponent) == .unknown)
        fixture.cache.invalidate(path: document.relativePath)
        fixture.cache.prune(currentPaths: [])
        #expect(try Data(contentsOf: record) == future)
        #expect(SourceProjectionCache.recordPolicy(Data(original.prefix(8)), fileName: record.lastPathComponent) == .corrupt)
        #expect(SourceProjectionCache.recordPolicy(original, fileName: "notes.catalog.plist") == .unknown)
    }

    @Test("Unknown and future policies remain byte-unchanged through load, store, invalidate and prune", arguments: [false, true])
    func futurePoliciesRemainNonAuthorizing(catalog: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Title\n\n[[Target]]\n")
        for kind in 0..<5 {
            fixture.cache.store(SearchDocumentProjection(document: document), for: document)
            fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
            let record = catalog ? fixture.catalogRecord(document) : fixture.record(document)
            var frame = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: record), format: nil) as? [String: Any])
            var policy = try #require(frame["policy"] as? [String: Any])
            switch kind {
            case 0: policy["formatVersion"] = Int.max
            case 1: policy["markdownParserVersion"] = "next-unrecognized-parser"
            case 2: policy["yamlParserVersion"] = "99.0.0"
            case 3: policy["futurePolicy"] = 1
            default: frame["futureFrameExtension"] = "opaque future material"
            }
            frame["policy"] = policy
            let future = try PropertyListSerialization.data(fromPropertyList: frame, format: .binary, options: 0)
            try future.write(to: record)
            #expect(SourceProjectionCache.recordPolicy(future, fileName: record.lastPathComponent) == .unknown)
            #expect(!SourceProjectionCache.isReclaimableRecord(future, fileName: record.lastPathComponent))
            #expect(!SourceProjectionCache.isReclaimableTemporaryRecord(future))
            if catalog { #expect(fixture.cache.loadCatalog(for: document) == nil) } else { #expect(fixture.cache.load(for: document) == nil) }
            fixture.cache.store(SearchDocumentProjection(document: document), for: document)
            fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
            #expect(try Data(contentsOf: record) == future)
            fixture.cache.invalidate(path: document.relativePath)
            #expect(try Data(contentsOf: record) == future)
            fixture.cache.prune(currentPaths: [])
            #expect(try Data(contentsOf: record) == future)
            try FileManager.default.removeItem(at: record)
        }
    }

    enum CatalogDamage: CaseIterable, Sendable {
        case negativeUTF8, overflowingUTF16, mismatchedUTF8, surrogateBoundary, mismatchedLine, overflowingColumn
        case headingLevel, wrongVault, wrongPath, changedTitle, changedProperty, dynamicResolution
    }

    @Test("Forged Catalog payload with a recomputed digest cannot supply unsafe syntax or coordinates", arguments: CatalogDamage.allCases)
    func malformedCatalog(_ damage: CatalogDamage) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(
            relativePath: "Note.md",
            rawContent: "---\r\naliases: [Alias]\r\nsummary: Summary\r\n---\r\n# Émotion 😀\r\n\r\n[[Target#Heading|Alias]]{{*context*}}.\r\n")
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        let frame = try PropertyListDecoder().decode(SourceProjectionCache.CatalogFrame.self, from: Data(contentsOf: fixture.catalogRecord(document)))
        var payload = try #require(PropertyListSerialization.propertyList(from: SearchProjectionBlobCodec.decode(frame.payload), format: nil) as? [String: Any])
        var linkCatalog = try #require(payload["linkCatalog"] as? [String: Any])
        var headings = try #require(linkCatalog["headings"] as? [[String: Any]])
        var span = try #require(headings[0]["span"] as? [String: Any])
        switch damage {
        case .negativeUTF8: span["utf8LowerBound"] = -1
        case .overflowingUTF16: span["utf16UpperBound"] = Int.max
        case .mismatchedUTF8: span["utf8UpperBound"] = try #require(span["utf8UpperBound"] as? Int) - 1
        case .surrogateBoundary: span["utf16UpperBound"] = (document.rawContent as NSString).range(of: "😀").location + 1
        case .mismatchedLine:
            var start = try #require(span["start"] as? [String: Any])
            start["line"] = 1
            span["start"] = start
        case .overflowingColumn:
            var end = try #require(span["end"] as? [String: Any])
            end["utf8Column"] = Int.max
            span["end"] = end
        case .headingLevel: headings[0]["level"] = 7
        case .wrongVault, .wrongPath:
            var id = try #require(linkCatalog["id"] as? [String: Any])
            if damage == .wrongVault { id["vaultID"] = UUID().uuidString } else { id["relativePath"] = "Different.md" }
            linkCatalog["id"] = id
        case .changedTitle: payload["title"] = "Different title"
        case .changedProperty: payload["propertyTextValues"] = ["summary": ["Invented"]]
        case .dynamicResolution:
            var links = try #require(payload["authoredLinks"] as? [[String: Any]])
            var occurrence = try #require(MarkdownSemanticDocument(parsing: document).links.first)
            occurrence.resolution = .resolved(.init(vaultID: UUID(), relativePath: "Other.md"))
            links[0] = try #require(PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(occurrence), format: nil) as? [String: Any])
            payload["authoredLinks"] = links
        }
        headings[0]["span"] = span
        linkCatalog["headings"] = headings
        payload["linkCatalog"] = linkCatalog
        let compressed = try SearchProjectionBlobCodec.encode(PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0))
        let malformed = SourceProjectionCache.CatalogFrame(
            policy: frame.policy, vaultID: frame.vaultID, role: frame.role, profile: frame.profile,
            relativePathUTF8: frame.relativePathUTF8, fingerprint: frame.fingerprint,
            payloadDigest: SourceProjectionCache.digest(compressed), payload: compressed)
        try PropertyListEncoder().encode(malformed).write(to: fixture.catalogRecord(document))
        #expect(fixture.cache.loadCatalog(for: document) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.catalogRecord(document).path))
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        #expect(fixture.cache.loadCatalog(for: document) == fixture.catalogProjection(document))
    }

    @Test("Catalog damage and bounded inflate failures are nonauthorizing cache misses")
    func damagedCatalogRecords() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "# Title\n\n[[Target]]\n")
        for damage in 0..<4 {
            fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
            let record = fixture.catalogRecord(document)
            let original = try Data(contentsOf: record)
            switch damage {
            case 0: try original.prefix(8).write(to: record)
            case 1: try Data(repeating: 0, count: SourceProjectionCache.maximumRecordByteCount + 1).write(to: record)
            default:
                let frame = try PropertyListDecoder().decode(SourceProjectionCache.CatalogFrame.self, from: original)
                var payload = frame.payload
                if damage == 3 {
                    var length = UInt64(SourceProjectionCache.maximumRecordByteCount + 1).littleEndian
                    withUnsafeBytes(of: &length) { payload.replaceSubrange(5..<13, with: $0) }
                }
                let damaged = SourceProjectionCache.CatalogFrame(
                    policy: frame.policy, vaultID: frame.vaultID, role: frame.role, profile: frame.profile,
                    relativePathUTF8: frame.relativePathUTF8, fingerprint: frame.fingerprint,
                    payloadDigest: damage == 2 ? "bad" : SourceProjectionCache.digest(payload), payload: payload)
                try PropertyListEncoder().encode(damaged).write(to: record)
            }
            #expect(fixture.cache.loadCatalog(for: document) == nil)
            if damage == 1 {
                // Policy cannot be identified through the bounded reader.
                let oversized = try Data(contentsOf: record)
                fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
                fixture.cache.invalidate(path: document.relativePath)
                fixture.cache.prune(currentPaths: [])
                #expect(try Data(contentsOf: record) == oversized)
                try FileManager.default.removeItem(at: record)
            } else {
                #expect(!FileManager.default.fileExists(atPath: record.path))
            }
        }
    }

    @Test("Cold-process cache preserves complete multilingual projections and exact coordinates")
    func losslessReopen() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sources = [
            "", "ordinary prose\n\nSecond paragraph.",
            "\u{FEFF}---\r\naliases: [别名, Alias]\r\nsummary: Résumé\r\nauthor: CUI\r\n---\r\n# Émotion 😀\r\n\r\n情感 *freedom* [target](Other.md).\r\n",
            "# Heading\n\n> [!argument] Claim\n> Callout body\n\nText[^1].\n\n[^1]: Footnote body\n",
            "[[Target]]{{annotation freedom}}\n\nParagraph ^anchor\n\n![image](pic.png) and `code`.\n",
            "---\nsummary: unclosed\nBody 🧑🏽‍🔬\n",
        ]
        for (ordinal, source) in sources.enumerated() {
            let document = NoteDocument(relativePath: "Folder/中文 é \(ordinal).md", rawContent: source)
            let projection = SearchDocumentProjection(document: document)
            fixture.cache.store(projection, for: document)
            let reopened = SourceProjectionCache(
                applicationSupportURL: fixture.root, vaultID: fixture.vaultID, role: .topicKnowledge)
            let loaded = try #require(reopened.load(for: document))
            #expect(loaded == projection)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            #expect(try encoder.encode(loaded) == encoder.encode(projection))
        }
    }

    @Test("Fresh source fingerprint, exact path spelling and role bind every cache hit")
    func sourceAndProfileBinding() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "é.md", rawContent: "alpha")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        #expect(fixture.cache.load(for: document) != nil)
        #expect(fixture.cache.load(for: NoteDocument(relativePath: "é.md", rawContent: "bravo")) == nil)
        #expect(fixture.cache.load(for: NoteDocument(relativePath: "e\u{301}.md", rawContent: "alpha")) == nil)
        #expect(SourceProjectionCache(applicationSupportURL: fixture.root, vaultID: fixture.vaultID, role: .sourceCorpus).load(for: document) == nil)
        #expect(SourceProjectionCache(applicationSupportURL: fixture.root, vaultID: UUID(), role: .topicKnowledge).load(for: document) == nil)
    }

    @Test("Missing, truncated, oversized and checksum-damaged records are misses")
    func damagedRecords() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try Data(contentsOf: fixture.record(document))
        try original.prefix(8).write(to: fixture.record(document))
        #expect(fixture.cache.load(for: document) == nil)
        var frame = try PropertyListDecoder().decode(SourceProjectionCache.Frame.self, from: original)
        frame = .init(
            policy: frame.policy, vaultID: frame.vaultID, role: frame.role, profile: frame.profile,
            relativePathUTF8: frame.relativePathUTF8, fingerprint: frame.fingerprint,
            payloadDigest: "bad", payload: frame.payload)
        try fixture.write(frame, for: document)
        #expect(fixture.cache.load(for: document) == nil)
        let oversized = Data(repeating: 0, count: SourceProjectionCache.maximumRecordByteCount + 1)
        try oversized.write(to: fixture.record(document))
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        #expect(try Data(contentsOf: fixture.record(document)) == oversized)
        try FileManager.default.removeItem(at: fixture.record(document))
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        #expect(fixture.cache.load(for: document) != nil)
    }

    @Test("Version mismatch and malformed offset maps reject even a matching payload digest")
    func versionAndOffsetValidation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try PropertyListDecoder().decode(SourceProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        let policy = SourceProjectionCache.Policy(
            formatVersion: 0, projectionVersion: 2, markdownParserVersion: "0.8.0", yamlParserVersion: "6.2.2",
            searchVersion: SearchContract.currentVersion, schemaVersion: SearchContract.schemaVersion,
            tokenizerVersion: SearchContract.tokenizerPolicyVersion, rankingVersion: SearchContract.rankingPolicyVersion)
        try fixture.write(
            .init(
                policy: policy, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        let outdatedYAML = SourceProjectionCache.Policy(
            formatVersion: 2, projectionVersion: 2, markdownParserVersion: "0.8.0", yamlParserVersion: "6.0.0",
            searchVersion: SearchContract.currentVersion, schemaVersion: SearchContract.schemaVersion,
            tokenizerVersion: SearchContract.tokenizerPolicyVersion, rankingVersion: SearchContract.rankingPolicyVersion)
        try fixture.write(
            .init(
                policy: outdatedYAML, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        var payload = try #require(
            PropertyListSerialization.propertyList(from: SearchProjectionBlobCodec.decode(original.payload), format: nil) as? [String: Any])
        var segments = try #require(payload["segments"] as? [[String: Any]])
        #expect(!segments.isEmpty)
        segments[0]["offsetMap"] = Data([0x53, 0x4f, 0x4d, 0x32, 0, 0, 0, 0, 1])
        payload["segments"] = segments
        let encodedMaterial = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        let malformed = try SearchProjectionBlobCodec.encode(encodedMaterial)
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: SourceProjectionCache.digest(malformed), payload: malformed), for: document)
        #expect(fixture.cache.load(for: document) == nil)
    }

    @Test("Corrupt line coordinates cannot overflow and profile mismatches stay nonauthorizing")
    func malformedCoordinatesAndProfile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try PropertyListDecoder().decode(SourceProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role,
                profile: .analysis, relativePathUTF8: original.relativePathUTF8,
                fingerprint: original.fingerprint, payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        var payload = try #require(
            PropertyListSerialization.propertyList(from: SearchProjectionBlobCodec.decode(original.payload), format: nil) as? [String: Any])
        var segments = try #require(payload["segments"] as? [[String: Any]])
        let index = try #require(segments.firstIndex { $0["sourceRange"] is [String: Any] })
        var range = try #require(segments[index]["sourceRange"] as? [String: Any])
        range["column"] = Int.max
        segments[index]["sourceRange"] = range
        payload["segments"] = segments
        let encodedMaterial = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        let malformed = try SearchProjectionBlobCodec.encode(encodedMaterial)
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role,
                profile: original.profile, relativePathUTF8: original.relativePathUTF8,
                fingerprint: original.fingerprint, payloadDigest: SourceProjectionCache.digest(malformed), payload: malformed), for: document)
        #expect(fixture.cache.load(for: document) == nil)
    }

    @Test("Duplicate or skipped document ordinals reject even a recomputed digest and projection hash")
    func malformedDocumentOrdinals() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        let projection = SearchDocumentProjection(document: document)
        fixture.cache.store(projection, for: document)
        let original = try PropertyListDecoder().decode(SourceProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        #expect(projection.segments.count > 1)
        for ordinal in [0, 9] {
            var payload = try #require(
                PropertyListSerialization.propertyList(from: SearchProjectionBlobCodec.decode(original.payload), format: nil) as? [String: Any])
            var segments = try #require(payload["segments"] as? [[String: Any]])
            segments[1]["ordinal"] = ordinal
            payload["segments"] = segments
            let material =
                projection.segments.enumerated().map { index, segment in
                    "\(segment.field.rawValue)\u{1F}\(index == 1 ? ordinal : segment.ordinal)\u{1F}\(segment.normalizedText)"
                        + segment.relatedRankingText.keys.sorted().map { key in
                            "\u{1F}\(key)\u{1F}\(segment.relatedRankingText[key] ?? "")"
                        }.joined()
                }.joined(separator: "\u{1E}") + "\u{1D}false"
            payload["projectionHash"] = SourceProjectionCache.digest(Data(material.utf8))
            let encodedMaterial = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            let malformed = try SearchProjectionBlobCodec.encode(encodedMaterial)
            try fixture.write(
                .init(
                    policy: original.policy, vaultID: original.vaultID, role: original.role,
                    profile: original.profile, relativePathUTF8: original.relativePathUTF8,
                    fingerprint: original.fingerprint, payloadDigest: SourceProjectionCache.digest(malformed), payload: malformed), for: document)
            #expect(fixture.cache.load(for: document) == nil)
        }
    }

    @Test("Symlink substitution cannot read or overwrite outside cache storage")
    func symlinkContainment() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body.")
        let projection = SearchDocumentProjection(document: document)
        fixture.cache.store(projection, for: document)
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        let outside = fixture.root.appendingPathComponent("outside")
        let sentinel = Data("private sentinel".utf8)
        try sentinel.write(to: outside)
        try FileManager.default.removeItem(at: fixture.record(document))
        try FileManager.default.createSymbolicLink(at: fixture.record(document), withDestinationURL: outside)
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(projection, for: document)
        #expect(try Data(contentsOf: outside) == sentinel)
        try FileManager.default.removeItem(at: fixture.catalogRecord(document))
        try FileManager.default.createSymbolicLink(at: fixture.catalogRecord(document), withDestinationURL: outside)
        #expect(fixture.cache.loadCatalog(for: document) == nil)
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        #expect(try Data(contentsOf: outside) == sentinel)
        // A directory substitution also fails the descriptor walk.
        try FileManager.default.removeItem(at: fixture.directory)
        try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: fixture.root)
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(projection, for: document)
        #expect(fixture.cache.loadCatalog(for: document) == nil)
        fixture.cache.storeCatalog(fixture.catalogProjection(document), for: document)
        #expect(try Data(contentsOf: outside) == sentinel)
    }

    @Test("Dynamic graph state never persists and pruning retains only current source paths")
    func invalidationAndPrune() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = NoteDocument(relativePath: "First.md", rawContent: "Body.")
        let second = NoteDocument(relativePath: "Second.md", rawContent: "Other.")
        fixture.cache.store(SearchDocumentProjection(document: first, hasBrokenLink: true), for: first)
        #expect(fixture.cache.load(for: first) == nil)
        fixture.cache.store(SearchDocumentProjection(document: first), for: first)
        fixture.cache.store(SearchDocumentProjection(document: second), for: second)
        fixture.cache.storeCatalog(fixture.catalogProjection(first), for: first)
        fixture.cache.storeCatalog(fixture.catalogProjection(second), for: second)
        let retired = fixture.directory.appendingPathComponent(SourceProjectionCache.digest(Data("Retired.md".utf8)) + ".projection.json")
        try Data("obsolete derived record".utf8).write(to: retired)
        let unrelated = fixture.directory.appendingPathComponent("unrelated.txt")
        let sentinel = Data("unrelated bytes".utf8)
        try sentinel.write(to: unrelated)
        let unknownRecord = fixture.directory.appendingPathComponent("notes.catalog.plist")
        let unknownSearch = fixture.directory.appendingPathComponent("notes.projection.plist")
        try Data(contentsOf: fixture.catalogRecord(first)).write(to: unknownRecord)
        try Data(contentsOf: fixture.record(first)).write(to: unknownSearch)
        let unknownCatalogBytes = try Data(contentsOf: unknownRecord)
        let unknownSearchBytes = try Data(contentsOf: unknownSearch)
        #expect(!SourceProjectionCache.isReclaimableRecord(unknownCatalogBytes, fileName: unknownRecord.lastPathComponent))
        #expect(!SourceProjectionCache.isReclaimableRecord(unknownSearchBytes, fileName: unknownSearch.lastPathComponent))
        fixture.cache.prune(currentPaths: [first.relativePath])
        #expect(fixture.cache.load(for: first) != nil)
        #expect(fixture.cache.load(for: second) == nil)
        #expect(fixture.cache.loadCatalog(for: first) != nil)
        #expect(fixture.cache.loadCatalog(for: second) == nil)
        #expect(!FileManager.default.fileExists(atPath: retired.path))
        #expect(try Data(contentsOf: unrelated) == sentinel)
        #expect(try Data(contentsOf: unknownRecord) == unknownCatalogBytes)
        #expect(try Data(contentsOf: unknownSearch) == unknownSearchBytes)
        fixture.cache.invalidate(path: first.relativePath)
        #expect(fixture.cache.load(for: first) == nil)
        #expect(fixture.cache.loadCatalog(for: first) == nil)
    }

    private struct Fixture {
        let root: URL
        let vaultID = UUID()
        var cache: SourceProjectionCache {
            SourceProjectionCache(applicationSupportURL: root, vaultID: vaultID, role: .topicKnowledge)
        }
        var directory: URL {
            root.appendingPathComponent("Vaults/\(vaultID.uuidString)/source-projections-v1", isDirectory: true)
        }
        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/source-projection-cache-tests/\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        func record(_ document: NoteDocument) -> URL {
            directory.appendingPathComponent(SourceProjectionCache.fileName(document.relativePath))
        }
        func catalogRecord(_ document: NoteDocument) -> URL {
            directory.appendingPathComponent(SourceProjectionCache.catalogFileName(document.relativePath))
        }
        func catalogProjection(_ document: NoteDocument) -> WorkspaceSourceProjection {
            WorkspaceSourceProjection(vaultID: vaultID, document: document, semantic: MarkdownSemanticDocument(parsing: document))
        }
        func write(_ frame: SourceProjectionCache.Frame, for document: NoteDocument) throws {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(frame).write(to: record(document))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
