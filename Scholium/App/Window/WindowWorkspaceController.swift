import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

enum WindowWorkspaceResolution {
    case unavailable(assignments: [TriptychAssignment], message: String?)
    case unavailablePreserving(
        assignments: [TriptychAssignment],
        assignment: TriptychAssignment,
        message: String?
    )
    case selected(
        assignments: [TriptychAssignment],
        assignment: TriptychAssignment,
        identityRepairFailure: String?
    )
}

struct WindowWorkspaceSessionState {
    var assignment: TriptychAssignment?
    var registeredTriptychs: [TriptychAssignment] = []
    var recoveryMessage: String?
    var accessRecovery: WorkspaceAccessRecovery?
    var activeServicesID: UUID?
}

@MainActor
struct WindowWorkspaceRecoveryDependencies {
    let configureTriptych: @MainActor (
        _ paperAnalysisURL: URL,
        _ topicKnowledgeURL: URL,
        _ outputURL: URL,
        _ portableContainerURL: URL,
        _ triptychID: UUID,
        _ triptychName: String
    ) async throws -> Void
    let didRemoveRegistration: @MainActor (
        _ assignment: TriptychAssignment,
        _ registeredVaults: [RegisteredVault],
        _ registeredTriptychs: [TriptychAssignment]
    ) -> Void
    let reportInformation: @MainActor (String) -> Void
}

/// Owns one window's Triptych assignment and capability-session state.
/// `WindowModel` remains the composition root that installs capabilities into
/// feature controllers and routes cross-feature presentation effects.
@MainActor
final class WindowWorkspaceController: ObservableObject {
    @Published private(set) var state = WindowWorkspaceSessionState()
    @Published private(set) var isRecovering = false

    private let workspaceStore: WorkspaceStore
    let requestedTriptychID: UUID?
    private(set) var activeCapabilities: WindowWorkspaceCapabilities?
    private var recoveryDependencies: WindowWorkspaceRecoveryDependencies?
    private var attemptedInitialRestore = false
    private var recoveryGeneration: UInt64 = 0
    private var recoveryTaskCancellation: (@MainActor () -> Void)?

    init(workspaceStore: WorkspaceStore, requestedTriptychID: UUID?) {
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
    }

    func setAssignment(_ assignment: TriptychAssignment?) {
        state.assignment = assignment
    }

    func setRegisteredTriptychs(_ assignments: [TriptychAssignment]) {
        state.registeredTriptychs = assignments
    }

    func setRecoveryMessage(_ message: String?) {
        state.recoveryMessage = message
    }

    func setAccessRecovery(_ recovery: WorkspaceAccessRecovery?) {
        state.accessRecovery = recovery
    }

    func setActiveServicesID(_ id: UUID?) {
        state.activeServicesID = id
    }

    func setActiveCapabilities(_ capabilities: WindowWorkspaceCapabilities?) {
        activeCapabilities = capabilities
    }

    func bindRecoveryDependencies(_ dependencies: WindowWorkspaceRecoveryDependencies) {
        precondition(recoveryDependencies == nil)
        recoveryDependencies = dependencies
    }

    func beginInitialRestoreIfNeeded(isConfigured: Bool) -> Bool {
        guard !attemptedInitialRestore, !isConfigured else { return false }
        attemptedInitialRestore = true
        return true
    }

    func markInitialRestoreAttempted() {
        attemptedInitialRestore = true
    }

    func cancelRecovery() {
        recoveryGeneration &+= 1
        recoveryTaskCancellation?()
        recoveryTaskCancellation = nil
        isRecovering = false
    }

    @discardableResult
    func recordRecovery(for error: Error) -> Bool {
        guard let recovery = Self.accessRecoveryRoute(for: error) else {
            return false
        }
        state.accessRecovery = recovery
        state.recoveryMessage = Self.accessRecoveryMessage(for: recovery)
        return true
    }

    func restoreWorkspaceAccess(using selectedURL: URL) async throws {
        try await performRecovery { [self] in
            guard let recovery = state.accessRecovery,
                  let assignment = state.assignment,
                  let analyses = assignment.vault(for: .paperAnalysis),
                  let topics = assignment.vault(for: .topicKnowledge),
                  let works = assignment.vault(for: .output),
                  let recoveryDependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }

            let selected = selectedURL.resolvingSymlinksInPath().standardizedFileURL
            let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
            let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            let expected = URL(fileURLWithPath: recovery.expectedPath, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL.path

            let replacementAnalyses = analysesURL.resolvingSymlinksInPath()
                .standardizedFileURL.path == expected ? selected : analysesURL
            let replacementTopics = topicsURL.resolvingSymlinksInPath()
                .standardizedFileURL.path == expected ? selected : topicsURL
            let replacementWorks = worksURL.resolvingSymlinksInPath()
                .standardizedFileURL.path == expected ? selected : worksURL
            let portableURL: URL
            if recovery.kind == .portableControl {
                portableURL = selected
            } else {
                portableURL = await workspaceStore.portableContainerURL(
                    forWorksURL: replacementWorks
                ) ?? replacementWorks.deletingLastPathComponent()
            }
            try await recoveryDependencies.configureTriptych(
                replacementAnalyses,
                replacementTopics,
                replacementWorks,
                portableURL,
                assignment.id,
                assignment.triptych.name
            )
            state.accessRecovery = nil
            state.recoveryMessage = nil
        }
    }

    @discardableResult
    func rebuildUnsupportedPortableControl() async throws -> URL {
        try await performRecovery { [self] in
            guard let recovery = state.accessRecovery,
                  recovery.kind == .unsupportedPortableControl,
                  state.activeServicesID == nil,
                  let assignment = state.assignment,
                  let analyses = assignment.vault(for: .paperAnalysis),
                  let topics = assignment.vault(for: .topicKnowledge),
                  let works = assignment.vault(for: .output),
                  let recoveryDependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
            let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            guard let portableURL = await workspaceStore.portableContainerURL(
                forWorksURL: worksURL
            ) else {
                throw WorkspaceRegistryError.portableControlAccessUnavailable(
                    worksURL.deletingLastPathComponent().path
                )
            }
            let preserved = try await workspaceStore.preserveUnsupportedPortableControl(
                portableContainerURL: portableURL,
                worksURL: worksURL,
                triptychID: assignment.id
            )
            try await recoveryDependencies.configureTriptych(
                analysesURL,
                topicsURL,
                worksURL,
                portableURL,
                assignment.id,
                assignment.triptych.name
            )
            state.accessRecovery = nil
            state.recoveryMessage = nil
            recoveryDependencies.reportInformation(
                "Previous portable control was preserved at \(preserved.path)."
            )
            return preserved
        }
    }

    @discardableResult
    func archiveInvalidNoteMetadataRecord() async throws -> URL {
        try await performRecovery { [self] in
            guard let recovery = state.accessRecovery,
                  recovery.kind == .invalidNoteMetadataRecord,
                  let issue = recovery.noteMetadataIssue,
                  state.activeServicesID == nil,
                  let assignment = state.assignment,
                  let analyses = assignment.vault(for: .paperAnalysis),
                  let topics = assignment.vault(for: .topicKnowledge),
                  let works = assignment.vault(for: .output),
                  let recoveryDependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
            let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            guard let portableURL = await workspaceStore.portableContainerURL(
                forWorksURL: worksURL
            ) else {
                throw WorkspaceRegistryError.portableControlAccessUnavailable(
                    worksURL.deletingLastPathComponent().path
                )
            }
            let preserved = try await workspaceStore.archiveInvalidNoteMetadataRecord(
                portableContainerURL: portableURL,
                worksURL: worksURL,
                issue: issue,
                triptychID: assignment.id
            )
            try await recoveryDependencies.configureTriptych(
                analysesURL,
                topicsURL,
                worksURL,
                portableURL,
                assignment.id,
                assignment.triptych.name
            )
            state.accessRecovery = nil
            state.recoveryMessage = nil
            recoveryDependencies.reportInformation(
                "Invalid Metadata record preserved at \(preserved.path)."
            )
            return preserved
        }
    }

    func removeUnavailableTriptychRegistration() async throws {
        try await performRecovery { [self] in
            guard state.accessRecovery != nil,
                  state.activeServicesID == nil,
                  let assignment = state.assignment,
                  let recoveryDependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            try await workspaceStore.removeLocalTriptychRegistration(id: assignment.id)
            activeCapabilities = nil
            state.assignment = nil
            state.accessRecovery = nil
            state.recoveryMessage = nil
            let refreshedVaults = (try? await workspaceStore.registeredVaults()) ?? []
            let refreshedTriptychs = (try? await workspaceStore.registeredTriptychs()) ?? []
            state.registeredTriptychs = refreshedTriptychs
            recoveryDependencies.didRemoveRegistration(
                assignment,
                refreshedVaults,
                refreshedTriptychs
            )
        }
    }

    var canRemoveUnavailableTriptychRegistration: Bool {
        state.accessRecovery != nil
            && state.activeServicesID == nil
            && state.assignment != nil
    }

    private func performRecovery<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        guard !isRecovering else { throw CancellationError() }
        recoveryGeneration &+= 1
        let operationGeneration = recoveryGeneration
        isRecovering = true
        let task = Task { try await operation() }
        recoveryTaskCancellation = { task.cancel() }
        defer {
            recoveryTaskCancellation = nil
            if operationGeneration == recoveryGeneration {
                isRecovering = false
            }
        }
        try Task.checkCancellation()
        let value = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard operationGeneration == recoveryGeneration else {
            throw CancellationError()
        }
        return value
    }

    private static func accessRecoveryRoute(for error: Error) -> WorkspaceAccessRecovery? {
        if let workspaceError = error as? WorkspaceRegistryError {
            switch workspaceError {
            case .vaultAccessUnavailable(let path):
                return WorkspaceAccessRecovery(kind: .vault, expectedPath: path)
            case .portableControlAccessUnavailable(let path):
                return WorkspaceAccessRecovery(kind: .portableControl, expectedPath: path)
            default:
                break
            }
        }
        if let applicationError = error as? ScholiumApplicationError,
           case .portableControlRecoveryRequired(let controlPath, let reason) = applicationError {
            return WorkspaceAccessRecovery(
                kind: .unsupportedPortableControl,
                expectedPath: controlPath,
                reason: reason
            )
        }
        if let applicationError = error as? ScholiumApplicationError,
           case .noteMetadataRecoveryRequired(let controlPath, let issue) = applicationError {
            return WorkspaceAccessRecovery(
                kind: .invalidNoteMetadataRecord,
                expectedPath: controlPath,
                reason: issue.explanation,
                noteMetadataIssue: issue
            )
        }
        return nil
    }

    private static func accessRecoveryMessage(for recovery: WorkspaceAccessRecovery) -> String {
        switch recovery.kind {
        case .vault:
            "Scholium needs renewed access to '\(recovery.expectedPath)'. Choose that folder again."
        case .portableControl:
            "Scholium needs renewed access to '\(recovery.expectedPath)' so it can use the portable .scholium folder beside Works."
        case .unsupportedPortableControl:
            "Scholium must archive the unsupported portable control folder at '\(recovery.expectedPath)' before rebuilding current control state."
        case .invalidNoteMetadataRecord:
            "Scholium must archive the exact invalid Metadata record before reloading this Triptych."
        }
    }

    func resolveAssignment(
        preferredTriptychID: UUID?,
        currentTriptychID: UUID?
    ) async -> WindowWorkspaceResolution {
        let assignments: [TriptychAssignment]
        do {
            assignments = try await workspaceStore.registeredTriptychs()
        } catch {
            if let assignment = state.assignment {
                return .unavailablePreserving(
                    assignments: state.registeredTriptychs,
                    assignment: assignment,
                    message: error.localizedDescription
                )
            }
            return .unavailable(
                assignments: state.registeredTriptychs,
                message: error.localizedDescription
            )
        }

        let selectedID = preferredTriptychID ?? currentTriptychID ?? requestedTriptychID
        let stored: TriptychAssignment?
        if let selectedID {
            stored = assignments.first { $0.id == selectedID }
            guard stored != nil else {
                return .unavailable(
                    assignments: assignments,
                    message: "This Triptych is no longer registered on this Mac. Open an existing Triptych or choose its three folders again."
                )
            }
        } else {
            stored = try? await workspaceStore.defaultTriptych()
        }
        guard let stored else {
            return .unavailable(assignments: assignments, message: nil)
        }

        do {
            let repaired = try await workspaceStore.reconcileTriptychIdentity(id: stored.id)
            let refreshed = repaired == stored
                ? assignments
                : ((try? await workspaceStore.registeredTriptychs()) ?? assignments)
            return .selected(
                assignments: refreshed,
                assignment: repaired,
                identityRepairFailure: nil
            )
        } catch {
            return .selected(
                assignments: assignments,
                assignment: stored,
                identityRepairFailure: error.localizedDescription
            )
        }
    }
}
