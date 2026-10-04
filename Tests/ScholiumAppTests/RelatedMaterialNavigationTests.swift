import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Writing reference source navigation", .serialized) @MainActor
struct RelatedMaterialNavigationTests {
    @Test("Reference recovery preserves a different dirty draft; changed and dirty sources never use old locations")
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
        let draftSource = "# Draft\n\nExact source.\n"
        let draftFile = works.appendingPathComponent("Draft.md")
        try Data(draftSource.utf8).write(to: draftFile)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: triptych, triptychName: "Reference Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.output)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let draft = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Draft.md" })
            await window.openWorkspaceReference(draft.reference)
            await window.waitForPendingDocumentTransitionsForTesting()
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

            func prepareSeed() async throws -> RelatedMaterialsSeed {
                let descriptor = try #require(window.currentDocumentDescriptor)
                let snapshot = RelatedContentSeedSnapshot(
                    noteID: .init(vaultID: descriptor.reference.vaultID, relativePath: descriptor.reference.relativePath), source: "Exact source.")
                let seed = RelatedMaterialsSeed(
                    request: .init(seed: snapshot),
                    attachment: .init(
                        noteID: descriptor.sessionKey.noteID, vaultID: descriptor.reference.vaultID,
                        relativePath: descriptor.reference.relativePath, text: "Exact source.", fingerprint: snapshot.fingerprint,
                        sourceLine: 1))
                await materials.find(
                    capture: { seed },
                    retrieve: { request in
                        .init(
                            requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .init("fixture"),
                            availability: .unavailable, state: .current, identityCandidates: [], lexicalCandidates: [candidate], identityHasMore: false,
                            lexicalHasMore: false, passages: [passage])
                    }, references: [note.reference]
                ).value
                return seed
            }
            _ = try await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.reference.vaultID == note.reference.vaultID)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == note.reference.relativePath)
            #expect(window.documentController.sourceLocationRequest?.line == 3)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == candidate.fingerprint.sha256)
            #expect(window.shellState.operationIssues.isEmpty)

            let external = source + "External change\r\n"
            try Data(external.utf8).write(to: file)
            _ = try await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest == nil)
            let changedNotice = try #require(window.shellState.operationIssues.last)
            #expect(changedNotice.kind == .information)
            #expect(changedNotice.message.contains("different version"))
            #expect(try Data(contentsOf: file) == Data(external.utf8))

            await window.openWorkspaceReference(draft.reference)
            await window.waitForPendingDocumentTransitionsForTesting()
            let draftDescriptor = try #require(window.currentDocumentDescriptor)
            #expect(draftDescriptor.reference.vaultID == draft.reference.vaultID)
            #expect(draftDescriptor.reference.relativePath == draft.reference.relativePath)
            #expect(draftDescriptor.sessionKey.noteID == draft.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            let draftSession = window.documentController.session(for: draftDescriptor)
            draftSession.suppressAutosave = true
            draftSession.editingSource = "Unsaved draft must remain untouched."
            #expect(draftSession.hasUnsavedChanges)
            let retainedSeed = try await prepareSeed()
            #expect(materials.cards == [card])
            // The unavailable reference belongs to another Note. Its handled
            // failure must retain the active draft and writing context.
            try FileManager.default.removeItem(at: file)
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == draftDescriptor.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            let unavailableNotice = try #require(window.shellState.operationIssues.last)
            #expect(unavailableNotice.kind == .information)
            #expect(unavailableNotice.message.contains("could not be opened"))
            #expect(unavailableNotice.message.contains("Find Writing References"))
            #expect(!unavailableNotice.message.contains("Note was opened"))
            #expect(materials.seed?.request.id == retainedSeed.request.id)
            #expect(materials.cards == [card])
            #expect(materials.issue == nil)
            #expect(draftSession.editingSource == "Unsaved draft must remain untouched." && draftSession.hasUnsavedChanges)
            #expect(try Data(contentsOf: draftFile) == Data(draftSource.utf8))
            // The detached fixture's dirty buffer has served its preservation
            // assertion. Return it to saved source before testing navigation.
            draftSession.editingSource = draftSource
            #expect(!draftSession.hasUnsavedChanges)
            try Data(external.utf8).write(to: file)
            _ = try #require(await window.refreshAfterResearchHandoff())
            #expect(window.workspaceCatalog?.notes.contains { $0.reference == note.reference } == true)

            _ = try await prepareSeed()
            #expect(await window.useRelatedMaterial(card, inChat: false))
            await window.waitForPendingDocumentTransitionsForTesting()
            let descriptor = try #require(window.currentDocumentDescriptor)
            #expect(descriptor.reference.vaultID == note.reference.vaultID)
            #expect(descriptor.reference.relativePath == note.reference.relativePath)
            #expect(descriptor.sessionKey.noteID == note.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            session.editingSource = "Unsaved source must remain untouched."
            #expect(session.hasUnsavedChanges)
            _ = try await prepareSeed()
            #expect(window.researchController.relatedMaterials.seed != nil)
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
