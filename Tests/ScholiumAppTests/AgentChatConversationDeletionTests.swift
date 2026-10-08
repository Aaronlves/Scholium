import AppKit
import Foundation
import PDFKit
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Conversation material deletion", .serialized)
@MainActor
struct AgentChatConversationDeletionTests {
    @Test("Deleting archived history releases draft, queue and message copies while a branch retains shared material")
    func removesOnlyUnreferencedCopies() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root, toolHandler: success)
        try #require(await controller.waitUntilLoaded())
        let sourceID = try #require(controller.selectedID)
        var materials: [AgentChatLocalMaterial] = []
        for index in 0..<6 {
            let source = root.appendingPathComponent("source-\(index).txt")
            try Data("Retained source \(index). 中文。\n".utf8).write(to: source)
            materials.append(try await controller.materialStore.stage(source))
        }
        let urls = try await previewURLs(materials, controller: controller)
        let bytes = try urls.map { try Data(contentsOf: $0) }
        controller.update(in: sourceID) {
            $0.localMaterials = [materials[0], materials[3]]
            $0.queuedMessages = [.init(role: .user, text: "Queued request", localMaterials: [materials[1], materials[4]])]
            $0.messages = [.init(role: .user, text: "Sent request", localMaterials: [materials[2], materials[5]])]
        }
        var branch = AgentChatConversation(triptychID: controller.triptychID)
        branch.branchOrigin = .init(conversationID: sourceID, turnID: "ended-source-turn")
        branch.localMaterials = [materials[4]]
        branch.queuedMessages = [.init(role: .user, text: "Branch queue", localMaterials: [materials[5]])]
        branch.messages = [.init(role: .user, text: "Inherited request", localMaterials: [materials[3]])]
        controller.conversations.append(branch)
        controller.executions[branch.id] = .init()
        controller.setArchived(sourceID, archived: true)
        try await controller.flushPersistence()

        controller.deleteConversation(sourceID)
        try await eventually { urls.prefix(3).allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        let stored = try await history(controller, root: root).load()
        #expect(!stored.contains { $0.id == sourceID })
        #expect(stored.first { $0.id == branch.id } == branch)
        for index in 3..<6 { #expect(try Data(contentsOf: urls[index]) == bytes[index]) }
        for index in 0..<6 {
            #expect(try Data(contentsOf: root.appendingPathComponent("source-\(index).txt")) == bytes[index])
        }

        controller.setArchived(branch.id, archived: true)
        controller.deleteConversation(branch.id)
        try await eventually { urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        #expect(try await history(controller, root: root).load().isEmpty)
    }

    @Test("Deletion removes retained PDF page images and converted image copies without altering the original PDF")
    func removesAllRepresentations() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root, toolHandler: success)
        try #require(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 30, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let image = NSImage(size: NSSize(width: 20, height: 30))
        image.addRepresentation(bitmap)
        let pdf = PDFDocument()
        pdf.insert(try #require(PDFPage(image: image)), at: 0)
        pdf.insert(try #require(PDFPage(image: image)), at: 1)
        let source = root.appendingPathComponent("scanned.pdf")
        let original = try #require(pdf.dataRepresentation())
        try original.write(to: source)
        await controller.addLocalFiles([source], to: id)
        let suppliedPDF = try #require(controller.selected?.localMaterials.first)
        try #require(await controller.usePDFPages("1-2", from: suppliedPDF, in: id))
        let pages = try #require(controller.selected?.localMaterials.first)
        #expect(pages.pageImages.count == 2)
        let tiff = try #require(bitmap.representation(using: .tiff, properties: [:]))
        await controller.addTransferredMaterials([.image(tiff)], origin: .clipboard, to: id) { _ in
            Issue.record("A captured image cannot add a Note")
        }
        let captured = try #require(controller.selected?.localMaterials.last)
        #expect(captured.capturedFileName != nil && captured.storedFileName != captured.capturedFileName)
        let materialRoot = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("Materials")
        let copies = try FileManager.default.contentsOfDirectory(at: materialRoot, includingPropertiesForKeys: nil)
        #expect(copies.count == 5)
        controller.setArchived(id, archived: true)
        try await controller.flushPersistence()

        controller.deleteConversation(id)
        try await eventually { copies.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) } }
        #expect(try Data(contentsOf: source) == original)
        #expect(try await history(controller, root: root).load().isEmpty)
    }

    @Test("A failed deletion save preserves copies until explicit retry or later autosave commits the deletion", arguments: [false, true])
    func failedSavePreservesCopies(retryExplicitly: Bool) async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        let gate = ConversationDeletionSaveGate(storage: storage)
        let controller = AgentChatController(
            triptychID: triptychID, root: root,
            workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
            saveHistory: { try await gate.save($0) }, toolHandler: { request, _ in success(request) })
        try #require(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        let source = root.appendingPathComponent("source.txt")
        let bytes = Data("Preserve this supplied text.\n".utf8)
        try bytes.write(to: source)
        await controller.addLocalFiles([source], to: id)
        let material = try #require(controller.selected?.localMaterials.first)
        let copy = try await controller.previewLocalMaterial(material)
        controller.setArchived(id, archived: true)
        try await controller.flushPersistence()
        let before = try await storage.load()
        let expectedError = String(localized: "Conversation not saved: \(CocoaError(.fileWriteOutOfSpace).localizedDescription)")
        gate.failFollowingSaves = true

        controller.deleteConversation(id)
        try await eventually { controller.historySaveError == expectedError }
        await controller.persistenceTask?.value
        #expect(controller.connectionError == nil && controller.materialCleanupError == nil)
        #expect(try Data(contentsOf: copy) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try await storage.load() == before)

        gate.failFollowingSaves = false
        if retryExplicitly {
            controller.retryHistorySave()
        } else {
            controller.newConversation()
            controller.editDraft("An ordinary edit retries the retained deletion")
        }
        try await eventually { !FileManager.default.fileExists(atPath: copy.path) && !controller.isRetryingHistorySave }
        await controller.persistenceTask?.value
        #expect(controller.historySaveError == nil && controller.materialCleanupError == nil)
        #expect(!(try await storage.load()).contains { $0.id == id })
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test("Deletion recovery retains references added before or during its successful save", arguments: [false, true])
    func recoveryPreservesNewReferences(referenceDuringSave: Bool) async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        let gate = ConversationDeletionSaveGate(storage: storage)
        defer { gate.finish(failure: true) }
        let controller = AgentChatController(
            triptychID: triptychID, root: root,
            workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
            saveHistory: { try await gate.save($0) }, toolHandler: { request, _ in success(request) })
        try #require(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        let source = root.appendingPathComponent("reused.txt")
        let bytes = Data("Retained by a newer conversation.\n".utf8)
        try bytes.write(to: source)
        await controller.addLocalFiles([source], to: id)
        let material = try #require(controller.selected?.localMaterials.first)
        let copy = try await controller.previewLocalMaterial(material)
        controller.setArchived(id, archived: true)
        try await controller.flushPersistence()
        gate.failFollowingSaves = true
        controller.deleteConversation(id)
        try await eventually { controller.historySaveError != nil }

        gate.failFollowingSaves = false
        if referenceDuringSave {
            gate.pauseNextSave = true
            controller.retryHistorySave()
            try await eventually { gate.isWaiting }
        }
        controller.newConversation()
        let newID = try #require(controller.selectedID)
        controller.update { $0.localMaterials = [material] }
        if referenceDuringSave { gate.finish() } else { controller.retryHistorySave() }
        try await eventually { !controller.isRetryingHistorySave }
        #expect(try Data(contentsOf: copy) == bytes)
        try await controller.flushPersistence()
        #expect((try await storage.load()).first { $0.id == newID }?.localMaterials == [material])

        controller.update { $0.localMaterials = [] }
        try await controller.flushPersistence()
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(controller.historySaveError == nil && controller.materialCleanupError == nil)
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test("Cleanup failure reports a committed deletion separately from a failed history save")
    func cleanupFailureRetainsCopiesAndNamesCommittedDeletion() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = fixtureChatController(triptychID: UUID(), root: root, toolHandler: success)
        try #require(await controller.waitUntilLoaded())
        let id = try #require(controller.selectedID)
        let source = root.appendingPathComponent("source.txt")
        let bytes = Data("Retained despite cleanup failure.\n".utf8)
        try bytes.write(to: source)
        await controller.addLocalFiles([source], to: id)
        let material = try #require(controller.selected?.localMaterials.first)
        let name = try #require(material.storedFileName)
        let materialRoot = root.appendingPathComponent(controller.triptychID.uuidString).appendingPathComponent("Materials")
        let preserved = root.appendingPathComponent("preserved-materials")
        controller.setArchived(id, archived: true)
        try await controller.flushPersistence()
        try FileManager.default.moveItem(at: materialRoot, to: preserved)
        try Data("Blocks directory creation".utf8).write(to: materialRoot)
        let expectedPrefix = String(localized: "Conversation deleted, but its retained material could not be removed: \("")")

        controller.deleteConversation(id)
        try await eventually { controller.materialCleanupError?.hasPrefix(expectedPrefix) == true }
        #expect(controller.historySaveError == nil && controller.connectionError == nil)
        #expect(try await history(controller, root: root).load().isEmpty)
        #expect(try Data(contentsOf: preserved.appendingPathComponent(name)) == bytes)
        #expect(try Data(contentsOf: source) == bytes)

        // A later successful save retries the retained cleanup obligation,
        // clearing its diagnosis only once the copy is actually released.
        try FileManager.default.removeItem(at: materialRoot)
        try FileManager.default.moveItem(at: preserved, to: materialRoot)
        try await controller.flushPersistence()
        #expect(controller.materialCleanupError == nil)
        #expect(!FileManager.default.fileExists(atPath: materialRoot.appendingPathComponent(name).path))
        #expect(try Data(contentsOf: source) == bytes)
    }

    @Test("A branch removal during deletion cannot erase material still referenced by the committed deletion snapshot")
    func concurrentBranchRemovalPreservesSavedReference() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        let gate = ConversationDeletionSaveGate(storage: storage)
        defer { gate.finish(failure: true) }
        let controller = AgentChatController(
            triptychID: triptychID, root: root,
            workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
            saveHistory: { try await gate.save($0) }, toolHandler: { request, _ in success(request) })
        try #require(await controller.waitUntilLoaded())
        let sourceID = try #require(controller.selectedID)
        let source = root.appendingPathComponent("shared.txt")
        let bytes = Data("Shared retained source.\n".utf8)
        try bytes.write(to: source)
        await controller.addLocalFiles([source], to: sourceID)
        let material = try #require(controller.selected?.localMaterials.first)
        let copy = try await controller.previewLocalMaterial(material)
        var branch = AgentChatConversation(triptychID: triptychID)
        branch.branchOrigin = .init(conversationID: sourceID, turnID: "ended-source-turn")
        branch.localMaterials = [material]
        controller.conversations.append(branch)
        controller.executions[branch.id] = .init()
        controller.setArchived(sourceID, archived: true)
        try await controller.flushPersistence()
        gate.pauseNextSave = true

        controller.deleteConversation(sourceID)
        try await eventually { gate.isWaiting }
        controller.removeLocalMaterial(material.id, from: branch.id)
        gate.failFollowingSaves = true
        gate.finish()
        try await eventually { controller.materialErrors[branch.id] != nil }
        await controller.persistenceTask?.value
        let stored = try await storage.load()
        #expect(!stored.contains { $0.id == sourceID })
        #expect(stored.first { $0.id == branch.id }?.localMaterials == [material])
        #expect(controller.conversations.first { $0.id == branch.id }?.localMaterials.isEmpty == true)
        #expect(try Data(contentsOf: copy) == bytes)
    }

    @Test("Earlier saves and queued reattachments cannot erase a later committed material reference", arguments: [false, true])
    func queuedSnapshotsProtectMaterial(deletionPrecedesHeldSave: Bool) async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let triptychID = UUID()
        let storage = AgentChatStorage(root: root.appendingPathComponent(triptychID.uuidString))
        let gate = ConversationDeletionSaveGate(storage: storage)
        defer { gate.finish(failure: true) }
        let controller = AgentChatController(
            triptychID: triptychID, root: root,
            workspaceDirectory: { try agentChatFixtureWorkspace(root: root, triptychID: triptychID) },
            saveHistory: { try await gate.save($0) }, toolHandler: { request, _ in success(request) })
        try #require(await controller.waitUntilLoaded())
        let originalID = try #require(controller.selectedID)
        let source = root.appendingPathComponent("queued-reference.txt")
        let bytes = Data("A committed queued snapshot must retain these bytes.\n".utf8)
        try bytes.write(to: source)
        let material = try await controller.materialStore.stage(source)
        let copy = try await controller.previewLocalMaterial(material)
        var oldestSave: Task<Void, Error>?
        if deletionPrecedesHeldSave {
            controller.update { $0.localMaterials = [material] }
            controller.setArchived(originalID, archived: true)
        }
        try await controller.flushPersistence()
        gate.pauseNextSave = true
        if deletionPrecedesHeldSave {
            // S0 already owns cleanup candidates. A queued new conversation
            // will regain this immutable material before S0 completes.
            controller.deleteConversation(originalID)
        } else {
            // S0 predates the attachment and deletion; it may never process
            // cleanup candidates added after its snapshot was enqueued.
            oldestSave = Task { try await controller.flushPersistence() }
        }
        try await eventually { gate.isWaiting }
        if deletionPrecedesHeldSave { controller.newConversation() }
        let retainedID = try #require(controller.selectedID)
        controller.update { $0.localMaterials = [material] }
        let referencingSave = Task { try await controller.flushPersistence() }
        try await eventually { controller.pendingHistorySaveReferences.count == 2 }

        controller.setArchived(retainedID, archived: true)
        gate.shouldFail = { !$0.contains { $0.id == retainedID } }
        controller.deleteConversation(retainedID)
        try await eventually { controller.pendingHistorySaveReferences.count == 3 }
        gate.finish()
        try await oldestSave?.value
        try await referencingSave.value
        await controller.persistenceTask?.value

        #expect(controller.historySaveError != nil)
        #expect(controller.pendingHistorySaveReferences.isEmpty)
        #expect(controller.conversations.allSatisfy { $0.id != retainedID })
        #expect((try await storage.load()).first { $0.id == retainedID }?.localMaterials == [material])
        #expect(try Data(contentsOf: copy) == bytes)
        #expect(try Data(contentsOf: source) == bytes)

        gate.shouldFail = nil
        controller.retryHistorySave()
        try await eventually { !controller.isRetryingHistorySave }
        await controller.persistenceTask?.value
        #expect(controller.historySaveError == nil && controller.materialCleanupError == nil)
        #expect(controller.pendingDeletionMaterials.isEmpty && controller.pendingHistorySaveReferences.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(try await storage.load().isEmpty)
        #expect(try Data(contentsOf: source) == bytes)
    }

    private func fixtureRoot() throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/deletion-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func history(_ controller: AgentChatController, root: URL) -> AgentChatStorage {
        .init(root: root.appendingPathComponent(controller.triptychID.uuidString))
    }

    private func previewURLs(_ materials: [AgentChatLocalMaterial], controller: AgentChatController) async throws -> [URL] {
        var urls: [URL] = []
        for material in materials { urls.append(try await controller.previewLocalMaterial(material)) }
        return urls
    }

    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            try #require(ContinuousClock.now < deadline, "Conversation deletion did not reach the expected state")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func success(_ request: ScholiumMCPBridgeRequest) -> ScholiumMCPBridgeResponse {
        try! .init(requestID: request.requestID, result: .object([:]))
    }
}

@MainActor
private final class ConversationDeletionSaveGate {
    let storage: AgentChatStorage
    var pauseNextSave = false
    var failFollowingSaves = false
    var shouldFail: (([AgentChatConversation]) -> Bool)?
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    init(storage: AgentChatStorage) { self.storage = storage }

    func save(_ values: [AgentChatConversation]) async throws {
        if pauseNextSave {
            pauseNextSave = false
            try await withCheckedThrowingContinuation { continuation = $0 }
        } else if failFollowingSaves || shouldFail?(values) == true {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try await storage.save(values)
    }

    func finish(failure: Bool = false) {
        let waiting = continuation
        continuation = nil
        if failure { waiting?.resume(throwing: CocoaError(.fileWriteOutOfSpace)) } else { waiting?.resume() }
    }
}
