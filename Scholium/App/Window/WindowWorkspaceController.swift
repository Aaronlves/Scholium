import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

private enum WindowWorkspaceResolution {
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

enum WindowWorkspaceActivationOutcome {
    case unavailable
    case activated
    case recoveryRequired
    case failed(String)
}

struct WindowWorkspaceInstallationFeedback {
    let transactionRecoveryIssues: [String]
}

struct WindowWorkspaceActiveSession {
    let capabilities: WindowWorkspaceCapabilities
    let snapshot: WorkspaceSnapshot
}

struct WindowWorkspaceReplacement {
    let previousAssignment: TriptychAssignment?
}

struct WindowWorkspaceSessionState {
    var assignment: TriptychAssignment?
    var registeredVaults: [RegisteredVault] = []
    var registeredTriptychs: [TriptychAssignment] = []
    var recoveryMessage: String?
    var accessRecovery: WorkspaceAccessRecovery?
    var activeServicesID: UUID?
}

@MainActor
struct WindowWorkspaceDependencies {
    let installSession: @MainActor (
        WindowWorkspaceCapabilities,
        WorkspaceSnapshot
    ) async throws -> WindowWorkspaceInstallationFeedback
    let didRemoveRegistration: @MainActor (TriptychAssignment) -> Void
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
    private var dependencies: WindowWorkspaceDependencies?
    private var attemptedInitialRestore = false
    private var preferredOpeningVault: WorkspaceVaultSlot = .paperAnalysis
    private var recoveryGeneration: UInt64 = 0
    private var recoveryTaskCancellation: (@MainActor () -> Void)?
    private var permissionRefreshTask: Task<Void, Never>?

    init(workspaceStore: WorkspaceStore, requestedTriptychID: UUID?) {
        self.workspaceStore = workspaceStore
        self.requestedTriptychID = requestedTriptychID
    }

    func setAccessRecovery(_ recovery: WorkspaceAccessRecovery?) {
        state.accessRecovery = recovery
    }

    func bindDependencies(_ dependencies: WindowWorkspaceDependencies) {
        precondition(self.dependencies == nil)
        self.dependencies = dependencies
    }

    func beginInitialRestoreIfNeeded(isConfigured: Bool) -> Bool {
        guard !attemptedInitialRestore, !isConfigured else { return false }
        attemptedInitialRestore = true
        return true
    }

    func markInitialRestoreAttempted() {
        attemptedInitialRestore = true
    }

    func cancelAll() {
        recoveryGeneration &+= 1
        recoveryTaskCancellation?()
        recoveryTaskCancellation = nil
        permissionRefreshTask?.cancel()
        permissionRefreshTask = nil
        isRecovering = false
    }

    func refreshRegistrations() async {
        do {
            state.registeredVaults = try await workspaceStore.registeredVaults()
            state.registeredTriptychs = try await workspaceStore.registeredTriptychs()
        } catch {
            state.recoveryMessage = error.localizedDescription
        }
    }

    func refreshWorkspaceAssignment(
        preferredTriptychID: UUID?,
        openingVault: WorkspaceVaultSlot
    ) async -> WindowWorkspaceActivationOutcome {
        preferredOpeningVault = openingVault
        let resolution = await resolveAssignment(
            preferredTriptychID: preferredTriptychID,
            currentTriptychID: state.assignment?.id
        )
        switch resolution {
        case .unavailable(let assignments, let message):
            state.registeredTriptychs = assignments
            state.assignment = nil
            state.recoveryMessage = message
            activeCapabilities = nil
            state.activeServicesID = nil
            return .unavailable
        case .unavailablePreserving(let assignments, let assignment, let message):
            state.registeredTriptychs = assignments
            state.assignment = assignment
            state.recoveryMessage = message
            return .unavailable
        case .selected(let assignments, let assignment, let repairFailure):
            state.registeredTriptychs = assignments
            state.assignment = assignment
            if activeCapabilities?.assignment.id != assignment.id {
                activeCapabilities = nil
                state.activeServicesID = nil
            }
            do {
                try await activate(assignment: assignment, openingVault: openingVault)
                if let repairFailure {
                    state.recoveryMessage = "Scholium opened the registered Triptych, but could not repair its stored vault identities. \(repairFailure)"
                }
                return .activated
            } catch {
                if recordRecovery(for: error) {
                    return .recoveryRequired
                }
                let message = "Scholium could not activate this Triptych's shared files, search, and research history. The registered locations remain unchanged. \(error.localizedDescription)"
                state.recoveryMessage = message
                return .failed(message)
            }
        }
    }

    @discardableResult
    func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID?,
        triptychName: String?,
        openingVault: WorkspaceVaultSlot
    ) async throws -> TriptychAssignment {
        preferredOpeningVault = openingVault
        let normalizedName = triptychName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilities = try await workspaceStore.configureTriptychCapabilities(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID ?? state.assignment?.id ?? requestedTriptychID,
            triptychName: (normalizedName?.isEmpty == false ? normalizedName : nil)
                ?? state.registeredTriptychs.first(where: { $0.id == triptychID })?.triptych.name
                ?? state.assignment?.triptych.name,
            openingVault: openingVault
        )
        let registeredVaults = try await workspaceStore.registeredVaults()
        let registeredTriptychs = try await workspaceStore.registeredTriptychs()
        try await install(capabilities: capabilities)
        state.accessRecovery = nil
        state.recoveryMessage = nil
        state.registeredVaults = registeredVaults
        state.registeredTriptychs = registeredTriptychs
        return capabilities.assignment
    }

    func activeSession(
        for assignment: TriptychAssignment,
        openingVault: WorkspaceVaultSlot
    ) async throws -> WindowWorkspaceActiveSession {
        preferredOpeningVault = openingVault
        if activeCapabilities?.assignment.id != assignment.id {
            try await activate(assignment: assignment, openingVault: openingVault)
        }
        guard let capabilities = activeCapabilities,
              capabilities.assignment.id == assignment.id,
              let snapshot = workspaceStore.snapshot(for: capabilities.runtimeIdentity) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return WindowWorkspaceActiveSession(
            capabilities: capabilities,
            snapshot: snapshot
        )
    }

    func vaultConfig(rootURL: URL) async -> VaultConfig {
        await workspaceStore.vaultConfig(rootURL: rootURL)
    }

    func portableContainerURL(for worksURL: URL) async -> URL? {
        await workspaceStore.portableContainerURL(forWorksURL: worksURL)
    }

    func adopt(_ activation: WorkspaceActivation) -> WindowWorkspaceReplacement? {
        let previousRuntimeIdentity = activeCapabilities?.runtimeIdentity
        let intendedID = state.assignment?.id
            ?? state.activeServicesID
            ?? requestedTriptychID
        guard activation.workspaceID == intendedID
                || previousRuntimeIdentity.map(activation.replaces) == true,
              previousRuntimeIdentity != activation.runtimeIdentity else {
            return nil
        }
        let previousAssignment = state.assignment
        state.assignment = activation.capabilities.assignment
        replaceRegisteredAssignment(
            activation.capabilities.assignment,
            replacing: previousAssignment
        )
        state.activeServicesID = activation.workspaceID
        activeCapabilities = activation.capabilities
        permissionRefreshTask?.cancel()
        permissionRefreshTask = Task { [workspaceStore] in
            await workspaceStore.refreshPendingResearchAgentPermissions(
                in: activation.workspaceID
            )
        }
        return WindowWorkspaceReplacement(
            previousAssignment: previousAssignment
        )
    }

    private func activate(
        assignment: TriptychAssignment,
        openingVault: WorkspaceVaultSlot
    ) async throws {
        let capabilities = try await workspaceStore.workspaceCapabilities(
            id: assignment.id,
            openingVault: openingVault
        )
        try await install(capabilities: capabilities)
    }

    private func install(capabilities: WindowWorkspaceCapabilities) async throws {
        guard let dependencies,
              let snapshot = workspaceStore.snapshot(for: capabilities.runtimeIdentity) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let feedback = try await dependencies.installSession(capabilities, snapshot)
        try Task.checkCancellation()
        activeCapabilities = capabilities
        state.assignment = capabilities.assignment
        state.activeServicesID = capabilities.assignment.id
        if !feedback.transactionRecoveryIssues.isEmpty {
            state.recoveryMessage = ([
                "An interrupted system Trash deletion still requires inspection.",
            ] + feedback.transactionRecoveryIssues).joined(separator: "\n")
        }
    }

    private func replaceRegisteredAssignment(
        _ assignment: TriptychAssignment,
        replacing previous: TriptychAssignment?
    ) {
        state.registeredTriptychs.removeAll {
            $0.id == previous?.id || $0.id == assignment.id
        }
        state.registeredTriptychs.append(assignment)
        state.registeredTriptychs.sort {
            let order = $0.triptych.name.localizedStandardCompare($1.triptych.name)
            return order == .orderedSame
                ? $0.id.uuidString < $1.id.uuidString
                : order == .orderedAscending
        }
        let replacedVaultIDs = Set(previous?.vaults.values.map(\.id) ?? [])
        let currentVaultIDs = Set(assignment.vaults.values.map(\.id))
        state.registeredVaults.removeAll {
            replacedVaultIDs.contains($0.id) || currentVaultIDs.contains($0.id)
        }
        state.registeredVaults.append(contentsOf: assignment.vaults.values)
        state.registeredVaults.sort {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.canonicalPath != $1.canonicalPath {
                return $0.canonicalPath < $1.canonicalPath
            }
            return $0.id.uuidString < $1.id.uuidString
        }
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
                  let works = assignment.vault(for: .output) else {
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
                portableURL = await portableContainerURL(for: replacementWorks)
                    ?? replacementWorks.deletingLastPathComponent()
            }
            try await configureTriptych(
                paperAnalysisURL: replacementAnalyses,
                topicKnowledgeURL: replacementTopics,
                outputURL: replacementWorks,
                portableContainerURL: portableURL,
                triptychID: assignment.id,
                triptychName: assignment.triptych.name,
                openingVault: preferredOpeningVault
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
                  let dependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
            let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            guard let portableURL = await portableContainerURL(for: worksURL) else {
                throw WorkspaceRegistryError.portableControlAccessUnavailable(
                    worksURL.deletingLastPathComponent().path
                )
            }
            let preserved = try await workspaceStore.preserveUnsupportedPortableControl(
                portableContainerURL: portableURL,
                worksURL: worksURL,
                triptychID: assignment.id
            )
            try await configureTriptych(
                paperAnalysisURL: analysesURL,
                topicKnowledgeURL: topicsURL,
                outputURL: worksURL,
                portableContainerURL: portableURL,
                triptychID: assignment.id,
                triptychName: assignment.triptych.name,
                openingVault: preferredOpeningVault
            )
            state.accessRecovery = nil
            state.recoveryMessage = nil
            dependencies.reportInformation(
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
                  let dependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let analysesURL = URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true)
            let topicsURL = URL(fileURLWithPath: topics.canonicalPath, isDirectory: true)
            let worksURL = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
            guard let portableURL = await portableContainerURL(for: worksURL) else {
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
            try await configureTriptych(
                paperAnalysisURL: analysesURL,
                topicKnowledgeURL: topicsURL,
                outputURL: worksURL,
                portableContainerURL: portableURL,
                triptychID: assignment.id,
                triptychName: assignment.triptych.name,
                openingVault: preferredOpeningVault
            )
            state.accessRecovery = nil
            state.recoveryMessage = nil
            dependencies.reportInformation(
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
                  let dependencies else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            try await workspaceStore.removeLocalTriptychRegistration(id: assignment.id)
            activeCapabilities = nil
            state.assignment = nil
            state.activeServicesID = nil
            state.accessRecovery = nil
            state.recoveryMessage = nil
            let refreshedVaults = (try? await workspaceStore.registeredVaults()) ?? []
            let refreshedTriptychs = (try? await workspaceStore.registeredTriptychs()) ?? []
            state.registeredVaults = refreshedVaults
            state.registeredTriptychs = refreshedTriptychs
            dependencies.didRemoveRegistration(assignment)
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
        if let repositoryError = error as? VaultRepositoryError,
           case .rootUnavailable(let path) = repositoryError {
            return WorkspaceAccessRecovery(kind: .vault, expectedPath: path)
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

    private func resolveAssignment(
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
