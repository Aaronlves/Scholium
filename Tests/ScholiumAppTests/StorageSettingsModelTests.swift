import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Storage Settings lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct StorageSettingsModelTests {
    @Test("Concurrent measurement joins one inventory read and retains the previous measurement on failure")
    func measurementSingleFlightAndFailure() async throws {
        let backend = StorageSettingsTestBackend()
        let gate = StorageSettingsTestGate()
        defer { gate.release() }
        var entered = gate.entries.makeAsyncIterator()
        let inventory = backend.sampleInventory
        backend.inventoryRead = {
            await gate.wait()
            return inventory
        }
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        let first = Task { await model.refreshInventory() }
        _ = await entered.next()
        let (joining, joined) = AsyncStream<Void>.makeStream()
        var joiningIterator = joining.makeAsyncIterator()
        let second = Task {
            joined.yield(())
            joined.finish()
            await model.refreshInventory()
        }
        _ = await joiningIterator.next()
        #expect(model.isMeasuring)
        #expect(backend.inventoryReads == 1)
        gate.release()
        await first.value
        await second.value
        #expect(model.inventory == backend.sampleInventory)
        #expect(model.measuredBytes == 37)
        #expect(model.unreadableEntries == 2 && model.skippedEntries == 1)
        backend.inventoryRead = { throw StorageSettingsTestFailure() }
        await model.refreshInventory()
        #expect(model.inventory == backend.sampleInventory)
        #expect(model.errorMessage != nil)
        #expect(!model.isMeasuring)
        backend.inventoryRead = { inventory }
        await model.refreshInventory()
        #expect(model.errorMessage == nil)
    }

    @Test("Clear and rebuild are separate confirmed operations pinned to the displayed Triptych", arguments: [ScholiumStorageAction.clearIndex, .rebuildIndex])
    func confirmedIndexActions(_ action: ScholiumStorageAction) async throws {
        let backend = StorageSettingsTestBackend()
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        let id = UUID()
        model.setPaneActive(true)
        model.selectTriptych(id: id, name: "Target Triptych")
        model.requestIndexAction(action)
        let cancelled = try #require(model.confirmation)
        #expect(backend.performed.isEmpty)
        model.dismissConfirmation()
        #expect(model.confirm(cancelled) == nil)
        #expect(backend.performed.isEmpty)
        model.requestIndexAction(action)
        let request = try #require(model.confirmation)
        let task = try #require(model.confirm(request))
        #expect(model.confirm(request) == nil)
        await task.value
        #expect(backend.performed.count == 1)
        #expect(backend.performed.first?.action == action)
        #expect(backend.performed.first?.triptychID == id)
        #expect(model.completedOperation == .storage(.init(action: action), triptychName: "Target Triptych"))
        #expect(!model.isPerforming && model.confirmation == nil)
    }

    @Test("An admitted operation survives navigation, retains partial results and prevents a second mutation")
    func operationSurvivesInactivePage() async throws {
        let backend = StorageSettingsTestBackend()
        let gate = StorageSettingsTestGate()
        defer { gate.release() }
        var entered = gate.entries.makeAsyncIterator()
        let result = ScholiumStorageOperationResult(
            action: .rebuildIndex,
            cleanup: .init(removedFiles: 3, removedBytes: 100, preservedFiles: 2, failedFiles: 1, busyDirectories: 1),
            warnings: ["Another owner retained a file."])
        backend.operation = { _, _ in
            await gate.wait()
            return result
        }
        let firstID = UUID()
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        model.setPaneActive(true)
        model.selectTriptych(id: firstID, name: "Original Target")
        model.requestIndexAction(.rebuildIndex)
        let confirmation = try #require(model.confirmation)
        let task = try #require(model.confirm(confirmation))
        _ = await entered.next()
        model.setPaneActive(false)
        model.selectTriptych(id: UUID(), name: "Another Target")
        model.setPaneActive(true)
        model.requestIndexAction(.clearIndex)
        await model.performSafeAction(.clearProjectionCache)
        #expect(model.isPerforming && model.confirmation == nil)
        #expect(backend.performed.count == 1)
        gate.release()
        await task.value
        #expect(backend.performed.first?.triptychID == firstID)
        #expect(model.completedOperation == .storage(result, triptychName: "Original Target"))
        #expect(model.inventory == backend.sampleInventory)
        #expect(!model.isPerforming)
    }

    @Test("Navigation cancels an unconfirmed archived-chat plan and rejects its late result")
    func archivedPreparationCannotCrossScope() async throws {
        let backend = StorageSettingsTestBackend()
        let gate = StorageSettingsTestGate()
        defer { gate.release() }
        var entered = gate.entries.makeAsyncIterator()
        let oldID = UUID()
        backend.archives = { id in
            await gate.wait()
            return .init(triptychID: id, conversationIDs: [UUID()], revision: "old", estimatedByteCount: 5)
        }
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        model.setPaneActive(true)
        model.selectTriptych(id: oldID, name: "Original")
        let preparation = Task { await model.prepareArchivedChatDeletion() }
        _ = await entered.next()
        model.setPaneActive(false)
        model.selectTriptych(id: UUID(), name: "Successor")
        model.setPaneActive(true)
        gate.release()
        await preparation.value
        #expect(model.confirmation == nil)
        #expect(!model.isBusy)
        #expect(backend.deletedPlans.isEmpty)
    }

    @Test("Archived deletion sends the exact prepared cohort and retains material-cleanup failure separately")
    func archivedDeletionUsesPreparedPlan() async throws {
        let backend = StorageSettingsTestBackend()
        let id = UUID()
        let plan = ArchivedChatCleanupPlan(triptychID: id, conversationIDs: [UUID(), UUID()], revision: "exact-revision", estimatedByteCount: 450)
        backend.archives = { _ in plan }
        let result = ArchivedChatCleanupResult(removedConversations: 2, materialCleanupIssue: "Materials are still in use.")
        backend.delete = { _ in result }
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        model.setPaneActive(true)
        model.selectTriptych(id: id, name: "Archive Target")
        await model.prepareArchivedChatDeletion()
        let request = try #require(model.confirmation)
        #expect(request.intent == .archivedChats(plan))
        #expect(backend.deletedPlans.isEmpty)
        let task = try #require(model.confirm(request))
        await task.value
        #expect(backend.deletedPlans == [plan])
        #expect(model.completedOperation == .archivedChats(result, triptychName: "Archive Target"))
    }

    @Test("Navigation or target changes cancel an unconfirmed unused-material inspection", arguments: [false, true])
    func unusedMaterialPreparationCannotCrossScope(changeTarget: Bool) async throws {
        let target = UUID()
        try await withMaterialPlan(triptychID: target) { plan in
            let backend = StorageSettingsTestBackend()
            let gate = StorageSettingsTestGate()
            defer { gate.release() }
            var entered = gate.entries.makeAsyncIterator()
            backend.unused = { _ in
                await gate.wait()
                return plan
            }
            let model = StorageSettingsModel(capabilities: backend.capabilities)
            model.setPaneActive(true)
            model.selectTriptych(id: target, name: "Inspected Target")
            let preparation = Task { await model.prepareUnusedChatMaterialCleanup() }
            _ = await entered.next()
            if changeTarget {
                model.selectTriptych(id: UUID(), name: "Successor")
            } else {
                model.setPaneActive(false)
                model.setPaneActive(true)
            }
            gate.release()
            await preparation.value
            #expect(model.confirmation == nil && !model.isBusy)
            #expect(backend.unusedInspections == [target])
            #expect(backend.trashedPlans.isEmpty)
        }
    }

    @Test("Unused-material confirmation requires the inspected Triptych and explicit admission")
    func unusedMaterialConfirmationKeepsExactTarget() async throws {
        let target = UUID()
        try await withMaterialPlan(triptychID: target) { plan in
            let backend = StorageSettingsTestBackend()
            let model = StorageSettingsModel(capabilities: backend.capabilities)
            model.setPaneActive(true)
            model.selectTriptych(id: target, name: "Material Target")
            backend.unused = { _ in .init(triptychID: UUID(), files: plan.files) }
            await model.prepareUnusedChatMaterialCleanup()
            #expect(model.confirmation == nil && backend.trashedPlans.isEmpty)
            backend.unused = { _ in plan }
            await model.prepareUnusedChatMaterialCleanup()
            let request = try #require(model.confirmation)
            #expect(request.intent == .unusedChatMaterials(plan))
            #expect(request.triptychID == target && backend.trashedPlans.isEmpty)
            model.dismissConfirmation()
            #expect(model.confirm(request) == nil && backend.trashedPlans.isEmpty)
        }
    }

    @Test("An admitted unused-material cleanup retains its target and partial outcome after navigation and measurement failure")
    func unusedMaterialPartialResultSurvivesNavigation() async throws {
        let target = UUID()
        try await withMaterialPlan(triptychID: target, count: 3) { plan in
            let backend = StorageSettingsTestBackend()
            let gate = StorageSettingsTestGate()
            defer { gate.release() }
            var entered = gate.entries.makeAsyncIterator()
            let result = AgentChatMaterialCleanupResult(
                movedFiles: 1, movedBytes: 7, preservedFiles: 2, failedFiles: 1, uncertainFiles: 1,
                retainedFileNames: ["retained-synthetic-copy.txt"],
                resultingTrashURLs: [URL(fileURLWithPath: "/synthetic-trash/confirmed-copy.txt")])
            backend.unused = { _ in plan }
            backend.trash = { _ in
                await gate.wait()
                return result
            }
            backend.inventoryRead = { throw StorageSettingsTestFailure() }
            let model = StorageSettingsModel(capabilities: backend.capabilities)
            model.setPaneActive(true)
            model.selectTriptych(id: target, name: "Original Material Target")
            await model.prepareUnusedChatMaterialCleanup()
            let request = try #require(model.confirmation)
            let operation = try #require(model.confirm(request))
            _ = await entered.next()
            model.setPaneActive(false)
            model.selectTriptych(id: UUID(), name: "Different Target")
            model.setPaneActive(true)
            await model.prepareUnusedChatMaterialCleanup()
            await model.prepareArchivedChatDeletion()
            #expect(model.isPerforming && model.confirmation == nil)
            #expect(backend.unusedInspections == [target])
            #expect(backend.trashedPlans == [plan] && backend.deletedPlans.isEmpty)
            gate.release()
            await operation.value
            #expect(model.completedOperation == .unusedChatMaterials(result, triptychName: "Original Material Target"))
            #expect(model.errorMessage != nil)
            #expect(!model.isPerforming && model.activityScope == .chat)
            #expect(backend.trashedPlans == [plan])
        }
    }

    @Test("Stopping an admitted cleanup is idempotent and retains its confirmed partial result")
    func stopUnusedMaterialCleanupKeepsPartialResult() async throws {
        let target = UUID()
        try await withMaterialPlan(triptychID: target, count: 2) { plan in
            let backend = StorageSettingsTestBackend()
            let gate = StorageSettingsTestGate()
            defer { gate.release() }
            var entered = gate.entries.makeAsyncIterator()
            var observedCancellation = false
            let result = AgentChatMaterialCleanupResult(
                movedFiles: 1, movedBytes: 7, preservedFiles: 1, wasCancelled: true,
                retainedFileNames: ["remaining-synthetic-copy.txt"],
                resultingTrashURLs: [URL(fileURLWithPath: "/synthetic-trash/confirmed-copy.txt")])
            backend.unused = { _ in plan }
            backend.trash = { _ in
                await gate.wait()
                observedCancellation = Task.isCancelled
                return result
            }
            let model = StorageSettingsModel(capabilities: backend.capabilities)
            model.setPaneActive(true)
            model.selectTriptych(id: target, name: "Stopped Target")
            await model.prepareUnusedChatMaterialCleanup()
            let request = try #require(model.confirmation)
            let operation = try #require(model.confirm(request))
            _ = await entered.next()
            #expect(model.canStopCleanup && model.isPerforming)
            model.stopCleanup()
            model.stopCleanup()
            #expect(!model.canStopCleanup && model.isPerforming)
            await operation.value
            #expect(observedCancellation)
            #expect(model.completedOperation == .unusedChatMaterials(result, triptychName: "Stopped Target"))
            #expect(!model.canStopCleanup && !model.isPerforming)
            #expect(model.errorMessage == nil && model.notice == nil)
            #expect(backend.trashedPlans == [plan])
        }
    }

    @Test("Safe cleanup has machine scope and errors never become a success result")
    func safeCleanupScopeAndFailure() async throws {
        let backend = StorageSettingsTestBackend()
        let model = StorageSettingsModel(capabilities: backend.capabilities)
        model.setPaneActive(true)
        model.selectTriptych(id: UUID(), name: "Selected")
        backend.operation = { _, _ in throw StorageSettingsTestFailure() }
        await model.performSafeAction(.clearProjectionCache)
        #expect(backend.performed.count == 1)
        #expect(backend.performed.first?.triptychID == nil)
        #expect(model.completedOperation == nil)
        #expect(model.errorMessage != nil && !model.isPerforming)
        await model.performSafeAction(.clearIndex)
        #expect(backend.performed.count == 1)
    }

    private func withMaterialPlan(
        triptychID: UUID, count: Int = 1,
        operation: @MainActor (UnusedChatMaterialCleanupPlan) async throws -> Void
    ) async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/agent-chat-tests/storage-plan-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let materials = root.appendingPathComponent("Chat/\(triptychID.uuidString)/Materials")
        try FileManager.default.createDirectory(at: materials, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data("Synthetic unused material \(index)".utf8)
                .write(to: materials.appendingPathComponent("\(UUID().uuidString).txt"))
        }
        let store = AgentChatMaterialStore(root: materials)
        let files = try await store.unusedMaterialCleanupPlan(referencedMaterialIDs: [], expectedHistoryFingerprint: nil)
        try await operation(.init(triptychID: triptychID, files: files))
    }
}

private struct StorageSettingsTestFailure: LocalizedError {
    var errorDescription: String? { "Synthetic storage failure" }
}

@MainActor
private final class StorageSettingsTestBackend {
    struct Performed {
        let action: ScholiumStorageAction
        let triptychID: UUID?
    }
    let sampleInventory = ScholiumStorageInventory(
        rootURL: URL(fileURLWithPath: "/unused-synthetic-storage"), measuredAt: Date(timeIntervalSince1970: 1),
        usages: [
            .init(category: .temporaryFiles, byteCount: 12, fileCount: 1, unreadableEntries: 2),
            .init(category: .sourceProjectionCache, byteCount: 25, fileCount: 2, skippedEntries: 1),
        ])
    var inventoryReads = 0
    var performed: [Performed] = []
    var deletedPlans: [ArchivedChatCleanupPlan] = []
    var unusedInspections: [UUID] = []
    var trashedPlans: [UnusedChatMaterialCleanupPlan] = []
    var inventoryRead: (() async throws -> ScholiumStorageInventory)?
    var operation: ((ScholiumStorageAction, UUID?) async throws -> ScholiumStorageOperationResult)?
    var archives: ((UUID) async throws -> ArchivedChatCleanupPlan)?
    var delete: ((ArchivedChatCleanupPlan) async throws -> ArchivedChatCleanupResult)?
    var unused: ((UUID) async throws -> UnusedChatMaterialCleanupPlan)?
    var trash: ((UnusedChatMaterialCleanupPlan) async throws -> AgentChatMaterialCleanupResult)?

    var capabilities: StorageSettingsCapabilities {
        .init(
            inventory: { [self] in
                inventoryReads += 1
                if let inventoryRead { return try await inventoryRead() }
                return sampleInventory
            },
            perform: { [self] action, id in
                performed.append(.init(action: action, triptychID: id))
                if let operation { return try await operation(action, id) }
                return .init(action: action)
            },
            archivedChats: { [self] id in
                if let archives { return try await archives(id) }
                return .init(triptychID: id, conversationIDs: [], revision: "empty", estimatedByteCount: 0)
            },
            deleteArchivedChats: { [self] plan in
                deletedPlans.append(plan)
                if let delete { return try await delete(plan) }
                return .init(removedConversations: plan.conversationIDs.count, materialCleanupIssue: nil)
            },
            unusedChatMaterials: { [self] id in
                unusedInspections.append(id)
                guard let unused else { throw StorageSettingsTestFailure() }
                return try await unused(id)
            },
            trashUnusedChatMaterials: { [self] plan in
                trashedPlans.append(plan)
                guard let trash else { throw StorageSettingsTestFailure() }
                return try await trash(plan)
            })
    }
}

/// Cancellation releases a test-owned wait; ordinary owner cancellation can
/// still be observed by the production method's post-read admission check.
@MainActor
private final class StorageSettingsTestGate {
    let entries: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var waiter: CheckedContinuation<Void, Never>?
    private var isReleased = false

    init() {
        (entries, continuation) = AsyncStream.makeStream()
    }

    func wait() async {
        continuation.yield(())
        guard !isReleased else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.release() }
        }
    }

    func release() {
        isReleased = true
        waiter?.resume()
        waiter = nil
        continuation.finish()
    }
}
