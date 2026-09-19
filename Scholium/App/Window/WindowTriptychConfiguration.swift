import Foundation
import ScholiumContracts

/// Binding the window to a Triptych: adopting a workspace activation,
/// installing its session, and the capabilities that activation grants.
extension WindowModel {
    func startWorkspaceObservers() {
        let relay = WindowModelObserverRelay(model: self)
        let activationHandler: @Sendable (WorkspaceActivation) -> Void = { activation in
            deliverWorkspaceActivation(activation, to: relay.model)
        }
        workspaceStore.$latestWorkspaceActivation
            .compactMap(nonisolatedWorkspaceActivation)
            .sink(receiveValue: activationHandler)
            .store(in: &workspaceCancellables)

        let workspaceEventsHandler: @Sendable ([UUID: WorkspaceEvent]) -> Void = { events in
            deliverWorkspaceEvents(events, to: relay.model)
        }
        workspaceStore.$workspaceEvents
            .sink(receiveValue: workspaceEventsHandler)
            .store(in: &workspaceCancellables)

        let confirmedAgentChangeHandler: @Sendable (AgentChange?) -> Void = { change in
            guard let change else { return }
            deliverConfirmedAgentChange(change, to: relay.model)
        }
        workspaceStore.$lastConfirmedAgentChange
            .sink(receiveValue: confirmedAgentChangeHandler)
            .store(in: &workspaceCancellables)

        observeWindowSessionChanges()
    }

    func refreshWorkspaceAssignment(preferredTriptychID: UUID? = nil) async {
        let outcome = await windowWorkspaceController.refreshWorkspaceAssignment(
            preferredTriptychID: preferredTriptychID,
            openingVault: shellState.selectedWorkspace
        )
        switch outcome {
        case .unavailable, .activated:
            break
        case .recoveryRequired:
            vaultError = nil
        case .failed(let message):
            vaultError = message
        }
    }

    func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws {
        let openingVault = requestedInitialWorkspaceSlot
        let assignment = try await windowWorkspaceController.configureTriptych(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL,
            portableContainerURL: portableContainerURL,
            triptychID: triptychID,
            triptychName: triptychName,
            openingVault: openingVault
        )
        PerformanceProbe.shared.markWarmLibraryWorkspaceReady()
        if let current = currentRegisteredVault,
            let assignedCurrent = assignment.vaults.values.first(where: {
                $0.id == current.id || $0.canonicalPath == current.canonicalPath
            })
        {
            currentRegisteredVault = assignedCurrent
            currentVaultRole = assignedCurrent.role
            return
        }
        try await openWorkspaceVault(openingVault)
    }

    var requestedTriptychIDForRecovery: UUID? { requestedTriptychID }

    func installWindowWorkspaceSession(
        capabilities: WindowWorkspaceCapabilities,
        snapshot: WorkspaceSnapshot
    ) async throws -> [String] {
        bindApplicationCapabilities(
            to: capabilities,
            snapshot: snapshot
        )
        var activationIssues = snapshot.research.healthIssues
        if let settingsIssue = try await loadTriptychSettingsProjection() {
            activationIssues.append(settingsIssue)
        }
        if !activationIssues.isEmpty {
            vaultError =
                ([
                    "Some workspace state could not be loaded. The affected files remain unchanged; see the details for unavailable operations."
                ] + activationIssues).joined(separator: "\n\n")
        }
        let recoveryIssues = try await libraryMutationController.recoverInterruptedTransactions()
        await refreshTransactionRecoveryRecords()
        PerformanceProbe.shared.markStartupSafetyReady()
        return recoveryIssues
    }

    private func loadTriptychSettingsProjection() async throws -> String? {
        let state = try await researchController.settingsLoadState()
        switch state {
        case .current(let snapshot):
            triptychSettings = snapshot.settings
            return nil
        case .needsReview(let settings, _, let reason):
            triptychSettings = settings
            return TriptychControlError.settingsNeedsReview(reason).localizedDescription
        case .missing:
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsMissing.localizedDescription
        case .oldSchema(let version):
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsOldSchema(version).localizedDescription
        case .futureSchema(let version):
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsFutureSchema(version).localizedDescription
        case .corrupted:
            triptychSettings = TriptychSettings()
            return TriptychControlError.settingsCorrupted.localizedDescription
        }
    }

    private func bindApplicationCapabilities(
        to capabilities: WindowWorkspaceCapabilities,
        snapshot: WorkspaceSnapshot? = nil
    ) {
        discoveryController.bind(to: capabilities.discovery)
        libraryMutationController.bind(to: capabilities.libraryMutations)
        documentController.bind(
            to: capabilities.documents,
            snapshot: snapshot,
            documentDidCommit: { [weak self] result in
                guard let self else { return }
                _ = await self.replaceSavedDocument(result.document)
            }
        )
        researchController.bind(
            to: ResearchControllerCapabilities(
                triptychID: capabilities.id,
                documents: capabilities.documents,
                research: capabilities.research.research,
                agentCollaboration: capabilities.agentCollaboration,
                recoveryRecordsURL: capabilities.research.recoveryRecordsURL
            ),
            snapshot: snapshot
        )
    }

    func adoptWorkspaceActivation(_ activation: WorkspaceActivation) {
        guard let replacement = windowWorkspaceController.adopt(activation) else { return }
        PerformanceProbe.shared.markWarmLibraryWorkspaceReady()

        let previousAssignment = replacement.previousAssignment
        let previousVault = currentRegisteredVault
        bindApplicationCapabilities(
            to: activation.capabilities,
            snapshot: activation.snapshot
        )
        editorFlushCoordinator.activateTriptych(activation.workspaceID) { [weak self] in
            guard let self else { return }
            try await self.documentController.flushLeasedOrPinnedSessions()
        }

        if let previousVault {
            let previousSlot = WorkspaceVaultSlot.allCases.first(where: { slot in
                guard let assigned = previousAssignment?.vault(for: slot) else { return false }
                return assigned.id == previousVault.id
                    || assigned.canonicalPath == previousVault.canonicalPath
            })
            let rebound =
                previousSlot.flatMap { slot in
                    activation.capabilities.assignment.vault(for: slot)
                }
                ?? activation.capabilities.assignment.vaults.values.first(where: {
                    $0.id == previousVault.id
                        || $0.canonicalPath == previousVault.canonicalPath
                })
            if let rebound {
                currentRegisteredVault = rebound
                currentVaultRole = rebound.role
            }
        }

        let projectionCommit = workspaceProjectionController.activate(
            snapshot: activation.snapshot,
            runtimeIdentity: activation.runtimeIdentity,
            context: workspaceProjectionContext
        )
        applyWorkspaceProjectionCommit(projectionCommit)
        if currentRegisteredVault != nil {
            PerformanceProbe.shared.markWarmLibraryProjectionReady()
        }
    }

    var currentWorkspaceSlot: WorkspaceVaultSlot? {
        let selected = shellState.selectedWorkspace
        return workspaceAssignment?.vault(for: selected) == nil ? nil : selected
    }
}
