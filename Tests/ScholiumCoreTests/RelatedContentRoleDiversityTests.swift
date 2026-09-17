import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content role diversity")
struct RelatedContentRoleDiversityTests {
    private let analyses = UUID(uuidString: "687B8C4C-1CDD-43B2-BE08-E5E9CD5177BD")!
    private let topics = UUID(uuidString: "1C956FD7-FE5B-4311-BCCA-24DD7A352ED4")!
    private let works = UUID(uuidString: "E36DA66F-430C-4436-8FFB-DB6D5A04B11C")!

    // Equal lengths and no focus terms: ranking input frequencies remain
    // controlled while each Note offers visibly distinct authored material.
    private static let distinctContexts = [
        "Choices require reflective endorsement.",
        "Citizens govern collective institutions.",
        "Promises constrain future decisions.",
        "Agents reconsider inherited commitments.",
        "Judgment weighs competing possibilities.",
        "Consent expresses voluntary authorization.",
    ]

    private func source(_ path: String, role: VaultRole, text: String) -> RelatedContentSource {
        let vault: UUID
        switch role {
        case .sourceCorpus: vault = analyses
        case .topicKnowledge: vault = topics
        case .draftProject: vault = works
        case .other: preconditionFailure("This fixture uses only Triptych roles")
        }
        let document = NoteDocument(relativePath: path, rawContent: "\u{FEFF}# " + path + "\r\n\r\n" + text + "\r\n")
        return .init(
            candidate: .init(
                note: .init(vaultID: vault, relativePath: path), vaultRole: role,
                title: path, fingerprint: document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
            document: document)
    }

    private func evaluate(_ sources: [RelatedContentSource], focus: String) throws -> [RelatedContentPassage] {
        let seed = RelatedContentSeedSnapshot(
            noteID: .init(vaultID: works, relativePath: "Current.md"), source: "Unsaved " + focus,
            focuses: [.init(kind: .selectedPassage, text: focus)])
        // An exceptionally strong matching self candidate must still disappear.
        let current = source("Current.md", role: .draftProject, text: "[[Target]]{{" + String(repeating: focus + " ", count: 12) + "}}")
        let complete = sources + [current]
        let request = RelatedContentRequest(seed: seed)
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: complete)
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: complete.reversed()) == passages)
        #expect(passages.count == 6)
        #expect(!passages.contains { $0.candidate.note == seed.noteID })
        #expect(Set(passages.map { $0.candidate.note }).count == passages.count)
        for passage in passages {
            let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            #expect(passage.candidate.vaultRole == original.candidate.vaultRole)
            #expect(passage.candidate.fingerprint == original.document.fingerprint)
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: original.document.rawContent))
            #expect(String(original.document.rawContent[range]) == passage.source)
            #expect(passage.range.line == 3)
        }
        return passages
    }

    @Test("Comparable Analyses and Topics remain visible beside several equally matching Works")
    func comparableRoles() throws {
        // Identical annotation fields provide equal relevance across roles;
        // distinct four-word prose keeps this about role representation rather
        // than exact/near-copy suppression. Titles put all Works before the rest.
        let ownWriting = Self.distinctContexts.enumerated().map {
            source("A Work \($0.offset + 1).md", role: .draftProject, text: "[[Target]]{{freedom autonomy}} " + $0.element)
        }
        let sources =
            ownWriting + [
                source("Z Analysis.md", role: .sourceCorpus, text: "[[Target]]{{freedom autonomy}} Interference limits available alternatives."),
                source("Z Topic.md", role: .topicKnowledge, text: "[[Target]]{{freedom autonomy}} Distinctions clarify individual agency."),
            ]
        let passages = try evaluate(sources, focus: "freedom autonomy")
        #expect(Set(passages.map { $0.candidate.vaultRole }) == [.sourceCorpus, .topicKnowledge, .draftProject])
        #expect(passages.contains { $0.candidate.note.relativePath == "Z Analysis.md" })
        #expect(passages.contains { $0.candidate.note.relativePath == "Z Topic.md" })
    }

    @Test("Role representation cannot promote less complete writing-focus coverage")
    func coverageBeforeRoles() throws {
        let ownWriting = Self.distinctContexts.enumerated().map {
            source("Work \($0.offset + 1).md", role: .draftProject, text: "Freedom autonomy deliberation responsibility: " + $0.element)
        }
        let sources =
            ownWriting + [
                source("Analysis.md", role: .sourceCorpus, text: "[[Target]]{{freedom autonomy}}"),
                source("Topic.md", role: .topicKnowledge, text: "[[Target]]{{freedom autonomy}}"),
            ]
        let passages = try evaluate(sources, focus: "freedom autonomy deliberation responsibility")
        #expect(passages.allSatisfy { $0.candidate.vaultRole == .draftProject })
        #expect(Set(passages.map { $0.candidate.note }) == Set(ownWriting.map { $0.candidate.note }))
    }

    @Test("Incidental same-coverage references cannot displace strongly matching Works merely to fill a role")
    func relevanceBeforeRoles() throws {
        let ownWriting = Self.distinctContexts.enumerated().map {
            source("Work \($0.offset + 1).md", role: .draftProject, text: "[[Target]]{{freedom autonomy}} " + $0.element)
        }
        // The terms occur once in a long unrelated paragraph. Eligibility is
        // intentional; equal distinct-term coverage alone does not make this
        // material comparable to concentrated authored annotation matches.
        let incidental = "Freedom autonomy. " + String(repeating: "Botanical specimens have green leaves and woody stems. ", count: 90)
        let sources =
            ownWriting + [
                source("Analysis.md", role: .sourceCorpus, text: incidental),
                source("Topic.md", role: .topicKnowledge, text: incidental),
            ]
        let passages = try evaluate(sources, focus: "freedom autonomy")
        #expect(passages.allSatisfy { $0.candidate.vaultRole == .draftProject })
        #expect(Set(passages.map { $0.candidate.note }) == Set(ownWriting.map { $0.candidate.note }))
    }
}
