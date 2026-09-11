import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Chat reference revision navigation", .serialized)
@MainActor
struct AgentChatReferenceNavigationTests {
    @Test("References verify exact source before locating and never save a current dirty Note")
    func versionedNavigation() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-evolution/reference-navigation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = root.appendingPathComponent("Triptych")
        let analyses = triptych.appendingPathComponent("Analyses")
        let topics = triptych.appendingPathComponent("Topics")
        let works = triptych.appendingPathComponent("Works")
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = "\u{FEFF}# 原文\r\n\r\nExact **source** 😀.\r\n"
        let file = analyses.appendingPathComponent("Source.md")
        try Data(source.utf8).write(to: file)
        try Data("# Peer\n".utf8).write(to: analyses.appendingPathComponent("Peer.md"))
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses,
                topicKnowledgeURL: topics, outputURL: works, portableContainerURL: triptych, triptychName: "Reference Fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let noteID = try #require(note.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            let fingerprint = DocumentFingerprint(content: source)
            let peer = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Peer.md" })
            let peerID = try #require(peer.reference.stableNoteID.flatMap(UUID.init(uuidString:)))
            #expect(window.openChatReference(AgentChatReference.url(noteID: peerID)))
            await window.waitForPendingDocumentTransitionsForTesting()
            let url = AgentChatReference.url(noteID: noteID, line: 3, revision: fingerprint, vaultID: note.reference.vaultID)
            #expect(window.openChatReference(url))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.currentDocumentDescriptor?.sessionKey == DocumentSessionKey(vaultID: note.reference.vaultID, noteID: noteID))
            #expect(window.documentController.sourceLocationRequest?.line == 3)
            #expect(window.documentTabController.allTabs.count == 2)
            #expect(window.documentTabController.allTabs.contains { $0.document.workspaceDescriptor?.sessionKey.noteID == peerID })
            let exact = (source as NSString).range(of: "source")
            let passage = SearchSourceRange(
                utf16LowerBound: exact.location, utf16UpperBound: NSMaxRange(exact),
                line: 3, column: 9, endLine: 3, endColumn: 15)
            await window.openChatAttachment(
                .init(
                    noteID: noteID, vaultID: note.reference.vaultID,
                    relativePath: "Source.md", text: "source", fingerprint: fingerprint, sourceLine: 3, sourceRange: passage))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.range == passage)
            #expect(window.documentController.sourceLocationRequest?.sourceFingerprint == fingerprint.sha256)
            #expect(window.documentController.sourceLocationRequest?.requiresExactSelection == true)
            let issueCount = window.shellState.operationIssues.count

            #expect(window.openChatReference(AgentChatReference.url(noteID: noteID, line: 99, revision: fingerprint)))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil)
            #expect(window.documentController.sourceLocationRequest == nil)
            #expect(window.shellState.operationIssues.count > issueCount)

            await window.openChatAttachment(
                .init(
                    noteID: noteID, vaultID: note.reference.vaultID,
                    relativePath: "Source.md", text: "wrong", fingerprint: fingerprint, sourceLine: 3, sourceRange: passage))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.range == nil && window.documentController.sourceLocationRequest?.line == nil)

            #expect(window.openChatReference(AgentChatReference.url(noteID: noteID, line: 3)))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil)
            let unverifiedNotice = window.shellState.operationIssues.last?.message
            let afterUnverified = window.shellState.operationIssues.count
            #expect(window.openChatReference(AgentChatReference.url(noteID: noteID)))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil && window.shellState.operationIssues.count == afterUnverified)
            #expect(!window.openChatReference(AgentChatReference.url(noteID: noteID, vaultID: UUID())))
            #expect(!window.openChatReference(AgentChatReference.url(noteID: UUID())))
            #expect(window.currentDocumentDescriptor?.sessionKey.noteID == noteID)

            // A stale attachment follows the same version check as an answer link.
            await window.openChatAttachment(
                .init(
                    noteID: noteID, vaultID: note.reference.vaultID,
                    relativePath: "Source.md", text: "Old source", fingerprint: DocumentFingerprint(content: "Old source"), sourceLine: 2))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil)
            let changedNotice = window.shellState.operationIssues.last?.message
            #expect(changedNotice != nil && changedNotice != unverifiedNotice)

            // The catalog may still show the old revision while a concurrent writer has changed the file.
            let external = source + "External change\r\n"
            try Data(external.utf8).write(to: file)
            for issue in window.shellState.operationIssues { window.shellState.dismissOperationIssue(id: issue.id) }
            #expect(window.openChatReference(url))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil)
            #expect(window.shellState.operationIssues.last?.message == changedNotice)
            #expect(try Data(contentsOf: file) == Data(external.utf8))
            try Data(source.utf8).write(to: file)

            let selected = try #require(window.currentDocumentDescriptor)
            let session = window.documentController.session(for: selected)
            session.suppressAutosave = true
            let unsaved = "Unsaved source must stay in the current editor."
            session.editingSource = unsaved
            for issue in window.shellState.operationIssues { window.shellState.dismissOperationIssue(id: issue.id) }
            #expect(window.openChatReference(url))
            await window.waitForPendingDocumentTransitionsForTesting()
            #expect(window.documentController.sourceLocationRequest?.line == nil)
            #expect(window.shellState.operationIssues.last?.message == unverifiedNotice)
            #expect(session.editingSource == unsaved && session.hasUnsavedChanges)
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
