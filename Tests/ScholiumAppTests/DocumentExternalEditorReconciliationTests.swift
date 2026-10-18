import AppKit
import Foundation
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Live editor external reconciliation", .serialized)
@MainActor
struct DocumentExternalEditorReconciliationTests {
    @Test("External publication captures queued browser input before deciding clean or conflict", arguments: [false, true])
    func pendingInput(pending: Bool) async throws {
        try await withEditor { fixture in
            let insertion = "Pending cafe\u{301} 🦉\r\n"
            if pending { fixture.bridge.insertBrowserOnly(insertion) }
            #expect(!fixture.session.hasUnsavedChanges)
            let expected = fixture.bridge.source
            let external = fixture.snapshot("External writer\r\n")
            fixture.publish(external)
            await fixture.controller.waitForPendingHydrations()

            #expect(fixture.bridge.freezeCount == 1)
            #expect(fixture.bridge.suspensionID == nil)
            #expect(fixture.session.editorSession.detachmentSuspensionID == nil)
            if pending {
                #expect(fixture.session.hasUnsavedChanges)
                #expect(fixture.session.editingRevision == fixture.original.fingerprint)
                #expect(fixture.session.retainedExactSource.utf8.elementsEqual(expected.utf8))
                #expect(fixture.session.conflict?.editorSource.utf8.elementsEqual(expected.utf8) == true)
                #expect(fixture.session.conflict?.diskSource == external.document.rawContent)
                #expect(fixture.bridge.initializations == 1)
            } else {
                #expect(!fixture.session.hasUnsavedChanges)
                #expect(fixture.session.editingRevision == external.fingerprint)
                #expect(fixture.session.conflict == nil)
                try #require(try await fixture.session.editorSession.waitUntilLoadedForSave())
                #expect(fixture.bridge.source == external.document.rawContent)
            }
        }
    }

    @Test("A newer publication supersedes a pending freeze without leaving input suspended")
    func supersededPublication() async throws {
        try await withEditor { fixture in
            let gate = CaptureGate()
            fixture.bridge.nextFreeze = gate
            fixture.publish(fixture.snapshot("Older external\r\n"))
            try await gate.waitUntilStarted()
            fixture.publish(fixture.snapshot("Newest external\r\n"))
            gate.release()
            await fixture.controller.waitForPendingHydrations()
            try #require(try await fixture.session.editorSession.waitUntilLoadedForSave())
            #expect(fixture.bridge.source == "Newest external\r\n")
            #expect(fixture.session.originalEditingSource == "Newest external\r\n")
            #expect(fixture.bridge.suspensionID == nil)
            #expect(fixture.session.conflict == nil)
        }
    }

    @Test("Navigation waits for refresh cleanup and keeps its own later suspension")
    func navigationDoesNotBorrowRefreshFreeze() async throws {
        try await withEditor { fixture in
            let gate = CaptureGate()
            fixture.bridge.nextFreeze = gate
            fixture.publish(fixture.snapshot("External\r\n"))
            try await gate.waitUntilStarted()
            let refreshSuspension = try #require(fixture.bridge.suspensionID)
            let navigation = Task { @MainActor in
                try await fixture.controller.prepareSessionTransfer(fixture.document)
            }
            defer {
                navigation.cancel()
                gate.release()
            }
            gate.release()
            await fixture.controller.waitForPendingHydrations()
            try await navigation.value
            let navigationSuspension = try #require(fixture.bridge.suspensionID)
            #expect(navigationSuspension != refreshSuspension)
            #expect(fixture.session.editorSession.detachmentSuspensionID == navigationSuspension)
            try await fixture.session.editorSession.resumeAfterDetachment(suspensionID: navigationSuspension)
        }
    }

    @Test("Unbinding during capture preserves source and releases only the cancelled refresh freeze")
    func cancelledRefresh() async throws {
        try await withEditor { fixture in
            let gate = CaptureGate()
            fixture.bridge.nextFreeze = gate
            fixture.publish(fixture.snapshot("External\r\n"))
            try await gate.waitUntilStarted()
            let preparation = try #require(fixture.session.detachmentPreparationTask)
            fixture.controller.unbind()
            gate.release()
            _ = await preparation.result
            #expect(fixture.bridge.source == fixture.original.document.rawContent)
            #expect(fixture.session.editingRevision == fixture.original.fingerprint)
            #expect(fixture.bridge.suspensionID == nil)
            #expect(fixture.bridge.initializations == 1)
        }
    }

    @Test("An existing navigation suspension defers external replacement until its owner resumes")
    func alreadySuspendedNavigation() async throws {
        try await withEditor { fixture in
            try await fixture.controller.prepareSessionTransfer(fixture.document)
            let navigationID = try #require(fixture.bridge.suspensionID)
            fixture.publish(fixture.snapshot("External while navigating\r\n"))
            await fixture.controller.waitForPendingHydrations()
            #expect(fixture.bridge.source == fixture.original.document.rawContent)
            #expect(fixture.bridge.suspensionID == navigationID)
            #expect(fixture.session.editorSession.detachmentSuspensionID == navigationID)
            fixture.controller.resumeAutosave(afterTransferOf: fixture.document, suspensionID: navigationID)
            await fixture.session.detachmentResumeTask?.value
            await fixture.controller.waitForPendingHydrations()
            try #require(try await fixture.session.editorSession.waitUntilLoadedForSave())
            #expect(fixture.bridge.source == "External while navigating\r\n")
            #expect(fixture.bridge.suspensionID == nil)
        }
    }

    @Test("Composition beginning after refresh admission preserves source as a conflict")
    func compositionStartsBeforeCapture() async throws {
        try await withEditor { fixture in
            let external = fixture.snapshot("External during IME\r\n")
            fixture.publish(external)
            let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
            fixture.session.editorSession.updateInteraction(
                selections: [selection], line: 1, column: 1, lineCount: 1,
                documentVersion: fixture.session.editorSession.generation, interactionRevision: 1,
                context: .init(
                    selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                    composing: true, availableCommands: [], undoLabel: nil, redoLabel: nil))
            await fixture.controller.waitForPendingHydrations()
            #expect(fixture.bridge.source == fixture.original.document.rawContent)
            #expect(fixture.session.editingRevision == fixture.original.fingerprint)
            #expect(fixture.session.conflict?.diskSource == external.document.rawContent)
            #expect(fixture.session.conflict?.editorSource == fixture.original.document.rawContent)
            #expect(fixture.bridge.suspensionID == nil)
        }
    }

    @Test("A refresh waiting for navigation cannot replace its newer deferred publication")
    func newerPublicationDuringNavigationAcquisition() async throws {
        try await withEditor { fixture in
            let gate = CaptureGate()
            fixture.session.detachmentResumeTask = Task { @MainActor in await gate.pause() }
            let newest = fixture.snapshot("Newest while navigation completes\r\n")
            let navigation = Task { @MainActor in
                try await fixture.controller.prepareSessionTransfer(fixture.document) { _ in
                    fixture.publish(newest)
                }
            }
            defer {
                navigation.cancel()
                gate.release()
            }
            try await gate.waitUntilStarted()
            try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
                while fixture.session.detachmentPreparationTask == nil { await Task.yield() }
            }
            fixture.publish(fixture.snapshot("Older while navigation captures\r\n"))
            // Navigation is waiting for resumption, before any suspension exists.
            #expect(fixture.session.editorSession.detachmentSuspensionID == nil)
            gate.release()
            try await navigation.value
            fixture.session.detachmentResumeTask = nil
            await fixture.controller.waitForPendingHydrations()
            let navigationID = try #require(fixture.bridge.suspensionID)
            fixture.controller.resumeAutosave(afterTransferOf: fixture.document, suspensionID: navigationID)
            await fixture.session.detachmentResumeTask?.value
            await fixture.controller.waitForPendingHydrations()
            try #require(try await fixture.session.editorSession.waitUntilLoadedForSave())
            #expect(fixture.bridge.source == newest.document.rawContent)
            #expect(fixture.session.editingRevision == newest.fingerprint)
            #expect(fixture.bridge.suspensionID == nil)
        }
    }

    enum InputRecoveryRoute: CaseIterable { case retryEdit, navigationResume, sourceReload }

    @Test("A failed short-operation resume exposes current-document recovery and retains the draft", arguments: InputRecoveryRoute.allCases)
    func failedResumeCanRecoverInCurrentDocument(route: InputRecoveryRoute) async throws {
        try await withEditor { fixture in
            fixture.bridge.insertBrowserOnly("Retained after a transient resume failure 🦉\r\n")
            let draft = fixture.bridge.source
            fixture.bridge.resumeFailuresRemaining = 1
            fixture.publish(fixture.snapshot("External while typing\r\n"))
            await fixture.controller.waitForPendingHydrations()
            let failure = try #require(fixture.session.inputResumeFailure)
            #expect(fixture.session.inputResumeError != nil)
            #expect(failure.suspensionID == fixture.bridge.suspensionID)
            #expect(fixture.session.editorSession.detachmentSuspensionID == failure.suspensionID)
            #expect(fixture.session.conflict?.editorSource == draft)
            #expect(fixture.session.hasUnsavedChanges)

            switch route {
            case .retryEdit:
                try await fixture.controller.retryEditorInput(session: fixture.session, target: fixture.document.editingTarget)
            case .navigationResume:
                fixture.controller.resumeAutosave(afterTransferOf: fixture.document, suspensionID: failure.suspensionID)
                await fixture.session.detachmentResumeTask?.value
            case .sourceReload:
                let editor = fixture.session.editorSession
                editor.loadDocument(draft, documentID: editor.documentID, mode: .source)
                try #require(try await editor.waitUntilLoadedForSave())
                try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
                    while fixture.session.inputResumeFailure != nil { await Task.yield() }
                }
            }
            #expect(fixture.session.inputResumeFailure == nil && fixture.session.inputResumeError == nil)
            #expect(fixture.session.editorSession.detachmentSuspensionID == nil && fixture.bridge.suspensionID == nil)
            #expect(fixture.session.retainedExactSource.utf8.elementsEqual(draft.utf8))
            #expect(fixture.session.conflict?.editorSource == draft && fixture.session.hasUnsavedChanges)
            #expect(fixture.controller.selectedDocument?.editingTarget == fixture.document.editingTarget)
        }
    }

    @Test("A stale short-operation retry clears its record without releasing a navigation freeze")
    func inputRecoveryCannotReleaseNavigationFreeze() async throws {
        try await withEditor { fixture in
            try await fixture.controller.prepareSessionTransfer(fixture.document)
            let navigationID = try #require(fixture.bridge.suspensionID)
            let editor = fixture.session.editorSession
            fixture.session.inputResumeFailure = .init(
                suspensionID: "retired-short-operation", sessionID: editor.sessionID,
                documentID: editor.documentID, message: "Retired resumption failure")
            let resumeCount = fixture.bridge.resumeCount
            try await fixture.controller.retryEditorInput(session: fixture.session, target: fixture.document.editingTarget)
            #expect(fixture.session.inputResumeFailure == nil)
            #expect(fixture.bridge.resumeCount == resumeCount)
            #expect(fixture.bridge.suspensionID == navigationID && editor.detachmentSuspensionID == navigationID)
            fixture.controller.resumeAutosave(afterTransferOf: fixture.document, suspensionID: navigationID)
            await fixture.session.detachmentResumeTask?.value
            #expect(fixture.bridge.suspensionID == nil)
        }
    }

    @Test("Navigation taking over the same failed-resume token revokes the old Retry Edit authority")
    func navigationTakesOverFailedShortOperationToken() async throws {
        try await withEditor { fixture in
            fixture.bridge.insertBrowserOnly("Retained while navigation takes ownership\r\n")
            let draft = fixture.bridge.source
            fixture.bridge.resumeFailuresRemaining = 1
            fixture.publish(fixture.snapshot("External before navigation\r\n"))
            await fixture.controller.waitForPendingHydrations()
            let failure = try #require(fixture.session.inputResumeFailure)
            #expect(fixture.bridge.suspensionID == failure.suspensionID)

            try await fixture.controller.prepareSessionTransfer(fixture.document)
            #expect(fixture.bridge.suspensionID == failure.suspensionID)
            #expect(fixture.session.editorSession.detachmentSuspensionID == failure.suspensionID)
            #expect(fixture.session.inputResumeFailure == nil)
            let resumeCount = fixture.bridge.resumeCount
            try await fixture.controller.retryEditorInput(session: fixture.session, target: fixture.document.editingTarget)
            #expect(fixture.bridge.resumeCount == resumeCount)
            #expect(fixture.bridge.suspensionID == failure.suspensionID)
            #expect(fixture.session.retainedExactSource.utf8.elementsEqual(draft.utf8))

            fixture.controller.resumeAutosave(afterTransferOf: fixture.document, suspensionID: failure.suspensionID)
            await fixture.session.detachmentResumeTask?.value
            #expect(fixture.bridge.suspensionID == nil)
            #expect(fixture.session.retainedExactSource.utf8.elementsEqual(draft.utf8))
        }
    }

    enum InvalidFreezeReply: CaseIterable { case rejected, incompleteHistory }

    @Test("A failed capture and failed cleanup retain short-operation recovery authority", arguments: InvalidFreezeReply.allCases)
    func failedCaptureCleanupCanRetry(reply: InvalidFreezeReply) async throws {
        try await withEditor { fixture in
            fixture.bridge.insertBrowserOnly("Retain source after a rejected capture 🦉\r\n")
            let draft = fixture.bridge.source
            fixture.bridge.invalidNextFreeze = reply
            // One failure belongs to capture's internal cleanup, the other to
            // its serialized owner's cleanup; the explicit retry can succeed.
            fixture.bridge.resumeFailuresRemaining = 2
            fixture.publish(fixture.snapshot("External while capture fails\r\n"))
            await fixture.controller.waitForPendingHydrations()
            let failure = try #require(fixture.session.inputResumeFailure)
            #expect(fixture.session.inputResumeError != nil)
            #expect(fixture.bridge.suspensionID == failure.suspensionID)
            #expect(fixture.session.editorSession.detachmentSuspensionID == failure.suspensionID)
            #expect(fixture.bridge.source.utf8.elementsEqual(draft.utf8))

            try await fixture.controller.retryEditorInput(session: fixture.session, target: fixture.document.editingTarget)
            await fixture.controller.waitForPendingHydrations()
            #expect(fixture.session.inputResumeFailure == nil && fixture.session.inputResumeError == nil)
            #expect(fixture.bridge.suspensionID == nil && fixture.session.editorSession.detachmentSuspensionID == nil)
            #expect(fixture.session.retainedExactSource.utf8.elementsEqual(draft.utf8))
            #expect(fixture.session.conflict?.editorSource == draft)
            #expect(fixture.session.hasUnsavedChanges)
        }
    }

    private func withEditor(_ operation: @MainActor (Fixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let fixture = Fixture()
        let webView = WKWebView()
        fixture.session.editorSession.attach(webView)
        fixture.session.editorSession.editorBecameReady()
        defer {
            fixture.bridge.nextFreeze?.release()
            fixture.session.cancelScheduledWork()
            fixture.session.editorSession.detach(webView)
            fixture.controller.unbind()
        }
        try #require(try await fixture.session.editorSession.waitUntilLoadedForSave())
        try await operation(fixture)
    }

    @MainActor
    private final class Fixture {
        let controller = DocumentController()
        let bridge = BufferBridge()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let session: DocumentSessionModel
        let document: WindowSelectedDocument
        let original: WorkspaceNoteSnapshot

        init() {
            let key = self.key
            document = .workspace(
                .init(
                    sessionKey: key,
                    reference: .init(
                        vaultID: key.vaultID, vaultName: "Fixture", vaultRole: .draftProject,
                        relativePath: "Source.md", stableNoteID: key.noteID.uuidString)))
            original = Self.snapshot(key: key, source: "\u{FEFF}Original 中文 🦉\r\n")
            session = DocumentSessionModel(key: key, editorSession: MarkdownEditorSession(bridgeDispatcher: bridge))
            controller.rememberPresentationMode(.source)
            controller.receiveSessionTransfer(.init(document: document, session: session, snapshot: original, mode: .source))
            controller.beginEditing(
                session: session, target: document.editingTarget,
                source: original.document.rawContent, revision: original.fingerprint, mode: .source)
            session.suppressAutosave = true
        }

        func snapshot(_ source: String) -> WorkspaceNoteSnapshot { Self.snapshot(key: key, source: source) }
        func publish(_ snapshot: WorkspaceNoteSnapshot) {
            controller.recordCommittedSnapshot(snapshot, vaultName: "Fixture", vaultRole: .draftProject)
        }
        private static func snapshot(key: DocumentSessionKey, source: String) -> WorkspaceNoteSnapshot {
            let document = NoteDocument(relativePath: "Source.md", rawContent: source)
            return WorkspaceNoteSnapshot(
                id: .init(vaultID: key.vaultID, relativePath: "Source.md"),
                stableIdentity: .resolved(key.noteID), document: document,
                fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
                graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0))
        }
    }

    /// Only delivery timing is substituted. The production session admits and
    /// reconciles the complete source/generation/capture envelopes.
    @MainActor
    private final class BufferBridge: MarkdownEditorBridgeDispatching {
        var source = ""
        var generation = 0
        var suspensionID: String?
        var nextFreeze: CaptureGate?
        var freezeCount = 0
        var initializations = 0
        var resumeFailuresRemaining = 0
        var resumeCount = 0
        var invalidNextFreeze: InvalidFreezeReply?
        func insertBrowserOnly(_ text: String) {
            source += text
            generation += 1
        }

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            let selection = ["anchor": 0, "head": 0]
            var result: [String: Any] = [
                "requestID": request.requestID.uuidString,
                "interactionRevision": generation, "sourceChanged": false, "selections": [selection], "accepted": true,
            ]
            switch request.operation {
            case .initialize(let text, _, _, _, _, _):
                source = text
                generation = 0
                suspensionID = nil
                initializations += 1
            case .queryText:
                result["text"] = source
            case .suspendForDetachment(let id):
                suspensionID = id
                freezeCount += 1
                result["text"] = source
                result["recovery"] = [
                    "documentID": request.documentID, "fingerprint": request.startingFingerprint,
                    "generation": generation, "ranges": [selection], "source": source,
                    "stateJSON": "{}", "undoHistoryPreserved": true, "dirty": generation > 0,
                ]
                if let invalid = invalidNextFreeze {
                    invalidNextFreeze = nil
                    switch invalid {
                    case .rejected:
                        result["accepted"] = false
                        result["error"] = "The capture reply was rejected."
                    case .incompleteHistory:
                        var recovery = try #require(result["recovery"] as? [String: Any])
                        recovery.removeValue(forKey: "stateJSON")
                        recovery["undoHistoryPreserved"] = false
                        result["recovery"] = recovery
                    }
                }
                if let gate = nextFreeze {
                    nextFreeze = nil
                    await gate.pause()
                }
            case .resumeAfterDetachment(let id):
                resumeCount += 1
                if resumeFailuresRemaining > 0 {
                    resumeFailuresRemaining -= 1
                    throw MarkdownEditorSession.SessionError.bridgeRejected("The editor could not resume input. Try again.")
                }
                if suspensionID == id { suspensionID = nil }
            default: break
            }
            result["resultingGeneration"] = generation
            return result
        }
    }

    @MainActor
    private final class CaptureGate {
        private let arrivals = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func pause() async {
            arrivals.continuation.yield(())
            if !released { await withCheckedContinuation { continuation = $0 } }
        }
        func waitUntilStarted() async throws {
            try await withScholiumLifecycleDeadline(phase: .routeReadiness, timeout: .seconds(3)) {
                for await _ in self.arrivals.stream { return }
            }
        }
        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
