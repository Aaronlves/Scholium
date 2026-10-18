import Combine
import Foundation
import ScholiumContracts

struct ArchivedChatCleanupPlan: Equatable, Sendable {
    let triptychID: UUID
    let conversationIDs: [UUID]
    let revision: String
    let estimatedByteCount: Int64
}

struct ArchivedChatCleanupResult: Equatable, Sendable {
    let removedConversations: Int
    let materialCleanupIssue: String?
}

struct UnusedChatMaterialCleanupPlan: Equatable, Sendable {
    let triptychID: UUID
    let files: AgentChatMaterialCleanupPlan
}

/// The Settings page receives scoped operations, never a runtime or arbitrary
/// filesystem root. Agent Runtime storage is outside this capability.
@MainActor
struct StorageSettingsCapabilities {
    let inventory: () async throws -> ScholiumStorageInventory
    let perform: (ScholiumStorageAction, UUID?) async throws -> ScholiumStorageOperationResult
    let archivedChats: (UUID) async throws -> ArchivedChatCleanupPlan
    let deleteArchivedChats: (ArchivedChatCleanupPlan) async throws -> ArchivedChatCleanupResult
    let unusedChatMaterials: (UUID) async throws -> UnusedChatMaterialCleanupPlan
    let trashUnusedChatMaterials: (UnusedChatMaterialCleanupPlan) async throws -> AgentChatMaterialCleanupResult
}

struct StorageSettingsConfirmation: Identifiable, Equatable {
    enum Intent: Equatable {
        case index(ScholiumStorageAction, UUID)
        case archivedChats(ArchivedChatCleanupPlan)
        case unusedChatMaterials(UnusedChatMaterialCleanupPlan)
    }

    let id = UUID()
    let intent: Intent
    let triptychName: String

    var triptychID: UUID {
        switch intent {
        case .index(_, let id): id
        case .archivedChats(let plan): plan.triptychID
        case .unusedChatMaterials(let plan): plan.triptychID
        }
    }
}

enum StorageSettingsActivityScope: Equatable {
    case overview, caches, index, chat
}

enum StorageSettingsCompletedOperation: Equatable {
    case storage(ScholiumStorageOperationResult, triptychName: String?)
    case archivedChats(ArchivedChatCleanupResult, triptychName: String)
    case unusedChatMaterials(AgentChatMaterialCleanupResult, triptychName: String)
}

/// One retained page owns measurement, confirmation and operation feedback.
/// A committed operation outlives category navigation; only unconfirmed plans
/// are cancelled when the page or selected Triptych changes.
@MainActor
final class StorageSettingsModel: ObservableObject {
    @Published private(set) var activityScope = StorageSettingsActivityScope.overview
    @Published private(set) var inventory: ScholiumStorageInventory?
    @Published private(set) var isMeasuring = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isPerforming = false
    @Published private(set) var canStopCleanup = false
    @Published private(set) var confirmation: StorageSettingsConfirmation?
    @Published private(set) var completedOperation: StorageSettingsCompletedOperation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?

    private let capabilities: StorageSettingsCapabilities?
    private var inventoryTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var preparationGeneration: UInt64 = 0
    private var isPaneActive = false
    private var selectedTriptychID: UUID?
    private var selectedTriptychName = ""

    init(capabilities: StorageSettingsCapabilities?) {
        self.capabilities = capabilities
    }

    var isAvailable: Bool { capabilities != nil }
    var isBusy: Bool { isPreparing || isPerforming }
    var measuredBytes: Int64 { inventory?.usages.reduce(0) { $0 + $1.byteCount } ?? 0 }
    var unreadableEntries: Int { inventory?.usages.reduce(0) { $0 + $1.unreadableEntries } ?? 0 }
    var skippedEntries: Int { inventory?.usages.reduce(0) { $0 + $1.skippedEntries } ?? 0 }

    func setPaneActive(_ active: Bool) {
        isPaneActive = active
        if !active { dismissConfirmation() }
    }

    func selectTriptych(id: UUID?, name: String) {
        guard selectedTriptychID != id || selectedTriptychName != name else { return }
        selectedTriptychID = id
        selectedTriptychName = name
        dismissConfirmation()
    }

    func measureIfNeeded() async {
        guard inventory == nil else { return }
        await refreshInventory()
    }

    func refreshInventory() async {
        if let inventoryTask {
            await inventoryTask.value
            return
        }
        guard let capabilities else { return }
        isMeasuring = true
        if !isPerforming { activityScope = .overview }
        errorMessage = nil
        let task = Task { [self] in
            defer {
                isMeasuring = false
                inventoryTask = nil
            }
            do {
                inventory = try await capabilities.inventory()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = ScholiumErrorLocalization.message(error)
            }
        }
        inventoryTask = task
        await task.value
    }

    func requestIndexAction(_ action: ScholiumStorageAction) {
        guard action == .rebuildIndex || action == .clearIndex,
            isPaneActive, !isBusy, !isMeasuring, let selectedTriptychID, capabilities != nil
        else { return }
        dismissConfirmation()
        confirmation = StorageSettingsConfirmation(
            intent: .index(action, selectedTriptychID), triptychName: selectedTriptychName)
    }

    func prepareArchivedChatDeletion() async {
        guard isPaneActive, !isBusy, !isMeasuring, let selectedTriptychID, let capabilities else { return }
        dismissConfirmation()
        let generation = preparationGeneration
        let targetName = selectedTriptychName
        isPreparing = true
        activityScope = .chat
        errorMessage = nil
        notice = nil
        let task = Task { [self] in
            defer {
                if generation == preparationGeneration {
                    isPreparing = false
                    preparationTask = nil
                }
            }
            do {
                let plan = try await capabilities.archivedChats(selectedTriptychID)
                try Task.checkCancellation()
                guard isPaneActive, generation == preparationGeneration,
                    self.selectedTriptychID == selectedTriptychID, plan.triptychID == selectedTriptychID
                else { return }
                guard !plan.conversationIDs.isEmpty else {
                    notice = ScholiumL10n.string("No archived conversations to delete.")
                    return
                }
                confirmation = StorageSettingsConfirmation(intent: .archivedChats(plan), triptychName: targetName)
            } catch is CancellationError {
                return
            } catch {
                guard isPaneActive, generation == preparationGeneration,
                    self.selectedTriptychID == selectedTriptychID
                else { return }
                errorMessage = ScholiumErrorLocalization.message(error)
            }
        }
        preparationTask = task
        await task.value
    }

    func dismissConfirmation() {
        preparationGeneration &+= 1
        preparationTask?.cancel()
        preparationTask = nil
        isPreparing = false
        confirmation = nil
    }

    func prepareUnusedChatMaterialCleanup() async {
        guard isPaneActive, !isBusy, !isMeasuring, let selectedTriptychID, let capabilities else { return }
        dismissConfirmation()
        let generation = preparationGeneration
        let targetName = selectedTriptychName
        isPreparing = true
        activityScope = .chat
        errorMessage = nil
        notice = nil
        let task = Task { [self] in
            defer {
                if generation == preparationGeneration {
                    isPreparing = false
                    preparationTask = nil
                }
            }
            do {
                let plan = try await capabilities.unusedChatMaterials(selectedTriptychID)
                try Task.checkCancellation()
                guard isPaneActive, generation == preparationGeneration,
                    self.selectedTriptychID == selectedTriptychID, plan.triptychID == selectedTriptychID
                else { return }
                guard plan.files.fileCount > 0 else {
                    notice = ScholiumL10n.string("No unused Chat-material files to move to Trash.")
                    return
                }
                confirmation = StorageSettingsConfirmation(intent: .unusedChatMaterials(plan), triptychName: targetName)
            } catch is CancellationError {
                return
            } catch {
                guard isPaneActive, generation == preparationGeneration, self.selectedTriptychID == selectedTriptychID else { return }
                errorMessage = ScholiumErrorLocalization.message(error)
            }
        }
        preparationTask = task
        await task.value
    }

    @discardableResult
    func confirm(_ request: StorageSettingsConfirmation) -> Task<Void, Never>? {
        guard confirmation?.id == request.id, isPaneActive, !isBusy,
            request.triptychID == selectedTriptychID, let capabilities
        else { return nil }
        confirmation = nil
        isPerforming = true
        errorMessage = nil
        notice = nil
        switch request.intent {
        case .index: activityScope = .index
        case .archivedChats, .unusedChatMaterials: activityScope = .chat
        }
        if case .unusedChatMaterials = request.intent { canStopCleanup = true }
        let task = Task { [self] in
            defer {
                isPerforming = false
                canStopCleanup = false
                cleanupTask = nil
            }
            do {
                switch request.intent {
                case .index(let action, let id):
                    let result = try await capabilities.perform(action, id)
                    completedOperation = .storage(result, triptychName: request.triptychName)
                case .archivedChats(let plan):
                    let result = try await capabilities.deleteArchivedChats(plan)
                    completedOperation = .archivedChats(result, triptychName: request.triptychName)
                case .unusedChatMaterials(let plan):
                    let result = try await capabilities.trashUnusedChatMaterials(plan)
                    completedOperation = .unusedChatMaterials(result, triptychName: request.triptychName)
                    canStopCleanup = false
                }
                await refreshInventory()
            } catch is CancellationError {
                if case .unusedChatMaterials = request.intent {
                    completedOperation = nil
                    notice = ScholiumL10n.string("Cleanup stopped before any files were moved.")
                } else {
                    errorMessage = ScholiumErrorLocalization.message(CancellationError())
                }
            } catch {
                errorMessage = ScholiumErrorLocalization.message(error)
            }
        }
        if canStopCleanup { cleanupTask = task }
        return task
    }

    func stopCleanup() {
        guard canStopCleanup else { return }
        canStopCleanup = false
        cleanupTask?.cancel()
    }

    func performSafeAction(_ action: ScholiumStorageAction) async {
        guard action == .clearTemporaryFiles || action == .clearProjectionCache || action == .cleanRetiredDerivedState,
            isPaneActive, !isBusy, !isMeasuring, let capabilities
        else { return }
        dismissConfirmation()
        isPerforming = true
        activityScope = .caches
        errorMessage = nil
        notice = nil
        defer { isPerforming = false }
        do {
            let result = try await capabilities.perform(action, nil)
            completedOperation = .storage(result, triptychName: nil)
            await refreshInventory()
        } catch {
            errorMessage = ScholiumErrorLocalization.message(error)
        }
    }
}
