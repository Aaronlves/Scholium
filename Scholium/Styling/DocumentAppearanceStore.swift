import AppKit
import Combine
import Foundation
import ScholiumContracts

/// Observable macOS adapter over Application-owned style persistence.
@MainActor
final class DocumentAppearanceStore: ObservableObject {
    @Published private(set) var appearanceProfiles: [DocumentAppearanceProfile] = []
    @Published private(set) var appearanceReloadRevision = 0
    @Published private(set) var selectedAppearanceProfileID: UUID?
    @Published private(set) var storeError: String?
    @Published private(set) var canModifyAppearance = false
    @Published private(set) var appearanceError: String?
    @Published private(set) var isRestoringAppearance = false

    private let operations: any StyleUseCases
    private var operationTail: Task<Void, Never>?

    init(operations: any StyleUseCases) {
        self.operations = operations
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refresh()
        }
    }

    var canRepairAppearance: Bool { !canModifyAppearance && !appearanceProfiles.isEmpty }

    var selectedAppearanceProfile: DocumentAppearanceProfile? {
        appearanceProfiles.first { $0.id == selectedAppearanceProfileID }
    }

    func refresh() async {
        _ = await enqueue { try await self.operations.styleSnapshot() }.result
    }

    func createAppearance(named name: String = "Untitled Appearance") {
        perform { try await self.operations.createAppearanceProfile(named: name) }
    }

    func selectAppearance(_ id: UUID) {
        perform { try await self.operations.selectAppearanceProfile(id) }
    }

    func updateAppearance(_ profile: DocumentAppearanceProfile) {
        perform { try await self.operations.updateAppearanceProfile(profile) }
    }

    func renameAppearance(_ id: UUID, to name: String) {
        perform { try await self.operations.renameAppearanceProfile(id, to: name) }
    }

    func duplicateAppearance(_ id: UUID) {
        perform { try await self.operations.duplicateAppearanceProfile(id) }
    }

    func removeAppearance(_ id: UUID) {
        perform { try await self.operations.removeAppearanceProfile(id) }
    }

    func revealAppearanceConfiguration() {
        Task {
            do {
                let url = try await operations.appearanceConfigurationURL()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { storeError = error.localizedDescription }
        }
    }

    func reloadAppearanceConfiguration() {
        _ = enqueue(reloadAppearance: true) { try await self.operations.reloadAppearanceConfiguration() }
    }

    func repairAppearanceProfile(_ profile: DocumentAppearanceProfile) {
        guard !isRestoringAppearance else { return }
        isRestoringAppearance = true
        _ = enqueue(reloadAppearance: true, completion: { self.isRestoringAppearance = false }) {
            try await self.operations.repairAppearanceProfile(profile)
        }
    }

    func restoreAppearanceDefaults() {
        guard !isRestoringAppearance else { return }
        isRestoringAppearance = true
        _ = enqueue(reloadAppearance: true, completion: { self.isRestoringAppearance = false }) {
            try await self.operations.restoreAppearanceDefaults()
        }
    }

    private func perform(
        _ operation: @escaping @Sendable () async throws -> StyleSnapshot
    ) {
        _ = enqueue(operation)
    }

    /// One MainActor queue owns request order through authoritative publication.
    /// An enqueued operation completes even if its caller stops awaiting it.
    private func enqueue(
        reloadAppearance: Bool = false,
        completion: @escaping @MainActor () -> Void = {},
        _ operation: @escaping @Sendable () async throws -> StyleSnapshot
    ) -> Task<StyleSnapshot, Error> {
        let predecessor = operationTail
        let task = Task { @MainActor in
            await predecessor?.value
            defer { completion() }
            do {
                let snapshot = try await operation()
                apply(snapshot)
                if reloadAppearance { appearanceReloadRevision += 1 }
                return snapshot
            } catch {
                // A failed reload may still have changed the owner's failure
                // state. Publish it before reporting the original error; this
                // exposes recovery without replacing the retained draft.
                if let snapshot = try? await operations.styleSnapshot() { apply(snapshot) }
                storeError = error.localizedDescription
                throw error
            }
        }
        operationTail = Task { @MainActor in _ = await task.result }
        return task
    }

    private func apply(_ snapshot: StyleSnapshot) {
        appearanceProfiles = snapshot.appearanceProfiles
        selectedAppearanceProfileID = snapshot.selectedAppearanceProfileID
        storeError = snapshot.storeError
        canModifyAppearance = snapshot.canModifyAppearance
        appearanceError = snapshot.appearanceError
    }
}
