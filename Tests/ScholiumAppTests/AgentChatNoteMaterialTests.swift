import AppKit
import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Whole Note chat materials", .serialized)
@MainActor
struct AgentChatNoteMaterialTests {
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Note material fixture did not become ready")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A selected Note preserves exact source and sends only to its captured conversation")
    func captureAndSend() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-evolution/note-material-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let analyses = root.appendingPathComponent("Triptych/Analyses")
        let topics = root.appendingPathComponent("Triptych/Topics")
        let works = root.appendingPathComponent("Triptych/Works")
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let source = "\u{FEFF}---\r\ntitle: 原文与解释\r\ncustom: 'keep exactly'\r\n---\r\n# 材料\r\n\r\nLiteral **source** 😀.\r\n"
        let file = analyses.appendingPathComponent("Source.md")
        try Data(source.utf8).write(to: file)
        let secondSource = "# Second synthetic material\n\nKeep both captured Notes.\n"
        try Data(secondSource.utf8).write(to: analyses.appendingPathComponent("Second.md"))
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics,
                outputURL: works, portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Chat Material Fixture")
            let preference = ChatSidebarPreferenceFixture(enabled: true)
            defer { preference.cleanup() }
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id, chatSidebarPreferences: preference.preferences)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let chat = try #require(window.chatController)
            try await wait { chat.isLoaded }
            let target = try #require(chat.selectedID)
            chat.editDraft("Discuss the supplied material.")
            chat.newConversation()
            let other = try #require(chat.selectedID)
            let item = SidebarNoteDragItem(
                .init(
                    documentID: .init(
                        vaultID: note.reference.vaultID,
                        relativePath: note.reference.relativePath), stableNoteID: try #require(note.reference.stableNoteID.flatMap(UUID.init(uuidString:))),
                    revision: note.fingerprint))
            let pasteboard = NSPasteboard(name: .init("note-drop-\(UUID())"))
            defer { pasteboard.releaseGlobally() }
            let payload = NSPasteboardItem()
            payload.setData(try JSONEncoder().encode(item), forType: .init(SidebarNoteDragItem.pasteboardType))
            payload.setString("file:///not-the-note.md", forType: .fileURL)
            pasteboard.writeObjects([payload])
            let captured = AgentChatPasteboardSnapshot.read(pasteboard)
            #expect(captured.count == 1)
            #expect(throws: AgentChatNoteMaterialError.self) { try AgentChatPasteboardSnapshot.resolve(item, in: []) }
            let libraryNote = try #require(window.notes.first { $0.relativePath == "Source.md" })
            let retainedIDs = chat.conversations.map(\.id)
            preference.preferences.isEnabled = false
            #expect(!window.canAddNotesToChat([item]) && !window.canAddLibraryNoteToChat(libraryNote))
            #expect(!window.addNotesToChat([item]) && !window.addLibraryNoteToChat(libraryNote))
            #expect(!(await window.addCurrentSelectionToChat()))
            await #expect(throws: ChatSidebarPresentationError.self) { try await window.addNoteToChat(note, conversationID: target) }
            #expect(chat.conversations.map(\.id) == retainedIDs && chat.selectedID == other)
            #expect(chat.conversations.first { $0.id == target }?.draft == "Discuss the supplied material.")
            #expect(chat.conversations.allSatisfy { $0.attachments.isEmpty && $0.messages.isEmpty })
            preference.preferences.isEnabled = true
            #expect(window.canAddNotesToChat([item]))
            #expect(window.canAddLibraryNoteToChat(libraryNote))
            let stale = SidebarNoteDragItem(
                .init(
                    documentID: item.documentID, stableNoteID: item.stableNoteID,
                    revision: .init(content: "a different version")))
            #expect(!window.canAddNotesToChat([stale]))
            #expect(!window.addNotesToChat([stale]))
            let secondNote = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Second.md" })
            let secondItem = SidebarNoteDragItem(
                .init(
                    documentID: .init(vaultID: secondNote.reference.vaultID, relativePath: secondNote.reference.relativePath),
                    stableNoteID: try #require(secondNote.reference.stableNoteID.flatMap(UUID.init(uuidString:))), revision: secondNote.fingerprint))
            // The composer captures the same admitted loader before scheduling
            // a multi-item transfer. Hide while its first stage is suspended.
            let addPreparedNote = try window.prepareChatNoteMaterials(in: target)
            var releaseFirstMaterial: CheckedContinuation<Void, Never>?
            defer { releaseFirstMaterial?.resume() }
            var preparedItems = 0
            let transferring = Task {
                await chat.addTransferredMaterials([.note(item), .note(secondItem)], origin: .drop, to: target) { captured in
                    preparedItems += 1
                    if preparedItems == 1 { await withCheckedContinuation { releaseFirstMaterial = $0 } }
                    try await addPreparedNote(AgentChatPasteboardSnapshot.resolve(captured, in: window.workspaceCatalog?.notes ?? []))
                }
            }
            try await wait { releaseFirstMaterial != nil }
            preference.preferences.isEnabled = false
            #expect(throws: ChatSidebarPresentationError.self) { try window.prepareChatNoteMaterials(in: other) }
            #expect(!window.addNotesToChat([secondItem]))
            #expect(chat.selectedID == other && chat.preparingMaterials == [target])
            releaseFirstMaterial?.resume()
            releaseFirstMaterial = nil
            await transferring.value
            let transferred = try #require(chat.conversations.first { $0.id == target })
            #expect(preparedItems == 2 && transferred.attachments.map(\.text) == [source, secondSource])
            #expect(transferred.draft == "Discuss the supplied material." && transferred.messages.isEmpty)
            #expect(chat.selectedID == other && chat.selected?.attachments.isEmpty == true)
            #expect(chat.preparingMaterials.isEmpty && chat.materialErrors[target] == nil && window.chatController === chat)
            preference.preferences.isEnabled = true
            chat.select(target)
            for attachment in transferred.attachments { chat.removeAttachment(attachment.id) }
            #expect(window.addLibraryNoteToChat(libraryNote))
            // A transfer admitted before hiding still finishes in its captured
            // conversation, while later requests are refused.
            preference.preferences.isEnabled = false
            #expect(chat.contextPresentationID != nil)
            chat.select(other)
            try await wait { chat.conversations.first { $0.id == target }?.attachments.isEmpty == false }
            let invalid = NSPasteboardItem()
            invalid.setData(Data("invalid".utf8), forType: .init(SidebarNoteDragItem.pasteboardType))
            invalid.setString("file:///not-the-note.md", forType: .fileURL)
            pasteboard.clearContents()
            pasteboard.writeObjects([invalid])
            #expect(AgentChatPasteboardSnapshot.read(pasteboard).isEmpty)
            #expect(chat.selectedID == other && chat.selected?.attachments.isEmpty == true)
            let material = try #require(chat.conversations.first { $0.id == target }?.attachments.first)
            #expect(material.text == source && material.fingerprint == DocumentFingerprint(data: Data(source.utf8)))
            #expect(!window.isChatSidebarEnabled && window.chatController === chat)
            preference.preferences.isEnabled = true
            #expect(material.extent == .wholeNote && material.source == .savedSource && material.vaultRole == .sourceCorpus)
            #expect(chat.conversations.first { $0.id == target }?.messages.isEmpty == true)
            #expect(!chat.attachContext([material], to: UUID()))
            await #expect(throws: AgentChatNoteMaterialError.self) { try await window.addNoteToChat(note, conversationID: UUID()) }
            try await chat.flushPersistence()
            chat.select(target)
            let fixture = repository.appendingPathComponent("Tests/Fixtures/agent-chat-runtime.py")
            chat.connect(executable: fixture, home: chat.runtimeHome, helper: fixture)
            try await wait { chat.canSend }
            chat.send()
            preference.preferences.isEnabled = false
            try await wait { chat.state == .ready && !chat.isBusy && chat.selected?.pendingMessageID == nil && chat.selected?.messages.isEmpty == false }
            #expect(window.chatController === chat && chat.connectionState == .ready && !window.isChatSidebarEnabled)
            preference.preferences.isEnabled = true
            let turn = try JSONDecoder().decode(MCPJSONValue.self, from: Data(contentsOf: chat.runtimeHome.appendingPathComponent("last-turn.json")))
            let input = try #require(turn.objectValue?["input"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
            #expect(input.contains(source) && input.contains("Extent: wholeNote") && input.contains("Source: savedSource"))
            #expect(input.contains("Vault role: source_corpus") && input.contains(material.fingerprint.sha256))
            let referenceLine = try #require(input.components(separatedBy: "\n").first { $0.hasPrefix("Reference: ") })
            let referenceURL = try #require(URL(string: String(referenceLine.dropFirst("Reference: ".count))))
            let reference = try #require(AgentChatReference.parse(referenceURL))
            #expect(reference.noteID == material.noteID && reference.vaultID == material.vaultID)
            #expect(reference.revision == material.fingerprint.sha256 && reference.line == material.sourceLine)
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            let snapshot = try #require(
                try await window.documentController.noteSnapshot(
                    .init(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)))
            window.documentController.installOpenedDocument(snapshot, vaultName: note.reference.vaultName, vaultRole: note.reference.vaultRole)
            let selected = try #require(window.documentController.selectedDocument)
            let session = window.documentController.session(for: selected.editingTarget)
            session.suppressAutosave = true
            session.preparePresentationMode(.read)
            window.rememberPresentationMode(.read)
            try await wait { window.presentedDocumentMode == .read }
            session.renderedReadFingerprint = DocumentFingerprint(content: source).sha256
            let passageRange = (source as NSString).range(of: "Literal")
            session.readSelection = .init(
                startLine: 7, endLine: 7, excerpt: "Literal",
                utf16LowerBound: passageRange.location, utf16UpperBound: NSMaxRange(passageRange))
            var releaseSelection: CheckedContinuation<Bool, Never>?
            defer { releaseSelection?.resume(returning: false) }
            var didContinueSelection = false
            let ask = Task {
                try await window.runSelectionInquiry(
                    .ask,
                    validate: {
                        await withCheckedContinuation { releaseSelection = $0 }
                    }
                ) { didContinueSelection = true }
            }
            try await wait { releaseSelection != nil }
            // A hidden Chat has no active destination. Ask Agent must capture
            // a new conversation only after validation succeeds, rather than
            // preparing the previously selected conversation.
            #expect(chat.preparingMaterials.isEmpty)
            chat.select(other)
            releaseSelection?.resume(returning: true)
            releaseSelection = nil
            #expect(try await ask.value == nil && !didContinueSelection)
            #expect(chat.selectedID == other && chat.preparingMaterials.isEmpty)
            #expect(chat.conversations.first { $0.id == target }?.attachments.isEmpty == true)
            #expect(chat.selected?.attachments.isEmpty == true)
            chat.select(target)
            _ = try await window.runSelectionInquiry(.ask, validate: { true }) { didContinueSelection = true }
            let selectionConversationID = try #require(chat.selectedID)
            #expect(selectionConversationID != target && selectionConversationID != other)
            #expect(didContinueSelection && chat.selected?.attachments.first?.text == "Literal")
            #expect(chat.preparingMaterials.isEmpty)
            chat.removeAttachment(try #require(chat.selected?.attachments.first?.id))
            session.readSelection = nil
            session.editingSource = "Unsaved source that must never be replaced by the saved Note."
            await #expect(throws: AgentChatNoteMaterialError.self) { try await window.addNoteToChat(note, conversationID: other) }
            #expect(chat.conversations.first { $0.id == other }?.attachments.isEmpty == true)
            #expect(session.editingSource.hasPrefix("Unsaved source"))
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            await chat.disconnect()
            // Both the global menu and the composer call this Window-owned
            // entry. Even a failed capture participates in the same preparation
            // scope; it never consumes a draft or creates an empty replacement.
            chat.editDraft("Keep @selection while source selection is unavailable")
            var preparationStates: [Set<UUID>] = []
            let preparationObservation = chat.$preparingMaterials.sink { preparationStates.append($0) }
            let retainedConversationIDs = chat.conversations.map(\.id)
            #expect(!(await window.addCurrentSelectionToChat()))
            #expect(preparationStates.contains([selectionConversationID]) && chat.preparingMaterials.isEmpty)
            #expect(chat.selected?.draft == "Keep @selection while source selection is unavailable")
            #expect(chat.conversations.map(\.id) == retainedConversationIDs)
            preparationObservation.cancel()
            chat.setArchived(selectionConversationID, archived: true)
            #expect(chat.selected?.isAvailable == false)
            #expect(!(await window.addCurrentSelectionToChat()))
            #expect(chat.selectedID == selectionConversationID && chat.conversations.map(\.id) == retainedConversationIDs)
            #expect(chat.selected?.draft == "Keep @selection while source selection is unavailable")
            chat.deleteConversation(selectionConversationID)
            let remainingConversationIDs = chat.conversations.map(\.id)
            #expect(chat.selectedID == nil)
            #expect(!(await window.addCurrentSelectionToChat()))
            #expect(chat.selectedID == nil && chat.conversations.map(\.id) == remainingConversationIDs)
            try await chat.flushPersistence()
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }

    @Test("An unsupported archive stays byte-unchanged and cannot be loaded as the current material schema")
    func archiveBoundary() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/agent-chat-evolution/material-archive-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = AgentChatStorage(root: root)
        try await storage.save([.init(triptychID: UUID())])
        let url = root.appendingPathComponent("conversations.json")
        var archive = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        archive["version"] = 9
        let old = try JSONSerialization.data(withJSONObject: archive)
        try old.write(to: url)
        await #expect(throws: CocoaError.self) { try await storage.load() }
        #expect(try Data(contentsOf: url) == old)
    }
}
