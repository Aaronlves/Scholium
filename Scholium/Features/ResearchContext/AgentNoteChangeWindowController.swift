import Foundation
import ScholiumContracts

struct AgentNoteChangeDisplayTarget: Identifiable, Equatable {
    let id: UUID
    let title: String
    let relativePath: String
    let role: ResearchActionTargetRole
    let expectedFingerprint: DocumentFingerprint
    let currentFingerprint: DocumentFingerprint?
}

struct AgentNoteChangePresentationIdentity: Equatable {
    let actionName: String
    let skillName: String
}

/// The exact-window owner for one Agent Note Change sheet and its transient
/// presentation lifecycle. Durable validation and decisions remain in
/// Application; App-wide request-to-window claims remain in the claim
/// coordinator; AppKit retains native responder capture and restoration.
@MainActor
final class AgentNoteChangeWindowController: ObservableObject {
    struct Dependencies {
        let presentationIdentity:
            @MainActor (AgentNoteChangeRequestRecord) async throws
                -> AgentNoteChangePresentationIdentity
        let refresh:
            @MainActor (_ requestID: UUID, _ triptychID: UUID) async throws -> Void
        let resolve:
            @MainActor (
                _ triptychID: UUID,
                _ requestID: UUID,
                _ state: AgentNoteChangeDecisionState,
                _ allowedNoteIDs: [UUID]
            ) async throws -> AgentNoteChangeRequestRecord
        let snapshot: @MainActor (UUID) -> WorkspaceSnapshot?
        let now: @MainActor () -> Date
        let sleep: @MainActor (Duration) async throws -> Void

        init(
            presentationIdentity: @escaping @MainActor (
                AgentNoteChangeRequestRecord
            ) async throws -> AgentNoteChangePresentationIdentity,
            refresh: @escaping @MainActor (
                _ requestID: UUID,
                _ triptychID: UUID
            ) async throws -> Void,
            resolve: @escaping @MainActor (
                _ triptychID: UUID,
                _ requestID: UUID,
                _ state: AgentNoteChangeDecisionState,
                _ allowedNoteIDs: [UUID]
            ) async throws -> AgentNoteChangeRequestRecord,
            snapshot: @escaping @MainActor (UUID) -> WorkspaceSnapshot?,
            now: @escaping @MainActor () -> Date = Date.init,
            sleep: @escaping @MainActor (Duration) async throws -> Void = {
                try await Task.sleep(for: $0)
            }
        ) {
            self.presentationIdentity = presentationIdentity
            self.refresh = refresh
            self.resolve = resolve
            self.snapshot = snapshot
            self.now = now
            self.sleep = sleep
        }
    }

    @Published private(set) var record: AgentNoteChangeRequestRecord?
    @Published private(set) var identity: AgentNoteChangePresentationIdentity?
    @Published private(set) var identityLoadFailed = false
    @Published private(set) var hasLocallyExpired = false
    @Published private(set) var isResolving = false

    let windowID: UUID

    private let presentationRouter: WindowPresentationRouter
    private let claimCoordinator: AgentNoteChangeClaimCoordinator
    private let dependencies: Dependencies
    private let reportError: @MainActor (String) -> Void
    private var identityTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?
    private var snapshotRefreshTask: Task<Void, Never>?

    init(
        windowID: UUID,
        presentationRouter: WindowPresentationRouter,
        claimCoordinator: AgentNoteChangeClaimCoordinator,
        dependencies: Dependencies,
        reportError: @escaping @MainActor (String) -> Void
    ) {
        self.windowID = windowID
        self.presentationRouter = presentationRouter
        self.claimCoordinator = claimCoordinator
        self.dependencies = dependencies
        self.reportError = reportError
    }

    deinit {
        identityTask?.cancel()
        expiryTask?.cancel()
        decisionTask?.cancel()
        snapshotRefreshTask?.cancel()
    }

    func registerWindowEndpoint(
        activeTriptychID: @escaping @MainActor () -> UUID?,
        isKeyWindow: @escaping @MainActor () -> Bool,
        canPresent: @escaping @MainActor () -> Bool,
        willPresent: @escaping @MainActor () -> Void,
        focus: @escaping @MainActor () -> Void
    ) {
        claimCoordinator.register(.init(
            id: windowID,
            triptychID: activeTriptychID,
            isKeyWindow: isKeyWindow,
            canPresent: canPresent,
            present: { [weak self] record in
                guard let self else { return }
                willPresent()
                self.present(record, activeTriptychID: activeTriptychID())
            },
            update: { [weak self] in self?.update($0) },
            dismiss: { [weak self] in self?.requestDismissal(id: $0) },
            focus: { _ in focus() }
        ))
    }

    func unregisterWindow() {
        claimCoordinator.unregister(windowID: windowID)
        if let requestID = record?.id {
            requestDismissal(id: requestID)
        }
        resetPresentationState()
    }

    func noteWindowActivated() {
        claimCoordinator.noteWindowActivated(windowID)
    }

    func presentationBecameAvailable() {
        claimCoordinator.presentationBecameAvailable(windowID: windowID)
    }

    func present(
        _ record: AgentNoteChangeRequestRecord,
        activeTriptychID: UUID?
    ) {
        guard activeTriptychID == record.request.triptychID,
              presentationRouter.sheet == nil else { return }
        self.record = record
        identity = nil
        identityLoadFailed = false
        hasLocallyExpired = false
        scheduleExpiryRefresh(for: record)
        presentationRouter.present(.agentNoteChange(record.id))
        resolvePresentationIdentity(for: record)
    }

    func update(_ record: AgentNoteChangeRequestRecord) {
        guard self.record?.id == record.id else { return }
        self.record = record
        isResolving = false
        hasLocallyExpired = false
        scheduleExpiryRefresh(for: record)
        if record.isUnresolved, identity == nil {
            resolvePresentationIdentity(for: record)
        } else if !record.isUnresolved {
            identityTask?.cancel()
            identityTask = nil
        }
    }

    func requestDismissal(id: UUID) {
        presentationRouter.dismissSheet(
            if: "agent-note-change:\(id.uuidString.lowercased())"
        )
    }

    func finishDismissal() {
        guard let requestID = record?.id else { return }
        resetPresentationState()
        claimCoordinator.presentationDidDismiss(
            requestID: requestID,
            windowID: windowID
        )
        presentationBecameAvailable()
    }

    func resolve(
        state: AgentNoteChangeDecisionState,
        allowedNoteIDs: [UUID]
    ) {
        guard !isResolving,
              let record,
              record.isUnresolved else { return }
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.scholium.qa",
           ProcessInfo.processInfo.arguments.contains(
               "--scholium-agent-change-request-fixture"
           ) {
            do {
                let resolved = try record.resolving(
                    state: state,
                    allowedNoteIDs: allowedNoteIDs,
                    continuationPlan: state == .allowedSubset
                        ? AgentNoteChangeContinuationPlan(
                            groupID: record.request.parentRunID,
                            parentRunID: record.request.parentRunID,
                            requestID: record.id,
                            childPhases: allowedNoteIDs.map {
                                AgentNoteChangeChildPhasePlan(noteID: $0)
                            }
                        )
                        : nil,
                    at: dependencies.now()
                )
                claimCoordinator.receive(resolved, intent: .decision)
            } catch {
                reportError(error.localizedDescription)
            }
            return
        }
        #endif

        isResolving = true
        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await dependencies.resolve(
                    record.request.triptychID,
                    record.id,
                    state,
                    allowedNoteIDs
                )
                guard self.record?.id == record.id else { return }
                if resolved.decision.state == .stale
                    || resolved.decision.state == .expired {
                    update(resolved)
                }
                decisionTask = nil
            } catch is CancellationError {
                guard self.record?.id == record.id else { return }
                isResolving = false
                decisionTask = nil
            } catch {
                guard self.record?.id == record.id else { return }
                isResolving = false
                decisionTask = nil
                reportError(
                    "Scholium could not record this decision. \(error.localizedDescription)"
                )
            }
        }
    }

    func refreshForWorkspaceSnapshot(triptychID: UUID) {
        guard let record,
              record.isUnresolved,
              record.request.triptychID == triptychID else { return }
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await dependencies.refresh(record.id, record.request.triptychID)
            guard self.record?.id == record.id else { return }
            snapshotRefreshTask = nil
        }
    }

    func displayTargets(
        for record: AgentNoteChangeRequestRecord
    ) -> [AgentNoteChangeDisplayTarget] {
        let snapshot = dependencies.snapshot(record.request.triptychID)
        return record.request.targets.map { target in
            let currentDocument = snapshot?.document(id: target.note)
            let title: String
            if let note = currentDocument {
                title = ResearchNoteTitleResolver.resolve(
                    document: note.document,
                    vaultRole: note.vaultRole
                ).title
            } else {
                title = URL(fileURLWithPath: target.note.relativePath)
                    .deletingPathExtension().lastPathComponent
            }
            return AgentNoteChangeDisplayTarget(
                id: target.noteID,
                title: title,
                relativePath: target.note.relativePath,
                role: target.role,
                expectedFingerprint: target.expectedFingerprint,
                currentFingerprint: currentDocument?.fingerprint
            )
        }
    }

    #if DEBUG
    func presentQASyntheticRequest(activeTriptychID: UUID?) {
        guard Bundle.main.bundleIdentifier == "com.scholium.qa",
              let triptychID = activeTriptychID,
              let snapshot = dependencies.snapshot(triptychID),
              let note = snapshot.vaults
                .first(where: { $0.vault.role == .topicKnowledge })?
                .documents.first,
              let noteID = note.stableIdentity.resolvedID else { return }
        do {
            let parent = try AgentNoteChangeActionRevision(
                definition: .analyze,
                packageID: "scholium-analyze",
                skillRevision: DocumentFingerprint(content: "qa-analyze-skill"),
                profileOrigin: .applicationDefault,
                profileRevision: DocumentFingerprint(content: "qa-analyze-profile"),
                profileDocumentRevision: nil
            )
            let requested = try AgentNoteChangeActionRevision(
                definition: .synthesize,
                packageID: "scholium-synthesize",
                skillRevision: DocumentFingerprint(content: "qa-synthesize-skill"),
                profileOrigin: .applicationDefault,
                profileRevision: DocumentFingerprint(content: "qa-synthesize-profile"),
                profileDocumentRevision: nil
            )
            let request = try AgentNoteChangeRequest(
                triptychID: triptychID,
                parentRunID: UUID(),
                parentAction: parent,
                requestedAction: requested,
                targets: [try AgentNoteChangeTarget(
                    noteID: noteID,
                    note: note.id,
                    role: .topic,
                    expectedFingerprint: note.fingerprint
                )],
                operations: [.modifyMarkdown],
                agentReason: "The current analysis may qualify this Topic. Review the requested Note before allowing a separate synthesis phase."
            )
            let record = try AgentNoteChangeRequestRecord(
                request: request,
                receivedAt: dependencies.now(),
                validFor: 10 * 60
            )
            claimCoordinator.receive(record, intent: .submit)
        } catch {
            reportError(error.localizedDescription)
        }
    }
    #endif

    private func resolvePresentationIdentity(
        for record: AgentNoteChangeRequestRecord
    ) {
        guard record.isUnresolved,
              self.record?.id == record.id,
              identityTask == nil else { return }
        identityLoadFailed = false
        identityTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 0..<3 {
                do {
                    let identity = try await dependencies.presentationIdentity(record)
                    guard self.record?.id == record.id else {
                        identityTask = nil
                        return
                    }
                    self.identity = identity
                    identityTask = nil
                    return
                } catch is CancellationError {
                    identityTask = nil
                    return
                } catch where attempt < 2 {
                    do {
                        try await dependencies.sleep(
                            .milliseconds(250 * (attempt + 1))
                        )
                    } catch {
                        identityTask = nil
                        return
                    }
                } catch {
                    break
                }
            }
            try? await dependencies.refresh(record.id, record.request.triptychID)
            guard self.record?.id == record.id else {
                identityTask = nil
                return
            }
            identityLoadFailed = true
            identityTask = nil
        }
    }

    private func scheduleExpiryRefresh(
        for record: AgentNoteChangeRequestRecord
    ) {
        expiryTask?.cancel()
        expiryTask = nil
        guard record.isUnresolved else { return }
        let delay = max(0, record.expiresAt.timeIntervalSince(dependencies.now()))
        expiryTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await dependencies.sleep(.seconds(delay))
                try Task.checkCancellation()
            } catch {
                return
            }
            guard self.record?.id == record.id else { return }
            hasLocallyExpired = true
            isResolving = true
            for attempt in 0..<3 {
                do {
                    try await dependencies.refresh(record.id, record.request.triptychID)
                    return
                } catch is CancellationError {
                    return
                } catch where attempt < 2 {
                    try? await dependencies.sleep(
                        .milliseconds(250 * (attempt + 1))
                    )
                } catch {
                    break
                }
            }
            guard self.record?.id == record.id,
                  let expired = try? record.expiringIfNeeded(
                    at: dependencies.now()
                  ) else { return }
            claimCoordinator.receive(expired, intent: .refresh)
        }
    }

    private func resetPresentationState() {
        record = nil
        identity = nil
        identityLoadFailed = false
        hasLocallyExpired = false
        isResolving = false
        identityTask?.cancel()
        identityTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        decisionTask?.cancel()
        decisionTask = nil
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
    }
}
