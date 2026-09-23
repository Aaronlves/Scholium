import AppKit
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Detached document persistence")
struct DocumentDetachedPersistenceTests {
    @Test("Native detachment captures exact text and freezes input until reattachment")
    func detachedCaptureAdmission() async throws {
        let fixture = try await makeEditor()
        try fixture.insert("cafe\u{301} 🦉\r\n")
        let expected = fixture.editor.checkedSource
        fixture.editor.detachNativeView(attachmentID: fixture.attachmentID)
        let snapshot = try await fixture.editor.persistenceSnapshot(expectedRevision: fixture.revision)
        #expect(snapshot.text.utf8.elementsEqual(expected.utf8))
        #expect(snapshot.suspensionID != nil)
        #expect(!fixture.editor.nativeEditor.isEditable)
        fixture.editor.nativeEditor.insertText("Late", replacementRange: NSRange(location: 0, length: 0))
        #expect(try await fixture.editor.currentText() == expected)
        let resumed = fixture.editor.attachNativeView()
        defer { fixture.editor.detachNativeView(attachmentID: resumed) }
        #expect(fixture.editor.nativeEditor.isEditable)
        try fixture.insert("Resumed")
        #expect(try await fixture.editor.currentText() == expected + "Resumed")
    }

    @Test("A stale navigation completion cannot resume a newer suspension")
    func staleResumeDoesNotUnfreeze() async throws {
        let fixture = try await makeEditor()
        defer { fixture.editor.detachNativeView(attachmentID: fixture.attachmentID) }
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        let first = try #require(fixture.editor.detachmentSuspensionID)
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(fixture.editor.detachmentSuspensionID == first)
        try await fixture.editor.resumeAfterDetachment(suspensionID: first)
        try await fixture.editor.captureStateForViewReconstruction(suspendForDetachment: true)
        let second = try #require(fixture.editor.detachmentSuspensionID)
        #expect(first != second)
        try await fixture.editor.resumeAfterDetachment(suspensionID: first)
        #expect(fixture.editor.detachmentSuspensionID == second)
        try await fixture.editor.resumeAfterDetachment(suspensionID: second)
        #expect(fixture.editor.detachmentSuspensionID == nil)
    }

    @Test("Immediate navigation waits for the previous cancelled transition to resume before freezing again")
    func immediateNavigationWaitsForResume() async throws {
        let fixture = try await makeEditor()
        defer { fixture.editor.detachNativeView(attachmentID: fixture.attachmentID) }
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        let document = WindowSelectedDocument.workspace(
            .init(
                sessionKey: key,
                reference: .init(
                    vaultID: key.vaultID, vaultName: "Topics", vaultRole: .topicKnowledge,
                    relativePath: "Source.md", stableNoteID: key.noteID.uuidString)))
        let session = DocumentSessionModel(key: key, editorSession: fixture.editor)
        session.beginEditing(in: .edit)
        session.editingSource = fixture.editor.checkedSource
        session.originalEditingSource = fixture.editor.checkedSource
        session.editingRevision = fixture.revision
        let controller = DocumentController()
        controller.receiveSessionTransfer(.init(document: document, session: session, snapshot: nil, mode: .edit))
        defer { session.cancelScheduledWork() }
        try await controller.prepareSessionTransfer(document)
        let first = try #require(fixture.editor.detachmentSuspensionID)
        controller.resumeAutosave(afterTransferOf: document, suspensionID: first)
        try await controller.prepareSessionTransfer(document)
        let second = try #require(fixture.editor.detachmentSuspensionID)
        #expect(second != first)
        #expect(session.detachmentResumeTask == nil)
        try await fixture.editor.resumeAfterDetachment(suspensionID: second)
    }

    enum SaveScenario: CaseIterable {
        case ordinary, externalConflict
    }

    @Test("A background native document saves exact bytes and detects external conflict", arguments: SaveScenario.allCases)
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
                source: original, revision: snapshot.fingerprint, mode: .edit)
            try fixture.insert("\r\nResearcher's cafe\u{301} 🦉\r\n")
            session.suppressAutosave = true
            controller.receiveSessionTransfer(
                .init(document: document, session: session, snapshot: snapshot, mode: .edit),
                selecting: false
            )
            defer { session.cancelScheduledWork() }
            try await controller.prepareSessionTransfer(document)
            fixture.editor.detachNativeView(attachmentID: fixture.attachmentID)
            let expected = fixture.editor.checkedSource
            #expect(controller.selectedDocument == nil)
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
                #expect(!fixture.editor.hasAttachedNativeView)
                #expect(fixture.editor.hasDetachedPersistenceSnapshot)
                #expect(session.pendingEditorCommit == nil)
                let reconstructed = fixture.editor.checkedSource
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
        _ = NSApplication.shared
        let editor = MarkdownEditorSession()
        editor.loadDocument(source, documentID: editor.editorDocumentID, mode: .edit)
        let attachmentID = editor.attachNativeView()
        try #require(editor.isLoaded)
        return Fixture(editor: editor, attachmentID: attachmentID, revision: DocumentFingerprint(content: source))
    }

    @MainActor
    private struct Fixture {
        let editor: MarkdownEditorSession
        let attachmentID: UUID
        let revision: DocumentFingerprint

        func insert(_ exact: String) throws {
            let end = editor.nativeEditor.rawSource.utf16.count
            let normalized = exact.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            try editor.nativeEditor.replaceProjectedRanges([(NSRange(location: end, length: 0), normalized)])
            _ = try editor.reconcileNativeSource()
        }
    }
}
