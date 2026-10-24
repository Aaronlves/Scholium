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
                session.beginSaveAttempt(.init(task: Task { throw CocoaError(.fileWriteUnknown) }))
            }
            gate.release()
            #expect(await opening.value == false)
            prepared.continuation.finish()
            session.cancelSaveAttempt()
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

    @Test("Selecting the current tab supersedes a destination waiting for outgoing preparation")
    func currentTabSupersedesWaitingNavigation() async throws {
        try await withFixture { fixture in
            let window = fixture.window
            let origin = try #require(window.documentController.selectedDocument)
            let tabID = try #require(window.documentTabController.selectedTabID)
            let session = window.documentController.session(for: origin.editingTarget)
            let gate = TransitionGate()
            defer {
                gate.release()
                session.detachmentResumeTask = nil
            }
            session.detachmentResumeTask = Task { await gate.wait() }
            window.openInNewTab(fixture.reference)
            for _ in 0..<100 where !gate.started { await Task.yield() }
            try #require(gate.started)
            window.selectDocumentTab(withID: tabID)
            gate.release()
            await window.waitForDocumentTransitions()
            #expect(window.documentController.selectedDocument == origin)
            #expect(window.documentTabController.selectedTabID == tabID)
            #expect(window.documentTabController.tabs.count == 1)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("Opening a peer-owned Note supersedes an older local destination without changing the origin")
    func peerOpeningSupersedesWaitingLocalNavigation() async throws {
        try await withFixture { fixture in
            try await withPeer(of: fixture) { peer in
                let window = fixture.window
                try await peer.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
                let peerDocument = try #require(peer.documentController.selectedDocument)
                let origin = window.documentController.selectedDocument
                let gate = TransitionGate()
                defer { gate.release() }
                var oldDestinationInstalled = false
                window.enqueueDocumentTransition(
                    preparation: .operationOnly,
                    admitBeforePreparation: { await gate.wait() }
                ) { oldDestinationInstalled = true }
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
                window.requestOpenNote(fixture.reference)
                gate.release()
                await window.waitForDocumentTransitions()
                await peer.waitForDocumentTransitions()
                #expect(!oldDestinationInstalled)
                #expect(window.documentController.selectedDocument == origin)
                #expect(peer.documentController.selectedDocument == peerDocument)
                #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
        }
    }

    @Test("A new selection in either window revokes a pending peer history selection and its return position", arguments: [false, true])
    func localNavigationSupersedesPendingPeerHistory(peerOwnsNewSelection: Bool) async throws {
        try await withFixture { fixture in
            try await withPeer(of: fixture) { peer in
                let window = fixture.window
                let origin = try #require(window.documentController.selectedDocument)
                let originReference = try #require(origin.workspaceDescriptor?.reference)
                try await peer.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
                let target = try #require(peer.documentController.selectedDocument)
                let targetSession = peer.documentController.session(for: target.editingTarget)
                targetSession.observeScrollFraction(0.21, on: .read)
                window.documentNavigationHistoryController.removeAll()
                window.documentNavigationHistoryController.record(target)
                window.documentNavigationHistoryController.captureCurrent(
                    document: target,
                    position: .init(sourceFingerprint: fixture.result.fingerprint.sha256, scrollPosition: .init(fraction: 0.73)))
                window.documentNavigationHistoryController.record(origin)
                let other = WindowSelectedDocument.unavailable(vaultID: fixture.result.vaultID, relativePath: "Peer.md")
                peer.documentController.selectDocument(other)
                peer.documentTabController.activate(document: other, title: "Peer", toolTip: "Peer.md", placement: .newTab)
                let otherSession = peer.documentController.session(for: other.editingTarget)
                let gate = TransitionGate()
                defer {
                    gate.release()
                    otherSession.detachmentResumeTask = nil
                }
                otherSession.detachmentResumeTask = Task { await gate.wait() }
                window.navigateDocumentHistory(.back)
                for _ in 0..<100 where !gate.started { await Task.yield() }
                try #require(gate.started)
                if peerOwnsNewSelection {
                    peer.selectDocumentTab(withID: try #require(peer.documentTabController.selectedTabID))
                } else {
                    window.requestOpenNote(originReference)
                }
                await window.waitForDocumentTransitions()
                gate.release()
                await peer.waitForDocumentTransitions()
                #expect(window.documentController.selectedDocument == origin)
                #expect(window.documentNavigationHistoryController.currentDocument == origin)
                #expect(!window.documentNavigationHistoryController.canGoForward)
                #expect(peer.documentController.selectedDocument == other)
                #expect(targetSession.readScrollPosition.fraction == 0.21)
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

    @Test("A newly authored link resolves without a saved graph occurrence and preserves its retained dirty origin")
    func authoredUnsavedLinkWithoutGraphOccurrence() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let originSession = window.documentController.session(for: origin)
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let draft = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Draft.md" })
            try await window.activateWorkspaceReference(draft.reference, tabActivation: .place(.replaceSelected))
            originSession.suppressAutosave = true
            let changed = String(decoding: fixture.originalDraft, as: UTF8.self) + "\n[[Source#Source]]\n"
            let restore = try editSource(changed, session: originSession, in: window)
            defer { restore() }
            let mode = window.presentedDocumentMode
            await finishAuthoredLink(window.openInternalLink("Source#Source", from: "Draft.md"), in: window)
            #expect(window.selectedDocumentPath == "Source.md")
            #expect(window.documentController.sourceLocationRequest?.line == 1)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == fixture.result.fingerprint.sha256)
            #expect(window.presentedDocumentMode == mode)
            #expect(originSession.editingSource.utf8.elementsEqual(changed.utf8) && originSession.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("Authored fragment navigation never applies a saved line to a dirty retained target")
    func authoredDirtyDestinationDoesNotReceiveSavedLine() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let draftDescriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: draftDescriptor)
            session.suppressAutosave = true
            let changed = "Leading unsaved lines.\n\n" + String(decoding: fixture.originalDraft, as: UTF8.self)
            let restore = try editSource(changed, session: session, in: window)
            defer { restore() }
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            window.documentController.requestSourceLocation(line: nil)
            let mode = window.presentedDocumentMode
            await finishAuthoredLink(window.openInternalLink("Draft#Draft", from: "Source.md"), in: window)
            #expect(window.selectedDocumentPath == "Draft.md")
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains("could not be verified") == true)
            #expect(window.presentedDocumentMode == mode)
            #expect(session.editingSource.utf8.elementsEqual(changed.utf8) && session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("A queued authored fragment rejects changed canonical source before departure and permits refreshed retry")
    func authoredQueuedLocatorRevalidatesSource() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let origin = try #require(window.currentDocumentDescriptor)
            // Hold the exact captured catalog while canonical bytes change.
            // The owning hydration check, not a watcher refresh, must reject it.
            window.workspaceCancellables.removeAll()
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            try await waitForAuthoredBoundary { gate.started }
            let admission = window.openInternalLink("Draft#Draft", from: "Source.md")
            await admission?.value
            let changed = "New external prefix.\n\n" + String(decoding: fixture.originalDraft, as: UTF8.self)
            try Data(changed.utf8).write(to: fixture.draftFile)
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message == WorkspaceHydrationError.staleSnapshot.localizedDescription)
            #expect(try Data(contentsOf: fixture.draftFile) == Data(changed.utf8))
            try #require(await window.refreshAfterResearchHandoff() != nil)
            await finishAuthoredLink(window.openInternalLink("Draft#Draft", from: "Source.md"), in: window)
            #expect(window.selectedDocumentPath == "Draft.md")
            #expect(window.documentController.sourceLocationRequest?.line == 3)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == DocumentFingerprint(content: changed).sha256)
            #expect(try Data(contentsOf: fixture.draftFile) == Data(changed.utf8))
        }
    }

    @Test("A missing authored target retains the origin and permits an explicit retry after restoration")
    func authoredMissingDestinationAndRetry() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let origin = try #require(window.currentDocumentDescriptor)
            window.workspaceCancellables.removeAll()
            try FileManager.default.removeItem(at: fixture.draftFile)
            await finishAuthoredLink(window.openInternalLink("Draft#Draft", from: "Source.md"), in: window)
            try #require(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(!window.shellState.operationIssues.isEmpty)
            try fixture.originalDraft.write(to: fixture.draftFile)
            try #require(await window.refreshAfterResearchHandoff() != nil)
            await finishAuthoredLink(window.openInternalLink("Draft#Draft", from: "Source.md"), in: window)
            #expect(window.selectedDocumentPath == "Draft.md")
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("A later missing authored link supersedes a queued valid destination")
    func authoredMissingIntentSupersedesQueuedDestination() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let origin = try #require(window.currentDocumentDescriptor)
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            try await waitForAuthoredBoundary { gate.started }
            let admission = window.openInternalLink("Draft#Draft", from: "Source.md")
            await admission?.value
            window.openInternalLink("Actually Missing", from: "Source.md")
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains("broken") == true)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("Repeated fragment-only navigation keeps the same session, mode and exact source", arguments: [false, true])
    func authoredSameNoteFragment(dirty: Bool) async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let descriptor = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: descriptor)
            session.suppressAutosave = true
            let source = String(decoding: fixture.originalDraft, as: UTF8.self)
            let changed = dirty ? "Unsaved prefix.\n\n" + source : source
            let restore = try editSource(changed, session: session, in: window)
            defer { restore() }
            let mode = window.presentedDocumentMode
            for _ in 0..<2 {
                await finishAuthoredLink(window.openInternalLink("#Draft", from: "Draft.md"), in: window)
                #expect(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
                #expect(window.presentedDocumentMode == mode)
                if dirty {
                    #expect(window.documentController.sourceLocationRequest == nil)
                    #expect(window.shellState.operationIssues.last?.message.contains("could not be verified") == true)
                } else {
                    #expect(window.documentController.sourceLocationRequest?.line == 1)
                    #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == DocumentFingerprint(content: source).sha256)
                }
                #expect(session.editingSource.utf8.elementsEqual(changed.utf8))
                #expect(session.hasUnsavedChanges == dirty)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
        }
    }

    @Test(
        "An unavailable or ambiguous passage opens its unambiguous Note without claiming passage arrival",
        arguments: ["Missing", "^missing", "Repeated", "^repeated"])
    func authoredUnavailableFragmentFallback(fragment: String) async throws {
        let draft = "# Draft\n\n## Repeated\n\nFirst block. ^repeated\n\n## Repeated\n\nSecond block. ^repeated\n"
        try await withFixture(authoredLinks: true, authoredDraft: draft) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let mode = window.presentedDocumentMode
            await finishAuthoredLink(window.openInternalLink("Draft#" + fragment, from: "Source.md"), in: window)
            #expect(window.selectedDocumentPath == "Draft.md")
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains("could not be verified") == true)
            #expect(window.presentedDocumentMode == mode)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("Authored paths and heading fragments use one percent decoding at their existing semantic boundary")
    func authoredEncodedTargetAndHeading() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let folder = fixture.sourceFile.deletingLastPathComponent()
            let intended = folder.appendingPathComponent("Literal%20.md")
            let unintended = folder.appendingPathComponent("Literal .md")
            let source = "# S\n\n## 53\n\nExact destination.\n"
            try Data(source.utf8).write(to: intended)
            try Data("# S\n\nUnrelated Note.\n".utf8).write(to: unintended)
            try #require(await window.refreshAfterResearchHandoff() != nil)
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            await finishAuthoredLink(window.openInternalLink("Literal%2520#%2553", from: "Source.md"), in: window)
            #expect(window.selectedDocumentPath == "Literal%20.md")
            #expect(window.documentController.sourceLocationRequest?.line == 3)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == DocumentFingerprint(content: source).sha256)
            #expect(try Data(contentsOf: intended) == Data(source.utf8))
            #expect(try Data(contentsOf: unintended) == Data("# S\n\nUnrelated Note.\n".utf8))
        }
    }

    @Test("A direct authored link forwards the complete locator to its owning peer without saving the origin", arguments: [false, true])
    func authoredPeerDestination(dirty: Bool) async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let originSession = window.documentController.session(for: origin)
            originSession.suppressAutosave = true
            let changed = String(decoding: fixture.originalDraft, as: UTF8.self) + "\n[[Source#Source]]\n"
            let restoreOrigin = try editSource(changed, session: originSession, in: window)
            defer { restoreOrigin() }
            try await withPeer(of: fixture) { peer in
                try await peer.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
                let target = try #require(peer.currentDocumentDescriptor)
                let session = peer.documentController.session(for: target)
                session.suppressAutosave = true
                let source = String(decoding: fixture.originalSource, as: UTF8.self)
                let targetText = dirty ? "Unsaved target prefix.\n\n" + source : source
                let restoreTarget = try editSource(targetText, session: session, in: peer)
                defer { restoreTarget() }
                await finishAuthoredLink(window.openInternalLink("Source#Source", from: "Draft.md"), in: window, peer: peer)
                #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
                #expect(originSession.editingSource.utf8.elementsEqual(changed.utf8) && originSession.hasUnsavedChanges)
                #expect(peer.currentDocumentDescriptor?.sessionKey == target.sessionKey)
                if dirty {
                    #expect(peer.documentController.sourceLocationRequest == nil)
                    #expect(peer.shellState.operationIssues.last?.message.contains("could not be verified") == true)
                } else {
                    #expect(peer.documentController.sourceLocationRequest?.line == 1)
                    #expect(peer.documentController.sourceLocationRequest?.sourceFingerprint == fixture.result.fingerprint.sha256)
                }
                #expect(session.editingSource.utf8.elementsEqual(targetText.utf8) && session.hasUnsavedChanges == dirty)
                #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
        }
    }

    @Test("A peer acquiring a queued authored destination receives its locator before origin preparation", arguments: [false, true])
    func authoredQueuedPeerAcquisition(composing: Bool) async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            let changed = String(decoding: fixture.originalDraft, as: UTF8.self) + "\n[[Source#Source]]\n"
            let restore = try editSource(changed, session: session, in: window)
            defer { restore() }
            setComposition(composing, on: session)
            defer { setComposition(false, on: session) }
            try await withPeer(of: fixture) { peer in
                let gate = TransitionGate()
                defer { gate.release() }
                window.documentTransitionCoordinator.enqueue(
                    prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
                try await waitForAuthoredBoundary { gate.started }
                let admission = window.openInternalLink("Source#Source", from: "Draft.md")
                await admission?.value
                try await peer.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
                let target = try #require(peer.currentDocumentDescriptor)
                gate.release()
                await window.waitForPendingDocumentTransitionsForTesting()
                await peer.waitForPendingDocumentTransitionsForTesting()
                #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
                #expect(session.editingSource.utf8.elementsEqual(changed.utf8) && session.hasUnsavedChanges)
                #expect(session.editorSession.isComposing == composing)
                #expect(session.editError == nil && window.lastSaveError == nil)
                #expect(peer.currentDocumentDescriptor?.sessionKey == target.sessionKey)
                #expect(peer.documentController.sourceLocationRequest?.line == 1)
                #expect(peer.documentController.sourceLocationRequest?.sourceFingerprint == fixture.result.fingerprint.sha256)
                #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            }
        }
    }

    @Test("A queued authored target cannot capture a replacement at its former path")
    func authoredMovedTargetDoesNotReuseOldPath() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let gate = TransitionGate()
            defer { gate.release() }
            window.documentTransitionCoordinator.enqueue(
                prepare: { await gate.wait() }, operation: {}, didFail: { _ in Issue.record("Fixture queue failed") })
            try await waitForAuthoredBoundary { gate.started }
            let admission = window.openInternalLink("Source#Source", from: "Draft.md")
            await admission?.value
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let noteID = try #require(fixture.result.stableNoteID.flatMap(UUID.init(uuidString:)))
            let target = NoteMutationTarget(
                documentID: .init(vaultID: fixture.result.vaultID, relativePath: "Source.md"),
                stableNoteID: noteID, revision: fixture.result.fingerprint)
            _ = try await capabilities.libraryMutations.move(target, to: "Relocated.md")
            let replacement = Data("# Replacement\n\nDifferent Note.\n".utf8)
            try replacement.write(to: fixture.sourceFile)
            try #require(await window.refreshAfterResearchHandoff() != nil)
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(!window.shellState.operationIssues.isEmpty)
            #expect(try Data(contentsOf: fixture.sourceFile) == replacement)
            let moved = fixture.sourceFile.deletingLastPathComponent().appendingPathComponent("Relocated.md")
            #expect(try Data(contentsOf: moved) == fixture.originalSource)
            await finishAuthoredLink(window.openInternalLink("Relocated#Source", from: "Draft.md"), in: window)
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == noteID)
            #expect(window.selectedDocumentPath == "Relocated.md")
            #expect(window.documentController.sourceLocationRequest?.line == 1)
        }
    }

    @Test("A suspended source admission failure belongs only to its current navigation intent", arguments: [false, true])
    func supersededSourceAdmissionFailure(superseded: Bool) async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: origin)
            session.suppressAutosave = true
            let changed = String(decoding: fixture.originalDraft, as: UTF8.self) + "\nRetained unsaved input.\n"
            let restore = try editSource(changed, session: session, in: window)
            defer { restore() }
            let gate = TransitionGate()
            defer { gate.release() }
            await window.openWorkspaceReference(
                fixture.reference, sourceFingerprint: fixture.result.fingerprint,
                validateSource: {
                    await gate.wait()
                    throw WorkspaceHydrationError.staleSnapshot
                })
            try await waitForAuthoredBoundary { gate.started }
            if superseded {
                window.openInternalLink("Actually Missing", from: "Draft.md")
                #expect(window.shellState.operationIssues.last?.message.contains("broken") == true)
            }
            let issueCount = window.shellState.operationIssues.count
            gate.release()
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(session.editingSource.utf8.elementsEqual(changed.utf8) && session.hasUnsavedChanges)
            #expect(session.editError == nil && window.lastSaveError == nil)
            if superseded {
                #expect(window.shellState.operationIssues.count == issueCount)
                #expect(window.shellState.operationIssues.last?.message.contains("broken") == true)
            } else {
                #expect(window.shellState.operationIssues.count == issueCount + 1)
                #expect(window.shellState.operationIssues.last?.message == WorkspaceHydrationError.staleSnapshot.localizedDescription)
            }
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
        }
    }

    @Test("A new stable Note at a retained path cannot claim passage arrival in the former Note's session")
    func authoredReusedPathCannotCountAsCurrentIdentity() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let former = try #require(window.currentDocumentDescriptor)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            let formerNote = VaultQualifiedNoteID(vaultID: former.sessionKey.vaultID, relativePath: "Draft.md")
            let original = String(decoding: fixture.originalDraft, as: UTF8.self)
            // Model a lagging window observer receiving a valid newer provider
            // reference. Every identity and source below comes from real source
            // operations; the old Document remains independently retained.
            window.workspaceCancellables.removeAll()
            let target = NoteMutationTarget(
                documentID: formerNote, stableNoteID: former.sessionKey.noteID,
                revision: DocumentFingerprint(content: original))
            _ = try await capabilities.libraryMutations.move(target, to: "Former Draft.md")
            _ = try await capabilities.documents.importMarkdownSource(original, at: formerNote)
            let fresh = try await window.discoveryController.refreshWorkspace()
            let replacement = try #require(fresh.document(id: formerNote))
            let replacementID = try #require(replacement.stableIdentity.resolvedID)
            try #require(replacementID != former.sessionKey.noteID)
            try #require(replacement.fingerprint == DocumentFingerprint(content: original))
            try #require(window.currentDocumentDescriptor == former)
            let reference = VaultNoteReference(
                vaultID: former.reference.vaultID, vaultName: former.reference.vaultName,
                vaultRole: former.reference.vaultRole, relativePath: "Draft.md",
                stableNoteID: replacementID.uuidString.lowercased())
            window.documentController.requestSourceLocation(line: nil)
            await window.openWorkspaceReference(reference, line: 1, sourceFingerprint: replacement.fingerprint)
            await window.waitForPendingDocumentTransitionsForTesting()
            // The stale window cannot open the newer identity until its source
            // projection arrives. It must not count path+bytes as that identity.
            #expect(window.currentDocumentDescriptor?.sessionKey == former.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(!window.shellState.operationIssues.isEmpty)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            try #require(await window.refreshAfterResearchHandoff() != nil)
            await window.openWorkspaceReference(reference, line: 1, sourceFingerprint: replacement.fingerprint)
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == replacementID)
            #expect(window.selectedDocumentPath == "Draft.md")
            #expect(window.documentController.sourceLocationRequest?.line == 1)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == replacement.fingerprint.sha256)
            let moved = fixture.draftFile.deletingLastPathComponent().appendingPathComponent("Former Draft.md")
            #expect(try Data(contentsOf: moved) == fixture.originalDraft)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    @Test("An opening phase cannot admit direct links from an older complete graph and recovers on completion")
    func authoredLinkRequiresCompleteGeneration() async throws {
        try await withFixture(authoredLinks: true) { fixture in
            let window = fixture.window
            let origin = try #require(window.currentDocumentDescriptor)
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            window.workspaceCancellables.removeAll()
            let complete = try await window.discoveryController.refreshWorkspace()
            try #require(complete.discovery.catalog.graph != nil)
            // Retain the last complete graph deliberately: its presence alone
            // must not override the source cohort's explicit opening phase.
            let opening = WorkspaceSnapshot(
                triptych: complete.triptych, mode: complete.mode, phase: .opening,
                generatedAt: complete.generatedAt, vaults: complete.vaults,
                discovery: complete.discovery, research: complete.research,
                sourceInventoryRevision: complete.sourceInventoryRevision,
                documentChangesGeneration: complete.documentChangesGeneration)
            try #require(
                window.workspaceProjectionController.replaceSnapshot(
                    opening, runtimeIdentity: capabilities.runtimeIdentity,
                    status: .opening(.init(snapshot: opening)), context: window.workspaceProjectionContext) != nil)
            await finishAuthoredLink(window.openInternalLink("Source#Source", from: "Draft.md"), in: window)
            #expect(window.currentDocumentDescriptor?.sessionKey == origin.sessionKey)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.last?.message.contains("still refreshing") == true)
            // Completion publishes a newer source inventory cohort; replaying
            // the same cohort cannot replace the accepted opening projection.
            let completed = WorkspaceSnapshot(
                triptych: complete.triptych, mode: complete.mode, phase: .complete,
                generatedAt: complete.generatedAt, vaults: complete.vaults,
                discovery: complete.discovery, research: complete.research,
                sourceInventoryRevision: opening.sourceInventoryRevision + 1,
                documentChangesGeneration: complete.documentChangesGeneration)
            try #require(
                window.workspaceProjectionController.replaceSnapshot(
                    completed, runtimeIdentity: capabilities.runtimeIdentity,
                    status: .current(.init(snapshot: completed)), context: window.workspaceProjectionContext) != nil)
            try #require(window.workspaceProjectionController.snapshotPhase == .complete)
            await finishAuthoredLink(window.openInternalLink("Source#Source", from: "Draft.md"), in: window)
            #expect(window.selectedDocumentPath == "Source.md")
            #expect(window.documentController.sourceLocationRequest?.line == 1)
            #expect(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            #expect(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
        }
    }

    /// Model diagnostic: complete synchronous link admission and ordered
    /// navigation with two retained tabs. No native renderer, focus or paint.
    @Test(
        "Measure direct-link resolution and warm retained navigation across synthetic Triptychs",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DIRECT_LINKS"] == "1"),
        arguments: [500, 5_000])
    func authoredLinkPerformance(noteCount: Int) async throws {
        try await withFixture(authoredLinks: true, performanceNoteCount: noteCount) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let summaryCount = window.workspaceProjectionController.vaultSnapshotsByID.values.reduce(0) { $0 + $1.documents.count }
            try #require(summaryCount == noteCount)
            let mode = window.presentedDocumentMode
            let sourceFingerprint = DocumentFingerprint(content: String(decoding: fixture.originalSource, as: UTF8.self)).sha256
            let draftFingerprint = DocumentFingerprint(content: String(decoding: fixture.originalDraft, as: UTF8.self)).sha256
            var admissionMS: [Double] = []
            var completionMS: [Double] = []
            for ordinal in 0..<12 {
                let toDraft = ordinal.isMultiple(of: 2)
                let expectedPath = toDraft ? "Draft.md" : "Source.md"
                let from = toDraft ? "Source.md" : "Draft.md"
                let target = toDraft ? "Draft#Draft" : "Source#Source"
                window.documentController.requestSourceLocation(line: nil)
                let started = ContinuousClock.now
                let admission = window.openInternalLink(target, from: from)
                let admitted = ContinuousClock.now
                await finishAuthoredLink(admission, in: window)
                let completed = ContinuousClock.now
                try #require(window.selectedDocumentPath == expectedPath)
                try #require(window.documentController.sourceLocationRequest?.line == 1)
                try #require(window.documentController.sourceLocationRequest?.sourceFingerprint == (toDraft ? draftFingerprint : sourceFingerprint))
                try #require(window.presentedDocumentMode == mode)
                try #require(window.shellState.operationIssues.isEmpty)
                if ordinal >= 3 {
                    admissionMS.append(Self.directLinkMilliseconds(started.duration(to: admitted)))
                    completionMS.append(Self.directLinkMilliseconds(started.duration(to: completed)))
                }
            }
            try #require(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            try #require(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #if DEBUG
                let configuration = "debug"
            #else
                let configuration = "release"
            #endif
            for (name, values) in [("synchronous_admission", admissionMS), ("queue_completion", completionMS)] {
                let mean = values.reduce(0, +) / Double(values.count)
                let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
                let sorted = values.sorted()
                let payload: [String: Any] = [
                    "metric": name, "configuration": configuration, "notes": noteCount,
                    "warmups": 3, "samples": values.count, "unit": "ms",
                    "median": sorted[sorted.count / 2], "mean": mean,
                    "minimum": sorted.first!, "maximum": sorted.last!,
                    "standard_deviation": sqrt(variance), "values": values,
                    "native_paint_measured": false, "correctness": "target, fingerprint, mode, exact source unchanged",
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                print("DIRECT_LINK_PERF \(String(decoding: data, as: UTF8.self))")
            }
        }
    }

    private static func directLinkMilliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1_000_000_000_000_000
    }

    /// Model publication diagnostic. Cloning, public-link warmup, source
    /// hydration and correctness checks are outside the timed replacement.
    /// No native renderer, focus, paint or retained memory is measured.
    @Test(
        "Measure equal copied source-cohort publication after a warmed direct link",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_DIRECT_LINK_PUBLICATION"] == "1"),
        arguments: [500, 5_000])
    func authoredCopiedCohortPublicationPerformance(noteCount: Int) async throws {
        try await withFixture(authoredLinks: true, performanceNoteCount: noteCount) { fixture in
            let window = fixture.window
            try await window.activateWorkspaceReference(fixture.reference, tabActivation: .place(.newTab))
            let descriptor = try #require(window.currentDocumentDescriptor)
            let mode = window.presentedDocumentMode
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            // Freeze only this model window's event receiver. The source and
            // Application runtime are still real, isolated fixture owners.
            window.workspaceCancellables.removeAll()
            let frozen = try await window.discoveryController.refreshWorkspace()
            try #require(frozen.phase == .complete)
            try #require(frozen.vaults.reduce(0) { $0 + $1.documents.count } == noteCount)
            let fingerprint = DocumentFingerprint(content: String(decoding: fixture.originalSource, as: UTF8.self)).sha256
            var publicationMS: [Double] = []
            for ordinal in 0..<12 {
                // This public route works before and after resolver reuse; no
                // private cache accessor is needed to manufacture a warm state.
                await finishAuthoredLink(window.openInternalLink("#Source", from: "Source.md"), in: window)
                try #require(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
                try #require(window.documentController.sourceLocationRequest?.line == 1)
                try #require(window.documentController.sourceLocationRequest?.sourceFingerprint == fingerprint)
                let copiedVaults = try frozen.vaults.map { vault in
                    let copiedDocuments = vault.documents.map { $0 }
                    let prior = try #require(window.workspaceProjectionController.vaultSnapshot(id: vault.vault.id))
                    try #require(prior.documents == copiedDocuments)
                    if !copiedDocuments.isEmpty {
                        let storageIsDistinct = prior.documents.withUnsafeBufferPointer { old in
                            copiedDocuments.withUnsafeBufferPointer { copied in old.baseAddress != copied.baseAddress }
                        }
                        try #require(storageIsDistinct, "The diagnostic requires genuinely copied summary storage")
                    }
                    try #require(zip(prior.documents, copiedDocuments).allSatisfy { $0.hasSameSourceBinding(as: $1) })
                    return WorkspaceVaultSnapshot(
                        slot: vault.slot, vault: vault.vault, pathComparisonPolicy: vault.pathComparisonPolicy,
                        documents: copiedDocuments, folders: vault.folders, identityRecovery: vault.identityRecovery)
                }
                let publication = WorkspaceSnapshot(
                    triptych: frozen.triptych, mode: frozen.mode, phase: .complete,
                    generatedAt: frozen.generatedAt, vaults: copiedVaults,
                    discovery: frozen.discovery, research: frozen.research,
                    sourceInventoryRevision: frozen.sourceInventoryRevision + UInt64(ordinal) + 1,
                    documentChangesGeneration: frozen.documentChangesGeneration)
                try #require(window.workspaceProjectionController.advancesSourceInventory(publication))
                let context = window.workspaceProjectionContext
                let started = ContinuousClock.now
                let commit = window.workspaceProjectionController.replaceSnapshot(
                    publication, runtimeIdentity: capabilities.runtimeIdentity,
                    status: .current(.init(snapshot: publication)), context: context)
                let completed = ContinuousClock.now
                try #require(commit != nil)
                try #require(window.workspaceProjectionController.snapshotPhase == .complete)
                try #require(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
                try #require(window.presentedDocumentMode == mode)
                try #require(window.shellState.operationIssues.isEmpty)
                try #require(
                    window.workspaceProjectionController.cachedNote(
                        vaultID: fixture.result.vaultID, stableNoteID: descriptor.sessionKey.noteID,
                        relativePath: "Source.md")?.fingerprint == fixture.result.fingerprint)
                if ordinal >= 3 {
                    publicationMS.append(Self.directLinkMilliseconds(started.duration(to: completed)))
                }
            }
            // The final publication must also remain navigable with its exact
            // unchanged source binding, rather than only the prior warm state.
            await finishAuthoredLink(window.openInternalLink("#Source", from: "Source.md"), in: window)
            try #require(window.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey)
            try #require(window.documentController.sourceLocationRequest?.sourceFingerprint == fingerprint)
            try #require(try Data(contentsOf: fixture.sourceFile) == fixture.originalSource)
            try #require(try Data(contentsOf: fixture.draftFile) == fixture.originalDraft)
            #if DEBUG
                let configuration = "debug"
            #else
                let configuration = "release"
            #endif
            let mean = publicationMS.reduce(0, +) / Double(publicationMS.count)
            let variance = publicationMS.reduce(0) { $0 + pow($1 - mean, 2) } / Double(publicationMS.count)
            let sorted = publicationMS.sorted()
            let payload: [String: Any] = [
                "metric": "equal_copied_cohort_publication", "configuration": configuration, "notes": noteCount,
                "warmups": 3, "samples": publicationMS.count, "unit": "ms",
                "median": sorted[sorted.count / 2], "mean": mean,
                "minimum": sorted.first!, "maximum": sorted.last!, "standard_deviation": sqrt(variance), "values": publicationMS,
                "public_link_warmed_each_sample": true, "fresh_array_storage_verified": true,
                "strictly_newer_source_inventory": true, "native_paint_measured": false, "retained_memory_measured": false,
                "correctness": "equal summaries, exact binding, retained target/mode/fingerprint, unchanged disk bytes",
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print("DIRECT_LINK_PUBLICATION_PERF \(String(decoding: data, as: UTF8.self))")
        }
    }

    private func finishAuthoredLink(_ admission: Task<Void, Never>?, in window: WindowModel, peer: WindowModel? = nil) async {
        // Wait for actual queue admission before draining the owning queue. A
        // previous issue or the destination's old tab is not a completion signal.
        await admission?.value
        await window.waitForPendingDocumentTransitionsForTesting()
        await peer?.waitForPendingDocumentTransitionsForTesting()
    }

    private func waitForAuthoredBoundary(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(ready(), "The fixture transition gate did not start")
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

    private func withFixture(
        identicalSources: Bool = false, authoredLinks: Bool = false, authoredDraft: String? = nil, performanceNoteCount: Int = 2,
        _ body: (Fixture) async throws -> Void
    ) async throws {
        let fixture = try await Fixture.make(
            identicalSources: identicalSources, authoredLinks: authoredLinks, authoredDraft: authoredDraft, performanceNoteCount: performanceNoteCount)
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

        static func make(
            identicalSources: Bool = false, authoredLinks: Bool = false, authoredDraft: String? = nil, performanceNoteCount: Int = 2
        ) async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/feature-audit/research-workflow/fixtures/\(UUID())")
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            let sourceFile = analyses.appendingPathComponent("Source.md")
            let draftFile = works.appendingPathComponent("Draft.md")
            let source =
                "\u{FEFF}# Source\r\n\r\nExact **source** 😀. [[Draft|writing]]{{Authored context.}}\r\n" + (authoredLinks ? "\r\n[[Draft#Draft]]\r\n" : "")
            let draft = authoredDraft ?? (identicalSources ? source : "# Draft\n\nIndependent writing.\n")
            var store: WorkspaceStore?
            do {
                for directory in [analyses, topics, works] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try Data(source.utf8).write(to: sourceFile)
                try Data(draft.utf8).write(to: draftFile)
                if performanceNoteCount > 2 {
                    let destinations = [analyses, topics, works]
                    for ordinal in 0..<(performanceNoteCount - 2) {
                        let folder = destinations[ordinal % destinations.count].appendingPathComponent("Synthetic/Section\(ordinal / 300)")
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let paragraphs = (0..<8).map {
                            "Synthetic argument \(ordinal).\($0) compares conceptual evidence and interpretation. 中文研究语境 retains exact authored distinctions."
                        }.joined(separator: "\n\n")
                        let synthetic =
                            "---\ntitle: Synthetic argument \(ordinal)\naliases: [Synthetic alias \(ordinal), Context \(ordinal)]\nkeywords: [interpretation, evidence]\n---\n\n# Synthetic argument \(ordinal)\n\n\(paragraphs)\n\n## Discussion\n\n[[Source#Source]]{{Synthetic connection context.}}\n\nA source-owned claim. ^claim-\(ordinal)\n"
                        try Data(synthetic.utf8).write(to: folder.appendingPathComponent("Synthetic\(ordinal).md"))
                    }
                }
                let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Search Navigation fixture")
                let window = WindowModel(workspaceStore: created, requestedTriptychID: capabilities.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
                try await window.openWorkspaceVault(.output)
                window.documentController.rememberPresentationMode(authoredLinks ? .source : .read)
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
