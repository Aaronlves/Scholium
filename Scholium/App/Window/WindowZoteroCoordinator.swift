import Foundation
import ScholiumContracts

@MainActor
struct WindowZoteroDependencies {
    let capability: @MainActor () -> (triptychID: UUID?, binding: (any ZoteroBindingUseCases)?)
    let reportInformation: @MainActor (String) -> Void
}

/// Owns one window's Zotero operations and cancellation generation. Errors
/// remain typed results for the panel's presentation-local state; WindowModel
/// only supplies the currently installed Triptych capability.
@MainActor
final class WindowZoteroCoordinator {
    let bridge: ZoteroBridge
    private let dependencies: WindowZoteroDependencies
    private var generation: UInt64 = 0
    private var taskCancellations: [UUID: @MainActor () -> Void] = [:]

    init(bridge: ZoteroBridge, dependencies: WindowZoteroDependencies) {
        self.bridge = bridge
        self.dependencies = dependencies
    }

    func cancelAll() {
        generation &+= 1
        taskCancellations.values.forEach { $0() }
        taskCancellations.removeAll()
    }

    func searchLibrary(query: String) async throws -> [ZoteroSearchHit] {
        try await perform { [bridge] in
            try await bridge.searchLibrary(query: query)
        }
    }

    func prepareLinkAndFill(
        noteID: UUID,
        library: ZoteroLibraryMetadata,
        itemKey: String
    ) async throws -> ZoteroMetadataPlan {
        try await performWithCapability { capability in
            try await capability.prepareZoteroLinkAndFill(
                noteID: noteID,
                library: library,
                itemKey: itemKey
            )
        }
    }

    func prepareMetadataRefresh(noteID: UUID) async throws -> ZoteroMetadataPlan {
        try await performWithCapability { capability in
            try await capability.prepareZoteroMetadataRefresh(noteID: noteID)
        }
    }

    func commitMetadataPlan(_ plan: ZoteroMetadataPlan) async throws {
        let result = try await performWithCapability { capability in
            try await capability.commitZoteroMetadataPlan(plan)
        }
        if let warning = result.derivedRefreshWarning {
            dependencies.reportInformation(warning)
            return
        }
        let retained = result.retainedConflictKeys.count
        let message: String
        switch plan.mode {
        case .linkAndFill:
            if result.filledKeys.isEmpty {
                message = retained == 0
                    ? String(localized: "Zotero link saved. No empty supported Metadata fields needed filling.")
                    : String(localized: "Zotero link saved. Existing Metadata values were kept.")
            } else if retained == 0 {
                message = String(localized: "Zotero link saved and \(result.filledKeys.count) Metadata fields filled.")
            } else {
                message = String(localized: "Zotero link saved and \(result.filledKeys.count) Metadata fields filled; \(retained) existing values were kept.")
            }
        case .refresh:
            message = String(localized: "Zotero Metadata refreshed: \(result.filledKeys.count) fields filled and \(result.updatedKeys.count) fields updated.")
        }
        dependencies.reportInformation(message)
    }

    func clearBinding(noteID: UUID) async throws {
        let warning: String? = try await performWithCapability { capability in
            let snapshot = try await capability.zoteroBindings()
            guard snapshot.binding(for: noteID) != nil else { return nil }
            let result = try await capability.clearZoteroBinding(
                noteID: noteID,
                expectedRevision: snapshot.revision
            )
            return result.derivedRefreshWarning
        }
        if let warning {
            dependencies.reportInformation(warning)
        }
    }

    private func performWithCapability<T: Sendable>(
        _ operation: @escaping @Sendable (any ZoteroBindingUseCases) async throws -> T
    ) async throws -> T {
        let installed = dependencies.capability()
        guard let capability = installed.binding else {
            throw ScholiumApplicationError.workspaceShutDown(
                installed.triptychID ?? UUID()
            )
        }
        return try await perform { try await operation(capability) }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let operationGeneration = generation
        let operationID = UUID()
        let task = Task { try await operation() }
        taskCancellations[operationID] = { task.cancel() }
        defer {
            taskCancellations[operationID] = nil
        }
        try Task.checkCancellation()
        let value = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard operationGeneration == generation else {
            throw CancellationError()
        }
        return value
    }
}
