import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Source-bound persistent Search projections")
struct SourceSearchProjectionCacheTests {
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
            let reopened = SourceSearchProjectionCache(
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
        #expect(SourceSearchProjectionCache(applicationSupportURL: fixture.root, vaultID: fixture.vaultID, role: .sourceCorpus).load(for: document) == nil)
        #expect(SourceSearchProjectionCache(applicationSupportURL: fixture.root, vaultID: UUID(), role: .topicKnowledge).load(for: document) == nil)
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
        var frame = try JSONDecoder().decode(SourceSearchProjectionCache.Frame.self, from: original)
        frame = .init(
            policy: frame.policy, vaultID: frame.vaultID, role: frame.role, profile: frame.profile,
            relativePathUTF8: frame.relativePathUTF8, fingerprint: frame.fingerprint,
            payloadDigest: "bad", payload: frame.payload)
        try fixture.write(frame, for: document)
        #expect(fixture.cache.load(for: document) == nil)
        try Data(repeating: 0, count: SourceSearchProjectionCache.maximumRecordByteCount + 1).write(to: fixture.record(document))
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        #expect(fixture.cache.load(for: document) != nil)
    }

    @Test("Version mismatch and malformed offset maps reject even a matching payload digest")
    func versionAndOffsetValidation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try JSONDecoder().decode(SourceSearchProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        let policy = SourceSearchProjectionCache.Policy(
            formatVersion: 0, projectionVersion: 1, markdownParserVersion: "0.8.0", yamlParserVersion: "6.2.2",
            searchVersion: SearchContract.currentVersion, schemaVersion: SearchContract.schemaVersion,
            tokenizerVersion: SearchContract.tokenizerPolicyVersion, rankingVersion: SearchContract.rankingPolicyVersion)
        try fixture.write(
            .init(
                policy: policy, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        let outdatedYAML = SourceSearchProjectionCache.Policy(
            formatVersion: 1, projectionVersion: 1, markdownParserVersion: "0.8.0", yamlParserVersion: "6.0.0",
            searchVersion: SearchContract.currentVersion, schemaVersion: SearchContract.schemaVersion,
            tokenizerVersion: SearchContract.tokenizerPolicyVersion, rankingVersion: SearchContract.rankingPolicyVersion)
        try fixture.write(
            .init(
                policy: outdatedYAML, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        var payload = try #require(PropertyListSerialization.propertyList(from: original.payload, format: nil) as? [String: Any])
        var segments = try #require(payload["segments"] as? [[String: Any]])
        #expect(!segments.isEmpty)
        segments[0]["offsetMap"] = Data([0x53, 0x4f, 0x4d, 0x31, 0, 0, 0, 0, 1])
        payload["segments"] = segments
        let malformed = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role, profile: original.profile,
                relativePathUTF8: original.relativePathUTF8, fingerprint: original.fingerprint,
                payloadDigest: SourceSearchProjectionCache.digest(malformed), payload: malformed), for: document)
        #expect(fixture.cache.load(for: document) == nil)
    }

    @Test("Corrupt line coordinates cannot overflow and profile mismatches stay nonauthorizing")
    func malformedCoordinatesAndProfile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        fixture.cache.store(SearchDocumentProjection(document: document), for: document)
        let original = try JSONDecoder().decode(SourceSearchProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role,
                profile: .analysis, relativePathUTF8: original.relativePathUTF8,
                fingerprint: original.fingerprint, payloadDigest: original.payloadDigest, payload: original.payload), for: document)
        #expect(fixture.cache.load(for: document) == nil)
        var payload = try #require(PropertyListSerialization.propertyList(from: original.payload, format: nil) as? [String: Any])
        var segments = try #require(payload["segments"] as? [[String: Any]])
        let index = try #require(segments.firstIndex { $0["sourceRange"] is [String: Any] })
        var range = try #require(segments[index]["sourceRange"] as? [String: Any])
        range["column"] = Int.max
        segments[index]["sourceRange"] = range
        payload["segments"] = segments
        let malformed = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        try fixture.write(
            .init(
                policy: original.policy, vaultID: original.vaultID, role: original.role,
                profile: original.profile, relativePathUTF8: original.relativePathUTF8,
                fingerprint: original.fingerprint, payloadDigest: SourceSearchProjectionCache.digest(malformed), payload: malformed), for: document)
        #expect(fixture.cache.load(for: document) == nil)
    }

    @Test("Duplicate or skipped document ordinals reject even a recomputed digest and projection hash")
    func malformedDocumentOrdinals() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let document = NoteDocument(relativePath: "Note.md", rawContent: "Body freedom.")
        let projection = SearchDocumentProjection(document: document)
        fixture.cache.store(projection, for: document)
        let original = try JSONDecoder().decode(SourceSearchProjectionCache.Frame.self, from: Data(contentsOf: fixture.record(document)))
        #expect(projection.segments.count > 1)
        for ordinal in [0, 9] {
            var payload = try #require(PropertyListSerialization.propertyList(from: original.payload, format: nil) as? [String: Any])
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
            payload["projectionHash"] = SourceSearchProjectionCache.digest(Data(material.utf8))
            let malformed = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
            try fixture.write(
                .init(
                    policy: original.policy, vaultID: original.vaultID, role: original.role,
                    profile: original.profile, relativePathUTF8: original.relativePathUTF8,
                    fingerprint: original.fingerprint, payloadDigest: SourceSearchProjectionCache.digest(malformed), payload: malformed), for: document)
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
        let outside = fixture.root.appendingPathComponent("outside")
        let sentinel = Data("private sentinel".utf8)
        try sentinel.write(to: outside)
        try FileManager.default.removeItem(at: fixture.record(document))
        try FileManager.default.createSymbolicLink(at: fixture.record(document), withDestinationURL: outside)
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(projection, for: document)
        #expect(try Data(contentsOf: outside) == sentinel)
        // A directory substitution also fails the descriptor walk.
        try FileManager.default.removeItem(at: fixture.directory)
        try FileManager.default.createSymbolicLink(at: fixture.directory, withDestinationURL: fixture.root)
        #expect(fixture.cache.load(for: document) == nil)
        fixture.cache.store(projection, for: document)
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
        fixture.cache.prune(currentPaths: [first.relativePath])
        #expect(fixture.cache.load(for: first) != nil)
        #expect(fixture.cache.load(for: second) == nil)
        fixture.cache.invalidate(path: first.relativePath)
        #expect(fixture.cache.load(for: first) == nil)
    }

    private struct Fixture {
        let root: URL
        let vaultID = UUID()
        var cache: SourceSearchProjectionCache {
            SourceSearchProjectionCache(applicationSupportURL: root, vaultID: vaultID, role: .topicKnowledge)
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
            directory.appendingPathComponent(SourceSearchProjectionCache.fileName(document.relativePath))
        }
        func write(_ frame: SourceSearchProjectionCache.Frame, for document: NoteDocument) throws {
            let encoder = JSONEncoder()
            try encoder.encode(frame).write(to: record(document))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
