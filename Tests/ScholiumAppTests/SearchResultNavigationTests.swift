import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Search result source navigation", .serialized) @MainActor
struct SearchResultNavigationTests {
    @Test("Search opens the exact matching range and retains Document mode", arguments: [WindowOpenDisposition.replaceCurrent, .newTab])
    func currentResult(disposition: WindowOpenDisposition) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: disposition)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.reference.relativePath == "Source.md")
            #expect(window.documentController.sourceLocationRequest?.range == fixture.result.sourceRange)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == fixture.result.fingerprint.sha256)
            #expect(window.requestPresentationMode == .read)
            #expect(window.documentTabController.tabs.count == (disposition == .newTab ? 2 : 1))
            #expect(window.shellState.operationIssues.isEmpty)
            let savedSource = try Data(contentsOf: fixture.sourceFile)
            let savedDraft = try Data(contentsOf: fixture.draftFile)
            #expect(savedSource == fixture.originalSource)
            #expect(savedDraft == fixture.originalDraft)
        }
    }

    @Test("A queued changed or missing Search result cannot navigate or save the outgoing draft", arguments: [false, true])
    func changedQueuedResult(deleted: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            session.editingSource = "Unsaved draft must remain exact."
            defer { session.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self) }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
            let changed = Data("New first paragraph.\r\n\r\n".utf8) + fixture.originalSource
            if deleted { try FileManager.default.removeItem(at: fixture.sourceFile) } else { try changed.write(to: fixture.sourceFile) }
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(session.hasUnsavedChanges)
            #expect(session.editingSource == "Unsaved draft must remain exact.")
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #expect(!window.shellState.operationIssues.isEmpty)
            if !deleted { #expect(try Data(contentsOf: fixture.sourceFile) == changed) }
        }
    }

    @Test("A queued Search follows a newly owning window without touching the identical-source origin", arguments: [false, true])
    func queuedPeerOwnership(dirty: Bool) async throws {
        try await withFixture(identicalSources: true) { fixture in
            try await withPeer(of: fixture) { peer in
                let window = fixture.window
                let origin = try #require(window.currentDocumentDescriptor)
                let initialMode = window.requestPresentationMode
                let originSession = window.documentController.session(for: origin)
                originSession.suppressAutosave = true
                let originText = dirty ? "Unsaved origin must not be prepared." : String(decoding: fixture.originalDraft, as: UTF8.self)
                originSession.editingSource = originText
                defer { originSession.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self) }
                let gate = TransitionGate()
                defer { gate.release() }
                window.documentTransitionCoordinator.enqueue(
                    prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
                await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
                let peerReference = try #require(peer.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" }).reference
                try await peer.activateWorkspaceReference(peerReference, tabActivation: .place(.newTab))
                let destination = try #require(peer.currentDocumentDescriptor)
                let targetSession = peer.documentController.session(for: destination)
                targetSession.suppressAutosave = true
                if dirty { targetSession.editingSource = "Unsaved target must retain its position." }
                defer { targetSession.editingSource = String(decoding: fixture.originalSource, as: UTF8.self) }
                peer.documentController.requestSourceLocation(line: nil)
                gate.release()
                await window.waitForPendingDocumentTransitionsForTesting()
                await peer.waitForPendingDocumentTransitionsForTesting()
                #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
                #expect(window.documentController.sourceLocationRequest == nil)
                #expect(window.requestPresentationMode == initialMode)
                #expect(originSession.editingSource == originText)
                #expect(originSession.hasUnsavedChanges == dirty)
                #expect(originSession.editError == nil)
                #expect(window.lastSaveError == nil)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
                #expect(peer.currentDocumentDescriptor?.sessionKey == destination.sessionKey)
                if dirty {
                    #expect(peer.documentController.sourceLocationRequest == nil)
                    #expect(targetSession.editingSource == "Unsaved target must retain its position.")
                    #expect(targetSession.hasUnsavedChanges)
                    #expect(peer.shellState.operationIssues.last?.message == SearchResultNavigationError.staleResult.localizedDescription)
                } else {
                    #expect(peer.documentController.sourceLocationRequest?.range == fixture.result.sourceRange)
                    #expect(peer.documentController.sourceLocationRequest?.sourceFingerprint == fixture.result.fingerprint.sha256)
                }
                #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            }
        }
    }

    @Test("Queued Search binds the stable Note after a move even when the former path is reused", arguments: [false, true])
    func queuedMovedIdentity(edited: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            let draft = "Unsaved draft must not leave for a stale result."
            session.editingSource = edited ? draft : String(decoding: fixture.originalDraft, as: UTF8.self)
            defer { session.editingSource = String(decoding: fixture.originalDraft, as: UTF8.self) }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let noteID = try #require(fixture.result.stableNoteID.flatMap(UUID.init(uuidString:)))
            let target = NoteMutationTarget(
                documentID: .init(vaultID: fixture.result.vaultID, relativePath: "Source.md"),
                stableNoteID: noteID, revision: fixture.result.fingerprint)
            _ = try await capabilities.libraryMutations.move(target, to: "Relocated.md")
            let moved = fixture.sourceFile.deletingLastPathComponent().appendingPathComponent("Relocated.md")
            let movedBytes = edited ? Data("Changed after moving.\r\n".utf8) + fixture.originalSource : fixture.originalSource
            try movedBytes.write(to: moved)
            try fixture.originalSource.write(to: fixture.sourceFile)
            await window.retryDerivedRefresh()
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            if edited {
                #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
                #expect(window.documentController.sourceLocationRequest == nil)
                #expect(session.editingSource == draft && session.hasUnsavedChanges)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
                #expect(!window.shellState.operationIssues.isEmpty)
                #expect(session.editError == nil)
                #expect(window.lastSaveError == nil)
            } else {
                #expect(window.currentDocumentDescriptor?.sessionKey.noteID == noteID)
                #expect(window.currentDocumentDescriptor?.reference.relativePath == "Relocated.md")
                #expect(window.documentController.sourceLocationRequest?.range == fixture.result.sourceRange)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
            #expect(try Data(contentsOf: moved) == movedBytes)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
        }
    }

    @Test("Saved-source Search cannot apply an old range to a dirty target buffer")
    func dirtyTarget() async throws {
        try await withFixture { fixture in
            let window = fixture.window
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
            await window.waitForPendingDocumentTransitionsForTesting()
            let target = try #require(window.currentDocumentDescriptor)
            window.documentController.requestSourceLocation(line: nil)
            let session = window.documentController.session(for: target)
            session.suppressAutosave = true
            session.editingSource = "Unsaved target shifts the source range."
            defer { session.editingSource = String(decoding: fixture.originalSource, as: UTF8.self) }
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == target.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(session.hasUnsavedChanges)
            #expect(session.editingSource == "Unsaved target shifts the source range.")
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(window.shellState.operationIssues.last?.message == SearchResultNavigationError.staleResult.localizedDescription)
        }
    }

    @Test("Links retain their source revision through routing and never locate a changed or dirty passage", arguments: [false, true])
    func linkSourceRevision(dirty: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent)
            await window.waitForPendingDocumentTransitionsForTesting()
            window.documentController.requestSourceLocation(line: nil)
            let projection = ConnectionsProjection.make(
                graph: window.linkGraph, catalogNotes: window.workspaceCatalog?.notes,
                current: fixture.result.noteReference, direction: .outgoing)
            let item = try #require(projection.items.first)
            let source = try #require(item.source)
            var routed: WindowDocumentRoute?
            let research = ResearchController(intentHandler: {
                if case .openDocument(let route) = $0 { routed = route }
            })
            research.requestOpen(
                source.reference, sourceLine: item.edge.occurrence.linkSpan.start.line,
                sourceFingerprint: source.fingerprint)
            let route = try #require(routed)
            #expect(route.reference == source.reference)
            #expect(route.sourceLocator?.line == item.edge.occurrence.linkSpan.start.line)
            #expect(route.sourceFingerprint == fixture.result.fingerprint)
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            let changed = "Changed first line.\r\n\r\n" + String(decoding: fixture.originalSource, as: UTF8.self)
            if dirty { session.editingSource = changed } else { try Data(changed.utf8).write(to: fixture.sourceFile) }
            defer { session.editingSource = String(decoding: fixture.originalSource, as: UTF8.self) }
            await window.openWorkspaceReference(
                route.reference, line: route.sourceLocator?.line, sourceFingerprint: route.sourceFingerprint)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains(dirty ? "could not be verified" : "different version") == true)
            if dirty {
                #expect(session.editingSource == changed && session.hasUnsavedChanges)
                #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            } else {
                #expect(try Data(contentsOf: fixture.sourceFile) == Data(changed.utf8))
            }
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

    private func withFixture(identicalSources: Bool = false, _ body: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture.make(identicalSources: identicalSources)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            try await body(fixture)
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    private func withPeer(of fixture: Fixture, _ body: (WindowModel) async throws -> Void) async throws {
        let triptychID = try #require(fixture.window.workspaceAssignment?.id)
        let peer = WindowModel(workspaceStore: fixture.store, requestedTriptychID: triptychID)
        await peer.refreshWorkspaceAssignment(preferredTriptychID: triptychID)
        try await peer.openWorkspaceVault(.paperAnalysis)
        fixture.store.documentLocations.register(fixture.window)
        fixture.store.documentLocations.register(peer)
        defer {
            fixture.store.documentLocations.unregister(fixture.window)
            fixture.store.documentLocations.unregister(peer)
        }
        do {
            try await body(peer)
            await Fixture.stop(peer)
        } catch {
            await Fixture.stop(peer)
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
        let window: WindowModel
        let result: NoteSearchResult

        static func make(identicalSources: Bool = false) async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/feature-audit/research-workflow/fixtures/\(UUID())")
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            let sourceFile = analyses.appendingPathComponent("Source.md")
            let draftFile = works.appendingPathComponent("Draft.md")
            let source = "\u{FEFF}# Source\r\n\r\nExact **source** 😀. [[Draft|writing]]{{Authored context.}}\r\n"
            let draft = identicalSources ? source : "# Draft\n\nIndependent writing.\n"
            var store: WorkspaceStore?
            do {
                for directory in [analyses, topics, works] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try Data(source.utf8).write(to: sourceFile)
                try Data(draft.utf8).write(to: draftFile)
                let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Search Navigation fixture")
                let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
                try await window.openWorkspaceVault(.output)
                window.documentController.rememberPresentationMode(.read)
                let sourceNote = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
                let draftNote = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Draft.md" })
                await window.openWorkspaceReference(draftNote.reference)
                await window.waitForPendingDocumentTransitionsForTesting()
                let range = try #require(DocumentPassageSnapshot.capture(source: source, range: (source as NSString).range(of: "Exact **source** 😀.")))
                let result = NoteSearchResult(
                    vaultID: sourceNote.reference.vaultID, vaultName: sourceNote.reference.vaultName, vaultRole: .sourceCorpus,
                    relativePath: "Source.md", stableNoteID: sourceNote.reference.stableNoteID,
                    title: "Source", matchedField: .body, context: nil, sourceLine: 3, snippet: "Exact source 😀.", highlights: [],
                    sourceRange: range.sourceRange, freshnessToken: .init("fixture"), fingerprint: .init(content: source),
                    evidentialLayer: .paperAnalysis, classification: .retrievalLead)
                return Fixture(
                    root: root, sourceFile: sourceFile, draftFile: draftFile, originalSource: Data(source.utf8), originalDraft: Data(draft.utf8),
                    store: created, window: window, result: result)
            } catch {
                await store?.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func shutdown() async {
            await Self.stop(window)
            await store.shutdownApplicationRuntime()
        }

        static func stop(_ window: WindowModel) async {
            window.libraryRevealTask?.cancel()
            window.documentTransitionCoordinator.cancelAll()
            await window.waitForPendingDocumentTransitionsForTesting()
            window.researchController.unbind()
            window.workspaceCancellables.removeAll()
            window.windowWorkspaceController.cancelAll()
            for tab in window.documentTabController.tabs {
                window.documentController.session(for: tab.document.editingTarget).cancelScheduledWork()
            }
        }
    }
}
