import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Writing reference source navigation", .serialized) @MainActor
struct RelatedMaterialNavigationTests {
    @Test("Current references locate their source; changed and dirty sources explain why location is unavailable")
    func revisionCheckedOpening() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/related-reference-navigation/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = root.appendingPathComponent("Triptych")
        let analyses = triptych.appendingPathComponent("Analyses")
        let topics = triptych.appendingPathComponent("Topics")
        let works = triptych.appendingPathComponent("Works")
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = "\u{FEFF}# Source\r\n\r\nExact **source** 😀.\r\n"
        let file = analyses.appendingPathComponent("Source.md")
        try Data(source.utf8).write(to: file)
        try Data("# Draft\n\nExact source.\n".utf8).write(to: works.appendingPathComponent("Draft.md"))
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: triptych, triptychName: "Reference Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.output)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let candidate = RelatedContentCandidate(
                note: .init(vaultID: note.reference.vaultID, relativePath: "Source.md"),
                vaultRole: .sourceCorpus, title: "Source", fingerprint: .init(content: source),
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
            let exact = (source as NSString).range(of: "Exact **source** 😀.")
            let passage = RelatedContentPassage(
                candidate: candidate,
                range: .init(utf16LowerBound: exact.location, utf16UpperBound: NSMaxRange(exact), line: 3, column: 1, endLine: 3, endColumn: 21),
                source: "Exact **source** 😀.", displayText: "Exact source 😀.", excerpt: "Exact source 😀.", excerptMatches: [], matches: [])
            let card = RelatedMaterialCard(passage: passage, reference: note.reference)
            let materials = window.researchController.relatedMaterials

            func prepareSeed() async {
                let snapshot = RelatedContentSeedSnapshot(noteID: candidate.note, source: "Exact source.")
                let seed = RelatedMaterialsSeed(
                    request: .init(seed: snapshot),
                    attachment: .init(
                        noteID: UUID(), vaultID: candidate.note.vaultID, relativePath: "Draft.md", text: "Exact source.", fingerprint: snapshot.fingerprint,
                        sourceLine: 1))
                await materials.find(
                    capture: { seed },
                    retrieve: { request in
                        .init(
                            requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .init("fixture"),
                            availability: .unavailable, state: .empty, identityCandidates: [], lexicalCandidates: [], identityHasMore: false,
                            lexicalHasMore: false)
                    }, references: []
                ).value
            }
            await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.reference.vaultID == note.reference.vaultID)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == note.reference.relativePath)
            #expect(window.documentController.sourceLocationRequest?.line == 3)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == candidate.fingerprint.sha256)
            #expect(window.shellState.operationIssues.isEmpty)

            let external = source + "External change\r\n"
            try Data(external.utf8).write(to: file)
            await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest == nil)
            let changedNotice = try #require(window.shellState.operationIssues.last)
            #expect(changedNotice.kind == .information)
            #expect(changedNotice.message.contains("different version"))
            #expect(try Data(contentsOf: file) == Data(external.utf8))

            try FileManager.default.removeItem(at: file)
            await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.kind == .information)
            #expect(window.shellState.operationIssues.last?.message.contains("could not be verified") == true)
            try Data(external.utf8).write(to: file)

            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            session.editingSource = "Unsaved source must remain untouched."
            await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains("could not be verified") == true)
            #expect(session.editingSource == "Unsaved source must remain untouched." && session.hasUnsavedChanges)
            #expect(try Data(contentsOf: file) == Data(external.utf8))
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
