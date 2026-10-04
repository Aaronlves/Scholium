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

    @Test("A failed deletion save preserves every staged byte and the saved archived conversation")
    func failedSavePreservesCopies() async throws {
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
        try await eventually { controller.connectionError == expectedError }
        await controller.persistenceTask?.value
        #expect(try Data(contentsOf: copy) == bytes)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try await storage.load() == before)
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
        try await eventually { controller.connectionError?.hasPrefix(expectedPrefix) == true }
        #expect(try await history(controller, root: root).load().isEmpty)
        #expect(try Data(contentsOf: preserved.appendingPathComponent(name)) == bytes)
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
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }

    init(storage: AgentChatStorage) { self.storage = storage }

    func save(_ values: [AgentChatConversation]) async throws {
        if pauseNextSave {
            pauseNextSave = false
            try await withCheckedThrowingContinuation { continuation = $0 }
        } else if failFollowingSaves {
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
