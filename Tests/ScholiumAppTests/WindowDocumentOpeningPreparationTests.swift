import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Window document opening preparation", .serialized)
@MainActor
struct WindowDocumentOpeningPreparationTests {
    private enum FixtureFailure: LocalizedError {
        case save
        case capture
        case destination

        var errorDescription: String? {
            switch self {
            case .save: "Synthetic save acknowledgement failure."
            case .capture: "Synthetic editor capture failure."
            case .destination: "Synthetic destination failure."
            }
        }
    }

    @Test("A cross-role hydration failure retains the exact origin Library and document")
    func crossRoleHydrationFailurePreservesOrigin() async throws {
        let fixture = try await OpeningFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let window = fixture.window
            let origin = try #require(window.documentController.selectedDocument)
            let originVault = try #require(window.currentRegisteredVault)
            let originNotes = window.notes
            let originMode = window.presentedDocumentMode
            let reference = try #require(
                window.workspaceCatalog?.notes.first {
                    $0.reference.relativePath == "Destination.md"
                }?.reference)
            let target = fixture.analyses.appendingPathComponent("Destination.md")
            try Data([0xFF, 0xFE, 0x00]).write(to: target)
            do {
                try await window.activateWorkspaceReference(reference, tabActivation: .place(.replaceSelected))
                Issue.record("Unreadable destination unexpectedly opened")
            } catch {
                #expect(window.documentController.selectedDocument == origin)
                #expect(window.currentRegisteredVault?.id == originVault.id)
                #expect(window.shellState.selectedWorkspace == .output)
                #expect(window.discoveryController.library.workspaceSlot == .output)
                #expect(window.notes.map(\.relativePath) == originNotes.map(\.relativePath))
                #expect(window.presentedDocumentMode == originMode)
                #expect(window.documentTabController.selectedTab?.document == origin)
            }
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(OpeningFixture.source.utf8))
            try Data(OpeningFixture.source.utf8).write(to: target)
            _ = await window.refreshAfterResearchHandoff()
            try await window.activateWorkspaceReference(reference, tabActivation: .place(.replaceSelected))
            #expect(window.currentRegisteredVault?.id == reference.vaultID)
            #expect(window.shellState.selectedWorkspace == .paperAnalysis)
            #expect(window.documentController.selectedDocumentPath == "Destination.md")
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("Closing freezes late input through its final save and resumes after failure", arguments: [false, true])
    func closeOwnsInputThroughFinalSave(failsAcknowledgement: Bool) async throws {
        let fixture = try await OpeningFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let window = fixture.window
        let document = try #require(window.documentController.selectedDocument)
        let descriptor = try #require(document.workspaceDescriptor)
        let committedSnapshot = try #require(window.documentController.snapshots[descriptor.sessionKey])
        let dispatcher = CloseCommitDispatcher()
        let session = DocumentSessionModel(
            key: descriptor.sessionKey,
            editorSession: MarkdownEditorSession(bridgeDispatcher: dispatcher)
        )
        window.documentController.receiveSessionTransfer(
            .init(
                document: document, session: session,
                snapshot: committedSnapshot, mode: .source
            ))
        session.beginEditing(in: .source)
        session.originalEditingSource = OpeningFixture.source
        session.editingSource = OpeningFixture.source
        session.editingRevision = DocumentFingerprint(content: OpeningFixture.source)
        session.suppressAutosave = true
        let editor = MarkdownEditorWebViewIntegrationTests.EditorHarness(
            source: OpeningFixture.source, usesSessionDocumentIdentity: true,
            suppliedSession: session.editorSession,
            citationSnapshot: committedSnapshot.document.citationSnapshot, initialMode: .source
        )
        var release: CheckedContinuation<Void, Never>?
        defer {
            release?.resume()
            session.cancelScheduledWork()
            editor.close()
        }
        do {
            try await editor.waitUntilReady()
            // Fixture publications may reconcile the newly attached editor.
            // Finish that setup before testing departure's freeze ownership.
            await window.documentController.waitForPendingHydrations()
            try #require(try await session.editorSession.waitUntilLoadedForSave())
            try #require(session.editorSession.detachmentSuspensionID == nil)
            try await session.editorSession.perform(.pastePlain, argument: "Saved edit 中文 😀.\r\n")
            let saved = try await session.editorSession.currentText()
            let capabilities = try #require(window.windowWorkspaceController.activeCapabilities)
            var didPauseCommit = false
            window.documentController.bind(
                to: capabilities.documents,
                documentDidCommit: { _ in
                    if !didPauseCommit {
                        didPauseCommit = true
                        await withCheckedContinuation { release = $0 }
                    }
                })
            dispatcher.failNextCommit = failsAcknowledgement
            let tabID = try #require(window.documentTabController.selectedTabID)
            window.closeDocumentTab(withID: tabID)
            try await waitUntil { release != nil }
            do {
                try await session.editorSession.perform(.pastePlain, argument: "FORBIDDEN LATE INPUT")
                Issue.record("Closing accepted input after its final saved snapshot")
            } catch MarkdownEditorSession.SessionError.bridgeRejected {
                #expect(session.editorSession.checkedSource.utf8.elementsEqual(saved.utf8))
            }
            release?.resume()
            release = nil
            await window.waitForDocumentTransitions()
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(saved.utf8))
            if failsAcknowledgement {
                #expect(window.documentTabController.selectedTabID == tabID)
                #expect(window.documentController.selectedDocument == document)
                await session.detachmentResumeTask?.value
                try await session.editorSession.perform(.pastePlain, argument: "Resumed input")
                #expect(session.editorSession.checkedSource.contains("Resumed input"))
                #expect(!session.editorSession.checkedSource.contains("FORBIDDEN LATE INPUT"))
            } else {
                #expect(window.documentTabController.tabs.isEmpty)
                #expect(window.documentController.selectedDocument == nil)
            }
            await editor.closeAndDrain()
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            release?.resume()
            release = nil
            await window.waitForDocumentTransitions()
            await editor.closeAndDrain()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    private final class CloseCommitDispatcher: MarkdownEditorBridgeDispatching {
        var failNextCommit = false
        var failCaptureNumber: Int?
        var onNextCapture: (@MainActor () throws -> Void)?
        private(set) var captureCount = 0
        private let production = WKWebViewMarkdownEditorBridgeDispatcher()

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            if failNextCommit, case .acknowledgeCommittedSnapshot = request.operation {
                failNextCommit = false
                throw FixtureFailure.save
            }
            if case .suspendForDetachment = request.operation {
                captureCount += 1
                let result = try await production.dispatch(requestJSON: requestJSON, in: webView)
                let onCapture = onNextCapture
                onNextCapture = nil
                try onCapture?()
                if captureCount == failCaptureNumber {
                    // The input freeze succeeded but its reply was lost. The
                    // ordinary failure path must retain and resume this Note.
                    throw FixtureFailure.capture
                }
                return result
            }
            return try await production.dispatch(requestJSON: requestJSON, in: webView)
        }
    }

    enum DepartureFailure: CaseIterable { case initialCapture, saveAcknowledgement, finalCapture, saveConflict }

    @Test("Replacement distinguishes a failed save from capture before or after a successful commit", arguments: DepartureFailure.allCases)
    func replacementFailureDescribesItsActualStage(failure: DepartureFailure) async throws {
        let fixture = try await OpeningFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let window = fixture.window
        let document = try #require(window.documentController.selectedDocument)
        let descriptor = try #require(document.workspaceDescriptor)
        let committedSnapshot = try #require(window.documentController.snapshots[descriptor.sessionKey])
        let dispatcher = CloseCommitDispatcher()
        let session = DocumentSessionModel(
            key: descriptor.sessionKey,
            editorSession: MarkdownEditorSession(bridgeDispatcher: dispatcher))
        window.documentController.receiveSessionTransfer(
            .init(
                document: document, session: session,
                snapshot: committedSnapshot, mode: .source))
        session.beginEditing(in: .source)
        session.originalEditingSource = OpeningFixture.source
        session.editingSource = OpeningFixture.source
        session.editingRevision = DocumentFingerprint(content: OpeningFixture.source)
        session.suppressAutosave = true
        let editor = MarkdownEditorWebViewIntegrationTests.EditorHarness(
            source: OpeningFixture.source, usesSessionDocumentIdentity: true,
            suppliedSession: session.editorSession,
            citationSnapshot: committedSnapshot.document.citationSnapshot, initialMode: .source)
        defer {
            session.cancelScheduledWork()
            editor.close()
        }
        do {
            try await editor.waitUntilReady()
            await window.documentController.waitForPendingHydrations()
            try #require(try await session.editorSession.waitUntilLoadedForSave())
            try #require(session.editorSession.detachmentSuspensionID == nil)
            try await session.editorSession.perform(.pastePlain, argument: "Retained draft 中文 😀.\r\n")
            let exactDraft = try await session.editorSession.currentText()
            let externalSource = "External source 中文 😀.\r\n"
            // Fault stages belong to this departure, after fixture reconciliation.
            let initialCaptureCount = dispatcher.captureCount
            switch failure {
            case .initialCapture: dispatcher.failCaptureNumber = initialCaptureCount + 1
            case .saveAcknowledgement: dispatcher.failNextCommit = true
            case .finalCapture: dispatcher.failCaptureNumber = initialCaptureCount + 2
            case .saveConflict:
                dispatcher.onNextCapture = {
                    try Data(externalSource.utf8).write(to: fixture.works.appendingPathComponent("Origin.md"))
                }
            }
            var reachedDestination = false
            window.enqueueDocumentTransition { reachedDestination = true }
            await window.waitForDocumentTransitions()
            await session.detachmentResumeTask?.value
            #expect(!reachedDestination)
            #expect(window.documentController.selectedDocument == document)
            #expect(window.documentTabController.selectedTab?.document == document)
            #expect(Data(session.editorSession.checkedSource.utf8) == Data(exactDraft.utf8))
            let expectedDisk =
                switch failure {
                case .initialCapture: OpeningFixture.source
                case .saveConflict: externalSource
                case .saveAcknowledgement, .finalCapture: exactDraft
                }
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(expectedDisk.utf8))
            let issue = try #require(window.shellState.operationIssues.last)
            if failure == .saveConflict {
                #expect(window.lastSaveError != nil)
                #expect(!session.canRetrySave)
                #expect(issue.message.contains("could not be saved"))
                let conflict = try #require(session.conflict)
                #expect(Data(conflict.editorSource.utf8) == Data(exactDraft.utf8))
                #expect(Data(conflict.diskSource.utf8) == Data(externalSource.utf8))
                #expect(session.hasUnsavedChanges)
            } else {
                #expect(window.lastSaveError == nil)
                #expect(!session.canRetrySave)
                #expect(issue.message.contains("could not leave the current note"))
                #expect(!issue.message.contains("could not be saved"))
                let expectedFailure = failure == .saveAcknowledgement ? FixtureFailure.save : .capture
                #expect(issue.message.contains(expectedFailure.localizedDescription))
            }
            if failure == .saveAcknowledgement || failure == .finalCapture {
                #expect(session.originalEditingSource.utf8.elementsEqual(exactDraft.utf8))
                #expect(session.pendingEditorCommit == nil)
            }
            if failure == .finalCapture { #expect(dispatcher.captureCount == initialCaptureCount + 2) }
            await editor.closeAndDrain()
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            await window.waitForDocumentTransitions()
            await editor.closeAndDrain()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("Destination failures retain their own meaning after departure succeeds", arguments: [false, true])
    func destinationFailureIsNotReportedAsSaveFailure(currencyAware: Bool) async throws {
        let (model, background, outgoing) = makeModel()
        defer {
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        let document = model.documentController.selectedDocument
        if currencyAware {
            model.enqueueDocumentTransition(preparation: .flushRegisteredEditor(capturingEditorState: true)) { _ in throw FixtureFailure.destination }
        } else {
            model.enqueueDocumentTransition { throw FixtureFailure.destination }
        }
        await model.waitForDocumentTransitions()
        #expect(model.documentController.selectedDocument == document)
        #expect(model.lastSaveError == nil)
        #expect(!outgoing.hasUnsavedChanges)
        #expect(!outgoing.canRetrySave)
        #expect(model.shellState.operationIssues.last?.message == FixtureFailure.destination.localizedDescription)
    }

    @Test("A retained-document failure never reveals a same-path Note in an independently browsed Library")
    func failureRevealDoesNotTargetBrowsedTwin() async throws {
        let fixture = try await OpeningFixture.make(includeSameNamedAnalysis: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            let window = fixture.window
            let document = try #require(window.documentController.selectedDocument)
            let analysis = try #require(window.workspaceAssignment?.vault(for: .paperAnalysis))
            await window.libraryRevealTask?.value
            try await window.prepareWorkspaceSelection(.paperAnalysis, sourceScope: .library)
            try #require(window.documentController.selectedDocument == document)
            try #require(window.currentRegisteredVault?.id == analysis.id)
            try #require(window.discoveryController.library.workspaceSlot == .paperAnalysis)
            try #require(window.notes.contains { $0.relativePath == document.relativePath })
            if let previous = window.discoveryController.libraryRevealRequest {
                window.discoveryController.consumeLibraryRevealRequest(previous)
            }
            let selection = window.discoveryController.library.selectedRowIDs
            window.enqueueDocumentTransition(preparation: .operationOnly) { throw FixtureFailure.destination }
            await window.waitForDocumentTransitions()

            #expect(window.documentController.selectedDocument == document)
            #expect(window.currentRegisteredVault?.id == analysis.id)
            #expect(window.discoveryController.library.selectedRowIDs == selection)
            #expect(
                window.discoveryController.libraryRevealRequest == nil, "The retained Works Note cannot reveal its Analyses twin or leave an off-scope reveal")
            #expect(window.shellState.operationIssues.last?.message == FixtureFailure.destination.localizedDescription)
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(OpeningFixture.source.utf8))
            #expect(try Data(contentsOf: fixture.analyses.appendingPathComponent("Origin.md")) == Data(OpeningFixture.source.utf8))
            window.windowCloseCoordinator.finalize()
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            fixture.window.documentTransitionCoordinator.cancelAll()
            fixture.window.windowCloseCoordinator.finalize()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    enum DestinationFailureCurrency: CaseIterable, Equatable, Sendable {
        case current, superseded, closed
    }

    @Test(
        "Only a current destination failure may publish its banner and retained-document reveal",
        .timeLimit(.minutes(1)), arguments: DestinationFailureCurrency.allCases)
    func destinationFailurePresentationRespectsCurrency(currency: DestinationFailureCurrency) async throws {
        let fixture = try await OpeningFixture.make()
        let arrival = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        defer {
            release?.resume()
            arrival.continuation.finish()
            fixture.window.documentTransitionCoordinator.cancelAll()
            fixture.window.windowCloseCoordinator.finalize()
            try? FileManager.default.removeItem(at: fixture.root)
        }
        do {
            let window = fixture.window
            let document = try #require(window.documentController.selectedDocument)
            var completionFailure: Error?
            var finishCount = 0
            window.enqueueDocumentTransition(
                preparation: .operationOnly,
                {
                    // This destination intentionally finishes with its own
                    // error after cancellation instead of throwing CancellationError.
                    await withCheckedContinuation {
                        release = $0
                        arrival.continuation.yield(())
                    }
                    throw FixtureFailure.destination
                },
                didFinish: {
                    finishCount += 1
                    arrival.continuation.finish()
                },
                completion: {
                    if case .failure(let error) = $0 { completionFailure = error }
                })
            for await _ in arrival.stream { break }
            try #require(release != nil)
            // Successful opening owns a separate queued Library reveal. Join
            // that owner and retain its exact request as the admitted baseline.
            await window.libraryRevealTask?.value
            let previousReveal = window.discoveryController.libraryRevealRequest
            let previousIssues = window.shellState.operationIssues
            switch currency {
            case .current: break
            case .superseded: try #require(window.beginDocumentNavigation() != nil)
            case .closed: window.windowCloseCoordinator.finalize()
            }
            release?.resume()
            release = nil
            await window.waitForDocumentTransitions()

            #expect(finishCount == 1)
            let failure = try #require(completionFailure as? FixtureFailure)
            if case .destination = failure {} else { Issue.record("The destination's actual result was discarded") }
            #expect(window.documentController.selectedDocument == document)
            #expect(window.lastSaveError == nil)
            if currency == .current {
                #expect(window.shellState.operationIssues.last?.message == FixtureFailure.destination.localizedDescription)
                #expect(window.discoveryController.libraryRevealRequest?.scope.vaultID == document.vaultID)
                #expect(window.discoveryController.libraryRevealRequest?.relativePath == document.relativePath)
                #expect(window.discoveryController.libraryRevealRequest != previousReveal)
            } else {
                #expect(window.shellState.operationIssues == previousIssues, "An obsolete destination added a stale issue")
                #expect(window.discoveryController.libraryRevealRequest == previousReveal, "An obsolete destination changed the admitted Library reveal")
            }
            #expect(try Data(contentsOf: fixture.works.appendingPathComponent("Origin.md")) == Data(OpeningFixture.source.utf8))
            window.windowCloseCoordinator.finalize()
            await fixture.store.shutdownApplicationRuntime()
        } catch {
            release?.resume()
            release = nil
            fixture.window.documentTransitionCoordinator.cancelAll()
            await fixture.window.waitForDocumentTransitions()
            fixture.window.windowCloseCoordinator.finalize()
            await fixture.store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test(
        "Revoking presentation preserves custom failure receipts and retained source",
        .timeLimit(.minutes(1)), arguments: [DestinationFailureCurrency.superseded, .closed])
    func revokedPresentationStillDeliversCustomFailure(currency: DestinationFailureCurrency) async throws {
        let (model, background, outgoing) = makeModel()
        let arrival = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Void, Never>?
        let draft = "\u{FEFF}Retained researcher source 中文 😀 e\u{301}。\r\n"
        outgoing.beginEditing(in: .source)
        outgoing.editingSource = draft
        outgoing.suppressAutosave = true
        defer {
            release?.resume()
            arrival.continuation.finish()
            model.documentTransitionCoordinator.cancelAll()
            model.windowCloseCoordinator.finalize()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var receivedFailure: Error?
        var completedFailure: Error?
        var finishCount = 0
        model.enqueueDocumentTransition(
            preparation: .operationOnly,
            {
                await withCheckedContinuation {
                    release = $0
                    arrival.continuation.yield(())
                }
                throw FixtureFailure.destination
            },
            didFail: { receivedFailure = $0 },
            didFinish: {
                finishCount += 1
                arrival.continuation.finish()
            },
            completion: { if case .failure(let error) = $0 { completedFailure = error } })
        for await _ in arrival.stream { break }
        try #require(release != nil)
        switch currency {
        case .current: Issue.record("This case must revoke presentation")
        case .superseded:
            for _ in 0..<16 { try #require(model.beginDocumentNavigation() != nil) }
        case .closed: model.windowCloseCoordinator.finalize()
        }
        release?.resume()
        release = nil
        await model.waitForDocumentTransitions()
        #expect(receivedFailure?.localizedDescription == FixtureFailure.destination.localizedDescription)
        #expect(completedFailure?.localizedDescription == FixtureFailure.destination.localizedDescription)
        #expect(finishCount == 1)
        #expect(model.shellState.operationIssues.isEmpty)
        #expect(model.discoveryController.libraryRevealRequest == nil)
        #expect(Data(outgoing.editingSource.utf8) == Data(draft.utf8) && outgoing.hasUnsavedChanges)
    }

    @Test("A registered editor capture failure after flushing retains the Note without declaring a failed save")
    func registeredCaptureFailureDoesNotInventSaveFailure() async throws {
        let (model, background, outgoing) = makeModel()
        let document = model.documentController.selectedDocument
        var flushCount = 0
        model.registerEditorFlush(
            for: try #require(model.selectedDocumentPath), token: UUID(),
            flush: { flushCount += 1 },
            captureForReconstruction: { throw FixtureFailure.capture })
        defer {
            model.editorFlushCoordinator.clearCurrentEditor()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var reachedDestination = false
        model.enqueueDocumentTransition(preparation: .flushRegisteredEditor(capturingEditorState: true)) { _ in reachedDestination = true }
        await model.waitForDocumentTransitions()
        #expect(flushCount == 1)
        #expect(!reachedDestination)
        #expect(model.documentController.selectedDocument == document)
        #expect(model.lastSaveError == nil)
        #expect(!outgoing.canRetrySave)
        let issue = try #require(model.shellState.operationIssues.last)
        #expect(issue.message.contains(FixtureFailure.capture.localizedDescription))
        #expect(!issue.message.contains("could not be saved"))
    }

    enum RejectedTransitionState: Sendable, Equatable {
        case transfer, preparingClose, preparedClose, finalizedClose
    }

    @Test(
        "Rejected navigation settles once without changing retained documents",
        arguments: [RejectedTransitionState.transfer, .preparingClose, .preparedClose, .finalizedClose]
    )
    func rejectedTransitionsFinishImmediately(state: RejectedTransitionState) async throws {
        let (model, background, outgoing) = makeModel()
        let document = model.documentController.selectedDocument
        let tabs = model.documentTabController.tabs.map(\.id)
        let sources = [background.editingSource, outgoing.editingSource].map { Data($0.utf8) }
        let gate = AsyncStream<Void>.makeStream()
        var flushStarted = false
        var closeTask: Task<WindowClosePreparationOutcome, Error>?
        defer {
            gate.continuation.finish()
            closeTask?.cancel()
            model.windowCloseCoordinator.cancelPreparation()
            model.editorFlushCoordinator.clearCurrentEditor()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        do {
            switch state {
            case .transfer:
                model.transferInProgress = true
            case .preparingClose:
                model.registerEditorFlush(
                    for: try #require(model.selectedDocumentPath), token: UUID(),
                    flush: {
                        flushStarted = true
                        for await _ in gate.stream { break }
                    }, captureForReconstruction: {})
                closeTask = Task { try await model.windowCloseCoordinator.prepare() }
                let deadline = ContinuousClock.now.advanced(by: .seconds(2))
                while !flushStarted {
                    try #require(ContinuousClock.now < deadline, "Close preparation did not reach the registered flush")
                    try await Task.sleep(for: .milliseconds(1))
                }
            case .preparedClose, .finalizedClose:
                _ = try await model.windowCloseCoordinator.prepare()
                if state == .finalizedClose { model.windowCloseCoordinator.finalize() }
            }

            var ordinaryFinishes = 0
            var completions = 0
            var currencyFinishes = 0
            var preparationCount = 0
            var operationCount = 0
            var successes = 0
            model.enqueueDocumentTransition(
                preparation: .operationOnly,
                validateBeforePreparation: { preparationCount += 1 },
                { operationCount += 1 },
                didSucceed: { successes += 1 },
                didFinish: { ordinaryFinishes += 1 },
                completion: { result in
                    completions += 1
                    if case .success = result { Issue.record("Rejected navigation reported success") }
                })
            model.enqueueDocumentTransition(
                preparation: .flushRegisteredEditor(capturingEditorState: true),
                validateBeforePreparation: { preparationCount += 1 },
                { _ in operationCount += 1 },
                didSucceed: { successes += 1 },
                didFinish: { currencyFinishes += 1 })
            #expect(ordinaryFinishes == 1 && completions == 1)
            #expect(currencyFinishes == 1)
            await model.waitForDocumentTransitions()
            #expect(ordinaryFinishes == 1 && completions == 1 && currencyFinishes == 1)
            #expect(preparationCount == 0 && operationCount == 0 && successes == 0)
            let issueIDs = model.shellState.operationIssues.map(\.id)
            model.libraryMutationController.requestUntitledNoteCreation(in: nil)
            #expect(!model.libraryMutationController.isCreatingNote)
            await model.waitForDocumentTransitions()
            #expect(!model.libraryMutationController.isCreatingNote)
            #expect(model.shellState.operationIssues.map(\.id) == issueIDs)
            #expect(model.documentController.selectedDocument == document)
            #expect(model.documentTabController.tabs.map(\.id) == tabs)
            #expect([background.editingSource, outgoing.editingSource].map { Data($0.utf8) } == sources)

            if state != .finalizedClose {
                model.transferInProgress = false
                model.windowCloseCoordinator.cancelPreparation()
                gate.continuation.finish()
                if let closeTask { _ = try? await closeTask.value }
                model.editorFlushCoordinator.clearCurrentEditor()
                var resumed = 0
                model.enqueueDocumentTransition(preparation: .flushRegisteredEditor(capturingEditorState: true), { _ in resumed += 1 })
                await model.waitForDocumentTransitions()
                #expect(resumed == 1)
            }
        } catch {
            gate.continuation.finish()
            closeTask?.cancel()
            model.windowCloseCoordinator.cancelPreparation()
            if let closeTask { _ = try? await closeTask.value }
            throw error
        }
    }

    @Test("Close drains navigation admitted before its preparation begins")
    func closeDrainsAlreadyAdmittedNavigation() async throws {
        let (model, background, outgoing) = makeModel()
        let gate = AsyncStream<Void>.makeStream()
        var operationStarted = false
        var finishes = 0
        var closeTask: Task<WindowClosePreparationOutcome, Error>?
        defer {
            gate.continuation.finish()
            closeTask?.cancel()
            model.windowCloseCoordinator.cancelPreparation()
            model.documentTransitionCoordinator.cancelAll()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        do {
            model.enqueueDocumentTransition(
                preparation: .flushRegisteredEditor(capturingEditorState: true),
                { isCurrent in
                    operationStarted = true
                    for await _ in gate.stream { break }
                    #expect(isCurrent())
                }, didFinish: { finishes += 1 })
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !operationStarted {
                try #require(ContinuousClock.now < deadline, "Navigation did not start")
                try await Task.sleep(for: .milliseconds(1))
            }
            closeTask = Task { try await model.windowCloseCoordinator.prepare() }
            while !model.windowCloseCoordinator.isPreparingOrFinalized {
                try #require(ContinuousClock.now < deadline, "Close preparation did not start")
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(finishes == 0 && !model.windowCloseCoordinator.isPrepared)
            gate.continuation.finish()
            _ = try await closeTask?.value
            await model.waitForDocumentTransitions()
            #expect(finishes == 1 && model.windowCloseCoordinator.isPrepared)
        } catch {
            gate.continuation.finish()
            closeTask?.cancel()
            model.windowCloseCoordinator.cancelPreparation()
            model.documentTransitionCoordinator.cancelAll()
            await model.waitForDocumentTransitions()
            if let closeTask { _ = try? await closeTask.value }
            throw error
        }
    }

    @MainActor
    private struct OpeningFixture {
        static let source = "\u{FEFF}Exact source 中文 😀 e\u{301}。\r\n"
        let root: URL
        let analyses: URL
        let works: URL
        let store: WorkspaceStore
        let window: WindowModel

        static func make(includeSameNamedAnalysis: Bool = false) async throws -> Self {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/feature-review/core-fixtures/\(UUID())")
            let triptych = root.appendingPathComponent("Triptych")
            let analyses = triptych.appendingPathComponent("Analyses")
            let topics = triptych.appendingPathComponent("Topics")
            let works = triptych.appendingPathComponent("Works")
            for directory in [analyses, topics, works] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try Data(source.utf8).write(to: analyses.appendingPathComponent("Destination.md"))
            try Data(source.utf8).write(to: works.appendingPathComponent("Origin.md"))
            if includeSameNamedAnalysis {
                try Data(source.utf8).write(to: analyses.appendingPathComponent("Origin.md"))
            }
            let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
            do {
                let configured = try await store.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Opening Fixture")
                let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
                await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
                try await window.openWorkspaceVault(.output)
                window.documentController.rememberPresentationMode(.read)
                try await window.openNote("Origin.md")
                return Self(root: root, analyses: analyses, works: works, store: store, window: window)
            } catch {
                await store.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }

    @Test("Replacement guards its outgoing source without joining an unrelated retained save", arguments: [false, true])
    func replacementSaveIsTargetLocal(failsOutgoing: Bool) async throws {
        let (model, background, outgoing) = makeModel()
        let failing = failsOutgoing ? outgoing : background
        failing.beginEditing(in: .source)
        failing.originalEditingSource = "Saved\r\n"
        let exactDraft = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        failing.editingSource = exactDraft
        failing.suppressAutosave = true
        let save = Task<EditorSaveOutcome, Error> { throw FixtureFailure.save }
        failing.beginSaveAttempt(.init(task: save))
        defer {
            save.cancel()
            failing.cancelSaveAttempt()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        let selectedAtStart = model.documentController.selectedDocument
        var reachedDestination = false
        model.enqueueDocumentTransition {
            reachedDestination = true
        }
        await model.waitForDocumentTransitions()
        #expect(reachedDestination == !failsOutgoing)
        #expect(model.documentController.selectedDocument == selectedAtStart)
        #expect(Data(failing.editingSource.utf8) == Data(exactDraft.utf8))
        #expect(model.documentTabController.tabs.count == 2)
    }

    @Test("Opening a new or retained tab preserves the outgoing dirty session without saving", arguments: [DocumentTabPlacement.newTab, .replaceSelected])
    func retainedOpeningDoesNotSaveOutgoing(placement: DocumentTabPlacement) async throws {
        let (model, background, outgoing) = makeModel()
        let reference = try #require(model.documentTabController.tabs.first?.document.workspaceDescriptor?.reference)
        outgoing.beginEditing(in: .source)
        outgoing.originalEditingSource = "Saved\r\n"
        let draft = "\u{FEFF}Uncommitted 中文 😀。\r\n"
        outgoing.editingSource = draft
        outgoing.editError = "Retained failure"
        outgoing.canRetrySave = true
        outgoing.suppressAutosave = true
        outgoing.scrollFraction = 0.62
        defer {
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var reachedDestination = false
        model.enqueueDocumentTransition(preparation: model.openingPreparation(for: reference, placement: placement)) {
            reachedDestination = true
        }
        await model.waitForDocumentTransitions()
        #expect(reachedDestination)
        #expect(Data(outgoing.editingSource.utf8) == Data(draft.utf8))
        #expect(outgoing.hasUnsavedChanges)
        #expect(outgoing.editError == "Retained failure")
        #expect(outgoing.scrollFraction == 0.62)
        #expect(outgoing.activeSaveAttempt == nil)
    }

    @Test("A destination removed before queued opening preparation requires an outgoing save")
    func queuedDestinationLossRequiresSave() async throws {
        let (model, background, outgoing) = makeModel()
        let tab = try #require(model.documentTabController.tabs.first)
        let reference = try #require(tab.document.workspaceDescriptor?.reference)
        let save = installFailedSave(on: outgoing)
        var release: CheckedContinuation<Void, Never>?
        defer {
            release?.resume()
            save.cancel()
            outgoing.cancelSaveAttempt()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        model.documentTransitionCoordinator.enqueueCleanup { _ in
            await withCheckedContinuation { release = $0 }
            model.documentTabController.removeTabs(withIDs: [tab.id])
        }
        try await waitUntil { release != nil }
        var reachedDestination = false
        model.enqueueDocumentTransition(preparation: model.openingPreparation(for: reference)) {
            reachedDestination = true
        }
        release?.resume()
        release = nil
        await model.waitForDocumentTransitions()
        #expect(!reachedDestination)
        #expect(model.documentController.selectedDocument == model.documentTabController.selectedTab?.document)
        #expect(outgoing.hasUnsavedChanges)
    }

    @Test("A retained destination lost during preparation leaves its outgoing dirty session open")
    func destinationLossDuringPreparationPreservesOrigin() async throws {
        let (model, background, outgoing) = makeModel()
        let tab = try #require(model.documentTabController.tabs.first)
        let reference = try #require(tab.document.workspaceDescriptor?.reference)
        outgoing.beginEditing(in: .source)
        outgoing.originalEditingSource = "Saved\r\n"
        outgoing.editingSource = "Unsaved 中文 😀。\r\n"
        outgoing.suppressAutosave = true
        var release: CheckedContinuation<Void, Never>?
        let inFlight = Task<EditorSaveOutcome, Error> {
            await withCheckedContinuation { release = $0 }
            return .clean
        }
        outgoing.beginSaveAttempt(.init(task: inFlight))
        var failedSave: Task<EditorSaveOutcome, Error>?
        defer {
            release?.resume()
            inFlight.cancel()
            failedSave?.cancel()
            outgoing.cancelSaveAttempt()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var reachedDestination = false
        var beganPreparation = false
        model.enqueueDocumentTransition(
            preparation: .openingDocument(
                placement: .replaceSelected,
                retainedTab: {
                    beganPreparation = true
                    return model.documentTabController.tab(for: reference)
                })
        ) {
            reachedDestination = true
        }
        try await waitUntil { release != nil && beganPreparation }
        model.documentTabController.removeTabs(withIDs: [tab.id])
        failedSave = installFailedSave(on: outgoing)
        release?.resume()
        release = nil
        await model.waitForDocumentTransitions()
        #expect(!reachedDestination)
        #expect(outgoing.hasUnsavedChanges)
        #expect(model.documentController.selectedDocument == model.documentTabController.selectedTab?.document)
    }

    private func installFailedSave(on session: DocumentSessionModel) -> Task<EditorSaveOutcome, Error> {
        session.beginEditing(in: .source)
        session.originalEditingSource = "Saved\r\n"
        session.editingSource = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        session.suppressAutosave = true
        let save = Task<EditorSaveOutcome, Error> { throw FixtureFailure.save }
        session.cancelSaveAttempt()
        session.beginSaveAttempt(.init(task: save))
        return save
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw FixtureFailure.save }
            await Task.yield()
        }
    }

    @Test(
        "Synthetic replacement records the delay contributed by an unrelated pending save",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_TAB_BACKGROUND_SAVE_MEASURE"] == "1")
    )
    func syntheticBackgroundSaveDepartureMeasurement() async throws {
        // This is a controlled causal probe: the background save task is a
        // substituted 250 ms boundary. No disk or user-visible paint claim.
        let (model, background, outgoing) = makeModel()
        background.beginEditing(in: .source)
        background.originalEditingSource = "Saved\r\n"
        let exactDraft = "\u{FEFF}Unsaved 中文 😀 e\u{301}。\r\n"
        background.editingSource = exactDraft
        background.suppressAutosave = true
        defer {
            background.cancelSaveAttempt()
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        var milliseconds: [Double] = []
        for sample in 0..<7 {
            let pending = Task<EditorSaveOutcome, Error> { @MainActor in
                try await Task.sleep(for: .milliseconds(250))
                return .clean
            }
            let attempt = ActiveSaveAttempt(task: pending)
            background.beginSaveAttempt(attempt)
            let start = ContinuousClock.now
            var elapsed: Duration?
            model.enqueueDocumentTransition {
                elapsed = start.duration(to: .now)
            }
            await model.waitForDocumentTransitions()
            let duration = try #require(elapsed).components
            if sample >= 2 {
                milliseconds.append(Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
            }
            _ = try await pending.value
            background.completeSaveAttempt(token: attempt.token)
            #expect(Data(background.editingSource.utf8) == Data(exactDraft.utf8))
        }
        print(
            "TAB_BACKGROUND_SAVE_SCENARIO substituted_save_ms=250 warmups=2 retained=5 "
                + "milliseconds=\(milliseconds.map { String(format: "%.3f", $0) }.joined(separator: ","))")
        #expect(milliseconds.count == 5)
    }

    @Test("Library replacement navigates without ending the departing presentation")
    func libraryReplacementDoesNotClosePresentation() throws {
        let (model, background, outgoing) = makeModel()
        defer {
            background.cancelScheduledWork()
            outgoing.cancelScheduledWork()
        }
        outgoing.canRetrySave = true
        outgoing.scrollFraction = 0.62
        let departing = try #require(model.documentTabController.tabs.last?.document)
        let destination = try #require(model.documentTabController.tabs.first?.document)
        model.documentController.selectDocument(destination)
        model.synchronizeDocumentTabs(after: .place(.replaceSelected))
        #expect(outgoing.scrollFraction == 0.62)
        #expect(model.documentController.retainedSession(for: try #require(departing.sessionKey)) === outgoing)
    }

    private func makeModel() -> (WindowModel, DocumentSessionModel, DocumentSessionModel) {
        let model = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let vaultID = UUID()
        var sessions: [DocumentSessionModel] = []
        for path in ["Background.md", "Outgoing.md"] {
            let noteID = UUID()
            let snapshot = WorkspaceNoteSnapshot(
                id: .init(vaultID: vaultID, relativePath: path), vaultRole: .topicKnowledge,
                stableIdentity: .resolved(noteID),
                document: .init(relativePath: path, rawContent: "Saved\r\n"),
                fileMetadata: .init(byteCount: 7, creationDate: nil, modificationDate: nil),
                graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
            model.documentController.installOpenedDocument(snapshot, vaultName: "Fixture", vaultRole: .topicKnowledge)
            let document = model.documentController.selectedDocument!
            let session = model.documentController.session(for: document.editingTarget)
            session.finishEditing()
            sessions.append(session)
            model.documentTabController.activate(document: document, title: path, toolTip: path, placement: .newTab)
        }
        model.reconcileDocumentSessionLeases()
        return (model, sessions[0], sessions[1])
    }
}
