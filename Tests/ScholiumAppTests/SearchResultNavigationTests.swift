import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Search result source navigation", .serialized) @MainActor
struct SearchResultNavigationTests {
    @Test("Registered-file opening uses guarded new-tab departure and preserves retained input", arguments: [false, true])
    func registeredFileOpeningIsGuarded(composing: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            window.didRestoreWindowSession = true
            fixture.store.documentLocations.register(window)
            defer { fixture.store.documentLocations.unregister(window) }
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            let restore = try editSource("Retained unsaved input.", session: session, in: window)
            defer { restore() }
            setComposition(composing, on: session)
            try #require(session.editorSession.isComposing == composing)
            do {
                #expect(
                    try await fixture.store.documentLocations.openInExistingWindow(
                        fixture.reference, triptychID: try #require(window.workspaceAssignment?.id)))
                #expect(!composing)
                #expect(window.selectedDocumentPath == "Source.md")
                #expect(window.documentTabController.tabs.count == 2)
            } catch {
                #expect(composing)
                #expect(error as? DocumentControllerError == .editorUnavailable)
                #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
                #expect(window.documentTabController.tabs.count == 1)
            }
            setComposition(false, on: session)
            #expect(session.editingSource == "Retained unsaved input.")
            #expect(session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("New-tab completion terminates exactly once for rejected and superseded admission", arguments: [false, true])
    func newTabCompletionTerminates(blocked: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let gate = TransitionGate()
            defer {
                gate.release()
                window.transferInProgress = false
            }
            if blocked {
                window.transferInProgress = true
            } else {
                window.documentTransitionCoordinator.enqueue(
                    prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
            }
            var first: [Bool] = []
            var second: [Bool] = []
            window.openInNewTab(fixture.reference, onCompletion: { first.append((try? $0.get()) != nil) })
            window.openInNewTab(fixture.reference, onCompletion: { second.append((try? $0.get()) != nil) })
            gate.release()
            await window.waitForDocumentTransitions()
            #expect(first == [false])
            #expect(second == [!blocked])
            #expect(
                window.currentDocumentDescriptor?.sessionKey
                    == (blocked
                        ? origin.sessionKey
                        : fixture.result.stableNoteID.flatMap(UUID.init(uuidString:)).map { DocumentSessionKey(vaultID: fixture.result.vaultID, noteID: $0) }))
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("Quick Search keeps query/results when guarded departure or queued source admission fails", arguments: [false, true])
    func quickSearchWaitsForTerminalFailure(staleSource: Bool) async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            let restore = try editSource("Retained unsaved origin.", session: session, in: window)
            defer { restore() }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            let prepared = AsyncStream<Void>.makeStream()
            let controller = searchOpeningController(window: window, didValidate: { prepared.continuation.yield(()) })
            let state = SearchWorkspaceState(query: "source", scope: .triptych)
            controller.begin(.general)
            let request = window.discoveryController.beginSearch(state)
            let generation = try #require(try await window.discoveryController.discoverySnapshot().searchGeneration)
            window.discoveryController.receiveSearchResponse(
                .init(
                    requestID: request.id, scope: .triptych,
                    explanation: .init(provider: .note, providerWasExplicit: false, scope: .triptych, expression: .and([])),
                    freshnessToken: fixture.result.freshnessToken, availability: .current(generation),
                    results: [.note(fixture.result)], hasMore: false), for: request)
            let before = window.discoveryController.search
            let opening = Task { await controller.open(.result(.note(fixture.result)), disposition: .replaceCurrent) }
            for await _ in prepared.stream { break }
            if staleSource {
                try Data("Changed source before queued admission.\n".utf8).write(to: fixture.sourceFile)
            } else {
                session.activeSaveTask = Task { throw CocoaError(.fileWriteUnknown) }
            }
            gate.release()
            #expect(await opening.value == false)
            prepared.continuation.finish()
            session.activeSaveTask = nil
            #expect(controller.presentation == .sidebar)
            #expect(window.discoveryController.search == before)
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(session.editingSource == "Retained unsaved origin.")
            #expect(session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #expect(!window.shellState.operationIssues.isEmpty)
        }
    }

    @Test("History commits and restores only after a late peer selection succeeds", arguments: [false, true])
    func historyWaitsForLatePeerSelection(peerFails: Bool) async throws {
        try await withFixture { fixture in
            try await withPeer(of: fixture) { peer in
                let window = fixture.window
                let origin = try #require(window.documentController.selectedDocument)
                let originSession = window.documentController.session(for: origin.editingTarget)
                let key = DocumentSessionKey(
                    vaultID: fixture.result.vaultID, noteID: try #require(fixture.result.stableNoteID.flatMap(UUID.init(uuidString:))))
                let target = WindowSelectedDocument.workspace(.init(sessionKey: key, reference: fixture.reference))
                window.documentNavigationHistoryController.removeAll()
                window.documentNavigationHistoryController.record(target)
                window.documentNavigationHistoryController.captureCurrent(
                    document: target, position: .init(sourceFingerprint: fixture.result.fingerprint.sha256, scrollPosition: .init(fraction: 0.73)))
                window.documentNavigationHistoryController.record(origin)
                let gate = TransitionGate()
                defer {
                    gate.release()
                    originSession.detachmentResumeTask = nil
                }
                originSession.detachmentResumeTask = Task { await gate.wait() }
                window.navigateDocumentHistory(.back)
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
                try await peer.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
                let targetSession = peer.documentController.session(for: target.editingTarget)
                let other = WindowSelectedDocument.unavailable(vaultID: fixture.result.vaultID, relativePath: "Peer.md")
                peer.documentController.selectDocument(other)
                peer.documentTabController.activate(document: other, title: "Peer", toolTip: "Peer.md", placement: .newTab)
                let otherSession = peer.documentController.session(for: other.editingTarget)
                otherSession.editorSession.loadDocument("Peer source", documentID: otherSession.editorSession.bridgeDocumentID, mode: .livePreview)
                setComposition(peerFails, on: otherSession)
                gate.release()
                await window.waitForDocumentTransitions()
                await peer.waitForDocumentTransitions()
                #expect(window.documentController.selectedDocument == origin)
                #expect(window.documentNavigationHistoryController.currentDocument == (peerFails ? origin : target))
                #expect(window.documentNavigationHistoryController.canGoForward == !peerFails)
                #expect(peer.documentController.selectedDocument?.editingTarget == (peerFails ? other : target).editingTarget)
                if !peerFails { #expect(targetSession.readScrollPosition.fraction == 0.73) }
                setComposition(false, on: otherSession)
                #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
        }
    }

    private func setComposition(_ composing: Bool, on session: DocumentSessionModel) {
        let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
        session.editorSession.updateInteraction(
            selections: [selection], line: 1, column: 1, lineCount: 1,
            documentVersion: session.editorSession.generation, interactionRevision: 0, focusTarget: .editor,
            context: .init(
                selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                composing: composing, availableCommands: [], undoLabel: nil, redoLabel: nil))
    }

    private func searchOpeningController(window: WindowModel, didValidate: @escaping @MainActor () -> Void) -> WindowSearchController {
        WindowSearchController(
            discoveryController: window.discoveryController,
            dependencies: .init(
                loadSavedSearches: { [] }, saveSavedSearches: { _, _ in }, recoverSavedSearches: { nil },
                executionContext: { _ in .init(workspaceIsAvailable: false, currentNoteSnapshot: nil, currentVaultID: nil) },
                resultEvidence: { result, scope in
                    let evidence = await window.currentSearchResultEvidence(for: result, scope: scope)
                    didValidate()
                    return evidence
                },
                open: { result, disposition, isCurrent in await window.openSearchSelection(result, disposition: disposition, isCurrentRequest: isCurrent) },
                hasCurrentNote: { true }, reportInformation: { _ in }, reportLoadFailure: { _ in },
                reportSaveFailure: { _ in }, setAvailabilityStatus: { _ in }, reportCatalogFailure: { _ in }))
    }

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
            let restoreSource = try editSource("Unsaved draft must remain exact.", session: session, in: window)
            defer { restoreSource() }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            let opening = Task { await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent) }
            await Task.yield()
            let changed = Data("New first paragraph.\r\n\r\n".utf8) + fixture.originalSource
            if deleted { try FileManager.default.removeItem(at: fixture.sourceFile) } else { try changed.write(to: fixture.sourceFile) }
            gate.release()
            _ = await opening.value
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
                let restoreOrigin = try editSource(originText, session: originSession, in: window)
                defer { restoreOrigin() }
                let gate = TransitionGate()
                defer { gate.release() }
                window.documentTransitionCoordinator.enqueue(
                    prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
                let opening = Task { await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent) }
                await Task.yield()
                let peerReference = try #require(peer.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" }).reference
                try await peer.activateWorkspaceReference(peerReference, tabActivation: .place(.newTab))
                let destination = try #require(peer.currentDocumentDescriptor)
                let targetSession = peer.documentController.session(for: destination)
                targetSession.suppressAutosave = true
                let restoreTarget = try editSource(
                    dirty ? "Unsaved target must retain its position." : String(decoding: fixture.originalSource, as: UTF8.self),
                    session: targetSession, in: peer)
                defer { restoreTarget() }
                peer.documentController.requestSourceLocation(line: nil)
                gate.release()
                _ = await opening.value
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
            let restoreSource = try editSource(
                edited ? draft : String(decoding: fixture.originalDraft, as: UTF8.self), session: session, in: window)
            defer { restoreSource() }
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            let opening = Task { await window.openSearchSelection(.result(.note(fixture.result)), disposition: .replaceCurrent) }
            await Task.yield()
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
            _ = await opening.value
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
            let restoreSource = try editSource("Unsaved target shifts the source range.", session: session, in: window)
            defer { restoreSource() }
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
            let restoreSource = try editSource(
                dirty ? changed : String(decoding: fixture.originalSource, as: UTF8.self), session: session, in: window)
            if !dirty { try Data(changed.utf8).write(to: fixture.sourceFile) }
            defer { restoreSource() }
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

    private func editSource(_ source: String, session: DocumentSessionModel, in window: WindowModel) throws -> () -> Void {
        let snapshot = try #require(window.documentController.activeSnapshot)
        try #require(snapshot.stableIdentity.resolvedID == session.key?.noteID)
        guard !source.utf8.elementsEqual(snapshot.document.rawContent.utf8) else { return {} }
        let editor = session.editorSession
        // Managed editor input starts from the Note's checked citation identity,
        // including companion absence, and updates the exact-source mirror.
        let restore = {
            editor.loadDocument(
                snapshot.document.rawContent, documentID: editor.bridgeDocumentID,
                mode: session.retainedEditorMode, citationSnapshot: snapshot.document.citationSnapshot)
            session.editingSource = snapshot.document.rawContent
        }
        restore()
        try #require(
            editor.acceptEditorChanges(
                [
                    .init(
                        from: 0, to: EditorSourceOffsetMap(source: snapshot.document.rawContent).editorUTF16Length,
                        insert: source.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: source)
                ],
                baseGeneration: 0, resultingGeneration: 1, citationManaged: true,
                citationData: snapshot.document.citationSnapshot?.data))
        session.editingSource = source
        return restore
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
        var reference: VaultNoteReference {
            .init(
                vaultID: result.vaultID, vaultName: result.vaultName, vaultRole: result.vaultRole,
                relativePath: result.relativePath, stableNoteID: result.stableNoteID)
        }

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
                let generation = try #require(try await window.discoveryController.discoverySnapshot().searchGeneration)
                let result = NoteSearchResult(
                    vaultID: sourceNote.reference.vaultID, vaultName: sourceNote.reference.vaultName, vaultRole: .sourceCorpus,
                    relativePath: "Source.md", stableNoteID: sourceNote.reference.stableNoteID,
                    title: "Source", matchedField: .body, context: nil, sourceLine: 3, snippet: "Exact source 😀.", highlights: [],
                    sourceRange: range.sourceRange, freshnessToken: .triptych(generation), fingerprint: .init(content: source),
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
