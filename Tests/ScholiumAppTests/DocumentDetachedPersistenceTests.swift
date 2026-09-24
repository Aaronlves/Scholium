import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@MainActor
@Suite("Detached document persistence")
struct DocumentDetachedPersistenceTests {
    @Test("Only a frozen full capture authorizes a detached save, and a later delta invalidates it")
    func detachedCaptureAdmission() async throws {
        let fixture = try await makeEditor()
        let editor = fixture.editor
        defer { if editor.hasAttachedWebView { editor.detach(fixture.webView) } }
        try fixture.insert("cafe\u{301} 🦉\r\n")
        try await editor.captureStateForViewReconstruction()
        editor.detach(fixture.webView)
        await #expect(throws: MarkdownEditorSession.SessionError.self) {
            try await editor.persistenceSnapshot(expectedRevision: fixture.revision)
        }

        let frozen = try await makeEditor()
        try frozen.insert("cafe\u{301} 🦉\r\n")
        try await frozen.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        frozen.editor.detach(frozen.webView)
        let snapshot = try await frozen.editor.persistenceSnapshot(expectedRevision: frozen.revision)
        #expect(Data(snapshot.text.utf8) == Data(frozen.dispatcher.source.utf8))
        #expect(snapshot.suspensionID != nil)
        #expect(
            frozen.editor.acceptEditorChanges(
                [.init(from: 0, to: 0, insert: "Late", exactInsert: "Late")],
                baseGeneration: frozen.editor.generation, resultingGeneration: frozen.editor.generation + 1))
        await #expect(throws: MarkdownEditorSession.SessionError.self) {
            try await frozen.editor.persistenceSnapshot(expectedRevision: frozen.revision)
        }
    }

    @Test("A stale navigation completion cannot resume a newer suspension")
    func staleResumeDoesNotUnfreeze() async throws {
        let fixture = try await makeEditor()
        defer { fixture.editor.detach(fixture.webView) }
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        let first = try #require(fixture.editor.detachmentSuspensionID)
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(fixture.editor.detachmentSuspensionID == first)
        try await fixture.editor.resumeAfterDetachment(suspensionID: first)
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        let second = try #require(fixture.editor.detachmentSuspensionID)
        #expect(first != second)
        try await fixture.editor.resumeAfterDetachment(suspensionID: first)
        #expect(fixture.dispatcher.suspensionID == second)
        #expect(fixture.editor.detachmentSuspensionID == second)
        try await fixture.editor.resumeAfterDetachment(suspensionID: second)
        #expect(fixture.dispatcher.suspensionID == nil)
        #expect(fixture.editor.detachmentSuspensionID == nil)
    }

    @Test("Immediate navigation waits for the previous cancelled transition to resume before freezing again")
    func immediateNavigationWaitsForResume() async throws {
        let fixture = try await makeEditor()
        defer { fixture.editor.detach(fixture.webView) }
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let document = WindowSelectedDocument.workspace(
            .init(
                sessionKey: key,
                reference: .init(
                    vaultID: key.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                    relativePath: "Source.md", stableNoteID: key.noteID.uuidString)))
        let session = DocumentSessionModel(key: key, editorSession: fixture.editor)
        session.beginEditing(in: .source)
        session.editingSource = fixture.dispatcher.source
        session.originalEditingSource = fixture.dispatcher.source
        session.editingRevision = fixture.revision
        let controller = DocumentController()
        controller.receiveSessionTransfer(.init(document: document, session: session, snapshot: nil, mode: .source))
        defer { session.cancelScheduledWork() }
        try await controller.prepareSessionTransfer(document)
        let first = try #require(fixture.editor.detachmentSuspensionID)
        controller.resumeAutosave(afterTransferOf: document, suspensionID: first)
        try await controller.prepareSessionTransfer(document)
        let second = try #require(fixture.editor.detachmentSuspensionID)
        #expect(second != first)
        #expect(fixture.dispatcher.suspensionID == second)
        #expect(session.detachmentResumeTask == nil)
        try await fixture.editor.resumeAfterDetachment(suspensionID: second)
    }

    enum SaveScenario: CaseIterable {
        case ordinary, externalConflict, failedAcknowledgement, failedFrozenAcknowledgement
    }

    @Test("A background frozen document saves exact bytes and rebases its reconstruction without a WebView", arguments: SaveScenario.allCases)
    func backgroundSaveAndExternalConflict(scenario: SaveScenario) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/detached-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let file = vaults[1].appendingPathComponent("Source.md")
        let original = "\u{FEFF}Original\r\n"
        try Data(original.utf8).write(to: file)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Detached save fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
            let snapshot = try #require(vault.documents.first { $0.id.relativePath == "Source.md" })
            let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: try #require(snapshot.stableIdentity.resolvedID))
            let document = WindowSelectedDocument.workspace(
                .init(
                    sessionKey: key,
                    reference: .init(
                        vaultID: key.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                        relativePath: "Source.md", stableNoteID: key.noteID.uuidString)))
            let fixture = try await makeEditor(source: original)
            let session = DocumentSessionModel(key: key, editorSession: fixture.editor)
            let controller = DocumentController()
            controller.bind(to: capabilities.documents)
            controller.beginEditing(
                session: session, target: document.editingTarget,
                source: original, revision: snapshot.fingerprint, mode: .source)
            try fixture.insert("\r\nResearcher's cafe\u{301} 🦉\r\n")
            session.suppressAutosave = true
            controller.receiveSessionTransfer(
                .init(document: document, session: session, snapshot: snapshot, mode: .source),
                selecting: scenario == .failedFrozenAcknowledgement
            )
            defer { session.cancelScheduledWork() }
            if scenario == .failedAcknowledgement || scenario == .failedFrozenAcknowledgement {
                if scenario == .failedFrozenAcknowledgement { try await controller.prepareSessionTransfer(document) }
                fixture.dispatcher.failNextAcknowledgement = true
                await #expect(throws: MarkdownEditorSession.SessionError.self) {
                    try await controller.flushCurrentEditor(session: session, target: document.editingTarget)
                }
                try #require(!fixture.dispatcher.failNextAcknowledgement)
                #expect(session.pendingEditorCommit != nil)
                #expect(try Data(contentsOf: file) == Data(fixture.dispatcher.source.utf8))
                #expect(session.editingRevision?.sha256 != fixture.editor.startingFingerprint)
                if scenario == .failedFrozenAcknowledgement {
                    let suspensionID = try #require(fixture.editor.detachmentSuspensionID)
                    controller.resumeAutosave(afterTransferOf: document, suspensionID: suspensionID)
                    let resume = try #require(session.detachmentResumeTask)
                    await resume.value
                    #expect(session.pendingEditorCommit == nil)
                    #expect(fixture.editor.detachmentSuspensionID == nil)
                    #expect(fixture.dispatcher.suspensionID == nil)
                    #expect(fixture.editor.startingFingerprint == session.editingRevision?.sha256)
                }
                try fixture.insert("Input after the committed snapshot.\r\n")
            }
            try await controller.prepareSessionTransfer(document)
            fixture.editor.detach(fixture.webView)
            let expected = fixture.dispatcher.source
            if scenario == .ordinary || scenario == .externalConflict { #expect(session.editingSource == original) }
            if scenario != .failedFrozenAcknowledgement { #expect(controller.selectedDocument == nil) }
            if scenario == .externalConflict {
                let external = "External revision\r\n"
                try Data(external.utf8).write(to: file)
                await #expect(throws: VaultRepositoryError.self) {
                    try await controller.flushBeforeClosing(document)
                }
                #expect(try Data(contentsOf: file) == Data(external.utf8))
                #expect(Data(try #require(session.conflict).editorSource.utf8) == Data(expected.utf8))
                #expect(session.hasUnsavedChanges)
            } else {
                try await controller.flushBeforeClosing(document)
                #expect(try Data(contentsOf: file) == Data(expected.utf8))
                #expect(!session.hasUnsavedChanges)
                #expect(session.editingRevision == DocumentFingerprint(content: expected))
                #expect(fixture.editor.startingFingerprint == session.editingRevision?.sha256)
                #expect(!fixture.editor.hasAttachedWebView)
                #expect(fixture.editor.hasDetachedPersistenceSnapshot)
                #expect(session.pendingEditorCommit == nil)
                let reconstructed = fixture.editor.sourceForViewAttachment(proposedSource: original, documentID: fixture.editor.bridgeDocumentID)
                #expect(Data(reconstructed.utf8) == Data(expected.utf8))
                // Another lifecycle flush joins the same committed detached state.
                try await controller.flushBeforeClosing(document)
            }
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    private func makeEditor(source: String = "Original\r\n") async throws -> Fixture {
        let dispatcher = CaptureDispatcher()
        let editor = MarkdownEditorSession(bridgeDispatcher: dispatcher)
        let webView = WKWebView()
        editor.attach(webView)
        editor.loadDocument(source, documentID: editor.bridgeDocumentID, mode: .source)
        editor.editorBecameReady()
        let loaded = try await editor.waitUntilLoadedForSave()
        try #require(loaded)
        return Fixture(editor: editor, webView: webView, dispatcher: dispatcher, revision: DocumentFingerprint(content: source))
    }

    @MainActor
    private struct Fixture {
        let editor: MarkdownEditorSession
        let webView: WKWebView
        let dispatcher: CaptureDispatcher
        let revision: DocumentFingerprint

        func insert(_ exact: String) throws {
            let end = EditorSourceOffsetMap(source: dispatcher.source).editorUTF16Length
            let nextGeneration = editor.generation + 1
            try #require(
                editor.acceptEditorChanges(
                    [
                        .init(from: end, to: end, insert: exact.replacingOccurrences(of: "\r\n", with: "\n"), exactInsert: exact)
                    ], baseGeneration: editor.generation, resultingGeneration: nextGeneration))
            dispatcher.source += exact
            dispatcher.generation = nextGeneration
            try #require(Data(editor.checkedSource.utf8) == Data(dispatcher.source.utf8))
        }
    }

    /// Deterministic bridge responses exercise the native lifecycle contract;
    /// WebKit input-freezing behavior is covered by the runtime integration test.
    @MainActor
    private final class CaptureDispatcher: MarkdownEditorBridgeDispatching {
        var source = ""
        var generation = 0
        var suspensionID: String?
        var failNextAcknowledgement = false
        private var selections = [MarkdownEditorSelectionRange(anchor: 0, head: 0)]

        func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
            let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
            var text: String?
            var recovery: MarkdownEditorRecoverySnapshot?
            var commitSuperseded: Bool?
            switch request.operation {
            case .initialize(let source, _, _, let initialSelection):
                self.source = source
                generation = 0
                suspensionID = nil
                selections = initialSelection.map { [$0] } ?? [.init(anchor: 0, head: 0)]
            case .suspendForDetachment(let id):
                suspensionID = id
                recovery = snapshot(request)
            case .resumeAfterDetachment(let id):
                guard suspensionID == id else { throw MarkdownEditorSession.SessionError.staleRequest }
                suspensionID = nil
            case .captureRecovery:
                recovery = snapshot(request)
            case .queryText:
                text = source
            case .acknowledgeCommittedSnapshot(let expected, let committed, _):
                if failNextAcknowledgement {
                    failNextAcknowledgement = false
                    throw MarkdownEditorSession.SessionError.unavailable
                }
                let superseded = !source.utf8.elementsEqual(expected.utf8)
                if !superseded { source = committed }
                text = source
                commitSuperseded = superseded
            default:
                break
            }
            // Match WKWebView's object boundary directly. Decoding an encoded
            // JSON string through Foundation here can strip an authored BOM
            // when a later character needs a surrogate pair.
            var result: [String: Any] = [
                "requestID": request.requestID.uuidString,
                "resultingGeneration": generation,
                "sourceChanged": false,
                "selections": selections.map { ["anchor": $0.anchor, "head": $0.head] },
                "accepted": true,
            ]
            if let text { result["text"] = text }
            if let commitSuperseded { result["commitSuperseded"] = commitSuperseded }
            if let recovery {
                result["recovery"] = [
                    "documentID": recovery.documentID,
                    "fingerprint": recovery.fingerprint,
                    "generation": recovery.generation,
                    "ranges": recovery.ranges.map { ["anchor": $0.anchor, "head": $0.head] },
                    "source": recovery.source,
                    "undoHistoryPreserved": recovery.undoHistoryPreserved,
                    "dirty": recovery.dirty,
                    "focusTarget": "editor",
                ]
            }
            return result
        }

        private func snapshot(_ request: MarkdownEditorRequest) -> MarkdownEditorRecoverySnapshot {
            MarkdownEditorRecoverySnapshot(
                documentID: request.documentID, fingerprint: request.startingFingerprint,
                generation: generation, ranges: selections, source: source,
                stateJSON: nil, undoHistoryPreserved: false, dirty: generation > 0, focusTarget: .editor)
        }
    }
}
