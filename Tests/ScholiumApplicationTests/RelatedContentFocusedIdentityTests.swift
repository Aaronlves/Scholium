import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication
@testable import ScholiumCore

@Suite("Related-content focused identity source loading")
struct RelatedContentFocusedIdentityTests {
    @Test("All unsampled named sources reach passages before the candidate preview is limited")
    func fullSourcesBeforePreviewLimit() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/related-focused-identity-application/\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("analyses")
        let topics = root.appendingPathComponent("topics")
        let works = root.appendingPathComponent("works")
        for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let seed = "An unrelated draft."
        try Data(seed.utf8).write(to: works.appendingPathComponent("Draft.md"))
        let identities = ["celadon", "dolomite", "emerald", "fluorite", "granite"]
        let paths = ["Celadon.md", "Dolomite.md", "Glossary A.md", "Glossary B.md", "Granite.md"]
        var originals: [String: Data] = [:]
        for (number, path) in paths.enumerated() {
            let properties = (2...3).contains(number) ? "---\r\naliases: [\(identities[number])]\r\n---\r\n\r\n" : ""
            let bytes = Data("\u{FEFF}\(properties)\(identities[number].capitalized) identifies nonprivate sample \(number).\r\n".utf8)
            try bytes.write(to: topics.appendingPathComponent(path))
            originals[path] = bytes
        }
        let context = (0..<100).map { "context\($0)" }
        let focus = (Array(context.prefix(2)) + identities + Array(context.dropFirst(2))).joined(separator: " ")
        let sampled = RelatedContentQueryTerms.terms(in: focus, limit: RelatedContentContract.maximumFocusSeedTerms)
        try #require(Set(sampled).isDisjoint(with: identities))
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(applicationSupportURL: root.appendingPathComponent("state"), workspaceRegistryStorageURL: root.appendingPathComponent("registry"))))
        do {
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Focused identity fixture")
            let worksID = try #require(handle.assignment.vault(for: .output)?.id)
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: worksID, relativePath: "Draft.md"), source: seed,
                    focuses: [.init(kind: .researchRequest, text: focus)]),
                identityLimit: 0, lexicalLimit: 1)
            let cold = try await handle.discovery.relatedContent(request)
            #expect(cold.state == .current && cold.omittedSourceCount == 0)
            #expect(cold.identityCandidates.isEmpty)
            #expect(cold.lexicalCandidates.count == 1 && cold.lexicalHasMore)
            #expect(cold.passages.count == identities.count)
            #expect(Set(cold.passages.map(\.candidate.note.relativePath)) == Set(paths))
            #expect(await handle.lastRelatedContentMeasurement?.sourceCount == identities.count)
            let topicsID = try #require(handle.assignment.vault(for: .topicKnowledge)?.id)
            for passage in cold.passages {
                let path = passage.candidate.note.relativePath
                let bytes = try Data(contentsOf: topics.appendingPathComponent(path))
                #expect(bytes == originals[path])
                let text = String(decoding: bytes, as: UTF8.self)
                let range = try #require(
                    Range(
                        NSRange(
                            location: passage.range.utf16LowerBound,
                            length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: text))
                #expect(Data(passage.source.utf8) == Data(text[range].utf8))
                #expect(passage.candidate.fingerprint == DocumentFingerprint(content: text))
                #expect(passage.candidate.note.vaultID == topicsID && passage.candidate.vaultRole == .topicKnowledge)
            }
            try await handle.discovery.prepareRelatedContent(request)
            #expect(try await handle.discovery.relatedContent(request) == cold)
            #expect(try Data(contentsOf: works.appendingPathComponent("Draft.md")) == Data(seed.utf8))
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }
}
