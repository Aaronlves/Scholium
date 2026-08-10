import Combine
import Foundation
import ScholiumContracts

struct ResearchActionClient {
    let availableActions: @MainActor (
        ResearchActionNoteSnapshot
    ) async throws -> [ResearchActionAvailability]
    let materialCandidates: @MainActor (
        ResearchActionNoteSnapshot,
        ResearchActionDefinition
    ) async throws -> [ResearchActionNoteSnapshot]
    let sourceAccess: @MainActor (
        ResearchActionNoteSnapshot
    ) async throws -> ResearchSourceAccessStatus
    let bindLocalSource: @MainActor (
        ResearchActionNoteSnapshot,
        URL
    ) async throws -> ResearchSourceReference
    let prepare: @MainActor (
        ResearchActionExecutionRequest,
        MaterialChangedSinceUseAttentionContext?
    ) async throws -> ResearchActionPreparation
    let actionRun: @MainActor (UUID) async throws -> ResearchActionPreparation
    let handoff: @MainActor (UUID) async throws -> ResearchAgentHandoff
    let cancel: @MainActor (UUID) async throws -> Void
    let openActiveDiscussion: @MainActor (UUID) -> Void

    init(
        availableActions: @escaping @MainActor (ResearchActionNoteSnapshot) async throws -> [ResearchActionAvailability],
        materialCandidates: @escaping @MainActor (ResearchActionNoteSnapshot, ResearchActionDefinition) async throws -> [ResearchActionNoteSnapshot],
        sourceAccess: @escaping @MainActor (ResearchActionNoteSnapshot) async throws -> ResearchSourceAccessStatus,
        bindLocalSource: @escaping @MainActor (ResearchActionNoteSnapshot, URL) async throws -> ResearchSourceReference,
        prepare: @escaping @MainActor (ResearchActionExecutionRequest, MaterialChangedSinceUseAttentionContext?) async throws -> ResearchActionPreparation,
        actionRun: @escaping @MainActor (UUID) async throws -> ResearchActionPreparation = { _ in
            throw ResearchActionExecutionContractError.staleResolution
        },
        handoff: @escaping @MainActor (UUID) async throws -> ResearchAgentHandoff = { _ in
            throw ResearchActionExecutionContractError.staleResolution
        },
        cancel: @escaping @MainActor (UUID) async throws -> Void,
        openActiveDiscussion: @escaping @MainActor (UUID) -> Void
    ) {
        self.availableActions = availableActions
        self.materialCandidates = materialCandidates
        self.sourceAccess = sourceAccess
        self.bindLocalSource = bindLocalSource
        self.prepare = prepare
        self.actionRun = actionRun
        self.handoff = handoff
        self.cancel = cancel
        self.openActiveDiscussion = openActiveDiscussion
    }
}

enum ResearchActionPanelPhase: Equatable {
    case idle
    case loading
    case editing
    case preparing
    case prepared
    case cancelling
    case cancelled
    case failed
}

struct ResearchActionCancellationRecovery: Equatable, Identifiable {
    let runID: UUID
    let errorMessage: String

    var id: UUID { runID }
}

/// Per-window owner for the common, Profile-generated Action sheet. It keeps
/// researcher-entered academic values and protected selector values transient
/// and delegates every durable
/// identity, revision, authority, recovery, and completion decision to the
/// Application boundary.
@MainActor
final class ResearchActionController: ObservableObject {
    private typealias CancellationOperation = @MainActor (UUID) async throws -> Void

    @Published private(set) var target: ResearchActionNoteSnapshot?
    @Published private(set) var activeActionID: ResearchActionID?
    @Published private(set) var presentationID: UUID?
    @Published private(set) var availability: [ResearchActionAvailability] = []
    @Published private(set) var availabilityTarget: ResearchActionNoteSnapshot?
    @Published private(set) var isRefreshingAvailability = false
    @Published private(set) var availabilityError: String?
    @Published private(set) var presentationAvailability: ResearchActionAvailability?
    @Published private(set) var phase: ResearchActionPanelPhase = .idle
    @Published private(set) var materialCandidates: [ResearchActionNoteSnapshot] = []
    @Published private(set) var isLoadingMaterialCandidates = false
    @Published private(set) var sourceStatus: ResearchSourceAccessStatus?
    @Published private(set) var isLoadingSourceStatus = false
    @Published private(set) var preparation: ResearchActionPreparation?
    @Published private(set) var agentHandoff: ResearchAgentHandoff?
    @Published private(set) var resultRecord: PortableResearchRecord?
    @Published private(set) var continuationRecords: [PortableResearchRecord] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBindingSource = false
    @Published private(set) var cancellationRecoveries: [ResearchActionCancellationRecovery] = []
    @Published private(set) var retryingCancellationRecoveryIDs: Set<UUID> = []
    @Published private(set) var pendingCancellationBarrierCount = 0
    @Published private(set) var endingActivityRunIDs: Set<UUID> = []
    @Published private(set) var statusActivity: WorkspaceResearchActivity?

    @Published var textValues: [String: String] = [:]
    @Published var choiceValues: [String: Set<String>] = [:]
    @Published var selectedFocalNoteIDs: Set<UUID> = []
    @Published var selectedFidelityChecks: Set<FidelityCheck> = []
    @Published var usesPassage = true

    private var passage: CommentAnchor?
    private var resynthesisContext: MaterialChangedSinceUseAttentionContext?
    private var client: ResearchActionClient?
    private var generation: UInt64 = 0
    private var availabilityGeneration: UInt64 = 0
    private var loadingTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var sourceTask: Task<Void, Never>?
    private var recoveryCancellations: [UUID: CancellationOperation] = [:]

    var isPresented: Bool { presentationID != nil }
    var isBusy: Bool {
        isBindingSource || phase == .loading || phase == .preparing || phase == .cancelling
    }
    var passageIsAvailable: Bool { passage != nil }
    var isStatusPresentation: Bool { statusActivity != nil }
    var hasCancellationBarrier: Bool {
        phase == .cancelling
            || pendingCancellationBarrierCount > 0
            || !cancellationRecoveries.isEmpty
    }

    var activeAvailability: ResearchActionAvailability? {
        presentationAvailability
    }

    var profile: ResearchAcademicActionProfile? {
        activeAvailability?.profile.profile
    }

    var platformDefinition: PlatformActionDefinition? {
        activeActionID.flatMap(PlatformActionCatalog.definition)
    }

    var canCancelPreparedRun: Bool {
        preparation?.state == .prepared && resultRecord == nil
    }

    var canPrepare: Bool {
        guard phase == .editing || phase == .failed,
              activeAvailability?.isEnabled == true,
              let profile,
              !isLoadingMaterialCandidates,
              !isLoadingSourceStatus,
              !isBusy else { return false }
        return profile.academicInputFields.allSatisfy(academicFieldIsSatisfied)
            && requiredPlatformSelectorsAreSatisfied
    }

    func bind(_ client: ResearchActionClient) {
        invalidate(clearAvailability: true)
        self.client = client
    }

    func receive(records: [PortableResearchRecord]) {
        guard let runID = preparation?.runID else { return }
        resultRecord = records.first { $0.id == runID }
        continuationRecords = records.filter {
            $0.continuationLineage?.kind == .continueResearch
                && $0.continuationLineage?.parentRunID == runID
        }.sorted {
            if $0.finishedAt != $1.finishedAt { return $0.finishedAt < $1.finishedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func receive(activities: [WorkspaceResearchActivity]) {
        guard let runID = statusActivity?.runID else { return }
        guard let activity = activities.first(where: { $0.runID == runID }) else {
            phase = .cancelled
            return
        }
        statusActivity = activity
    }

    func unbind() {
        invalidate(clearAvailability: true)
        client = nil
    }

    func refreshAvailability(for target: ResearchActionNoteSnapshot?) async {
        guard let target, let client else {
            availability = []
            availabilityTarget = nil
            isRefreshingAvailability = false
            availabilityError = nil
            return
        }
        let retainsCurrentRows = availabilityTarget == target
        availabilityGeneration &+= 1
        let token = availabilityGeneration
        if !retainsCurrentRows { availability = [] }
        availabilityTarget = target
        isRefreshingAvailability = true
        availabilityError = nil
        do {
            let loaded = try await client.availableActions(target)
            guard token == self.availabilityGeneration,
                  self.availabilityTarget == target,
                  self.target == nil || self.target == target else { return }
            availability = Self.sorted(loaded)
            isRefreshingAvailability = false
        } catch is CancellationError {
            guard token == self.availabilityGeneration,
                  self.availabilityTarget == target else { return }
            isRefreshingAvailability = false
            return
        } catch {
            guard token == self.availabilityGeneration,
                  self.availabilityTarget == target else { return }
            if !retainsCurrentRows { availability = [] }
            isRefreshingAvailability = false
            availabilityError = error.localizedDescription
        }
    }

    @discardableResult
    func beginStatus(
        target: ResearchActionNoteSnapshot,
        availability: ResearchActionAvailability?,
        activity: WorkspaceResearchActivity,
        presentationID: UUID
    ) -> Bool {
        guard phase != .cancelling, !hasCancellationBarrier else { return false }
        invalidate(clearAvailability: false)
        self.target = target
        availabilityTarget = target
        activeActionID = activity.actionID
        self.presentationID = presentationID
        presentationAvailability = availability
        statusActivity = activity
        phase = .loading
        let token = generation
        loadingTask = Task { @MainActor [self] in
            guard let client else { return }
            do {
                let loaded = try await client.actionRun(activity.runID)
                guard accepts(token), self.presentationID == presentationID,
                      loaded.runID == activity.runID,
                      loaded.snapshot.actionID == activity.actionID,
                      loaded.snapshot.target.noteID == activity.targetNoteID else {
                    return
                }
                preparation = loaded
                phase = .prepared
            } catch is CancellationError {
                return
            } catch {
                guard accepts(token), self.presentationID == presentationID else {
                    return
                }
                phase = .failed
                errorMessage = error.localizedDescription
            }
        }
        return true
    }

    @discardableResult
    func begin(
        target: ResearchActionNoteSnapshot,
        availability selected: ResearchActionAvailability,
        selection: CommentAnchor?,
        initialInstruction: String? = nil,
        initialMaterialNoteIDs: Set<UUID> = [],
        resynthesisContext: MaterialChangedSinceUseAttentionContext? = nil,
        presentationID: UUID
    ) -> Bool {
        guard phase != .preparing, !hasCancellationBarrier else { return false }
        invalidate(clearAvailability: false)
        self.target = target
        availabilityTarget = target
        activeActionID = selected.id
        self.presentationID = presentationID
        passage = selection
        self.resynthesisContext = resynthesisContext
        usesPassage = selection != nil
        presentationAvailability = selected
        guard selected.canPresentInInterface else {
            phase = .failed
            errorMessage = selected.repairReasons.first?.interfaceDescription
                ?? "Unavailable for this note."
            return true
        }
        initializeValues(for: selected.profile.profile)
        selectedFocalNoteIDs = initialMaterialNoteIDs
        if let initialInstruction,
           let field = selected.profile.profile.academicInputFields.first(where: {
               $0.kind == .freeText && $0.requirement != .excluded
           }) {
            setText(initialInstruction, field: field)
        }
        phase = .editing
        errorMessage = Self.presentationError(for: selected)
        let selectors = Set(
            (PlatformActionCatalog.definition(for: selected.id)?.requiredSelectors ?? [])
                + (PlatformActionCatalog.definition(for: selected.id)?.optionalSelectors ?? [])
        )
        let needsMaterialCandidates = selectors.contains(.focalNotes)
        let needsSourceStatus = selectors.contains(.source)
        isLoadingMaterialCandidates = needsMaterialCandidates
        isLoadingSourceStatus = needsSourceStatus

        let token = generation
        loadingTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            async let materialResult = Self.captureResult {
                if needsMaterialCandidates {
                    return try await client.materialCandidates(
                        target,
                        selected.definition
                    )
                }
                return []
            }
            async let sourceResult: Result<ResearchSourceAccessStatus?, Error> = Self.captureResult {
                if needsSourceStatus {
                    return Optional(try await client.sourceAccess(target))
                }
                return nil
            }
            let (materials, source) = await (materialResult, sourceResult)
            guard self.accepts(token), self.presentationID == presentationID else { return }
            self.isLoadingMaterialCandidates = false
            self.isLoadingSourceStatus = false
            var failures: [String] = []
            switch materials {
            case .success(let candidates):
                self.materialCandidates = candidates
            case .failure(let error):
                if !(error is CancellationError) { failures.append(error.localizedDescription) }
            }
            switch source {
            case .success(let status):
                self.sourceStatus = status
            case .failure(let error):
                if !(error is CancellationError) { failures.append(error.localizedDescription) }
            }
            if !failures.isEmpty {
                self.errorMessage = failures.joined(separator: "\n")
            }
        }
        return true
    }

    func setText(_ value: String, field: ResearchAcademicFieldDefinition) {
        guard field.kind == .freeText,
              let maximum = field.maximumTextUTF8Count else { return }
        var bounded = value
        while bounded.utf8.count > maximum, !bounded.isEmpty {
            bounded.removeLast()
        }
        textValues[field.fieldID.rawValue] = bounded
    }

    func setChoice(
        _ value: String,
        isSelected: Bool,
        field: ResearchAcademicFieldDefinition
    ) {
        guard field.choices.contains(where: { $0.value == value }) else { return }
        var selected = choiceValues[field.fieldID.rawValue] ?? []
        if isSelected {
            if field.kind == .singleChoice {
                selected = [value]
            } else {
                selected.insert(value)
            }
        } else {
            selected.remove(value)
        }
        choiceValues[field.fieldID.rawValue] = selected
    }

    func setFocalNote(
        _ noteID: UUID,
        isSelected: Bool
    ) {
        if isSelected {
            guard selectedFocalNoteIDs.contains(noteID)
                    || selectedFocalNoteIDs.count < 16 else { return }
            selectedFocalNoteIDs.insert(noteID)
        } else {
            selectedFocalNoteIDs.remove(noteID)
        }
    }

    func setFidelityCheck(_ check: FidelityCheck, isSelected: Bool) {
        if isSelected {
            selectedFidelityChecks.insert(check)
        } else {
            selectedFidelityChecks.remove(check)
        }
    }

    func bindLocalSource(_ url: URL) {
        guard let client, let target,
              platformSelectors.contains(.source) else { return }
        sourceTask?.cancel()
        let token = nextGeneration()
        isBindingSource = true
        errorMessage = nil
        sourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reference = try await client.bindLocalSource(target, url)
                let actions = try await client.availableActions(target)
                guard self.accepts(token), self.target == target else { return }
                let resolved = Self.sorted(actions)
                guard let activeActionID = self.activeActionID,
                      let selected = resolved.first(where: { $0.id == activeActionID }) else {
                    throw ResearchActionExecutionContractError.actionUnavailable(
                        self.activeActionID ?? .analyze
                    )
                }
                self.availability = resolved
                self.availabilityTarget = target
                self.availabilityError = nil
                self.presentationAvailability = selected
                self.sourceStatus = .available(reference)
                self.isBindingSource = false
                self.errorMessage = Self.presentationError(for: selected)
            } catch is CancellationError {
                return
            } catch {
                guard self.accepts(token), self.target == target else { return }
                self.isBindingSource = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func prepare() {
        guard let client,
              let target,
              let activeActionID,
              let profile,
              let presentationAvailability,
              let presentationID,
              canPrepare else { return }
        let request: ResearchActionExecutionRequest
        do {
            request = ResearchActionExecutionRequest(
                actionID: activeActionID,
                expectedExecutionKind: presentationAvailability.definition.executionKind,
                expectedProfileRevision: presentationAvailability.profile.profileRevision,
                expectedProfileDocumentRevision:
                    presentationAvailability.profile.profileDocumentRevision,
                target: target,
                platformInputs: try platformInputs(),
                academicInputs: try academicInputs(for: profile)
            )
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            return
        }
        let token = nextGeneration()
        phase = .preparing
        errorMessage = nil
        preparationTask = Task { @MainActor [self] in
            do {
                let result = try await client.prepare(request, resynthesisContext)
                guard self.accepts(token), self.presentationID == presentationID else {
                    cleanupUndeliveredRun(result.runID, using: client)
                    return
                }
                preparation = result
                resultRecord = nil
                continuationRecords = []
                do {
                    let handoff = try await client.handoff(result.runID)
                    guard self.accepts(token), self.presentationID == presentationID else {
                        cleanupUndeliveredRun(result.runID, using: client)
                        return
                    }
                    agentHandoff = handoff
                    phase = .prepared
                } catch {
                    guard self.accepts(token), self.presentationID == presentationID else {
                        cleanupUndeliveredRun(result.runID, using: client)
                        return
                    }
                    phase = .failed
                    errorMessage = error.localizedDescription
                }
            } catch is CancellationError {
                if accepts(token), self.presentationID == presentationID {
                    phase = .failed
                    errorMessage = String(
                        localized: "Action preparation was cancelled.",
                        table: "Localizable",
                        bundle: .module
                    )
                }
                return
            } catch let error as ResearchFunctionContractError {
                guard accepts(token), self.presentationID == presentationID else {
                    return
                }
                if case .activeDiscussionExists(let discussionID) = error {
                    phase = .editing
                    client.openActiveDiscussion(discussionID)
                    return
                }
                phase = .failed
                errorMessage = error.localizedDescription
            } catch {
                guard accepts(token), self.presentationID == presentationID else {
                    return
                }
                phase = .failed
                errorMessage = error.localizedDescription
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
        Task { @MainActor [self] in
            do {
                try await client.cancel(runID)
                guard accepts(token) else {
                    finishPendingCancellationBarrier()
                    return
                }
                preparation = nil
                agentHandoff = nil
                resultRecord = nil
                continuationRecords = []
                phase = .cancelled
            } catch {
                if accepts(token) {
                    phase = .failed
                    errorMessage = error.localizedDescription
                } else {
                    recordCancellationRecovery(
                        runID: runID,
                        error: error,
                        cancel: client.cancel
                    )
                    finishPendingCancellationBarrier()
                }
            }
        }
    }

    func endActivity(runID: UUID) {
        guard let client,
              !endingActivityRunIDs.contains(runID) else { return }
        endingActivityRunIDs.insert(runID)
        Task { @MainActor [self] in
            do {
                try await client.cancel(runID)
                endingActivityRunIDs.remove(runID)
            } catch {
                endingActivityRunIDs.remove(runID)
                recordCancellationRecovery(
                    runID: runID,
                    error: error,
                    cancel: client.cancel
                )
            }
        }
    }

    func retryHandoff() {
        guard let client, let preparation,
              phase == .failed, !isBusy else { return }
        requestHandoff(using: client, runID: preparation.runID)
    }

    /// Invalidates any prior pairing for this Run and issues a fresh short
    /// handoff. The Run and its durable recovery state remain unchanged.
    func regenerateHandoff() {
        guard let client, let preparation,
              phase == .prepared, !isBusy else { return }
        requestHandoff(using: client, runID: preparation.runID)
    }

    private func requestHandoff(
        using client: ResearchActionClient,
        runID: UUID
    ) {
        let token = nextGeneration()
        phase = .preparing
        errorMessage = nil
        agentHandoff = nil
        Task { @MainActor [self] in
            do {
                let handoff = try await client.handoff(runID)
                guard accepts(token) else { return }
                agentHandoff = handoff
                phase = .prepared
            } catch {
                guard accepts(token) else { return }
                phase = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    func retryCancellationRecovery(runID: UUID) {
        guard cancellationRecoveries.contains(where: { $0.runID == runID }),
              let cancel = recoveryCancellations[runID],
              !retryingCancellationRecoveryIDs.contains(runID) else { return }
        retryingCancellationRecoveryIDs.insert(runID)
        Task { @MainActor [self] in
            do {
                try await cancel(runID)
                clearCancellationRecovery(runID: runID)
            } catch {
                retryingCancellationRecoveryIDs.remove(runID)
                recordCancellationRecovery(
                    runID: runID,
                    error: error,
                    cancel: cancel
                )
            }
        }
    }

    func dismiss(presentationID: UUID? = nil) {
        if let presentationID, self.presentationID != presentationID { return }
        invalidate(clearAvailability: false)
    }

    func invalidateIfTargetChanged(_ current: ResearchActionNoteSnapshot?) {
        guard let target else { return }
        guard current == target else { invalidate(clearAvailability: false); return }
    }

    private func initializeValues(for profile: ResearchAcademicActionProfile) {
        for field in profile.academicInputFields where field.requirement != .excluded {
            switch field.kind {
            case .freeText:
                textValues[field.fieldID.rawValue] = ""
            case .singleChoice, .multipleChoice:
                choiceValues[field.fieldID.rawValue] = []
            }
        }
        if platformSelectors.contains(.fidelityChecks) {
            selectedFidelityChecks = [.content]
        }
    }

    /// A Run that never produced a delivered handoff has no Agent Session or
    /// mutation authority. Cleanup is process-local and best effort: failure
    /// leaves an inert durable Run, not a researcher-visible recovery
    /// obligation or a global Action barrier.
    private func cleanupUndeliveredRun(
        _ runID: UUID,
        using client: ResearchActionClient
    ) {
        Task { @MainActor in
            _ = try? await client.cancel(runID)
        }
    }

    private func recordCancellationRecovery(
        runID: UUID,
        error: Error,
        cancel: @escaping @MainActor (UUID) async throws -> Void
    ) {
        let recovery = ResearchActionCancellationRecovery(
            runID: runID,
            errorMessage: error.localizedDescription
        )
        if let index = cancellationRecoveries.firstIndex(where: { $0.runID == runID }) {
            cancellationRecoveries[index] = recovery
        } else {
            cancellationRecoveries.append(recovery)
            cancellationRecoveries.sort {
                $0.runID.uuidString < $1.runID.uuidString
            }
        }
        recoveryCancellations[runID] = cancel
    }

    private func clearCancellationRecovery(runID: UUID) {
        cancellationRecoveries.removeAll { $0.runID == runID }
        recoveryCancellations[runID] = nil
        retryingCancellationRecoveryIDs.remove(runID)
        endingActivityRunIDs.remove(runID)
    }

    private func finishPendingCancellationBarrier() {
        pendingCancellationBarrierCount = max(0, pendingCancellationBarrierCount - 1)
    }

    private func academicFieldIsSatisfied(
        _ field: ResearchAcademicFieldDefinition
    ) -> Bool {
        guard field.requirement == .required else { return true }
        switch field.kind {
        case .freeText:
            return !(textValues[field.fieldID.rawValue] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .singleChoice, .multipleChoice:
            return !(choiceValues[field.fieldID.rawValue] ?? []).isEmpty
        }
    }

    var platformSelectors: Set<PlatformActionSelector> {
        guard let platformDefinition else { return [] }
        return Set(
            platformDefinition.requiredSelectors + platformDefinition.optionalSelectors
        )
    }

    private var requiredPlatformSelectorsAreSatisfied: Bool {
        guard let platformDefinition else { return false }
        return platformDefinition.requiredSelectors.allSatisfy { selector in
            switch selector {
            case .source:
                sourceStatus?.state == .available
            case .focalNotes:
                !selectedFocalNoteIDs.isEmpty
            case .passage:
                passage != nil && usesPassage
            case .fidelityChecks:
                !selectedFidelityChecks.isEmpty
            case .citationStyle, .feedback:
                // These selectors are resolved from current app-owned state.
                true
            }
        }
    }

    private func academicInputs(
        for profile: ResearchAcademicActionProfile
    ) throws -> ResearchAcademicFieldValues {
        var values: [String: ResearchAcademicFieldValue] = [:]
        for field in profile.academicInputFields where field.requirement != .excluded {
            switch field.kind {
            case .freeText:
                let text = textValues[field.fieldID.rawValue] ?? ""
                if field.requirement == .required || !text.isEmpty {
                    values[field.fieldID.rawValue] = .freeText(text)
                }
            case .singleChoice:
                if let choice = choiceValues[field.fieldID.rawValue]?.sorted().first {
                    values[field.fieldID.rawValue] = .singleChoice(choice)
                }
            case .multipleChoice:
                let choices = choiceValues[field.fieldID.rawValue]?.sorted() ?? []
                if field.requirement == .required || !choices.isEmpty {
                    values[field.fieldID.rawValue] = .multipleChoice(choices)
                }
            }
        }
        return try ResearchAcademicFieldValues(
            rawValues: values,
            definitions: profile.academicInputFields
        )
    }

    private func platformInputs() throws -> ResearchActionPlatformInputs {
        let focalNotes = platformSelectors.contains(.focalNotes)
            ? materialCandidates.filter { selectedFocalNoteIDs.contains($0.noteID) }
            : []
        return try ResearchActionPlatformInputs(
            focalNotes: focalNotes,
            passage: platformSelectors.contains(.passage) && usesPassage
                ? passage
                : nil,
            fidelityChecks: platformSelectors.contains(.fidelityChecks)
                ? selectedFidelityChecks
                : []
        )
    }

    private func invalidate(clearAvailability: Bool) {
        if phase == .cancelling {
            pendingCancellationBarrierCount += 1
        }
        _ = nextGeneration()
        availabilityGeneration &+= 1
        loadingTask?.cancel()
        preparationTask?.cancel()
        sourceTask?.cancel()
        loadingTask = nil
        preparationTask = nil
        sourceTask = nil
        target = nil
        activeActionID = nil
        presentationID = nil
        presentationAvailability = nil
        materialCandidates = []
        isLoadingMaterialCandidates = false
        sourceStatus = nil
        isLoadingSourceStatus = false
        preparation = nil
        agentHandoff = nil
        resultRecord = nil
        continuationRecords = []
        statusActivity = nil
        errorMessage = nil
        isBindingSource = false
        textValues = [:]
        choiceValues = [:]
        selectedFocalNoteIDs = []
        selectedFidelityChecks = []
        passage = nil
        resynthesisContext = nil
        usesPassage = true
        phase = .idle
        if clearAvailability {
            availability = []
            availabilityTarget = nil
            isRefreshingAvailability = false
            availabilityError = nil
        }
    }

    private static func captureResult<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async -> Result<Value, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    @discardableResult
    private func nextGeneration() -> UInt64 {
        generation &+= 1
        return generation
    }

    private func accepts(_ token: UInt64) -> Bool {
        token == generation && !Task.isCancelled
    }

    private static func sorted(
        _ actions: [ResearchActionAvailability]
    ) -> [ResearchActionAvailability] {
        actions.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.id.rawValue < $1.id.rawValue
        }
    }

    private static func presentationError(
        for availability: ResearchActionAvailability
    ) -> String? {
        guard !availability.isEnabled else { return nil }
        return availability.repairReasons.first(where: {
            $0.code != .sourceAccessRequired
        })?.interfaceDescription
    }
}

extension ResearchActionRepairReason {
    var interfaceDescription: String {
        switch code {
        case .targetUnavailable:
            String(localized: "The current note is unavailable.", table: "Localizable", bundle: .module)
        case .targetChanged:
            String(localized: "The note changed; reopen the Action.", table: "Localizable", bundle: .module)
        case .targetIdentityChanged:
            String(localized: "The note identity changed; reopen the Action.", table: "Localizable", bundle: .module)
        case .invalidTargetRole:
            String(localized: "This Action is not available for this kind of note.", table: "Localizable", bundle: .module)
        case .inactiveTarget:
            String(localized: "This Action requires an active note.", table: "Localizable", bundle: .module)
        case .sourceAccessRequired:
            String(localized: "Choose the exact source again before Analyze.", table: "Localizable", bundle: .module)
        case .methodMissing:
            String(localized: "Install or restore the working method in Research Guidance.", table: "Localizable", bundle: .module)
        case .methodDisabled:
            String(localized: "Enable the working method in Research Guidance.", table: "Localizable", bundle: .module)
        case .methodInvalid:
            String(localized: "The working method needs repair in Research Guidance.", table: "Localizable", bundle: .module)
        case .profileInvalid:
            String(localized: "The Action Profile needs repair in Research Guidance.", table: "Localizable", bundle: .module)
        case .unsupportedCapability:
            String(localized: "This Action requests a capability Scholium cannot mediate.", table: "Localizable", bundle: .module)
        }
    }
}

extension ResearchActionAvailability {
    /// Source repair is part of Analyze's app-owned module, so the sheet must
    /// remain reachable even though execution itself is still fail closed.
    var canPresentInInterface: Bool {
        isEnabled || repairReasons.contains { $0.code == .sourceAccessRequired }
    }
}

extension ResearchFunctionTargetRole {
    var actionRole: ResearchActionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}

extension ResearchActionTargetRole {
    var functionRole: ResearchFunctionTargetRole {
        switch self {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
    }
}

extension ResearchActionNoteSnapshot {
    var functionTarget: ResearchFunctionTarget {
        ResearchFunctionTarget(
            noteID: noteID,
            note: note,
            role: role.functionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

extension ResearchFunctionMaterial {
    var actionNote: ResearchActionNoteSnapshot {
        ResearchActionNoteSnapshot(
            noteID: noteID,
            note: note,
            role: role.actionRole,
            lifecycle: lifecycle,
            fingerprint: fingerprint,
            title: title
        )
    }
}

extension ResearchActionDefinition {
    var protectedFunction: ResearchFunctionID {
        switch executionKind {
        case .discussion: .discuss
        case .analysis, .synthesis: .develop
        case .writing: .revise
        case .critique: .critique
        case .checkFidelity: .fidelity
        case .manuscript: .manuscript
        }
    }
}
