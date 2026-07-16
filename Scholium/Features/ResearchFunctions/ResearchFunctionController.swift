import ScholiumContracts
import Combine
import Foundation

/// The window composition root supplies these delivery-neutral closures. The
/// client deliberately exposes no repository, skill package, YAML, or file
/// system surface to the feature controller.
struct ResearchFunctionClient {
    let availableFunctions: @MainActor (
        ResearchFunctionTarget
    ) async throws -> [ResearchFunctionAvailability]
    let materialCandidates: @MainActor (
        ResearchFunctionTarget,
        ResearchFunctionID
    ) async throws -> [ResearchFunctionMaterialCandidate]
    let prepare: @MainActor (
        ResearchFunctionRequest
    ) async throws -> ResearchFunctionPreparation
    let complete: @MainActor (
        ResearchFunctionCompletionSubmission
    ) async throws -> ResearchFunctionCompletion
    let cancel: @MainActor (UUID) async throws -> Void
}

enum ResearchFunctionPanelPhase: Equatable {
    case idle
    case loading
    case editing
    case preparing
    case prepared
    case awaitingFidelity
    case unverified
    case completed
    case stale
    case cancelling
    case cancelled
    case failed
}

/// Per-window draft owner for one Research Function panel.
///
/// Target identity is immutable for the lifetime of a presentation. Every
/// asynchronous response is generation-gated so a response from a previous
/// runtime, note, or panel can never replace the current draft.
@MainActor
final class ResearchFunctionController: ObservableObject {
    @Published private(set) var target: ResearchFunctionTarget?
    @Published private(set) var activeFunction: ResearchFunctionID?
    @Published private(set) var presentationID: UUID?
    @Published private(set) var phase: ResearchFunctionPanelPhase = .idle
    @Published private(set) var availability: [
        ResearchFunctionID: ResearchFunctionAvailability
    ] = [:]
    @Published private(set) var materialCandidates: [
        ResearchFunctionMaterialCandidate
    ] = []
    @Published private(set) var preparation: ResearchFunctionPreparation?
    @Published private(set) var targetRuns: [ResearchFunctionRecordProjection] = []
    @Published private(set) var errorMessage: String?

    @Published var instruction = ""
    @Published var selectedMaterialIDs: Set<UUID> = []
    @Published var scopeKind: ResearchFunctionScopeKind = .whole
    @Published var selectedCommentIDs: Set<UUID> = []
    @Published var fidelityChecks: Set<FidelityCheck> = [.content]

    private var passageSelection: ResearcherCommentAnchor?
    private var client: ResearchFunctionClient?
    private var generation: UInt64 = 0
    private var availabilityGeneration: UInt64 = 0
    private var loadingTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?

    var isPresented: Bool { presentationID != nil }
    var isBusy: Bool { phase == .loading || phase == .preparing || phase == .cancelling }
    var passageIsAvailable: Bool { passageSelection != nil }

    /// A reused Fidelity preparation has no newly persisted run to cancel.
    /// Ordinary prepared runs remain cancellable until durable completion
    /// evidence appears in the workspace projection.
    var canCancelPreparedRun: Bool {
        guard let preparation,
              preparation.state == .prepared,
              preparation.reusedCompletion == nil else { return false }
        return presentedRun?.completion == nil
    }

    var presentedRun: ResearchFunctionRecordProjection? {
        guard let runID = preparation?.runID else { return nil }
        return targetRuns.first { $0.id == runID }
    }

    var selectedMaterials: [ResearchFunctionMaterial] {
        materialCandidates
            .filter { selectedMaterialIDs.contains($0.id) }
            .map(\.material)
    }

    var scope: ResearchFunctionScope? {
        switch scopeKind {
        case .whole:
            .whole
        case .passage:
            passageSelection.map(ResearchFunctionScope.passage)
        }
    }

    var canPrepare: Bool {
        guard let function = activeFunction,
              target != nil,
              availability[function]?.isEnabled == true,
              !isBusy,
              phase != .prepared,
              function != .review else { return false }
        if function == .fidelity { return !fidelityChecks.isEmpty }
        if function == .dialogue {
            return !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    func bind(_ client: ResearchFunctionClient) {
        invalidate(clearAvailability: true)
        targetRuns = []
        self.client = client
    }

    func unbind() {
        invalidate(clearAvailability: true)
        targetRuns = []
        client = nil
    }

    func refreshAvailability(for target: ResearchFunctionTarget?) async {
        guard let target, let client else {
            availability = [:]
            return
        }
        availabilityGeneration &+= 1
        let token = availabilityGeneration
        do {
            let result = try await client.availableFunctions(target)
            guard token == availabilityGeneration,
                  self.target == nil || self.target == target else { return }
            availability = Dictionary(uniqueKeysWithValues: result.map { ($0.function, $0) })
            if phase == .loading, self.target == target { phase = .editing }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard token == availabilityGeneration else { return }
            availability = [:]
            if self.target == target { phase = .failed }
            errorMessage = error.localizedDescription
        }
    }

    /// Receives immutable durable projections from the current workspace
    /// generation. These survive panel dismissal and never merge Dialogue,
    /// Critique, Human Review, Comments, or Fidelity findings into one record.
    func receive(
        _ runs: [ResearchFunctionRecordProjection],
        targetNoteID: UUID?
    ) {
        guard let targetNoteID else {
            targetRuns = []
            return
        }
        targetRuns = runs
            .filter { $0.snapshot.request.target.noteID == targetNoteID }
            .sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        guard let run = presentedRun else { return }
        phase = switch run.runState {
        case .prepared: .prepared
        case .awaitingFidelity: .awaitingFidelity
        case .complete: .completed
        case .unverified: .unverified
        case .stale: .stale
        case .cancelled: .cancelled
        }
    }

    func begin(
        target: ResearchFunctionTarget,
        function: ResearchFunctionID,
        selection: ResearcherCommentAnchor?,
        presentationID: UUID
    ) {
        invalidate(clearAvailability: false)
        self.target = target
        activeFunction = function
        self.presentationID = presentationID
        passageSelection = selection
        scopeKind = selection == nil ? .whole : .passage
        fidelityChecks = [.content]
        instruction = ""
        selectedMaterialIDs = []
        selectedCommentIDs = []
        phase = .loading

        let token = generation
        loadingTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                async let available = client.availableFunctions(target)
                async let candidates = client.materialCandidates(target, function)
                let (availability, materialCandidates) = try await (available, candidates)
                guard self.accepts(token),
                      self.target == target,
                      self.presentationID == presentationID else { return }
                self.availability = Dictionary(
                    uniqueKeysWithValues: availability.map { ($0.function, $0) }
                )
                self.materialCandidates = materialCandidates
                self.phase = .editing
                self.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard self.accepts(token), self.presentationID == presentationID else { return }
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func setScope(_ kind: ResearchFunctionScopeKind) {
        guard kind == .whole || passageSelection != nil else { return }
        scopeKind = kind
    }

    func setMaterialSelected(_ id: UUID, isSelected: Bool) {
        guard let candidate = materialCandidates.first(where: { $0.id == id }),
              candidate.isSelectable else { return }
        if isSelected {
            selectedMaterialIDs.insert(id)
        } else {
            selectedMaterialIDs.remove(id)
        }
    }

    func setCommentSelected(_ id: UUID, isSelected: Bool) {
        if isSelected {
            selectedCommentIDs.insert(id)
        } else {
            selectedCommentIDs.remove(id)
        }
    }

    func setFidelityCheck(_ check: FidelityCheck, isSelected: Bool) {
        guard fidelityCheckAvailability(check)?.isEnabled == true else { return }
        if isSelected {
            fidelityChecks.insert(check)
        } else {
            fidelityChecks.remove(check)
        }
    }

    func fidelityCheckAvailability(
        _ check: FidelityCheck
    ) -> ResearchFunctionCheckAvailability? {
        availability[.fidelity]?.fidelityChecks.first { $0.check == check }
    }

    func prepare() {
        guard let client,
              let function = activeFunction,
              let target,
              let presentationID,
              canPrepare else { return }

        let request = ResearchFunctionRequest(
            function: function,
            target: target,
            materials: selectedMaterials,
            instruction: instruction,
            scope: scope,
            checks: function == .fidelity ? fidelityChecks : [],
            commentIDs: selectedCommentIDs.sorted { $0.uuidString < $1.uuidString }
        )
        do {
            try request.validate()
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            return
        }

        let token = nextGeneration()
        phase = .preparing
        errorMessage = nil
        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.prepare(request)
                guard self.accepts(token),
                      self.target == target,
                      self.presentationID == presentationID else { return }
                self.preparation = result
                self.phase = Self.panelPhase(for: result.state)
            } catch is CancellationError {
                return
            } catch {
                guard self.accepts(token), self.presentationID == presentationID else { return }
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelPreparedRun() {
        guard let client, let runID = preparation?.runID else {
            dismiss()
            return
        }
        let token = nextGeneration()
        phase = .cancelling
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.cancel(runID)
                guard self.accepts(token) else { return }
                self.phase = .cancelled
                self.preparation = nil
            } catch is CancellationError {
                return
            } catch {
                guard self.accepts(token) else { return }
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func dismiss(presentationID: UUID? = nil) {
        if let presentationID, self.presentationID != presentationID { return }
        invalidate(clearAvailability: false)
    }

    func invalidateIfTargetChanged(_ current: ResearchFunctionTarget?) {
        guard let target else { return }
        guard current?.noteID == target.noteID,
              current?.note == target.note,
              current?.fingerprint == target.fingerprint else {
            invalidate(clearAvailability: false)
            return
        }
    }

    private func invalidate(clearAvailability: Bool) {
        _ = nextGeneration()
        availabilityGeneration &+= 1
        loadingTask?.cancel()
        preparationTask?.cancel()
        loadingTask = nil
        preparationTask = nil
        target = nil
        activeFunction = nil
        presentationID = nil
        materialCandidates = []
        preparation = nil
        errorMessage = nil
        instruction = ""
        selectedMaterialIDs = []
        scopeKind = .whole
        passageSelection = nil
        selectedCommentIDs = []
        fidelityChecks = [.content]
        phase = .idle
        if clearAvailability { availability = [:] }
    }

    @discardableResult
    private func nextGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func accepts(_ token: UInt64) -> Bool {
        token == generation && !Task.isCancelled
    }

    private static func panelPhase(
        for state: ResearchFunctionRunState
    ) -> ResearchFunctionPanelPhase {
        switch state {
        case .prepared: .prepared
        case .awaitingFidelity: .awaitingFidelity
        case .complete: .completed
        case .unverified: .unverified
        case .stale: .stale
        case .cancelled: .cancelled
        }
    }
}

extension ResearchFunctionRecordProjection {
    var runState: ResearchFunctionRunState {
        completion?.state ?? .prepared
    }
}

extension ResearchFunctionRepairReason {
    var interfaceDescription: String {
        switch code {
        case .targetUnavailable:
            "The current note is unavailable."
        case .targetChanged:
            "The note changed; reopen the function."
        case .targetIdentityChanged:
            "The note identity changed; reopen the function."
        case .invalidTargetRole:
            "This function is not available for this kind of note."
        case .inactiveTarget:
            "This function requires an active note."
        case .missingWorkflow:
            "The required workflow is not available."
        case .invalidWorkflow:
            "The workflow needs repair in Research Guidance."
        case .missingCapability:
            "Install and bind a matching Researcher Skill in Settings."
        case .malformedBinding:
            "The Researcher Skill binding needs repair in Settings."
        case .humanReviewOnly:
            "Review is completed by the researcher in Scholium."
        }
    }
}
