import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Unused Chat material cleanup", .timeLimit(.minutes(1)))
@MainActor
struct AgentChatUnusedMaterialCleanupTests {
    @Test("Durable history protects capture and page siblings after an unsaved live removal")
    func durableReferencesSurviveLiveRemoval() async throws {
        try await withFixture { fixture in
            let capture = try fixture.makeMaterial(captured: true)
            let pages = try fixture.makeMaterial(pageImage: true)
            let owner = try #require(fixture.controller.selectedID)
            fixture.controller.update(in: owner) { $0.localMaterials = [capture, pages] }
            try await fixture.controller.flushPersistence()
            fixture.controller.update(in: owner) { $0.localMaterials = [] }

            let plan = try await fixture.controller.unusedChatMaterialCleanupPlan()
            #expect(plan.files.fileCount == 0 && plan.files.preservedFiles == 4)
            // An empty protected cohort proves the controller route without
            // dispatching any native Trash operation.
            let result = try await fixture.controller.moveUnusedChatMaterialsToTrash(plan)
            #expect(result.movedFiles == 0 && result.preservedFiles == 4)
            #expect(result.resultingTrashURLs.isEmpty)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test("Current drafts, queued input, messages and archived history protect their complete material groups")
    func liveReferencesProtectEveryOwner() async throws {
        try await withFixture { fixture in
            let draft = try fixture.makeMaterial(captured: true)
            let queued = try fixture.makeMaterial(pageImage: true)
            let sent = try fixture.makeMaterial()
            let archived = try fixture.makeMaterial()
            let unused = try fixture.makeMaterial()
            let owner = try #require(fixture.controller.selectedID)
            fixture.controller.update(in: owner) {
                $0.localMaterials = [draft]
                $0.queuedMessages = [.init(id: "queued", role: .user, text: "Queued input", localMaterials: [queued])]
                $0.messages = [.init(id: "sent", role: .user, text: "Retained input", localMaterials: [sent])]
            }
            var archivedConversation = AgentChatConversation(triptychID: fixture.triptychID)
            archivedConversation.archivedAt = Date()
            archivedConversation.localMaterials = [archived]
            fixture.controller.conversations.append(archivedConversation)

            let plan = try await fixture.controller.unusedChatMaterialCleanupPlan()
            #expect(plan.files.candidateFileNames == [try #require(unused.storedFileName)])
            #expect(plan.files.preservedFiles == 6)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test("Cleanup admission blocks material preparation and protects references added during the history await")
    func referenceAndAdmissionRace() async throws {
        try await withFixture { fixture in
            let pendingSave = try fixture.makeMaterial(captured: true)
            let pendingDeletion = try fixture.makeMaterial()
            let gate = UnusedMaterialHistoryGate()
            defer { gate.release() }
            fixture.reader.gate = gate
            var entered = gate.entries.makeAsyncIterator()
            let planning = Task { try await fixture.controller.unusedChatMaterialCleanupPlan() }
            _ = await entered.next()
            #expect(fixture.controller.isCleaningUnusedMaterials)

            let owner = try #require(fixture.controller.selectedID)
            var prepared = false
            let admitted = await fixture.controller.performMaterialPreparation(in: owner) { prepared = true }
            #expect(!admitted && !prepared)
            fixture.controller.pendingHistorySaveReferences[UUID()] = [pendingSave.id]
            fixture.controller.pendingDeletionMaterials[pendingDeletion.id] = pendingDeletion
            gate.release()
            let plan = try await planning.value
            #expect(plan.files.fileCount == 0 && plan.files.preservedFiles == 3)
            #expect(!fixture.controller.isCleaningUnusedMaterials)
            fixture.reader.gate = nil
            let admittedAfterCleanup = await fixture.controller.performMaterialPreparation(in: owner) { prepared = true }
            #expect(admittedAfterCleanup && prepared)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test(
        "Active execution, preparation and tentative archive deletion reject cleanup before file effects", arguments: ["preparation", "archive", "execution"])
    func busyOwnersRejectCleanup(ownerKind: String) async throws {
        try await withFixture { fixture in
            _ = try fixture.makeMaterial()
            let plan = try await fixture.controller.unusedChatMaterialCleanupPlan()
            let owner = try #require(fixture.controller.selectedID)
            if ownerKind == "archive" {
                fixture.controller.archivedChatCleanup = ArchivedChatCleanupTransaction(retained: [])
            } else if ownerKind == "execution" {
                fixture.controller.executions[owner]?.sendingMessageID = "synthetic-active-send"
            } else {
                fixture.controller.preparingMaterials.insert(UUID())
            }
            defer {
                fixture.controller.preparingMaterials.removeAll()
                fixture.controller.archivedChatCleanup = nil
                fixture.controller.executions[owner]?.sendingMessageID = nil
            }
            await #expect {
                _ = try await fixture.controller.unusedChatMaterialCleanupPlan()
            } throws: { error in
                if case UnusedChatMaterialCleanupError.busy = error { return true }
                return false
            }
            await #expect {
                _ = try await fixture.controller.moveUnusedChatMaterialsToTrash(plan)
            } throws: { error in
                if case UnusedChatMaterialCleanupError.busy = error { return true }
                return false
            }
            #expect(!fixture.controller.isCleaningUnusedMaterials)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test("Missing durable-history authority fails closed and releases cleanup admission", arguments: [false, true])
    func unreadableHistoryPreservesMaterials(unsupportedFormat: Bool) async throws {
        try await withFixture { fixture in
            _ = try fixture.makeMaterial()
            let bytes = Data((unsupportedFormat ? "{\"version\":99,\"conversations\":[]}" : "{broken-history").utf8)
            try bytes.write(to: fixture.historyURL)
            await #expect(throws: (any Error).self) {
                _ = try await fixture.controller.unusedChatMaterialCleanupPlan()
            }
            #expect(!fixture.controller.isCleaningUnusedMaterials)
            #expect(try Data(contentsOf: fixture.historyURL) == bytes)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test("A new reference invalidates the inspected cohort before any Trash dispatch")
    func changedReferencesInvalidatePlan() async throws {
        try await withFixture { fixture in
            let material = try fixture.makeMaterial()
            let plan = try await fixture.controller.unusedChatMaterialCleanupPlan()
            #expect(plan.files.fileCount == 1)
            let owner = try #require(fixture.controller.selectedID)
            fixture.controller.update(in: owner) { $0.localMaterials = [material] }
            await #expect(throws: AgentChatMaterialCleanupError.changed) {
                _ = try await fixture.controller.moveUnusedChatMaterialsToTrash(plan)
            }
            #expect(!fixture.controller.isCleaningUnusedMaterials)
            try fixture.expectAllBytesUnchanged()
        }
    }

    @Test("Changed file bytes and a foreign Triptych cannot reuse cleanup confirmation")
    func changedBytesAndTargetInvalidatePlan() async throws {
        try await withFixture { fixture in
            let material = try fixture.makeMaterial()
            let plan = try await fixture.controller.unusedChatMaterialCleanupPlan()
            let foreign = UnusedChatMaterialCleanupPlan(triptychID: UUID(), files: plan.files)
            await #expect {
                _ = try await fixture.controller.moveUnusedChatMaterialsToTrash(foreign)
            } throws: { error in
                if case UnusedChatMaterialCleanupError.wrongTriptych = error { return true }
                return false
            }
            try fixture.expectAllBytesUnchanged()

            let url = fixture.materialsURL.appendingPathComponent(try #require(material.storedFileName))
            let changed = Data("A concurrent writer's newer copy".utf8)
            try changed.write(to: url)
            await #expect(throws: AgentChatMaterialCleanupError.changed) {
                _ = try await fixture.controller.moveUnusedChatMaterialsToTrash(plan)
            }
            #expect(try Data(contentsOf: url) == changed)
            #expect(!fixture.controller.isCleaningUnusedMaterials)
        }
    }

    @Test("Cancellation during durable inspection preserves files and releases admission")
    func cancelledHistoryReadPreservesMaterials() async throws {
        try await withFixture { fixture in
            _ = try fixture.makeMaterial()
            let gate = UnusedMaterialHistoryGate()
            defer { gate.release() }
            fixture.reader.gate = gate
            var entered = gate.entries.makeAsyncIterator()
            let planning = Task { try await fixture.controller.unusedChatMaterialCleanupPlan() }
            _ = await entered.next()
            planning.cancel()
            gate.release()
            await #expect(throws: CancellationError.self) { _ = try await planning.value }
            #expect(!fixture.controller.isCleaningUnusedMaterials)
            try fixture.expectAllBytesUnchanged()
        }
    }

    private func withFixture(_ operation: @MainActor (UnusedChatMaterialFixture) async throws -> Void) async throws {
        let fixture = try UnusedChatMaterialFixture()
        defer { fixture.remove() }
        do {
            try #require(await fixture.controller.waitUntilLoaded())
            try await fixture.controller.flushPersistence()
            try await operation(fixture)
        } catch {
            fixture.reader.gate?.release()
            fixture.controller.scheduledPersistenceTask?.cancel()
            await fixture.controller.persistenceTask?.value
            throw error
        }
        fixture.controller.scheduledPersistenceTask?.cancel()
        await fixture.controller.persistenceTask?.value
    }
}

@MainActor
private final class UnusedChatMaterialFixture {
    let root: URL
    let triptychID: UUID
    let materialsURL: URL
    let historyURL: URL
    let controller: AgentChatController
    let reader: UnusedMaterialHistoryReader
    private let defaults: UserDefaults
    private let suiteName: String
    private var expectedFiles: [URL: Data] = [:]

    init() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/unused-materials-\(UUID())")
        self.root = root
        let triptychID = UUID()
        self.triptychID = triptychID
        let chatRoot = root.appendingPathComponent("Chat")
        let historyRoot = chatRoot.appendingPathComponent(triptychID.uuidString)
        materialsURL = historyRoot.appendingPathComponent("Materials")
        historyURL = historyRoot.appendingPathComponent("conversations.json")
        try FileManager.default.createDirectory(at: materialsURL, withIntermediateDirectories: true)
        let suiteName = "scholium.qa.unused-materials.\(UUID())"
        self.suiteName = suiteName
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        self.defaults = defaults
        let reader = UnusedMaterialHistoryReader(storage: AgentChatStorage(root: historyRoot))
        self.reader = reader
        let workspace = root
        controller = AgentChatController(
            triptychID: triptychID, root: chatRoot, workspaceDirectory: { workspace },
            methodDefaults: defaults, contextAccessPreferences: AgentContextAccessPreferences(defaults: defaults),
            loadHistory: { try await reader.load() },
            toolHandler: { request, _ in
                Issue.record("Chat material cleanup must not invoke a research tool")
                return try! .init(requestID: request.requestID, result: .object([:]))
            })
    }

    func makeMaterial(captured: Bool = false, pageImage: Bool = false) throws -> AgentChatLocalMaterial {
        let id = UUID()
        let bytes = Data("Synthetic immutable material \(id)".utf8)
        let name = id.uuidString + (pageImage ? ".pdf" : captured ? ".png" : ".txt")
        let source = root.appendingPathComponent("source-\(id).txt")
        try retain(bytes, at: source)
        try retain(bytes, at: materialsURL.appendingPathComponent(name))
        let capturedName = captured ? id.uuidString + ".tiff" : nil
        if let capturedName { try retain(bytes, at: materialsURL.appendingPathComponent(capturedName)) }
        let pageName = id.uuidString + ".page-2.png"
        if pageImage { try retain(bytes, at: materialsURL.appendingPathComponent(pageName)) }
        return .init(
            id: id, source: .file(source), storedFileName: name, fingerprint: .init(data: bytes),
            kind: pageImage ? .pdf : captured ? .image : .text,
            pageImages: pageImage ? [.init(number: 2, storedFileName: pageName, fingerprint: .init(data: bytes))] : [],
            capturedFileName: capturedName, capturedFingerprint: captured ? .init(data: bytes) : nil)
    }

    func expectAllBytesUnchanged() throws {
        for (url, bytes) in expectedFiles { #expect(try Data(contentsOf: url) == bytes) }
    }

    private func retain(_ bytes: Data, at url: URL) throws {
        try bytes.write(to: url)
        expectedFiles[url] = bytes
    }

    func remove() {
        controller.scheduledPersistenceTask?.cancel()
        reader.gate?.release()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class UnusedMaterialHistoryReader {
    let storage: AgentChatStorage
    var gate: UnusedMaterialHistoryGate?
    init(storage: AgentChatStorage) { self.storage = storage }
    func load() async throws -> AgentChatHistorySnapshot {
        if let gate { await gate.wait() }
        return try await storage.loadSnapshot()
    }
}

@MainActor
private final class UnusedMaterialHistoryGate {
    let entries: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var waiter: CheckedContinuation<Void, Never>?
    private var released = false

    init() { (entries, continuation) = AsyncStream.makeStream() }

    func wait() async {
        continuation.yield(())
        guard !released else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.release() }
        }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
        continuation.finish()
    }
}
