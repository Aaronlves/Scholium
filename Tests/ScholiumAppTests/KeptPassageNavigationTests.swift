import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Kept passage lifecycle and navigation", .serialized) @MainActor
struct KeptPassageNavigationTests {
    @Test("Snapshots survive real Note and role changes, refresh and same-Triptych binding in their own window")
    func windowLifetime() async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let peer = fixture.peer
            let card = fixture.card
            let entry = KeptPassage(card: card)
            window.keepRelatedPassage(card)
            window.keepRelatedPassage(card)
            #expect(window.researchController.keptPassages.entries == [entry])
            #expect(peer.researchController.keptPassages.entries.isEmpty)
            peer.keepRelatedPassage(card)
            try await window.prepareWorkspaceSelection(.paperAnalysis, sourceScope: .library)
            await window.openWorkspaceReference(card.reference)
            await window.waitForPendingDocumentTransitionsForTesting()
            _ = try #require(await window.refreshAfterResearchHandoff())
            window.researchController.selectInspectorMode(.related)
            window.researchController.relatedMaterials.reset()
            window.researchController.bind(to: fixture.researchCapabilities(id: fixture.capabilities.id))
            #expect(window.researchController.keptPassages.entries == [entry])
            let items = ConnectionsProjection.make(
                graph: window.linkGraph, catalogNotes: window.workspaceCatalog?.notes,
                current: card.candidate.note, direction: .outgoing
            ).items
            let item = try #require(items.first)
            await window.keepLinkPassage(item)
            #expect(window.researchController.keptPassages.contains(item))
            #expect(window.researchController.keptPassages.entries.count == 2)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            window.researchController.bind(to: fixture.researchCapabilities(id: UUID()))
            #expect(window.researchController.keptPassages.entries.isEmpty)
            #expect(peer.researchController.keptPassages.entries == [entry])
        }
    }

    @Test("Kept source opening needs no search seed and never selects an obsolete passage or abandons a draft for a missing source")
    func safeSourceOpening() async throws {
        try await withFixture { fixture in
            let window = fixture.window
            window.keepRelatedPassage(fixture.card)
            let entry = try #require(window.researchController.keptPassages.entries.first)
            #expect(window.researchController.relatedMaterials.seed == nil)
            await window.openKeptPassage(entry)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.reference.vaultID == entry.reference.vaultID)
            #expect(window.currentDocumentDescriptor?.reference.relativePath == entry.reference.relativePath)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == entry.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            #expect(window.documentController.sourceLocationRequest?.line == entry.sourceRange.line)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == entry.fingerprint.sha256)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)

            let changed = fixture.originalSource + Data("External change.\r\n".utf8)
            try changed.write(to: fixture.sourceFile)
            _ = try #require(await window.refreshAfterResearchHandoff())
            await window.openKeptPassage(entry)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.researchController.keptPassages.entries == [entry])
            #expect(window.researchController.keptPassages.errorMessage == KeptPassageError.changedSource.localizedDescription)
            #expect(try Data(contentsOf: fixture.sourceFile) == changed)

            await window.openWorkspaceReference(fixture.draft)
            await window.waitForPendingDocumentTransitionsForTesting()
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            session.editingSource = "Unsaved writing must remain exact."
            try FileManager.default.removeItem(at: fixture.sourceFile)
            await window.openKeptPassage(entry)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
            #expect(session.editingSource == "Unsaved writing must remain exact.")
            #expect(session.hasUnsavedChanges)
            #expect(window.researchController.keptPassages.entries == [entry])
            #expect(window.researchController.keptPassages.errorMessage == KeptPassageError.missingSource.localizedDescription)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            session.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self)
        }
    }

    enum RemovalAction: CaseIterable, Sendable { case remove, reset, removeAndKeepAgain }

    @Test("Removed snapshots cannot revive an old queued open or save its outgoing dirty draft", arguments: RemovalAction.allCases)
    func cancelledQueuedOpening(change: RemovalAction) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            window.keepRelatedPassage(fixture.card)
            let kept = window.researchController.keptPassages
            let entry = try #require(kept.entries.first)
            let original = window.currentDocumentDescriptor?.sessionKey
            let descriptor = try #require(window.currentDocumentDescriptor)
            let draftSession = window.documentController.session(for: descriptor)
            draftSession.suppressAutosave = true
            let dirtyText = "Queued snapshot cancellation must not save this draft."
            draftSession.editingSource = dirtyText
            defer { draftSession.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self) }
            #expect(draftSession.hasUnsavedChanges)
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("The fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            await window.openKeptPassage(entry)
            switch change {
            case .reset: kept.reset()
            case .remove: kept.remove(entry.id)
            case .removeAndKeepAgain:
                kept.remove(entry.id)
                kept.retain(entry)
            }
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == original)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(kept.entries == (change == .removeAndKeepAgain ? [entry] : []))
            #expect(draftSession.editingSource == dirtyText)
            #expect(draftSession.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("A source deleted while queued cannot select its retained tab or save the active dirty draft")
    func missingQueuedSource() async throws {
        try await withFixture { fixture in
            let window = fixture.window
            window.keepRelatedPassage(fixture.card)
            let entry = try #require(window.researchController.keptPassages.entries.first)
            try await window.activateWorkspaceReference(entry.reference, tabActivation: .place(.newTab))
            await window.openWorkspaceReference(fixture.draft)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentTabController.tabs.count == 2)
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            let dirtyText = "The missing source must not save or replace this draft."
            session.editingSource = dirtyText
            defer { session.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self) }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("The fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            await window.openKeptPassage(entry)
            try FileManager.default.removeItem(at: fixture.sourceFile)
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(session.editingSource == dirtyText && session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #expect(window.researchController.keptPassages.entries == [entry])
            #expect(!window.shellState.operationIssues.isEmpty)
        }
    }

    @MainActor private final class TransitionGate {
        private(set) var started = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            started = true
            await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            try await body(fixture)
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @MainActor private struct Fixture {
        let root: URL
        let sourceFile: URL
        let draftFile: URL
        let originalSource: Data
        let originalDraft: Data
        let store: WorkspaceStore
        let capabilities: WindowWorkspaceCapabilities
        let window: WindowModel
        let peer: WindowModel
        let card: RelatedMaterialCard
        let draft: VaultNoteReference

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/kept-passages/\(UUID())")
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            let sourceFile = analyses.appendingPathComponent("Source.md")
            let draftFile = works.appendingPathComponent("Draft.md")
            var store: WorkspaceStore?
            do {
                for directory in [analyses, topics, works] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                try Data("\u{FEFF}# Source\r\n\r\nExact **source** [[Draft|visible]]{{Qualified.}}.\r\n".utf8).write(to: sourceFile)
                try Data("# Draft\n\nIndependent writing.\n".utf8).write(to: draftFile)
                let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Kept Passage fixture")
                let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
                let peer = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
                for model in [window, peer] {
                    await model.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
                    try await model.openWorkspaceVault(.output)
                    model.documentController.rememberPresentationMode(.read)
                }
                let source = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
                let draft = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Draft.md" })
                await window.openWorkspaceReference(draft.reference)
                await window.waitForPendingDocumentTransitionsForTesting()
                let document = try await capabilities.documents.load(.init(vaultID: source.reference.vaultID, relativePath: source.reference.relativePath))
                let paragraph = try #require(MarkdownSemanticDocument(parsing: document).blocks.first { $0.kind == .paragraph })
                let captured = try #require(DocumentPassageSnapshot.capture(source: document.rawContent, range: paragraph.span.nsRange))
                let candidate = RelatedContentCandidate(
                    note: .init(vaultID: source.reference.vaultID, relativePath: source.reference.relativePath), vaultRole: source.reference.vaultRole,
                    title: source.title, fingerprint: document.fingerprint,
                    reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
                let display = ResearchExcerptPresentation.readableText(captured.excerpt, includingAnnotations: true)
                let passage = RelatedContentPassage(
                    candidate: candidate, range: captured.sourceRange, source: captured.excerpt, displayText: display, excerpt: display,
                    excerptMatches: [], matches: [])
                return Fixture(
                    root: root, sourceFile: sourceFile, draftFile: draftFile,
                    originalSource: try Data(contentsOf: sourceFile), originalDraft: try Data(contentsOf: draftFile), store: created,
                    capabilities: capabilities,
                    window: window, peer: peer, card: .init(passage: passage, reference: source.reference), draft: draft.reference)
            } catch {
                await store?.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func researchCapabilities(id: UUID) -> ResearchControllerCapabilities {
            .init(
                triptychID: id, documents: capabilities.documents, research: capabilities.research.research,
                agentCollaboration: capabilities.agentCollaboration, changes: capabilities.changes, recoveryRecordsURL: capabilities.research.recoveryRecordsURL
            )
        }

        func shutdown() async {
            for model in [window, peer] {
                model.libraryRevealTask?.cancel()
                model.documentTransitionCoordinator.cancelAll()
                await model.waitForPendingDocumentTransitionsForTesting()
                model.researchController.unbind()
                model.workspaceCancellables.removeAll()
                model.windowWorkspaceController.cancelAll()
                for tab in model.documentTabController.tabs { model.documentController.session(for: tab.document.editingTarget).cancelScheduledWork() }
            }
            await store.shutdownApplicationRuntime()
        }
    }
}
