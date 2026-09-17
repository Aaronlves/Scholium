import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related-content source projection memo")
struct RelatedContentSourceProjectionMemoTests {
    private let vault = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func source(
        _ path: String = "Fixture.md", _ text: String,
        vaultID: UUID? = nil, role: VaultRole = .sourceCorpus,
        candidatePath: String? = nil, fingerprint: DocumentFingerprint? = nil
    ) -> RelatedContentSource {
        let document = NoteDocument(relativePath: path, rawContent: text)
        return .init(
            candidate: .init(
                note: .init(vaultID: vaultID ?? vault, relativePath: candidatePath ?? path),
                vaultRole: role, title: path,
                fingerprint: fingerprint ?? document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
            document: document)
    }

    /// Reference prepares passages without caching, independent of memo
    /// lookup/storage. Additional tests below assert authored text and ranges.
    private func uncachedReference(_ document: NoteDocument) -> (
        note: [String: String], paragraphs: [(range: SearchSourceRange, display: String, fields: [String: String])]
    ) {
        let semantic = MarkdownSemanticDocument(parsing: document)
        let full = SearchDocumentProjection(document: document, semantic: semantic)
        let paragraphs = semantic.blocks.filter { $0.kind == .paragraph }.compactMap {
            block -> (
                range: SearchSourceRange, display: String, fields: [String: String]
            )? in
            guard block.span.utf16Range.count <= RelatedContentContract.maximumPassageUTF16Count,
                let range = Range(block.span.nsRange, in: document.rawContent)
            else { return nil }
            let exact = String(document.rawContent[range])
            let snippet = NoteDocument(relativePath: document.relativePath, rawContent: exact)
            let segments = SearchDocumentProjection(document: snippet).segments.filter {
                $0.sourceRange != nil && $0.field != .title && $0.field != .alias
            }
            return (
                .init(
                    utf16LowerBound: block.span.utf16LowerBound,
                    utf16UpperBound: block.span.utf16UpperBound,
                    line: block.span.start.line, column: block.span.start.utf16Column,
                    endLine: block.span.end.line, endColumn: block.span.end.utf16Column),
                ResearchExcerptPresentation.readableText(exact, includingAnnotations: true),
                RelatedContentBM25F.Document(segments: segments).fields
            )
        }
        return (RelatedContentBM25F.Document(segments: full.segments).fields, paragraphs)
    }

    @Test("Cached preparation preserves uncached fields, display and exact CRLF coordinates")
    func fidelity() throws {
        let fixtures = [
            "\u{FEFF}---\r\nsummary: needle freedom\r\nkeywords: [needle, freedom]\r\nunknown: preserved\r\n---\r\n\r\nUnrelated prose.\r\n",
            "Émotion 😀 [[目标|行动]]{{自由}} ordinary.\r\n\r\nSecond paragraph.\r\n",
            "![alternate needle](https://example.test/image.png \"Caption freedom\")\r\n",
            "- list needle.\r\n\r\n> quote freedom.\r\n",
        ]
        var memo = RelatedContentSourceProjectionMemo()
        for (index, text) in fixtures.enumerated() {
            let input = source("Fixture\(index).md", text)
            let reference = uncachedReference(input.document)
            let coldProjection = try memo.projection(for: input)
            let cold = try #require(coldProjection)
            let warmProjection = try memo.projection(for: input)
            let warm = try #require(warmProjection)
            #expect(cold.noteScoringDocument.fields == reference.note)
            #expect(warm.noteScoringDocument.fields == reference.note)
            #expect(warm.paragraphs.count == reference.paragraphs.count)
            for (actual, expected) in zip(warm.paragraphs, reference.paragraphs) {
                #expect(actual.range == expected.range)
                #expect(actual.displayText == expected.display)
                #expect(actual.scoringDocument.fields == expected.fields)
                #expect(actual.normalizedDisplayText == SearchTextNormalization.lexicalNormalize(expected.display))
                let range = try #require(
                    Range(
                        NSRange(
                            location: actual.range.utf16LowerBound,
                            length: actual.range.utf16UpperBound - actual.range.utf16LowerBound),
                        in: input.document.rawContent))
                #expect(!String(input.document.rawContent[range]).hasSuffix("\r\n"))
            }
        }
        #expect(memo.statistics.hits == fixtures.count)
        #expect(memo.statistics.misses == fixtures.count)
    }

    @Test("Annotation wording and image title remain distinct from raw source and alt text")
    func visibleText() throws {
        let first = "Émotion 😀 [[目标|行动]]{{自由}} ordinary."
        let input = source("Fixture.md", first + "\r\n\r\nSecond paragraph.\r\n")
        var memo = RelatedContentSourceProjectionMemo()
        let preparedProjection = try memo.projection(for: input)
        let prepared = try #require(preparedProjection)
        let paragraph = try #require(prepared.paragraphs.first)
        #expect(paragraph.displayText == "Émotion 😀 行动 (自由) ordinary.")
        #expect(paragraph.range.utf16LowerBound == 0)
        #expect(paragraph.range.utf16UpperBound == first.utf16.count)
        #expect(paragraph.range.line == 1)
        #expect(paragraph.range.column == 1)
        #expect(paragraph.scoringDocument.fields["annotation"]?.contains("自由") == true)
        #expect(paragraph.scoringDocument.fields["link"]?.contains("行动") == true)
        #expect(paragraph.scoringDocument.fields["body"]?.contains("自由") != true)
        #expect(paragraph.scoringDocument.fields.values.allSatisfy { !$0.contains("目标") })
        let imageProjection = try memo.projection(
            for: source(
                "Image.md", "![alternate needle](https://example.test/image.png \"Caption freedom\")\r\n"))
        let image = try #require(imageProjection)
        #expect(image.paragraphs.map(\.displayText) == ["Caption freedom"])
    }

    @Test("Nested paragraphs survive and YAML-only terms do not become excerpt content")
    func nestedAndMetadata() throws {
        var memo = RelatedContentSourceProjectionMemo()
        let nestedProjection = try memo.projection(for: source("Nested.md", "- list needle.\r\n\r\n> quote freedom.\r\n"))
        let nested = try #require(nestedProjection)
        #expect(nested.paragraphs.map(\.displayText) == ["list needle.", "quote freedom."])
        #expect(nested.paragraphs.map { $0.range.line } == [1, 3])
        #expect(nested.paragraphs.allSatisfy { $0.range.column > 1 })
        let metadataProjection = try memo.projection(
            for: source(
                "Metadata.md", "---\r\nsummary: needle freedom\r\n---\r\n\r\nUnrelated prose.\r\n"))
        let metadata = try #require(metadataProjection)
        #expect(metadata.noteScoringDocument.fields["summary"]?.contains("needle freedom") == true)
        #expect(metadata.paragraphs.map(\.displayText) == ["Unrelated prose."])
        #expect(
            metadata.paragraphs.allSatisfy {
                !$0.scoringDocument.fields.values.contains(where: { $0.contains("needle") || $0.contains("freedom") })
            })
    }

    @Test("Fingerprint, role, vault and exact UTF-8 path isolate memo reuse")
    func isolation() throws {
        var memo = RelatedContentSourceProjectionMemo()
        let original = source("Fixture.md", "needle")
        let originalProjection = try memo.projection(for: original)
        _ = try #require(originalProjection)
        let reusedProjection = try memo.projection(for: original)
        _ = try #require(reusedProjection)
        #expect(memo.statistics.hits == 1)
        let otherVault = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let otherVaultProjection = try memo.projection(for: source("Fixture.md", "needle", vaultID: otherVault))
        _ = try #require(otherVaultProjection)
        let otherRoleProjection = try memo.projection(for: source("Fixture.md", "needle", role: .topicKnowledge))
        _ = try #require(otherRoleProjection)
        #expect(memo.statistics.misses == 3)
        #expect(memo.entryCount == 2)
        let wrongFingerprintProjection = try memo.projection(for: source("Fixture.md", "changed", fingerprint: original.document.fingerprint))
        #expect(wrongFingerprintProjection == nil)
        let wrongPathProjection = try memo.projection(for: source("Actual.md", "needle", candidatePath: "Other.md"))
        #expect(wrongPathProjection == nil)
        let composed = "Café.md"
        let decomposed = "Cafe\u{301}.md"
        #expect(composed == decomposed)
        #expect(Data(composed.utf8) != Data(decomposed.utf8))
        let wrongUnicodePathProjection = try memo.projection(for: source(decomposed, "needle", candidatePath: composed))
        #expect(wrongUnicodePathProjection == nil)
        let composedProjection = try memo.projection(for: source(composed, "needle"))
        _ = try #require(composedProjection)
        let hitsBefore = memo.statistics.hits
        let decomposedProjection = try memo.projection(for: source(decomposed, "needle"))
        _ = try #require(decomposedProjection)
        #expect(memo.statistics.hits == hitsBefore)
        #expect(memo.entryCount == 3)
    }

    @Test("Source replacement retains only latest revision and cannot reuse old annotation text")
    func replacement() throws {
        var memo = RelatedContentSourceProjectionMemo()
        let old = source("Fixture.md", "[[Target]]{{old needle}}")
        let new = source("Fixture.md", "[[Target]]{{new freedom}}")
        let oldProjection = try memo.projection(for: old)
        _ = try #require(oldProjection)
        let changedProjection = try memo.projection(for: new)
        let changed = try #require(changedProjection)
        #expect(changed.paragraphs.map(\.displayText) == ["Target (new freedom)"])
        #expect(changed.paragraphs.allSatisfy { !$0.displayText.contains("old") })
        #expect(memo.entryCount == 1)
        let reusedNewProjection = try memo.projection(for: new)
        _ = try #require(reusedNewProjection)
        #expect(memo.statistics.hits == 1)
        let revisitedOldProjection = try memo.projection(for: old)
        _ = try #require(revisitedOldProjection)
        #expect(memo.statistics.misses == 3)
        #expect(memo.entryCount == 1)
    }

    @Test("Index replacement prunes deleted notes and changed revisions while retaining unchanged notes")
    func retention() throws {
        var memo = RelatedContentSourceProjectionMemo()
        let old = source("Changed.md", "old needle.")
        let deleted = source("Deleted.md", "deleted needle.")
        let unchanged = source("Unchanged.md", "unchanged freedom.")
        for input in [old, deleted, unchanged] {
            let prepared = try memo.projection(for: input)
            _ = try #require(prepared)
        }
        let changed = source("Changed.md", "new freedom.")
        let documents = [changed, unchanged].map {
            SearchIndexDocument(
                vaultID: $0.candidate.note.vaultID,
                vaultName: "Fixture",
                vaultRole: $0.candidate.vaultRole,
                document: $0.document)
        }
        memo.retain(documents)
        #expect(memo.entryCount == 1)
        #expect(memo.estimatedByteCount > 0)

        let retained = try memo.projection(for: unchanged)
        _ = try #require(retained)
        #expect(memo.statistics.hits == 1)
        let oldPrepared = try memo.projection(for: old)
        _ = try #require(oldPrepared)
        #expect(memo.statistics.misses == 4)
        let deletedPrepared = try memo.projection(for: deleted)
        _ = try #require(deletedPrepared)
        #expect(memo.statistics.misses == 5)

        memo.retain(documents)
        #expect(memo.entryCount == 1)
        let changedPrepared = try memo.projection(for: changed)
        let replacement = try #require(changedPrepared)
        #expect(replacement.paragraphs.map(\.displayText) == ["new freedom."])
        #expect(memo.statistics.misses == 6)
        #expect(memo.entryCount == 2)

        memo.retain([])
        #expect(memo.entryCount == 0)
        #expect(memo.estimatedByteCount == 0)
    }

    @Test("Byte budget evicts least recently used entry; oversized preparation remains usable without retention")
    func budget() throws {
        let a = source("A.md", "needle freedom.")
        let b = source("B.md", "needle freedom.")
        let c = source("C.md", "needle freedom.")
        var probe = RelatedContentSourceProjectionMemo()
        let probeProjection = try probe.projection(for: a)
        _ = try #require(probeProjection)
        let oneEntryCost = probe.estimatedByteCount
        var memo = RelatedContentSourceProjectionMemo(maximumByteCount: oneEntryCost * 2)
        let initialAProjection = try memo.projection(for: a)
        _ = try #require(initialAProjection)
        let initialBProjection = try memo.projection(for: b)
        _ = try #require(initialBProjection)
        let touchedAProjection = try memo.projection(for: a)
        _ = try #require(touchedAProjection)
        let initialCProjection = try memo.projection(for: c)
        _ = try #require(initialCProjection)
        #expect(memo.entryCount == 2)
        #expect(memo.estimatedByteCount <= memo.maximumByteCount)
        let retainedAProjection = try memo.projection(for: a)
        _ = try #require(retainedAProjection)
        #expect(memo.statistics.hits == 2)
        let missesBefore = memo.statistics.misses
        let evictedBProjection = try memo.projection(for: b)
        _ = try #require(evictedBProjection)
        #expect(memo.statistics.misses == missesBefore + 1)
        #expect(memo.entryCount == 2)
        #expect(memo.estimatedByteCount <= memo.maximumByteCount)
        var oversize = RelatedContentSourceProjectionMemo(maximumByteCount: 0)
        let oversizedProjection = try oversize.projection(for: a)
        let usable = try #require(oversizedProjection)
        #expect(usable.paragraphs.map(\.displayText) == ["needle freedom."])
        let repeatedOversizedProjection = try oversize.projection(for: a)
        _ = try #require(repeatedOversizedProjection)
        #expect(oversize.statistics.hits == 0)
        #expect(oversize.statistics.misses == 2)
        #expect(oversize.entryCount == 0)
        #expect(oversize.estimatedByteCount == 0)
    }

    @Test("Repeated over-budget scans reuse resident requested Notes without omitting uncached projections")
    func protectedFullScans() throws {
        let a = source("A.md", "needle freedom.")
        let b = source("B.md", "needle freedom.")
        let c = source("C.md", "needle freedom.")
        var probe = RelatedContentSourceProjectionMemo()
        _ = try probe.projection(for: a)
        var memo = RelatedContentSourceProjectionMemo(maximumByteCount: probe.estimatedByteCount * 2)
        // The first full scan ends with B and C resident. Ordinary LRU would
        // subsequently evict B for A, then C for B, producing zero scan hits.
        for input in [a, b, c] { _ = try memo.projection(for: input) }
        for _ in 0..<2 {
            let before = memo.statistics
            let protection = memo.scanProtection(for: [a, b, c])
            var preparations: [String] = []
            for input in [a, b, c] {
                let result = try memo.projection(for: input, protection: protection) { document in
                    preparations.append(document.relativePath)
                    return try .init(document: document)
                }
                let projection = try #require(result)
                #expect(projection.paragraphs.map(\.displayText) == ["needle freedom."])
                #expect(projection.noteScoringDocument.fields == uncachedReference(input.document).note)
            }
            #expect(preparations == ["A.md"])
            #expect(memo.statistics.hits == before.hits + 2)
            #expect(memo.statistics.misses == before.misses + 1)
            #expect(memo.statistics.protectedAdmissionSkips == before.protectedAdmissionSkips + 1)
            #expect(memo.statistics.evictions == before.evictions)
            #expect(memo.entryCount == 2)
            #expect(memo.estimatedByteCount <= memo.maximumByteCount)
        }

        // A later request no longer needs B. Its fresh snapshot protects C,
        // permitting A to replace B without carrying protection across requests.
        let before = memo.statistics
        let protection = memo.scanProtection(for: [a, c])
        _ = try memo.projection(for: a, protection: protection)
        _ = try memo.projection(for: c, protection: protection)
        _ = try memo.projection(for: a, protection: protection)
        #expect(memo.statistics.misses == before.misses + 1)
        #expect(memo.statistics.hits == before.hits + 2)
        #expect(memo.statistics.evictions == before.evictions + 1)
        #expect(memo.statistics.protectedAdmissionSkips == before.protectedAdmissionSkips)
        #expect(memo.entryCount == 2)
        #expect(memo.estimatedByteCount <= memo.maximumByteCount)
    }

    @Test("Scan protection excludes stale revisions and changed roles so their replacements can be retained")
    func protectionRequiresCurrentIdentity() throws {
        let old = source("B.md", "needle freedom.")
        let oldRole = source("C.md", "needle freedom.")
        let changed = source("B.md", "newest liberty.")
        let changedRole = source("C.md", "needle freedom.", role: .topicKnowledge)
        var probe = RelatedContentSourceProjectionMemo()
        _ = try probe.projection(for: old)
        var memo = RelatedContentSourceProjectionMemo(maximumByteCount: probe.estimatedByteCount * 2)
        for input in [old, oldRole] { _ = try memo.projection(for: input) }
        let before = memo.statistics
        let protection = memo.scanProtection(for: [changed, changedRole])
        let replaced = try memo.projection(for: changed, protection: protection)
        let replacement = try #require(replaced)
        #expect(replacement.paragraphs.map(\.displayText) == ["newest liberty."])
        _ = try memo.projection(for: changedRole, protection: protection)
        #expect(memo.statistics.hits == before.hits)
        #expect(memo.statistics.misses == before.misses + 2)
        #expect(memo.statistics.protectedAdmissionSkips == before.protectedAdmissionSkips)
        #expect(memo.entryCount == 2)
        #expect(memo.estimatedByteCount <= memo.maximumByteCount)

        let refreshed = memo.scanProtection(for: [changed, changedRole])
        for input in [changed, changedRole] { _ = try memo.projection(for: input, protection: refreshed) }
        #expect(memo.statistics.hits == before.hits + 2)
        #expect(memo.statistics.misses == before.misses + 2)
    }
}
