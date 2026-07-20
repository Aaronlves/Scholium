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
    let dialogueResponseProfile: @MainActor () async throws -> DialogueResponseProfile
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

enum ResearchFunctionMaterialsPhase: Equatable, Sendable {
    case idle
    case loading
    case empty
    case ready
    case failed(String)
}

enum ResearchFunctionMaterialTreeNodeKind: Hashable, Sendable {
    case role(ResearchFunctionTargetRole)
    case folder(role: ResearchFunctionTargetRole, relativePath: String)
    case material(UUID)
}

struct ResearchFunctionMaterialTreeNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: ResearchFunctionMaterialTreeNodeKind
    let candidate: ResearchFunctionMaterialCandidate?
    let children: [ResearchFunctionMaterialTreeNode]
    let isExpanded: Bool
}

struct ResearchFunctionMaterialsViewState: Equatable, Sendable {
    let phase: ResearchFunctionMaterialsPhase
    let query: String
    let showsSuggestedOnly: Bool
    let selectedMaterialIDs: Set<UUID>
    let selectedCandidates: [ResearchFunctionMaterialCandidate]
    let roots: [ResearchFunctionMaterialTreeNode]
    let isFrozen: Bool
}

enum ResearchFunctionMaterialsAction: Equatable, Sendable {
    case setQuery(String)
    case toggleFolder(String)
    case setSuggestedOnly(Bool)
    case setSelected(UUID, Bool)
    case remove(UUID)
    case retry
    case reset
}

/// One owner for the complete Materials draft. The state projects an exact
/// role/folder hierarchy without changing the authoritative Material request
/// contract or selecting any suggestion implicitly.
struct ResearchFunctionMaterialsState: Equatable, Sendable {
    private(set) var phase: ResearchFunctionMaterialsPhase = .idle
    private(set) var candidates: [ResearchFunctionMaterialCandidate] = []
    private(set) var selectedMaterialIDs: Set<UUID> = []
    private(set) var query = ""
    private(set) var showsSuggestedOnly = false
    private(set) var expandedFolderIDs: Set<String> = []
    private(set) var isFrozen = false

    var permitsPreparation: Bool {
        phase == .ready || phase == .empty
    }

    var selectedMaterials: [ResearchFunctionMaterial] {
        candidates
            .filter { selectedMaterialIDs.contains($0.id) }
            .map(\.material)
    }

    var viewState: ResearchFunctionMaterialsViewState {
        ResearchFunctionMaterialsViewState(
            phase: phase,
            query: query,
            showsSuggestedOnly: showsSuggestedOnly,
            selectedMaterialIDs: selectedMaterialIDs,
            selectedCandidates: candidates.filter {
                selectedMaterialIDs.contains($0.id)
            },
            roots: visibleRoots,
            isFrozen: isFrozen
        )
    }

    mutating func beginLoading() {
        self = Self()
        phase = .loading
    }

    mutating func retryLoading() {
        guard !isFrozen else { return }
        phase = .loading
        candidates = []
        selectedMaterialIDs = []
    }

    mutating func receive(
        _ loaded: [ResearchFunctionMaterialCandidate],
        target: VaultQualifiedNoteID,
        passage: ResearcherCommentAnchor?
    ) {
        guard !isFrozen else { return }
        candidates = loaded.map { candidate in
            let contextualReasons = candidate.suggestionReasons.map { reason in
                guard reason.kind == .linkedFromTarget,
                      reason.sourceNote == target,
                      let passage,
                      Self.overlaps(reason.sourceSpan, passage) else {
                    return reason
                }
                return ResearchFunctionMaterialSuggestionReason(
                    kind: .linkedFromSelectedPassage,
                    sourceNote: reason.sourceNote,
                    sourceSpan: reason.sourceSpan
                )
            }
            return ResearchFunctionMaterialCandidate(
                material: candidate.material,
                aliases: candidate.aliases,
                suggestionReasons: contextualReasons,
                isSelectable: candidate.isSelectable,
                repairReasons: candidate.repairReasons
            )
        }
        selectedMaterialIDs.formIntersection(candidates.map(\.id))
        expandedFolderIDs.formUnion(
            Set(ResearchFunctionTargetRole.allCases.map(Self.roleNodeID))
        )
        for candidate in candidates where !candidate.suggestionReasons.isEmpty {
            expandedFolderIDs.formUnion(Self.folderAncestorIDs(for: candidate.material))
        }
        phase = candidates.isEmpty ? .empty : .ready
    }

    mutating func fail(_ message: String) {
        guard !isFrozen else { return }
        candidates = []
        selectedMaterialIDs = []
        phase = .failed(message)
    }

    mutating func freeze() {
        isFrozen = true
    }

    mutating func unfreeze() {
        isFrozen = false
    }

    mutating func apply(_ action: ResearchFunctionMaterialsAction) {
        if isFrozen, action != .reset { return }
        switch action {
        case .setQuery(let value):
            query = value
        case .toggleFolder(let id):
            if expandedFolderIDs.contains(id) {
                expandedFolderIDs.remove(id)
            } else {
                expandedFolderIDs.insert(id)
            }
        case .setSuggestedOnly(let value):
            showsSuggestedOnly = value
        case .setSelected(let id, let selected):
            guard let candidate = candidates.first(where: { $0.id == id }),
                  candidate.isSelectable else { return }
            if selected {
                selectedMaterialIDs.insert(id)
            } else {
                selectedMaterialIDs.remove(id)
            }
        case .remove(let id):
            selectedMaterialIDs.remove(id)
        case .retry:
            break
        case .reset:
            self = Self()
        }
    }

    private var visibleRoots: [ResearchFunctionMaterialTreeNode] {
        guard phase == .ready else { return [] }
        let needle = Self.comparable(query)
        let visible = candidates.filter { candidate in
            if showsSuggestedOnly, candidate.suggestionReasons.isEmpty { return false }
            guard !needle.isEmpty else { return true }
            let path = candidate.material.note.relativePath
            let filename = (path as NSString).lastPathComponent
            return ([candidate.material.title, filename, path] + candidate.aliases)
                .contains { Self.comparable($0).contains(needle) }
        }
        let forcesDisclosure = !needle.isEmpty || showsSuggestedOnly
        return ResearchFunctionTargetRole.allCases.compactMap { role in
            let roleCandidates = visible.filter { $0.material.role == role }
            guard !roleCandidates.isEmpty || !forcesDisclosure else { return nil }
            var accumulator = FolderAccumulator()
            for candidate in roleCandidates {
                let components = candidate.material.note.relativePath
                    .split(separator: "/", omittingEmptySubsequences: true)
                    .dropLast()
                    .map(String.init)
                accumulator.insert(candidate, folders: Array(components))
            }
            let id = Self.roleNodeID(role)
            return ResearchFunctionMaterialTreeNode(
                id: id,
                title: Self.roleTitle(role),
                kind: .role(role),
                candidate: nil,
                children: accumulator.nodes(
                    role: role,
                    parentPath: "",
                    expandedFolderIDs: expandedFolderIDs,
                    forcesDisclosure: forcesDisclosure
                ),
                isExpanded: forcesDisclosure || expandedFolderIDs.contains(id)
            )
        }
    }

    private static func comparable(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static func overlaps(
        _ span: SourceSpan,
        _ passage: ResearcherCommentAnchor
    ) -> Bool {
        span.utf16LowerBound < passage.utf16Range.upperBound
            && passage.utf16Range.lowerBound < span.utf16UpperBound
    }

    private static func roleNodeID(_ role: ResearchFunctionTargetRole) -> String {
        "role:\(role.rawValue)"
    }

    private static func folderNodeID(
        role: ResearchFunctionTargetRole,
        path: String
    ) -> String {
        "folder:\(role.rawValue):\(path)"
    }

    private static func folderAncestorIDs(
        for material: ResearchFunctionMaterial
    ) -> Set<String> {
        let components = material.note.relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .dropLast()
            .map(String.init)
        var result: Set<String> = [roleNodeID(material.role)]
        var path: [String] = []
        for component in components {
            path.append(component)
            result.insert(folderNodeID(role: material.role, path: path.joined(separator: "/")))
        }
        return result
    }

    private static func roleTitle(_ role: ResearchFunctionTargetRole) -> String {
        switch role {
        case .analysis: ScholiumL10n.dynamicString("Analyses")
        case .topic: ScholiumL10n.dynamicString("Topics")
        case .work: ScholiumL10n.dynamicString("Works")
        }
    }

    private struct FolderAccumulator {
        var direct: [ResearchFunctionMaterialCandidate] = []
        var folders: [String: FolderAccumulator] = [:]

        mutating func insert(
            _ candidate: ResearchFunctionMaterialCandidate,
            folders components: [String]
        ) {
            guard let first = components.first else {
                direct.append(candidate)
                return
            }
            var child = folders[first] ?? FolderAccumulator()
            child.insert(candidate, folders: Array(components.dropFirst()))
            folders[first] = child
        }

        func nodes(
            role: ResearchFunctionTargetRole,
            parentPath: String,
            expandedFolderIDs: Set<String>,
            forcesDisclosure: Bool
        ) -> [ResearchFunctionMaterialTreeNode] {
            let folderNodes = folders.keys.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }.compactMap { name -> ResearchFunctionMaterialTreeNode? in
                guard let child = folders[name] else { return nil }
                let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
                let id = ResearchFunctionMaterialsState.folderNodeID(
                    role: role,
                    path: path
                )
                return ResearchFunctionMaterialTreeNode(
                    id: id,
                    title: name,
                    kind: .folder(role: role, relativePath: path),
                    candidate: nil,
                    children: child.nodes(
                        role: role,
                        parentPath: path,
                        expandedFolderIDs: expandedFolderIDs,
                        forcesDisclosure: forcesDisclosure
                    ),
                    isExpanded: forcesDisclosure || expandedFolderIDs.contains(id)
                )
            }
            let noteNodes = direct.sorted { lhs, rhs in
                let titleOrder = lhs.material.title.localizedStandardCompare(
                    rhs.material.title
                )
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.material.note.relativePath.localizedStandardCompare(
                    rhs.material.note.relativePath
                ) == .orderedAscending
            }.map { candidate in
                ResearchFunctionMaterialTreeNode(
                    id: "material:\(candidate.id.uuidString.lowercased())",
                    title: candidate.material.title,
                    kind: .material(candidate.id),
                    candidate: candidate,
                    children: [],
                    isExpanded: false
                )
            }
            return folderNodes + noteNodes
        }
    }
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
    @Published private(set) var materialsState = ResearchFunctionMaterialsState()
    @Published private(set) var preparation: ResearchFunctionPreparation?
    @Published private(set) var targetRuns: [ResearchFunctionRecordProjection] = []
    @Published private(set) var errorMessage: String?

    @Published var instruction = ""
    @Published var scopeKind: ResearchFunctionScopeKind = .whole
    @Published var selectedCommentIDs: Set<UUID> = []
    @Published var fidelityChecks: Set<FidelityCheck> = [.content]
    @Published var dialogueResponseModules: Set<DialogueResponseModule> = []
    @Published private(set) var dialogueResponseDefaultsLoaded = false
    @Published private(set) var humanReviewRevision: DocumentFingerprint?
    @Published var humanReviewQualification: NoteQualification?
    @Published var humanReviewNote = ""

    private var passageSelection: ResearcherCommentAnchor?
    private var client: ResearchFunctionClient?
    private var generation: UInt64 = 0
    private var availabilityGeneration: UInt64 = 0
    private var materialsGeneration: UInt64 = 0
    private var loadingTask: Task<Void, Never>?
    private var materialsTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?

    var isPresented: Bool { presentationID != nil }
    var isBusy: Bool { phase == .loading || phase == .preparing || phase == .cancelling }
    var passageIsAvailable: Bool { passageSelection != nil }
    var materialCandidates: [ResearchFunctionMaterialCandidate] {
        materialsState.candidates
    }
    var selectedMaterialIDs: Set<UUID> {
        materialsState.selectedMaterialIDs
    }
    var materialsViewState: ResearchFunctionMaterialsViewState {
        materialsState.viewState
    }

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
        materialsState.selectedMaterials
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
              materialsState.permitsPreparation,
              !materialsState.isFrozen,
              !isBusy,
              phase != .prepared,
              function != .review else { return false }
        if function == .fidelity { return !fidelityChecks.isEmpty }
        if function == .dialogue {
            return dialogueResponseDefaultsLoaded
                && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        // Availability is target-scoped. Never display or enable launchers for
        // a newly selected note from the previous note's completed request.
        availability = [:]
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
        if function == .review {
            // Human Review is a judgment record, not an agent instruction
            // packet. Keep its hidden Materials state empty and never cross
            // the candidate boundary for this presentation.
            materialsState.receive([], target: target.note, passage: nil)
        } else {
            materialsState.beginLoading()
        }
        selectedCommentIDs = []
        dialogueResponseModules = []
        dialogueResponseDefaultsLoaded = false
        phase = .loading

        let token = generation
        loadingTask = Task { [weak self] in
            guard let self, let client = self.client else { return }
            do {
                async let available = client.availableFunctions(target)
                let profile: DialogueResponseProfile?
                if function == .dialogue {
                    profile = try await client.dialogueResponseProfile()
                } else {
                    profile = nil
                }
                let availability = try await available
                guard self.accepts(token),
                      self.target == target,
                      self.presentationID == presentationID else { return }
                if let profile, !profile.validationIssues.isEmpty {
                    self.phase = .failed
                    self.errorMessage = profile.validationIssues.joined(separator: " ")
                    return
                }
                self.availability = Dictionary(
                    uniqueKeysWithValues: availability.map { ($0.function, $0) }
                )
                self.dialogueResponseModules = Set(profile?.knownModules ?? [])
                self.dialogueResponseDefaultsLoaded = function == .dialogue && profile != nil
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
        if function != .review {
            loadMaterials(
                client: client,
                target: target,
                function: function,
                presentationID: presentationID,
                passage: selection
            )
        }
    }

    /// Loads the fingerprint-bound Human Review into the same per-window
    /// feature model that owns the panel presentation. The view only binds to
    /// these values, so a temporary Properties handoff cannot reconstruct or
    /// discard an in-progress judgment.
    func beginHumanReviewDraft(
        revision: DocumentFingerprint,
        record: HumanReviewRecord?
    ) {
        guard activeFunction == .review
                || (activeFunction == .dialogue
                    && (target?.role == .analysis || target?.role == .topic))
        else { return }
        humanReviewRevision = revision
        if let draft = record?.draft, draft.fingerprint == revision {
            humanReviewQualification = draft.qualification
            humanReviewNote = draft.reviewNote
        } else if let completed = record?.review(for: revision) {
            humanReviewQualification = completed.qualification
            humanReviewNote = completed.reviewNote
        } else {
            humanReviewQualification = nil
            humanReviewNote = ""
        }
    }

    /// Continues the same Review after an intentional Properties mutation.
    /// Only the exact presentation and stable note identity may advance to the
    /// new fingerprint; the researcher's unsaved judgment remains untouched.
    func resumeHumanReviewDraft(
        presentationID: UUID,
        target: ResearchFunctionTarget
    ) {
        guard self.presentationID == presentationID,
              (activeFunction == .review || activeFunction == .dialogue),
              let previousTarget = self.target,
              previousTarget.noteID == target.noteID,
              previousTarget.note == target.note else { return }
        self.target = target
        humanReviewRevision = target.fingerprint
    }

    func setScope(_ kind: ResearchFunctionScopeKind) {
        guard kind == .whole || passageSelection != nil else { return }
        scopeKind = kind
    }

    func sendMaterials(_ action: ResearchFunctionMaterialsAction) {
        switch action {
        case .retry:
            retryMaterials()
        default:
            materialsState.apply(action)
        }
    }

    private func retryMaterials() {
        guard case .failed = materialsState.phase,
              let client,
              let target,
              let function = activeFunction,
              let presentationID else { return }
        materialsState.retryLoading()
        loadMaterials(
            client: client,
            target: target,
            function: function,
            presentationID: presentationID,
            passage: passageSelection
        )
    }

    private func loadMaterials(
        client: ResearchFunctionClient?,
        target: ResearchFunctionTarget,
        function: ResearchFunctionID,
        presentationID: UUID,
        passage: ResearcherCommentAnchor?
    ) {
        materialsGeneration &+= 1
        let token = materialsGeneration
        let panelToken = generation
        materialsTask?.cancel()
        guard let client else {
            materialsState.fail("Materials are unavailable for this workspace.")
            return
        }
        materialsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let candidates = try await client.materialCandidates(target, function)
                guard token == self.materialsGeneration,
                      self.accepts(panelToken),
                      self.target == target,
                      self.presentationID == presentationID else { return }
                self.materialsState.receive(
                    candidates,
                    target: target.note,
                    passage: passage
                )
            } catch is CancellationError {
                return
            } catch {
                guard token == self.materialsGeneration,
                      self.accepts(panelToken),
                      self.target == target,
                      self.presentationID == presentationID else { return }
                self.materialsState.fail(error.localizedDescription)
            }
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

    func setDialogueResponseModule(
        _ module: DialogueResponseModule,
        isSelected: Bool
    ) {
        guard activeFunction == .dialogue, dialogueResponseDefaultsLoaded else { return }
        if isSelected {
            dialogueResponseModules.insert(module)
        } else {
            dialogueResponseModules.remove(module)
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
            commentIDs: selectedCommentIDs.sorted { $0.uuidString < $1.uuidString },
            dialogueResponseModules: function == .dialogue
                ? DialogueResponseModule.allCases.filter(dialogueResponseModules.contains)
                : nil
        )
        do {
            try request.validate()
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
            return
        }

        let token = nextGeneration()
        materialsState.freeze()
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
                self.materialsState.unfreeze()
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
        materialsGeneration &+= 1
        loadingTask?.cancel()
        materialsTask?.cancel()
        preparationTask?.cancel()
        loadingTask = nil
        materialsTask = nil
        preparationTask = nil
        target = nil
        activeFunction = nil
        presentationID = nil
        materialsState.apply(.reset)
        preparation = nil
        errorMessage = nil
        instruction = ""
        scopeKind = .whole
        passageSelection = nil
        selectedCommentIDs = []
        fidelityChecks = [.content]
        dialogueResponseModules = []
        dialogueResponseDefaultsLoaded = false
        humanReviewRevision = nil
        humanReviewQualification = nil
        humanReviewNote = ""
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
            ScholiumL10n.string("The current note is unavailable.")
        case .targetChanged:
            ScholiumL10n.string("The note changed; reopen the function.")
        case .targetIdentityChanged:
            ScholiumL10n.string("The note identity changed; reopen the function.")
        case .invalidTargetRole:
            ScholiumL10n.string("This function is not available for this kind of note.")
        case .inactiveTarget:
            ScholiumL10n.string("This function requires an active note.")
        case .missingWorkflow:
            ScholiumL10n.string("The required workflow is not available.")
        case .invalidWorkflow:
            ScholiumL10n.string("The workflow needs repair in Research Guidance.")
        case .missingCapability:
            ScholiumL10n.string("Install and bind a matching Researcher Skill in Settings.")
        case .malformedBinding:
            ScholiumL10n.string("The Researcher Skill binding needs repair in Settings.")
        case .humanReviewOnly:
            ScholiumL10n.string("Review is completed by the researcher in Scholium.")
        }
    }
}
