import Combine
import Foundation
import ScholiumContracts

struct RecommendedBibliographyClient {
    let overview: @MainActor (
        RecommendedBibliographyTarget
    ) async throws -> RecommendedBibliographyOverview
    let prepare: @MainActor (
        RecommendedBibliographyRequest
    ) async throws -> RecommendedBibliographyPreparation
    let cancel: @MainActor (UUID) async throws -> Void
    let dismiss: @MainActor (UUID, UUID) async throws -> Void
}

enum RecommendedBibliographyPanelPhase: Equatable {
    case idle
    case loading
    case ready
    case preparing
    case awaitingAgent
    case cancelling
    case stale
    case cancelled
    case failed
}

/// Per-window owner for the Analysis recommendation draft and projection.
/// It owns no repository, skill package, YAML, or filesystem authority.
@MainActor
final class RecommendedBibliographyController: ObservableObject {
    @Published private(set) var target: RecommendedBibliographyTarget?
    @Published private(set) var projection: RecommendedBibliographyProjection?
    @Published private(set) var preparation: RecommendedBibliographyPreparation?
    @Published private(set) var phase: RecommendedBibliographyPanelPhase = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var needsMethodRepair = false
    @Published var selectedGoals: Set<BibliographyRecommendationGoal> = []
    @Published var purpose = ""

    private var client: RecommendedBibliographyClient?
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?

    var visibleCandidates: [RecommendedBibliographyCandidate] {
        projection?.candidates.filter { !$0.isDismissed } ?? []
    }

    var canPrepare: Bool {
        target != nil
            && preparation == nil
            && phase != .loading
            && phase != .preparing
            && phase != .cancelling
    }

    func bind(_ client: RecommendedBibliographyClient) {
        invalidate()
        self.client = client
    }

    func unbind() {
        invalidate()
        client = nil
    }

    func refresh(for target: RecommendedBibliographyTarget?) async {
        await load(target, force: false)
    }

    private func load(
        _ target: RecommendedBibliographyTarget?,
        force: Bool
    ) async {
        let targetChanged = self.target != target
        guard force || targetChanged || phase == .failed
            || (projection == nil && preparation == nil) else { return }
        generation &+= 1
        let token = generation
        task?.cancel()
        if targetChanged, target != nil {
            projection = nil
            selectedGoals = []
            purpose = ""
        }
        self.target = target
        if targetChanged, target != nil { preparation = nil }
        errorMessage = nil
        needsMethodRepair = false
        guard let target, let client else {
            phase = projection == nil && preparation == nil ? .idle : .ready
            return
        }
        phase = .loading
        do {
            let overview = try await client.overview(target)
            guard token == generation, self.target == target else { return }
            apply(overview)
            needsMethodRepair = false
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            phase = .failed
            needsMethodRepair = methodRepairRequired(error)
            errorMessage = error.localizedDescription
        }
    }

    func prepare() {
        guard let target, let client, canPrepare else { return }
        generation &+= 1
        let token = generation
        phase = .preparing
        errorMessage = nil
        needsMethodRepair = false
        let request = RecommendedBibliographyRequest(
            target: target,
            goals: BibliographyRecommendationGoal.allCases.filter(selectedGoals.contains),
            purpose: purpose
        )
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let preparation = try await client.prepare(request)
                guard token == generation, self.target == target else { return }
                self.preparation = preparation
                phase = .awaitingAgent
            } catch is CancellationError {
                return
            } catch {
                guard token == generation else { return }
                phase = .failed
                needsMethodRepair = methodRepairRequired(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        guard let id = preparation?.id, let client else { return }
        generation &+= 1
        let token = generation
        phase = .cancelling
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.cancel(id)
                guard token == generation else { return }
                preparation = nil
                phase = .cancelled
            } catch is CancellationError {
                return
            } catch {
                guard token == generation else { return }
                phase = .failed
                needsMethodRepair = methodRepairRequired(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismiss(candidateID: UUID) {
        guard let client, let target, let requestID = projection?.id else { return }
        generation &+= 1
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.dismiss(requestID, candidateID)
                await refreshAfterMutation(
                    target: target,
                    client: client,
                    token: token
                )
            } catch {
                guard token == generation, self.target == target else { return }
                needsMethodRepair = methodRepairRequired(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    func retry() async {
        await load(target, force: true)
    }

    private func refreshAfterMutation(
        target: RecommendedBibliographyTarget,
        client: RecommendedBibliographyClient,
        token: UInt64
    ) async {
        do {
            let refreshed = try await client.overview(target)
            guard token == generation, self.target == target else { return }
            apply(refreshed)
            errorMessage = nil
            needsMethodRepair = false
        } catch {
            guard token == generation, self.target == target else { return }
            needsMethodRepair = methodRepairRequired(error)
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ overview: RecommendedBibliographyOverview) {
        projection = overview.result
        preparation = overview.activePreparation
        switch (overview.activePreparation, overview.latestRun?.state) {
        case (.some, _):
            phase = .awaitingAgent
        case (.none, .stale):
            phase = .stale
        case (.none, .cancelled):
            phase = .cancelled
        case (.none, .prepared):
            // A prepared projection without its immutable preparation is a
            // malformed durable state rather than an apparently ready panel.
            phase = .failed
            errorMessage = String(localized: "The pending Recommended Bibliography request could not be restored.", table: "Localizable", bundle: .module)
        case (.none, .complete), (.none, .none):
            phase = .ready
        }
    }

    private func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
        target = nil
        projection = nil
        preparation = nil
        phase = .idle
        errorMessage = nil
        needsMethodRepair = false
        selectedGoals = []
        purpose = ""
    }

    private func methodRepairRequired(_ error: Error) -> Bool {
        guard let error = error as? RecommendedBibliographyError else { return false }
        if case .methodRequiresRepair = error { return true }
        return false
    }
}
