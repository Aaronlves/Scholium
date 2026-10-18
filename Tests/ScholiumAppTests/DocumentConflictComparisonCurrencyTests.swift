import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing
import WebKit

@testable import ScholiumApp

@MainActor
@Suite("Conflict comparison currency", .serialized)
struct DocumentConflictComparisonCurrencyTests {
    @Test("Comparison captures current source and citations after the conflict, including pending WebKit deltas", arguments: [false, true])
    func comparisonCapturesCurrentEditor(citationManaged: Bool) async throws {
        try await withFixture(citationManaged: citationManaged) { fixture in
            let firstDraft = fixture.editor.checkedSource
            fixture.bridge.appendBrowserOnly("After conflict: cafe\u{301} 🦉\r\n")
            if citationManaged { fixture.bridge.replaceCitationData(.init(documentData: "Current local preferences")) }
            let current = fixture.bridge.source
            #expect(fixture.session.conflict?.editorSource == firstDraft)
            #expect(fixture.editor.checkedSource == firstDraft)

            try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)

            let comparison = try #require(fixture.session.conflictComparison)
            #expect(Data(comparison.editorSource.utf8) == Data(current.utf8))
            #expect(comparison.editorRevision == DocumentFingerprint(content: current))
            #expect(comparison.diskRevision == fixture.disk.fingerprint)
            #expect(comparison.editorCitationData == fixture.bridge.citationData)
            #expect(fixture.session.showConflictComparison)
            #expect(fixture.editor.checkedSource == current)
            #expect(fixture.session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.url) == fixture.disk.sourceBytes)
        }
    }

    @Test("Reload refuses source or citation input accepted after the displayed comparison", arguments: [false, true])
    func reloadRefusesPendingInput(citationOnly: Bool) async throws {
        try await withFixture(citationManaged: citationOnly) { fixture in
            try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)
            let compared = try #require(fixture.session.conflictComparison)
            if citationOnly {
                fixture.bridge.replaceCitationData(.init(documentData: "Unshown local citation preferences"))
            } else {
                fixture.bridge.appendBrowserOnly("Unshown input after comparison 🦉\r\n")
            }
            let current = fixture.bridge.source
            let currentCitations = fixture.bridge.citationData
            #expect(fixture.editor.checkedSource == compared.editorSource)
            #expect(fixture.editor.checkedCitationData == compared.editorCitationData)

            await #expect(throws: (any Error).self) {
                try await fixture.controller.reloadFromDisk(session: fixture.session, target: fixture.target)
            }

            #expect(Data(fixture.editor.checkedSource.utf8) == Data(current.utf8))
            #expect(fixture.editor.checkedCitationData == currentCitations)
            #expect(fixture.session.conflict != nil && fixture.session.isEditing)
            #expect(fixture.session.hasUnsavedChanges)
            #expect(fixture.editor.detachmentSuspensionID == nil)
            #expect(fixture.bridge.suspensionID == nil)
            #expect(try Data(contentsOf: fixture.url) == fixture.disk.sourceBytes)
            #expect(try await fixture.documents.load(fixture.id).citationSnapshot == fixture.disk.citationSnapshot)
        }
    }

    enum InterruptedComparison: CaseIterable { case cancellation, departure, newerConflict }

    @Test("A cancelled or superseded full-buffer comparison cannot publish", arguments: InterruptedComparison.allCases)
    func comparisonReadCurrency(interruption: InterruptedComparison) async throws {
        try await withFixture { fixture in
            let pause = CapturePause()
            fixture.bridge.nextQueryPause = pause
            fixture.bridge.appendBrowserOnly("Pending current draft\r\n")
            let current = fixture.bridge.source
            let pending = Task { @MainActor in
                try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)
            }
            defer {
                pause.release()
                pending.cancel()
            }
            try await pause.waitUntilStarted()
            let conflictBefore = try #require(fixture.session.conflict)
            var expectedConflict = conflictBefore
            switch interruption {
            case .cancellation: pending.cancel()
            case .departure: fixture.controller.clearSelectionAfterClosingLastTab()
            case .newerConflict:
                expectedConflict = .init(
                    relativePath: conflictBefore.relativePath, editorSource: conflictBefore.editorSource,
                    diskSource: "Newer disk revision\r\n", baseRevision: conflictBefore.baseRevision)
                fixture.session.conflict = expectedConflict
            }
            pause.release()
            await #expect(throws: (any Error).self) { try await pending.value }
            #expect(fixture.session.conflict == expectedConflict)
            #expect(fixture.session.conflictComparison == nil && !fixture.session.showConflictComparison)
            #expect(fixture.bridge.source == current)
            #expect(try Data(contentsOf: fixture.url) == fixture.disk.sourceBytes)
        }
    }

    @Test("Cancelling a frozen reload restores its own input and retains the compared draft")
    func cancelledReloadResumesItsFreeze() async throws {
        try await withFixture { fixture in
            try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)
            let compared = try #require(fixture.session.conflictComparison)
            let pause = CapturePause()
            fixture.controller.bind(to: fixture.documents, documentDidCommit: { _ in await pause.suspend() })
            let pending = Task { @MainActor in
                try await fixture.controller.reloadFromDisk(session: fixture.session, target: fixture.target)
            }
            defer {
                pause.release()
                pending.cancel()
            }
            try await pause.waitUntilStarted()
            #expect(fixture.bridge.suspensionID != nil)
            pending.cancel()
            pause.release()
            await #expect(throws: CancellationError.self) { try await pending.value }

            #expect(fixture.editor.detachmentSuspensionID == nil && fixture.bridge.suspensionID == nil)
            #expect(fixture.session.conflict != nil && fixture.session.isEditing)
            #expect(Data(fixture.editor.checkedSource.utf8) == Data(compared.editorSource.utf8))
            #expect(fixture.session.hasUnsavedChanges)
            #expect(try Data(contentsOf: fixture.url) == fixture.disk.sourceBytes)
        }
    }

    @Test("A failed reload cannot resume a suspension already owned by navigation")
    func failedReloadPreservesExistingFreeze() async throws {
        try await withFixture { fixture in
            try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)
            try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
            let navigationToken = try #require(fixture.editor.detachmentSuspensionID)
            let revision = try #require(fixture.session.editingRevision)
            fixture.session.conflict = .init(
                relativePath: fixture.id.relativePath, editorSource: fixture.editor.checkedSource,
                diskSource: "Superseding conflict\r\n", baseRevision: revision)
            await #expect(throws: (any Error).self) {
                try await fixture.controller.reloadFromDisk(session: fixture.session, target: fixture.target)
            }
            #expect(fixture.editor.detachmentSuspensionID == navigationToken)
            #expect(fixture.bridge.suspensionID == navigationToken)
            try await fixture.editor.resumeAfterDetachment(suspensionID: navigationToken)
        }
    }

    @Test("An unchanged displayed source and citation pair can reload exactly", arguments: [false, true])
    func unchangedPairReloads(citationManaged: Bool) async throws {
        try await withFixture(citationManaged: citationManaged) { fixture in
            try await fixture.controller.presentConflictComparison(session: fixture.session, target: fixture.target)
            try await fixture.controller.reloadFromDisk(session: fixture.session, target: fixture.target)
            #expect(fixture.session.conflict == nil && fixture.session.conflictComparison == nil)
            #expect(!fixture.session.isEditing && !fixture.session.hasUnsavedChanges)
            #expect(Data(fixture.editor.checkedSource.utf8) == fixture.disk.sourceBytes)
            #expect(fixture.editor.checkedCitationData == fixture.disk.citationSnapshot?.data)
            #expect(try Data(contentsOf: fixture.url) == fixture.disk.sourceBytes)
        }
    }

    private struct Fixture {
        let controller: DocumentController
        let session: DocumentSessionModel
        let editor: MarkdownEditorSession
        let bridge: ConflictBufferBridge
        let target: DocumentEditingTarget
        let documents: any DocumentUseCases
        let id: VaultQualifiedNoteID
        let url: URL
        let disk: NoteDocument
    }

    private func withFixture(
        citationManaged: Bool = false, _ operation: @MainActor (Fixture) async throws -> Void
    ) async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/conflict-comparison-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
        let source = "\u{FEFF}# Synthetic conflict\r\nOriginal e\u{301} 🦉.\r\n"
        let url = vaults[1].appendingPathComponent("Conflict.md")
        try Data(source.utf8).write(to: url)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let capabilities = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Conflict comparison fixture")
            let vault = try #require(try await capabilities.documents.snapshot().first { $0.vault.role == .topicKnowledge })
            let summary = try #require(vault.documents.first { $0.id.relativePath == "Conflict.md" })
            let opened = try await capabilities.documents.hydrate(summary)
            let noteID = try #require(opened.stableIdentity.resolvedID)
            let mutation = NoteMutationTarget(documentID: summary.id, stableNoteID: noteID, revision: opened.fingerprint)
            let base: NoteDocument
            if citationManaged {
                base = try await capabilities.documents.save(
                    mutation, changeSet: .citationSource(source, .init(expectedRevision: nil, data: .init(documentData: "Base preferences")))
                ).committedValue.document
            } else {
                base = opened.document
            }
            let diskSource = source + "External writer's revision.\r\n"
            let disk = try await capabilities.documents.save(
                mutation,
                changeSet: citationManaged
                    ? .citationSource(diskSource, .init(expectedRevision: base.citationSnapshot?.revision, data: .init(documentData: "Disk preferences")))
                    : .source(diskSource)
            ).committedValue.document
            let bridge = ConflictBufferBridge()
            let editor = MarkdownEditorSession(bridgeDispatcher: bridge)
            let key = DocumentSessionKey(vaultID: summary.id.vaultID, noteID: noteID)
            let document = WindowSelectedDocument.workspace(
                .init(
                    sessionKey: key,
                    reference: .init(
                        vaultID: summary.id.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                        relativePath: summary.id.relativePath, stableNoteID: noteID.uuidString)))
            let session = DocumentSessionModel(key: key, editorSession: editor)
            let controller = DocumentController()
            controller.rememberPresentationMode(.source)
            controller.receiveSessionTransfer(
                .init(
                    document: document, session: session, snapshot: .init(summary: opened.summary, document: base), mode: .source))
            controller.bind(to: capabilities.documents)
            let webView = WKWebView()
            editor.attach(webView)
            defer {
                bridge.nextQueryPause?.release()
                session.cancelScheduledWork()
                controller.unbind()
                editor.detach(webView)
            }
            editor.editorBecameReady()
            try #require(try await editor.waitUntilLoadedForSave())
            bridge.appendBrowserOnly("Local draft before conflict.\r\n")
            let captured = try await editor.persistenceSnapshot(expectedRevision: base.fingerprint)
            session.conflict = .init(
                relativePath: summary.id.relativePath, editorSource: captured.text, diskSource: disk.rawContent,
                baseRevision: base.fingerprint, baseCitationSnapshot: base.citationSnapshot,
                editorCitationData: captured.citationData, diskCitationSnapshot: disk.citationSnapshot)
            try await operation(
                .init(
                    controller: controller, session: session, editor: editor, bridge: bridge,
                    target: document.editingTarget, documents: capabilities.documents, id: summary.id, url: url, disk: disk))
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}

@MainActor
private final class CapturePause {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    private var released = false

    func suspend() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !started {
            try #require(ContinuousClock.now < deadline)
            await Task.yield()
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ConflictBufferBridge: MarkdownEditorBridgeDispatching {
    var source = ""
    var generation = 0
    var citationSnapshot: ZoteroCitationSnapshot?
    var citationData: ZoteroCitationData?
    var suspensionID: String?
    var nextQueryPause: CapturePause?

    func appendBrowserOnly(_ value: String) {
        source += value
        generation += 1
    }
    func replaceCitationData(_ value: ZoteroCitationData) {
        citationData = value
        generation += 1
    }

    func dispatch(requestJSON: String, in webView: WKWebView) async throws -> Any? {
        let request = try JSONDecoder().decode(MarkdownEditorRequest.self, from: Data(requestJSON.utf8))
        var text: String?
        var recovery = false
        var preservesHistory = false
        switch request.operation {
        case .initialize(let source, _, _, _, let citationSnapshot, _):
            self.source = source
            generation = 0
            self.citationSnapshot = citationSnapshot
            citationData = citationSnapshot?.data
            suspensionID = nil
        case .queryText:
            if let pause = nextQueryPause {
                nextQueryPause = nil
                await pause.suspend()
            }
            text = source
        case .suspendForDetachment(let id):
            suspensionID = id
            text = source
            recovery = true
            preservesHistory = true
        case .captureRecovery: recovery = true
        case .resumeAfterDetachment(let id):
            guard suspensionID == id else { throw MarkdownEditorSession.SessionError.staleRequest }
            suspensionID = nil
        default: break
        }
        var result: [String: Any] = [
            "requestID": request.requestID.uuidString, "resultingGeneration": generation,
            "interactionRevision": generation, "sourceChanged": false,
            "selections": [["anchor": 0, "head": 0]], "accepted": true,
            "citationManaged": citationSnapshot != nil,
        ]
        if let text { result["text"] = text }
        if let citationData { result["citationData"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationData)) }
        if recovery {
            var payload: [String: Any] = [
                "documentID": request.documentID, "fingerprint": request.startingFingerprint,
                "generation": generation, "ranges": [["anchor": 0, "head": 0]],
                "source": source, "undoHistoryPreserved": preservesHistory, "dirty": generation > 0, "focusTarget": "editor",
            ]
            if preservesHistory { payload["stateJSON"] = "{}" }
            if let citationSnapshot { payload["citationSnapshot"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationSnapshot)) }
            if let citationData { payload["citationData"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(citationData)) }
            result["recovery"] = payload
        }
        return result
    }
}
