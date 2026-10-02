import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content focus admission")
struct RelatedContentFocusAdmissionTests {
    @Test("One authored translation admits a paragraph without its other language")
    func oneLiteralAlternative() async throws {
        let notes = ["Source.md": "我们在这里讨论自由的限度。"]
        #expect(try await evaluate(focus: "freedom", notes: notes).paths.isEmpty)
        let result = try await evaluate(focus: "freedom", alternatives: ["freedom", "自由"], notes: notes)
        #expect(result.paths == ["Source.md"])
        #expect(result.passages.first?.matches.filter { $0.seedKind == .researchRequest }.flatMap(\.terms) == ["自由"])
    }

    @Test("Authored phrases retain exact bilingual alternative provenance and reject partial or metadata-only matches")
    func literalPhraseProvenance() async throws {
        let result = try await evaluate(
            focus: "unrelated selection", alternatives: ["Free Will", "自由意志"],
            notes: [
                "Latin.md": "FREE WILL is considered in this invented source passage.",
                "Chinese.md": "这里讨论自主的自由意志与责任。",
                "Partial.md": "这里只有自由。另一处出现由意，随后出现意志。",
                "Separated.md": "Free — will are separated by punctuation in this fixture.",
                "Metadata.md": "---\nkeywords: [Free Will]\n---\n\nA paragraph about unrelated catering expenses.",
            ])
        #expect(result.paths == ["Latin.md", "Chinese.md"])
        for (path, term) in [("Latin.md", "Free Will"), ("Chinese.md", "自由意志")] {
            let passage = try #require(result.passages.first { $0.candidate.note.relativePath == path })
            #expect(passage.matches.filter { $0.seedKind == .researchRequest }.flatMap(\.terms) == [term])
        }
    }

    @Test("Literal alternative boundaries do not manufacture a Note identity while ordinary research requests retain prose matching")
    func literalIdentityBoundaries() {
        let projection = SearchDocumentProjection(document: .init(relativePath: "Draft.md", rawContent: "unrelated"))
        let ordinary = RelatedContentSeedMaterial(projection: projection, focuses: [.init(kind: .researchRequest, text: "free will")])
        #expect(ordinary.termGroups.first?.terms == ["free", "will"])
        #expect(ordinary.identityMentionReason(title: "Free Will", aliases: [])?.mentions.first?.seedKind == .researchRequest)
        let alternatives = RelatedContentSeedMaterial(
            projection: projection, focuses: [.init(kind: .researchRequest, text: "free will", literalAlternatives: ["free", "will"])])
        #expect(alternatives.identityMentionReason(title: "Free Will", aliases: []) == nil)
    }

    @Test("A locally repeated named concept survives a longer writing request", arguments: [0, 500])
    func namedConcept(distractors: Int) async throws {
        var notes = [
            "Defeasibility.md": "Defeasibility concerns reasons that can lose their justificatory force when further information appears.",
            "Evidence.md": "Evidence should be collected before comparing possible explanations.",
            "Event.md": "This question requires a careful discussion of the relation between event evidence and catering expenses.",
        ]
        for index in 0..<distractors {
            notes["Background-\(index).md"] = "A question about room \(index) prompted a discussion of catering expenses."
        }
        let result = try await evaluate(
            focus: "This question requires a careful discussion of the relation between evidence and defeasibility.",
            notes: notes)
        #expect(result.paths.contains("Defeasibility.md"))
        #expect(result.paths.contains("Evidence.md"))
        #expect(result.stages["Defeasibility.md"]?.contains(.eligible) == true)
    }

    @Test("A complete explicit alias is locally corroborated through canonical normalization")
    func aliasAdmission() async throws {
        let result = try await evaluate(
            focus: "Please compare the discussion of façade with the available architectural evidence.",
            notes: [
                "Glossary.md": "---\naliases: [façade]\n---\n\nFAC\u{0327}ADE is the authored term in this small fixture.",
                "Office.md": "Please compare the discussion of the available architectural evidence at the office meeting.",
            ])
        #expect(result.stages["Glossary.md"]?.contains(.localMatch) == true)
        #expect(result.stages["Glossary.md"]?.contains(.eligible) == true)
        #expect(result.paths.contains("Glossary.md"))
    }

    @Test("Focused-name admission is independent of the three-identity candidate channel limit")
    func identityChannelLimit() async throws {
        let notes = [
            "Aster.md": "Aster names the first sample.",
            "Beryl.md": "Beryl names the second sample.",
            "Citrine.md": "Citrine names the third sample.",
            "Dolomite.md": "Dolomite names the fourth sample.",
            "Z Glossary.md": "---\naliases: [emerald]\n---\n\nEmerald names the fifth sample.",
        ]
        let result = try await evaluate(
            focus: "Please compare Aster, Beryl, Citrine, Dolomite and emerald while considering where specimens occur.", notes: notes)
        #expect(result.paths == Set(notes.keys))
        #expect(result.stages["Dolomite.md"]?.contains(.eligible) == true)
        #expect(result.stages["Z Glossary.md"]?.contains(.eligible) == true)
    }

    @Test("Identity context cannot admit metadata-only or incomplete identity matches")
    func identityNeedsLocalCorroboration() async throws {
        let result = try await evaluate(
            focus: "Please examine crystalline memory together with glacial sediment evidence.",
            notes: [
                "Crystalline Memory.md": "Memory of an office meeting is recorded here.",
                "Glacial Sediment.md": "---\nkeywords: [glacial, sediment]\n---\n\nAnnual catering expenses are recorded here.",
                "Material.md": "Glacial sediment and crystalline memory are the two exact phrases in this invented fixture.",
            ])
        #expect(result.paths == ["Material.md"])
        #expect(result.stages["Crystalline Memory.md"]?.contains(.insufficientFocus) == true)
        #expect(result.stages["Glacial Sediment.md"]?.contains(.noLocalMatch) == true)
    }

    @Test("A Note named only in surrounding source does not bypass selected-focus coverage")
    func surroundingIdentityIsNotFocus() async throws {
        let result = try await evaluate(
            focus: "spectral calibration measurement",
            surrounding: "Appendix is discussed elsewhere.",
            notes: [
                "Appendix.md": "Calibration of an office printer is scheduled for tomorrow.",
                "Material.md": "Spectral calibration measurement uses a reference lamp.",
            ])
        #expect(result.paths == ["Material.md"])
    }

    @Test("A negation-only Note name supplies no single-term exception")
    func negationIsNotIdentityEvidence() async throws {
        let result = try await evaluate(
            focus: "not spectral calibration measurement",
            notes: [
                "Not.md": "Not an available fixture.",
                "Material.md": "Spectral calibration measurement uses a reference lamp.",
            ])
        #expect(result.paths == ["Material.md"])
    }

    @Test("Diagnostics distinguish duplicate material and result limits from focus rejection")
    func terminalDiagnostics() async throws {
        var notes = ["A Copy.md": "Spectral calibration.", "B Copy.md": "Spectral calibration."]
        for number in 0..<8 {
            notes["Material-\(number).md"] = "Spectral calibration measures fixture \(number)."
        }
        let result = try await evaluate(focus: "spectral calibration", notes: notes)
        #expect(result.paths.count == RelatedContentContract.maximumPassages)
        #expect(result.stages["B Copy.md"]?.contains(.duplicate) == true)
        #expect(result.stages.values.contains { $0.contains(.limited) })
        for (path, stages) in result.stages {
            let terminal = stages.intersection([.selected, .duplicate, .limited])
            #expect(terminal.count == 1)
            #expect(stages.contains(.eligible))
            #expect(stages.contains(.selected) == result.paths.contains(path))
        }
    }

    private struct Result {
        let paths: Set<String>
        let stages: [String: Set<RelatedContentRankingDiagnostic.Stage>]
        let passages: [RelatedContentPassage]
    }

    private func evaluate(focus: String, surrounding: String = "", alternatives: [String] = [], notes: [String: String]) async throws -> Result {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/related-focus-tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics")
        let index = try TriptychSearchIndex(databaseURL: root.appendingPathComponent("index.sqlite"), triptychID: UUID(), vaults: [vault])
        let documents = notes.sorted { $0.key < $1.key }.map { path, text in
            SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: path, rawContent: "\u{FEFF}" + text.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"))
        }
        _ = try await index.synchronize(documents)
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault.id, relativePath: "Current.md"), source: surrounding + "\n\n" + focus,
                focuses: [.init(kind: .selectedPassage, text: focus)]
                    + (alternatives.isEmpty
                        ? [] : [.init(kind: .researchRequest, text: alternatives.joined(separator: " "), literalAlternatives: alternatives)])))
        let response = try await index.relatedMaterialSourceCandidates(request)
        var seen = Set<VaultQualifiedNoteID>()
        let candidates = (response.identityCandidates + response.lexicalCandidates).filter { seen.insert($0.note).inserted }
        let sources = try candidates.map { candidate in
            RelatedContentSource(
                candidate: candidate, document: try #require(documents.first { $0.document.relativePath == candidate.note.relativePath }).document)
        }
        var stages: [String: Set<RelatedContentRankingDiagnostic.Stage>] = [:]
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: sources) {
            stages[$0.note.relativePath, default: []].insert($0.stage)
        }
        #expect(try await index.relatedPassages(request, sources: sources) == passages)
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == passages)
        for passage in passages {
            let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: original.document.rawContent))
            #expect(String(original.document.rawContent[range]) == passage.source)
            #expect(passage.candidate.fingerprint == original.document.fingerprint)
        }
        return .init(paths: Set(passages.map { $0.candidate.note.relativePath }), stages: stages, passages: passages)
    }
}
