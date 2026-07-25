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
        ResearchActionExecutionRequest
    ) async throws -> ResearchActionPreparation
    let cancel: @MainActor (UUID) async throws -> Void
    let openActiveDiscussion: @MainActor (UUID) -> Void
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
/// researcher-entered parameter values transient and delegates every durable
/// identity, revision, authority, checkpoint, and completion decision to the
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
    @Published private(set) var sourceStatus: ResearchSourceAccessStatus?
    @Published private(set) var preparation: ResearchActionPreparation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBindingSource = false
    @Published private(set) var cancellationRecoveries: [ResearchActionCancellationRecovery] = []
    @Published private(set) var retryingCancellationRecoveryIDs: Set<UUID> = []
    @Published private(set) var pendingCancellationBarrierCount = 0

    @Published var textValues: [String: String] = [:]
    @Published var booleanValues: [String: Bool] = [:]
    @Published var choiceValues: [String: Set<ResearchActionModuleChoiceValue>] = [:]
    @Published var noteValues: [String: Set<UUID>] = [:]
    @Published var usesPassage = true

    private var passage: CommentAnchor?
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
    var hasCancellationBarrier: Bool {
        phase == .preparing
            || phase == .cancelling
            || pendingCancellationBarrierCount > 0
            || !cancellationRecoveries.isEmpty
    }

    var activeAvailability: ResearchActionAvailability? {
        presentationAvailability
    }

    var profile: ResearchActionProfile? {
        activeAvailability?.profile.profile
    }

    var canCancelPreparedRun: Bool {
        preparation?.state == .prepared
    }

    var canPrepare: Bool {
        guard phase == .editing || phase == .failed,
              activeAvailability?.isEnabled == true,
              let profile,
              !isBusy else { return false }
        return profile.modules.allSatisfy(moduleIsSatisfied)
    }

    func bind(_ client: ResearchActionClient) {
        invalidate(clearAvailability: true)
        self.client = client
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
        availabilityGeneration &+= 1
        let token = availabilityGeneration
        availability = []
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
            availability = []
            isRefreshingAvailability = false
            availabilityError = error.localizedDescription
        }
    }

    @discardableResult
    func begin(
        target: ResearchActionNoteSnapshot,
        actionID: ResearchActionID,
        selection: CommentAnchor?,
        presentationID: UUID
    ) -> Bool {
        guard !hasCancellationBarrier else { return false }
        // The Inspector's availability is only a launcher preflight. Preserve
        // it for menu continuity while the sheet resolves an independent,
        // exact Profile that alone may authorize preparation.
        invalidate(clearAvailability: false)
        self.target = target
        availabilityTarget = target
        activeActionID = actionID
        self.presentationID = presentationID
        passage = selection
        usesPassage = selection != nil
        phase = .loading

        let token = generation
        loadingTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                let actions = try await client.availableActions(target)
                guard self.accepts(token), self.presentationID == presentationID else { return }
                let resolved = Self.sorted(actions)
                self.availability = resolved
                self.availabilityTarget = target
                self.availabilityError = nil
                guard let selected = resolved.first(where: { $0.id == actionID }) else {
                    throw ResearchActionExecutionContractError.actionUnavailable(actionID)
                }
                self.presentationAvailability = selected
                guard selected.canPresentInInterface else {
                    self.phase = .failed
                    self.errorMessage = selected.repairReasons.first?.interfaceDescription
                        ?? "Unavailable for this note."
                    return
                }
                self.initializeValues(for: selected.profile.profile)

                if selected.profile.profile.modules.contains(where: {
                    $0.kind == .notePicker || $0.kind == .materialSelector
                }) {
                    let candidates = try await client.materialCandidates(
                        target,
                        selected.definition
                    )
                    guard self.accepts(token), self.presentationID == presentationID else {
                        return
                    }
                    self.materialCandidates = candidates
                }
                if selected.profile.profile.modules.contains(where: {
                    $0.kind == .sourceReference
                }) {
                    let status = try await client.sourceAccess(target)
                    guard self.accepts(token), self.presentationID == presentationID else {
                        return
                    }
                    self.sourceStatus = status
                }
                guard self.accepts(token), self.presentationID == presentationID else { return }
                self.phase = .editing
                self.errorMessage = Self.presentationError(for: selected)
            } catch is CancellationError {
                return
            } catch {
                guard self.accepts(token), self.presentationID == presentationID else { return }
                self.presentationAvailability = nil
                self.materialCandidates = []
                self.sourceStatus = nil
                self.availabilityError = error.localizedDescription
                self.phase = .failed
                self.errorMessage = error.localizedDescription
            }
        }
        return true
    }

    func setText(_ value: String, module: ResearchActionModuleDefinition) {
        guard let maximum = module.maximumTextUTF8ByteCount else { return }
        var bounded = value
        while bounded.utf8.count > maximum, !bounded.isEmpty {
            bounded.removeLast()
        }
        textValues[module.id.rawValue] = bounded
    }

    func setBoolean(_ value: Bool, module: ResearchActionModuleDefinition) {
        booleanValues[module.id.rawValue] = value
    }

    func setChoice(
        _ value: ResearchActionModuleChoiceValue,
        isSelected: Bool,
        module: ResearchActionModuleDefinition
    ) {
        var selected = choiceValues[module.id.rawValue] ?? []
        if isSelected {
            let maximum = module.maximumSelectionCount ?? 1
            if maximum == 1 {
                selected = [value]
            } else {
                guard selected.contains(value) || selected.count < maximum else { return }
                selected.insert(value)
            }
        } else {
            selected.remove(value)
        }
        choiceValues[module.id.rawValue] = selected
    }

    func setNote(
        _ noteID: UUID,
        isSelected: Bool,
        module: ResearchActionModuleDefinition
    ) {
        var selected = noteValues[module.id.rawValue] ?? []
        if isSelected {
            let maximum = module.maximumSelectionCount ?? 1
            if maximum == 1 {
                selected = [noteID]
            } else {
                guard selected.contains(noteID) || selected.count < maximum else { return }
                selected.insert(noteID)
            }
        } else {
            selected.remove(noteID)
        }
        noteValues[module.id.rawValue] = selected
    }

    func bindLocalSource(_ url: URL) {
        guard let client, let target, profile?.sourceRequirement == .required else { return }
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
              let presentationID,
              canPrepare else { return }
        let request = ResearchActionExecutionRequest(
            actionID: activeActionID,
            target: target,
            parameterValues: parameterValues(for: profile)
        )
        let token = nextGeneration()
        phase = .preparing
        errorMessage = nil
        preparationTask = Task { @MainActor [self] in
            do {
                let result = try await client.prepare(request)
                guard self.accepts(token), self.presentationID == presentationID else {
                    // Preparation can cross a durable checkpoint/grant
                    // boundary even when its caller was cancelled. Reclaim a
                    // late result through the typed cancellation path instead
                    // of dropping an invisible prepared run.
                    reclaimAbandonedPreparation(result, using: client)
                    return
                }
                preparation = result
                phase = .prepared
            } catch is CancellationError {
                if !accepts(token) || self.presentationID != presentationID {
                    finishPendingCancellationBarrier()
                } else {
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
                    finishPendingCancellationBarrier()
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
                    finishPendingCancellationBarrier()
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

    private func initializeValues(for profile: ResearchActionProfile) {
        for module in profile.modules {
            switch module.kind {
            case .boundedText:
                textValues[module.id.rawValue] = ""
            case .boolean:
                booleanValues[module.id.rawValue] = module.defaultBoolean ?? false
            case .enumeration:
                choiceValues[module.id.rawValue] = []
            case .notePicker, .materialSelector:
                noteValues[module.id.rawValue] = []
            case .passageAnchor, .sourceReference:
                break
            }
        }
    }

    private func reclaimAbandonedPreparation(
        _ preparation: ResearchActionPreparation,
        using client: ResearchActionClient
    ) {
        Task { @MainActor [self] in
            defer { finishPendingCancellationBarrier() }
            do {
                try await client.cancel(preparation.runID)
                clearCancellationRecovery(runID: preparation.runID)
            } catch {
                recordCancellationRecovery(
                    runID: preparation.runID,
                    error: error,
                    cancel: client.cancel
                )
            }
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
    }

    private func finishPendingCancellationBarrier() {
        pendingCancellationBarrierCount = max(0, pendingCancellationBarrierCount - 1)
    }

    private func moduleIsSatisfied(_ module: ResearchActionModuleDefinition) -> Bool {
        guard module.isRequired else { return true }
        switch module.kind {
        case .boundedText:
            return !(textValues[module.id.rawValue] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .boolean:
            return booleanValues[module.id.rawValue] != nil
        case .enumeration:
            return !(choiceValues[module.id.rawValue] ?? []).isEmpty
        case .notePicker, .materialSelector:
            return !(noteValues[module.id.rawValue] ?? []).isEmpty
        case .passageAnchor:
            return passage != nil && usesPassage
        case .sourceReference:
            return sourceStatus?.state == .available
        }
    }

    private func parameterValues(
        for profile: ResearchActionProfile
    ) -> [ResearchActionModuleID: ResearchActionParameterValue] {
        Dictionary(uniqueKeysWithValues: profile.modules.compactMap { module in
            let value: ResearchActionParameterValue?
            switch module.kind {
            case .boundedText:
                let text = textValues[module.id.rawValue] ?? ""
                value = text.isEmpty ? nil : .text(text)
            case .boolean:
                value = booleanValues[module.id.rawValue].map(ResearchActionParameterValue.boolean)
            case .enumeration:
                let choices = (choiceValues[module.id.rawValue] ?? [])
                    .sorted { $0.rawValue < $1.rawValue }
                value = choices.isEmpty ? nil : .choices(choices)
            case .notePicker, .materialSelector:
                let ids = noteValues[module.id.rawValue] ?? []
                let notes = materialCandidates.filter { ids.contains($0.noteID) }
                value = notes.isEmpty ? nil : .notes(notes)
            case .passageAnchor:
                value = usesPassage ? passage.map(ResearchActionParameterValue.passage) : nil
            case .sourceReference:
                // The Application resolves the machine-local binding again and
                // freezes the exact reference in the Action snapshot.
                value = nil
            }
            return value.map { (module.id, $0) }
        })
    }

    private func invalidate(clearAvailability: Bool) {
        if phase == .preparing || phase == .cancelling {
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
        sourceStatus = nil
        preparation = nil
        errorMessage = nil
        isBindingSource = false
        textValues = [:]
        booleanValues = [:]
        choiceValues = [:]
        noteValues = [:]
        passage = nil
        usesPassage = true
        phase = .idle
        if clearAvailability {
            availability = []
            availabilityTarget = nil
            isRefreshingAvailability = false
            availabilityError = nil
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
            if $0.group != $1.group { return $0.group == .defaultAction }
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
