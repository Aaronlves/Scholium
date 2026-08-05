import Foundation
import ScholiumContracts

/// Exact-window owner for one Agent permission sheet. It never resolves paths,
/// identities, revisions, policy, Methods, Profiles, or checkpoints itself.
@MainActor
final class ResearchAgentPermissionWindowController: ObservableObject {
    struct Dependencies {
        let refreshWriteSet: @MainActor (
            _ requestID: UUID,
            _ triptychID: UUID
        ) async throws -> Void
        let resolveWriteSet: @MainActor (
            _ triptychID: UUID,
            _ requestID: UUID,
            _ state: ResearchWriteSetExtensionState,
            _ allowedHandles: [ResearchWriteTargetHandle]
        ) async throws -> ResearchWriteSetExtensionRecord
        let refreshContinuation: @MainActor (
            _ triptychID: UUID,
            _ parentRunID: UUID,
            _ requestID: UUID
        ) async throws -> Void
        let resolveContinuation: @MainActor (
            _ triptychID: UUID,
            _ parentRunID: UUID,
            _ requestID: UUID,
            _ allow: Bool
        ) async throws -> ResearchContinuationRequestRecord
        let now: @MainActor () -> Date
        let sleep: @MainActor (Duration) async throws -> Void

        init(
            refreshWriteSet: @escaping @MainActor (
                _ requestID: UUID,
                _ triptychID: UUID
            ) async throws -> Void,
            resolveWriteSet: @escaping @MainActor (
                _ triptychID: UUID,
                _ requestID: UUID,
                _ state: ResearchWriteSetExtensionState,
                _ allowedHandles: [ResearchWriteTargetHandle]
            ) async throws -> ResearchWriteSetExtensionRecord,
            refreshContinuation: @escaping @MainActor (
                _ triptychID: UUID,
                _ parentRunID: UUID,
                _ requestID: UUID
            ) async throws -> Void,
            resolveContinuation: @escaping @MainActor (
                _ triptychID: UUID,
                _ parentRunID: UUID,
                _ requestID: UUID,
                _ allow: Bool
            ) async throws -> ResearchContinuationRequestRecord,
            now: @escaping @MainActor () -> Date = Date.init,
            sleep: @escaping @MainActor (Duration) async throws -> Void = {
                try await Task.sleep(for: $0)
            }
        ) {
            self.refreshWriteSet = refreshWriteSet
            self.resolveWriteSet = resolveWriteSet
            self.refreshContinuation = refreshContinuation
            self.resolveContinuation = resolveContinuation
            self.now = now
            self.sleep = sleep
        }
    }

    @Published private(set) var claim: ResearchAgentPermissionClaim?
    @Published private(set) var hasLocallyExpired = false
    @Published private(set) var isResolving = false

    let windowID: UUID
    private let presentationRouter: WindowPresentationRouter
    private let claimCoordinator: ResearchAgentPermissionClaimCoordinator
    private let dependencies: Dependencies
    private let reportError: @MainActor (String) -> Void
    private var expiryTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?

    init(
        windowID: UUID,
        presentationRouter: WindowPresentationRouter,
        claimCoordinator: ResearchAgentPermissionClaimCoordinator,
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
        expiryTask?.cancel()
        decisionTask?.cancel()
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
            present: { [weak self] claim in
                willPresent()
                self?.present(claim, activeTriptychID: activeTriptychID())
            },
            update: { [weak self] in self?.update($0) },
            dismiss: { [weak self] in self?.requestDismissal(id: $0) },
            focus: { _ in focus() }
        ))
    }

    func unregisterWindow() {
        if let requestID = claim?.id {
            presentationRouter.dismissSheet(
                if: "research-agent-permission:\(requestID.uuidString.lowercased())"
            )
        }
        claimCoordinator.unregister(windowID: windowID)
        resetPresentationState()
    }

    func noteWindowActivated() {
        claimCoordinator.noteWindowActivated(windowID)
    }

    func presentationBecameAvailable() {
        claimCoordinator.presentationBecameAvailable(windowID: windowID)
    }

    func present(
        _ claim: ResearchAgentPermissionClaim,
        activeTriptychID: UUID?
    ) {
        guard activeTriptychID == claim.triptychID,
              presentationRouter.sheet == nil else { return }
        self.claim = claim
        hasLocallyExpired = false
        scheduleExpiryRefresh(for: claim)
        presentationRouter.present(.researchAgentPermission(claim.id))
    }

    func update(_ claim: ResearchAgentPermissionClaim) {
        guard self.claim?.id == claim.id else { return }
        self.claim = claim
        isResolving = false
        hasLocallyExpired = false
        scheduleExpiryRefresh(for: claim)
    }

    func resolveWriteSet(
        state: ResearchWriteSetExtensionState,
        allowedHandles: [ResearchWriteTargetHandle]
    ) {
        guard !isResolving,
              case .writeSetExtension(let record) = claim,
              record.isUnresolved else { return }
        beginDecision(recordID: record.id) { [dependencies] in
            _ = try await dependencies.resolveWriteSet(
                record.triptychID,
                record.id,
                state,
                allowedHandles
            )
        }
    }

    func resolveContinuation(allow: Bool) {
        guard !isResolving,
              case .continuation(let record) = claim,
              record.state == .pending else { return }
        beginDecision(recordID: record.id) { [dependencies] in
            _ = try await dependencies.resolveContinuation(
                record.triptychID,
                record.parentRunID,
                record.id,
                allow
            )
        }
    }

    func refreshForWorkspaceSnapshot(triptychID: UUID) {
        guard let claim,
              claim.isUnresolved,
              claim.triptychID == triptychID else { return }
        Task { try? await refresh(claim) }
    }

    func requestDismissal(id: UUID) {
        presentationRouter.dismissSheet(
            if: "research-agent-permission:\(id.uuidString.lowercased())"
        )
    }

    func finishDismissal() {
        guard let requestID = claim?.id else { return }
        resetPresentationState()
        claimCoordinator.presentationDidDismiss(
            requestID: requestID,
            windowID: windowID
        )
        presentationBecameAvailable()
    }

    private func beginDecision(
        recordID: UUID,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        isResolving = true
        decisionTask?.cancel()
        decisionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await operation()
            } catch is CancellationError {
                guard self.claim?.id == recordID else { return }
                isResolving = false
            } catch {
                guard self.claim?.id == recordID else { return }
                isResolving = false
                reportError(
                    "Scholium could not record this Agent permission decision. \(error.localizedDescription)"
                )
            }
            decisionTask = nil
        }
    }

    private func scheduleExpiryRefresh(
        for claim: ResearchAgentPermissionClaim
    ) {
        expiryTask?.cancel()
        guard claim.isUnresolved else { return }
        let delay = max(0, claim.expiresAt.timeIntervalSince(dependencies.now()))
        expiryTask = Task { [weak self] in
            guard let self else { return }
            do { try await dependencies.sleep(.seconds(delay)) }
            catch { return }
            guard self.claim?.id == claim.id else { return }
            hasLocallyExpired = true
            isResolving = true
            try? await refresh(claim)
        }
    }

    private func refresh(_ claim: ResearchAgentPermissionClaim) async throws {
        switch claim {
        case .writeSetExtension(let record):
            try await dependencies.refreshWriteSet(record.id, record.triptychID)
        case .continuation(let record):
            try await dependencies.refreshContinuation(
                record.triptychID,
                record.parentRunID,
                record.id
            )
        }
    }

    private func resetPresentationState() {
        claim = nil
        hasLocallyExpired = false
        isResolving = false
        expiryTask?.cancel()
        expiryTask = nil
        decisionTask?.cancel()
        decisionTask = nil
    }
}
