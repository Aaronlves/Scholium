import ScholiumContracts
import ScholiumResearchRecordsFeature
import SwiftUI

enum ResearchRecordChangePresentation {
    static func modified(
        _ changes: [PortableResearchConfirmedChange]
    ) -> [PortableResearchConfirmedChange] {
        changes.filter { $0.kind == .modified }
    }

    static func created(
        _ changes: [PortableResearchConfirmedChange]
    ) -> [PortableResearchConfirmedChange] {
        changes.filter { $0.kind == .created }
    }
}

struct ResearchRecordChangesSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    let canDirectlyUndo: Bool

    @State private var changeState: ResearchRecordChangeState?
    @State private var isLoading = false
    @State private var isReloading = false
    @State private var isReloadRequired = false
    @State private var errorMessage: String?
    @State private var isPresentingAgentChanges = false
    @State private var isPresentingDirectUndo = false

    private var modifiedChanges: [PortableResearchConfirmedChange] {
        ResearchRecordChangePresentation.modified(record.confirmedChanges)
    }

    private var createdChanges: [PortableResearchConfirmedChange] {
        ResearchRecordChangePresentation.created(record.confirmedChanges)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "CHANGES",
                identifier: "scholium.researchRecord.changesHeader"
            )

            ResearchRecordEvidenceEntry(
                symbol: record.confirmedChanges.isEmpty
                    ? "checkmark.seal"
                    : modifiedChanges.isEmpty
                        ? "doc.badge.plus"
                        : "doc.text.magnifyingglass",
                title: changesTitle,
                body: changesBody,
                identifier: "scholium.researchRecord.changes.status"
            )

            if !record.confirmedChanges.isEmpty {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Button("View Agent Changes…") {
                        isPresentingAgentChanges = true
                    }
                    .accessibilityIdentifier(
                        "scholium.researchRecord.changes.agentChanges"
                    )
                    if canDirectlyUndo, !modifiedChanges.isEmpty {
                        directUndoButton
                    }
                    if isLoading || isReloading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(
                                isLoading ? "Checking source changes" : "Reloading changes"
                            )
                    }
                }
            }

            if let errorMessage {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    Text(errorMessage)
                        .font(ScholiumTypography.interface(.compact))
                        .scholiumForeground(.destructive)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(
                            "scholium.researchRecord.changes.error"
                        )
                    if isReloadRequired {
                        Button("Reload Changes", action: reloadChanges)
                            .disabled(isReloading)
                            .accessibilityIdentifier(
                                "scholium.researchRecord.changes.reload"
                            )
                    }
                }
            }
        }
        .task(id: record.id) {
            guard canDirectlyUndo, !modifiedChanges.isEmpty else { return }
            await loadChangeState()
        }
        .sheet(
            isPresented: $isPresentingAgentChanges
        ) {
            if let presentation = AgentChangesPresentation(
                record: record,
                preferredNoteID: model.contextNoteID,
                id: record.id
            ) {
                AgentChangesView(
                    presentation: presentation,
                    loadComparison: context.comparison,
                    loadChangeState: context.changeState,
                    loadDocument: context.loadDocument,
                    openNote: { noteID, note in
                        context.openNote(noteID, note, nil)
                    }
                )
            }
        }
        .sheet(
            isPresented: $isPresentingDirectUndo
        ) {
            if let changeState {
                ResearchRecordComparisonSheet(
                    record: record,
                    initialChangeState: changeState,
                    canDirectlyUndo: canDirectlyUndo,
                    loadComparison: context.comparison,
                    loadChangeState: context.changeState,
                    undo: context.undoChanges,
                    didUpdateRecord: model.acceptUpdatedRecord
                )
            }
        }
    }

    private var changesTitle: String {
        if record.confirmedChanges.isEmpty {
            return String(localized: "No confirmed source changes")
        }
        if modifiedChanges.isEmpty {
            return String(localized: "\(createdChanges.count) Notes created by Agent")
        }
        if createdChanges.isEmpty {
            return String(localized: "\(modifiedChanges.count) confirmed source changes")
        }
        return String(
            localized: "\(modifiedChanges.count) modified, \(createdChanges.count) created"
        )
    }

    private var changesBody: String {
        if record.confirmedChanges.isEmpty {
            return String(localized: "This result did not change a Note.")
        }
        if modifiedChanges.isEmpty {
            return String(
                localized: "Created Notes have visible provenance and require Settlement, but no fabricated before-source comparison or direct Undo."
            )
        }
        if createdChanges.isEmpty {
            return String(
                localized: "View the exact Agent changes. Reading or comparing them does not mark any Note reviewed."
            )
        }
        return String(
            localized: "Compare modified Notes below. Created Notes retain visible provenance and require Settlement without a fabricated before-source comparison."
        )
    }

    private var directUndoButton: some View {
        Button("Direct Undo…") { isPresentingDirectUndo = true }
            .disabled(
                changeState == nil || isReloading
                    || isReloadRequired
            )
            .accessibilityIdentifier(
                "scholium.researchRecord.changes.directUndo"
            )
    }

    private func loadChangeState() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            changeState = try await context.changeState(record.id)
        } catch is CancellationError {
            return
        } catch {
            changeState = nil
            errorMessage = error.localizedDescription
        }
    }

    private func reloadChanges() {
        guard isReloadRequired, !isReloading else { return }
        isReloading = true
        Task { @MainActor in
            defer { isReloading = false }
            do {
                let updated = try await context.reloadRecord(record.id)
                guard updated.id == record.id else {
                    throw ResearchRecordChangeRecoveryError.recordUnavailable
                }
                let state = try await context.changeState(updated.id)
                model.acceptUpdatedRecord(updated)
                changeState = state
                isReloadRequired = false
                errorMessage = nil
            } catch {
                isReloadRequired = true
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ResearchRecordComparisonDocument: Identifiable {
    enum LoadState {
        case loading
        case loaded(ExactSourceComparison)
        case unavailable(String)
    }

    let id: UUID
    let change: PortableResearchConfirmedChange
    let participant: PortableResearchNoteRevision
    var current: ResearchRecordChangeCurrentState
    var loadState: LoadState = .loading
    var undoStatus: ResearchRecordChangeUndoStatus?
}

struct ResearchRecordDirectUndoGrantState: Equatable {
    let finalizedResultFingerprint: DocumentFingerprint
    private(set) var isValid: Bool

    init(
        finalizedResultFingerprint: DocumentFingerprint,
        isValid: Bool
    ) {
        self.finalizedResultFingerprint = finalizedResultFingerprint
        self.isValid = isValid
    }

    @discardableResult
    mutating func reconcile(
        observedFinalizedResultFingerprint: DocumentFingerprint
    ) -> Bool {
        guard isValid else { return false }
        if observedFinalizedResultFingerprint != finalizedResultFingerprint {
            isValid = false
        }
        return isValid
    }
}

private struct ResearchRecordComparisonSheet: View {
    typealias LoadComparison = @MainActor (UUID, UUID) async throws
        -> ExactSourceComparison
    typealias LoadChangeState = @MainActor (UUID) async throws
        -> ResearchRecordChangeState
    typealias Undo = @MainActor (
        UUID,
        Set<UUID>,
        DocumentFingerprint
    ) async throws -> ResearchRecordChangesUndoResult

    @Environment(\.dismiss) private var dismiss

    let record: PortableResearchRecord
    let initialChangeState: ResearchRecordChangeState
    let loadComparison: LoadComparison
    let loadChangeState: LoadChangeState
    let undo: Undo
    let didUpdateRecord: (PortableResearchRecord) -> Void

    @State private var documents: [ResearchRecordComparisonDocument]
    @State private var expandedDocumentIDs: Set<UUID>
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var directUndoGrant: ResearchRecordDirectUndoGrantState
    @State private var isUndoing = false
    @State private var confirmsUndo = false
    @State private var operationMessage: String?

    init(
        record: PortableResearchRecord,
        initialChangeState: ResearchRecordChangeState,
        canDirectlyUndo: Bool,
        loadComparison: @escaping LoadComparison,
        loadChangeState: @escaping LoadChangeState,
        undo: @escaping Undo,
        didUpdateRecord: @escaping (PortableResearchRecord) -> Void
    ) {
        self.record = record
        self.initialChangeState = initialChangeState
        self.loadComparison = loadComparison
        self.loadChangeState = loadChangeState
        self.undo = undo
        self.didUpdateRecord = didUpdateRecord
        let statesByID = Dictionary(uniqueKeysWithValues:
            initialChangeState.documents.map { ($0.noteID, $0) }
        )
        let mapped: [ResearchRecordComparisonDocument] =
            ResearchRecordChangePresentation.modified(record.confirmedChanges)
            .compactMap { change -> ResearchRecordComparisonDocument? in
            guard let participant = record.participatingNotes.first(where: {
                $0.noteID == change.noteID
            }), let current = statesByID[change.noteID] else { return nil }
            return ResearchRecordComparisonDocument(
                id: change.noteID,
                change: change,
                participant: participant,
                current: current
            )
        }
        _documents = State(initialValue: mapped)
        _expandedDocumentIDs = State(
            initialValue: mapped.first.map { [$0.id] } ?? []
        )
        _directUndoGrant = State(
            initialValue: ResearchRecordDirectUndoGrantState(
                finalizedResultFingerprint:
                    initialChangeState.finalizedResultFingerprint,
                isValid: canDirectlyUndo
            )
        )
    }

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Direct Undo",
            detail: "Review exact document revisions, then select complete documents to restore from Before Agent Work.",
            identifier: "scholium.researchRecord.comparison"
        ) {
            Button("Expand All") {
                expandedDocumentIDs = Set(documents.map(\.id))
            }
            Button("Collapse All") { expandedDocumentIDs.removeAll() }
        } content: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                    ForEach($documents) { $document in
                        comparisonDocument($document)
                    }
                    if let operationMessage {
                        Text(operationMessage)
                            .font(ScholiumTypography.interface(.compact))
                            .scholiumForeground(.destructive)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                "scholium.researchRecord.comparison.message"
                            )
                    }
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
            }
        } footer: {
            comparisonFooter
        }
        .interactiveDismissDisabled(isUndoing)
        .task { await loadAllComparisons() }
        .confirmationDialog(
            undoConfirmationTitle,
            isPresented: $confirmsUndo,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Undo Selected Documents", role: .destructive) {
                undoSelectedDocuments()
            }
        } message: {
            Text("Each selected document will be restored to its exact Before Agent Work revision. Later or missing source revisions will not be overwritten.")
        }
    }

    private func comparisonDocument(
        _ document: Binding<ResearchRecordComparisonDocument>
    ) -> some View {
        let value = document.wrappedValue
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if allowsDirectUndo, value.change.startingRevision != nil {
                    Toggle(
                        "Select \(value.participant.title)",
                        isOn: selectionBinding(for: value)
                    )
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(value.current.status != .agentEndingRevision || isUndoing)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.comparison.select.\(value.id.uuidString)"
                    )
                }
                Button {
                    toggleExpanded(value.id)
                } label: {
                    HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Image(
                            systemName: expandedDocumentIDs.contains(value.id)
                                ? "chevron.down" : "chevron.right"
                        )
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                        .frame(width: ScholiumMetrics.ResearchSheet.Comparison.disclosureIndicatorWidth)
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                            Text(value.participant.title)
                                .font(ScholiumTypography.interface(.rowTitle))
                                .scholiumForeground(.primaryText)
                            Text(value.current.currentRelativePath
                                ?? value.participant.note.relativePath)
                                .font(ScholiumTypography.exact(.small))
                                .scholiumForeground(.secondaryText)
                            Text(documentStatus(value))
                                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                                .scholiumForeground(statusColor(value))
                        }
                        Spacer(minLength: 0)
                        if let revision = value.current.observedRevision {
                            Text(short(revision))
                                .font(ScholiumTypography.exact(.small))
                                .scholiumForeground(.mutedText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(value.participant.title), "
                        + (value.current.currentRelativePath
                            ?? value.participant.note.relativePath)
                )
                .accessibilityValue(
                    "\(expandedDocumentIDs.contains(value.id) ? String(localized: "Expanded") : String(localized: "Collapsed")), \(documentStatus(value))"
                )
                .accessibilityHint(
                    expandedDocumentIDs.contains(value.id)
                        ? "Collapses this document" : "Expands this document"
                )
            }
            .padding(ScholiumGrid.Spacing.nestedContentInset)

            if expandedDocumentIDs.contains(value.id) {
                ScholiumStructuralRule()
                switch value.loadState {
                case .loading:
                    ScholiumContentStateView(
                        "Preparing Exact Comparison…",
                        indicator: .progress
                    )
                    .frame(
                        minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                    )
                case .loaded(let comparison):
                    ExactSourceComparisonView(
                        comparison: comparison,
                        startingLabel: "Before Agent Work",
                        endingLabel: "Agent Revision",
                        startingOnlyLabel: "Before Agent Work only",
                        endingOnlyLabel: "Agent revision only",
                        identifierPrefix:
                            "scholium.researchRecord.comparison.\(value.id.uuidString)"
                    )
                    .padding(ScholiumGrid.Spacing.nestedContentInset)
                case .unavailable(let message):
                    ScholiumContentStateView(
                        "Comparison Unavailable",
                        detail: Text(message),
                        indicator: .symbol("exclamationmark.triangle", role: .attention)
                    )
                    .frame(
                        minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                    )
                }
            }
        }
        .background(ScholiumColorRole.documentBackground.color)
        .clipShape(RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
            .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchRecord.comparison.document.\(value.id.uuidString)"
        )
    }

    private var comparisonFooter: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Return to Record", action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)
                .disabled(isUndoing)
            Spacer(minLength: 0)
            if isUndoing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Undoing selected documents")
            }
            if allowsDirectUndo {
                Button("Undo Selected Documents…") { confirmsUndo = true }
                    .disabled(selectedDocumentIDs.isEmpty || isUndoing)
                    .accessibilityIdentifier(
                        "scholium.researchRecord.comparison.undo"
                    )
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
    }

    private var undoConfirmationTitle: String {
        selectedDocumentIDs.count == 1
            ? String(localized: "Undo the Selected Document?")
            : String(localized: "Undo \(selectedDocumentIDs.count) Selected Documents?")
    }

    private func selectionBinding(
        for document: ResearchRecordComparisonDocument
    ) -> Binding<Bool> {
        Binding(
            get: { selectedDocumentIDs.contains(document.id) },
            set: { selected in
                if selected { selectedDocumentIDs.insert(document.id) }
                else { selectedDocumentIDs.remove(document.id) }
            }
        )
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedDocumentIDs.contains(id) { expandedDocumentIDs.remove(id) }
        else { expandedDocumentIDs.insert(id) }
    }

    private func loadAllComparisons() async {
        for index in documents.indices {
            guard !Task.isCancelled else { return }
            do {
                let comparison = try await loadComparison(record.id, documents[index].id)
                try Task.checkCancellation()
                documents[index].loadState = .loaded(comparison)
            } catch is CancellationError {
                return
            } catch {
                documents[index].loadState = .unavailable(error.localizedDescription)
            }
        }
    }

    private func undoSelectedDocuments() {
        let selected = selectedDocumentIDs
        guard allowsDirectUndo, !selected.isEmpty, !isUndoing else { return }
        isUndoing = true
        operationMessage = nil
        Task { @MainActor in
            defer { isUndoing = false }
            do {
                let result = try await undo(
                    record.id,
                    selected,
                    directUndoGrant.finalizedResultFingerprint
                )
                didUpdateRecord(result.record)
                guard directUndoGrant.reconcile(
                    observedFinalizedResultFingerprint:
                        try result.record.finalizedResultFingerprint()
                ) else {
                    selectedDocumentIDs.removeAll()
                    operationMessage = String(localized: "The finalized Agent result changed. Return to the Result before continuing.")
                    return
                }
                for outcome in result.documents {
                    guard let index = documents.firstIndex(where: {
                        $0.id == outcome.noteID
                    }) else { continue }
                    documents[index].undoStatus = outcome.status
                }
                let allSucceeded = result.documents.count == selected.count
                    && result.documents.allSatisfy {
                        $0.status == .restored
                            || $0.status == .alreadyAtStartingRevision
                    }
                if allSucceeded {
                    dismiss()
                    return
                }
                selectedDocumentIDs.removeAll()
                operationMessage = String(localized: "Some selected documents were not restored. Review each document's current state before trying another action.")
                let state = try await loadChangeState(record.id)
                if !directUndoGrant.reconcile(
                    observedFinalizedResultFingerprint:
                        state.finalizedResultFingerprint
                ) {
                    selectedDocumentIDs.removeAll()
                }
                for current in state.documents {
                    guard let index = documents.firstIndex(where: {
                        $0.id == current.noteID
                    }) else { continue }
                    documents[index].current = current
                }
            } catch {
                operationMessage = error.localizedDescription
                selectedDocumentIDs.removeAll()
                do {
                    let state = try await loadChangeState(record.id)
                    if !directUndoGrant.reconcile(
                        observedFinalizedResultFingerprint:
                            state.finalizedResultFingerprint
                    ) {
                        selectedDocumentIDs.removeAll()
                    }
                    for current in state.documents {
                        guard let index = documents.firstIndex(where: {
                            $0.id == current.noteID
                        }) else { continue }
                        documents[index].current = current
                        documents[index].undoStatus = nil
                    }
                } catch {
                    operationMessage = [
                        operationMessage,
                        error.localizedDescription
                    ].compactMap { $0 }.joined(separator: "\n\n")
                }
            }
        }
    }

    private var allowsDirectUndo: Bool { directUndoGrant.isValid }

    private func documentStatus(
        _ document: ResearchRecordComparisonDocument
    ) -> String {
        if let undoStatus = document.undoStatus {
            switch undoStatus {
            case .restored: return String(localized: "Restored to Before Agent Work")
            case .alreadyAtStartingRevision:
                return String(localized: "Already at Before Agent Work")
            case .conflict: return String(localized: "Changed since Agent revision")
            case .unavailable: return String(localized: "Source unavailable")
            case .commitUncertain: return String(localized: "Restore outcome uncertain")
            }
        }
        return switch document.current.status {
        case .agentEndingRevision:
            document.change.kind == .created
                ? String(localized: "Created Agent revision is current")
                : String(localized: "Agent revision is current")
        case .startingRevision: String(localized: "Before Agent Work is current")
        case .superseded: String(localized: "Changed after Agent work")
        case .unavailable: String(localized: "Source unavailable")
        }
    }

    private func statusColor(
        _ document: ResearchRecordComparisonDocument
    ) -> ScholiumColorRole {
        if document.undoStatus == .commitUncertain
            || document.undoStatus == .conflict
            || document.undoStatus == .unavailable {
            return .destructive
        }
        return switch document.current.status {
        case .agentEndingRevision, .startingRevision:
            ScholiumColorRole.secondaryText
        case .superseded, .unavailable:
            ScholiumColorRole.attention
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "\(fingerprint.sha256.prefix(10))…"
    }
}
