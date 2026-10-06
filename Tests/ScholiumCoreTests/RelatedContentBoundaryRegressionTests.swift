import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related Material canonical boundaries and readable-text duplicates")
struct RelatedContentBoundaryRegressionTests {
    @Test(
        "Focus runs retain the exact matcher boundaries",
        arguments: [
            "free_will", "自由agency", "agency自由", "自由agency自主", "λόγος_λόγος", "CAFÉ_agency", "foo\u{200D}bar",
        ])
    func focusBoundaries(focus: String) {
        let expected = focus == "foo\u{200D}bar" ? ["fo", "bar"] : [SearchTextNormalization.normalize(focus)]
        #expect(RelatedContentQueryTerms.orderedTokens(in: focus) == expected)
        let matcher = RelatedContentTermMatcher(terms: expected)
        let normalized = SearchTextNormalization.lexicalNormalize(focus)
        #expect(matcher.matchingTerms(in: normalized, index: .init(normalized)) == Set(expected))
    }

    @Test(
        "Exact attached runs are recalled without admitting their separated parts",
        arguments: [
            ("free_will", "free will"), ("自由agency", "自由 agency"), ("agency自由", "agency 自由"),
            ("λόγος_λόγος", "λόγος λόγος"), ("CAFÉ_agency", "café agency"),
        ])
    func attachedRunRecall(input: (String, String)) async throws {
        let (focus, separated) = input
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.item("Exact.md", "\u{FEFF}# Source 😀\r\n\r\nThis passage considers **\(focus)** and responsibility.\r\n"),
            fixture.item("Separated.md", "This passage considers \(separated) and responsibility."),
            fixture.item("Metadata.md", "---\naliases: [\(focus)]\nkeywords: [\(focus)]\n---\n\nAn unrelated passage."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let passages = try await fixture.evaluate(index, focus: focus, documents: documents)
        #expect(passages.map { $0.candidate.note.relativePath } == ["Exact.md"])
        #expect(passages.first?.matches.first?.terms == [SearchTextNormalization.normalize(focus)])
        try fixture.checkSources(passages, documents: documents)
        #expect(try await fixture.evaluate(try fixture.index(), focus: focus, documents: documents) == passages)
    }

    @Test("Pure CJK bigrams, spaced concepts and quoted negation keep their authored behavior")
    func independentConceptControls() async throws {
        #expect(RelatedContentQueryTerms.orderedTokens(in: "自由意志") == ["自由", "由意", "意志"])
        #expect(RelatedContentQueryTerms.orderedTokens(in: "自由 agency") == ["自由", "agency"])
        #expect(RelatedContentQueryTerms.orderedTokens(in: "free will") == ["free", "will"])
        #expect(RelatedContentQueryTerms.orderedTokens(in: "a\u{20DD}b") == ["a\u{20DD}b"])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "“not free_will” and 「自由agency」") == ["not free_will", "自由agency"])
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.item("Chinese.md", "这里讨论自由意志的条件。"),
            fixture.item("Spaced.md", "自由 agency supplies a deliberately spaced concept."),
            fixture.item("Attached.md", "自由agency supplies a deliberately attached concept."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        #expect(try await fixture.evaluate(index, focus: "自由意志", documents: documents).map { $0.candidate.note.relativePath } == ["Chinese.md"])
        #expect(try await fixture.evaluate(index, focus: "自由 agency", documents: documents).map { $0.candidate.note.relativePath } == ["Spaced.md"])
    }

    @Test("Complete title and alias witnesses require the same attached wording locally", arguments: [false, true])
    func focusedIdentity(alias: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let path = alias ? "Glossary.md" : "free_will.md"
        let properties = alias ? "---\naliases: [free_will]\n---\n\n" : ""
        let documents = [
            fixture.item(path, properties + "free_will names an authored concept."),
            fixture.item("Other.md", "Spectral calibration measurement appears in an independent paragraph."),
            fixture.item("Partial.md", "---\naliases: [free_will]\n---\n\nFree and will are separate words here."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let passages = try await fixture.evaluate(index, focus: "Compare free_will with spectral calibration measurement.", documents: documents)
        #expect(Set(passages.map { $0.candidate.note.relativePath }) == [path, "Other.md"])
        try fixture.checkSources(passages, documents: documents)
    }

    @Test(
        "Case and accent differences survive within a Note and across Notes",
        arguments: [
            ("agency reason.", "Agency reason."), ("cafe reason.", "café reason."),
        ])
    func readableTextDistinctions(input: (String, String)) async throws {
        let (first, second) = input
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.item("Within.md", "\u{FEFF}\(first)\r\n\r\n\(second)\r\n\r\n\(first)\r\n"),
            fixture.item("Cross.md", second, vault: fixture.analyses),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let focus = input.0.hasPrefix("agency") ? "agency reason" : "cafe reason"
        let within = try await fixture.evaluate(index, focus: focus, documents: [documents[0]])
        #expect(within.map(\.displayText) == [first, second])
        let across = try await fixture.evaluate(index, focus: focus, documents: documents)
        #expect(Set(across.map(\.displayText)) == Set([first, second]))
        #expect(across.count == 2)
        try fixture.checkSources(within + across, documents: documents)
    }

    @Test("Attached-run recall and exact deduplication agree after edit, move, delete, reopen and rebuild")
    func mutationRebuildParity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let initial = [
            fixture.item("Topic.md", "自由agency reason.\r\n\r\n自由Agency reason.\r\n"),
            fixture.item("Analysis.md", "自由agency reason.", vault: fixture.analyses),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(initial)
        let initialPassages = try await fixture.evaluate(index, focus: "自由agency reason", documents: initial)
        #expect(Set(initialPassages.map(\.displayText)) == ["自由agency reason.", "自由Agency reason."])
        let edited = [
            fixture.item("Topic.md", "自由agency revised.\r\n\r\n自由Agency revised.\r\n"), initial[1],
        ]
        let moved = [
            fixture.item("Folder/Topic.md", edited[0].document.rawContent), initial[1],
        ]
        let deleted = [moved[0]]
        for (step, documents) in [edited, moved, deleted].enumerated() {
            _ = try await index.synchronize(documents)
            let incremental = try await fixture.evaluate(index, focus: "自由agency", documents: documents)
            #expect(Set(incremental.map(\.displayText)).isSuperset(of: ["自由agency revised.", "自由Agency revised."]))
            #expect(!incremental.contains { $0.candidate.note.relativePath == "Topic.md" && step > 0 })
            #expect(!incremental.contains { $0.candidate.note.relativePath == "Analysis.md" && step == 2 })
            let rebuilt = try fixture.index(databaseURL: fixture.root.appendingPathComponent("rebuilt-\(step).sqlite"))
            _ = try await rebuilt.synchronize(documents)
            #expect(try await fixture.evaluate(rebuilt, focus: "自由agency", documents: documents) == incremental)
            #expect(try await fixture.evaluate(try fixture.index(), focus: "自由agency", documents: documents) == incremental)
            try fixture.checkSources(incremental, documents: documents)
        }
    }

    @Test(
        "Whole-Note seeds recall attached terms through the same canonical boundaries",
        arguments: [
            ("free_will", "free will"), ("自由agency", "自由 agency"), ("agency自由", "agency 自由"),
            ("λόγος_λόγος", "λόγος λόγος"),
        ])
    func sourceNoteRecall(input: (String, String)) async throws {
        let (term, separated) = input
        let fixture = try Fixture()
        defer { fixture.remove() }
        let documents = [
            fixture.item("Exact.md", "This passage considers \(term) and responsibility."),
            fixture.item("Separated.md", "This passage considers \(separated) and responsibility."),
        ]
        let index = try fixture.index()
        _ = try await index.synchronize(documents)
        let passages = try await fixture.evaluate(index, focus: term, documents: documents, focused: false)
        #expect(passages.map { $0.candidate.note.relativePath } == ["Exact.md"])
        #expect(passages.first?.matches.map(\.seedKind) == [.sourceNote])
        #expect(passages.first?.matches.first?.terms == [SearchTextNormalization.normalize(term)])
        try fixture.checkSources(passages, documents: documents)
        #expect(try await fixture.evaluate(try fixture.index(), focus: term, documents: documents, focused: false) == passages)
    }

    @Test("Every source field shares canonical runs while retaining source-only negation policy")
    func sourceFieldBoundaries() {
        let document = NoteDocument(
            relativePath: "free_will.md",
            rawContent: """
                ---
                summary: 自由agency
                keywords: [agency自由]
                ---

                # λόγος_λόγος

                CAFÉ_agency is not an incidental reason.
                """)
        let projection = SearchDocumentProjection(document: document)
        let material = RelatedContentSeedMaterial(projection: projection, focuses: [])
        let terms = material.termGroups.first { $0.kind == .sourceNote }?.terms ?? []
        #expect(
            Set(["free_will", "自由agency", "agency自由", SearchTextNormalization.normalize("λόγος_λόγος"), "café_agency"])
                .isSubset(of: Set(terms)))
        #expect(!terms.contains("not"))
        let focused = RelatedContentSeedMaterial(projection: projection, focuses: [.init(kind: .selectedPassage, text: "not free_will")])
        #expect(focused.termGroups.first { $0.kind == .selectedPassage }?.terms == ["not", "free_will"])
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()
        let topics = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/fixtures/topics")
        let analyses = RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/fixtures/analyses")

        init() throws {
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/related-boundary-tests/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func item(_ path: String, _ text: String, vault: RegisteredVault? = nil) -> SearchIndexDocument {
            let vault = vault ?? topics
            return .init(vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role, document: .init(relativePath: path, rawContent: text))
        }

        func index(databaseURL: URL? = nil) throws -> TriptychSearchIndex {
            try .init(databaseURL: databaseURL ?? root.appendingPathComponent("index.sqlite"), triptychID: triptychID, vaults: [topics, analyses])
        }

        func evaluate(_ index: TriptychSearchIndex, focus: String, documents: [SearchIndexDocument], focused: Bool = true) async throws
            -> [RelatedContentPassage]
        {
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: topics.id, relativePath: "Current.md"), source: focus,
                    focuses: focused ? [.init(kind: .selectedPassage, text: focus)] : []))
            let response = try await index.relatedMaterialSourceCandidates(request)
            var seen = Set<VaultQualifiedNoteID>()
            let candidates = (response.identityCandidates + response.lexicalCandidates).filter { seen.insert($0.note).inserted }
            let permitted = Set(documents.map { VaultQualifiedNoteID(vaultID: $0.vaultID, relativePath: $0.relativePath) })
            let sources = try candidates.filter { permitted.contains($0.note) }.map { candidate in
                let document = try #require(documents.first { $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath })
                return RelatedContentSource(candidate: candidate, document: document.document)
            }
            let direct = try TriptychSearchIndex.relatedPassages(request, sources: sources)
            #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == direct)
            #expect(try await index.relatedPassages(request, sources: sources) == direct)
            return direct
        }

        func checkSources(_ passages: [RelatedContentPassage], documents: [SearchIndexDocument]) throws {
            for passage in passages {
                let document = try #require(
                    documents.first { $0.vaultID == passage.candidate.note.vaultID && $0.relativePath == passage.candidate.note.relativePath })
                let range = try #require(
                    Range(
                        NSRange(
                            location: passage.range.utf16LowerBound,
                            length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: document.document.rawContent))
                #expect(String(document.document.rawContent[range]) == passage.source)
                #expect(passage.candidate.fingerprint == document.document.fingerprint)
            }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
