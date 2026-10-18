import Foundation
import ScholiumContracts

enum UnusedChatMaterialCleanupError: Error, LocalizedError {
    case busy, wrongTriptych

    var errorDescription: String? {
        switch self {
        case .busy:
            String(
                localized: "Chat materials are in use. Wait for active Chat work, material preparation or history cleanup to finish, then inspect again.",
                bundle: .module)
        case .wrongTriptych:
            String(localized: "The inspected Chat materials belong to another Triptych. Inspect the selected Triptych again.", bundle: .module)
        }
    }
}

@MainActor
extension AgentChatController {
    func unusedChatMaterialCleanupPlan() async throws -> UnusedChatMaterialCleanupPlan {
        guard await waitUntilLoaded() else { throw CancellationError() }
        try admitUnusedMaterialCleanup()
        defer { isCleaningUnusedMaterials = false }
        let (references, fingerprint) = try await protectedCleanupMaterialIDs()
        let files = try await materialStore.unusedMaterialCleanupPlan(
            referencedMaterialIDs: references, expectedHistoryFingerprint: fingerprint)
        try Task.checkCancellation()
        return .init(triptychID: triptychID, files: files)
    }

    func moveUnusedChatMaterialsToTrash(_ plan: UnusedChatMaterialCleanupPlan) async throws -> AgentChatMaterialCleanupResult {
        guard plan.triptychID == triptychID else { throw UnusedChatMaterialCleanupError.wrongTriptych }
        guard await waitUntilLoaded() else { throw CancellationError() }
        try admitUnusedMaterialCleanup()
        defer { isCleaningUnusedMaterials = false }
        let (references, fingerprint) = try await protectedCleanupMaterialIDs()
        try Task.checkCancellation()
        return try await materialStore.moveUnusedMaterialsToTrash(
            plan.files, referencedMaterialIDs: references, expectedHistoryFingerprint: fingerprint)
    }

    private func admitUnusedMaterialCleanup() throws {
        try Task.checkCancellation()
        guard !isCleaningUnusedMaterials, !hasActiveExecutions, preparingMaterials.isEmpty, archivedChatCleanup == nil else {
            throw UnusedChatMaterialCleanupError.busy
        }
        // Admission precedes every suspension. All preparation entry points
        // share this guard, including transfers and PDF-page rendering.
        isCleaningUnusedMaterials = true
    }

    private func protectedCleanupMaterialIDs() async throws -> (Set<UUID>, DocumentFingerprint?) {
        var references = liveCleanupMaterialIDs()
        // A failed/unsupported history read cannot authorize file release.
        // Disk can still retain copies removed by an unsaved live draft.
        let history = try await loadHistory()
        guard history.conversations.allSatisfy({ $0.triptychID == triptychID }) else { throw CocoaError(.fileReadCorruptFile) }
        references.formUnion(referencedMaterialIDs(in: history.conversations))
        try Task.checkCancellation()
        references.formUnion(liveCleanupMaterialIDs())
        return (references, history.fingerprint)
    }

    private func liveCleanupMaterialIDs() -> Set<UUID> {
        var references = referencedMaterialIDs(in: conversations)
        for ids in pendingHistorySaveReferences.values { references.formUnion(ids) }
        references.formUnion(pendingDeletionMaterials.keys)
        return references
    }
}
